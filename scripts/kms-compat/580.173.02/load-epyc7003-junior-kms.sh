#!/bin/sh
# Load the pinned DSM 7.4 / kernel 5.10.55 EPYC7003 NVIDIA 580 Proprietary
# KMS pilot from a root shell opened directly in the Junior TTYD web console.
# This script is intentionally device-side; it does not connect to TTYD.
set -eu

MODULE_ARCHIVE=${1:-/tmp/nv-epyc7003-kms/nv-ko.tgz}
GSP_ARCHIVE=${2:-/tmp/nv-epyc7003-kms/nv-gsp.tgz}
WORK=${3:-/tmp/nv-epyc7003-kms/run}
EXPECTED_MODULE_SHA=44fd42f59c1ad8e940a9c859ba4b0e4fbd65e179bdb13ac0e1a7ce047d51ce7a
EXPECTED_GSP_SHA=39f99970299a398f82b7c6d61a20f22faca1589b044822bdf1e5a36094c7d62b

die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "Run this script as root in the Junior TTYD shell."
[ -s "$MODULE_ARCHIVE" ] || die "Missing module archive: $MODULE_ARCHIVE"
[ -s "$GSP_ARCHIVE" ] || die "Missing GSP archive: $GSP_ARCHIVE"
[ "$(uname -r)" = "5.10.55+" ] || die "Expected kernel 5.10.55+, found $(uname -r)."

synoinfo=/etc/synoinfo.conf
[ -r "$synoinfo" ] || synoinfo=/etc.defaults/synoinfo.conf
[ -r "$synoinfo" ] || die "Cannot read Synology platform identity."
grep -Eq '^unique="synology_epyc7003_' "$synoinfo" || die "This is not an EPYC7003 system."

sha256() {
  if [ -x /usr/bin/sha256sum ]; then /usr/bin/sha256sum "$1" | awk '{print $1}'
  elif [ -x /bin/sha256sum ]; then /bin/sha256sum "$1" | awk '{print $1}'
  else die "sha256sum is unavailable."; fi
}
[ "$(sha256 "$MODULE_ARCHIVE")" = "$EXPECTED_MODULE_SHA" ] || die "Module archive SHA-256 mismatch."
[ "$(sha256 "$GSP_ARCHIVE")" = "$EXPECTED_GSP_SHA" ] || die "GSP archive SHA-256 mismatch."

[ -x /bin/tar ] || [ -x /usr/bin/tar ] || die "tar is unavailable."
[ -x /bin/grep ] || [ -x /usr/bin/grep ] || die "grep is unavailable."
[ -x /bin/awk ] || [ -x /usr/bin/awk ] || die "awk is unavailable."
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

# Refuse to test on top of an already populated DRM/NVIDIA stack. This check
# prevents the provider state from another test from masking a dependency.
if grep -Eq '^(drm|drm_kms_helper|drm_mipi_dsi|i915|i915_compat|nvidia|nvidia_modeset|nvidia_drm|nvidia_uvm)[[:space:]]' /proc/modules; then
  die "DRM/i915/NVIDIA modules are already loaded; reboot to a clean Junior state first."
fi
[ ! -e /dev/dri ] || die "/dev/dri already exists; refusing a non-clean KMS test."
[ ! -e /dev/nvidia0 ] || die "/dev/nvidia0 already exists; refusing a non-clean NVIDIA test."

mkdir -p "$WORK/modules" "$WORK/gsp" "$WORK/firmware/nvidia/580.173.02"
tar -xzf "$MODULE_ARCHIVE" -C "$WORK/modules" || die "Cannot extract module archive."
tar -xzf "$GSP_ARCHIVE" -C "$WORK/gsp" || die "Cannot extract GSP archive."

[ "$(cat "$WORK/modules/PLATFORM")" = epyc7003 ] || die "Module pack PLATFORM metadata is not epyc7003."
[ "$(cat "$WORK/modules/VERSION")" = 580.173.02 ] || die "Unexpected NVIDIA module version."
grep -q '^5[.]10[.]55' "$WORK/modules/KVER" || die "Module pack KVER is not 5.10.55."
[ "$(cat "$WORK/gsp/VERSION")" = 580.173.02 ] || die "Unexpected GSP version."
for module in nvidia.ko nvidia-modeset.ko nvidia-drm.ko; do
  [ -s "$WORK/modules/$module" ] || die "Missing module: $module"
done
[ -s "$WORK/gsp/firmware/gsp_tu10x.bin" ] || die "GSP firmware gsp_tu10x.bin is missing."
cp "$WORK/gsp/firmware/"gsp_*.bin "$WORK/firmware/nvidia/580.173.02/"

echo "Target: $(grep '^unique=' "$synoinfo" | head -n 1), kernel $(uname -r)"
echo "Staged modules and firmware under $WORK"
echo "Pre-load dmesg saved to $WORK/dmesg.before"
dmesg > "$WORK/dmesg.before"
before_lines=$(wc -l < "$WORK/dmesg.before" | tr -d ' ')

if [ -w /sys/module/firmware_class/parameters/path ]; then
  printf '%s\n' "$WORK/firmware" > /sys/module/firmware_class/parameters/path
  echo "Firmware search path: $(cat /sys/module/firmware_class/parameters/path)"
fi

# Load the already installed, platform-matched DRM dependency graph, then the
# candidate modules in their required order. Stop on the first failed step.
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
ls -l /dev/nvidia*
echo "--- NVIDIA DRM initialization ---"
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
