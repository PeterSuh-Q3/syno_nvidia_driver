#!/usr/bin/env bash
# Build an offline .spk variant by downloading the already-
# published GitHub Release assets (from the pinned "nvidia" tag - see
# install.sh's REPO_RAW) and repacking them into DSM's package format,
# following the same INFO-templating / package.tgz / final-tar pattern as
# syno-amdgpu-driver/scripts/package-spk.sh.
#
# Usage: build-spk.sh <kver5-580-open|kver5-580-proprietary|kver5-595-open|kver5-595-proprietary|kver4-72|kver4-70>
set -euo pipefail

VARIANT=${1:?variant required: kver5-580-open | kver5-580-proprietary | kver5-595-open | kver5-595-proprietary | kver4-72 | kver4-70}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REL="https://github.com/PeterSuh-Q3/syno_nvidia_driver/releases/download/nvidia"
OUT="${DIST_DIR:-$ROOT/dist}"
WORK="$ROOT/work/spk-$VARIANT"

# ---- per-variant configuration ---------------------------------------------
# Platform lists and kernel-suffix/file-naming convention come straight from
# tcrp-addons/nvidiadriver/src/nvidia-index.json (pinned commit
# 40df760c9ebeafac00b8c61149c2b4dfe6141d1c, the same one install.sh reads).
# epyc7003ntb (PAS7700) is no longer supported by this driver.
KVER5_PLATFORMS="epyc7002 epyc7003 geminilakenk icelaked r1000nk v1000nk"
KVER4_PLATFORMS="apollolake broadwell broadwellnk broadwellnkv2 broadwellntbap geminilake purley r1000 v1000"
KO_FLAVOR_PREFIX=""
MODULE_FLAVOR="proprietary"
ENABLE_NVIDIA_DRM_MODESET=0
BUNDLE_DRM_PROVIDER=0
ENABLE_PLEX_RESTART=0
KO_ASSET_DIR=""
DRM_PROVIDER_SOURCE="release-26.10.13"
DISPLAYNAME="Synology NVIDIA Driver"

