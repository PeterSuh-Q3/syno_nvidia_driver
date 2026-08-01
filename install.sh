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
# "4.4.302+" -> "4.4.302". The trailing '+' is Synology's localversion marker;
# the index keys kernels by the bare x.y.z.
KVER="$(echo "$KREL" | sed 's/[^0-9.].*$//')"
say "  platform : ${B}${PLATFORM}${R}   kernel: ${B}${KREL}${R}"
if ! jq -e --arg p "$PLATFORM" '.platforms[$p]' "$IDX" >/dev/null 2>&1; then
  err "platform ${B}${PLATFORM}${R} is ${RED}NOT supported${R} by this driver package."
  say "  supported platforms: ${YEL}$(jq -r '.platforms|keys|join(", ")' "$IDX")${R}"
  exit 1
fi
# The platform NAME alone does not identify the kernel ABI: the same platform
# ships different kernels across DSM releases (broadwell & friends are 4.4.180
# on DSM 7.0/7.1 but 4.4.302 on 7.2+). Module vermagic embeds the exact
# version, so insmod refuses a mismatch - we must pick by platform AND kernel.
# Platforms that exist on more than one kernel carry a 'kernels' map keyed by
# version; single-kernel platforms keep the flat 'drivers' plus a 'kver' that
# we now verify instead of trusting blindly.
if jq -e --arg p "$PLATFORM" '.platforms[$p].kernels' "$IDX" >/dev/null 2>&1; then
  if ! jq -e --arg p "$PLATFORM" --arg k "$KVER" '.platforms[$p].kernels[$k]' "$IDX" >/dev/null 2>&1; then
    err "platform ${B}${PLATFORM}${R} is supported, but not on kernel ${B}${KVER}${R}."
    say "  modules are published for: ${YEL}$(jq -r --arg p "$PLATFORM" '.platforms[$p].kernels|keys|join(", ")' "$IDX")${R}"
    exit 1
  fi
  PKVER="$KVER"
else
  PKVER="$(jq -r --arg p "$PLATFORM" '.platforms[$p].kver' "$IDX")"
  if [ "$PKVER" != "$KVER" ]; then
    err "modules for ${B}${PLATFORM}${R} are built against kernel ${B}${PKVER}${R}, but this box runs ${B}${KVER}${R}."
    say "  ${DIM}vermagic must match exactly - insmod would reject them.${R}"
    exit 1
  fi
fi
ok "supported (kernel ${PKVER})"
# Resolved drivers node: per-kernel entry when the platform has one, flat
# 'drivers' otherwise. Every lookup below goes through this.
DQ='(.platforms[$p].kernels[$k].drivers // .platforms[$p].drivers)'

