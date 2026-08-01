#!/bin/sh
# jellyfin-autoconfig.sh <encoding.xml path> <ffmpeg binary> <GPU arch>
#
# Jellyfin ships with hardware acceleration off and expects the user to
# hand-pick NVENC in Dashboard -> Playback, then hand-pick which decode
# codecs are safe to turn on - something nobody can answer without NVIDIA's
# per-architecture capability tables. This does what Plex does automatically,
# but GPU-model-aware (Plex is not): encoders are probed against the real
# card so a Pascal box never gets AV1 turned on and a Kepler box never gets
# HEVC.
#
# Runs once: the config it writes lives on disk and survives reboot, so
# re-running would just undo whatever the user changed by hand afterward.
# Called both by install.sh (Step 6, if encoding.xml already exists) and by
# the rc.d boot hook (if it appears later, once the Jellyfin setup wizard is
# completed - the hook re-checks on every boot since there is no other
# trigger to hang a retry off).
set -u
JF_CFG="${1:?encoding.xml path required}"
NVFF="${2:?ffmpeg binary path required}"
JF_ARCH="${3:-}"
JF_STAMP="$(dirname "$JF_CFG")/.nvidia-autoconf"
JF_TTPDIR=/dev/shm/jellyfin-transcodes

[ -f "$JF_STAMP" ] && exit 0
[ -x "$NVFF" ] || exit 0
[ -f "$JF_CFG" ] || exit 0

JF_HW="$(sed -n 's#.*<HardwareAccelerationType>\([^<]*\)</HardwareAccelerationType>.*#\1#p' "$JF_CFG" 2>/dev/null)"
if [ -n "$JF_HW" ] && [ "$JF_HW" != "none" ]; then
  : > "$JF_STAMP" 2>/dev/null
  echo "Jellyfin: hardware acceleration already set to '$JF_HW' - left as is"
  exit 0
fi

# Ask the card itself what it can encode - each probe is a 1-frame encode to
# /dev/null, ~0.5s on real hardware.
nvprobe(){ timeout 15 "$NVFF" -hide_banner -loglevel quiet \
  -f lavfi -i nullsrc=s=128x128:d=0.04 -c:v "$1" -f null - >/dev/null 2>&1; }
JF_HEVC=false; nvprobe hevc_nvenc && JF_HEVC=true
JF_AV1=false;  nvprobe av1_nvenc  && JF_AV1=true

# NVDEC decode support cannot be probed the same way (needs real encoded
# input per codec), so it comes from the architecture instead. Erring
# generous is safe: ffmpeg silently falls back to software decode for a codec
# the chip cannot handle, whereas leaving a supported one off costs
# performance permanently and invisibly.
JF_DEC="h264 vc1 mpeg2video mpeg4"
case "$JF_ARCH" in
  Kepler)                ;;
  Maxwell)               JF_DEC="$JF_DEC vp8 hevc" ;;
  Ampere*|Ada|Blackwell) JF_DEC="$JF_DEC vp8 hevc vp9 av1" ;;
  *)                     JF_DEC="$JF_DEC vp8 hevc vp9" ;;
esac

# Preserve ownership across the edits: this file belongs to the package's
# service account (sc-jellyfin), and both sed -i and the awk rewrite below
# replace it with a new root-owned inode - the same class of regression that
# made service-setup's permission loss crash Jellyfin outright. Here it would
# just stop Jellyfin from ever saving playback settings again.
JF_OWN="$(stat -c '%U:%G' "$JF_CFG" 2>/dev/null)"

# First expression fills an element .NET serialised as nil (self-closing,
# with an attribute: <EncoderPreset xsi:nil="true" />); the second replaces
# one that already carries a value.
jfset(){ sed -i \
  -e "s#<$1 */>#<$1>$2</$1>#" \
  -e "s#<$1 [^>]*/>#<$1>$2</$1>#" \
  -e "s#<$1>[^<]*</$1>#<$1>$2</$1>#" "$JF_CFG" 2>/dev/null; }

