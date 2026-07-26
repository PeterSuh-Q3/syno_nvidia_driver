#!/usr/bin/env bash
#
# make-ffmpeg-layer.sh - build the OPTIONAL NVENC-capable ffmpeg layer.
#
# This layer is for the SynoCommunity Jellyfin *package* (its bundled ffmpeg has
# no NVENC) and for CLI use. Plex has its own NVENC transcoder and does not need
# it. It ships a jellyfin-ffmpeg pinned so its NVENC API matches the driver:
#
#   driver 5xx (NVENC 12.0/12.1)  ->  jellyfin-ffmpeg 6.0 / 7.0   (NVENC 12.x)
#   NEVER pair a newer ffmpeg (NVENC 12.2/13.x needs driver 570/610) with 535.
#
# Usage:
#   make-ffmpeg-layer.sh <driver_ver> <jellyfin_ffmpeg_tag>
#     e.g. make-ffmpeg-layer.sh 535.230.02 v6.0.1-8
#
# Output: out/nv-ffmpeg-<driver_ver>.tgz  (+ printed sha256 + index fragment)
# Then: gh release upload nvidia out/nv-ffmpeg-<driver>.tgz --repo .../syno_nvidia_driver
#       and paste the fragment's ffmpeg entry into nvidia-index.json.
set -euo pipefail
DRV="${1:?driver_ver e.g. 535.230.02}"
JF="${2:?jellyfin-ffmpeg tag e.g. v6.0.1-8}"
HERE="$(cd "$(dirname "$0")" && pwd)"; OUT="${OUT:-$HERE/out}"; mkdir -p "$OUT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

VER="${JF#v}"
URL="https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/${JF}/jellyfin-ffmpeg_${VER}_portable_linux64-gpl.tar.xz"
echo "[ffmpeg-layer] fetching $URL" >&2
curl -fkL -o "$WORK/jf.tar.xz" "$URL"
mkdir -p "$WORK/x"; tar -xJf "$WORK/jf.tar.xz" -C "$WORK/x"
FF="$(find "$WORK/x" -name ffmpeg -type f | head -1)"
FP="$(find "$WORK/x" -name ffprobe -type f | head -1)"
[ -n "$FF" ] || { echo "ffmpeg not found in tarball" >&2; exit 1; }

mkdir -p "$WORK/l/bin"; cp "$FF" "$WORK/l/bin/ffmpeg"; [ -n "$FP" ] && cp "$FP" "$WORK/l/bin/ffprobe"
chmod +x "$WORK/l/bin/"*
echo "jellyfin-ffmpeg ${VER} (portable linux64-gpl) - pinned for driver ${DRV}" > "$WORK/l/SOURCE"
TGZ="$OUT/nv-ffmpeg-${DRV}.tgz"
tar -C "$WORK/l" -czf "$TGZ" .
SHA="$(sha256sum "$TGZ" | cut -d' ' -f1)"
cat <<JSON

=== add to .platforms[<plat>].drivers["$DRV"] in nvidia-index.json ===
      "ffmpeg": { "file": "$(basename "$TGZ")", "sha256": "$SHA", "source": "jellyfin-ffmpeg ${VER}", "optional": true }
=== then: gh release upload nvidia $TGZ --repo PeterSuh-Q3/syno_nvidia_driver ===
JSON
