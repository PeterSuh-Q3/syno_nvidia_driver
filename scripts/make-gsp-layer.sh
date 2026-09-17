#!/usr/bin/env bash
# Extract NVIDIA-supplied GSP firmware from a Linux .run installer and package
# it as the release asset consumed by scripts/build-spk.sh.
#
# GSP firmware is a signed NVIDIA binary and is never compiled here.  The
# resulting archive intentionally contains gsp_*.bin files at its top level:
# build-spk.sh expands it directly into target/lib/firmware, where the SPK
# backend expects them.
#
# Usage:
#   scripts/make-gsp-layer.sh <driver-version> [run-file] [output-directory]
#
# Example:
#   scripts/make-gsp-layer.sh 595.99.02
#
# Defaults:
#   run-file         run/NVIDIA-Linux-x86_64-<driver-version>.run
#   output-directory out

set -euo pipefail

DRIVER=${1:?driver version required, e.g. 595.99.02}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN_FILE=${2:-"$ROOT/run/NVIDIA-Linux-x86_64-${DRIVER}.run"}
OUT=${3:-"$ROOT/out"}
ARCHIVE="$OUT/nv-gsp-${DRIVER}.tgz"

log() { printf '[make-gsp-layer] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

[ -f "$RUN_FILE" ] || die "NVIDIA .run not found: $RUN_FILE"
command -v sha256sum >/dev/null 2>&1 || die 'sha256sum is required'
command -v tar >/dev/null 2>&1 || die 'tar is required'

mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
EXTRACTED="$WORK/nvidia-run"
STAGE="$WORK/stage"
mkdir -p "$STAGE"

log "extracting $(basename "$RUN_FILE")"
sh "$RUN_FILE" --extract-only --target "$EXTRACTED" >/dev/null

# NVIDIA has used firmware/ in current Linux .run packages, but locate by name
# rather than relying on that implementation detail.  Keep the archive flat so
# it can be expanded directly into lib/firmware by build-spk.sh.
FOUND=0
while IFS= read -r -d '' firmware; do
  name=$(basename "$firmware")
  destination="$STAGE/$name"
  if [ -e "$destination" ] && ! cmp -s "$firmware" "$destination"; then
    die "conflicting firmware files named $name in the .run archive"
  fi
  cp -p "$firmware" "$destination"
  FOUND=$((FOUND + 1))
done < <(find "$EXTRACTED" -type f -name 'gsp_*.bin' -print0 | sort -z)

[ "$FOUND" -gt 0 ] || die "no gsp_*.bin firmware found in $RUN_FILE"

tar -C "$STAGE" -czf "$ARCHIVE" .
log "created $ARCHIVE"
log 'firmware payload:'
for firmware in "$STAGE"/gsp_*.bin; do
  log "  $(basename "$firmware")  $(sha256sum "$firmware" | awk '{print $1}')"
done
log "archive sha256: $(sha256sum "$ARCHIVE" | awk '{print $1}')"
log 'next: upload this archive to the nvidia release, then register its name,'
log 'sha256, and supported firmware file names in nvidia-gpu-support.json.'
