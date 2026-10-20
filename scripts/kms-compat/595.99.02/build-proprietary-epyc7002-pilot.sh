#!/usr/bin/env bash
# Isolated KMS pilot for NVIDIA 595.99.02 Proprietary on EPYC7002/K5.
# Run inside the pinned dante90/syno-compiler:7.4 image with the repository
# mounted at /work. This script never writes to canonical release assets.
set -Eeuo pipefail

readonly ROOT=/work
readonly DRIVER=595.99.02
readonly PLATFORM="${PLATFORM:?set PLATFORM to an allowed K5 platform}"
readonly KERNEL=5.10.55
readonly KERNEL_SHORT=51055
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly RUN_FILE="$ROOT/run/NVIDIA-Linux-x86_64-${DRIVER}.run"
readonly RUN_SHA256=e87477958bf763070549324bd5ad6c948eba6ed210e44005b3eff84940f6e1ec
readonly SHARED_DIR="$ROOT/out/release-assets-nvidia/shared/595"
readonly USERSPACE="$SHARED_DIR/nv-userspace-${DRIVER}.tgz"
readonly GSP="$SHARED_DIR/nv-gsp-${DRIVER}.tgz"
readonly SHIM="$ROOT/scripts/kms-compat/580.173.02/focused3-shim/drm-provider-symbol-aliases.h"
readonly SHIM_SHA256=a04daa03b8059439b2397ef31cd3a2a4e5b1563493b6519a9807669f3ab38ff9
readonly BASELINE="$ROOT/out/release-assets-nvidia/kver5-595-proprietary/nv-ko-${DRIVER}-proprietary-${PLATFORM}-${KERNEL_SHORT}.tgz"
readonly PROVIDER="${PROVIDER:-$ROOT/out/kms-expansion/inputs/${PLATFORM}-7.4-5.10.55-drm.tgz}"
readonly PROVIDER_SOURCE="${PROVIDER_SOURCE:-}"
PROVIDER_SYMVERS="${PROVIDER_SYMVERS:-}"

die() { printf '[595-proprietary-kms-pilot] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[595-proprietary-kms-pilot] %s\n' "$*" >&2; }
sha() { sha256sum "$1" | awk '{print $1}'; }

[[ -n "${OUT_DIR:-}" ]] || die 'OUT_DIR must name a new, unique candidate directory under /work/out/kms-expansion'
case "$OUT_DIR" in
  /work/out/kms-expansion/kver5-595-proprietary/${PLATFORM}-*) ;;
  *) die "unexpected candidate path: $OUT_DIR" ;;
esac
[[ ! -e "$OUT_DIR" ]] || die "candidate path already exists; refusing overwrite: $OUT_DIR"
case "$PLATFORM" in
  epyc7002|epyc7003|geminilakenk|icelaked|r1000nk|v1000nk) ;;
  *) die "unsupported K5 platform: $PLATFORM" ;;
esac

[[ "$(sha "$RUN_FILE")" == "$RUN_SHA256" ]] || die 'NVIDIA .run checksum mismatch'
[[ -s "$USERSPACE" ]] || die "missing shared userspace archive: $USERSPACE"
[[ -s "$GSP" ]] || die "missing shared GSP archive: $GSP"
[[ -s "$BASELINE" ]] || die "missing baseline no-KMS archive: $BASELINE"
[[ -s "$PROVIDER" ]] || die "missing exact-platform DRM provider pack: $PROVIDER"
[[ "$(sha "$SHIM")" == "$SHIM_SHA256" ]] || die 'focused3 compatibility shim checksum mismatch'
[[ "$(tar -xOzf "$USERSPACE" ./VERSION 2>/dev/null | tr -d '\r\n')" == "$DRIVER" ]] || die 'shared userspace version mismatch'
gsp_listing="$(tar -tzf "$GSP")"
grep -Eq '(^|/)gsp_[^/]+\.bin$' <<< "$gsp_listing" || die 'shared GSP archive lacks GSP firmware'
bash "$ROOT/scripts/check-shared-nvidia-layers.sh" || die 'shared-layer invariant failed'

readonly KSRC="/opt/${PLATFORM}/build"
readonly TCBIN="/opt/${PLATFORM}/bin"
if [[ -z "$PROVIDER_SYMVERS" ]]; then
  if [[ -n "$PROVIDER_SOURCE" && -s "$PROVIDER_SOURCE/Module.symvers" ]]; then
    PROVIDER_SYMVERS="$PROVIDER_SOURCE/Module.symvers"
  else
    # geminilakenk's exact DSM kernel tree already exports drm_gem_object_free.
    PROVIDER_SYMVERS="$KSRC/Module.symvers"
  fi
fi
[[ -s "$PROVIDER_SYMVERS" ]] || die "missing exact-platform Module.symvers: $PROVIDER_SYMVERS"
awk '$2 == "drm_gem_object_free" { found = 1 } END { exit !found }' "$PROVIDER_SYMVERS" \
  || die 'exact-platform Module.symvers lacks drm_gem_object_free'
