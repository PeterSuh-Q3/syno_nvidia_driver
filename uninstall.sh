#!/bin/bash
#
# syno_nvidia_driver - uninstaller (reverse of install.sh) for a running DSM.
# Unloads the NVIDIA modules and removes everything install.sh placed.
#
#   sudo bash uninstall.sh
#   curl -sL <this-url> | sudo bash      # one-liner (prompts read from tty)
#
set -u
ask(){ eval "$1=''"; IFS= read -r "$1" </dev/tty 2>/dev/null || true; }

R='\033[0m'; B='\033[1m'; DIM='\033[2m'
RED='\033[1;31m'; GRN='\033[1;32m'; YEL='\033[1;33m'; BLU='\033[1;34m'; CYN='\033[1;36m'; WHT='\033[1;37m'
say(){ printf "%b\n" "$*"; }
hr(){  say "${DIM}------------------------------------------------------------${R}"; }
step(){ say "\n${BLU}${B}▶ $*${R}"; }
ok(){   say "  ${GRN}✔${R} $*"; }
warn(){ say "  ${YEL}!${R} $*"; }
err(){  say "  ${RED}x${R} $*"; }
die(){  err "$*"; exit 1; }

NVDIR=/usr/local/nvidia
CRDIR=/usr/local/nvidia-runtime
CMPKG=/var/packages/ContainerManager

say ""
say "${CYN}${B}  ╔══════════════════════════════════════════════════════════╗${R}"
say "${CYN}${B}  ║        NVIDIA driver for Synology DSM · uninstaller       ║${R}"
say "${CYN}${B}  ╚══════════════════════════════════════════════════════════╝${R}"

# ------------------------------------------------------------ 1) ROOT check --
step "Step 1/6  Privilege check"
if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
  die "Must be run as ${B}root${R}. Try:  ${WHT}sudo $0${R}"
fi
ok "running as root"

# reverse order of install.sh -----------------------------------------------
hr
say "  This will unload the NVIDIA modules and remove ${WHT}$NVDIR${R}, the boot"
say "  hook, /usr/lib symlinks, device nodes, the nvidia-smi wrapper, and the"
say "  container runtime integration (if set up)."
warn "stop any GPU users first (Plex/Jellyfin transcodes) or unload may fail."
printf "%b" "  ${B}Continue? [y/N]: ${R}"; ask go; case "$go" in y|Y) ;; *) die "aborted by user" ;; esac

# ------------------------------------------------- 2) boot hook + wrapper --
step "Step 2/6  Removing boot hook & wrapper"
rm -f /usr/local/etc/rc.d/nvidia.sh && ok "removed rc.d/nvidia.sh" || warn "no boot hook"
rm -f /usr/bin/nvidia-smi          && ok "removed /usr/bin/nvidia-smi wrapper"

# ------------------------------------------------- 3) unload modules --
step "Step 3/6  Unloading kernel modules"
for m in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
  if lsmod 2>/dev/null | grep -q "^${m}\b"; then
    if rmmod "$m" 2>/dev/null; then ok "unloaded ${m}"; else warn "${m} busy - will clear on reboot"; fi
  fi
done
[ "$(lsmod 2>/dev/null | grep -c '^nvidia')" = "0" ] && ok "all nvidia modules unloaded" || warn "some modules still loaded (in use)"

# ------------------------------------------------- 4) device nodes --
step "Step 4/6  Removing device nodes"
rm -f /dev/nvidia0 /dev/nvidiactl /dev/nvidia-uvm /dev/nvidia-uvm-tools
rm -rf /dev/nvidia-caps
n=0; while [ $n -lt 8 ]; do rm -f "/dev/nvidia$n"; n=$((n+1)); done
ok "removed /dev/nvidia*"

# ------------------------------------------------- 5) files & symlinks --
step "Step 5/6  Removing driver files"
# /usr/lib symlinks that point into $NVDIR
cnt=0
for f in /usr/lib/*.so*; do
  [ -L "$f" ] || continue
  case "$(readlink "$f" 2>/dev/null)" in "$NVDIR"/*) rm -f "$f"; cnt=$((cnt+1)) ;; esac
done
ok "removed $cnt /usr/lib symlinks"
# kernel modules
rm -f /usr/lib/modules/nvidia.ko /usr/lib/modules/nvidia-uvm.ko \
      /usr/lib/modules/nvidia-modeset.ko /usr/lib/modules/nvidia-drm.ko \
      /usr/lib/modules/nvidia-peermem.ko
ok "removed nvidia*.ko from /usr/lib/modules"
# userspace tree
rm -rf "$NVDIR" && ok "removed $NVDIR"
# ld.so.conf.d entry (if any) + refresh
rm -f /etc/ld.so.conf.d/nvidia.conf 2>/dev/null
sed -i '\#/usr/local/nvidia/lib#d' /etc/ld.so.conf 2>/dev/null
[ -x /sbin/ldconfig ] && /sbin/ldconfig 2>/dev/null

# ------------------------------------------------- 6) container runtime --
step "Step 6/6  Removing container runtime (if set up)"
if [ -d "$CRDIR" ] || [ -f /etc/nvidia-container-runtime/config.toml ]; then
  DJ="$CMPKG/etc/dockerd.json"
  if [ -f "$DJ" ]; then
    if [ -f "$DJ.pre-nvidia.bak" ]; then
      mv "$DJ.pre-nvidia.bak" "$DJ"
      ok "daemon.json restored from pre-nvidia backup"
    elif command -v jq >/dev/null 2>&1; then
      NEWDJ="$(jq 'del(.runtimes.nvidia)' "$DJ" 2>/dev/null)"
      [ -n "$NEWDJ" ] && echo -E "$NEWDJ" > "$DJ" && ok "removed 'nvidia' runtime from daemon.json"
    else
      warn "no backup and no jq - daemon.json left untouched (remove .runtimes.nvidia manually)"
    fi
    warn "restart Container Manager to apply: sudo /usr/syno/bin/synopkg restart ContainerManager"
  fi
  # only remove /usr/sbin/ldconfig if it's the exact file install.sh placed
  # there (DSM had none originally) - never touch a real system ldconfig that
  # some future DSM update or other package might have installed since.
  if [ -f /usr/sbin/ldconfig ] && [ -f "$CRDIR/tools/ldconfig" ]; then
    A="$(sha256sum /usr/sbin/ldconfig 2>/dev/null | cut -d' ' -f1)"
    B="$(sha256sum "$CRDIR/tools/ldconfig" 2>/dev/null | cut -d' ' -f1)"
    [ -n "$A" ] && [ "$A" = "$B" ] && rm -f /usr/sbin/ldconfig && ok "removed /usr/sbin/ldconfig (ours)"
  fi
  rm -rf "$CRDIR" /etc/nvidia-container-runtime
  ok "removed $CRDIR and /etc/nvidia-container-runtime"
else
  ok "no container runtime found - nothing to do"
fi

hr
if [ "$(lsmod 2>/dev/null | grep -c '^nvidia')" != "0" ]; then
  say "${YEL}${B}  ✔ Uninstalled (files removed).${R} Modules still loaded (in use) -"
  say "  they will be gone after a ${WHT}reboot${R}."
else
  say "${GRN}${B}  ✔ Uninstall complete.${R}  No NVIDIA driver remains."
fi
hr
say ""
exit 0
