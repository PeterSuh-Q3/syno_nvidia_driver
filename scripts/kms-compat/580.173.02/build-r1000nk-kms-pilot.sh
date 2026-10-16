#!/usr/bin/env bash
# DSM 7.4 r1000nk / NVIDIA 580 Proprietary KMS pilot. Run inside the pinned
# dante90/syno-compiler:7.4 container with this repository mounted at /work.
# Requires the matching provider build already staged under out/ (see below).
set -Eeuo pipefail

root=/work
platform=r1000nk
kernel=/opt/r1000nk/build
provider=$root/out/kms-580-proprietary-kms-remaining-20261016-retry1/r1000nk/provider
released_provider=$root/out/provider-release-inspect-26.10.13/r1000nk-7.4-5.10.55-drm.tgz
reference=$root/out/preserved-build-envs/580-proprietary-kms/epyc7002-canonical-success/artifact/nv-ko-580.173.02-proprietary-epyc7002-51055.tgz
out=${OUT_DIR:-$root/out/r1000nk-kms-abi-fullheaders-v2-20261016}
artifact=$out/nv-ko-580.173.02-r1000nk-51055.tgz

test -s "$provider/Module.symvers"
test -s "$released_provider"
test -s "$reference"
test -s "$root/out/release-assets-nvidia/shared/580/nv-userspace-580.173.02.tgz"
test ! -e "$artifact" || { echo "Refusing to overwrite $artifact" >&2; exit 1; }
mkdir -p "$out" "$out/verify" "$kernel/include/drm" "$kernel/include/uapi/drm"

# NVIDIA conftest and Kbuild must see the same DRM interface as the provider.
# The prior six-header overlay compiled but Oopsed during drm_dev_register.
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
export EXTRA_CFLAGS="-include $provider/drm-provider-symbol-aliases.h -DBPM_VGACON_TEXT_FORCE_NOT_PRESENT -I$provider/backport-include -I$provider/drm-include-focused -I$provider/compat-include -I$provider/i915-include"
export NO_BACKLIGHT=1 NV_DRM_IOSYS_COMPAT=1 JOBS=12 OUT="$out"
export RUN_FILE="$root/run/NVIDIA-Linux-x86_64-580.173.02.run"
bash "$root/build-nvidia.sh" 580.173.02 "$platform" 5.10.55

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
  echo "Candidate introduced DRM imports absent from the physical success reference" >&2
  cat "$out/new-only-drm-imports.txt" >&2
  exit 1
}
if grep -Eq '^(drm_gem_handle_delete|drm_master_get)$' "$out/new-drm-imports.txt"; then
  echo 'Candidate retained the old DRM API path that Oopsed in earlier builds' >&2
  exit 1
fi
sha256sum "$artifact" "$module"
echo 'Static checks passed; physical KMS test is still required for each build.'
