#!/usr/bin/env bash
#
# build-nvidia.sh - Build the 2-layer NVIDIA package for a DSM kver5 platform.
#
# Runs INSIDE the `dante90/syno-compiler:<DSM>` container (the same image
# mshell-modules uses), where the Synology kernel tree + toolchain live at
#   /opt/<platform>/build/   (Module.symvers, System.map, headers)
# so vermagic + CONFIG_MODVERSIONS symbol CRCs come out matching the DSM kernel.
#
# This project is kept SEPARATE from mshell-modules on purpose (own path/repo).
# It only borrows the compiler image; it does not touch the module-pack tree.
#
# Only NVIDIA's OPEN kernel-interface glue is (re)compiled and linked against the
# closed nv-kernel blob. No vGPU/license daemon is produced - no-auth
# (physical / passthrough) target only.
#
# LAYERS (see README.md for why the split):
#   1) kernel   : nv-ko-<ver>-<platform>-<kvershort>.tgz   platform-specific, ~MB
#   2) userspace: nv-userspace-<ver>.tgz                   platform-INDEPENDENT,
#                 built once per driver version, shared by every kver5 platform.
#
# Usage (inside the container):
#   build-nvidia.sh <driver_ver> <platform> [<kver>]
#     e.g. build-nvidia.sh 535.183.06 epyc7002 5.10.55
#
# Env overrides:
#   RUN_FILE : NVIDIA-Linux-x86_64-<ver>.run   (default: ./run/<that name>)
#   KSRC     : kernel build tree (default: /opt/<platform>/build)
#   OUT      : output dir (default: ./out)
#   CC / LD / CROSS_COMPILE : toolchain (default: container's, x86_64 native)
#
set -euo pipefail

DRV="${1:?driver_ver e.g. 535.183.06}"
PLATFORM="${2:?platform e.g. epyc7002}"
KVER="${3:-5.10.55}"
KVERSHORT="$(echo "$KVER" | tr -d '.')"        # 5.10.55 -> 51055
ARCH=x86_64
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-$HERE/out}"

log(){ echo "[build-nvidia] $*" >&2; }
die(){ log "ERROR: $*"; exit 1; }

# --- kernel tree (container-internal, matches mshell-modules convention) ------
KSRC="${KSRC:-/opt/${PLATFORM}/build}"
[ -f "$KSRC/Module.symvers" ] || die "no Module.symvers at $KSRC - run inside dante90/syno-compiler:<DSM> (see run-on-vm.sh)"
log "kernel tree: $KSRC"

# --- toolchain (MUST match the kernel's compiler, else conftest silently fails
#     and NVIDIA falls back to legacy code paths - e.g. the removed __flush_tlb).
#     The Syno x86_64 toolchain lives at /opt/<platform>/bin and is NOT in PATH
#     by default; put it there and pin CC/CROSS_COMPILE to it. ------------------
TCBIN="/opt/${PLATFORM}/bin"
if [ -d "$TCBIN" ] && [ -x "$TCBIN/x86_64-pc-linux-gnu-gcc" ]; then
  export PATH="$TCBIN:$PATH"
  : "${CROSS_COMPILE:=x86_64-pc-linux-gnu-}"
fi
: "${CC:=${CROSS_COMPILE:-}gcc}"
: "${LD:=${CROSS_COMPILE:-}ld}"
log "toolchain: CC=$CC ($($CC --version 2>/dev/null | head -1))"

# --- locate the .run ----------------------------------------------------------
RUN_FILE="${RUN_FILE:-$HERE/run/NVIDIA-Linux-${ARCH}-${DRV}.run}"
[ -f "$RUN_FILE" ] || die "NVIDIA .run not found: $RUN_FILE"

command -v make >/dev/null || die "make missing in container"
mkdir -p "$OUT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

log "extracting $(basename "$RUN_FILE")"
sh "$RUN_FILE" --extract-only --target "$WORK/nv" >/dev/null
SRC="$WORK/nv"

