#!/bin/sh
# Root-owned, not writable/executable by the package's own unprivileged
# service account (conf/privilege's "tool" section sets this to 0550
# root:package at install time). Only reachable via nvidia-helper's
# fixed, whitelisted execl() - see spk/helper/nvidia-helper.c for why.
#
# All the privileged work that used to live directly in postinst /
# start-stop-status / preuninst now lives here instead, dispatched by
# $1 (postinst|start|uninstall). Those scripts are thin wrappers that
# just call the setuid helper with the right action name.
set -eu

SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="${SCRIPTDIR%/bin}"
SUP="$RUNTIME/share/nvidia-gpu-support.json"
NVDIR=/usr/local/nvidia
RCLOG=/var/log/nvidia-driver.log
ACTIVATION_STATE=/usr/lib/modules/.nvidia-activation-state
PLATFORM_MIGRATION_PENDING=/usr/lib/modules/.nvidia-platform-migration-pending
rclog(){ echo "$(date '+%H:%M:%S') nvidia-backend: $*" >>"$RCLOG" 2>/dev/null; }

# The payload's VERSION is the authoritative userspace driver version. Do not
# derive it from a neighbouring INFO file: resolving the target symlink puts
# this script under @appstore, where that relative INFO path does not exist.
expected_driver_version() {
  sed -n '1{s/[[:space:]]*$//;p;}' "$NVDIR/VERSION" 2>/dev/null
}

# /proc reports the module already resident in memory. modinfo would instead
# report the newly installed file on disk and cannot detect an unsafe upgrade.
running_driver_version() {
  # A fresh install or postinst before module activation has no proc entry.
  # Treat that as "no loaded driver" (not an awk I/O failure); the caller can
  # then continue to load the staged modules. When the entry exists, preserve
  # the version comparison that prevents unsafe live replacement.
  [ -r /proc/driver/nvidia/version ] || return 0
  # Proprietary modules report "Kernel Module 580.173.02", while open
  # modules report "Open Kernel Module for x86_64 580.173.02". Extract the
  # version-shaped token instead of assuming it immediately follows
  # "Kernel Module"; otherwise the open flavor is misread as version "for".
  awk '
    /Kernel Module/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9][0-9][0-9][.][0-9][0-9]*[.][0-9][0-9]$/) {
          print $i
          exit
        }
      }
    }
  ' /proc/driver/nvidia/version 2>/dev/null
}

