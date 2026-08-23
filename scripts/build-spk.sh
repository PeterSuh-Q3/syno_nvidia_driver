#!/usr/bin/env bash
# Build one of the three offline .spk variants by downloading the already-
# published GitHub Release assets (from the pinned "nvidia" tag - see
# install.sh's REPO_RAW) and repacking them into DSM's package format,
# following the same INFO-templating / package.tgz / final-tar pattern as
# syno-amdgpu-driver/scripts/package-spk.sh.
#
# Usage: build-spk.sh <kver5|kver4-72|kver4-70>
set -euo pipefail

VARIANT=${1:?variant required: kver5 | kver4-72 | kver4-70}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REL="https://github.com/PeterSuh-Q3/syno_nvidia_driver/releases/download/nvidia"
OUT="$ROOT/dist"
WORK="$ROOT/work/spk-$VARIANT"

# ---- per-variant configuration ---------------------------------------------
# Platform lists and kernel-suffix/file-naming convention come straight from
# tcrp-addons/nvidiadriver/src/nvidia-index.json (pinned commit
# 40df760c9ebeafac00b8c61149c2b4dfe6141d1c, the same one install.sh reads).
KVER5_PLATFORMS="epyc7002 epyc7003 epyc7003ntb geminilakenk icelaked r1000nk v1000nk"
KVER4_PLATFORMS="apollolake broadwell broadwellnk broadwellnkv2 broadwellntbap geminilake purley r1000 v1000"

case "$VARIANT" in
  kver5)
    DRIVER=580.173.02
    KSUFFIX=51055
    PLATFORMS="$KVER5_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver5
    OS_MIN_VER=7.2-00000
    # Turing+ (GA10x/TU10x) is the class this branch/platform set targets.
    BUNDLE_GSP=1
    DESC="NVIDIA driver (kernel 5.10.55 platforms, driver ${DRIVER}). Bundled offline for: ${PLATFORMS}."
    FILESUFFIX=""
    ;;
  kver4-72)
    DRIVER=550.163.01
    KSUFFIX=44302
    PLATFORMS="$KVER4_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver4-dsm72
    OS_MIN_VER=7.2-00000
    BUNDLE_GSP=0
    DESC="NVIDIA driver (kernel 4.4.302, DSM 7.2-7.4, driver ${DRIVER}). Bundled offline for: ${PLATFORMS}."
    FILESUFFIX="-dsm7.2-7.4"
    ;;
  kver4-70)
    DRIVER=550.163.01
    KSUFFIX=44180
    PLATFORMS="$KVER4_PLATFORMS"
    PACKAGE=syno-nvidia-driver-kver4-dsm70
    OS_MIN_VER=7.0-00000
    BUNDLE_GSP=0
    DESC="NVIDIA driver (kernel 4.4.180, DSM 7.0-7.1, driver ${DRIVER}). Bundled offline for: ${PLATFORMS}."
    FILESUFFIX="-dsm7.0-7.1"
    ;;
  *) echo "Unknown variant: $VARIANT (expected kver5 | kver4-72 | kver4-70)" >&2; exit 2 ;;
esac

# Wipe everything except dl/ (the downloaded release assets) so re-running
# after an INFO/script fix doesn't re-pull ~500MB-900MB over the network.
rm -rf "$WORK/target" "$WORK/scripts" "$WORK/conf" "$WORK/INFO" "$WORK"/*.PNG
mkdir -p "$WORK/target/lib/modules" "$WORK/target/lib/nvidia/bin" "$WORK/target/lib/nvidia/lib" \
         "$WORK/target/lib/firmware" "$WORK/target/share" "$WORK/scripts" "$WORK/conf" "$WORK/dl"

fetch() {
  local file=$1
  [ -f "$WORK/dl/$file" ] && return 0
  echo "fetching $file"
  curl -sL --fail "$REL/$file" -o "$WORK/dl/$file"
}

# ---- kernel modules (one nv-ko tgz per platform, this variant's kernel) ----
for p in $PLATFORMS; do
  KO="nv-ko-${DRIVER}-${p}-${KSUFFIX}.tgz"
  fetch "$KO"
  mkdir -p "$WORK/target/lib/modules/$p"
  tar -xzf "$WORK/dl/$KO" -C "$WORK/target/lib/modules/$p"
done

# ---- shared userspace (one tgz, identical across platforms in a variant) --
US="nv-userspace-${DRIVER}.tgz"
fetch "$US"
tar -xzf "$WORK/dl/$US" -C "$WORK/target/lib/nvidia"

# ---- GSP firmware (kver5/580 only - no gsp_fw entries exist for 550) ------
if [ "$BUNDLE_GSP" = 1 ]; then
  GSP="nv-gsp-${DRIVER}.tgz"
  fetch "$GSP"
  tar -xzf "$WORK/dl/$GSP" -C "$WORK/target/lib/firmware"
fi

# ---- bundled GPU-support table (offline copy, not live-fetched) -----------
# Pinned to the same tcrp-addons commit install.sh reads (see its SUP_URL) so
# a package built today and one built after a future gpu-support.json update
# resolve to the same table until this SHA is deliberately bumped.
curl -sL --fail "https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/40df760c9ebeafac00b8c61149c2b4dfe6141d1c/nvidiadriver/src/nvidia-gpu-support.json" \
  -o "$WORK/target/share/nvidia-gpu-support.json"

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
  -e "s/^version=\"[^\"]*\"/version=\"${DRIVER}-1\"/" \
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
