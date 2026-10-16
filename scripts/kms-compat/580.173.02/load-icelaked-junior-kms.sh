#!/bin/sh
# Run from root in the Junior TTYD shell after staging nv-ko.tgz and nv-gsp.tgz.
set -eu
SCRIPT_DIR=${0%/*}
exec /bin/sh "$SCRIPT_DIR/load-junior-kms-common.sh" \
  icelaked synology_icelaked_ 3606877153 90166210 \
  "${1:-/tmp/nv-icelaked-kms/nv-ko.tgz}" \
  "${2:-/tmp/nv-icelaked-kms/nv-gsp.tgz}" \
  "${3:-/tmp/nv-icelaked-kms/run}"
