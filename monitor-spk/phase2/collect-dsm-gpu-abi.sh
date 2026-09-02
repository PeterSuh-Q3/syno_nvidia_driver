#!/bin/sh
# Read-only evidence collector for the Phase 2 DSM Resource Monitor bridge.
# Run as root on the exact DSM/platform pair being researched.  It does not
# change configuration, restart services, or copy any DSM/private libraries.
set -eu

OUT=${1:-"/tmp/syno-nvidia-gpu-monitor-phase2-$(date +%Y%m%d-%H%M%S)"}
mkdir -p "$OUT"

run() {
    name=$1
    shift
    "$@" >"$OUT/$name" 2>&1 || true
}

run identity uname -a
run packages /usr/syno/bin/synopkg list
run utilization-api /usr/syno/bin/synowebapi --exec \
    api=SYNO.Core.System.Utilization method=get version=1 type=current
run gpuinfo-api /usr/syno/bin/synowebapi --exec \
    api=SYNO.Core.System.GpuInfo method=list version=1
run gpu-flags sh -c 'grep -E "support_(gpu_info|nvidia_gpu)" /etc/synoinfo.conf /etc.defaults/synoinfo.conf 2>/dev/null'
run core-module-hash sh -c 'sha256sum /usr/syno/synoman/webapi/lib/SYNO.Core.System.so /usr/syno/synoman/webapi/lib/SYNO.Core.System.GpuInfo.so /usr/syno/synoman/webapi/lib/SYNO.Core.System.Utilization.so 2>/dev/null'
run system-library-hashes sh -c 'sha256sum /usr/lib/libsynogpuinfo.so.7 /usr/lib/libsynosnmp.so.1 /usr/lib/libnetsnmpmibs.so.40 2>/dev/null'
run core-module-symbols sh -c 'grep -aoEi ".{0,60}(gpu|utilization|support_gpu).{0,100}" /usr/syno/synoman/webapi/lib/SYNO.Core.System.GpuInfo.so 2>/dev/null'
run resource-monitor-gpu-ui sh -c 'grep -aoEi ".{0,100}(gpu_memory|gpu_utilization|support_gpu).{0,160}" /usr/syno/synoman/webman/modules/ResourceMonitor/resource.js 2>/dev/null'
run snmp-processes sh -c 'ps | grep -E "snmpd|synosnmpcd" | grep -v grep'
run nvidia-modules sh -c 'lsmod | grep "^nvidia"'
run nvidia-nvml sh -c 'test -x /var/packages/syno-nvidia-gpu-monitor/target/bin/syno-nvidia-gpu-monitor && /var/packages/syno-nvidia-gpu-monitor/target/bin/syno-nvidia-gpu-monitor --json'

tar -C "$(dirname "$OUT")" -czf "$OUT.tar.gz" "$(basename "$OUT")"
printf 'Created read-only evidence bundle: %s.tar.gz\n' "$OUT"
