#!/bin/bash
#
# syno_nvidia_driver - interactive installer for a running Synology DSM.
#
# No-auth NVIDIA driver for physical / passthrough GPUs (no vGPU / license).
# Installs the 2-layer package (kernel modules + userspace) matched to this
# box's platform + DSM kernel, with an optional NVENC ffmpeg layer for the
# SynoCommunity Jellyfin package.
#
#   sudo bash install.sh                 # after downloading
#   curl -sL <this-url> | sudo bash      # one-liner (prompts read from tty)
#
set -u
# Read a prompt from the terminal, NOT from stdin. With `curl -sL URL | sudo
# bash` bash reads the *script* from stdin, so prompts must come from /dev/tty;
# a global `exec </dev/tty` would break that (bash would read the rest of the
# script from the tty). No tty (non-interactive) -> empty -> caller's default.
ask(){ eval "$1=''"; IFS= read -r "$1" </dev/tty 2>/dev/null || true; }

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
V470="$(jq -r --arg p "$PLATFORM" '.platforms[$p].drivers | keys | map(select(startswith("470."))) | .[0] // empty' "$IDX")"
V580="$(jq -r --arg p "$PLATFORM" '.platforms[$p].drivers | keys | map(select(startswith("580."))) | .[0] // empty' "$IDX")"
# 580 needs GSP firmware on Turing+ (compute capability >= 7.5). We ship it
# for chips the index has a matching blob for (gsp_fw name -> gsp_firmware.
# <driver>.chips); GPUs needing GSP but with no available blob (currently
# Ada/RTX 40, Blackwell/RTX 50 - NVIDIA's .run doesn't bundle their firmware)
# still hit the hard warning gate below.
NEEDS_GSP="$(jq -r --arg g "$GPUID" '.gpus[$g].needs_gsp // false' "$SUP" 2>/dev/null)"
GSP_FW="$(jq -r --arg g "$GPUID" '.gpus[$g].gsp_fw // empty' "$SUP" 2>/dev/null)"
CUDA_MAX="$(jq -r --arg g "$GPUID" '.gpus[$g].cuda_max // empty' "$SUP" 2>/dev/null)"
tag_of(){ # $1 version -> "(verified)"/"(build-ok)"/"" for this GPU
  [ -n "$GPUID" ] || { echo ""; return; }
  [ "$(jq -r --arg g "$GPUID" --arg v "$1" '(.gpus[$g].verified // [])|index($v)' "$SUP" 2>/dev/null)" != "null" ] && { echo "${GRN}(verified)${R}"; return; }
  [ "$(jq -r --arg g "$GPUID" --arg v "$1" '(.gpus[$g].build_ok // [])|index($v)' "$SUP" 2>/dev/null)" != "null" ] && { echo "${YEL}(build-ok)${R}"; return; }
  echo ""
}
mark(){ [ "${REC_BRANCH}" = "$1" ] && printf "%b" " ${MAG}<= recommended for your GPU${R}"; }
say "  ${B}1)${R} 535 : ${WHT}${V535:-N/A}${R} $(tag_of "$V535")$(mark 535)  ${DIM}(Production/LTS, Maxwell..Ada)${R}"
say "  ${B}2)${R} 550 : ${WHT}${V550:-N/A}${R} $(tag_of "$V550")$(mark 550)  ${DIM}(newest)${R}"
say "  ${B}3)${R} 470 : ${WHT}${V470:-N/A}${R} $(tag_of "$V470")$(mark 470)  ${DIM}(legacy LTSB, Kepler..Ampere; for older GPUs)${R}"
say "  ${B}4)${R} 580 : ${WHT}${V580:-N/A}${R} $(tag_of "$V580")$(mark 580)  ${DIM}(newest branch, Maxwell..Ampere w/ GSP fw, highest CUDA)${R}"
[ -n "$CUDA_MAX" ] && say "  ${DIM}Your GPU tops out at ${WHT}CUDA ${CUDA_MAX}${R}${DIM} - set by its compute capability, not by the driver.${R}"
DEF=1; [ "${REC_BRANCH}" = "550" ] && DEF=2; [ "${REC_BRANCH}" = "470" ] && DEF=3; [ "${REC_BRANCH}" = "580" ] && DEF=4
DRV=""
while :; do
  printf "%b" "  ${B}Select [1=535 / 2=550 / 3=470 / 4=580] (default ${DEF}): ${R}"
  ask ans; ans="${ans:-$DEF}"
  case "$ans" in
    1) DRV="$V535" ;; 2) DRV="$V550" ;; 3) DRV="$V470" ;; 4) DRV="$V580" ;;
    *) warn "enter 1, 2, 3 or 4"; continue ;;
  esac
  [ -n "$DRV" ] && [ "$DRV" != "null" ] && break
  warn "that version is not available for ${PLATFORM}; pick another"