export PATH="$TCBIN:$PATH"
[[ -s "$KSRC/Module.symvers" ]] || die "missing platform Module.symvers: $KSRC"
[[ -x "$TCBIN/x86_64-pc-linux-gnu-gcc" ]] || die 'missing platform compiler'
[[ "$(cat "$KSRC/include/config/kernel.release")" == "$KERNEL+" ]] || die 'unexpected kernel release'

mkdir -p "$OUT_DIR/baseline" "$OUT_DIR/artifacts" "$OUT_DIR/logs" "$OUT_DIR/evidence"
cp -p "$BASELINE" "$OUT_DIR/baseline/"
printf '%s  %s\n' "$(sha "$BASELINE")" "$(basename "$BASELINE")" > "$OUT_DIR/baseline/SHA256SUMS"
log "preserved no-KMS baseline: $(sha "$BASELINE")"

# This uses the EPYC7002 focused3 symbol shim proven with 580 Proprietary, and
# supplies the matching provider DRM headers to 595's own conftest/Kbuild. The
# first attempt showed that the 595 module's conftest did not enable DRM
# (`nvidia-drm.ko` had no modeset parameter) without this provider header view.
# 595 Proprietary also references drm_gem_object_free from nvidia.ko, so the
# exact-platform provider Module.symvers is passed to modpost.
autoconf="$KSRC/include/generated/autoconf.h"
[[ -s "$autoconf" ]] || die "missing generated config: $autoconf"
sed -i -E '/^#(define|undef) CONFIG_DRM_MODULE/d' "$autoconf"
printf '#define CONFIG_DRM_MODULE 1\n' >> "$autoconf"
if [[ -n "$PROVIDER_SOURCE" ]]; then
  [[ -s "$PROVIDER_SOURCE/drm-include/drm/drm_drv.h" ]] || die 'missing exact-platform provider DRM headers'
  [[ -s "$PROVIDER_SOURCE/i915-include/linux/iosys-map.h" ]] || die 'missing exact-platform provider iosys-map header'
  mkdir -p "$KSRC/include/drm" "$KSRC/include/uapi/drm" "$KSRC/include/linux"
  cp -R "$PROVIDER_SOURCE/drm-include/drm/." "$KSRC/include/drm/"
  cp -R "$PROVIDER_SOURCE/drm-include/uapi/drm/." "$KSRC/include/uapi/drm/"
  cp "$PROVIDER_SOURCE/i915-include/linux/iosys-map.h" "$KSRC/include/linux/iosys-map.h"
  for header in dma-fence.h dma-fence-array.h dma-resv.h sync_file.h; do
    [[ -s "$PROVIDER_SOURCE/drm-include/linux/$header" ]] || die "missing provider header $header"
    cp "$PROVIDER_SOURCE/drm-include/linux/$header" "$KSRC/include/linux/$header"
  done
else
  log 'using exact platform kernel DRM headers without a separately compiled provider header overlay'
fi

candidate_raw="$OUT_DIR/artifacts/nv-ko-${DRIVER}-${PLATFORM}-${KERNEL_SHORT}.tgz"
candidate="$OUT_DIR/artifacts/nv-ko-${DRIVER}-proprietary-${PLATFORM}-${KERNEL_SHORT}.tgz"
log "build identity: driver=$DRIVER flavor=proprietary platform=$PLATFORM kernel=$KERNEL jobs=12"
log "compiler image digest: $IMAGE_DIGEST"
log "shim: $(sha "$SHIM")"
EXTRA_CFLAGS="-include $SHIM -DNV_DRM_AVAILABLE -DBPM_VGACON_TEXT_FORCE_NOT_PRESENT${PROVIDER_SOURCE:+ -I$PROVIDER_SOURCE/backport-include -I$PROVIDER_SOURCE/drm-include -I$PROVIDER_SOURCE/i915-include}" \
KBUILD_EXTRA_SYMBOLS="$PROVIDER_SYMVERS" \
NO_BACKLIGHT=1 NV_DRM_IOSYS_COMPAT=1 JOBS=12 OUT="$OUT_DIR/artifacts" \
  bash "$ROOT/build-nvidia.sh" "$DRIVER" "$PLATFORM" "$KERNEL" \
  2>&1 | tee "$OUT_DIR/logs/build.log"
[[ -s "$candidate_raw" ]] || die "build did not produce $candidate_raw"
mv "$candidate_raw" "$candidate"

mkdir -p "$OUT_DIR/evidence/module"
tar -xzf "$candidate" -C "$OUT_DIR/evidence/module"
mkdir -p "$OUT_DIR/evidence/provider"
tar -xzf "$PROVIDER" -C "$OUT_DIR/evidence/provider" --wildcards '*.ko'
for module in nvidia.ko nvidia-uvm.ko nvidia-modeset.ko nvidia-drm.ko nvidia-peermem.ko; do
  [[ -s "$OUT_DIR/evidence/module/$module" ]] || die "missing module: $module"
  vermagic="$(/sbin/modinfo -F vermagic "$OUT_DIR/evidence/module/$module")"
  [[ "$vermagic" == 5.10.55+* ]] || die "wrong vermagic: $module ($vermagic)"
