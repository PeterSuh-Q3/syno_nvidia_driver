#!/usr/bin/env bash
# Fail if versioned, platform-independent layers were copied into build output.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
shared="$root/out/release-assets-nvidia/shared/"
bad=0
count=0
scan_dirs=()
for directory in "$root/out" "$root/work"; do
  [[ ! -d "$directory" ]] || scan_dirs+=("$directory")
done
if ((${#scan_dirs[@]} == 0)); then
  printf 'shared NVIDIA layers: no archives yet, no duplicates\n'
  exit 0
fi

while IFS= read -r -d '' archive; do
  if [[ "$archive" != "$shared"* ]]; then
    printf 'duplicate layer outside shared directory: %s\n' "$archive" >&2
    bad=1
    continue
  fi
  ((count += 1))
  if [[ "$archive" == *'/nv-userspace-'* ]]; then
    version=$(tar -xOzf "$archive" ./VERSION 2>/dev/null | tr -d '\r\n') || {
      printf 'unreadable userspace layer: %s\n' "$archive" >&2
      bad=1
      continue
    }
    [[ "${archive##*/}" == "nv-userspace-${version}.tgz" ]] || {
      printf 'userspace version mismatch: %s\n' "$archive" >&2
      bad=1
    }
  else
    tar -tzf "$archive" 2>/dev/null | grep -E '(^|/)gsp_[^/]+\.bin$' >/dev/null || {
      printf 'invalid GSP layer: %s\n' "$archive" >&2
      bad=1
    }
  fi
done < <(find "${scan_dirs[@]}" \( -name 'nv-userspace-*.tgz' -o -name 'nv-gsp-*.tgz' \) -print0)

((bad == 0)) || exit 1
printf 'shared NVIDIA layers: %d canonical archives, no duplicates\n' "$count"
