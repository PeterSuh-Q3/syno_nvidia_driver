#!/bin/sh
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nvidia-recovery-notification.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Use echo as a harmless stand-in to verify the exact synodsmnotify arguments.
DSM_NOTIFY=/bin/echo
PACKAGE_ID=syno-nvidia-driver-kver5-595-proprietary
RCLOG="$TMP/notification.log"
eval "$(sed -n '/^rclog(){/p' "$ROOT/spk/bin/nvidia-backend.sh")"
eval "$(sed -n '/^notify_module_recovery() {/,/^}/p' "$ROOT/spk/bin/nvidia-backend.sh")"

notify_module_recovery recovered epyc7002 5.10.55+
grep -Fq -- "-c SYNO.SDS._ThirdParty.App.$PACKAGE_ID -l info @administrators" "$RCLOG" \
  || fail 'success notification did not use the package notification class and target DSM administrators'
grep -Fq "$PACKAGE_ID:notification:module_recovered epyc7002 5.10.55+" "$RCLOG" \
  || fail 'success notification did not use its localized message key and recovery parameters'

: > "$RCLOG"
notify_module_recovery reboot epyc7002 5.10.55+
grep -Fq -- "-c SYNO.SDS._ThirdParty.App.$PACKAGE_ID -l warn @administrators" "$RCLOG" \
  || fail 'reboot-required notification did not use warning severity'
grep -Fq "$PACKAGE_ID:notification:module_reboot_required epyc7002 5.10.55+" "$RCLOG" \
  || fail 'reboot-required notification omitted the localized next-action key'

: > "$RCLOG"
notify_module_recovery failed epyc7002 5.10.55+
grep -Fq -- "-c SYNO.SDS._ThirdParty.App.$PACKAGE_ID -l error @administrators" "$RCLOG" \
  || fail 'failure notification did not use error severity'
grep -Fq "$PACKAGE_ID:notification:module_recovery_failed epyc7002 5.10.55+" "$RCLOG" \
  || fail 'failure notification omitted its localized diagnostic key'

printf 'NVIDIA recovery notification tests passed.\n'
