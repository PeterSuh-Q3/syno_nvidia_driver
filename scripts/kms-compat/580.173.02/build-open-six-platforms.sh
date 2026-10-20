#!/usr/bin/env bash
# Host orchestrator for 580 Open KMS candidates. Every platform gets a new,
# digest-pinned compiler container; Gemini Lake is deliberately built last.
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
readonly ROOT="$root_dir"
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly IMAGE="dante90/syno-compiler:7.4@${IMAGE_DIGEST}"
# Keep geminilakenk last: its provider-header/API compatibility path differs.
readonly PLATFORMS=(epyc7002 epyc7003 icelaked r1000nk v1000nk geminilakenk)

[[ -d "$ROOT/.git" ]] || { echo "Not a git checkout: $ROOT" >&2; exit 1; }
command -v docker >/dev/null || { echo 'docker CLI unavailable on host' >&2; exit 1; }
mkdir -p "$ROOT/out/build-logs/580-open-platforms"

failed=0
for platform in "${PLATFORMS[@]}"; do
  log="$ROOT/out/build-logs/580-open-platforms/${platform}-$(date -u +%Y%m%dT%H%M%SZ).log"
  printf '\n===== Fresh pinned container: 580 Open KMS %s =====\n' "$platform"
  if ! docker run --rm --privileged -u 0 \
      -e NV_BUILD_IMAGE_DIGEST="$IMAGE_DIGEST" \
      -v "$ROOT:/work" \
      "$IMAGE" bash /work/scripts/kms-compat/580.173.02/run-open-platform-in-container.sh "$platform" \
      2>&1 | tee "$log"; then
    printf '[580-open-kms] FAILED: %s (log: %s)\n' "$platform" "$log" >&2
    failed=1
  fi
done

if ((failed)); then
  echo 'At least one candidate failed; successful outputs remain isolated and unpromoted.' >&2
  exit 1
fi
echo 'All six 580 Open candidates passed static validation; physical KMS tests and promotion remain separate.'
