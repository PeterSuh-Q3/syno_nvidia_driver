#!/bin/sh
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nvidia-preinst-dva.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Run a copy of preinst next to a stub GPU guard, so the test only exercises
# the model check and never probes real PCI devices.
cp "$ROOT/spk/scripts/preinst" "$TMP/preinst"
printf '#!/bin/sh\necho GUARD-REACHED\n' > "$TMP/nvidia-gpu-guard.sh"
chmod +x "$TMP/preinst" "$TMP/nvidia-gpu-guard.sh"

for model in dva3221 dva3219; do
  out="$(NVIDIA_UNAME_A="Linux DVA 4.4.302+ #1 SMP x86_64 GNU/Linux synology_denverton_$model" \
    "$TMP/preinst" 2>&1)" && fail "preinst accepted $model"
  printf '%s\n' "$out" | grep -Fq "$model ships Synology's own NVIDIA driver" \
    || fail "missing DVA refusal message for $model: $out"
done

LOG="$TMP/install.log"
NVIDIA_UNAME_A="Linux DVA 4.4.302+ #1 SMP x86_64 GNU/Linux synology_denverton_dva3221" \
  SYNOPKG_TEMP_LOGFILE="$LOG" SYNOPKG_DSM_LANGUAGE=krn "$TMP/preinst" >/dev/null 2>&1 \
  && fail 'preinst accepted dva3221 (krn)'
grep -Fq 'dva3221 모델은' "$LOG" || fail 'Korean refusal message not written to SYNOPKG_TEMP_LOGFILE'

for uname_a in \
  "Linux RackStation 4.4.302+ #90080 SMP x86_64 GNU/Linux synology_denverton_rs820+" \
  "Linux DS 4.4.302+ #1 SMP x86_64 GNU/Linux synology_denverton_ds1819+" \
  "Linux DS 5.10.55+ #1 SMP x86_64 GNU/Linux synology_epyc7002_sa6400"; do
  out="$(NVIDIA_UNAME_A="$uname_a" "$TMP/preinst" 2>&1)" || fail "preinst refused non-DVA host: $uname_a"
  [ "$out" = GUARD-REACHED ] || fail "GPU guard not reached for: $uname_a ($out)"
done

printf 'preinst DVA guard tests passed.\n'
