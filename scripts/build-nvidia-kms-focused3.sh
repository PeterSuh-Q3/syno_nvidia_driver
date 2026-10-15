#!/usr/bin/env bash
# Host-side launcher for one focused3 diagnostic build in the pinned image.
# Output is a local candidate only; nothing is copied to release-assets-nvidia.
set -Eeuo pipefail

platform="${1:?usage: scripts/build-nvidia-kms-focused3.sh <epyc7002|epyc7003> }"
case "$platform" in
  epyc7002|epyc7003) ;;
  *) echo "unsupported platform: $platform" >&2; exit 2 ;;
esac

readonly root="$(cd "$(dirname "$0")/.." && pwd)"
readonly image="dante90/syno-compiler@sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f"
readonly run_file="$root/run/NVIDIA-Linux-x86_64-580.173.02.run"
readonly expected_run_sha="8d8eb9001e05a9a8a663d3d5d304feb64ef2844ee185ccdfd952786820f46e1b"

[[ -s "$run_file" ]] || { echo "missing NVIDIA installer: $run_file" >&2; exit 10; }
actual_run_sha="$(shasum -a 256 "$run_file" | awk '{print $1}')"
[[ "$actual_run_sha" == "$expected_run_sha" ]] || {
  echo "NVIDIA .run SHA-256 mismatch: expected $expected_run_sha, got $actual_run_sha" >&2
  exit 11
}
docker info >/dev/null || { echo 'Docker engine is unavailable' >&2; exit 12; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_rel="out/kms-focused3-repro/$stamp/$platform"
mkdir -p "$root/$out_rel"

docker run --rm --privileged -u 0 \
  -v "$root:/work" \
  "$image" \
  bash /work/scripts/build-nvidia-kms-focused3-in-container.sh "$platform" "/work/$out_rel" \
  2>&1 | tee "$root/$out_rel/build.log"

archive="$root/$out_rel/nv-ko-580.173.02-proprietary-${platform}-51055.tgz"
docker run --rm --entrypoint /bin/bash -v "$root:/work:ro" "$image" \
  /work/scripts/validate-nvidia-kms-focused3.sh "$platform" "/work/$out_rel/$(basename "$archive")"

printf 'Diagnostic candidate: %s\n' "$archive"
printf 'SHA-256: %s\n' "$(shasum -a 256 "$archive" | awk '{print $1}')"
printf 'This is not a release promotion or a claim of device runtime validation.\n'
