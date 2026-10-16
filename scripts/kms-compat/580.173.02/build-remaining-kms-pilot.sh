#!/usr/bin/env bash
# Rebuild one unverified DSM 7.4 NVIDIA 580 Proprietary KMS platform using
# the full-header r1000nk success recipe. Run in the pinned compiler image.
set -Eeuo pipefail

root=/work
platform=${1:?platform required: epyc7003, icelaked, or v1000nk}
case "$platform" in
  epyc7003) provider=$root/out/nvidia-kms-provider-builds-580-proprietary-20261016/epyc7003-da5 ;;
  icelaked|v1000nk) provider=$root/out/kms-580-proprietary-kms-remaining-20261016-retry1/$platform/provider ;;
  *) echo "Unsupported pilot platform: $platform" >&2; exit 2 ;;
esac
kernel=/opt/$platform/build
released_provider=$root/out/provider-release-inspect-26.10.13/$platform-7.4-5.10.55-drm.tgz
reference=$root/out/release-assets-nvidia/kver5-580-proprietary/nv-ko-580.173.02-proprietary-epyc7002-51055.tgz
shim=$root/out/drm-provider-symbol-aliases.h
out=${OUT_DIR:-$root/out/kms-580-proprietary-fullheaders-20261016/$platform}
artifact=$out/nv-ko-580.173.02-proprietary-$platform-51055.tgz

for input in "$provider/Module.symvers" "$provider/i915-include/linux/iosys-map.h" \
             "$provider/drm-include-focused/drm/drm_drv.h" \
             "$provider/drm-include-focused/uapi/drm/drm.h" \
             "$released_provider" "$reference" "$shim" \
             "$root/out/release-assets-nvidia/shared/580/nv-userspace-580.173.02.tgz"; do
  test -s "$input" || { echo "Missing build input: $input" >&2; exit 1; }
done
echo 'a04daa03b8059439b2397ef31cd3a2a4e5b1563493b6519a9807669f3ab38ff9  '"$shim" | sha256sum -c -
test ! -e "$artifact" || { echo "Refusing to overwrite $artifact" >&2; exit 1; }
mkdir -p "$out" "$out/verify" "$kernel/include/drm" "$kernel/include/uapi/drm"

# NVIDIA conftest and Kbuild must see the exact same provider DRM API.
cp -R "$provider/drm-include-focused/drm/." "$kernel/include/drm/"
cp -R "$provider/drm-include-focused/uapi/drm/." "$kernel/include/uapi/drm/"
cp "$provider/i915-include/linux/iosys-map.h" "$kernel/include/linux/iosys-map.h"
for header in dma-fence.h dma-fence-array.h dma-resv.h sync_file.h; do
  cp "$provider/drm-include-focused/linux/$header" "$kernel/include/linux/$header"
done
autoconf=$kernel/include/generated/autoconf.h
sed -i -E '/^#(define|undef) CONFIG_DRM_MODULE/d' "$autoconf"
echo '#define CONFIG_DRM_MODULE 1' >> "$autoconf"

export KBUILD_EXTRA_SYMBOLS="$provider/Module.symvers"
export EXTRA_CFLAGS="-include $shim -DBPM_VGACON_TEXT_FORCE_NOT_PRESENT -I$provider/backport-include -I$provider/drm-include-focused -I$provider/compat-include -I$provider/i915-include"
export NO_BACKLIGHT=1 NV_DRM_IOSYS_COMPAT=1 JOBS=12 OUT="$out"
export RUN_FILE="$root/run/NVIDIA-Linux-x86_64-580.173.02.run"
bash "$root/build-nvidia.sh" 580.173.02 "$platform" 5.10.55

generated=$out/nv-ko-580.173.02-$platform-51055.tgz
test -s "$generated"
mv "$generated" "$artifact"
tar -xzf "$artifact" -C "$out/verify"
module=$out/verify/nvidia-drm.ko
test "$(stat -c %s "$module")" -gt 11648
modinfo -F vermagic "$module" | grep -q '^5\.10\.55'
modinfo -p "$module" | grep -q '^modeset:'
bash "$root/scripts/check-drm-abi.sh" "$module" "$released_provider"

mkdir -p "$out/reference"
tar -xzf "$reference" -C "$out/reference" ./nvidia-drm.ko
nm -u "$module" | awk '/drm/ {print $NF}' | sort -u > "$out/new-drm-imports.txt"
nm -u "$out/reference/nvidia-drm.ko" | awk '/drm/ {print $NF}' | sort -u > "$out/good-drm-imports.txt"
comm -13 "$out/good-drm-imports.txt" "$out/new-drm-imports.txt" > "$out/new-only-drm-imports.txt"
test ! -s "$out/new-only-drm-imports.txt" || {
  echo "New DRM imports absent from the EPYC7002 physical-success reference:" >&2
  cat "$out/new-only-drm-imports.txt" >&2
  exit 1
}
if grep -Eq '^(drm_gem_handle_delete|drm_master_get)$' "$out/new-drm-imports.txt"; then
  echo 'Old DRM API path detected; rejecting candidate' >&2
  exit 1
fi
sha256sum "$artifact" "$module"
echo 'Static checks passed; device KMS testing is still required.'