record_activation_state() {
  expected=$1 running=$2 status=$3
  tmp="${ACTIVATION_STATE}.tmp.$$"
  umask 022
  {
    printf 'expected_driver=%s\n' "$expected"
    printf 'running_driver=%s\n' "$running"
    printf 'status=%s\n' "$status"
    printf 'updated_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$tmp"
  mv -f "$tmp" "$ACTIVATION_STATE"
}

# The package payload under $RUNTIME (/volume1/@appstore/<pkg>/...) is
# owned by this package's own unprivileged service account, not root -
# DSM's conf/privilege "tool" section only accepts individual FILE
# relpaths (declaring a directory fails with error 313), so there is no
# way to get DSM to hand ~100 userspace files root ownership at install
# time the way it does for the setuid helper. NVDIR is a symlink straight
# into this tree (see do_postinst) instead of a copy, and every consumer
# on the box (Plex, Jellyfin, anything dlopen()-ing via /usr/lib) loads
# from it - so if it stayed service-account-owned, that low-privilege
# account could plant a trojaned .so and have it loaded into a root or
# other-user process. Re-lock it to root on every privileged entry point
# (postinst AND start, i.e. every boot), not just once, so a
# delete-and-recreate by the service account between boots can't
# reintroduce writable files - same fix pattern as SynoSmartInfo's
# smartinfo-helper directory self-heal (v2.0.6, CVE-adjacent, see
# https://github.com/PeterSuh-Q3/SynoSmartInfo/issues/21).
lock_payload() {
  # Locking only the leaf dirs (lib/nvidia, lib/modules) isn't enough:
  # delete-and-recreate is governed by the PARENT directory's write bit,
  # not the child's own ownership. If $RUNTIME/lib stayed service-account-
  # writable, the service account could rm -rf lib/nvidia and mkdir a
  # fresh one it fully owns, sidestepping the leaf-level chown entirely.
  # Walk the whole payload tree, parents included.
  for d in "$RUNTIME/lib" "$RUNTIME/share"; do
    [ -d "$d" ] || continue
    chown -R root:root "$d" 2>/dev/null || true
    chmod -R go-w "$d" 2>/dev/null || true
  done
}

# RR/PML configurations can rebuild /usr/lib/modules during boot after the
# package was installed but before DSM starts package services.  The immutable
# package payload remains on the data volume, so kver5 packages can restore
# their platform-specific modules safely at that point.  Limit this recovery
# to the 5.10.55 family for now; kver4 package behaviour is intentionally
# unchanged.
package_kernel_version() {
  sed -n '1{s/[[:space:]]*$//;p;}' "$RUNTIME/share/nvidia-kernel-version" 2>/dev/null
}

nvidia_modules_loaded() {
  grep -Eq '^nvidia(_uvm|_modeset|_drm)?[[:space:]]' /proc/modules 2>/dev/null
}

module_vermagic() {
  module=$1
  if command -v modinfo >/dev/null 2>&1; then
    modinfo -F vermagic "$module" 2>/dev/null
  elif [ -x /usr/bin/kmod ]; then
    /usr/bin/kmod modinfo -F vermagic "$module" 2>/dev/null
  elif [ -x /bin/kmod ]; then
    /bin/kmod modinfo -F vermagic "$module" 2>/dev/null
  else
    return 1
  fi
}

platform_modules_match() {
  platform=$1
  moddir="$RUNTIME/lib/modules/$platform"
  [ -d "$moddir" ] || return 1
  found=0
  for ko in "$moddir"/*.ko; do
    [ -s "$ko" ] || continue
    found=1
    cmp -s "$ko" "/usr/lib/modules/$(basename "$ko")" || return 1
  done
  [ "$found" -eq 1 ]
}

# Re-select the matching module set from this package's offline platform
# matrix. A platform switch is safe to stage on disk, but a live NVIDIA stack
# is never forcibly unloaded: if one is resident, defer activation to reboot.
stage_platform_modules() {
  platform=$1
  kver=$2
  krel=${3:-$(uname -r)}
  moddir="$RUNTIME/lib/modules/$platform"
  expected_kver=$(package_kernel_version)

  if [ -z "$expected_kver" ]; then
    rclog "platform migration unavailable: package has no kernel-version metadata"
    return 1
  fi
  if [ "$kver" != "$expected_kver" ]; then
    rclog "platform migration unavailable: package targets kernel '$expected_kver', running '$kver'"
    return 1
  fi
  if [ ! -d "$moddir" ]; then
    rclog "platform migration unavailable: no bundled module set for '$platform'"
    return 1
  fi

  if [ "$(cat "$moddir/PLATFORM" 2>/dev/null)" != "$platform" ] ||
     [ "$(cat "$moddir/KVER" 2>/dev/null)" != "$expected_kver" ]; then
    rclog "platform migration unavailable: module manifest mismatch in '$moddir'"
    return 1
  fi

  # Validate the full candidate before changing /usr/lib/modules. A platform
  # label alone is not enough: a missing module or wrong kernel ABI must never
  # leave a mixed/partial set or fall back to the previous platform's files.
  for module in nvidia.ko nvidia-uvm.ko nvidia-modeset.ko nvidia-drm.ko; do
    [ -s "$moddir/$module" ] || {
      rclog "platform migration unavailable: '$platform' bundle lacks $module"
      return 1
    }
  done
  found=0
  for ko in "$moddir"/*.ko; do
    [ -s "$ko" ] || continue
    found=1
    vermagic=$(module_vermagic "$ko") || {
      rclog "platform migration unavailable: cannot inspect ABI of $(basename "$ko")"
      return 1
    }
    module_krel=${vermagic%% *}
    if [ "$module_krel" != "$krel" ]; then
      rclog "platform migration unavailable: $(basename "$ko") ABI '$module_krel' does not match running '$krel'"
      return 1
    fi
  done
  [ "$found" -eq 1 ] || {
    rclog "platform migration unavailable: payload for '$platform' has no .ko files"
    return 1
  }

  stage="/usr/lib/modules/.nvidia-stage.$$"
  rm -rf "$stage"
  mkdir -p "$stage" /usr/lib/modules || return 1
  for ko in "$moddir"/*.ko; do
    [ -s "$ko" ] || continue
    cp -f "$ko" "$stage/$(basename "$ko")" || { rm -rf "$stage"; return 1; }
  done
  for ko in "$stage"/*.ko; do
    [ -s "$ko" ] || continue
    mv -f "$ko" "/usr/lib/modules/$(basename "$ko")" || { rm -rf "$stage"; return 1; }
  done
  rm -rf "$stage"
  marker_tmp="/usr/lib/modules/.nvidia-platform.tmp.$$"
  printf '%s %s %s\n' "$platform" "$kver" "$krel" > "$marker_tmp" || return 1
  mv -f "$marker_tmp" /usr/lib/modules/.nvidia-platform || return 1
  rclog "staged validated module set for '$platform' ($krel)"
  return 0
}

stage_kver5_modules() {
  platform=$1
  kver=$2
  krel=${3:-$(uname -r)}
  [ "$kver" = "5.10.55" ] || return 0
  stage_platform_modules "$platform" "$kver" "$krel"
}

restore_kver5_modules_if_missing() {
  platform=$1
  kver=$2
  krel=${3:-$(uname -r)}
  [ "$kver" = "5.10.55" ] || return 0
  missing=0
  for module in nvidia nvidia-uvm nvidia-modeset nvidia-drm; do
    [ -f "/usr/lib/modules/$module.ko" ] || missing=1
  done
  [ "$missing" -eq 1 ] || return 0
  rclog "module recovery: NVIDIA files are missing; validating bundled set for '$platform'"
  if stage_platform_modules "$platform" "$kver" "$krel"; then
    rclog "module recovery: restored validated NVIDIA modules for '$platform'"
  else
    rclog "module recovery: refused unsafe module set for '$platform'"
    return 1
  fi
}

# K5 proprietary bundles a platform-specific quad-DRM pack for every
# supported platform. Load only the provider closure needed by NVIDIA DRM. Keep
# those modules under this package's private kmod root rather than replacing
# files in /usr/lib/modules. Loading drm_kms_helper through modprobe follows
# the matching pack's modules.dep; it does not request i915/amdgpu/bochs.
load_quad_drm_provider() {
  platform=$1
  krel=$2
  archive="$RUNTIME/lib/drm-provider/${platform}-7.4-5.10.55-drm.tgz"
  if [ "$platform" = geminilakenk ] && [ ! -s "$archive" ]; then
    rclog "quad DRM provider: no archive bundled for geminilakenk; retaining legacy package behavior"
    return 0
  fi
  case "$krel" in 5.10.55*) ;; *)
    rclog "quad DRM provider: unsupported kernel '$krel'"
    return 1
    ;;
  esac

  provider_root="$RUNTIME/lib/drm-provider/root"
  module_dir="$provider_root/lib/modules/$krel/kernel/quad-drm"
  stamp="$RUNTIME/lib/drm-provider/.staged-${platform}-${krel}"
  [ -s "$archive" ] || { rclog "quad DRM provider: missing archive for '$platform'"; return 1; }

  if command -v sha256sum >/dev/null 2>&1; then
    archive_id=$(sha256sum "$archive" | awk '{print $1}')
  else
    archive_id=$(cksum "$archive" | awk '{print $1 ":" $2}')
  fi
  if [ "$(cat "$stamp" 2>/dev/null)" != "$archive_id" ] ||
     [ ! -s "$module_dir/drm.ko" ] || [ ! -s "$module_dir/drm_kms_helper.ko" ]; then
    rm -rf "$provider_root/lib/modules/$krel"
    mkdir -p "$module_dir"
    if ! tar -xzf "$archive" -C "$module_dir" >>"$RCLOG" 2>&1; then
      rclog "quad DRM provider: extraction failed for '$platform'"
      return 1
    fi
    for required in drm.ko drm_kms_helper.ko; do
      if [ ! -s "$module_dir/$required" ]; then
        rclog "quad DRM provider: archive for '$platform' lacks $required"
        return 1
      fi
    done
    printf '%s\n' "$archive_id" > "$stamp"
  fi

  # This private root contains only the bundled out-of-tree modules. Empty
  # metadata files make depmod treat that intentionally minimal tree cleanly
  # instead of logging missing modules.order/modules.builtin warnings.
  for metadata in modules.order modules.builtin modules.builtin.modinfo; do
    [ -f "$provider_root/lib/modules/$krel/$metadata" ] ||
      : > "$provider_root/lib/modules/$krel/$metadata"
  done

  DEPMOD=$(command -v depmod 2>/dev/null || true)
  MODPROBE=$(command -v modprobe 2>/dev/null || true)
  [ -n "$DEPMOD" ] && [ -n "$MODPROBE" ] || {
    rclog "quad DRM provider: depmod/modprobe unavailable"
    return 1
  }
  if ! "$DEPMOD" -b "$provider_root" "$krel" >>"$RCLOG" 2>&1; then
    rclog "quad DRM provider: depmod failed for '$platform' ($krel)"
    return 1
  fi
  if ! "$MODPROBE" -d "$provider_root" -S "$krel" drm_kms_helper >>"$RCLOG" 2>&1; then
    rclog "quad DRM provider: failed to load drm_kms_helper dependency closure for '$platform'"
    return 1
  fi
  rclog "quad DRM provider: loaded drm_kms_helper dependency closure for '$platform'; GPU driver modules were not requested"
  return 0
}

do_postinst() {
  lock_payload
  PLATFORM="$(uname -a | awk '{for (i=1; i<=NF; i++) if ($i ~ /^synology_/) { sub(/^synology_/, "", $i); sub(/_.*/, "", $i); print $i; exit }}')"
  KREL="$(uname -r)"
  KVER="$(echo "$KREL" | sed 's/[^0-9.].*$//')"

  if [ ! -d "$RUNTIME/lib/modules/$PLATFORM" ]; then
    echo "nvidia-driver: no bundled kernel module for platform '$PLATFORM' - this variant does not cover this box" >&2
    exit 1
  fi

  if ! stage_platform_modules "$PLATFORM" "$KVER" "$KREL"; then
    echo "nvidia-driver: no ABI-compatible module bundle for '$PLATFORM' on '$KREL'; refusing to stage or load modules." >&2
    exit 1
  fi

  # ---- userspace (shared across every platform in this variant) ----
  # Symlink straight into the (now root-owned, see lock_payload) package
  # payload instead of copying it - the previous cp duplicated ~450MB
  # onto the system partition (/dev/md0) for no reason, since the SPK's
  # own copy already lives on the data volume (/volume1/@appstore/...).
  # This was the exact system-partition-exhaustion problem the .spk
  # packaging was supposed to avoid (see the standalone install.sh
  # complaints in issue #7) - it just moved instead of eliminated.
  rm -rf "$NVDIR"
  ln -sfn "$RUNTIME/lib/nvidia" "$NVDIR"
  chmod +x "$NVDIR/bin/"* 2>/dev/null || true

  # nv-userspace-*.tgz ships only the fully-versioned real files (e.g.
  # libnvidia-ml.so.580.173.02) - none of the usual NVIDIA-installer
  # symlink chain (libnvidia-ml.so.1, libnvidia-ml.so). nvidia-smi and
  # every other consumer link against the SONAME (libFOO.so.1), not the
  # full version, so without these nvidia-smi fails with "couldn't find
  # libnvidia-ml.so" even though the real library is right there.
  ( cd "$NVDIR/lib" 2>/dev/null && for f in *.so.*; do
      [ -f "$f" ] || continue
      case "$f" in *.so.1) continue ;; esac  # already at SONAME level
      base="${f%%.so.*}.so"
      ln -sf "$f" "$base.1"
      ln -sf "$base.1" "$base"
    done ) 2>/dev/null || true

  ( cd "$NVDIR/lib" 2>/dev/null && for so in *.so*; do [ -e "$so" ] && ln -sf "$NVDIR/lib/$so" "/usr/lib/$so"; done ) 2>/dev/null || true
  [ -f "$NVDIR/bin/nvidia-smi" ] && cp -f "$NVDIR/bin/nvidia-smi" /usr/bin/nvidia-smi && chmod +x /usr/bin/nvidia-smi

  mkdir -p /etc/ld.so.conf.d
  echo "$NVDIR/lib" > /etc/ld.so.conf.d/nvidia.conf
  [ -x /sbin/ldconfig ] && /sbin/ldconfig 2>/dev/null || true

  # ---- GPU detection + GSP firmware (bundled, no network needed) ----
  GPUID=""
  for d in /sys/bus/pci/devices/*; do
    [ "$(cat "$d/vendor" 2>/dev/null)" = "0x10de" ] || continue
    case "$(cat "$d/class" 2>/dev/null)" in 0x0300*|0x0302*)
      GPUID="10de:$(sed 's/^0x//' "$d/device" 2>/dev/null | tr 'A-Z' 'a-z')"; break ;; esac
  done

  if [ -n "$GPUID" ] && [ -f "$SUP" ] && command -v jq >/dev/null 2>&1; then
    # Handed to jellyfin-autoconfig.sh (via do_start) at every boot, since
    # NVDEC decode-codec support can only be inferred from the GPU
    # architecture, not probed the way NVENC encoders are.
    jq -r --arg g "$GPUID" '.gpus[$g].arch // "unknown"' "$SUP" 2>/dev/null > /usr/lib/modules/.nvidia-gpuarch
    NEEDS_GSP="$(jq -r --arg g "$GPUID" '.gpus[$g].needs_gsp // false' "$SUP" 2>/dev/null)"
    GSP_FW="$(jq -r --arg g "$GPUID" '.gpus[$g].gsp_fw // empty' "$SUP" 2>/dev/null)"
    DRV="$(expected_driver_version)"
    if [ "$NEEDS_GSP" = "true" ] && [ -n "$GSP_FW" ] && [ -f "$RUNTIME/lib/firmware/$GSP_FW" ]; then
      FWDIR="/lib/firmware/nvidia/${DRV:-unknown}"
      mkdir -p "$FWDIR"
      cp -f "$RUNTIME/lib/firmware/$GSP_FW" "$FWDIR/$GSP_FW"
      echo "nvidia-driver: GSP firmware $GSP_FW staged -> $FWDIR"
    elif [ "$NEEDS_GSP" = "true" ]; then
      echo "nvidia-driver: WARNING - $GPUID needs GSP firmware but none is bundled for it; the driver will load but the GPU will not initialise." >&2
    fi
  fi

  echo "nvidia-driver: installed for platform '$PLATFORM' (kernel $KVER)"
  echo "nvidia-driver: loading modules now (also re-runs on every future boot via start-stop-status)"
  do_start install
  restart_plex install
}

plex_process_signature() {
  signature=""
  for cmdline in /proc/[0-9]*/cmdline; do
    [ -r "$cmdline" ] || continue
    args="$(tr '\000' ' ' < "$cmdline" 2>/dev/null || true)"
    case "$args" in
      *"/Plex Media Server"*|*"Plex Media Server"*)
        pid="${cmdline#/proc/}"
        pid="${pid%/cmdline}"
        signature="${signature}${pid} "
        ;;
    esac
  done
  printf '%s' "$signature" | sed 's/[[:space:]]*$//'
}