done
# Guard: 580 on a GSP-requiring GPU with no available firmware would install
# but fail to initialise. If we DO have a matching blob, just note it - Step 8
# deploys it automatically, no confirmation needed.
GSP_AVAIL=""
if [ -n "$GSP_FW" ] && [ "$GSP_FW" != "null" ]; then
  GSP_AVAIL="$(jq -r --arg d "$DRV" --arg f "$GSP_FW" '.gsp_firmware[$d].chips // [] | index($f) // empty' "$IDX" 2>/dev/null)"
fi
case "$DRV" in
  580.*) if [ "$NEEDS_GSP" = "true" ]; then
           if [ -n "$GSP_AVAIL" ]; then
             say "  ${DIM}${GNAME:-this GPU} needs GSP firmware (${GSP_FW}) - will be installed automatically.${R}"
           else
             warn "${WHT}${GNAME:-Your GPU}${R} is Turing or newer and needs ${B}GSP firmware${R} on 580,"
             warn "and ${B}no firmware blob is available yet${R} for this chip - the driver would"
             warn "load but fail to initialise."
             warn "Pick ${B}1 (535)${R} or ${B}2 (550)${R} instead until GSP support lands for it."
             printf "%b" "  ${B}Continue with 580 anyway? [y/N]: ${R}"
             ask g; case "$g" in y|Y) ;; *) die "aborted - re-run and choose 535 or 550" ;; esac
           fi
         fi ;;
esac
ok "selected driver ${WHT}${DRV}${R}"

# ==================================================== 6) optional ffmpeg ==
step "Step 6/8  NVENC ffmpeg (for SynoCommunity Jellyfin package)"
FFF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ffmpeg.file // empty' "$IDX")"
WANT_FF=false
if [ -n "$FFF" ]; then
  say "  ${DIM}Plex has its own transcoder and does NOT need this.${R}"
  say "  ${DIM}The Jellyfin *package* bundles a non-NVENC ffmpeg; this adds an NVENC one.${R}"
  printf "%b" "  ${B}Also install NVENC ffmpeg? [y/N]: ${R}"
  ask a; case "$a" in y|Y) WANT_FF=true; ok "will install ffmpeg layer" ;; *) ok "skipping ffmpeg" ;; esac
else
  warn "no ffmpeg layer published for ${DRV}; skipping"
fi

# ==================================================== confirm & download ==
KOF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ko.file' "$IDX")"
USF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].userspace.file' "$IDX")"
hr
say "  ${B}About to install:${R}  driver ${WHT}${DRV}${R} for ${WHT}${PLATFORM}${R}, ffmpeg=${WANT_FF}"
printf "%b" "  ${B}Proceed? [Y/n]: ${R}"; ask go; case "$go" in n|N) die "aborted by user" ;; esac

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
# Record which platform these .ko were built for. All kver5 platforms share
# the exact same vermagic string (5.10.55+ SMP mod_unload), so the kernel's
# own vermagic check does NOT catch a .ko from the wrong platform - and
# per-platform kernel .config can genuinely differ (e.g. backlight/acpi_video
# on/off). The boot hook below checks this marker before insmod so a leftover
# module from a previous platform (e.g. after switching the loader's declared
# platform without uninstalling first) can't get silently auto-loaded.
echo "$PLATFORM" > /usr/lib/modules/.nvidia-platform
ok "kernel modules -> /usr/lib/modules"

