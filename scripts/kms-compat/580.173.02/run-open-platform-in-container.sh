#!/usr/bin/env bash
# One-platform runner. Invoked in a fresh pinned DSM 7.4 compiler container.
set -Eeuo pipefail

readonly ROOT=/work
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly FLEX_VERSION=2.6.4-8.2
readonly BISON_VERSION='2:3.8.2+dfsg-1+b1'
platform=${1:?usage: run-open-platform-in-container.sh <platform>}
case "$platform" in
  epyc7002|epyc7003|icelaked|r1000nk|v1000nk|geminilakenk) ;;
  *) echo "Unsupported K5 platform: $platform" >&2; exit 2 ;;
esac
[[ "${NV_BUILD_IMAGE_DIGEST:-}" == "$IMAGE_DIGEST" ]] || {
  echo 'Compiler image digest mismatch' >&2
  exit 1
}

# Record these exact prerequisites in each disposable build container. This
# also prevents a future provider-preparation step from silently lacking them.
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  "flex=$FLEX_VERSION" "bison=$BISON_VERSION"
[[ "$(dpkg-query -W -f='${Version}' flex)" == "$FLEX_VERSION" ]]
[[ "$(dpkg-query -W -f='${Version}' bison)" == "$BISON_VERSION" ]]

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
readonly run_id
readonly evidence_dir="$ROOT/out/kms-expansion/kver5-580-open/dependencies"
mkdir -p "$evidence_dir"
{
  printf 'platform=%s\n' "$platform"
  printf 'compiler_image=dante90/syno-compiler:7.4@%s\n' "$IMAGE_DIGEST"
  printf 'flex=%s\n' "$(dpkg-query -W -f='${Version}' flex)"
  printf 'bison=%s\n' "$(dpkg-query -W -f='${Version}' bison)"
  printf 'provider_inputs=out/kms-expansion/inputs/%s-26.10.15-provider-build\n' "$platform"
} | tee "$evidence_dir/${platform}-${run_id}.txt"

out_dir="$ROOT/out/kms-expansion/kver5-580-open/${platform}-${run_id}"
bash "$ROOT/scripts/kms-compat/580.173.02/build-open-platform-candidate.sh" "$platform" "$out_dir"