case "$VARIANT" in
  kver5-580-open)
    # KMS candidate promotion: keep the prior no-KMS SPK/version recoverable,
    # while the standard open package now consumes the promoted KMS module set.
    WORK="$ROOT/work/spk-kver5-580-open-kms"
    DRIVER=580.173.02
    PACKAGE_REVISION=6
    KSUFFIX=51055
    PLATFORMS="$KVER5_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver5-580-open
    DISPLAYNAME="Synology NVIDIA Driver 580 open"
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=1
    KO_FLAVOR_PREFIX="open-"
    MODULE_FLAVOR="open"
    KO_ASSET_DIR="$ROOT/out/release-assets-nvidia/kver5-580-open"
    BUNDLE_DRM_PROVIDER=1
    DRM_PROVIDER_SOURCE="work-26.10.15"
    ENABLE_NVIDIA_DRM_MODESET=1
    ENABLE_PLEX_RESTART=1
    DESC_EN="NVIDIA 580.173.02 open driver; CUDA API 13.0; supports Turing/Ampere GPUs in the bundled compatibility table (not Ada/Blackwell); kernel 5.10.55. Platforms: ${PLATFORMS}. KMS enabled with matching quad-DRM providers and nvidia-drm modeset=1. Automatic recovery validates and restores missing/mismatched platform modules from this package after boot-time DSM/loader changes and notifies administrators; it reports when a reboot is required. Plex is restarted and checked after driver activation, including after recovery. Physical KMS validation is pending. Reboot after migration if NVIDIA modules are already loaded."
    DESC_KR="NVIDIA 580.173.02 오픈 드라이버입니다. CUDA API 13.0을 제공하고 번들 호환성 표의 Turing/Ampere GPU를 지원합니다(Ada/Blackwell 제외). 커널 5.10.55용, 플랫폼: ${PLATFORMS}. 일치하는 quad-DRM provider와 nvidia-drm modeset=1로 KMS를 활성화합니다. 부팅 중 DSM/로더 변경으로 플랫폼 모듈이 누락되거나 불일치하면 패키지에서 검증·복구하고 관리자에게 알리며, 재부팅 필요 여부도 안내합니다. 복구 후에도 드라이버 활성화를 확인한 다음 Plex를 재시작하고 결과를 확인합니다. 실기 KMS 검증은 진행 전입니다. 마이그레이션 후 NVIDIA 모듈이 이미 적재되어 있으면 재부팅하십시오."
    FILESUFFIX=""
    ;;
  kver5-580-proprietary)
    # Include the matching DRM provider and retain the modeset=1 path used by
    # revision -4. Restart Plex after the driver is ready so its CUDA probe is
    # not lost to the DSM boot-time service ordering race.
    WORK="$ROOT/work/spk-kver5-580-proprietary-rev4"
    DRIVER=580.173.02
    PACKAGE_REVISION=7
    KSUFFIX=51055
    PLATFORMS="$KVER5_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver5-580-proprietary
    DISPLAYNAME="Synology NVIDIA Driver 580 Proprietary"
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=1
    KO_FLAVOR_PREFIX="proprietary-"
    MODULE_FLAVOR="proprietary"
    BUNDLE_DRM_PROVIDER=1
    ENABLE_NVIDIA_DRM_MODESET=1
    ENABLE_PLEX_RESTART=1
    DESC_EN="NVIDIA 580.173.02 proprietary driver; CUDA API 13.0; supports Maxwell–Ampere GPUs in the bundled compatibility table; kernel 5.10.55. Platforms: ${PLATFORMS}. Includes matching quad-DRM providers and KMS modeset=1. After boot-time DSM/loader changes, startup validates and restores missing/mismatched platform modules from this package, notifies administrators, and reports if reboot is required. Plex is restarted and checked after driver activation, including after recovery. Reboot after migration if NVIDIA modules are already loaded."
    DESC_KR="NVIDIA 580.173.02 독점 드라이버입니다. CUDA API 13.0을 제공하고 번들 호환성 표의 Maxwell–Ampere GPU를 지원합니다. 커널 5.10.55용, 플랫폼: ${PLATFORMS}. 일치하는 quad-DRM provider와 KMS modeset=1을 포함합니다. 부팅 중 DSM/로더 변경으로 플랫폼 모듈이 누락되거나 불일치하면 시작 시 패키지에서 검증·복구하고 관리자에게 알리며, 재부팅 필요 여부도 안내합니다. 복구 후에도 드라이버 활성화를 확인한 다음 Plex를 재시작하고 결과를 확인합니다. 마이그레이션 후 NVIDIA 모듈이 이미 적재되어 있으면 재부팅하십시오."
    FILESUFFIX=""
    ;;
  kver5-595-open)
    # Keep the previous no-KMS assembly tree intact; package the promoted KMS
    # modules and current shared quad-DRM provider archives in a new tree.
    WORK="$ROOT/work/spk-kver5-595-open-kms"
    DRIVER=595.99.02
    PACKAGE_REVISION=5
    KSUFFIX=51055
    PLATFORMS="$KVER5_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver5-595-open
    DISPLAYNAME="Synology NVIDIA Driver 595 open"
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=1
    KO_FLAVOR_PREFIX="open-"
    MODULE_FLAVOR="open"
    KO_ASSET_DIR="$ROOT/out/release-assets-nvidia/kver5-595-open"
    BUNDLE_DRM_PROVIDER=1
    DRM_PROVIDER_SOURCE="work-26.10.15"
    ENABLE_NVIDIA_DRM_MODESET=1
    ENABLE_PLEX_RESTART=1
    DESC_EN="NVIDIA 595.99.02 open driver; CUDA API 13.2; supports Turing and newer GPUs in the bundled compatibility table; kernel 5.10.55. Platforms: ${PLATFORMS}. KMS enabled with matching quad-DRM providers and nvidia-drm modeset=1. Automatic recovery validates and restores missing/mismatched platform modules from this package after boot-time DSM/loader changes and notifies administrators; it reports when a reboot is required. Plex is restarted and checked after driver activation, including after recovery. Physical KMS validation is pending. Reboot after migration if NVIDIA modules are already loaded."
    DESC_KR="NVIDIA 595.99.02 오픈 드라이버입니다. CUDA API 13.2를 제공하고 번들 호환성 표의 Turing 이상 GPU를 지원합니다. 커널 5.10.55용, 플랫폼: ${PLATFORMS}. 일치하는 quad-DRM provider와 nvidia-drm modeset=1로 KMS를 활성화합니다. 부팅 중 DSM/로더 변경으로 플랫폼 모듈이 누락되거나 불일치하면 패키지에서 검증·복구하고 관리자에게 알리며, 재부팅 필요 여부도 안내합니다. 복구 후에도 드라이버 활성화를 확인한 다음 Plex를 재시작하고 결과를 확인합니다. 실기 KMS 검증은 진행 전입니다. 마이그레이션 후 NVIDIA 모듈이 이미 적재되어 있으면 재부팅하십시오."
    FILESUFFIX=""
    ;;
  kver5-595-proprietary)
    WORK="$ROOT/work/spk-kver5-595-proprietary-rev5"
    DRIVER=595.99.02
    PACKAGE_REVISION=6
    KSUFFIX=51055
    PLATFORMS="$KVER5_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver5-595-proprietary
    DISPLAYNAME="Synology NVIDIA Driver 595 proprietary"
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=1
    KO_FLAVOR_PREFIX="proprietary-"
    MODULE_FLAVOR="proprietary"
    BUNDLE_DRM_PROVIDER=1
    ENABLE_NVIDIA_DRM_MODESET=1
    ENABLE_PLEX_RESTART=1
    DESC_EN="NVIDIA 595.99.02 proprietary driver; CUDA API 13.2; supports Turing and newer GPUs in the bundled compatibility table; kernel 5.10.55. Platforms: ${PLATFORMS}. Performs a GPU compatibility pre-check and enables KMS modeset=1 with matching quad-DRM providers. After boot-time DSM/loader changes, startup validates and restores missing/mismatched platform modules from this package, notifies administrators, and reports if reboot is required. Plex is restarted and checked after driver activation, including after recovery. Reboot after migration if NVIDIA modules are already loaded."
    DESC_KR="NVIDIA 595.99.02 독점 드라이버입니다. CUDA API 13.2를 제공하고 번들 호환성 표의 Turing 이상 GPU를 지원합니다. 커널 5.10.55용, 플랫폼: ${PLATFORMS}. GPU 호환성 사전 검사와 일치하는 quad-DRM provider, KMS modeset=1을 적용합니다. 부팅 중 DSM/로더 변경으로 플랫폼 모듈이 누락되거나 불일치하면 시작 시 패키지에서 검증·복구하고 관리자에게 알리며, 재부팅 필요 여부도 안내합니다. 복구 후에도 드라이버 활성화를 확인한 다음 Plex를 재시작하고 결과를 확인합니다. 마이그레이션 후 NVIDIA 모듈이 이미 적재되어 있으면 재부팅하십시오."
    FILESUFFIX=""
    ;;
  kver5)
    echo "The unsplit kver5 package ID is retired from the active package catalog; use the flavor-specific 580/595 variants." >&2
    exit 2
    ;;
  kver4-72)
    PACKAGE_REVISION=6
    DRIVER=550.163.01
    KSUFFIX=44302
    PLATFORMS="$KVER4_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver4-dsm72
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=0
    DESC_EN="NVIDIA 550.163.01 driver for kernel 4.4.302 (DSM 7.2–7.4); bundled platforms: ${PLATFORMS}. At startup, selects the current platform's modules only when the bundled kernel ABI matches. Reboot after migration if NVIDIA modules are already loaded."
    DESC_KR="커널 4.4.302용 NVIDIA 550.163.01 드라이버입니다(DSM 7.2–7.4). 포함 플랫폼은 ${PLATFORMS}입니다. 시작 시 번들 커널 ABI가 일치하는 경우에만 현재 플랫폼의 모듈을 선택합니다. 마이그레이션 후 NVIDIA 모듈이 이미 적재되어 있다면 재부팅하십시오."
    FILESUFFIX="-dsm7.2-7.4"
    ;;
  kver4-70)
    PACKAGE_REVISION=6
    DRIVER=550.163.01
    KSUFFIX=44180
    PLATFORMS="$KVER4_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver4-dsm70
    OS_MIN_VER=7.0-00000
    BUNDLE_GSP=0
    DESC_EN="NVIDIA 550.163.01 driver for kernel 4.4.180 (DSM 7.0–7.1); bundled platforms: ${PLATFORMS}. At startup, selects the current platform's modules only when the bundled kernel ABI matches. Reboot after migration if NVIDIA modules are already loaded."
    DESC_KR="커널 4.4.180용 NVIDIA 550.163.01 드라이버입니다(DSM 7.0–7.1). 포함 플랫폼은 ${PLATFORMS}입니다. 시작 시 번들 커널 ABI가 일치하는 경우에만 현재 플랫폼의 모듈을 선택합니다. 마이그레이션 후 NVIDIA 모듈이 이미 적재되어 있다면 재부팅하십시오."
    FILESUFFIX="-dsm7.0-7.1"
    ;;
  *) echo "Unknown variant: $VARIANT (expected kver5-580-open | kver5-580-proprietary | kver5-595-open | kver5-595-proprietary | kver4-72 | kver4-70)" >&2; exit 2 ;;