# GSP firmware -> /lib/firmware/nvidia/<driver_ver>/ (must exist BEFORE the
# nvidia module is loaded below - it's requested via request_firmware() at
# probe time). Persistent: /lib/firmware lives on the same rw root (/dev/md0)
# as everything else here, no re-deploy needed on later boots.
if [ -n "$GSP_AVAIL" ]; then
  GFF="$(jq -r --arg d "$DRV" '.gsp_firmware[$d].file' "$IDX")"
  GFSHA="$(jq -r --arg d "$DRV" '.gsp_firmware[$d].sha256' "$IDX")"
  say "  ↓ GSP firmware"
  curl -kL# "$REL/$GFF" -o "$DL/$GFF" || die "download failed: $GFF"
  [ -s "$DL/$GFF" ] || die "empty download: $GFF"
  GGOT="$(sha256sum "$DL/$GFF" 2>/dev/null | cut -d' ' -f1)"
  [ -z "$GGOT" ] || [ "$GGOT" = "$GFSHA" ] || die "sha256 mismatch for $GFF"
  FWDIR="/lib/firmware/nvidia/$DRV"
  mkdir -p "$FWDIR"
  tar -xzf "$DL/$GFF" -C "$DL" firmware
  cp -f "$DL/firmware/$GSP_FW" "$FWDIR/$GSP_FW"
  ok "GSP firmware -> $FWDIR/$GSP_FW"
fi

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

# nvidia-smi convenience "wrapper" - a REAL COPY of the binary, not a shell
# script. A shell-script wrapper works fine when run on the host (the target
# path it execs still exists), but nvidia-container-cli discovers /usr/bin/
# nvidia-smi by path and bind-mounts *that exact file* into containers - where
# $NVDIR doesn't exist, so the wrapper's `exec` fails with "No such file or
# directory". The real binary needs no LD_LIBRARY_PATH since its libs are
# already exposed on the default loader path via the /usr/lib symlinks above.
cp -f "$NVDIR/bin/nvidia-smi" /usr/bin/nvidia-smi
chmod +x /usr/bin/nvidia-smi

# boot hook so it survives reboot (reload modules + nodes + relink libs)
RCD=/usr/local/etc/rc.d; mkdir -p "$RCD"
cat > "$RCD/nvidia.sh" <<'RC'
#!/bin/sh
case "$1" in start|"")
  # Platform guard: skip loading if the installed .ko were built for a
  # different platform than the one currently running. vermagic alone can't
  # catch this (identical text across kver5 platforms) and per-platform
  # kernel .config can genuinely differ - loading the wrong .ko is not
  # guaranteed safe even though insmod itself might not refuse it.
  CURP="$(uname -a | awk '{print $NF}' | cut -d'_' -f2)"
  STOREDP="$(cat /usr/lib/modules/.nvidia-platform 2>/dev/null)"
  if [ -n "$STOREDP" ] && [ "$STOREDP" != "$CURP" ]; then
    logger -t nvidia.sh "SKIPPED: installed .ko are for platform '$STOREDP' but running on '$CURP' - re-run install.sh for this platform (or uninstall.sh first)" 2>/dev/null
    exit 0
  fi
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

