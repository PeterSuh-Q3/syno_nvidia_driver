#!/usr/bin/env bash
# Build and statically validate one 580.173.02 Open KMS candidate.
# Requires exact-platform 26.10.15 provider inputs in out/ and runs only in the
# pinned DSM 7.4 compiler image. Never writes canonical release assets.
set -Eeuo pipefail

readonly ROOT=/work
readonly DRIVER=580.173.02
readonly DSM_VERSION=7.4
readonly KERNEL=5.10.55
readonly KERNEL_SHORT=51055
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly SOURCE_COMMIT=a89571ecf197c83c04e16b1f09c516732defe91e
readonly SHIM="$ROOT/scripts/kms-compat/580.173.02/focused3-shim/drm-provider-symbol-aliases.h"
readonly SHIM_SHA256=a04daa03b8059439b2397ef31cd3a2a4e5b1563493b6519a9807669f3ab38ff9
readonly SHARED_ROOT="$ROOT/out/release-assets-nvidia/shared/580"
readonly PROVIDER_ROOT="$ROOT/work/shared-quad-drm-providers"
platform=${1:?usage: build-open-platform-candidate.sh <platform> <unique OUT_DIR>}
OUT_DIR=${2:?unique candidate OUT_DIR required}

case "$platform" in
  epyc7002|epyc7003|icelaked|r1000nk|v1000nk|geminilakenk) ;;
  *) echo "Unsupported K5 platform: $platform" >&2; exit 2 ;;
esac
case "$OUT_DIR" in
  "$ROOT/out/kms-expansion/kver5-580-open/${platform}-"*) ;;
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
readonly RUN_SHA256=8d8eb9001e05a9a8a663d3d5d304feb64ef2844ee185ccdfd952786820f46e1b
readonly BASELINE="$ROOT/out/release-assets-nvidia/kver5-580-open/nv-ko-${DRIVER}-open-${platform}-${KERNEL_SHORT}.tgz"
readonly USERSPACE_SHA256=362d89477c7217927c17e71f0209c51a3a349756f195633b61ede2905844be79
readonly GSP_SHA256=39f99970299a398f82b7c6d61a20f22faca1589b044822bdf1e5a36094c7d62b
case "$platform" in
  epyc7002) BASELINE_SHA256=d748835c560fcab11e645688c7f585aafd945843141720ee91844e24a8db3292; PROVIDER_SHA256=1e2485c6c5e963c7f392781c5375b3cb8374f0bd8541b7c0fab866b5434dd64c ;;
  epyc7003) BASELINE_SHA256=6ac75e26afc7624f98af249924919aa22693609967deb28ce1ff153e6c48549b; PROVIDER_SHA256=86f3676a0269faf73439f3cb4afb9979def9f64ba7292769fd43463634309910 ;;
  icelaked) BASELINE_SHA256=5688d4b29535cbb59ce9e911e3cec9024a3c349baec49e7c36443c2dcc5110e1; PROVIDER_SHA256=0e673b94ebea05442163a4ce1c49a96f2aadb0be8be2d4f608b8a8fc7adb53d9 ;;
  r1000nk) BASELINE_SHA256=2e9c574505d9965531610f2e9fa132d5191a75d5bdb0264208c183756dc45f93; PROVIDER_SHA256=da8bd4d3fa08acd46f1a0c4632ed3cd68807a528742c2b2160fc0743334e8e68 ;;
  v1000nk) BASELINE_SHA256=5374008faafebcc6fa73088250048c151af652da18186f7a92319251b8fcadcd; PROVIDER_SHA256=f8306467031a58bf2c06cbb55bae6ccb47c8295380c638bf52fb163b2c28ac65 ;;
  geminilakenk) BASELINE_SHA256=b1e50c66f36775db7edf119a422b1cfc70e9f02fd0d2bdbd31f141356d562113; PROVIDER_SHA256=542621fbb5d731dedde7fe108e7e058ead28e04252e1a8ba6043583c7f3ac4fc ;;
