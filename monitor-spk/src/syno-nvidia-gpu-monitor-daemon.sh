#!/bin/sh
set -u
BASE="/var/packages/syno-nvidia-gpu-monitor"
BIN="$BASE/target/bin/syno-nvidia-gpu-monitor"
OUT="$BASE/var/telemetry.json"
PID="$BASE/var/monitor.pid"
mkdir -p "$BASE/var"
echo "$$" > "$PID"
trap 'rm -f "$PID"; exit 0' INT TERM EXIT
while :; do
    "$BIN" --json > "$OUT.tmp" 2>/dev/null && mv -f "$OUT.tmp" "$OUT"
    sleep 5
done
