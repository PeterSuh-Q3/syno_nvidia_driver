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
DRM_REL="https://github.com/PeterSuh-Q3/mshell-modules/releases/download/26.10.13"
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
ENABLE_NVIDIA_DRM_MODESET=0
DISPLAYNAME="Synology NVIDIA Driver"

case "$VARIANT" in
  kver5-580-open)
    WORK="$ROOT/work/spk-kver5-580-open-rev2"
    DRIVER=580.173.02
    PACKAGE_REVISION=3
    KSUFFIX=51055
    PLATFORMS="$KVER5_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver5-580-open
    DISPLAYNAME="Synology NVIDIA Driver 580 open"
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=1
    KO_FLAVOR_PREFIX="open-"
    DESC="NVIDIA 580.173.02 open driver; CUDA API 13.0; GPU: Turing and Ampere (open-module support; Ada/Blackwell excluded by the bundled 580 GPU table); kernel 5.10.55. Offline platforms: ${PLATFORMS}. At startup, the package reselects the bundled module set for the detected platform and validates its kernel ABI; if the driver is already loaded after migration, reboot to activate the validated set."
    FILESUFFIX=""
    ;;
  kver5-580-proprietary)
    # Keep this revision's assembly tree separate from older builds.
    WORK="$ROOT/work/spk-kver5-580-proprietary-rev3"
    DRIVER=580.173.02
    PACKAGE_REVISION=4
    KSUFFIX=51055
    PLATFORMS="$KVER5_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver5-580-proprietary
    DISPLAYNAME="Synology NVIDIA Driver 580 Proprietary"
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=1
    KO_FLAVOR_PREFIX="proprietary-"
    ENABLE_NVIDIA_DRM_MODESET=1
    DESC="NVIDIA 580.173.02 proprietary driver; CUDA API 13.0; Maxwell-through-Ampere GPUs in the bundled compatibility table; kernel 5.10.55. Includes the six-platform quad DRM provider bundle. Required DRM dependencies are loaded before NVIDIA DRM; bundled i915, amdgpu and virtual GPU drivers are not force-loaded. KMS enabled: ${PLATFORMS}. At startup, the package reselects the detected platform's module set and verifies its kernel ABI; reboot after migration when NVIDIA modules are already resident."
    FILESUFFIX=""
    ;;
  kver5-595-open)
    WORK="$ROOT/work/spk-kver5-595-open"
    DRIVER=595.99.02
    PACKAGE_REVISION=2
    KSUFFIX=51055
    PLATFORMS="$KVER5_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver5-595-open
    DISPLAYNAME="Synology NVIDIA Driver 595 open"
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=1
    KO_FLAVOR_PREFIX="open-"
    DESC="NVIDIA 595.99.02 open driver; CUDA API 13.2; GPU: Turing and newer (as listed by the bundled GPU support table); kernel 5.10.55. Offline platforms: ${PLATFORMS}. At startup, the package reselects the detected platform's module set and validates its kernel ABI; if NVIDIA modules are already loaded after migration, reboot to activate the validated set."
    FILESUFFIX=""
    ;;
  kver5-595-proprietary)
    WORK="$ROOT/work/spk-kver5-595-proprietary"
    DRIVER=595.99.02
    PACKAGE_REVISION=2
    KSUFFIX=51055
    PLATFORMS="$KVER5_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver5-595-proprietary
    DISPLAYNAME="Synology NVIDIA Driver 595 proprietary"
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=1
    KO_FLAVOR_PREFIX="proprietary-"
    DESC="NVIDIA 595.99.02 proprietary driver; CUDA API 13.2; GPU: Turing and newer (as listed by the bundled GPU support table); kernel 5.10.55. Offline platforms: ${PLATFORMS}. This is the proprietary flavor with its own package ID and GPU compatibility pre-check. At startup, the package reselects the detected platform's module set and validates its kernel ABI; if NVIDIA modules are already loaded after migration, reboot to activate the validated set."
    FILESUFFIX=""
    ;;
  kver5)
    echo "The unsplit kver5 package ID is retired from the active package catalog; use the flavor-specific 580/595 variants." >&2
    exit 2
    ;;
  kver4-72)
    PACKAGE_REVISION=5
    DRIVER=550.163.01
    KSUFFIX=44302
    PLATFORMS="$KVER4_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver4-dsm72
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=0
    DESC="NVIDIA driver (kernel 4.4.302, DSM 7.2-7.4, driver ${DRIVER}). Bundled offline for: ${PLATFORMS}. Startup selects the current platform's modules only when their bundled kernel ABI matches; after migration with NVIDIA modules loaded, reboot to activate the selected set."
    FILESUFFIX="-dsm7.2-7.4"
    ;;
  kver4-70)
    PACKAGE_REVISION=5
    DRIVER=550.163.01
    KSUFFIX=44180
    PLATFORMS="$KVER4_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver4-dsm70
    OS_MIN_VER=7.0-00000
    BUNDLE_GSP=0
    DESC="NVIDIA driver (kernel 4.4.180, DSM 7.0-7.1, driver ${DRIVER}). Bundled offline for: ${PLATFORMS}. Startup selects the current platform's modules only when their bundled kernel ABI matches; after migration with NVIDIA modules loaded, reboot to activate the selected set."
    FILESUFFIX="-dsm7.0-7.1"
    ;;
  *) echo "Unknown variant: $VARIANT (expected kver5-580-open | kver5-580-proprietary | kver5-595-open | kver5-595-proprietary | kver4-72 | kver4-70)" >&2; exit 2 ;;