# ==================================================== 4) GPU detect + guide ==
step "Step 4/8  NVIDIA GPU detection"
GPUID=""
for d in /sys/bus/pci/devices/*; do
  [ "$(cat "$d/vendor" 2>/dev/null)" = "0x10de" ] || continue
  case "$(cat "$d/class" 2>/dev/null)" in 0x0300*|0x0302*)
    GPUID="10de:$(sed 's/^0x//' "$d/device" 2>/dev/null | tr 'A-Z' 'a-z')"; break ;; esac
done
# Branches this release actually publishes for THIS platform + kernel. Every
# recommendation below is intersected with it, so we can never point at a
# driver the release does not carry - kver5 platforms have 470/535/550/580,
# kver4 platforms have 550 only, and the old code happily recommended 535 on
# both because `default_branch` was a single global value.
AVAIL="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" "$DQ"' | keys | map(.[0:3]) | unique | join(" ")' "$IDX")"
NEWEST_AVAIL="${AVAIL##* }"        # keys are sorted ascending -> last = newest
has_branch(){ case " $AVAIL " in *" $1 "*) return 0 ;; esac; return 1; }

GNAME="Unknown"; GARCH=""; GBRANCHES=""; GLEGACY=""; REC_BRANCH=""; GKNOWN=false
KMAJ="${KVER%%.*}"
if [ -n "$GPUID" ] && jq -e --arg g "$GPUID" '.gpus[$g]' "$SUP" >/dev/null 2>&1; then
  GKNOWN=true
  GNAME="$(jq -r --arg g "$GPUID" '.gpus[$g].name // "Unknown NVIDIA GPU"' "$SUP")"
  GARCH="$(jq -r --arg g "$GPUID" '.gpus[$g].arch // ""' "$SUP")"
  # space-separated, newest-preferred first - iterated as a word list below
  GBRANCHES="$(jq -r --arg g "$GPUID" '.gpus[$g].branches // [] | join(" ")' "$SUP")"
  GLEGACY="$(jq -r --arg g "$GPUID" '.gpus[$g].legacy_driver // ""' "$SUP")"
fi
# Read here, not in step 5: the GSP facts gate the recommendation itself.
NEEDS_GSP="$(jq -r --arg g "$GPUID" '.gpus[$g].needs_gsp // false' "$SUP" 2>/dev/null)"
GSP_FW="$(jq -r --arg g "$GPUID" '.gpus[$g].gsp_fw // empty' "$SUP" 2>/dev/null)"
CUDA_MAX="$(jq -r --arg g "$GPUID" '.gpus[$g].cuda_max // empty' "$SUP" 2>/dev/null)"
# 580 runs the open kernel module, which on Turing+ refuses to initialise
# without a GSP firmware blob. We only ship the blobs NVIDIA's .run bundles
# (Turing + consumer Ampere), so for Ada/Blackwell/GA100 580 is present but
# unusable - never *recommend* it there, even though it stays selectable.
gsp_blocked(){ [ "$1" = "580" ] && [ "$NEEDS_GSP" = "true" ] && [ -z "$GSP_FW" ]; }
# Recommended = the newest branch the GPU supports that we also publish here.
for b in $GBRANCHES; do
  has_branch "$b" || continue
  gsp_blocked "$b" && continue
  REC_BRANCH="$b"; break
done
if [ -z "$REC_BRANCH" ]; then
  # No GPU match (or none of its branches are published): fall back to the
  # per-kernel default - 580 on kver5, 550 on kver4 - and only to a branch we
  # really have.
  KDEF="$(jq -r --arg k "$KMAJ" '.default_branch_by_kernel[$k] // .default_branch // empty' "$SUP" 2>/dev/null)"
  if [ -n "$KDEF" ] && has_branch "$KDEF"; then REC_BRANCH="$KDEF"; else REC_BRANCH="$NEWEST_AVAIL"; fi
fi

if [ -z "$GPUID" ]; then
  warn "no NVIDIA GPU detected on the PCI bus (passthrough not attached?)."
  warn "you can still install; recommended branch defaults to ${GRN}${REC_BRANCH}${R}"
elif [ "$GKNOWN" != "true" ]; then
  ok "detected: ${WHT}${GPUID}${R}"
  warn "this PCI id is not in the GPU catalog - it is probably newer than the"
  warn "catalog build. Defaulting to ${GRN}${REC_BRANCH}${R} (newest branch for kernel ${KMAJ}.x)."
elif [ -n "$GLEGACY" ]; then
  # In NVIDIA's own supportedchips list this chip appears only under a legacy
  # branch (390.xx and older) that this project does not build at all. Nothing
  # we ship will bind to it - say so instead of installing a driver that loads
  # and then finds no device.
  ok "detected: ${WHT}${GNAME}${R}  (${GPUID}${GARCH:+, $GARCH})"
  err "${WHT}${GNAME}${R} is only supported by NVIDIA's ${B}${GLEGACY}${R} legacy driver,"
  err "which this project does not build. ${RED}No branch here will drive it.${R}"
  printf "%b" "  ${B}Install anyway (it will not work)? [y/N]: ${R}"
  ask lg; case "$lg" in y|Y) ;; *) die "aborted - unsupported GPU" ;; esac
else
  ok "detected: ${WHT}${GNAME}${R}  (${GPUID}${GARCH:+, $GARCH})"
  # Report what can be INSTALLED here, not the full NVIDIA support matrix. On a
  # kver4 platform a Pascal card is supported by 470/535/550/580 as far as
  # NVIDIA is concerned, but only 550 is built for kernel 4.4 - leading with the
  # full list just advertises drivers this box cannot get.
  USABLE=""; UNAVAIL=""
  for b in $GBRANCHES; do
    if has_branch "$b"; then USABLE="$USABLE $b"; else UNAVAIL="$UNAVAIL $b"; fi
  done
  if [ -z "$USABLE" ]; then
    err "supported by NVIDIA's ${CYN}$(echo "${GBRANCHES}" | tr ' ' ',' | sed 's/,/, /g')${R} branch(es),"
    err "none of which are published for ${B}${PLATFORM}${R} on kernel ${B}${KVER}${R}"
    err "(this platform has only: ${YEL}${AVAIL}${R}) - ${RED}nothing here will drive this GPU.${R}"
    printf "%b" "  ${B}Install anyway (it will not work)? [y/N]: ${R}"
    ask nb; case "$nb" in y|Y) ;; *) die "aborted - no compatible driver for this platform/kernel" ;; esac
  elif [ "$USABLE" = " 580" ] && gsp_blocked 580; then
    # Only 580 lists this GPU, and 580 cannot initialise it without a firmware
    # blob we do not have (Ada / Blackwell / GA100). Nothing usable - but 580 is
    # still the least-wrong pick, so recommend it and be explicit about why.
    err "only ${B}580${R} lists it, and 580 needs a ${B}GSP firmware${R} blob for this chip"
    err "that NVIDIA's .run does not bundle - ${RED}the driver will load but not initialise.${R}"
    warn "nothing here can drive this GPU yet; continue only to test."
  else
    say "  installable driver branches: ${CYN}${USABLE# }${R}   recommended: ${GRN}${REC_BRANCH}${R}"
    # Mention the rest only as a footnote, so it reads as "you are not missing
    # anything installable" rather than as an option.
    [ -n "$UNAVAIL" ] && say "  ${DIM}(NVIDIA also supports it on ${UNAVAIL# }, not built for kernel ${KVER} - kver5 platforms only)${R}"
    gsp_blocked 580 && warn "580 is skipped as a recommendation: it needs a GSP firmware blob we don't ship for this chip."
  fi
fi

# ==================================================== 5) version selection ==
step "Step 5/8  Choose driver version"
V535="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" "$DQ"' | keys | map(select(startswith("535."))) | .[0] // empty' "$IDX")"
V550="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" "$DQ"' | keys | map(select(startswith("550."))) | .[0] // empty' "$IDX")"
V470="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" "$DQ"' | keys | map(select(startswith("470."))) | .[0] // empty' "$IDX")"
V580="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" "$DQ"' | keys | map(select(startswith("580."))) | .[0] // empty' "$IDX")"
# NEEDS_GSP / GSP_FW / CUDA_MAX were read in step 4 - they gate the branch
# recommendation, so they have to exist before it is computed. The hard warning
# gate below still uses them: GPUs needing GSP with no available blob (currently
# Ada/RTX 40, Blackwell/RTX 50 - NVIDIA's .run doesn't bundle their firmware)
# stay selectable but must be confirmed.
tag_of(){ # $1 version -> "(verified)"/"(build-ok)"/"" for this GPU
  [ -n "$GPUID" ] || { echo ""; return; }
  [ "$(jq -r --arg g "$GPUID" --arg v "$1" '(.gpus[$g].verified // [])|index($v)' "$SUP" 2>/dev/null)" != "null" ] && { echo "${GRN}(verified)${R}"; return; }
  [ "$(jq -r --arg g "$GPUID" --arg v "$1" '(.gpus[$g].build_ok // [])|index($v)' "$SUP" 2>/dev/null)" != "null" ] && { echo "${YEL}(build-ok)${R}"; return; }
  echo ""
}
mark(){ [ "${REC_BRANCH}" = "$1" ] && printf "%b" " ${MAG}<= recommended${R}"; }
# Flag branches the DETECTED GPU is not on. Silent when no GPU was detected or
# it is not in the catalog - we have nothing to judge against there.
incompat(){
  [ -n "$GBRANCHES" ] || return 0
  case " $GBRANCHES " in *" $1 "*) ;; *) printf "%b" " ${RED}(not supported by ${GNAME})${R}" ;; esac
}
desc_of(){ case "$1" in
  580) echo "newest, Maxwell..Blackwell, highest CUDA; Turing+ needs GSP fw" ;;
  550) echo "Maxwell..Ada, superseded by 580 on kver5" ;;
  535) echo "Production/LTS, Maxwell..Ada" ;;
  470) echo "legacy LTSB, Kepler..Ampere; the only branch for Kepler" ;;
esac; }
# The menu lists ONLY what is published for this platform+kernel, newest first.
# It used to print a fixed 1=535/2=550/3=470/4=580 with "N/A" on the missing
# ones, which on a kver4 platform meant three of the four entries could not be
# installed at all - and a Pascal card there was still being pointed at 580,
# a driver that exists only for kernel 5. Numbering is therefore dynamic.
set --
for b in 580 550 535 470; do has_branch "$b" && set -- "$@" "$b"; done
NBR=$#
[ "$NBR" -ge 1 ] || die "no driver published for ${PLATFORM} on kernel ${KVER}"
i=0; DEF=1
for b in "$@"; do
  i=$((i+1))
  eval "MB$i=$b; MV$i=\$V$b"
  [ "$b" = "$REC_BRANCH" ] && DEF=$i
  eval "v=\$V$b"
  say "  ${B}$i)${R} $b : ${WHT}${v}${R} $(tag_of "$v")$(mark "$b")$(incompat "$b")  ${DIM}($(desc_of "$b"))${R}"
done
[ -n "$CUDA_MAX" ] && say "  ${DIM}Your GPU tops out at ${WHT}CUDA ${CUDA_MAX}${R}${DIM} - set by its compute capability, not by the driver.${R}"
DRV=""; BR=""
# One published branch (every kver4 platform) = nothing to choose. Skip the
# prompt rather than asking a question with a single answer.
if [ "$NBR" -eq 1 ]; then
  eval "DRV=\$MV1; BR=\$MB1"
  say "  ${DIM}${BR} is the only branch built for ${PLATFORM} on kernel ${KVER} - selected automatically.${R}"
fi
while [ "$NBR" -gt 1 ]; do
  PICKS=""; i=0
  for b in "$@"; do i=$((i+1)); PICKS="$PICKS / $i=$b"; done
  printf "%b" "  ${B}Select [${PICKS# / }] (default ${DEF}): ${R}"
  ask ans; ans="${ans:-$DEF}"
  case "$ans" in
    ''|*[!0-9]*) warn "enter a number between 1 and ${NBR}"; continue ;;
  esac
  if [ "$ans" -lt 1 ] || [ "$ans" -gt "$NBR" ]; then
    warn "enter a number between 1 and ${NBR}"; continue
  fi
  eval "DRV=\$MV$ans; BR=\$MB$ans"
  # Picking a branch that does not list this GPU installs cleanly and then
  # binds to nothing (nvidia-smi: "No devices were found"). Confirm, don't block
  # - the catalog can lag a brand-new SKU.
  if [ -n "$GBRANCHES" ]; then
    case " $GBRANCHES " in
      *" $BR "*) ;;
      *) warn "${B}${BR}${R} does not list ${WHT}${GNAME}${R} as supported - it would load but find no GPU."
         printf "%b" "  ${B}Use ${BR} anyway? [y/N]: ${R}"
         ask ic; case "$ic" in y|Y) ;; *) continue ;; esac ;;
    esac
  fi
  break
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
             # Name the branches that actually list this GPU - telling a
             # Blackwell owner to "pick 535 or 550" is a dead end, 580 is the
             # only branch that knows the chip at all.
             ALT=""; for b in $GBRANCHES; do [ "$b" = "580" ] || { has_branch "$b" && ALT="$ALT or $b"; }; done
             ALT="${ALT# or }"
             if [ -n "$ALT" ]; then
               warn "Pick ${B}${ALT}${R} instead until GSP support lands for it."
             else
               warn "No other branch here supports this GPU - there is no working option yet."
             fi
             printf "%b" "  ${B}Continue with 580 anyway? [y/N]: ${R}"
             ask g; case "$g" in y|Y) ;; *) die "aborted${ALT:+ - re-run and choose${ALT}}" ;; esac
           fi
         fi ;;
esac
ok "selected driver ${WHT}${DRV}${R}"

# ==================================================== 6) optional ffmpeg ==
step "Step 6/8  NVENC ffmpeg (for SynoCommunity Jellyfin package)"
FFF="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].ffmpeg.file // empty' "$IDX")"
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
KOF="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].ko.file' "$IDX")"
USF="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].userspace.file' "$IDX")"
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
# The kernel version goes in too: a DSM upgrade (7.1 -> 7.2) keeps the platform
# name but moves 4.4.180 -> 4.4.302, which silently invalidates these modules.
echo "$PLATFORM $PKVER" > /usr/lib/modules/.nvidia-platform
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
  ok "ffmpeg -> $NVDIR/bin/ffmpeg"

  # SynoCommunity's Jellyfin package hardcodes the ffmpeg path as a *command
  # line argument* in its service-setup:
  #     --ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg
  # That argument outranks encoding.xml and greys out the Dashboard field
  # (encoding.xml only keeps a read-only EncoderAppPathDisplay), so the user
  # cannot point Jellyfin at our NVENC build from the UI at all. The ffmpeg7
  # package's own binary has no NVENC encoders, so transcoding stays on CPU.
  # Patch the launch argument instead of touching ffmpeg7's files: the arg is
  # Jellyfin-local, and ffmpeg7 is a dependency of Jellyfin only.
  # Jellyfin resolves ffprobe from the same directory, and our layer ships
  # both, so pointing at our bin/ is sufficient.
  JF_SS=/var/packages/jellyfin/scripts/service-setup
  if [ -f "$JF_SS" ] && grep -q -- '--ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg' "$JF_SS"; then
    say "  ${DIM}Jellyfin package forces its ffmpeg path via a launch argument.${R}"
    printf "%b" "  ${B}Point Jellyfin at the NVENC ffmpeg? [y/N]: ${R}"
    ask jf
    case "$jf" in
      y|Y)
        cp -n "$JF_SS" "$JF_SS.pre-nvidia.bak" 2>/dev/null
        sed -i "s#--ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg#--ffmpeg $NVDIR/bin/ffmpeg#" "$JF_SS"
        # sed -i (and cp above) rebuild the file under the current umask,
        # which does not preserve the original 755 - confirmed on real
        # hardware landing as root:root 700. DSM runs this script as the
        # package's own service account (sc-jellyfin), so a non-executable
        # file makes Jellyfin exit within ~20s ("abnormal status") before it
        # logs anything - looks like a crash, is really a permissions
        # regression. Force both files back to what every sibling script in
        # that directory already is.
        chown root:root "$JF_SS" "$JF_SS.pre-nvidia.bak" 2>/dev/null
        chmod 755 "$JF_SS" "$JF_SS.pre-nvidia.bak" 2>/dev/null
        ok "Jellyfin -> $NVDIR/bin/ffmpeg  (backup: $JF_SS.pre-nvidia.bak)"
        warn "restart Jellyfin to apply: sudo /usr/syno/bin/synopkg restart jellyfin"
        warn "a Jellyfin package UPDATE overwrites this - re-run this installer after one"

        # Jellyfin ships with hardware acceleration off and expects the user
        # to hand-pick NVENC in Dashboard -> Playback, then hand-pick which
        # decode codecs are safe to turn on - something nobody can answer
        # without NVIDIA's per-architecture capability tables. Offer to do
        # what Plex does automatically, but GPU-model-aware (Plex is not):
        # encoders are probed against the real card so a Pascal box never
        # gets AV1 turned on and a Kepler box never gets HEVC.
        #
        # jellyfin-autoconfig.sh is written to disk (not run in-process) so
        # the boot hook - a separate /bin/sh process spawned from a heredoc,
        # sharing no shell state with this installer - can call the exact
        # same logic later if encoding.xml does not exist yet at install
        # time. Single source of truth instead of two copies drifting apart.
        curl -skL "${REPO_RAW}/jellyfin-autoconfig.sh" -o "$NVDIR/bin/jellyfin-autoconfig.sh" \
          && chmod +x "$NVDIR/bin/jellyfin-autoconfig.sh"
        [ -n "$GARCH" ] && echo "$GARCH" > /usr/lib/modules/.nvidia-gpuarch 2>/dev/null
        JF_CFG=/var/packages/jellyfin/var/config/encoding.xml
        if [ -x "$NVDIR/bin/jellyfin-autoconfig.sh" ] && [ -f "$JF_CFG" ]; then
          say "  ${DIM}Also set NVENC + presets + a RAM transcode scratch dir in encoding.xml?${R}"
          printf "%b" "  ${B}Auto-configure Jellyfin's hardware transcoding? [y/N]: ${R}"
          ask hc
          case "$hc" in
            y|Y) "$NVDIR/bin/jellyfin-autoconfig.sh" "$JF_CFG" "$NVDIR/bin/ffmpeg" "$GARCH" ;;
            *)   ok "left encoding.xml untouched" ;;
          esac
        elif [ ! -f "$JF_CFG" ]; then
          say "  ${DIM}encoding.xml not found yet (Jellyfin setup wizard not completed) -${R}"
          say "  ${DIM}hardware transcoding will be auto-configured on next boot instead.${R}"
        fi
        ;;
      *) ok "left Jellyfin on the ffmpeg7 package binary (no NVENC)" ;;
    esac
  fi
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
  CURK="$(uname -r | sed 's/[^0-9.].*$//')"
  STORED="$(cat /usr/lib/modules/.nvidia-platform 2>/dev/null)"
  STOREDP="${STORED%% *}"
  # markers written by older installs hold the platform only (no space)
  STOREDK=""; case "$STORED" in *" "*) STOREDK="${STORED##* }" ;; esac
  if [ -n "$STOREDP" ] && [ "$STOREDP" != "$CURP" ]; then
    logger -t nvidia.sh "SKIPPED: installed .ko are for platform '$STOREDP' but running on '$CURP' - re-run install.sh for this platform (or uninstall.sh first)" 2>/dev/null
    exit 0
  fi
  # Kernel guard: a DSM upgrade can move the same platform to a new kernel
  # (4.4.180 -> 4.4.302). insmod would reject the vermagic anyway; catching it
  # here makes the reason visible in the log instead of a silent failure.
  if [ -n "$STOREDK" ] && [ "$STOREDK" != "$CURK" ]; then
    logger -t nvidia.sh "SKIPPED: installed .ko are for kernel '$STOREDK' but running '$CURK' (DSM upgraded?) - re-run install.sh" 2>/dev/null
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
  # /dev/nvidia-modeset: unlike nvidia-uvm-tools and /dev/dri/* (which DSM's
  # udev auto-creates once the module registers), this one needs an explicit
  # create - confirmed on real hardware: nvidia-modeset.ko loads and registers
  # major 195 (visible in /proc/devices) but no /dev node appears without it.
  # Use NVIDIA's own bundled tool rather than hardcoding the minor (254 by
  # convention) ourselves. No-ops harmlessly on platforms where
  # nvidia-modeset.ko didn't load (e.g. headless, no backlight.ko).
  [ -e /dev/nvidia-modeset ] || /usr/local/nvidia/bin/nvidia-modprobe -m 2>/dev/null
  for so in /usr/local/nvidia/lib/*.so*; do [ -e "$so" ] && ln -sf "$so" "/usr/lib/$(basename "$so")"; done
  [ -x /sbin/ldconfig ] && /sbin/ldconfig 2>/dev/null
  # Container Manager runtime integration (Step 9, if set up once already):
  # re-assert the 'nvidia' entry in dockerd.json on every boot, in case a DSM
  # update or config restore reverted it. Confirmed on real hardware that
  # rc.d runs several seconds BEFORE ContainerManager's own auto-start
  # (kernel module load logged ~8s ahead of the package's synopkg start
  # sequence), so this is already in place by the time dockerd reads it - no
  # restart needed on a normal boot, unlike the one-time setup below.
  CRDIR=/usr/local/nvidia-runtime
  DJ=/var/packages/ContainerManager/etc/dockerd.json
  if [ -x "$CRDIR/bin/nvidia-container-runtime" ] && [ -f "$DJ" ] && command -v jq >/dev/null 2>&1; then
    CUR="$(jq -r '.runtimes.nvidia.path // empty' "$DJ" 2>/dev/null)"
    if [ "$CUR" != "$CRDIR/bin/nvidia-container-runtime" ]; then
      NEWDJ="$(jq --arg p "$CRDIR/bin/nvidia-container-runtime" '.runtimes.nvidia = {"path": $p, "runtimeArgs": []}' "$DJ" 2>/dev/null)"
      if [ -n "$NEWDJ" ]; then
        echo -E "$NEWDJ" > "$DJ"
        logger -t nvidia.sh "container runtime: re-registered 'nvidia' in dockerd.json (was missing/stale)" 2>/dev/null
      fi
    fi
  fi
  # Jellyfin hardware-transcoding auto-configuration (see
  # jellyfin-autoconfig.sh for the logic). At install time this already ran
  # if encoding.xml existed yet; this covers the case where the Jellyfin
  # setup wizard was completed AFTER the installer ran - the script itself
  # is a no-op past its stamp file or with acceleration already set, so
  # calling it on every boot costs nothing once it has actually run.
  NVFF=/usr/local/nvidia/bin/ffmpeg
  JF_CFG=/var/packages/jellyfin/var/config/encoding.xml
  JF_AC=/usr/local/nvidia/bin/jellyfin-autoconfig.sh
  if [ -x "$JF_AC" ] && [ -x "$NVFF" ] && [ -f "$JF_CFG" ]; then
    OUT="$("$JF_AC" "$JF_CFG" "$NVFF" "$(cat /usr/lib/modules/.nvidia-gpuarch 2>/dev/null)" 2>&1)"
    [ -n "$OUT" ] && logger -t nvidia.sh "$OUT" 2>/dev/null
  fi
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
            warn "restart Container Manager to apply now: sudo /usr/syno/bin/synopkg restart ContainerManager"
            say "  ${DIM}(future boots re-assert this automatically via the boot hook, before${R}"
            say "  ${DIM}Container Manager auto-starts - no restart needed after a reboot.)${R}"
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