esac

# Keep migration candidates isolated from existing SPKs and assembly trees.
if [[ "${PLATFORM_MIGRATION_BUILD:-0}" == 1 ]]; then
  WORK="$ROOT/work/platform-migration-$VARIANT"
fi

# Opt-in, local-only diagnostic package. Keep the normal package work tree,
# dist artifact, package version, and lifecycle behavior untouched. The trace
# is emitted by the privileged backend to a root-only log on the NAS.
DIAGNOSTIC_SUFFIX=""
if [[ "${NVIDIA_DIAGNOSTIC_BUILD:-0}" == 1 ]]; then
  WORK="$ROOT/work/diagnostic-$VARIANT"
  OUT="${DIAGNOSTIC_DIST_DIR:-$ROOT/dist/diagnostic}"
  DIAGNOSTIC_SUFFIX="-diagnostic"
  DISPLAYNAME="$DISPLAYNAME (Install Diagnostic)"
  DESC_EN="$DESC_EN Diagnostic build: records a root-only execution trace at /var/log/nvidia-driver-diagnostic.log for troubleshooting; not for normal distribution."
  DESC_KR="$DESC_KR 진단용 빌드입니다. 문제 분석을 위해 /var/log/nvidia-driver-diagnostic.log에 root 전용 실행 추적 로그를 기록합니다. 일반 배포용이 아닙니다."