jfset HardwareAccelerationType   nvenc
jfset EnableHardwareEncoding     true
jfset EnableEnhancedNvdecDecoder true
jfset AllowHevcEncoding          "$JF_HEVC"
jfset AllowAv1Encoding           "$JF_AV1"
jfset EnableTonemapping          true
jfset EncoderAppPathDisplay      "$NVFF"
# Measured on real hardware (P620, entry Pascal, 1080p30 hevc_nvenc): p1
# 10.6x, p4 9.86x, p5 9.35x, p6 9.27x, p7 8.83x - only 17% between fastest and
# slowest. NVENC quality presets are nearly free (fixed-function silicon), so
# the usual x264 instinct to trade quality for throughput does not apply.
# Jellyfin maps preset names straight onto p1-p7.
jfset EncoderPreset              slow

JF_SHM="$(df -m /dev/shm 2>/dev/null | awk 'NR==2{print $2}')"
if [ -d /dev/shm ] && [ -n "$JF_SHM" ] && [ "$JF_SHM" -ge 2048 ] 2>/dev/null; then
  # A dedicated subdirectory, never /dev/shm itself - Jellyfin treats the
  # transcode path as exclusively its own and empties it wholesale on
  # cleanup. Pointed at /dev/shm directly that means trying to delete
  # whatever else lives in the same tmpfs (confirmed on real hardware: it
  # tried to delete Plex's /dev/shm/Transcode/Sessions).
  if grep -q "<TranscodingTempPath[ >/]" "$JF_CFG" 2>/dev/null; then
    jfset TranscodingTempPath "$JF_TTPDIR"
  else
    # A fresh Jellyfin config never had a value for this key, so there is
    # nothing to substitute - it must be inserted. Position matters: .NET's
    # XmlSerializer expects schema order and quietly ignores an element that
    # arrives out of place, so it goes right after EncodingThreadCount, which
    # is where Jellyfin itself writes it.
    sed -i "s#</EncodingThreadCount>#</EncodingThreadCount>\n  <TranscodingTempPath>$JF_TTPDIR</TranscodingTempPath>#" "$JF_CFG" 2>/dev/null
  fi
  jfset EnableThrottling      true
  jfset EnableSegmentDeletion true
  mkdir -p "$JF_TTPDIR" 2>/dev/null
  [ -n "$JF_OWN" ] && chown "$JF_OWN" "$JF_TTPDIR" 2>/dev/null
  chmod 755 "$JF_TTPDIR" 2>/dev/null
fi

# HardwareDecodingCodecs is a list, so it needs the whole element replaced
# rather than a value substitution - and it may be empty/self-closing on a
# config that has never had acceleration turned on.
awk -v list="$JF_DEC" '
  function emit(  n,a,i) {
    print "  <HardwareDecodingCodecs>"
    n = split(list, a, " ")
    for (i = 1; i <= n; i++) print "    <string>" a[i] "</string>"
    print "  </HardwareDecodingCodecs>"
  }
  /<HardwareDecodingCodecs *\/>/       { emit(); next }
  /<HardwareDecodingCodecs>/           { emit(); skip = 1; next }
  skip && /<\/HardwareDecodingCodecs>/ { skip = 0; next }
  skip                                 { next }
                                       { print }
' "$JF_CFG" > "$JF_CFG.nvtmp" 2>/dev/null \
  && [ -s "$JF_CFG.nvtmp" ] && mv -f "$JF_CFG.nvtmp" "$JF_CFG"
rm -f "$JF_CFG.nvtmp" 2>/dev/null

[ -n "$JF_OWN" ] && chown "$JF_OWN" "$JF_CFG" 2>/dev/null
chmod 644 "$JF_CFG" 2>/dev/null
: > "$JF_STAMP" 2>/dev/null
[ -n "$JF_OWN" ] && chown "$JF_OWN" "$JF_STAMP" 2>/dev/null

echo "Jellyfin auto-configured (arch=${JF_ARCH:-unknown} hevc=$JF_HEVC av1=$JF_AV1 preset=slow decode='$JF_DEC')"