done
[[ "$(cat "$OUT_DIR/evidence/module/VERSION")" == "$DRIVER" ]] || die 'module archive version mismatch'
[[ "$(cat "$OUT_DIR/evidence/module/PLATFORM")" == "$PLATFORM" ]] || die 'module archive platform mismatch'
drm_params="$(/sbin/modinfo -p "$OUT_DIR/evidence/module/nvidia-drm.ko")"
[[ "$drm_params" == *'modeset:'* ]] || die 'nvidia-drm lacks the modeset parameter'
drm_undefined="$(nm -u "$OUT_DIR/evidence/module/nvidia-drm.ko")"
grep -q 'dmabufbkpt_' <<< "$drm_undefined" || die 'focused3 shim alias is absent from nvidia-drm imports'
bash "$ROOT/scripts/check-drm-abi.sh" "$OUT_DIR/evidence/module/nvidia-drm.ko" "$PROVIDER" \
  | tee "$OUT_DIR/evidence/provider-abi-check.txt"

for module in "$OUT_DIR"/evidence/module/nvidia*.ko; do
  nm -u "$module" | awk 'NF {print $NF}' | LC_ALL=C sort -u \
    | awk '/^(drm|__drm|___drm|dmabufbkpt_)/' > "$OUT_DIR/evidence/$(basename "$module").imports"
done
for module in "$OUT_DIR"/evidence/provider/*.ko; do
  nm -g --defined-only "$module" 2>/dev/null \
    | awk 'NF >= 2 && $(NF-1) ~ /^[A-Za-z]$/ {print $NF}'
done | LC_ALL=C sort -u > "$OUT_DIR/evidence/provider.exports"
for imports_file in "$OUT_DIR"/evidence/nvidia*.ko.imports; do
  comm -23 "$imports_file" "$OUT_DIR/evidence/provider.exports" > "$imports_file.missing"
  [[ ! -s "$imports_file.missing" ]] || {
    printf 'Unresolved imports in %s:\n' "$(basename "$imports_file")" >&2
    cat "$imports_file.missing" >&2
    die 'candidate imports symbols absent from the exact-platform provider pack'
  }
done

successful_580="$ROOT/out/release-assets-nvidia/kver5-580-proprietary/nv-ko-580.173.02-proprietary-${PLATFORM}-${KERNEL_SHORT}.tgz"
[[ -s "$successful_580" ]] || die "missing known-success 580 reference: $successful_580"
mkdir -p "$OUT_DIR/evidence/reference-580"
tar -xzf "$successful_580" -C "$OUT_DIR/evidence/reference-580" ./nvidia-drm.ko
nm -u "$OUT_DIR/evidence/module/nvidia-drm.ko" | awk '/drm/ {print $NF}' | sort -u > "$OUT_DIR/evidence/drm-imports-595.txt"
nm -u "$OUT_DIR/evidence/reference-580/nvidia-drm.ko" | awk '/drm/ {print $NF}' | sort -u > "$OUT_DIR/evidence/drm-imports-known-good-580.txt"
comm -13 "$OUT_DIR/evidence/drm-imports-known-good-580.txt" "$OUT_DIR/evidence/drm-imports-595.txt" > "$OUT_DIR/evidence/new-drm-imports-vs-580.txt"

sha "$candidate" > "$OUT_DIR/evidence/candidate.sha256"
sha "$USERSPACE" > "$OUT_DIR/evidence/shared-userspace.sha256"
sha "$GSP" > "$OUT_DIR/evidence/shared-gsp.sha256"
sha "$PROVIDER" > "$OUT_DIR/evidence/provider.sha256"
sha "$PROVIDER_SYMVERS" > "$OUT_DIR/evidence/provider-Module.symvers.sha256"
sha "$RUN_FILE" > "$OUT_DIR/evidence/nvidia-run.sha256"
sha "$SHIM" > "$OUT_DIR/evidence/shim.sha256"
printf '%s\n' \
  "profile=kver5-595-proprietary" \
  "driver=$DRIVER" \
  "flavor=proprietary" \
  "platform=$PLATFORM" \
  "kernel=$KERNEL+" \
  "compiler_image=dante90/syno-compiler:7.4@$IMAGE_DIGEST" \
  "jobs=12" \
  "provider_symvers=$(sha "$PROVIDER_SYMVERS")" \
  "source_commit=$(git -C "$ROOT" rev-parse HEAD)" \
  "runtime_kms_test=pending" \
  "promotion=not-promoted" > "$OUT_DIR/BUILD-RECEIPT.txt"

log "candidate ready: $candidate"
log "candidate sha256: $(sha "$candidate")"
log 'Static ABI checks passed; physical modeset=1 testing is still required.'