esac
die() { printf '[580-open-kms:%s] ERROR: %s\n' "$platform" "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }

[[ -s "$RUN_FILE" && "$(sha "$RUN_FILE")" == "$RUN_SHA256" ]] || die 'NVIDIA .run missing or checksum mismatch'
[[ -s "$USERSPACE" && "$(sha "$USERSPACE")" == "$USERSPACE_SHA256" ]] || die 'canonical shared userspace missing or checksum mismatch'
[[ -s "$GSP" && "$(sha "$GSP")" == "$GSP_SHA256" ]] || die 'canonical shared GSP missing or checksum mismatch'
[[ -s "$BASELINE" && "$(sha "$BASELINE")" == "$BASELINE_SHA256" ]] || die "580 Open baseline missing or changed: $BASELINE"
[[ -s "$PROVIDER" && -s "$PROVIDER_SYMVERS" ]] || die 'exact platform provider pack or Module.symvers missing'
[[ "$(sha "$PROVIDER")" == "$PROVIDER_SHA256" ]] || die 'exact-platform provider pack checksum mismatch'
grep -qx "provider_source_commit=$SOURCE_COMMIT" "$PROVIDER_DIR/PROVIDER-RECEIPT.txt" || die 'provider source commit mismatch'
[[ "$(sha "$PROVIDER")" == "$(sed -n 's/^provider_pack_sha256=//p' "$PROVIDER_DIR/PROVIDER-RECEIPT.txt")" ]] || die 'provider receipt does not match provider asset'
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

# Match the proven full-header recipe; a fresh container prevents cross-target
# header/config overlays from leaking into this build.
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
printf '[580-open-kms:%s] flavor=open shim=%s NO_BACKLIGHT=%s\n' "$platform" "$shim_record" "$NO_BACKLIGHT"
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
  die 'DRM imports unresolved against exact-platform provider build'
}
if [[ "$platform" == geminilakenk ]]; then
  ! nm -u "$OUT_DIR/evidence/module/nvidia-drm.ko" | grep -q 'dmabufbkpt_' || die 'Gemini unexpectedly used the focused3 alias shim'
fi

sha "$candidate" > "$OUT_DIR/evidence/candidate.sha256"
sha "$RUN_FILE" > "$OUT_DIR/evidence/nvidia-run.sha256"
sha "$BASELINE" > "$OUT_DIR/evidence/baseline.sha256"
sha "$USERSPACE" > "$OUT_DIR/evidence/shared-userspace.sha256"
sha "$GSP" > "$OUT_DIR/evidence/shared-gsp.sha256"
sha "$PROVIDER" > "$OUT_DIR/evidence/provider-pack.sha256"
sha "$PROVIDER_SYMVERS" > "$OUT_DIR/evidence/provider-Module.symvers.sha256"
sha "$KSRC/.config" > "$OUT_DIR/evidence/synology-kernel-config.sha256"
sha "$KSRC/Module.symvers" > "$OUT_DIR/evidence/synology-kernel-Module.symvers.sha256"
{
  printf 'profile=kver5-580-open\ndriver=%s\nflavor=open\nplatform=%s\ndsm=%s\nkernel=%s+\n' "$DRIVER" "$platform" "$DSM_VERSION" "$KERNEL"
  printf 'compiler_image=dante90/syno-compiler:7.4@%s\nprovider_release=mshell-modules-26.10.15\nprovider_source_commit=%s\n' "$IMAGE_DIGEST" "$SOURCE_COMMIT"
  printf 'compatibility_shim=%s\nruntime_modeset_test=pending\npromotion=not-promoted\n' "$shim_record"
} > "$OUT_DIR/BUILD-RECEIPT.txt"
printf '[580-open-kms:%s] static candidate ready: %s (sha256 %s); physical modeset test pending\n' \
  "$platform" "$candidate" "$(sha "$candidate")"
