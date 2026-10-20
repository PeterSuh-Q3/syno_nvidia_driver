#!/usr/bin/env bash
# Isolated 595 Proprietary KMS rebuild for Gemini Lake NK / DSM 7.4.
# Run inside the pinned dante90/syno-compiler:7.4 image with the repository
# mounted at /work and the dual-gpu-backports source mounted read-only at
# /provider. This intentionally does NOT apply the focused3 symbol-alias shim.
set -Eeuo pipefail

readonly ROOT=/work
readonly DRIVER=595.99.02
readonly PLATFORM=geminilakenk
readonly KERNEL=5.10.55
readonly KERNEL_SHORT=51055
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly RUN_FILE="$ROOT/run/NVIDIA-Linux-x86_64-${DRIVER}.run"
readonly RUN_SHA256=e87477958bf763070549324bd5ad6c948eba6ed210e44005b3eff84940f6e1ec
readonly SHARED_DIR="$ROOT/out/release-assets-nvidia/shared/595"
readonly USERSPACE="$SHARED_DIR/nv-userspace-${DRIVER}.tgz"
readonly GSP="$SHARED_DIR/nv-gsp-${DRIVER}.tgz"
readonly PROVIDER="$ROOT/work/shared-quad-drm-providers/geminilakenk-7.4-5.10.55-drm.tgz"
readonly PROVIDER_SHA256=542621fbb5d731dedde7fe108e7e058ead28e04252e1a8ba6043583c7f3ac4fc
readonly BASELINE="$ROOT/out/release-assets-nvidia/kver5-595-proprietary/nv-ko-${DRIVER}-proprietary-${PLATFORM}-${KERNEL_SHORT}.tgz"
readonly PROVIDER_SOURCE=/provider
readonly KSRC="/opt/${PLATFORM}/build"
readonly TCBIN="/opt/${PLATFORM}/bin"
PROVIDER_SYMVERS="${PROVIDER_SYMVERS:-}"

die() { printf '[595-geminilakenk-kms-pilot] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[595-geminilakenk-kms-pilot] %s\n' "$*" >&2; }
sha() { sha256sum "$1" | awk '{print $1}'; }

[[ -n "${OUT_DIR:-}" ]] || die 'OUT_DIR must be a new candidate directory under /work/out/kms-expansion/kver5-595-proprietary'
case "$OUT_DIR" in
  /work/out/kms-expansion/kver5-595-proprietary/geminilakenk-*) ;;
  *) die "unexpected candidate path: $OUT_DIR" ;;
esac
[[ ! -e "$OUT_DIR" ]] || die "candidate path already exists; refusing overwrite: $OUT_DIR"

[[ "$(sha "$RUN_FILE")" == "$RUN_SHA256" ]] || die 'NVIDIA .run checksum mismatch'
[[ "$(sha "$PROVIDER")" == "$PROVIDER_SHA256" ]] || die 'Gemini Lake provider pack is not the pinned 26.10.15 asset'
[[ -s "$USERSPACE" && -s "$GSP" ]] || die 'canonical shared userspace/GSP input is missing'
[[ -s "$BASELINE" ]] || die "missing no-KMS baseline: $BASELINE"
[[ -s "$PROVIDER_SOURCE/drm-include/drm/drm_drv.h" ]] || die 'provider DRM headers are missing'
[[ -s "$PROVIDER_SOURCE/i915-include/linux/iosys-map.h" ]] || die 'provider i915 iosys-map header is missing'
[[ -s "$PROVIDER_SOURCE/backport-include/video/nomodeset.h" ]] || die 'specific video/nomodeset compatibility header is missing'
[[ "$(cat "$KSRC/include/config/kernel.release")" == "$KERNEL+" ]] || die 'unexpected DSM kernel release'
[[ -s "$KSRC/Module.symvers" && -s "$KSRC/.config" ]] || die 'exact Gemini kernel config/symbol table is missing'
[[ -n "$PROVIDER_SYMVERS" && -s "$PROVIDER_SYMVERS" ]] || die 'Gemini provider Module.symvers must be built from the matching provider source/config'
awk '$2 == "drm_connector_attach_hdr_output_metadata_property" { found = 1 } END { exit !found }' "$PROVIDER_SYMVERS" \
  || die 'Gemini provider Module.symvers lacks expected DRM exports'
