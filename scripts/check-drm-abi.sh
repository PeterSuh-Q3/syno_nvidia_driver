#!/usr/bin/env bash
# Verify that every DRM symbol imported by nvidia-drm.ko is exported by the
# exact DRM module pack that will be installed beside it.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <nvidia-drm.ko> <drm-provider-pack.tgz>" >&2
  exit 2
fi

KO=$1
PACK=$2
NM=${NM:-nm}

[ -s "$KO" ] || { echo "ERROR: missing NVIDIA DRM module: $KO" >&2; exit 2; }
[ -s "$PACK" ] || { echo "ERROR: missing DRM provider pack: $PACK" >&2; exit 2; }
command -v "$NM" >/dev/null 2>&1 || { echo "ERROR: nm not found: $NM" >&2; exit 2; }
tar -tzf "$PACK" >/dev/null || { echo "ERROR: invalid DRM provider archive: $PACK" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$PACK" -C "$TMP" --wildcards '*.ko'

imports=$("$NM" -u "$KO" | awk 'NF { print $NF }' | LC_ALL=C sort -u \
  | awk '/^(drm|__drm|___drm)/')
exports=$(
  find "$TMP" -type f -name '*.ko' -print0 \
    | while IFS= read -r -d '' module; do "$NM" -g --defined-only "$module" 2>/dev/null || true; done \
    | awk 'NF >= 2 && $(NF-1) ~ /^[A-Za-z]$/ { print $NF }' \
    | LC_ALL=C sort -u
)

missing=$(comm -23 <(printf '%s\n' "$imports") <(printf '%s\n' "$exports"))
if [ -n "$missing" ]; then
  echo "ERROR: nvidia-drm.ko imports DRM symbols absent from the selected provider pack:" >&2
  printf '  %s\n' $missing >&2
  echo "The module pack and NVIDIA DRM module are ABI-incompatible; do not package or install this combination." >&2
  exit 1
fi

echo "OK: every DRM symbol imported by nvidia-drm.ko is exported by $PACK"
