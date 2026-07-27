#!/bin/bash
#
# syno_nvidia_driver - interactive installer for a running Synology DSM.
#
# No-auth NVIDIA driver for physical / passthrough GPUs (no vGPU / license).
# Installs the 2-layer package (kernel modules + userspace) matched to this
# box's platform + DSM kernel, with an optional NVENC ffmpeg layer for the
# SynoCommunity Jellyfin package.
#
#   sudo ./install.sh
#
set -u

# ------------------------------------------------------------------ colours --
R='\033[0m'; B='\033[1m'; DIM='\033[2m'
RED='\033[1;31m'; GRN='\033[1;32m'; YEL='\033[1;33m'; BLU='\033[1;34m'
MAG='\033[1;35m'; CYN='\033[1;36m'; WHT='\033[1;37m'
say(){ printf "%b\n" "$*"; }
hr(){  say "${DIM}------------------------------------------------------------${R}"; }
step(){ say "\n${BLU}${B}▶ $*${R}"; }
ok(){   say "  ${GRN}✔${R} $*"; }
warn(){ say "  ${YEL}!${R} $*"; }
err(){  say "  ${RED}x${R} $*"; }
die(){  err "$*"; exit 1; }

banner(){
  say ""
  say "${CYN}${B}  ╔══════════════════════════════════════════════════════════╗${R}"
  say "${CYN}${B}  ║        NVIDIA driver for Synology DSM  (no-auth)          ║${R}"
  say "${CYN}${B}  ║        physical / passthrough GPU · installer            ║${R}"
  say "${CYN}${B}  ╚══════════════════════════════════════════════════════════╝${R}"
}

# --------------------------------------------------------- data / constants --
REPO_RAW="https://raw.githubusercontent.com/PeterSuh-Q3/syno_nvidia_driver/main"
IDX_URL="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/nvidiadriver/src/nvidia-index.json"
SUP_URL="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/nvidiadriver/src/nvidia-gpu-support.json"
IDX=/tmp/nvi-index.json
SUP=/tmp/nvi-support.json
DL=/tmp/nv-install
NVDIR=/usr/local/nvidia

