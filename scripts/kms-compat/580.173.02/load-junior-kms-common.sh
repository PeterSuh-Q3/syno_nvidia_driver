#!/bin/sh
# Shared device-side loader for the pinned DSM 7.4 / kernel 5.10.55 KMS pilots.
set -eu

PLATFORM=${1:?platform required}
UNIQUE_PREFIX=${2:?Synology unique prefix required}
EXPECTED_MODULE_CKSUM=${3:?module cksum required}
EXPECTED_MODULE_BYTES=${4:?module byte count required}
MODULE_ARCHIVE=${5:?module archive path required}
GSP_ARCHIVE=${6:?GSP archive path required}
WORK=${7:?work directory required}
EXPECTED_GSP_CKSUM=1395102804
EXPECTED_GSP_BYTES=79707626
VERSION=580.173.02

die() { echo "ERROR: $*" >&2; exit 1; }

uid_record=$(grep '^Uid:' /proc/self/status)
set -- $uid_record
[ "${2:-unknown}" = 0 ] || die "Run this script as root in the Junior TTYD shell."
[ -s "$MODULE_ARCHIVE" ] || die "Missing module archive: $MODULE_ARCHIVE"
[ -s "$GSP_ARCHIVE" ] || die "Missing GSP archive: $GSP_ARCHIVE"
[ "$(uname -r)" = "5.10.55+" ] || die "Expected kernel 5.10.55+, found $(uname -r)."

synoinfo=/etc/synoinfo.conf
[ -r "$synoinfo" ] || synoinfo=/etc.defaults/synoinfo.conf
[ -r "$synoinfo" ] || die "Cannot read Synology platform identity."
grep -Eq "^unique=\"$UNIQUE_PREFIX" "$synoinfo" || die "Target platform does not match $PLATFORM."

file_cksum() {
  /usr/bin/cksum "$1" | while read -r checksum bytes filename; do
    echo "$checksum $bytes"
  done
}
[ -x /usr/bin/cksum ] || die "DSM cksum utility is unavailable."
[ "$(file_cksum "$MODULE_ARCHIVE")" = "$EXPECTED_MODULE_CKSUM $EXPECTED_MODULE_BYTES" ] || die "Module archive transfer checksum/size mismatch."
[ "$(file_cksum "$GSP_ARCHIVE")" = "$EXPECTED_GSP_CKSUM $EXPECTED_GSP_BYTES" ] || die "GSP archive transfer checksum/size mismatch."

[ -x /bin/tar ] || [ -x /usr/bin/tar ] || die "tar is unavailable."
[ -x /bin/grep ] || [ -x /usr/bin/grep ] || die "grep is unavailable."
[ -x /bin/dmesg ] || [ -x /sbin/dmesg ] || die "dmesg is unavailable."
[ -x /sbin/modprobe ] || [ -x /usr/sbin/modprobe ] || die "modprobe is unavailable."
[ -x /sbin/insmod ] || [ -x /usr/sbin/insmod ] || die "insmod is unavailable."

