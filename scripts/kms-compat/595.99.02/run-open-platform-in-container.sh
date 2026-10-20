#!/usr/bin/env bash
# In-container runner for exactly one 595 Open platform. Must run in a fresh,
# digest-pinned dante90/syno-compiler:7.4 container.
set -Eeuo pipefail

readonly ROOT=/work
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly FLEX_VERSION=2.6.4-8.2
readonly BISON_VERSION='2:3.8.2+dfsg-1+b1'
platform=${1:?usage: run-open-platform-in-container.sh <platform>}
case "$platform" in
  epyc7003|geminilakenk|icelaked|r1000nk|v1000nk) ;;
  *) echo "Unsupported remaining K5 platform: $platform" >&2; exit 2 ;;
esac

[[ "${NV_BUILD_IMAGE_DIGEST:-}" == "$IMAGE_DIGEST" ]] || {
  echo 'Compiler image digest mismatch' >&2
  exit 1
}

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  "flex=$FLEX_VERSION" "bison=$BISON_VERSION"
[[ "$(dpkg-query -W -f='${Version}' flex)" == "$FLEX_VERSION" ]]
[[ "$(dpkg-query -W -f='${Version}' bison)" == "$BISON_VERSION" ]]

readonly run_id="$(date -u +%Y%m%dT%H%M%SZ)"
readonly evidence_dir="$ROOT/out/kms-expansion/kver5-595-open/dependencies"
mkdir -p "$evidence_dir"
{
  printf 'platform=%s\n' "$platform"
  printf 'compiler_image=dante90/syno-compiler:7.4@%s\n' "$IMAGE_DIGEST"
  printf 'flex=%s\n' "$(dpkg-query -W -f='${Version}' flex)"
  printf 'bison=%s\n' "$(dpkg-query -W -f='${Version}' bison)"
} | tee "$evidence_dir/${platform}-${run_id}.txt"

# A fresh container is essential: build-unified-drm.sh creates fixed /tmp/drm.
bash "$ROOT/scripts/kms-compat/595.99.02/prepare-open-provider-platform.sh" "$platform"
out_dir="$ROOT/out/kms-expansion/kver5-595-open/${platform}-${run_id}"
bash "$ROOT/scripts/kms-compat/595.99.02/build-open-platform-pilot.sh" "$platform" "$out_dir"