need(){ command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found."; }

banner

# ============================================================ 1) ROOT check ==
step "Step 1/8  Privilege check"
if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
  die "Must be run as ${B}root${R}. Try:  ${WHT}sudo $0${R}"
fi
ok "running as root"
need jq; need curl

# ==================================================== 2) fetch catalog data ==
step "Step 2/8  Fetching driver catalog"
curl -skL "$IDX_URL" -o "$IDX" || die "cannot download index ($IDX_URL)"
curl -skL "$SUP_URL" -o "$SUP" || die "cannot download gpu-support ($SUP_URL)"
jq -e . "$IDX" >/dev/null 2>&1 || die "index is not valid JSON"
REL="$(jq -r '.release_base' "$IDX")"
ok "catalog loaded"

# ============================================ 3) PLATFORM check (before GPU) ==
step "Step 3/8  Platform support check"
PLATFORM="$(uname -a | awk '{print $NF}' | cut -d'_' -f2)"
KREL="$(uname -r)"
say "  platform : ${B}${PLATFORM}${R}   kernel: ${B}${KREL}${R}"
if ! jq -e --arg p "$PLATFORM" '.platforms[$p]' "$IDX" >/dev/null 2>&1; then
  err "platform ${B}${PLATFORM}${R} is ${RED}NOT supported${R} by this driver package."
  say "  supported platforms: ${YEL}$(jq -r '.platforms|keys|join(", ")' "$IDX")${R}"
  exit 1
fi
PKVER="$(jq -r --arg p "$PLATFORM" '.platforms[$p].kver' "$IDX")"
ok "supported (kver ${PKVER})"

# ==================================================== 4) GPU detect + guide ==
step "Step 4/8  NVIDIA GPU detection"
GPUID=""
for d in /sys/bus/pci/devices/*; do
  [ "$(cat "$d/vendor" 2>/dev/null)" = "0x10de" ] || continue
  case "$(cat "$d/class" 2>/dev/null)" in 0x0300*|0x0302*)
    GPUID="10de:$(sed 's/^0x//' "$d/device" 2>/dev/null | tr 'A-Z' 'a-z')"; break ;; esac
done
GNAME="Unknown"; GARCH=""; REC_BRANCH="$(jq -r '.default_branch' "$SUP" 2>/dev/null)"
GBRANCHES=""
if [ -n "$GPUID" ]; then
  GNAME="$(jq -r --arg g "$GPUID" '.gpus[$g].name // "Unknown NVIDIA GPU"' "$SUP")"
  GARCH="$(jq -r --arg g "$GPUID" '.gpus[$g].arch // ""' "$SUP")"
  GBRANCHES="$(jq -r --arg g "$GPUID" '.gpus[$g].branches // [] | join(", ")' "$SUP")"
  [ -n "$GBRANCHES" ] && REC_BRANCH="$(jq -r --arg g "$GPUID" '.gpus[$g].branches[0] // .default_branch' "$SUP")"
  ok "detected: ${WHT}${GNAME}${R}  (${GPUID}${GARCH:+, $GARCH})"
  [ -n "$GBRANCHES" ] && say "  compatible driver branches: ${CYN}${GBRANCHES}${R}   recommended: ${GRN}${REC_BRANCH}${R}"
else
  warn "no NVIDIA GPU detected on the PCI bus (passthrough not attached?)."
  warn "you can still install; recommended branch defaults to ${GRN}${REC_BRANCH}${R}"
fi

# ==================================================== 5) version selection ==
step "Step 5/8  Choose driver version"
V535="$(jq -r --arg p "$PLATFORM" '.platforms[$p].drivers | keys | map(select(startswith("535."))) | .[0] // empty' "$IDX")"
V550="$(jq -r --arg p "$PLATFORM" '.platforms[$p].drivers | keys | map(select(startswith("550."))) | .[0] // empty' "$IDX")"
tag_of(){ # $1 version -> "(verified)"/"(build-ok)"/"" for this GPU
  [ -n "$GPUID" ] || { echo ""; return; }
  [ "$(jq -r --arg g "$GPUID" --arg v "$1" '(.gpus[$g].verified // [])|index($v)' "$SUP" 2>/dev/null)" != "null" ] && { echo "${GRN}(verified)${R}"; return; }
  [ "$(jq -r --arg g "$GPUID" --arg v "$1" '(.gpus[$g].build_ok // [])|index($v)' "$SUP" 2>/dev/null)" != "null" ] && { echo "${YEL}(build-ok)${R}"; return; }
  echo ""
}
mark(){ [ "${REC_BRANCH}" = "$1" ] && printf "%b" " ${MAG}<= recommended for your GPU${R}"; }
say "  ${B}1)${R} 535 : ${WHT}${V535:-N/A}${R} $(tag_of "$V535")$(mark 535)"
say "  ${B}2)${R} 550 : ${WHT}${V550:-N/A}${R} $(tag_of "$V550")$(mark 550)"
DEF=1; [ "${REC_BRANCH}" = "550" ] && DEF=2
DRV=""
while :; do
  printf "%b" "  ${B}Select [1=535 / 2=550] (default ${DEF}): ${R}"
  read -r ans; ans="${ans:-$DEF}"
  case "$ans" in
    1) DRV="$V535" ;; 2) DRV="$V550" ;;
    *) warn "enter 1 or 2"; continue ;;
  esac
  [ -n "$DRV" ] && [ "$DRV" != "null" ] && break
  warn "that version is not available for ${PLATFORM}; pick the other one"
done
ok "selected driver ${WHT}${DRV}${R}"

# ==================================================== 6) optional ffmpeg ==
step "Step 6/8  NVENC ffmpeg (for SynoCommunity Jellyfin package)"
FFF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ffmpeg.file // empty' "$IDX")"
WANT_FF=false
if [ -n "$FFF" ]; then
  say "  ${DIM}Plex has its own transcoder and does NOT need this.${R}"
  say "  ${DIM}The Jellyfin *package* bundles a non-NVENC ffmpeg; this adds an NVENC one.${R}"
  printf "%b" "  ${B}Also install NVENC ffmpeg? [y/N]: ${R}"
  read -r a; case "$a" in y|Y) WANT_FF=true; ok "will install ffmpeg layer" ;; *) ok "skipping ffmpeg" ;; esac
else
  warn "no ffmpeg layer published for ${DRV}; skipping"
fi

# ==================================================== confirm & download ==
KOF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ko.file' "$IDX")"
USF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].userspace.file' "$IDX")"
hr
say "  ${B}About to install:${R}  driver ${WHT}${DRV}${R} for ${WHT}${PLATFORM}${R}, ffmpeg=${WANT_FF}"
printf "%b" "  ${B}Proceed? [Y/n]: ${R}"; read -r go; case "$go" in n|N) die "aborted by user" ;; esac

step "Step 7/8  Downloading layers"
rm -rf "$DL"; mkdir -p "$DL"
dl(){ say "  ↓ $2"; curl -kL# "$REL/$1" -o "$DL/$1" || die "download failed: $1"; [ -s "$DL/$1" ] || die "empty download: $1"; }
dl "$KOF" "kernel modules"
dl "$USF" "userspace libraries"
[ "$WANT_FF" = "true" ] && dl "$FFF" "NVENC ffmpeg"
ok "download complete"

# ==================================================== 8) install ==
step "Step 8/8  Installing"
# unload any currently-loaded nvidia modules (ignore if busy)
for m in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do rmmod "$m" 2>/dev/null; done

# kernel modules -> /usr/lib/modules
mkdir -p /usr/lib/modules
rm -rf "$DL/ko"; mkdir -p "$DL/ko"; tar -xzf "$DL/$KOF" -C "$DL/ko"
for ko in "$DL"/ko/*.ko; do [ -f "$ko" ] && cp -f "$ko" "/usr/lib/modules/$(basename "$ko")"; done
ok "kernel modules -> /usr/lib/modules"

# userspace -> /usr/local/nvidia
rm -rf "$NVDIR"; mkdir -p "$NVDIR"
tar -xzf "$DL/$USF" -C "$NVDIR"
( cd "$NVDIR/lib" 2>/dev/null && for f in *.so."$DRV"; do
    [ -f "$f" ] || continue; base="${f%.so.$DRV}.so"; ln -sf "$f" "$base.1"; ln -sf "$base.1" "$base"
  done ) 2>/dev/null
# expose libs on the default loader path (DSM lacks /etc/ld.so.conf.d)
( cd "$NVDIR/lib" 2>/dev/null && for so in *.so*; do [ -e "$so" ] && ln -sf "$NVDIR/lib/$so" "/usr/lib/$so"; done ) 2>/dev/null
ok "userspace -> $NVDIR/lib  (+ /usr/lib symlinks)"

# optional ffmpeg
if [ "$WANT_FF" = "true" ]; then
  mkdir -p "$NVDIR/bin"; tar -xzf "$DL/$FFF" -C "$NVDIR"; chmod +x "$NVDIR/bin/ffmpeg" "$NVDIR/bin/ffprobe" 2>/dev/null
  ok "ffmpeg -> $NVDIR/bin/ffmpeg  (set Jellyfin 'FFmpeg path' to this)"
fi

# nvidia-smi convenience wrapper (junior DSM PATH lacks /usr/local/nvidia/bin)
cat > /usr/bin/nvidia-smi <<WRAP
#!/bin/sh
exec env LD_LIBRARY_PATH=$NVDIR/lib $NVDIR/bin/nvidia-smi "\$@"
WRAP
chmod +x /usr/bin/nvidia-smi

# boot hook so it survives reboot (reload modules + nodes + relink libs)
RCD=/usr/local/etc/rc.d; mkdir -p "$RCD"
cat > "$RCD/nvidia.sh" <<'RC'
#!/bin/sh
case "$1" in start|"")
  for m in nvidia nvidia-uvm nvidia-modeset nvidia-drm; do
    [ -f "/usr/lib/modules/$m.ko" ] && /sbin/insmod "/usr/lib/modules/$m.ko" 2>/dev/null
  done
  major=$(awk '$2=="nvidia-frontend"||$2=="nvidia"{print $1}' /proc/devices | head -1)
  ngpu=$(ls -d /proc/driver/nvidia/gpus/* 2>/dev/null | wc -l); [ "$ngpu" -ge 1 ] || ngpu=1
  [ -n "$major" ] && { [ -e /dev/nvidiactl ] || mknod -m 666 /dev/nvidiactl c "$major" 255; n=0; while [ "$n" -lt "$ngpu" ]; do [ -e /dev/nvidia$n ] || mknod -m 666 /dev/nvidia$n c "$major" $n; n=$((n+1)); done; }
  umajor=$(awk '$2=="nvidia-uvm"{print $1}' /proc/devices | head -1)
  [ -n "$umajor" ] && { [ -e /dev/nvidia-uvm ] || mknod -m 666 /dev/nvidia-uvm c "$umajor" 0; }
  for so in /usr/local/nvidia/lib/*.so*; do [ -e "$so" ] && ln -sf "$so" "/usr/lib/$(basename "$so")"; done
  [ -x /sbin/ldconfig ] && /sbin/ldconfig 2>/dev/null
  ;;
esac
RC
chmod +x "$RCD/nvidia.sh"
ok "boot hook installed ($RCD/nvidia.sh)"

# load now
"$RCD/nvidia.sh" start
[ -x /sbin/ldconfig ] && /sbin/ldconfig 2>/dev/null

# ==================================================== verify ==
hr
LOADED="$(lsmod 2>/dev/null | grep -c '^nvidia')"
if nvidia-smi >/tmp/nvsmi.out 2>&1; then
  say "${GRN}${B}  ✔ SUCCESS${R}  driver ${WHT}${DRV}${R} installed and GPU is live:"
  say "${DIM}$(sed 's/^/    /' /tmp/nvsmi.out | head -12)${R}"
else
  warn "modules loaded: ${LOADED}; nvidia-smi did not report a GPU yet."
  say "  ${DIM}$(head -3 /tmp/nvsmi.out 2>/dev/null | sed 's/^/    /')${R}"
  say "  If no GPU is attached (passthrough), attach it and reboot."
fi
hr
say "  run ${WHT}nvidia-smi${R} anytime"
say "  to uninstall: ${WHT}sudo curl -skLO ${REPO_RAW}/uninstall.sh && sudo bash uninstall.sh${R}"
say ""
rm -rf "$DL" /tmp/nvsmi.out 2>/dev/null
exit 0
