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
rclog(){ echo "$(date '+%H:%M:%S') nvidia-backend: $*" >>"$RCLOG" 2>/dev/null; }

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

do_postinst() {
  lock_payload
  PLATFORM="$(uname -a | awk '{print $NF}' | cut -d'_' -f2)"
  KREL="$(uname -r)"
  KVER="$(echo "$KREL" | sed 's/[^0-9.].*$//')"

  MODDIR="$RUNTIME/lib/modules/$PLATFORM"
  if [ ! -d "$MODDIR" ]; then
    echo "nvidia-driver: no bundled kernel module for platform '$PLATFORM' - this variant does not cover this box" >&2
    exit 1
  fi

  mkdir -p /usr/lib/modules
  for ko in "$MODDIR"/*.ko; do
    [ -f "$ko" ] && cp -f "$ko" "/usr/lib/modules/$(basename "$ko")"
  done
  # Boot-hook mismatch guard (see do_start): a DSM upgrade can move the
  # same platform to a different kernel point release, invalidating the
  # bundled .ko's vermagic without changing PLATFORM.
  echo "$PLATFORM $KVER" > /usr/lib/modules/.nvidia-platform

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
    DRV="$(sed -n 's/^version="\([^"]*\)".*/\1/p' "$RUNTIME/../INFO" 2>/dev/null | head -1)"
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
  do_start
}

do_start() {
  rclog "=== start ==="
  lock_payload

  # Platform/kernel guard: vermagic alone cannot catch a platform mismatch
  # (it is textually identical across every kver5 platform), and a DSM
  # upgrade can move the same platform to a different kernel point release.
  CURP="$(uname -a | awk '{print $NF}' | cut -d'_' -f2)"
  CURK="$(uname -r | sed 's/[^0-9.].*$//')"
  STORED="$(cat /usr/lib/modules/.nvidia-platform 2>/dev/null)"
  STOREDP="${STORED%% *}"
  STOREDK=""; case "$STORED" in *" "*) STOREDK="${STORED##* }" ;; esac
  if [ -n "$STOREDP" ] && [ "$STOREDP" != "$CURP" ]; then
    rclog "SKIPPED: installed .ko are for platform '$STOREDP' but running on '$CURP'"
    return 0
  fi
  if [ -n "$STOREDK" ] && [ "$STOREDK" != "$CURK" ]; then
    rclog "SKIPPED: installed .ko are for kernel '$STOREDK' but running '$CURK' (DSM upgraded?) - reinstall this package"
    return 0
  fi

  for m in nvidia nvidia-uvm nvidia-modeset nvidia-drm; do
    if [ -f "/usr/lib/modules/$m.ko" ]; then
      if /sbin/insmod "/usr/lib/modules/$m.ko" 2>>"$RCLOG"; then rclog "insmod $m OK"; else rclog "insmod $m FAILED (see above)"; fi
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
  if [ -x "$NVFF" ] && [ -f "$JF_SS" ] && grep -q -- '--ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg' "$JF_SS"; then
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
  return 0
}

do_uninstall() {
  # Jellyfin ffmpeg path: restore from the backup do_start made before ever
  # patching the live file.
  JF_SS=/var/packages/jellyfin/scripts/service-setup
  if [ -f "$JF_SS.pre-nvidia.bak" ]; then
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
  rm -f /usr/lib/modules/nvidia*.ko /usr/lib/modules/.nvidia-platform /usr/lib/modules/.nvidia-gpuarch

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
  start)     do_start ;;
  uninstall) do_uninstall ;;
  *) echo "nvidia-backend: unknown action '${1:-}'" >&2; exit 1 ;;
esac
