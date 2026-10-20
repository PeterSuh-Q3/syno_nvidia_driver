#!/usr/bin/env bash
# Host-side orchestrator: run one fresh compiler container per remaining
# platform so the provider workflow's fixed /tmp/drm path cannot collide.
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
readonly IMAGE=dante90/syno-compiler:7.4
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly DUAL_REPO="${DUAL_GPU_BACKPORTS_REPO:-/Volumes/GITHUB/dual-gpu-backports}"
readonly PLATFORMS=(epyc7003 geminilakenk icelaked r1000nk v1000nk)

[[ -d "$ROOT/.git" ]] || { echo "Not a git checkout: $ROOT" >&2; exit 1; }
[[ -d "$DUAL_REPO/.git" ]] || { echo "Missing dual-gpu-backports checkout: $DUAL_REPO" >&2; exit 1; }
command -v docker >/dev/null || { echo 'docker CLI unavailable on host' >&2; exit 1; }
mkdir -p "$ROOT/out/build-logs/595-open-platforms"

failed=0
for platform in "${PLATFORMS[@]}"; do
  log="$ROOT/out/build-logs/595-open-platforms/${platform}-$(date -u +%Y%m%dT%H%M%SZ).log"
  printf '\n===== Fresh pinned container: 595 Open KMS %s =====\n' "$platform"
  if ! docker run --rm --privileged -u 0 \
      -e NV_BUILD_IMAGE_DIGEST="$IMAGE_DIGEST" \
      -v "$ROOT:/work" -v "$DUAL_REPO:/dual:ro" \
      "$IMAGE" bash /work/scripts/kms-compat/595.99.02/run-open-platform-in-container.sh "$platform" \
      2>&1 | tee "$log"; then
    printf '[595-open-expansion] FAILED: %s (log: %s)\n' "$platform" "$log" >&2
    failed=1
  fi
done

if ((failed)); then
  echo 'At least one platform failed; successful candidates remain isolated and unpromoted.' >&2
  exit 1
fi
echo 'All five remaining 595 Open candidates passed static validation; runtime KMS tests remain pending.'
