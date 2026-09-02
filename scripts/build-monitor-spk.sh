#!/usr/bin/env bash
# Build the Phase 1 (read-only) NVIDIA telemetry collector for DSM 7.4.
# It uses the DSM 7.4 epyc7002 cross compiler so the binary is linked against
# the target libc.  The collector itself dlopen()s NVML at runtime.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACKAGE=syno-nvidia-gpu-monitor
VERSION=0.5.0-1
PLATFORM=epyc7002
IMAGE=${SYNOCOMPILER_IMAGE:-dante90/syno-compiler:7.4}
CC=${SYNOCOMPILER_CC:-/opt/epyc7002/bin/x86_64-pc-linux-gnu-gcc}
WORK="$ROOT/work/$PACKAGE-$PLATFORM"
OUT="$ROOT/dist"

rm -rf "$WORK"
mkdir -p "$WORK/target/bin/helper" "$WORK/scripts" "$WORK/conf" "$WORK/webapi" "$WORK/target/ui" "$OUT"

docker run --rm --platform linux/amd64 --entrypoint /bin/bash \
  -u 0 -v "$ROOT:/work" -w /work "$IMAGE" -lc \
  "'$CC' -O2 -s -Wall -Wextra -Werror -o '/work/work/$PACKAGE-$PLATFORM/target/bin/syno-nvidia-gpu-monitor' '/work/monitor-spk/src/syno-nvidia-gpu-monitor.c' -ldl"
chmod 0755 "$WORK/target/bin/syno-nvidia-gpu-monitor"
docker run --rm --platform linux/amd64 --entrypoint /bin/bash -u 0 -v "$ROOT:/work" -w /work "$IMAGE" -lc \
  "'$CC' -O2 -s -Wall -Wextra -Werror -o '/work/work/$PACKAGE-$PLATFORM/target/bin/helper/monitor-helper' '/work/monitor-spk/src/monitor-helper.c'"
chmod 0550 "$WORK/target/bin/helper/monitor-helper"
cp "$ROOT/monitor-spk/src/syno-nvidia-gpu-monitor-daemon.sh" "$WORK/target/bin/"
chmod 0755 "$WORK/target/bin/syno-nvidia-gpu-monitor-daemon.sh"
cp "$ROOT/monitor-spk/src/syno-nvidia-gpu-monitor-status.sh" "$WORK/target/bin/syno-nvidia-gpu-monitor-status"
chmod 0755 "$WORK/target/bin/syno-nvidia-gpu-monitor-status"

cp "$ROOT/monitor-spk/scripts/"* "$WORK/scripts/"
chmod 0755 "$WORK/scripts/"*
cp "$ROOT/monitor-spk/conf/privilege" "$WORK/conf/privilege"
cp "$ROOT/monitor-spk/webapi/SYNO.NvidiaGpuMonitor" "$WORK/webapi/SYNO.NvidiaGpuMonitor"
chmod 0755 "$WORK/webapi/SYNO.NvidiaGpuMonitor"
cp "$ROOT/monitor-spk/webui/index.html" "$WORK/target/ui/index.html"
cp "$ROOT/monitor-spk/webui/api.cgi" "$WORK/target/ui/api.cgi"
chmod 0755 "$WORK/target/ui/api.cgi"
cp "$ROOT/monitor-spk/INFO" "$WORK/INFO"
for icon in PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG; do
  cp "$ROOT/spk/$icon" "$WORK/$icon"
done

tar -C "$WORK/target" -czf "$WORK/package.tgz" .
CHECKSUM=$(md5sum "$WORK/package.tgz" | awk '{print $1}')
EXTRACT_SIZE=$(du -sk "$WORK/target" | awk '{print $1}')
{
  printf 'extractsize="%s"\n' "$EXTRACT_SIZE"
  printf 'create_time="%s"\n' "$(date +%Y%m%d-%H:%M:%S)"
  printf 'checksum="%s"\n' "$CHECKSUM"
} >> "$WORK/INFO"

SPK="$OUT/${PACKAGE}-${VERSION}-dsm7.4-${PLATFORM}.spk"
tar -C "$WORK" -cf "$SPK" INFO package.tgz scripts conf webapi PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG

echo "Built $SPK ($(du -h "$SPK" | cut -f1))"
tar -tf "$SPK"
