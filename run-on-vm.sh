#!/usr/bin/env bash
#
# run-on-vm.sh - Host-side wrapper: build the NVIDIA layers inside the
# dante90/syno-compiler container, mirroring mshell-modules' `docker run`.
#
# Run this ON the build VM (192.168.45.139), from this build project dir, e.g.:
#   ssh dante90@192.168.45.139
#   cd /path/to/nvidiadriver/build
#   ./run-on-vm.sh 535.183.06 epyc7002 7.4        # <ver> <platform> <DSM_VER>
#
# Prereqs on the VM:
#   - ./run/NVIDIA-Linux-x86_64-<ver>.run present (download once)
#   - sudo docker available (dante90 not in docker group -> sudo, NOPASSWD set)
#
set -euo pipefail
DRV="${1:?driver_ver e.g. 535.183.06}"
PLATFORM="${2:?platform e.g. epyc7002}"
DSM_VER="${3:-7.4}"            # picks the compiler image tag
KVER="${4:-5.10.55}"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ -f "$HERE/run/NVIDIA-Linux-x86_64-${DRV}.run" ] || {
  echo "ERROR: put NVIDIA-Linux-x86_64-${DRV}.run in $HERE/run/" >&2; exit 1; }
mkdir -p "$HERE/out"

SUDO=""; docker info >/dev/null 2>&1 || SUDO="sudo"
$SUDO docker run --rm -t --privileged -u 0 \
  -v "$HERE":/work \
  "dante90/syno-compiler:${DSM_VER}" \
  bash /work/build-nvidia.sh "$DRV" "$PLATFORM" "$KVER"

echo "Artifacts in $HERE/out :"
ls -la "$HERE/out"
