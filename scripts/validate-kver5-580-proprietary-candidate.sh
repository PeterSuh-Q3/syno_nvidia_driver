#!/usr/bin/env bash
# Runs inside the pinned dante90/syno-compiler image. Validate a complete
# candidate directory; this script is read-only and fails closed.
set -Eeuo pipefail

readonly DRIVER="580.173.02"
readonly KERNEL_VERSION="5.10.55"
readonly PLATFORMS=(epyc7002 epyc7003 geminilakenk icelaked r1000nk v1000nk)
ARTIFACT_DIR="${1:?pass the candidate artifact directory}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED_DIR="$ROOT/out/release-assets-nvidia/shared/${DRIVER%%.*}"
userspace="${2:-$SHARED_DIR/nv-userspace-${DRIVER}.tgz}"
gsp="${3:-$SHARED_DIR/nv-gsp-${DRIVER}.tgz}"

die() { printf '[validate-580-proprietary] ERROR: %s\n' "$*" >&2; exit 1; }
[[ -d "$ARTIFACT_DIR" ]] || die "not a directory: $ARTIFACT_DIR"
[[ -x /sbin/modinfo ]] || die '/sbin/modinfo is unavailable in the pinned compiler image'
command -v nm >/dev/null 2>&1 || die 'nm is unavailable in the pinned compiler image'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for platform in "${PLATFORMS[@]}"; do
  archive="$ARTIFACT_DIR/nv-ko-${DRIVER}-proprietary-${platform}-51055.tgz"
  [[ -s "$archive" ]] || die "missing archive: $archive"
  dest="$tmp/$platform"
  mkdir -p "$dest"
  tar -xzf "$archive" -C "$dest" || die "$platform archive is corrupt"
  [[ "$(cat "$dest/VERSION" 2>/dev/null || true)" == "$DRIVER" ]] || die "$platform VERSION mismatch"
  [[ "$(cat "$dest/KVER" 2>/dev/null || true)" == "$KERNEL_VERSION" ]] || die "$platform KVER mismatch"
  [[ "$(cat "$dest/PLATFORM" 2>/dev/null || true)" == "$platform" ]] || die "$platform metadata mismatch"

  for module in nvidia nvidia-uvm nvidia-modeset nvidia-drm nvidia-peermem; do
    [[ -s "$dest/$module.ko" ]] || die "$platform is missing $module.ko"
    vermagic="$(/sbin/modinfo -F vermagic "$dest/$module.ko" 2>/dev/null || true)"
    [[ "$vermagic" == "$KERNEL_VERSION"* ]] || die "$platform $module vermagic mismatch: ${vermagic:-unavailable}"
  done

  license="$(/sbin/modinfo -F license "$dest/nvidia.ko" 2>/dev/null || true)"
  [[ "$license" == NVIDIA ]] || die "$platform is not Proprietary flavor (nvidia.ko license=${license:-unavailable})"
  /sbin/modinfo -p "$dest/nvidia-drm.ko" | grep -Eq '^modeset:.*\(bool\)' || \
    die "$platform nvidia-drm.ko lacks the boolean modeset parameter"

  nm "$dest/nvidia.ko" > "$tmp/$platform.nm" || die "nm failed on $platform nvidia.ko"
  grep -q '__ksymtab_nvUvmInterface' "$tmp/$platform.nm" || \
    die "$platform nvidia.ko exports no nvUvmInterface symbols"
  nm -u "$dest/nvidia-modeset.ko" > "$tmp/$platform.undefined" || \
    die "nm failed on $platform nvidia-modeset.ko"
  if [[ "$platform" != geminilakenk ]] && grep -Eq 'backlight_device_(register|unregister)' "$tmp/$platform.undefined"; then
    die "$platform is headless but nvidia-modeset.ko still references backlight symbols"
  fi
  printf '[validate-580-proprietary] PASS %s vermagic=%s license=%s modeset=available\n' \
    "$platform" "$(/sbin/modinfo -F vermagic "$dest/nvidia.ko")" "$license"
done

[[ -s "$userspace" ]] || die 'shared userspace archive is missing'
mkdir -p "$tmp/userspace" "$tmp/gsp"
tar -xzf "$userspace" -C "$tmp/userspace" || die 'shared userspace archive is corrupt'
[[ "$(cat "$tmp/userspace/VERSION" 2>/dev/null || true)" == "$DRIVER" ]] || die 'shared userspace VERSION mismatch'
[[ -s "$gsp" ]] || die 'GSP archive is missing'
tar -xzf "$gsp" -C "$tmp/gsp" || die 'GSP archive is corrupt'
find "$tmp/gsp" -type f -name 'gsp_*.bin' -print > "$tmp/gsp-files"
[[ -s "$tmp/gsp-files" ]] || die 'GSP archive contains no gsp_*.bin files'
printf '[validate-580-proprietary] PASS shared userspace and GSP archives\n'