# --- Synology-kernel compat patches ------------------------------------------
# Synology's kernels are built with `# CONFIG_X86_PAT is not set`, which forces
# NVIDIA's builtin-PAT path (nv-pat.c, guarded by NV_ENABLE_BUILTIN_PAT_SUPPORT)
# instead of the kernel's own PAT support. That path uses two x86 primitives the
# Syno 5.10 kernel does not make available to modules:
#
#   1) __flush_tlb()  - removed from the x86 TLB API in 5.10. Replace it with the
#      local-TLB-flush inline it used to expand to - native_write_cr3(
#      __native_read_cr3()) - which reloads CR3. Both are static inlines (no
#      exported symbol), so unlike __flush_tlb_all() (EXPORT_SYMBOL_GPL, which
#      modpost rejects for the proprietary nvidia.ko) this links cleanly.
#
#   2) __write_cr4() - resolves to native_write_cr4(), a real (non-inline)
#      function NOT exported to modules -> "native_write_cr4 undefined" at
#      modpost. Emit the CR4 write as raw inline asm (what native_write_cr4 does
#      internally) so no symbol is referenced.
#
# Both are no-ops on kernels with CONFIG_X86_PAT (the path is not compiled).
#
# The call sites MOVE between driver branches: <=550 hid the CR4 write behind a
# NV_WRITE_CR4 macro in common/inc/nv-linux.h, while 580 calls __write_cr4()
# directly in nvidia/nv-pat.c with two different argument forms. So search the
# tree instead of hardcoding paths, rewrite every call site whatever its
# argument, and - crucially - DIE if any problematic call survives. A silently
# skipped patch previously surfaced only as an unrelated-looking
# "native_write_cr4 undefined" modpost error hundreds of lines later.
npatch=0
for f in $(grep -rl '__flush_tlb()' "$SRC/kernel" 2>/dev/null || true); do
  sed -i 's/__flush_tlb()/native_write_cr3(__native_read_cr3())/g' "$f"
  log "compat: ${f#$SRC/} __flush_tlb() -> native_write_cr3(__native_read_cr3())"
  npatch=$((npatch+1))
done
for f in $(grep -rl '__write_cr4(' "$SRC/kernel" 2>/dev/null || true); do
  sed -i 's/__write_cr4(\([^;]*\));/asm volatile("mov %0,%%cr4" :: "r"((unsigned long)(\1)) : "memory");/g' "$f"
  log "compat: ${f#$SRC/} __write_cr4() -> inline asm (native_write_cr4 not exported)"
  npatch=$((npatch+1))
done
leftover="$(grep -rn '__flush_tlb()\|__write_cr4(' "$SRC/kernel" 2>/dev/null || true)"
[ -z "$leftover" ] || die "Syno compat patch did not fully apply. These call sites survive and WILL fail at modpost:
$leftover
This driver branch moved or reshaped them - update the compat block in build-nvidia.sh."
log "compat: patched $npatch file(s); no unpatched __flush_tlb/__write_cr4 remain"

# =============================================================================
# LAYER 1 - kernel modules (.ko), platform-specific
# =============================================================================
log "compiling glue against $KVER / $PLATFORM (NVIDIA kbuild drives conftest.sh)"
make -C "$SRC/kernel" modules \
     SYSSRC="$KSRC" SYSOUT="$KSRC" \
     ARCH="$ARCH" \
     ${CROSS_COMPILE:+CROSS_COMPILE="$CROSS_COMPILE"} \
     ${CC:+CC="$CC"} ${LD:+LD="$LD"} \
     KERNEL_UNAME="$KVER" \
     -j"$(nproc)"

KO_STAGE="$WORK/ko"; mkdir -p "$KO_STAGE"
STRIP="${CROSS_COMPILE:-}strip"
# vermagic/symtab checks: the .ko are native x86_64, so use plain kmod/binutils.
# The CROSS_COMPILE-prefixed modinfo/nm often don't exist (toolchain ships gcc/ld/
# nm/strip but not modinfo) -> would emit false "vermagic ?" / "no export" WARNs.
command -v modinfo >/dev/null 2>&1 && MODINFO="modinfo" || MODINFO="${CROSS_COMPILE:-}modinfo"
command -v nm      >/dev/null 2>&1 && NM="nm"           || NM="${CROSS_COMPILE:-}nm"
found=0
for m in nvidia nvidia-uvm nvidia-modeset nvidia-drm nvidia-peermem; do
  f="$SRC/kernel/$m.ko"; [ -f "$f" ] || continue
  "$STRIP" --strip-debug "$f" -o "$KO_STAGE/$m.ko" 2>/dev/null || cp "$f" "$KO_STAGE/$m.ko"
  vm="$("$MODINFO" -F vermagic "$KO_STAGE/$m.ko" 2>/dev/null || echo '?')"
  log "  $m.ko  vermagic: $vm"
  found=$((found+1))