fi

# Wipe everything except dl/ (the downloaded release assets) so re-running
# after an INFO/script fix doesn't re-pull ~500MB-900MB over the network.
rm -rf "$WORK/target" "$WORK/scripts" "$WORK/conf" "$WORK/INFO" "$WORK"/*.PNG
mkdir -p "$WORK/target/lib/modules" "$WORK/target/lib/nvidia/bin" "$WORK/target/lib/nvidia/lib" \
         "$WORK/target/lib/firmware" "$WORK/target/share" "$WORK/target/ui/texts/enu" \
         "$WORK/target/ui/texts/krn" "$WORK/target/ui/images" "$WORK/scripts" "$WORK/conf" "$WORK/dl"
case "$KSUFFIX" in
  51055) PACKAGE_KERNEL_VERSION=5.10.55 ;;
  44302) PACKAGE_KERNEL_VERSION=4.4.302 ;;
  44180) PACKAGE_KERNEL_VERSION=4.4.180 ;;
  *) echo "Unknown kernel suffix '$KSUFFIX'; refusing to build without kernel metadata" >&2; exit 1 ;;
esac
printf '%s\n' "$PACKAGE_KERNEL_VERSION" > "$WORK/target/share/nvidia-kernel-version"
bash "$ROOT/scripts/check-shared-nvidia-layers.sh"

fetch() {
  local file=$1
  [ -f "$WORK/dl/$file" ] && return 0
  echo "fetching $file"
  curl -sL --fail "$REL/$file" -o "$WORK/dl/$file"
}

# ---- kernel modules (one nv-ko tgz per platform, this variant's kernel) ----
for p in $PLATFORMS; do
  KO="nv-ko-${DRIVER}-${KO_FLAVOR_PREFIX}${p}-${KSUFFIX}.tgz"
  if [ -n "$KO_ASSET_DIR" ]; then
    [ -s "$KO_ASSET_DIR/$KO" ] || { echo "missing promoted module archive: $KO_ASSET_DIR/$KO" >&2; exit 1; }
    cp -p "$KO_ASSET_DIR/$KO" "$WORK/dl/$KO"
  else
    fetch "$KO"
  fi
  mkdir -p "$WORK/target/lib/modules/$p"
  tar -xzf "$WORK/dl/$KO" -C "$WORK/target/lib/modules/$p"
done

# ---- shared userspace (one archive per driver version, not per SPK workdir) --
US="nv-userspace-${DRIVER}.tgz"
SHARED_US="$ROOT/out/release-assets-nvidia/shared/${DRIVER%%.*}/$US"
if [ ! -s "$SHARED_US" ]; then
  mkdir -p "$(dirname "$SHARED_US")"
  echo "fetching shared $US"
  curl -sL --fail "$REL/$US" -o "$SHARED_US.tmp.$$"
  mv "$SHARED_US.tmp.$$" "$SHARED_US"
fi
US_VERSION=$(tar -xOzf "$SHARED_US" ./VERSION 2>/dev/null | tr -d '\r\n')
[ "$US_VERSION" = "$DRIVER" ] || { echo "shared userspace version mismatch: $SHARED_US" >&2; exit 1; }
tar -xzf "$SHARED_US" -C "$WORK/target/lib/nvidia"

if [ "$ENABLE_NVIDIA_DRM_MODESET" = 1 ]; then
  mkdir -p "$WORK/target/share"
  : > "$WORK/target/share/nvidia-drm-kms-modeset.enabled"
fi
if [ "$ENABLE_PLEX_RESTART" = 1 ]; then
  mkdir -p "$WORK/target/share"
  : > "$WORK/target/share/nvidia-plex-restart.enabled"
fi

# ---- matching quad-DRM provider archives (K5 proprietary) -----------------
# Every bundled platform receives its matching provider closure before the
# NVIDIA modules. Keep this identical for 580 and 595 proprietary packages.
if [ "$BUNDLE_DRM_PROVIDER" = 1 ]; then
  DRM_CACHE="$ROOT/work/shared-quad-drm-providers"
  DRM_STAGE="$WORK/target/lib/drm-provider"
  mkdir -p "$DRM_STAGE" "$DRM_CACHE"
  stage_drm_provider() {
    local platform=$1 sha=$2 source_base=$3
    local asset="${platform}-7.4-5.10.55-drm.tgz" actual tmp
    # Identical filenames exist in multiple provider releases. Cache each
    # immutable archive by its expected digest so a newer local archive can
    # never shadow the pinned release selected by this package variant.
    local src="$DRM_CACHE/$sha/$asset"
    if [ ! -s "$src" ]; then
      mkdir -p "$(dirname "$src")"
      if [ "$source_base" = local ]; then
        local existing="$DRM_CACHE/$asset"
        [ -s "$existing" ] || { echo "missing local quad DRM provider: $existing" >&2; exit 1; }
        local existing_sha
        existing_sha=$(shasum -a 256 "$existing" | awk '{print $1}')
        [ "$existing_sha" = "$sha" ] || { echo "local quad DRM provider checksum mismatch for $asset: expected $sha, got $existing_sha" >&2; exit 1; }
        cp -p "$existing" "$src"
      else
      tmp="$src.tmp.$$"
      echo "fetching pinned quad DRM provider $asset"
      curl -sL --fail "$source_base/$asset" -o "$tmp"
      mv "$tmp" "$src"
      fi
    fi
    actual=$(shasum -a 256 "$src" | awk '{print $1}')
    [ "$actual" = "$sha" ] || {
      echo "quad DRM provider checksum mismatch for $asset: expected $sha, got $actual" >&2
      exit 1
    }
    tar -tzf "$src" | grep -qx 'drm.ko' || { echo "invalid DRM archive: $asset" >&2; exit 1; }
    tar -tzf "$src" | grep -qx 'drm_kms_helper.ko' || { echo "missing drm_kms_helper.ko: $asset" >&2; exit 1; }
    cp "$src" "$DRM_STAGE/$asset"
  }

  if [ "$DRM_PROVIDER_SOURCE" = "work-26.10.15" ]; then
    while read -r platform sha; do
      [ -n "$platform" ] || continue
      stage_drm_provider "$platform" "$sha" local
    done <<'DRM_ASSETS'
epyc7002 1e2485c6c5e963c7f392781c5375b3cb8374f0bd8541b7c0fab866b5434dd64c
epyc7003 86f3676a0269faf73439f3cb4afb9979def9f64ba7292769fd43463634309910
icelaked 0e673b94ebea05442163a4ce1c49a96f2aadb0be8be2d4f608b8a8fc7adb53d9
r1000nk da8bd4d3fa08acd46f1a0c4632ed3cd68807a528742c2b2160fc0743334e8e68
v1000nk f8306467031a58bf2c06cbb55bae6ccb47c8295380c638bf52fb163b2c28ac65
geminilakenk 542621fbb5d731dedde7fe108e7e058ead28e04252e1a8ba6043583c7f3ac4fc
DRM_ASSETS
  else
    while read -r platform sha source_base; do
      [ -n "$platform" ] || continue
      [ "$platform" = geminilakenk ] && [ "$DRIVER" != 595.99.02 ] && continue
      stage_drm_provider "$platform" "$sha" "$source_base"
    done <<'DRM_ASSETS'
epyc7002 5d9b7e5473102106859740bc329a94323635cf4c3ae0c51a5c6a6916bc424cf9 https://github.com/PeterSuh-Q3/mshell-modules/releases/download/26.10.13
epyc7003 722669eb04384dea78ae7aeec75aaa039e2582e352af5536a447e50ef54cdd1f https://github.com/PeterSuh-Q3/mshell-modules/releases/download/26.10.13
icelaked 5c0960e5eb598c80df07cf2a17714ba9ebd274a8a944efb070112da81388010d https://github.com/PeterSuh-Q3/mshell-modules/releases/download/26.10.13
r1000nk 424d51a8b2f4b912da6e11f006762447ad5128e7d568705a32ec04e3c9a41b17 https://github.com/PeterSuh-Q3/mshell-modules/releases/download/26.10.13
v1000nk b9fadf760f40ff7916f948521a8667da86f145e6797c5b099b8f545ac5812f0a https://github.com/PeterSuh-Q3/mshell-modules/releases/download/26.10.13
geminilakenk 542621fbb5d731dedde7fe108e7e058ead28e04252e1a8ba6043583c7f3ac4fc https://github.com/PeterSuh-Q3/tcrp-modules/releases/download/26.10.15
DRM_ASSETS
  fi
  mkdir -p "$WORK/target/share"
  : > "$WORK/target/share/nvidia-drm-provider.enabled"
fi

# ---- GSP firmware (kver5/580 only - no gsp_fw entries exist for 550) ------
if [ "$BUNDLE_GSP" = 1 ]; then
  GSP="nv-gsp-${DRIVER}.tgz"
  SHARED_GSP="$ROOT/out/release-assets-nvidia/shared/${DRIVER%%.*}/$GSP"
  if [ ! -s "$SHARED_GSP" ]; then
    mkdir -p "$(dirname "$SHARED_GSP")"
    echo "fetching shared $GSP"
    curl -sL --fail "$REL/$GSP" -o "$SHARED_GSP.tmp.$$"
    mv "$SHARED_GSP.tmp.$$" "$SHARED_GSP"
  fi
  tar -tzf "$SHARED_GSP" | grep -Eq '(^|/)gsp_[^/]+\.bin$' || {
    echo "shared GSP archive is invalid: $SHARED_GSP" >&2; exit 1;
  }
  # The shared GSP layer already has a top-level firmware/ directory. Unpack
  # it into a temporary directory and flatten only that directory into the
  # package's lib/firmware path expected by nvidia-backend.sh; retain the
  # archive's LICENSE and VERSION alongside the firmware files.
  GSP_STAGE="$WORK/target/.gsp-stage"
  mkdir -p "$GSP_STAGE" "$WORK/target/lib/firmware"
  tar -xzf "$SHARED_GSP" -C "$GSP_STAGE"
  if [ -d "$GSP_STAGE/firmware" ]; then
    cp -a "$GSP_STAGE/firmware/." "$WORK/target/lib/firmware/"
  else
    # Some published GSP layers contain gsp_*.bin at archive root while
    # others use firmware/. Normalize both layouts into the package path
    # consumed by nvidia-backend.sh; never ship an empty firmware directory.
    found_gsp=0
    for fw in "$GSP_STAGE"/gsp_*.bin; do
      [ -s "$fw" ] || continue
      cp -p "$fw" "$WORK/target/lib/firmware/" || exit 1
      found_gsp=1
    done
    [ "$found_gsp" -eq 1 ] || { echo "shared GSP archive has no firmware/gsp_*.bin payload: $SHARED_GSP" >&2; exit 1; }
  fi
  for metadata in LICENSE VERSION; do
    [ ! -f "$GSP_STAGE/$metadata" ] || cp -f "$GSP_STAGE/$metadata" "$WORK/target/lib/firmware/$metadata"
  done
  rm -rf "$GSP_STAGE"
fi

# ---- bundled GPU-support table (offline copy, not live-fetched) -----------
# Pinned to the same tcrp-addons commit install.sh reads (see its SUP_URL) so
# a package built today and one built after a future gpu-support.json update
# resolve to the same table until this SHA is deliberately bumped.
curl -sL --fail "https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/40df760c9ebeafac00b8c61149c2b4dfe6141d1c/nvidiadriver/src/nvidia-gpu-support.json" \
  -o "$WORK/target/share/nvidia-gpu-support.json"

# Package Center's preinst/preupgrade checks need a small PCI-ID table before
# package.tgz is unpacked. Keep it beside the lifecycle scripts and generate it
# from the same pinned GPU support database bundled into the installed package.
python3 - "$WORK/target/share/nvidia-gpu-support.json" "$WORK/scripts/nvidia-gpu-support.tsv" <<'PY'
import json
import sys

source, target = sys.argv[1:]
data = json.load(open(source, encoding="utf-8"))
with open(target, "w", encoding="utf-8") as out:
    for pci, gpu in sorted(data.get("gpus", {}).items()):
        fields = (
            pci,
            (gpu.get("arch") or "").replace("\t", " ").replace("\n", " "),
            (gpu.get("name") or "Unknown NVIDIA GPU").replace("\t", " ").replace("\n", " "),
            " ".join(gpu.get("branches") or []),
        )
        out.write("\t".join(fields) + "\n")
PY
printf '%s\n' "$DRIVER" > "$WORK/scripts/target-driver.txt"
printf '%s\n' "$MODULE_FLAVOR" > "$WORK/scripts/target-module-flavor.txt"

# ---- lifecycle scripts + conf (shared verbatim across all 3 variants) -----
cp "$ROOT/spk/scripts/"* "$WORK/scripts/"
cp "$ROOT/spk/conf/"* "$WORK/conf/"
chmod 0755 "$WORK/scripts/"*

# ---- setuid helper + backend script -----------------------------------
# postinst/start-stop-status/preuninst run as the conf/privilege-declared
# unprivileged "package" account (confirmed on real DSM 7.4 hardware -
# see spk/helper/nvidia-helper.c), so the actual root-requiring work
# (kernel modules, /dev nodes, ldconfig, Container Manager/Jellyfin
# integration) lives in nvidia-backend.sh, reachable only through this
# setuid helper. TARGET_SCRIPT is baked in per variant because each one
# installs to a different /var/packages/<name>/target.
mkdir -p "$WORK/target/bin/helper"
cp "$ROOT/spk/bin/nvidia-backend.sh" "$WORK/target/bin/nvidia-backend.sh"
chmod 0755 "$WORK/target/bin/nvidia-backend.sh"
if [[ "${NVIDIA_DIAGNOSTIC_BUILD:-0}" == 1 ]]; then
  python3 - "$WORK/target/bin/nvidia-backend.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "set -eu\n"
trace = '''set -eu
# Temporary install-diagnostic instrumentation. Keep this root-only because
# the trace can include system paths and command output.
umask 077
DIAGNOSTIC_LOG=/var/log/nvidia-driver-diagnostic.log
exec 2>>"$DIAGNOSTIC_LOG"
PS4='+$(date "+%Y-%m-%d %H:%M:%S") nvidia-backend[$$] '
trap 'diag_status=$?; printf "%s nvidia-backend: exit=%s action=%s\\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$diag_status" "${1:-unknown}" >&2' 0
set -x
'''
if text.count(needle) != 1:
    raise SystemExit(f"expected one backend set -eu, found {text.count(needle)}")
path.write_text(text.replace(needle, trace, 1))
PY
  python3 - "$WORK/scripts/postinst" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = 'if [ "$STATUS" -ne 0 ]; then\n'
replacement = '''if [ "$STATUS" -ne 0 ]; then
  echo "nvidia-driver: diagnostic trace: /var/log/nvidia-driver-diagnostic.log" >&2
'''
if text.count(needle) != 1:
    raise SystemExit(f"expected one postinst failure block, found {text.count(needle)}")
path.write_text(text.replace(needle, replacement, 1))
PY
  : > "$WORK/target/share/nvidia-install-diagnostic.enabled"
fi
docker run --rm --platform linux/amd64 \
  -v "$ROOT/spk/helper:/src" -v "$WORK/target/bin/helper:/out" -w /src gcc:latest \
  gcc -O2 -static -Wall -Wextra \
  -DTARGET_SCRIPT="\"/var/packages/${PACKAGE}/target/bin/nvidia-backend.sh\"" \
  -o /out/nvidia-helper.x86_64 nvidia-helper.c
chmod 0755 "$WORK/target/bin/helper/nvidia-helper.x86_64"

# ---- INFO templating --------------------------------------------------------
cp "$ROOT/spk/INFO" "$WORK/INFO"
sed -i.bak \
  -e "s/^package=\"[^\"]*\"/package=\"$PACKAGE\"/" \
  -e "s/^version=\"[^\"]*\"/version=\"${DRIVER}-${PACKAGE_REVISION}\"/" \
  -e "s/^displayname=\"[^\"]*\"/displayname=\"$DISPLAYNAME\"/" \
  -e "s/^arch=\"[^\"]*\"/arch=\"$PLATFORMS\"/" \
  -e "s/^os_min_ver=\"[^\"]*\"/os_min_ver=\"$OS_MIN_VER\"/" \
  -e "s#__DESC_EN__#$DESC_EN#g" \
  -e "s#__DESC_KR__#$DESC_KR#g" \
  "$WORK/INFO"
rm -f "$WORK/INFO.bak"
VERSION=$(sed -n 's/^version="\([^"]*\)"$/\1/p' "$WORK/INFO" | head -1)

# DSM 7 desktop notifications require localized I18N keys registered through
# the package's hidden .url app entry; arbitrary title/message strings are
# rejected by synodsmnotify.
sed "s/__PACKAGE__/$PACKAGE/g" "$ROOT/spk/ui/config" > "$WORK/target/ui/config"
cp "$ROOT/spk/ui/texts/enu/strings" "$WORK/target/ui/texts/enu/strings"
cp "$ROOT/spk/ui/texts/krn/strings" "$WORK/target/ui/texts/krn/strings"
cp "$ROOT/spk/PACKAGE_ICON.PNG" "$WORK/target/ui/images/app_64.png"
cp "$ROOT/spk/PACKAGE_ICON_256.PNG" "$WORK/target/ui/images/app_256.png"

for icon in PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG; do
  [ -f "$ROOT/spk/$icon" ] && cp "$ROOT/spk/$icon" "$WORK/$icon"
done

# ---- assemble package.tgz + final .spk -------------------------------------
tar -C "$WORK/target" -czf "$WORK/package.tgz" .
CHECKSUM=$(md5sum "$WORK/package.tgz" | awk '{print $1}')
EXTRACT_SIZE=$(du -sk "$WORK/target" | awk '{print $1}')
{
  printf 'extractsize="%s"\n' "$EXTRACT_SIZE"
  printf 'create_time="%s"\n' "$(date +%Y%m%d-%H:%M:%S)"
  printf 'checksum="%s"\n' "$CHECKSUM"
  for icon in PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG; do
    [ -f "$WORK/$icon" ] || continue
    key=$(echo "${icon%.PNG}" | tr '[:upper:]' '[:lower:]')
    printf '%s="%s"\n' "$key" "$(base64 < "$WORK/$icon" | tr -d '\n')"
  done
} >> "$WORK/INFO"

mkdir -p "$OUT"
members=(INFO package.tgz scripts conf)
for icon in PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG; do
  [ -f "$WORK/$icon" ] && members+=("$icon")
done
SPK="$OUT/${PACKAGE}-${VERSION}${FILESUFFIX}${DIAGNOSTIC_SUFFIX}.spk"
tar -C "$WORK" -cf "$SPK" "${members[@]}"
tar -xOf "$SPK" package.tgz | tar -tzf - | grep -qx './ui/config'
echo "Built $SPK ($(du -h "$SPK" | cut -f1))"
