#!/bin/sh
# Run from root in the Junior TTYD shell after staging nv-ko.tgz and nv-gsp.tgz.
set -eu
SCRIPT_DIR=${0%/*}
exec /bin/sh "$SCRIPT_DIR/load-junior-kms-common.sh" \
  epyc7003 synology_epyc7003_ 1575489399 90167458 \
  "${1:-/tmp/nv-epyc7003-kms/nv-ko.tgz}" \
  "${2:-/tmp/nv-epyc7003-kms/nv-gsp.tgz}" \
  "${3:-/tmp/nv-epyc7003-kms/run}"