[[ -x "$TCBIN/x86_64-pc-linux-gnu-gcc" ]] || die 'Gemini Lake DSM 7.4 compiler is missing'
[[ "$(tar -xOzf "$USERSPACE" ./VERSION 2>/dev/null | tr -d '\r\n')" == "$DRIVER" ]] || die 'shared userspace version mismatch'
gsp_listing="$(tar -tzf "$GSP")"
grep -Eq '(^|/)gsp_[^/]+\.bin$' <<< "$gsp_listing" || die 'shared GSP archive lacks firmware'
bash "$ROOT/scripts/check-shared-nvidia-layers.sh" || die 'shared-layer invariant failed'

readonly SUCCESSFUL_580="$ROOT/out/release-assets-nvidia/kver5-580-proprietary/nv-ko-580.173.02-proprietary-${PLATFORM}-${KERNEL_SHORT}.tgz"
[[ -s "$SUCCESSFUL_580" ]] || die 'known-success 580 Gemini reference is missing'

mkdir -p "$OUT_DIR/baseline" "$OUT_DIR/artifacts" "$OUT_DIR/logs" "$OUT_DIR/evidence/module" "$OUT_DIR/evidence/provider" "$OUT_DIR/evidence/reference-580"
cp -p "$BASELINE" "$OUT_DIR/baseline/"
cp -p "$PROVIDER_SYMVERS" "$OUT_DIR/evidence/provider-Module.symvers"
printf '%s  %s\n' "$(sha "$BASELINE")" "$(basename "$BASELINE")" > "$OUT_DIR/baseline/SHA256SUMS"

# Provider headers are build inputs, not a compatibility shim. Overlay only the
# DRM/i915 headers used by NVIDIA conftest/Kbuild into this disposable Docker
# container's exact Gemini K5 kernel tree. Do not inject module-lifecycle
# backport wrappers or the focused3 dmabufbkpt_* symbol aliases.
mkdir -p "$KSRC/include/drm" "$KSRC/include/uapi/drm" "$KSRC/include/linux"
cp -R "$PROVIDER_SOURCE/drm-include/drm/." "$KSRC/include/drm/"
cp -R "$PROVIDER_SOURCE/drm-include/uapi/drm/." "$KSRC/include/uapi/drm/"
cp "$PROVIDER_SOURCE/i915-include/linux/iosys-map.h" "$KSRC/include/linux/iosys-map.h"
for header in dma-fence.h dma-fence-array.h dma-resv.h sync_file.h; do
  [[ -s "$PROVIDER_SOURCE/drm-include/linux/$header" ]] || die "provider header missing: $header"
  cp "$PROVIDER_SOURCE/drm-include/linux/$header" "$KSRC/include/linux/$header"
done
autoconf="$KSRC/include/generated/autoconf.h"
[[ -s "$autoconf" ]] || die 'generated Gemini kernel config is missing'
sed -i -E '/^#(define|undef) CONFIG_DRM_MODULE/d' "$autoconf"
printf '#define CONFIG_DRM_MODULE 1\n' >> "$autoconf"

candidate_raw="$OUT_DIR/artifacts/nv-ko-${DRIVER}-${PLATFORM}-${KERNEL_SHORT}.tgz"
candidate="$OUT_DIR/artifacts/nv-ko-${DRIVER}-proprietary-${PLATFORM}-${KERNEL_SHORT}.tgz"
export PATH="$TCBIN:$PATH"
export KBUILD_EXTRA_SYMBOLS="$PROVIDER_SYMVERS"
export EXTRA_CFLAGS="-DNV_DRM_AVAILABLE -DBPM_VGACON_TEXT_FORCE_NOT_PRESENT -I$PROVIDER_SOURCE/backport-include -I$PROVIDER_SOURCE/drm-include -I$PROVIDER_SOURCE/i915-include"
export NV_DRM_IOSYS_COMPAT=1 NO_BACKLIGHT=0 JOBS=12 OUT="$OUT_DIR/artifacts"
export RUN_FILE
log "build: driver=$DRIVER flavor=proprietary platform=$PLATFORM DSM=7.4 kernel=$KERNEL"
log "provider pack sha256=$PROVIDER_SHA256; provider header source commit=$(git -C "$PROVIDER_SOURCE" rev-parse HEAD)"
log 'compatibility shim: provider-header overlay + targeted iosys/nomodeset compatibility only; no focused3 alias shim'
bash "$ROOT/build-nvidia.sh" "$DRIVER" "$PLATFORM" "$KERNEL" 2>&1 | tee "$OUT_DIR/logs/build.log"
[[ -s "$candidate_raw" ]] || die "build did not produce $candidate_raw"
mv "$candidate_raw" "$candidate"

