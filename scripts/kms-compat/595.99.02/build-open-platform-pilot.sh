#!/usr/bin/env bash
# Build and statically validate one 595.99.02 Open KMS platform candidate.
# Invoke in the pinned DSM 7.4 compiler image after preparing that platform's
# exact 26.10.15 provider inputs. Never writes canonical release assets.
set -Eeuo pipefail

readonly ROOT=/work
readonly DRIVER=595.99.02
readonly DSM_VERSION=7.4
readonly KERNEL=5.10.55
readonly KERNEL_SHORT=51055
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly SOURCE_COMMIT=a89571ecf197c83c04e16b1f09c516732defe91e
readonly SHIM="$ROOT/scripts/kms-compat/580.173.02/focused3-shim/drm-provider-symbol-aliases.h"
readonly SHIM_SHA256=a04daa03b8059439b2397ef31cd3a2a4e5b1563493b6519a9807669f3ab38ff9
readonly BASELINE_ROOT="$ROOT/out/kms-expansion/kver5-595-open/20261020T100200Z-design-recheck/baseline"
readonly SHARED_ROOT="$ROOT/out/release-assets-nvidia/shared/595"
readonly PROVIDER_ROOT="$ROOT/work/shared-quad-drm-providers"
platform=${1:?usage: build-open-platform-pilot.sh <platform> <unique OUT_DIR>}
OUT_DIR=${2:?unique candidate OUT_DIR required}

case "$platform" in
  epyc7003|geminilakenk|icelaked|r1000nk|v1000nk) ;;
  *) echo "Unsupported remaining K5 platform: $platform" >&2; exit 2 ;;
esac
case "$OUT_DIR" in
  "$ROOT/out/kms-expansion/kver5-595-open/${platform}-"*) ;;
  *) echo "Unexpected candidate path: $OUT_DIR" >&2; exit 2 ;;
esac
[[ ! -e "$OUT_DIR" ]] || { echo "Refusing to overwrite $OUT_DIR" >&2; exit 1; }
[[ "${NV_BUILD_IMAGE_DIGEST:-}" == "$IMAGE_DIGEST" ]] || { echo 'Compiler image digest mismatch' >&2; exit 1; }

