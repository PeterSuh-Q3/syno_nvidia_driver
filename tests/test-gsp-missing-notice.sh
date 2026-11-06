#!/bin/sh
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nvidia-gsp-notice.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Minimal .ko stand-ins: license= lives NUL-separated in .modinfo.
printf 'ELF\000license=NVIDIA\000vermagic=4.4.302+ SMP mod_unload \000' > "$TMP/proprietary.ko"
printf 'ELF\000license=Dual MIT/GPL\000vermagic=5.10.55+ SMP mod_unload \000' > "$TMP/open.ko"

eval "$(sed -n '/^module_license() {/,/^}/p' "$ROOT/spk/bin/nvidia-backend.sh")"
eval "$(sed -n '/^gsp_missing_notice() {/,/^}/p' "$ROOT/spk/bin/nvidia-backend.sh")"

[ "$(module_license "$TMP/proprietary.ko")" = "NVIDIA" ] || fail 'proprietary license not read'
[ "$(module_license "$TMP/open.ko")" = "Dual MIT/GPL" ] || fail 'open license not read'

# Proprietary module + Turing/Ampere: informational note on stdout, no warning.
for arch in Ampere Turing; do
  out="$(gsp_missing_notice 10de:25b0 "$arch" "$TMP/proprietary.ko" 2>"$TMP/err")"
  printf '%s\n' "$out" | grep -Fq "runs this GPU without GSP" || fail "no note for proprietary $arch: $out"
  [ ! -s "$TMP/err" ] || fail "unexpected warning for proprietary $arch: $(cat "$TMP/err")"
done

# Open module, or an architecture outside Turing/Ampere: original warning.
for case_ in "Ampere $TMP/open.ko" "Ada $TMP/proprietary.ko" "Hopper $TMP/proprietary.ko" "Ampere GA100|$TMP/proprietary.ko"; do
  case "$case_" in
    *"|"*) arch="${case_%%|*}"; ko="${case_#*|}" ;;
    *) arch="${case_%% *}"; ko="${case_#* }" ;;
  esac
  gsp_missing_notice 10de:0000 "$arch" "$ko" >/dev/null 2>"$TMP/err"
  grep -Fq "the GPU will not initialise" "$TMP/err" || fail "warning missing for $arch / $(basename "$ko")"
done

printf 'GSP missing-firmware notice tests passed.\n'