esac

# Keep migration candidates isolated from existing SPKs and assembly trees.
if [[ "${PLATFORM_MIGRATION_BUILD:-0}" == 1 ]]; then
  WORK="$ROOT/work/platform-migration-$VARIANT"
fi

# Wipe everything except dl/ (the downloaded release assets) so re-running
# after an INFO/script fix doesn't re-pull ~500MB-900MB over the network.
rm -rf "$WORK/target" "$WORK/scripts" "$WORK/conf" "$WORK/INFO" "$WORK"/*.PNG
mkdir -p "$WORK/target/lib/modules" "$WORK/target/lib/nvidia/bin" "$WORK/target/lib/nvidia/lib" \
         "$WORK/target/lib/firmware" "$WORK/target/share" "$WORK/scripts" "$WORK/conf" "$WORK/dl"
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
  fetch "$KO"
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

# ---- matching quad-DRM provider archives (580 proprietary K5 only) -------
# Preserve each upstream archive whole in the SPK. At runtime the backend
# extracts only the active platform's pack into a package-private kmod tree;
# it never overlays the system module directory or force-loads GPU drivers.
if [ "$VARIANT" = "kver5-580-proprietary" ]; then
  DRM_CACHE="$ROOT/work/kver5-580-proprietary-quad-drm-26.10.13"
  DRM_STAGE="$WORK/target/lib/drm-provider"
  mkdir -p "$DRM_STAGE" "$DRM_CACHE"
  while read -r platform sha; do
    [ -n "$platform" ] || continue
    asset="${platform}-7.4-5.10.55-drm.tgz"
    src="$DRM_CACHE/$asset"
    if [ ! -s "$src" ]; then
      tmp="$src.tmp.$$"
      echo "fetching pinned quad DRM provider $asset"
      curl -sL --fail "$DRM_REL/$asset" -o "$tmp"
      mv "$tmp" "$src"
    fi
    actual=$(shasum -a 256 "$src" | awk '{print $1}')
    [ "$actual" = "$sha" ] || {
      echo "quad DRM provider checksum mismatch for $asset: expected $sha, got $actual" >&2
      exit 1
    }
    tar -tzf "$src" | grep -qx 'drm.ko' || { echo "invalid DRM archive: $asset" >&2; exit 1; }
    tar -tzf "$src" | grep -qx 'drm_kms_helper.ko' || { echo "missing drm_kms_helper.ko: $asset" >&2; exit 1; }
    cp "$src" "$DRM_STAGE/$asset"
  done <<'DRM_ASSETS'
epyc7002 5d9b7e5473102106859740bc329a94323635cf4c3ae0c51a5c6a6916bc424cf9
epyc7003 722669eb04384dea78ae7aeec75aaa039e2582e352af5536a447e50ef54cdd1f
geminilakenk 5f7d81c6e511c8e5db7d471bcf44e30d156643c9f14b6a1c43a76db967dfed92
icelaked 5c0960e5eb598c80df07cf2a17714ba9ebd274a8a944efb070112da81388010d
r1000nk 424d51a8b2f4b912da6e11f006762447ad5128e7d568705a32ec04e3c9a41b17
v1000nk b9fadf760f40ff7916f948521a8667da86f145e6797c5b099b8f545ac5812f0a
DRM_ASSETS
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
  -e "s#^description=\".*\"#description=\"$DESC\"#" \
  "$WORK/INFO"
rm -f "$WORK/INFO.bak"
VERSION=$(sed -n 's/^version="\([^"]*\)"$/\1/p' "$WORK/INFO" | head -1)

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
SPK="$OUT/${PACKAGE}-${VERSION}${FILESUFFIX}.spk"
tar -C "$WORK" -cf "$SPK" "${members[@]}"
echo "Built $SPK ($(du -h "$SPK" | cut -f1))"
