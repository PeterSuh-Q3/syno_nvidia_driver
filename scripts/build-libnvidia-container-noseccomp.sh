#!/usr/bin/env bash
# Build NVIDIA libnvidia-container v1.19.1 for CentOS 7 ABI without seccomp.
# DSM's seccomp implementation rejects the ldconfig hook's syscall filter.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$ROOT/work/libnvidia-container-noseccomp-v1.19.1"
SOURCE="$WORK/source"
OUTPUT="$WORK/output"
UPSTREAM=https://github.com/NVIDIA/libnvidia-container.git
REVISION=7585946c6471402577e14474d7c56ca5be0348d7
RPM=libnvidia-container1-1.19.1-1.x86_64.rpm
IMAGE=nvidia/libnvidia-container/centos7-x86_64

mkdir -p "$WORK" "$OUTPUT"
if [ ! -d "$SOURCE/.git" ] || [ "$(git -C "$SOURCE" rev-parse HEAD 2>/dev/null || true)" != "$REVISION" ]; then
  rm -rf "$SOURCE"
  git init -q "$SOURCE"
  git -C "$SOURCE" remote add origin "$UPSTREAM"
  git -C "$SOURCE" fetch -q --depth 1 origin "$REVISION"
  git -C "$SOURCE" checkout -q --detach FETCH_HEAD
fi

# Upstream's make preflight uses GNU date flags; normalize that one timestamp
# expression for the macOS host that invokes Docker Desktop.
perl -0pi -e 's/date -u --iso-8601=minutes/date -u +%Y-%m-%dT%H:%M%z/' "$SOURCE/mk/common.mk"

make -C "$SOURCE" centos7-x86_64 WITH_SECCOMP=no LIB_VERSION=1.19.1 >&2

RPM_DIR="$SOURCE/dist/centos7/x86_64"
test -s "$RPM_DIR/$RPM"
rm -rf "$OUTPUT/usr"
mkdir -p "$OUTPUT"
docker run --rm \
  -v "$RPM_DIR:/input:ro" \
  -v "$OUTPUT:/out" \
  "$IMAGE" sh -ec \
  'cd /out && rpm2cpio "/input/'"$RPM"'" | cpio -id --quiet ./usr/lib64/libnvidia-container.so.1.19.1'

BUILT_LIB="$OUTPUT/usr/lib64/libnvidia-container.so.1.19.1"
test -s "$BUILT_LIB"
strings "$BUILT_LIB" | grep -Fq 'seccomp is disabled, all syscalls are allowed'
if strings "$BUILT_LIB" | grep -Fq 'syscall limiting failed'; then
  echo "Unexpected seccomp-enabled library output: $BUILT_LIB" >&2
  exit 1
fi
if docker run --rm -v "$OUTPUT:/out:ro" "$IMAGE" sh -ec \
  'readelf -d /out/usr/lib64/libnvidia-container.so.1.19.1 | grep -q "libseccomp.so.2"'; then
  echo "Unexpected libseccomp dependency in built library: $BUILT_LIB" >&2
  exit 1
fi

printf '%s\n' "$BUILT_LIB"