done
[ "$found" -ge 3 ] || die "expected >=3 .ko, got $found - build failed"

# self-check: nvidia.ko must EXPORT the uvm/modeset interface, else the
# dependent modules get 'Unknown symbol' at load time (the issue-#77 failure).
# EXPORT_SYMBOL emits __ksymtab_<name>; that (not just a 'T' definition) is what
# lets nvidia-uvm resolve the interface at load. Check for the ksymtab entries.
#
# Use `grep -c` (which consumes all of nm's output), NEVER `grep -q`: under
# `set -o pipefail` grep -q exits at the first match, nm then dies of SIGPIPE,
# and the whole pipeline reports failure - which made this check emit a false
# "does not export" WARN on every build with a large nvidia.ko (580 = 113MB),
# even though the symbols were present. Verified: grep -c finds 76, grep -q
# path reports failure.
if ! "$NM" --version >/dev/null 2>&1; then
  log "WARN: '$NM' unavailable - nvUvmInterface export self-check SKIPPED (not a build failure)"
else
  n=$("$NM" "$KO_STAGE/nvidia.ko" 2>/dev/null | grep -c '__ksymtab_nvUvmInterface' || true)
  [ "${n:-0}" -ge 1 ] || die "nvidia.ko exports no nvUvmInterface* symbols - nvidia-uvm would fail with 'Unknown symbol' at load (issue #77 class) and CUDA would be broken"
  log "ok: nvidia.ko exports $n nvUvmInterface* symbols (uvm will resolve)"
fi

echo "$DRV" > "$KO_STAGE/VERSION"; echo "$KVER" > "$KO_STAGE/KVER"
KO_TGZ="$OUT/nv-ko-${DRV}-${PLATFORM}-${KVERSHORT}.tgz"
tar -C "$KO_STAGE" -czf "$KO_TGZ" .
KO_SHA="$(sha256sum "$KO_TGZ" | cut -d' ' -f1)"
log "kernel layer -> $KO_TGZ  ($KO_SHA)"

# =============================================================================
# LAYER 2 - userspace, platform-independent (build once per driver version)
# =============================================================================
US_TGZ="$OUT/nv-userspace-${DRV}.tgz"
if [ -f "$US_TGZ" ]; then
  log "userspace layer exists, reusing: $US_TGZ"
else
  log "assembling userspace layer for $DRV"
  US="$WORK/us"; mkdir -p "$US/bin" "$US/lib"
  for b in nvidia-smi nvidia-persistenced nvidia-modprobe nvidia-debugdump; do
    [ -f "$SRC/$b" ] && cp -a "$SRC/$b" "$US/bin/" || log "  (skip missing $b)"
  done
  for so in "$SRC"/*.so."$DRV" "$SRC"/lib*.so.*; do
    [ -f "$so" ] || continue
    case "$(basename "$so")" in *vgpu*) continue ;; esac   # drop vGPU/license userspace
    cp -a "$so" "$US/lib/"
  done
  echo "$DRV" > "$US/VERSION"
  tar -C "$US" -czf "$US_TGZ" .
fi
US_SHA="$(sha256sum "$US_TGZ" | cut -d' ' -f1)"
log "userspace layer -> $US_TGZ  ($US_SHA)"

# --- emit index fragment ------------------------------------------------------
cat <<JSON

=== paste under .["$PLATFORM"] in src/nvidia-index.json ===
    "$DRV": {
      "ko":        { "file": "$(basename "$KO_TGZ")", "sha256": "$KO_SHA" },
      "userspace": { "file": "$(basename "$US_TGZ")", "sha256": "$US_SHA", "version": "$DRV" }
    }
=== then upload both .tgz to the GitHub Release tagged 'nvidia' ===
JSON
log "done."