plex_driver_ready() {
  expected="$(expected_driver_version)"
  running="$(running_driver_version)"
  [ -n "$expected" ] && [ "$expected" = "$running" ] &&
    [ -e /dev/nvidia0 ] && [ -d /proc/driver/nvidia/gpus ] &&
    [ -n "$(ls -A /proc/driver/nvidia/gpus 2>/dev/null)" ]
}

plex_restart_result() {
  printf 'NVIDIA_PLEX_RESULT=%s\n' "$1"
}

restart_plex() {
  reason=${1:-boot}
  PLEX_PKG=PlexMediaServer
  SYNOPKG=/usr/syno/bin/synopkg

  # This integration is intentionally scoped to package builds that opt in
  # with a payload marker, so other NVIDIA branches keep their old behavior.
  [ -f "$RUNTIME/share/nvidia-plex-restart.enabled" ] || return 0

  [ -f "/var/packages/$PLEX_PKG/INFO" ] || {
    rclog "Plex restart skipped: Plex package not installed"
    [ "$reason" = install ] && plex_restart_result absent
    return 0
  }

  before="$(plex_process_signature)"
  if [ -z "$before" ]; then
    rclog "Plex restart skipped: Plex was not running ($reason)"
    [ "$reason" = install ] && plex_restart_result not_running
    return 0
  fi

  if ! plex_driver_ready; then
    rclog "Plex restart skipped: NVIDIA driver is not active ($reason)"
    [ "$reason" = install ] && plex_restart_result driver_not_ready
    return 0
  fi

  if [ "$reason" = boot ]; then
    # /run is volatile and recreated at boot, so the marker limits this boot
    # hook to one attempt without suppressing the next DSM boot's retry.
    marker_dir=/run/syno-nvidia-driver
    [ -d /run ] || marker_dir=/tmp/syno-nvidia-driver
    mkdir -p "$marker_dir" 2>/dev/null || true
    marker="$marker_dir/plex-restart-at-boot.done"
    if [ -e "$marker" ]; then
      rclog "Plex boot restart skipped: already attempted this boot"
      return 0
    fi
    : > "$marker" 2>/dev/null || true
  else
    # Installation itself already performed the restart for this boot. If
    # DSM invokes start-stop-status again immediately after postinst, do not
    # restart Plex a second time in the same boot.
    marker_dir=/run/syno-nvidia-driver
    [ -d /run ] || marker_dir=/tmp/syno-nvidia-driver
    mkdir -p "$marker_dir" 2>/dev/null || true
    marker="$marker_dir/plex-restart-at-boot.done"
    : > "$marker" 2>/dev/null || true
  fi

  rclog "Plex restart requested ($reason); NVIDIA $(expected_driver_version) is active"
  if [ ! -x "$SYNOPKG" ] || ! "$SYNOPKG" restart "$PLEX_PKG" >>"$RCLOG" 2>&1; then
    rclog "Plex restart command failed ($reason)"
    [ "$reason" = install ] && plex_restart_result restart_failed
    return 0
  fi

  elapsed=0
  stable=0
  while [ "$elapsed" -lt 120 ]; do
    current="$(plex_process_signature)"
    if [ -n "$current" ] && [ "$current" != "$before" ]; then
      stable=$((stable + 1))
      [ "$stable" -ge 2 ] && {
        rclog "Plex restart succeeded ($reason); new process IDs: $current"
        [ "$reason" = install ] && plex_restart_result restart_success
        return 0
      }
    else
      stable=0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  rclog "Plex restart timed out ($reason); previous process IDs: $before"
  [ "$reason" = install ] && plex_restart_result restart_timeout
  return 0
}

