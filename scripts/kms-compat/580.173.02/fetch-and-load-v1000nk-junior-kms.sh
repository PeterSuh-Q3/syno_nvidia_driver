#!/bin/sh
# Fetch the pinned v1000nk KMS pilot and loader files from the Mac's temporary
# HTTP servers, then run the guarded loader in the Junior TTYD root shell.
set -eu

SERVER_HOST=${1:?usage: sh fetch-and-load-v1000nk-junior-kms.sh <mac-lan-ip>}
SCRIPT_PORT=${SCRIPT_PORT:-18766}
ARTIFACT_PORT=${ARTIFACT_PORT:-18765}
ROOT=/tmp/nv-v1000nk-kms
VERSION_DIR=scripts/kms-compat/580.173.02
MODULE_PATH=kms-580-proprietary-fullheaders-20261016/v1000nk/nv-ko-580.173.02-proprietary-v1000nk-51055.tgz
GSP_PATH=release-assets-nvidia/shared/580/nv-gsp-580.173.02.tgz

synoinfo=/etc/synoinfo.conf
[ -r "$synoinfo" ] || synoinfo=/etc.defaults/synoinfo.conf
[ -r "$synoinfo" ] || { echo "ERROR: Cannot read Synology platform identity." >&2; exit 1; }
grep -Eq '^unique="synology_v1000nk_' "$synoinfo" || { echo "ERROR: This is not a v1000nk system." >&2; exit 1; }
[ "$(uname -r)" = "5.10.55+" ] || { echo "ERROR: Expected kernel 5.10.55+." >&2; exit 1; }
uid_record=$(grep '^Uid:' /proc/self/status)
set -- $uid_record
[ "${2:-unknown}" = 0 ] || { echo "ERROR: Run from the root Junior TTYD shell." >&2; exit 1; }
if grep -Eq '^(drm|drm_kms_helper|drm_mipi_dsi|i915|i915_compat|nvidia|nvidia_modeset|nvidia_drm|nvidia_uvm)[[:space:]]' /proc/modules; then
  echo "ERROR: DRM/i915/NVIDIA modules are already loaded; reboot to a clean Junior state first." >&2
  exit 1
fi
[ ! -e /dev/dri ] || { echo "ERROR: /dev/dri already exists; refusing a non-clean KMS test." >&2; exit 1; }
[ ! -e /dev/nvidia0 ] || { echo "ERROR: /dev/nvidia0 already exists; refusing a non-clean NVIDIA test." >&2; exit 1; }

if [ -x /usr/bin/curl ]; then CURL=/usr/bin/curl
elif [ -x /bin/curl ]; then CURL=/bin/curl
else echo "ERROR: curl is unavailable." >&2; exit 1; fi

mkdir -p "$ROOT"
fetch() {
  url=$1
  destination=$2
  "$CURL" -fL --retry 2 --connect-timeout 10 -o "$destination" "$url"
}

fetch "http://$SERVER_HOST:$SCRIPT_PORT/$VERSION_DIR/load-v1000nk-junior-kms.sh" "$ROOT/load-v1000nk-junior-kms.sh"
fetch "http://$SERVER_HOST:$SCRIPT_PORT/$VERSION_DIR/load-junior-kms-common.sh" "$ROOT/load-junior-kms-common.sh"
fetch "http://$SERVER_HOST:$ARTIFACT_PORT/$MODULE_PATH" "$ROOT/nv-ko.tgz"
fetch "http://$SERVER_HOST:$ARTIFACT_PORT/$GSP_PATH" "$ROOT/nv-gsp.tgz"
chmod +x "$ROOT/load-v1000nk-junior-kms.sh" "$ROOT/load-junior-kms-common.sh"
exec /bin/sh "$ROOT/load-v1000nk-junior-kms.sh"