# ============================================ 9) optional: container runtime ==
CMPKG=/var/packages/ContainerManager
CRDIR=/usr/local/nvidia-runtime
if [ -d "$CMPKG" ]; then
  hr
  step "Step 9 (optional)  Container Manager (Docker) integration"
  say "  ${DIM}Lets 'docker run --runtime=nvidia --gpus all ...' containers see this GPU.${R}"
  printf "%b" "  ${B}Also set up the container runtime? [y/N]: ${R}"
  ask cr
  case "$cr" in
    y|Y)
      CRF="$(jq -r '.container_runtime.file' "$IDX")"
      CRSHA="$(jq -r '.container_runtime.sha256' "$IDX")"
      if [ -z "$CRF" ] || [ "$CRF" = "null" ]; then
        warn "no container_runtime layer published in the index; skipping"
      else
        mkdir -p "$DL"
        say "  ↓ container runtime layer"
        curl -kL# "$REL/$CRF" -o "$DL/$CRF" || die "download failed: $CRF"
        [ -s "$DL/$CRF" ] || die "empty download: $CRF"
        GOTSHA="$(sha256sum "$DL/$CRF" 2>/dev/null | cut -d' ' -f1)"
        [ -z "$GOTSHA" ] || [ "$GOTSHA" = "$CRSHA" ] || die "sha256 mismatch for $CRF"

        # extract straight to its final, exec-permitted home - /tmp is noexec on DSM
        rm -rf "$CRDIR"; mkdir -p "$CRDIR"
        tar -xzf "$DL/$CRF" -C "$CRDIR"
        chmod +x "$CRDIR"/bin/* "$CRDIR"/tools/* 2>/dev/null
        ok "runtime -> $CRDIR"

        # DSM ships no ldconfig/ld.so.cache; nvidia-container-cli needs one to
        # locate the driver's libs. Build our own with the bundled static ldconfig.
        "$CRDIR/tools/ldconfig" -C "$CRDIR/ld.so.cache" \
          /usr/lib "$NVDIR/lib" "$CRDIR/lib" 2>/dev/null

        # nvidia-ctk's own OCI hooks (e.g. `hook update-ldcache`, used inside
        # containers) hardcode a --ldconfig-path default of /sbin/ldconfig and
        # do NOT pick up config.toml's [nvidia-container-cli] ldconfig= key for
        # that default - config threading only covers the classic CLI path.
        # DSM has neither /sbin nor /usr/sbin/ldconfig at all (confirmed empty
        # slot, not an overwrite), so fill it with our bundled static binary -
        # this is what every downstream hook actually ends up calling.
        if [ ! -e /usr/sbin/ldconfig ]; then
          cp "$CRDIR/tools/ldconfig" /usr/sbin/ldconfig
          chmod +x /usr/sbin/ldconfig
          ok "installed static ldconfig -> /usr/sbin/ldconfig (DSM had none)"
        fi

        mkdir -p /etc/nvidia-container-runtime
        cat > /etc/nvidia-container-runtime/config.toml <<TOML
[nvidia-container-cli]
root = "/"
path = "$CRDIR/bin/nvidia-container-cli"
ldcache = "$CRDIR/ld.so.cache"
ldconfig = "@/usr/sbin/ldconfig"
environment = ["LD_LIBRARY_PATH=$CRDIR/lib"]

[nvidia-container-runtime]
runtimes = ["/var/packages/ContainerManager/target/usr/bin/runc"]

[nvidia-container-runtime-hook]
path = "$CRDIR/bin/nvidia-container-runtime-hook"

[nvidia-ctk]
path = "$CRDIR/bin/nvidia-ctk"
TOML
        ok "ld.so.cache built, config.toml written"

        # register the 'nvidia' runtime in Container Manager's daemon.json -
        # merge, never overwrite: DSM already has bip/data-root/etc in there.
        DJ="$CMPKG/etc/dockerd.json"
        if [ -f "$DJ" ]; then
          cp "$DJ" "$DJ.pre-nvidia.bak"
          NEWDJ="$(jq --arg p "$CRDIR/bin/nvidia-container-runtime" \
            '.runtimes.nvidia = {"path": $p, "runtimeArgs": []}' "$DJ")"
          if [ -n "$NEWDJ" ]; then
            echo -E "$NEWDJ" > "$DJ"
            ok "daemon.json: 'nvidia' runtime registered (backup: $DJ.pre-nvidia.bak)"
            warn "restart Container Manager to apply: sudo /usr/syno/bin/synopkg restart ContainerManager"
          else
            warn "failed to update daemon.json (jq error) - left untouched"
          fi
        else
          warn "daemon.json not found at $DJ - register the 'nvidia' runtime manually"
        fi
        say "  ${DIM}test after restart:${R}"
        say "  ${DIM}  docker run --rm --runtime=nvidia -e NVIDIA_VISIBLE_DEVICES=all${R} \\"
        say "  ${DIM}    nvidia/cuda:12.9.0-base-ubuntu24.04 nvidia-smi${R}"
        say "  ${DIM}(the plain '--gpus all' flag needs Docker 25+ CDI support, which this${R}"
        say "  ${DIM}Container Manager version does not have - use --runtime=nvidia instead.)${R}"
      fi
      ;;
    *) ok "skipping container runtime setup" ;;
  esac
fi

say ""
rm -rf "$DL" /tmp/nvsmi.out 2>/dev/null
exit 0
