#!/usr/bin/env bash
# Reproduce the 2026-10-16 focused3 580.173.02 Proprietary KMS diagnostic
# inside the pinned Synology toolchain image. This is not the canonical
# EPYC7002 attempt-6 recipe and does not publish or promote artifacts.
set -Eeuo pipefail

platform="${1:?usage: build-nvidia-kms-focused3-in-container.sh <epyc7002|epyc7003> <output-dir> }"
out_dir="${2:?usage: build-nvidia-kms-focused3-in-container.sh <epyc7002|epyc7003> <output-dir> }"
case "$platform" in
  epyc7002|epyc7003) ;;
  *) echo "unsupported platform: $platform" >&2; exit 2 ;;
esac

readonly compat="/work/scripts/kms-compat/580.173.02/focused3"
readonly ksrc="/opt/${platform}/build"
readonly provider_symvers="$compat/$platform/provider-Module.symvers"
readonly shim="$compat/drm-provider-symbol-aliases.h"

[[ -s "$ksrc/Module.symvers" ]] || { echo "missing target kernel Module.symvers: $ksrc" >&2; exit 10; }
[[ -s "$provider_symvers" ]] || { echo "missing platform provider Module.symvers: $provider_symvers" >&2; exit 11; }
[[ -s "$shim" ]] || { echo "missing symbol-remapping shim: $shim" >&2; exit 12; }

# Overlay only the six headers that were selected by the successful focused3
# diagnostic. Do not overlay the provider's broad DRM include tree: it caused
# API/layout collisions with Synology's headers in earlier attempts.
for header in dma-fence.h dma-fence-array.h dma-resv.h sync_file.h; do
  cp "$compat/include/linux/$header" "$ksrc/include/linux/$header"
done
for header in drm_print.h drm_atomic_helper.h; do
  cp "$compat/include/drm/$header" "$ksrc/include/drm/$header"
done

# The target image's kernel config omits the DRM module define needed for the
# NVIDIA KMS glue. Match the controlled diagnostic: enable it only in this
# disposable container's copy-on-write image layer.
autoconf="$ksrc/include/generated/autoconf.h"
if ! grep -q '^#define CONFIG_DRM_MODULE 1$' "$autoconf"; then
  printf '\n#define CONFIG_DRM_MODULE 1\n' >> "$autoconf"
fi

export NO_BACKLIGHT=1
export JOBS=12
export KBUILD_EXTRA_SYMBOLS="$provider_symvers"
export EXTRA_CFLAGS="-include $shim"
export OUT="$out_dir"

bash /work/build-nvidia.sh 580.173.02 "$platform" 5.10.55

archive="$out_dir/nv-ko-580.173.02-${platform}-51055.tgz"
[[ -s "$archive" ]] || { echo "build did not produce $archive" >&2; exit 13; }
mv "$archive" "$out_dir/nv-ko-580.173.02-proprietary-${platform}-51055.tgz"
sha256sum "$out_dir/nv-ko-580.173.02-proprietary-${platform}-51055.tgz"