do_start() {
  START_REASON=${1:-boot}
  rclog "=== start ==="
  lock_payload

  # Platform/kernel guard: vermagic alone cannot catch a platform mismatch
  # (it is textually identical across every kver5 platform), and a DSM
  # upgrade can move the same platform to a different kernel point release.
  CURP="$(uname -a | awk '{for (i=1; i<=NF; i++) if ($i ~ /^synology_/) { sub(/^synology_/, "", $i); sub(/_.*/, "", $i); print $i; exit }}')"
  CURL="$(uname -r)"
  CURK="$(echo "$CURL" | sed 's/[^0-9.].*$//')"
  STORED="$(cat /usr/lib/modules/.nvidia-platform 2>/dev/null)"
  STOREDP="${STORED%% *}"
  STOREDK=""; STOREDL=""
  case "$STORED" in
    *" "*) REST="${STORED#* }"; STOREDK="${REST%% *}"; case "$REST" in *" "*) STOREDL="${REST#* }" ;; esac ;;
  esac
  if [ -z "$STOREDP" ] || [ "$STOREDP" != "$CURP" ] || [ "$STOREDK" != "$CURK" ] || [ "$STOREDL" != "$CURL" ] || ! platform_modules_match "$CURP"; then
    rclog "platform/kernel changed: stored '$STOREDP $STOREDK $STOREDL', running '$CURP $CURK $CURL'; validating and selecting matching bundled modules"
    if ! stage_platform_modules "$CURP" "$CURK" "$CURL"; then
      rclog "REFUSED: package has no ABI-compatible module set for '$CURP $CURL'; existing modules were not loaded or replaced"
      echo "nvidia-driver: no compatible bundled modules for platform '$CURP' kernel '$CURL'; refusing to load the previous platform's modules." >&2
      return 1
    fi
    if nvidia_modules_loaded; then
      printf '%s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || date '+%s')" > "$PLATFORM_MIGRATION_PENDING"
      rclog "validated modules staged for '$CURP', but NVIDIA modules are resident; reboot required before activation"
      echo "nvidia-driver: compatible modules for '$CURP' are staged; reboot DSM to activate them safely." >&2
      return 0
    fi
    rclog "platform/kernel modules staged for '$CURP $CURL'; continuing with activation"
  fi

  if [ -f "$PLATFORM_MIGRATION_PENDING" ]; then
    if nvidia_modules_loaded; then
      rclog "SKIPPED: platform/kernel migration is staged but NVIDIA modules remain resident; reboot required"
      return 0
    fi
    rm -f "$PLATFORM_MIGRATION_PENDING"
    rclog "platform/kernel migration pending flag cleared; activating staged modules"
  fi

  # This self-heals only kver5 packages.  It runs after compatibility guards
  # but before any insmod attempt, so a RR/PML boot-time module-directory
  # rebuild cannot leave a superficially "running" package with no driver.
  restore_kver5_modules_if_missing "$CURP" "$CURK" "$CURL"

  # A package upgrade replaces .ko files and userspace immediately, but it
  # cannot safely unload a live NVIDIA stack: Plex/Jellyfin/Docker/CUDA may
  # own /dev/nvidia*, and forced unloads can hang DSM. At boot no old module
  # remains, so the normal path below loads the new files and clears the marker.
  EXPECTED_DRV="$(expected_driver_version)"
  RUNNING_DRV="$(running_driver_version)"
  if [ -n "$EXPECTED_DRV" ] && [ -n "$RUNNING_DRV" ] && [ "$EXPECTED_DRV" != "$RUNNING_DRV" ]; then
    record_activation_state "$EXPECTED_DRV" "$RUNNING_DRV" reboot_required
    rclog "REBOOT REQUIRED: userspace=$EXPECTED_DRV, loaded module=$RUNNING_DRV; refusing unsafe live replacement"
    echo "nvidia-driver: upgrade files installed (userspace $EXPECTED_DRV), but loaded kernel module is $RUNNING_DRV." >&2
    echo "nvidia-driver: reboot DSM before using NVIDIA. The package will activate $EXPECTED_DRV at boot." >&2
    return 0
  fi

  if [ -f "$RUNTIME/share/nvidia-drm-provider.enabled" ]; then
    if ! load_quad_drm_provider "$CURP" "$(uname -r)"; then
      rclog "NVIDIA module activation skipped because the bundled DRM provider closure is unavailable"
      echo "nvidia-driver: matching DRM dependencies could not be loaded; refusing to load NVIDIA modules with unresolved symbols." >&2
      return 1
    fi
  fi

  for m in nvidia nvidia-uvm nvidia-modeset nvidia-drm; do
    if [ -f "/usr/lib/modules/$m.ko" ]; then
      if [ "$m" = nvidia-drm ] && [ -f "$RUNTIME/share/nvidia-drm-kms-modeset.enabled" ]; then
        if /sbin/insmod "/usr/lib/modules/$m.ko" modeset=1 2>>"$RCLOG"; then
          rclog "insmod $m modeset=1 OK"
        else
          rclog "insmod $m modeset=1 FAILED (see above)"
        fi
      elif /sbin/insmod "/usr/lib/modules/$m.ko" 2>>"$RCLOG"; then
        rclog "insmod $m OK"
      else
        rclog "insmod $m FAILED (see above)"
      fi
    fi
  done

  NGPU=$(ls -d /proc/driver/nvidia/gpus/* 2>/dev/null | wc -l); [ "$NGPU" -ge 1 ] || NGPU=1
  MAJOR=$(awk '$2=="nvidia-frontend"||$2=="nvidia"{print $1}' /proc/devices | head -1)
  if [ -n "$MAJOR" ]; then
    [ -e /dev/nvidiactl ] || mknod -m 666 /dev/nvidiactl c "$MAJOR" 255
    n=0; while [ "$n" -lt "$NGPU" ]; do [ -e "/dev/nvidia$n" ] || mknod -m 666 "/dev/nvidia$n" c "$MAJOR" "$n"; n=$((n+1)); done
  fi
  UMAJOR=$(awk '$2=="nvidia-uvm"{print $1}' /proc/devices | head -1)
  [ -n "$UMAJOR" ] && [ ! -e /dev/nvidia-uvm ] && mknod -m 666 /dev/nvidia-uvm c "$UMAJOR" 0
  [ -e /dev/nvidia-modeset ] || "$RUNTIME/bin/nvidia-modprobe" -m 2>/dev/null || true

  RUNNING_DRV="$(running_driver_version)"
  if [ -n "$EXPECTED_DRV" ] && [ -n "$RUNNING_DRV" ]; then
    if [ "$EXPECTED_DRV" = "$RUNNING_DRV" ]; then
      rm -f "$ACTIVATION_STATE"
      rclog "driver active: kernel module and userspace both $EXPECTED_DRV"
    else
      record_activation_state "$EXPECTED_DRV" "$RUNNING_DRV" reboot_required
      rclog "REBOOT REQUIRED after load attempt: userspace=$EXPECTED_DRV, loaded module=$RUNNING_DRV"
    fi
  fi

  [ -x /sbin/ldconfig ] && /sbin/ldconfig 2>/dev/null || true

  # Container Manager runtime re-assertion (only if the optional layer was
  # staged - idempotent merge, safe to repeat every boot).
  CRDIR=/usr/local/nvidia-runtime
  DJ=/var/packages/ContainerManager/etc/dockerd.json
  if [ -x "$CRDIR/bin/nvidia-container-runtime" ] && [ -f "$DJ" ] && command -v jq >/dev/null 2>&1; then
    CUR="$(jq -r '.runtimes.nvidia.path // empty' "$DJ" 2>/dev/null)"
    if [ "$CUR" != "$CRDIR/bin/nvidia-container-runtime" ]; then
      NEWDJ="$(jq --arg p "$CRDIR/bin/nvidia-container-runtime" '.runtimes.nvidia = {"path": $p, "runtimeArgs": []}' "$DJ" 2>/dev/null)"
      [ -n "$NEWDJ" ] && echo -E "$NEWDJ" > "$DJ" && rclog "container runtime: re-registered 'nvidia' in dockerd.json"
    fi
  elif [ -f "$DJ" ] && command -v jq >/dev/null 2>&1; then
    CUR="$(jq -r '.runtimes.nvidia.path // empty' "$DJ" 2>/dev/null)"
    if [ "$CUR" = "$CRDIR/bin/nvidia-container-runtime" ]; then
      NEWDJ="$(jq 'del(.runtimes.nvidia)' "$DJ" 2>/dev/null)"
      [ -n "$NEWDJ" ] && echo -E "$NEWDJ" > "$DJ" && rclog "container runtime: removed stale 'nvidia' entry (layer not installed)"
    fi
  fi

  # Jellyfin ffmpeg path + hardware-transcoding auto-configuration (only if
  # the ffmpeg layer and the helper script were staged by do_postinst).
  NVFF=/usr/local/nvidia/bin/ffmpeg
  JF_SS=/var/packages/jellyfin/scripts/service-setup
  if [ ! -d /var/packages/syno-nvidia-ffmpeg ] && [ -x "$NVFF" ] && [ -f "$JF_SS" ] && grep -q -- '--ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg' "$JF_SS"; then
    cp -n "$JF_SS" "$JF_SS.pre-nvidia.bak" 2>/dev/null
    if sed -i "s#--ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg#--ffmpeg $NVFF#" "$JF_SS" 2>/dev/null; then
      chown root:root "$JF_SS" "$JF_SS.pre-nvidia.bak" 2>/dev/null
      chmod 755 "$JF_SS" "$JF_SS.pre-nvidia.bak" 2>/dev/null
      rclog "jellyfin: ffmpeg path repointed to $NVFF"
    fi
  fi
  JF_AC="$RUNTIME/bin/jellyfin-autoconfig.sh"
  JF_CFG=/var/packages/jellyfin/var/config/encoding.xml
  if [ -x "$JF_AC" ] && [ -x "$NVFF" ] && [ -f "$JF_CFG" ]; then
    OUT="$("$JF_AC" "$JF_CFG" "$NVFF" "$(cat /usr/lib/modules/.nvidia-gpuarch 2>/dev/null)" 2>&1)"
    [ -n "$OUT" ] && rclog "$OUT"
  fi

  rclog "loaded: $(lsmod 2>/dev/null | grep -c '^nvidia') nvidia modules; nodes: $(ls /dev/nvidia* 2>/dev/null | tr '\n' ' ')"
  rclog "=== start done ==="
  [ "$START_REASON" = install ] || restart_plex boot
  return 0
}

do_uninstall() {
  # Jellyfin ffmpeg path: restore from the backup do_start made before ever
  # patching the live file.
  JF_SS=/var/packages/jellyfin/scripts/service-setup
  if [ -f "$JF_SS.pre-nvidia.bak" ] && [ -f "$JF_SS" ] && grep -Fq -- '--ffmpeg /usr/local/nvidia/bin/ffmpeg' "$JF_SS"; then
    mv -f "$JF_SS.pre-nvidia.bak" "$JF_SS"
    chmod 755 "$JF_SS" 2>/dev/null || true
  fi
  # Hardware-transcoding auto-configuration is deliberately NOT reverted:
  # jellyfin-autoconfig.sh only ever touches encoding.xml once (gated by its
  # own stamp file) and from then on treats it as the user's own settings.

  # Container Manager runtime: remove only the entry this package registered.
  DJ=/var/packages/ContainerManager/etc/dockerd.json
  CRDIR=/usr/local/nvidia-runtime
  if [ -f "$DJ" ] && command -v jq >/dev/null 2>&1; then
    CUR="$(jq -r '.runtimes.nvidia.path // empty' "$DJ" 2>/dev/null)"
    if [ "$CUR" = "$CRDIR/bin/nvidia-container-runtime" ]; then
      NEWDJ="$(jq 'del(.runtimes.nvidia)' "$DJ" 2>/dev/null)"
      [ -n "$NEWDJ" ] && echo -E "$NEWDJ" > "$DJ"
    fi
  fi
  rm -rf "$CRDIR"

  # Kernel modules: unload if present (best-effort - a process holding the
  # GPU open will make rmmod fail, left as a visible error rather than
  # forced, since forcing it can hang the box).
  for m in nvidia-drm nvidia-modeset nvidia-uvm nvidia; do
    lsmod 2>/dev/null | grep -q "^$m " && rmmod "$m" 2>/dev/null || true
  done
  rm -f /usr/lib/modules/nvidia*.ko /usr/lib/modules/.nvidia-platform /usr/lib/modules/.nvidia-gpuarch \
    "$ACTIVATION_STATE" "$PLATFORM_MIGRATION_PENDING"

  # Userspace + library search path.
  rm -f /etc/ld.so.conf.d/nvidia.conf
  [ -x /sbin/ldconfig ] && /sbin/ldconfig 2>/dev/null || true
  if [ -d "$NVDIR/lib" ]; then
    for so in "$NVDIR"/lib/*.so*; do
      [ -e "$so" ] && [ -L "/usr/lib/$(basename "$so")" ] && rm -f "/usr/lib/$(basename "$so")"
    done
  fi
  [ -f /usr/bin/nvidia-smi ] && rm -f /usr/bin/nvidia-smi
  rm -rf "$NVDIR"
}

case "${1:-}" in
  postinst)  do_postinst ;;
  start)     do_start boot ;;
  uninstall) do_uninstall ;;
  *) echo "nvidia-backend: unknown action '${1:-}'" >&2; exit 1 ;;
esac