readonly KSRC="/opt/$platform/build"
readonly TCBIN="/opt/$platform/bin"
readonly PROVIDER_DIR="$ROOT/out/kms-expansion/inputs/${platform}-26.10.15-provider-build"
readonly PROVIDER="$PROVIDER_ROOT/${platform}-${DSM_VERSION}-${KERNEL}-drm.tgz"
readonly PROVIDER_SYMVERS="$PROVIDER_DIR/provider-Module.symvers"
readonly PROVIDER_SOURCE="$PROVIDER_DIR/source"
readonly USERSPACE="$SHARED_ROOT/nv-userspace-${DRIVER}.tgz"
readonly GSP="$SHARED_ROOT/nv-gsp-${DRIVER}.tgz"
readonly RUN_FILE="$ROOT/run/NVIDIA-Linux-x86_64-${DRIVER}.run"
readonly RUN_SHA256=e87477958bf763070549324bd5ad6c948eba6ed210e44005b3eff84940f6e1ec
readonly BASELINE="$BASELINE_ROOT/nv-ko-${DRIVER}-open-${platform}-${KERNEL_SHORT}.tgz"
die() { printf '[595-open-kms:%s] ERROR: %s\n' "$platform" "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }

[[ -s "$RUN_FILE" && "$(sha "$RUN_FILE")" == "$RUN_SHA256" ]] || die 'NVIDIA .run is missing or checksum mismatch'
[[ -s "$USERSPACE" && -s "$GSP" ]] || die 'canonical shared userspace/GSP archives are missing'
[[ -s "$BASELINE" ]] || die "preserved no-KMS baseline missing: $BASELINE"
[[ -s "$PROVIDER" && -s "$PROVIDER_SYMVERS" ]] || die 'exact platform provider pack or Module.symvers missing'
grep -qx "provider_source_commit=$SOURCE_COMMIT" "$PROVIDER_DIR/PROVIDER-RECEIPT.txt" || die 'provider source commit mismatch'
[[ "$(sha "$PROVIDER")" == "$(sed -n 's/^provider_pack_sha256=//p' "$PROVIDER_DIR/PROVIDER-RECEIPT.txt")" ]] || die 'provider receipt does not match the provider asset'
[[ -s "$PROVIDER_SOURCE/drm-include/drm/drm_drv.h" ]] || die 'matching provider DRM headers missing'
[[ "$(cat "$KSRC/include/config/kernel.release")" == "$KERNEL+" ]] || die 'kernel release mismatch'
[[ -x "$TCBIN/x86_64-pc-linux-gnu-gcc" ]] || die 'platform compiler missing'
bash "$ROOT/scripts/check-shared-nvidia-layers.sh" || die 'shared NVIDIA-layer invariant failed'

mkdir -p "$OUT_DIR/baseline" "$OUT_DIR/artifacts" "$OUT_DIR/logs" "$OUT_DIR/evidence/module"
cp -p "$BASELINE" "$OUT_DIR/baseline/"
printf '%s  %s\n' "$(sha "$BASELINE")" "$(basename "$BASELINE")" > "$OUT_DIR/baseline/SHA256SUMS"
cp "$PROVIDER_DIR/PROVIDER-RECEIPT.txt" "$OUT_DIR/evidence/PROVIDER-RECEIPT.txt"
cp "$PROVIDER_SYMVERS" "$OUT_DIR/evidence/provider-Module.symvers"
cp "$PROVIDER_DIR/provider.config" "$OUT_DIR/evidence/provider.config"
cp "$KSRC/.config" "$OUT_DIR/evidence/synology-kernel.config"
cp "$KSRC/Module.symvers" "$OUT_DIR/evidence/synology-kernel.Module.symvers"

# Each run gets a fresh disposable compiler container, so header/config overlays
# cannot leak between platforms. Open KMS needs both DRM module config symbols.
mkdir -p "$KSRC/include/drm" "$KSRC/include/uapi/drm" "$KSRC/include/linux"
cp -R "$PROVIDER_SOURCE/drm-include/drm/." "$KSRC/include/drm/"
cp -R "$PROVIDER_SOURCE/drm-include/uapi/drm/." "$KSRC/include/uapi/drm/"
cp "$PROVIDER_SOURCE/i915-include/linux/iosys-map.h" "$KSRC/include/linux/iosys-map.h"
for header in dma-fence.h dma-fence-array.h dma-resv.h sync_file.h; do
  [[ -s "$PROVIDER_SOURCE/drm-include/linux/$header" ]] || die "provider header missing: $header"
  cp "$PROVIDER_SOURCE/drm-include/linux/$header" "$KSRC/include/linux/$header"
done
autoconf="$KSRC/include/generated/autoconf.h"
[[ -s "$autoconf" ]] || die 'generated kernel config missing'
sed -i -E '/^#(define|undef) CONFIG_DRM(_MODULE)?([[:space:]]|$)/d; /^#(define|undef) CONFIG_DRM_KMS_HELPER(_MODULE)?([[:space:]]|$)/d' "$autoconf"
printf '%s\n' '#define CONFIG_DRM_MODULE 1' '#define CONFIG_DRM_KMS_HELPER_MODULE 1' >> "$autoconf"

export PATH="$TCBIN:$PATH"
extra_cflags="-DBPM_VGACON_TEXT_FORCE_NOT_PRESENT -I$PROVIDER_SOURCE/backport-include -I$PROVIDER_SOURCE/drm-include -I$PROVIDER_SOURCE/i915-include"
shim_record='provider video/nomodeset.h compatibility; no focused3 DMA-BUF alias shim'
if [[ "$platform" != geminilakenk ]]; then
  [[ -s "$SHIM" && "$(sha "$SHIM")" == "$SHIM_SHA256" ]] || die 'focused3 DMA-BUF alias shim checksum mismatch'
  extra_cflags="-include $SHIM $extra_cflags"
  shim_record="focused3 DMA-BUF alias shim sha256=$SHIM_SHA256"
fi
candidate_raw="$OUT_DIR/artifacts/nv-ko-${DRIVER}-${platform}-${KERNEL_SHORT}.tgz"
candidate="$OUT_DIR/artifacts/nv-ko-${DRIVER}-open-${platform}-${KERNEL_SHORT}.tgz"
NO_BACKLIGHT=1
[[ "$platform" != geminilakenk ]] || NO_BACKLIGHT=0
log="[595-open-kms:$platform] flavor=open kernel_source=kernel-open shim=$shim_record"
printf '%s\n' "$log"
NV_KERNEL_MODULE_TYPE=open KBUILD_EXTRA_SYMBOLS="$PROVIDER_SYMVERS" \
EXTRA_CFLAGS="$extra_cflags" NO_BACKLIGHT="$NO_BACKLIGHT" \
NV_DRM_IOSYS_COMPAT=1 JOBS=12 OUT="$OUT_DIR/artifacts" \
  bash "$ROOT/build-nvidia.sh" "$DRIVER" "$platform" "$KERNEL" \
  2>&1 | tee "$OUT_DIR/logs/build.log"
[[ -s "$candidate_raw" ]] || die 'expected output archive was not produced'
mv "$candidate_raw" "$candidate"

tar -xzf "$candidate" -C "$OUT_DIR/evidence/module"
for module in nvidia.ko nvidia-uvm.ko nvidia-modeset.ko nvidia-drm.ko nvidia-peermem.ko; do
  file="$OUT_DIR/evidence/module/$module"
  [[ -s "$file" ]] || die "candidate missing $module"
  vermagic=$(strings -a "$file" | sed -n 's/^vermagic=//p' | head -1)
  [[ "$vermagic" == "$KERNEL+"* ]] || die "invalid $module vermagic=$vermagic"
  min_size=1000; [[ "$module" != nvidia-drm.ko ]] || min_size=50000
  [[ "$(stat -c %s "$file")" -gt "$min_size" ]] || die "$module appears to be a stub"
done
[[ "$(cat "$OUT_DIR/evidence/module/VERSION")" == "$DRIVER" ]] || die 'module version marker mismatch'
[[ "$(cat "$OUT_DIR/evidence/module/PLATFORM")" == "$platform" ]] || die 'module platform marker mismatch'
strings -a "$OUT_DIR/evidence/module/nvidia-drm.ko" | awk 'index($0, "parm=modeset:") == 1 { found = 1 } END { exit !found }' || die 'nvidia-drm lacks modeset parameter'

tar -xzf "$PROVIDER" -C "$OUT_DIR/evidence" --wildcards '*.ko'
bash "$ROOT/scripts/check-drm-abi.sh" "$OUT_DIR/evidence/module/nvidia-drm.ko" "$PROVIDER" \
  | tee "$OUT_DIR/evidence/provider-abi-check.txt"
nm -u "$OUT_DIR/evidence/module/nvidia-drm.ko" | awk '/drm/ {print $NF}' | LC_ALL=C sort -u > "$OUT_DIR/evidence/drm-imports.txt"
nm -g --defined-only "$PROVIDER_DIR/modules"/*.ko 2>/dev/null \
  | awk 'NF >= 2 && $(NF-1) ~ /^[A-Za-z]$/ {print $NF}' | LC_ALL=C sort -u > "$OUT_DIR/evidence/provider-exports.txt"
comm -23 "$OUT_DIR/evidence/drm-imports.txt" "$OUT_DIR/evidence/provider-exports.txt" > "$OUT_DIR/evidence/unresolved-drm-imports.txt"
[[ ! -s "$OUT_DIR/evidence/unresolved-drm-imports.txt" ]] || {
  cat "$OUT_DIR/evidence/unresolved-drm-imports.txt" >&2
  die 'DRM imports unresolved against the exact-platform provider build'
}
if [[ "$platform" == geminilakenk ]]; then
  ! nm -u "$OUT_DIR/evidence/module/nvidia-drm.ko" | grep -q 'dmabufbkpt_' || die 'Gemini Lake unexpectedly used the focused3 alias shim'
fi

sha "$candidate" > "$OUT_DIR/evidence/candidate.sha256"
sha "$RUN_FILE" > "$OUT_DIR/evidence/nvidia-run.sha256"
sha "$USERSPACE" > "$OUT_DIR/evidence/shared-userspace.sha256"
sha "$GSP" > "$OUT_DIR/evidence/shared-gsp.sha256"
sha "$PROVIDER" > "$OUT_DIR/evidence/provider-pack.sha256"
sha "$PROVIDER_SYMVERS" > "$OUT_DIR/evidence/provider-Module.symvers.sha256"
sha "$KSRC/.config" > "$OUT_DIR/evidence/synology-kernel-config.sha256"
sha "$KSRC/Module.symvers" > "$OUT_DIR/evidence/synology-kernel-Module.symvers.sha256"
{
  printf 'profile=kver5-595-open\ndriver=%s\nflavor=open\nplatform=%s\ndsm=%s\nkernel=%s+\n' "$DRIVER" "$platform" "$DSM_VERSION" "$KERNEL"
  printf 'compiler_image=dante90/syno-compiler:7.4@%s\nprovider_release=mshell-modules-26.10.15\nprovider_source_commit=%s\n' "$IMAGE_DIGEST" "$SOURCE_COMMIT"
  printf 'compatibility_shim=%s\nruntime_modeset_test=pending\npromotion=not-promoted\n' "$shim_record"
} > "$OUT_DIR/BUILD-RECEIPT.txt"
printf '[595-open-kms:%s] static candidate ready: %s (sha256 %s); physical modeset test pending\n' \
  "$platform" "$candidate" "$(sha "$candidate")"
