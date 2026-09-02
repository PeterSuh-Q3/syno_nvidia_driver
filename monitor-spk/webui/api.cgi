#!/bin/sh
printf 'Content-Type: application/json\r\n\r\n'
exec /var/packages/syno-nvidia-gpu-monitor/target/bin/syno-nvidia-gpu-monitor --json
