#!/bin/sh
# Run from root in the Junior TTYD shell after staging nv-ko.tgz and nv-gsp.tgz.
set -eu
SCRIPT_DIR=${0%/*}
exec /bin/sh "$SCRIPT_DIR/load-junior-kms-common.sh" \
  v1000nk synology_v1000nk_ 864644449 90165769 \
  "${1:-/tmp/nv-v1000nk-kms/nv-ko.tgz}" \
  "${2:-/tmp/nv-v1000nk-kms/nv-gsp.tgz}" \
  "${3:-/tmp/nv-v1000nk-kms/run}"
