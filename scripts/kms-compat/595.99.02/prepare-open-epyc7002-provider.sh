#!/usr/bin/env bash
# Rebuild the exact DSM 7.4 EPYC7002 quad-DRM provider inputs corresponding
# to mshell-modules 26.10.15. Run inside the pinned 7.4 compiler container,
# with /work and the read-only dual-gpu-backports checkout mounted.
set -Eeuo pipefail

readonly ROOT=/work
readonly SOURCE_REPO=/dual
readonly PLATFORM=epyc7002
readonly DSM_VERSION=7.4
readonly KERNEL=5.10.55
readonly EXPECTED_SOURCE_COMMIT=a89571ecf197c83c04e16b1f09c516732defe91e
readonly EXPECTED_PROVIDER_SHA256=1e2485c6c5e963c7f392781c5375b3cb8374f0bd8541b7c0fab866b5434dd64c
readonly PROVIDER_PACK="$ROOT/out/kms-expansion/inputs/epyc7002-7.4-5.10.55-drm.tgz"
readonly OUTPUT="$ROOT/out/kms-expansion/inputs/epyc7002-26.10.15-provider-build"
readonly MODULE_OUTPUT_SUFFIX=out/modules
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
export DSM_VERSION

die() { printf '[595-open-provider] ERROR: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }

[[ "${NV_BUILD_IMAGE_DIGEST:-}" == "$IMAGE_DIGEST" ]] || die 'run with the pinned dante90/syno-compiler:7.4 image digest and set NV_BUILD_IMAGE_DIGEST'
[[ -d "$SOURCE_REPO/.git" ]] || die 'mount the dual-gpu-backports source checkout at /dual'
[[ "$(git -c safe.directory="$SOURCE_REPO" -C "$SOURCE_REPO" rev-parse HEAD)" == "$EXPECTED_SOURCE_COMMIT" ]] || die 'dual-gpu-backports source commit does not match the 26.10.15 provider build'
[[ -s "$PROVIDER_PACK" ]] || die "missing 26.10.15 provider pack: $PROVIDER_PACK"
[[ "$(sha "$PROVIDER_PACK")" == "$EXPECTED_PROVIDER_SHA256" ]] || die 'EPYC7002 provider pack is not the pinned 26.10.15 asset'
[[ ! -e "$OUTPUT" ]] || die "refusing to overwrite provider evidence: $OUTPUT"
[[ -s "/opt/$PLATFORM/build/.config" && -s "/opt/$PLATFORM/build/Module.symvers" ]] || die 'exact DSM kernel config/symbol table is missing from the compiler image'
[[ "$(cat "/opt/$PLATFORM/build/include/config/kernel.release")" == "$KERNEL+" ]] || die 'unexpected EPYC7002 kernel release'

tmp=$(mktemp -d /tmp/595-open-provider.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
source="$tmp/source"
mkdir -p "$source"
git -c safe.directory="$SOURCE_REPO" -C "$SOURCE_REPO" archive "$EXPECTED_SOURCE_COMMIT" | tar -x -C "$source"

# The provider workflow's source tree expects its downloaded DSM toolkit paths.
# Reuse this platform's exact Synology compiler and kernel tree from the pinned
# image; all writes are confined to this disposable container and source copy.
mkdir -p "$source/ksrc/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-$DSM_VERSION"
ln -s "/opt/$PLATFORM/build" "$source/ksrc/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib/modules/DSM-$DSM_VERSION/build"
mkdir -p "$source/toolchain/usr/local/x86_64-pc-linux-gnu"
ln -s "/opt/$PLATFORM/bin" "$source/toolchain/usr/local/x86_64-pc-linux-gnu/bin"

mkdir -p "$tmp/modules"
DSM_PLATFORM="$PLATFORM" GITHUB_WORKSPACE="$source" \
  OUT_MODULES="$tmp/modules" bash "$source/.github/scripts/build-unified-drm.sh" \
  2>&1 | tee "$ROOT/out/build-logs/595-open-epyc7002-provider-26.10.15.log"

[[ -s "$source/Module.symvers" ]] || die 'provider build did not produce Module.symvers'
[[ -s "$source/.config" ]] || die 'provider build did not produce its DRM config'
for module in drm drm_kms_helper drm_display_helper drm_mipi_dsi i915 i915-compat amdgpu bochs ast; do
  [[ -s "$source/$MODULE_OUTPUT_SUFFIX/$module.ko" ]] || die "provider output is missing $module.ko"
done
tar -tzf "$PROVIDER_PACK" | grep -E '^(\./)?ast\.ko$' >/dev/null || die '26.10.15 release pack does not contain AST'

mkdir -p "$OUTPUT/source"
cp -R "$source/drm-include" "$source/i915-include" "$source/backport-include" "$OUTPUT/source/"
cp "$source/Module.symvers" "$OUTPUT/provider-Module.symvers"
cp "$source/.config" "$OUTPUT/provider.config"
cp "/opt/$PLATFORM/build/.config" "$OUTPUT/synology-kernel.config"
cp "/opt/$PLATFORM/build/Module.symvers" "$OUTPUT/synology-kernel.Module.symvers"
cp "$PROVIDER_PACK" "$OUTPUT/provider-pack.tgz"
mkdir -p "$OUTPUT/modules"
cp -R "$source/$MODULE_OUTPUT_SUFFIX/." "$OUTPUT/modules/"
{
  printf 'provider_release=mshell-modules-26.10.15\n'
  printf 'provider_source_commit=%s\n' "$EXPECTED_SOURCE_COMMIT"
  printf 'provider_platform=%s\n' "$PLATFORM"
  printf 'dsm=%s\n' "$DSM_VERSION"
  printf 'kernel=%s+\n' "$KERNEL"
  printf 'compiler_image=dante90/syno-compiler:7.4@%s\n' "$IMAGE_DIGEST"
  printf 'provider_pack_sha256=%s\n' "$(sha "$PROVIDER_PACK")"
  printf 'provider_config_sha256=%s\n' "$(sha "$OUTPUT/provider.config")"
  printf 'provider_Module.symvers_sha256=%s\n' "$(sha "$OUTPUT/provider-Module.symvers")"
  printf 'synology_kernel_config_sha256=%s\n' "$(sha "$OUTPUT/synology-kernel.config")"
  printf 'synology_kernel_Module.symvers_sha256=%s\n' "$(sha "$OUTPUT/synology-kernel.Module.symvers")"
} > "$OUTPUT/PROVIDER-RECEIPT.txt"
echo "[595-open-provider] exact provider inputs ready: $OUTPUT"