tar -xzf "$candidate" -C "$OUT_DIR/evidence/module"
tar -xzf "$PROVIDER" -C "$OUT_DIR/evidence/provider" --wildcards '*.ko'
tar -xzf "$SUCCESSFUL_580" -C "$OUT_DIR/evidence/reference-580" ./nvidia-drm.ko
for module in nvidia.ko nvidia-uvm.ko nvidia-modeset.ko nvidia-drm.ko nvidia-peermem.ko; do
  [[ -s "$OUT_DIR/evidence/module/$module" ]] || die "candidate missing module: $module"
  vermagic="$(strings -a "$OUT_DIR/evidence/module/$module" | sed -n 's/^vermagic=//p' | head -1)"
  [[ "$vermagic" == 5.10.55+* ]] || die "wrong vermagic: $module ($vermagic)"
done
[[ "$(cat "$OUT_DIR/evidence/module/VERSION")" == "$DRIVER" ]] || die 'module archive version mismatch'
[[ "$(cat "$OUT_DIR/evidence/module/PLATFORM")" == "$PLATFORM" ]] || die 'module archive platform mismatch'
drm_metadata="$(strings -a "$OUT_DIR/evidence/module/nvidia-drm.ko")"
grep -q '^parm=modeset:' <<< "$drm_metadata" || die 'nvidia-drm lacks the modeset parameter'
drm_undefined="$(nm -u "$OUT_DIR/evidence/module/nvidia-drm.ko")"
grep -q 'dmabufbkpt_' <<< "$drm_undefined" && die 'unexpected focused3 alias shim import detected'

bash "$ROOT/scripts/check-drm-abi.sh" "$OUT_DIR/evidence/module/nvidia-drm.ko" "$PROVIDER" | tee "$OUT_DIR/evidence/provider-abi-check.txt"
nm -u "$OUT_DIR/evidence/module/nvidia-drm.ko" | awk '/drm/ {print $NF}' | LC_ALL=C sort -u > "$OUT_DIR/evidence/drm-imports-595.txt"
nm -u "$OUT_DIR/evidence/reference-580/nvidia-drm.ko" | awk '/drm/ {print $NF}' | LC_ALL=C sort -u > "$OUT_DIR/evidence/drm-imports-known-good-580.txt"
comm -13 "$OUT_DIR/evidence/drm-imports-known-good-580.txt" "$OUT_DIR/evidence/drm-imports-595.txt" > "$OUT_DIR/evidence/new-drm-imports-vs-580.txt"

sha "$candidate" > "$OUT_DIR/evidence/candidate.sha256"
sha "$PROVIDER" > "$OUT_DIR/evidence/provider.sha256"
sha "$PROVIDER_SYMVERS" > "$OUT_DIR/evidence/provider-Module.symvers.sha256"
sha "$KSRC/.config" > "$OUT_DIR/evidence/gemini-kernel-config.sha256"
sha "$KSRC/Module.symvers" > "$OUT_DIR/evidence/gemini-kernel-Module.symvers.sha256"
sha "$USERSPACE" > "$OUT_DIR/evidence/shared-userspace.sha256"
sha "$GSP" > "$OUT_DIR/evidence/shared-gsp.sha256"
sha "$RUN_FILE" > "$OUT_DIR/evidence/nvidia-run.sha256"
printf '%s\n' \
  "profile=kver5-595-proprietary" \
  "driver=$DRIVER" \
  "flavor=proprietary" \
  "platform=$PLATFORM" \
  "kernel=$KERNEL+" \
  "provider_pack_sha256=$PROVIDER_SHA256" \
  "provider_header_source_commit=$(git -C "$PROVIDER_SOURCE" rev-parse HEAD)" \
  "provider_Module.symvers=$(sha "$PROVIDER_SYMVERS")" \
  "target_kernel_Module.symvers=$(sha "$KSRC/Module.symvers")" \
  "compiler_image=dante90/syno-compiler:7.4@$IMAGE_DIGEST" \
  "compatibility_shim=none (provider header overlay and targeted API compatibility only)" \
  "runtime_kms_test=pending" \
  "promotion=not-promoted" > "$OUT_DIR/BUILD-RECEIPT.txt"
log "candidate ready: $candidate"
log "candidate sha256: $(sha "$candidate")"
log 'Static provider-export and metadata checks passed; physical modeset=1 runtime validation remains required.'