gpu_found=0
for pci in /sys/bus/pci/devices/*; do
  [ -r "$pci/vendor" ] && [ -r "$pci/class" ] || continue
  vendor=$(cat "$pci/vendor")
  class=$(cat "$pci/class")
  if [ "$vendor" = 0x10de ] && [ "${class#0x03}" != "$class" ]; then
    gpu_found=1
    echo "NVIDIA display device: $(basename "$pci") vendor=$vendor class=$class"
  fi
done
[ "$gpu_found" = 1 ] || die "No NVIDIA display-class PCI device is present."

# Start from an empty graphics stack so prior providers cannot mask a mismatch.
if grep -Eq '^(drm|drm_kms_helper|drm_mipi_dsi|i915|i915_compat|nvidia|nvidia_modeset|nvidia_drm|nvidia_uvm)[[:space:]]' /proc/modules; then
  die "DRM/i915/NVIDIA modules are already loaded; reboot to a clean Junior state first."
fi
[ ! -e /dev/dri ] || die "/dev/dri already exists; refusing a non-clean KMS test."
[ ! -e /dev/nvidia0 ] || die "/dev/nvidia0 already exists; refusing a non-clean NVIDIA test."

mkdir -p "$WORK/modules" "$WORK/gsp" "$WORK/firmware/nvidia/$VERSION"
tar -xzf "$MODULE_ARCHIVE" -C "$WORK/modules" || die "Cannot extract module archive."
tar -xzf "$GSP_ARCHIVE" -C "$WORK/gsp" || die "Cannot extract GSP archive."

[ "$(cat "$WORK/modules/PLATFORM")" = "$PLATFORM" ] || die "Module pack PLATFORM metadata does not match $PLATFORM."
[ "$(cat "$WORK/modules/VERSION")" = "$VERSION" ] || die "Unexpected NVIDIA module version."
grep -q '^5[.]10[.]55' "$WORK/modules/KVER" || die "Module pack KVER is not 5.10.55."
grep -q "$VERSION" "$WORK/gsp/VERSION" || die "GSP archive metadata does not match $VERSION."
for module in nvidia.ko nvidia-modeset.ko nvidia-drm.ko; do
  [ -s "$WORK/modules/$module" ] || die "Missing module: $module"
done
[ -s "$WORK/gsp/firmware/gsp_tu10x.bin" ] || die "GSP firmware gsp_tu10x.bin is missing."
cp "$WORK/gsp/firmware/"gsp_*.bin "$WORK/firmware/nvidia/$VERSION/"

echo "Target: $(grep '^unique=' "$synoinfo" | head -n 1), kernel $(uname -r)"
echo "Staged modules and firmware under $WORK"
dmesg > "$WORK/dmesg.before"
before_lines=$(wc -l < "$WORK/dmesg.before" | tr -d ' ')

if [ -w /sys/module/firmware_class/parameters/path ]; then
  printf '%s\n' "$WORK/firmware" > /sys/module/firmware_class/parameters/path
  echo "Firmware search path: $(cat /sys/module/firmware_class/parameters/path)"
fi

# Load the system's matching DRM dependencies, then NVIDIA in dependency order.
if [ -x /sbin/modprobe ]; then /sbin/modprobe drm_kms_helper
else /usr/sbin/modprobe drm_kms_helper; fi
if [ -x /sbin/insmod ]; then INSMOD=/sbin/insmod; else INSMOD=/usr/sbin/insmod; fi
"$INSMOD" "$WORK/modules/nvidia.ko"
"$INSMOD" "$WORK/modules/nvidia-modeset.ko"
"$INSMOD" "$WORK/modules/nvidia-drm.ko" modeset=1

echo "--- modeset ---"
cat /sys/module/nvidia_drm/parameters/modeset
echo "--- DRM nodes ---"
ls -l /dev/dri
echo "--- NVIDIA device nodes ---"
if ls /dev/nvidia* >/dev/null 2>&1; then
  ls -l /dev/nvidia*
else
  echo "No /dev/nvidia* character nodes yet (not required for this KMS registration check)."
fi
echo "--- NVIDIA DRM messages ---"
dmesg | grep -E 'nvidia-drm|NVRM|Unknown symbol|Oops|BUG:|general protection|Kernel panic' | tail -n 40

grep -q '^Y$' /sys/module/nvidia_drm/parameters/modeset || die "KMS modeset parameter is not enabled."
[ -c /dev/dri/card0 ] || [ -c /dev/dri/card1 ] || die "No DRM card node was created."
dmesg | grep -q 'Initialized nvidia-drm' || die "Kernel did not report NVIDIA DRM initialization."
dmesg > "$WORK/dmesg.after"
after_lines=$((before_lines + 1))
if tail -n +"$after_lines" "$WORK/dmesg.after" | grep -Eiq 'Oops:|BUG:|general protection fault|Kernel panic|Unknown symbol'; then
  die "Kernel log contains an Oops, panic, or unresolved symbol; stop further testing."
fi
echo "KMS pilot passed initial load checks. Keep this Junior boot under observation."
