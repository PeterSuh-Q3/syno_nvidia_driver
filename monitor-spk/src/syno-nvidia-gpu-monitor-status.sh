#!/bin/sh
if [ "${1:-}" = "--json" ] || { [ "${1:-}" = "status" ] && [ "${2:-}" = "--json" ]; }; then
    exec /var/packages/syno-nvidia-gpu-monitor/target/bin/syno-nvidia-gpu-monitor --json
fi
echo "Usage: syno-nvidia-gpu-monitor status --json" >&2
exit 2
