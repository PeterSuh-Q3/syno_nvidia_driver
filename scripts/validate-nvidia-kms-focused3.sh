#!/usr/bin/env bash
# Fail-closed checks for a focused3 diagnostic module archive. Run in the
# pinned Synology compiler image after build-nvidia-kms-focused3-in-container.
set -Eeuo pipefail

platform="${1:?usage: validate-nvidia-kms-focused3.sh <platform> <archive> }"
archive="${2:?usage: validate-nvidia-kms-focused3.sh <platform> <archive> }"
case "$platform" in
  epyc7002|epyc7003) ;;
  *) echo "unsupported platform: $platform" >&2; exit 2 ;;
esac

compat="/work/scripts/kms-compat/580.173.02/focused3"
symvers="$compat/$platform/provider-Module.symvers"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -xzf "$archive" -C "$tmp"

[[ "$(cat "$tmp/VERSION")" == 580.173.02 ]]
[[ "$(cat "$tmp/KVER")" == 5.10.55 ]]
[[ "$(cat "$tmp/PLATFORM")" == "$platform" ]]
[[ "$(/sbin/modinfo -F vermagic "$tmp/nvidia-drm.ko")" == 5.10.55* ]]
/sbin/modinfo -p "$tmp/nvidia-drm.ko" | grep -Eq '^modeset:.*\(bool\)'
[[ "$(/sbin/modinfo -F license "$tmp/nvidia.ko")" == NVIDIA ]]

nm -u "$tmp/nvidia-drm.ko" | awk 'NF { print $NF }' | LC_ALL=C sort -u \
  | awk '/^(drm_|__drm|___drm|dmabufbkpt_)/' > "$tmp/imports"
awk 'NF >= 2 { print $2 }' "$symvers" | LC_ALL=C sort -u > "$tmp/exports"
missing="$(comm -23 "$tmp/imports" "$tmp/exports")"
if [[ -n "$missing" ]]; then
  printf 'unresolved DRM/provider imports for %s:\n%s\n' "$platform" "$missing" >&2
  exit 20
fi
[[ -s "$tmp/imports" ]] || { echo 'no DRM imports found; refusing a stub module' >&2; exit 21; }

printf 'PASS platform=%s vermagic=%s modeset=yes provider-imports=%s\n' \
  "$platform" "$(/sbin/modinfo -F vermagic "$tmp/nvidia-drm.ko")" \
  "$(wc -l < "$tmp/imports" | tr -d ' ')"
