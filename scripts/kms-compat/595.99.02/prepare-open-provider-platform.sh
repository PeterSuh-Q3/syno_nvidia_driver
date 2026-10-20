#!/usr/bin/env bash
# Rebuild matching mshell-modules 26.10.15 provider ABI evidence for one K5
# DSM 7.4 platform. Run inside the pinned compiler image with /work and /dual
# mounted; outputs are isolated under out/kms-expansion/inputs/.
set -Eeuo pipefail

readonly ROOT=/work
readonly SOURCE_REPO=/dual
readonly DSM_VERSION=7.4
readonly KERNEL=5.10.55
readonly SOURCE_COMMIT=a89571ecf197c83c04e16b1f09c516732defe91e
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly MODULE_OUTPUT_SUFFIX=out/modules
export DSM_VERSION
platform=${1:?usage: prepare-open-provider-platform.sh <platform>}

case "$platform" in
  epyc7003) provider_sha=86f3676a0269faf73439f3cb4afb9979def9f64ba7292769fd43463634309910 ;;
  geminilakenk) provider_sha=542621fbb5d731dedde7fe108e7e058ead28e04252e1a8ba6043583c7f3ac4fc ;;
  icelaked) provider_sha=0e673b94ebea05442163a4ce1c49a96f2aadb0be8be2d4f608b8a8fc7adb53d9 ;;
  r1000nk) provider_sha=da8bd4d3fa08acd46f1a0c4632ed3cd68807a528742c2b2160fc0743334e8e68 ;;
  v1000nk) provider_sha=f8306467031a58bf2c06cbb55bae6ccb47c8295380c638bf52fb163b2c28ac65 ;;
  *) echo "Unsupported K5 platform: $platform" >&2; exit 2 ;;
esac

readonly PROVIDER_PACK="$ROOT/work/shared-quad-drm-providers/${platform}-${DSM_VERSION}-${KERNEL}-drm.tgz"
readonly OUTPUT="$ROOT/out/kms-expansion/inputs/${platform}-26.10.15-provider-build"
readonly KSRC="/opt/$platform/build"
readonly TCBIN="/opt/$platform/bin"
die() { printf '[595-open-provider:%s] ERROR: %s\n' "$platform" "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }

[[ "${NV_BUILD_IMAGE_DIGEST:-}" == "$IMAGE_DIGEST" ]] || die 'compiler image digest is not the pinned DSM 7.4 image'
[[ "$(dpkg-query -W -f='${Version}' flex 2>/dev/null || true)" == '2.6.4-8.2' ]] || die 'install pinned flex=2.6.4-8.2 in this disposable compiler container first'
[[ "$(dpkg-query -W -f='${Version}' bison 2>/dev/null || true)" == '2:3.8.2+dfsg-1+b1' ]] || die 'install pinned bison=2:3.8.2+dfsg-1+b1 in this disposable compiler container first'
[[ -d "$SOURCE_REPO/.git" ]] || die 'mount dual-gpu-backports at /dual'
[[ "$(git -c safe.directory="$SOURCE_REPO" -C "$SOURCE_REPO" rev-parse HEAD)" == "$SOURCE_COMMIT" ]] || die 'provider source commit mismatch'
[[ -s "$PROVIDER_PACK" && "$(sha "$PROVIDER_PACK")" == "$provider_sha" ]] || die 'provider asset missing or checksum mismatch'
[[ -s "$KSRC/.config" && -s "$KSRC/Module.symvers" ]] || die 'exact platform kernel config/symbol table missing'
[[ "$(cat "$KSRC/include/config/kernel.release")" == "$KERNEL+" ]] || die 'kernel release mismatch'
[[ -x "$TCBIN/x86_64-pc-linux-gnu-gcc" ]] || die 'exact platform cross-compiler missing'
[[ ! -e "$OUTPUT" ]] || die "refusing to overwrite existing provider evidence: $OUTPUT"

tmp=$(mktemp -d "/tmp/595-open-provider-${platform}.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
source="$tmp/source"
mkdir -p "$source" "$ROOT/out/build-logs"
git -c safe.directory="$SOURCE_REPO" -C "$SOURCE_REPO" archive "$SOURCE_COMMIT" | tar -x -C "$source"

# Bind the platform-specific Synology kernel/toolchain into the provider
# workflow's expected toolkit layout; all writes stay in this disposable copy.
mkdir -p "$source/ksrc/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-$DSM_VERSION"
ln -s "$KSRC" "$source/ksrc/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-$DSM_VERSION/build"
mkdir -p "$source/toolchain/usr/local/x86_64-pc-linux-gnu"
ln -s "$TCBIN" "$source/toolchain/usr/local/x86_64-pc-linux-gnu/bin"

DSM_PLATFORM="$platform" GITHUB_WORKSPACE="$source" \
  bash "$source/.github/scripts/build-unified-drm.sh" \
  2>&1 | tee "$ROOT/out/build-logs/595-open-${platform}-provider-26.10.15.log"

[[ -s "$source/Module.symvers" && -s "$source/.config" ]] || die 'provider build did not produce config and Module.symvers'
modules="$source/out/modules"
for module in drm drm_kms_helper drm_display_helper drm_mipi_dsi i915 i915-compat amdgpu bochs ast; do
  # The pinned provider workflow intentionally omits drm_mipi_dsi.ko for Gemini.
  [[ "$platform" != geminilakenk || "$module" != drm_mipi_dsi ]] || continue
  [[ -s "$modules/$module.ko" ]] || die "provider build missing $module.ko at actual workflow output path $modules"
done
tar -tzf "$PROVIDER_PACK" | grep -E '^([./]*ast\.ko)$' >/dev/null || die 'release pack is not the expected quad-DRM pack'

mkdir -p "$OUTPUT/source" "$OUTPUT/modules"
cp -R "$source/drm-include" "$source/i915-include" "$source/backport-include" "$OUTPUT/source/"
cp "$source/Module.symvers" "$OUTPUT/provider-Module.symvers"
cp "$source/.config" "$OUTPUT/provider.config"
cp "$KSRC/.config" "$OUTPUT/synology-kernel.config"
cp "$KSRC/Module.symvers" "$OUTPUT/synology-kernel.Module.symvers"
cp "$PROVIDER_PACK" "$OUTPUT/provider-pack.tgz"
cp -R "$modules/." "$OUTPUT/modules/"
{
  printf 'provider_release=mshell-modules-26.10.15\n'
  printf 'provider_source_commit=%s\n' "$SOURCE_COMMIT"
  printf 'provider_platform=%s\n' "$platform"
  printf 'dsm=%s\n' "$DSM_VERSION"
  printf 'kernel=%s+\n' "$KERNEL"
  printf 'compiler_image=dante90/syno-compiler:7.4@%s\n' "$IMAGE_DIGEST"
  printf 'provider_pack_sha256=%s\n' "$(sha "$PROVIDER_PACK")"
  printf 'provider_config_sha256=%s\n' "$(sha "$OUTPUT/provider.config")"
  printf 'provider_Module.symvers_sha256=%s\n' "$(sha "$OUTPUT/provider-Module.symvers")"
  printf 'synology_kernel_config_sha256=%s\n' "$(sha "$OUTPUT/synology-kernel.config")"
  printf 'synology_kernel_Module.symvers_sha256=%s\n' "$(sha "$OUTPUT/synology-kernel.Module.symvers")"
} > "$OUTPUT/PROVIDER-RECEIPT.txt"
printf '[595-open-provider:%s] exact provider inputs ready: %s\n' "$platform" "$OUTPUT"
