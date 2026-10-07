#!/bin/sh
# Fixed-action backend: only the package-owned FFmpeg files and a recognised
# SynoCommunity Jellyfin launch argument may be touched.
set -eu

PKG=/var/packages/syno-nvidia-ffmpeg
TARGET="$PKG/target"
FFMPEG="$TARGET/bin/ffmpeg"
FFPROBE="$TARGET/bin/ffprobe"
EXPECTED="$(cat "$TARGET/share/driver-version" 2>/dev/null || true)"
JELLYFIN_MAJOR="$(cat "$TARGET/share/jellyfin-min-major" 2>/dev/null || true)"
LOG=/var/log/nvidia-ffmpeg-spk.log
JF_SETUP=/var/packages/jellyfin/scripts/service-setup
JF_DEFAULT=/var/packages/ffmpeg7/target/bin/ffmpeg
JF_LEGACY=/usr/local/nvidia/bin/ffmpeg
BACKUP="$JF_SETUP.pre-syno-nvidia-ffmpeg.bak"
STATE_DIR="$PKG/var"
OLD_PATH_FILE="$STATE_DIR/previous-ffmpeg-path"

log() { printf '%s NVIDIA FFmpeg: %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null || true; }

active_driver() {
    if [ -r /sys/module/nvidia/version ]; then
        cat /sys/module/nvidia/version
    elif [ -x /usr/bin/nvidia-smi ]; then
        /usr/bin/nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1
    fi
}

installed_driver() {
    for package in syno-nvidia-driver-kver5 syno-nvidia-driver-kver4-dsm72 syno-nvidia-driver-kver4-dsm70; do
        info="/var/packages/$package/INFO"
        [ -r "$info" ] || continue
        version="$(sed -n 's/^version="\([0-9][0-9.]*\)-[0-9][0-9]*"$/\1/p' "$info" | head -1)"
        [ -n "$version" ] && { printf '%s\n' "$version"; return 0; }
    done
    return 1
}

jellyfin_major() {
    info=/var/packages/jellyfin/INFO
    [ -r "$info" ] || return 1
    sed -n 's/^version="\([0-9][0-9]*\)\..*/\1/p' "$info" | head -1
}

replace_argument() {
    old=$1 new=$2
    temp="$(mktemp "$JF_SETUP.nvidia-ffmpeg.XXXXXX")" || return 1
    if ! sed "s|--ffmpeg $old|--ffmpeg $new|" "$JF_SETUP" > "$temp" ||
       cmp -s "$temp" "$JF_SETUP"; then
        rm -f "$temp"
        return 1
    fi
    # Keep the original inode, owner and mode. A root-owned mode 0700
    # service-setup can make the Jellyfin daemon appear to crash on launch.
    cat "$temp" > "$JF_SETUP" || { rm -f "$temp"; return 1; }
    rm -f "$temp"
}

restart_jellyfin_if_running() {
    [ -x /usr/syno/bin/synopkg ] || return 0
    if /usr/syno/bin/synopkg status jellyfin >/dev/null 2>&1; then
        /usr/syno/bin/synopkg restart jellyfin >/dev/null 2>&1 || {
            log "Jellyfin restart failed; recheck service and FFmpeg path"
            return 1
        }
        log "Jellyfin restarted after FFmpeg path change"
    fi
}

configure() {
    [ -x "$FFMPEG" ] && [ -x "$FFPROBE" ] || {
        echo "NVIDIA FFmpeg: FFmpeg/FFprobe payload missing" >&2; return 1;
    }
    case "$EXPECTED" in *[!0-9.]*|'') echo "NVIDIA FFmpeg: invalid driver version" >&2; return 1 ;; esac
    installed="$(installed_driver || true)"
    if [ "$installed" != "$EXPECTED" ]; then
        echo "NVIDIA FFmpeg: driver package $EXPECTED required (installed: ${installed:-none})" >&2
        return 1
    fi
    running="$(active_driver || true)"
    if [ "$running" != "$EXPECTED" ]; then
        log "pending driver activation: expected=$EXPECTED running=${running:-none}"
        return 0
    fi
    [ -f "$JF_SETUP" ] || { log "Jellyfin absent; CLI FFmpeg ready"; return 0; }
    if [ "$JELLYFIN_MAJOR" != 0 ]; then
        server_major="$(jellyfin_major || true)"
        if [ -z "$server_major" ] || [ "$server_major" -lt "$JELLYFIN_MAJOR" ]; then
            log "Jellyfin automatic integration skipped: FFmpeg requires Jellyfin >=$JELLYFIN_MAJOR (installed ${server_major:-unknown})"
            return 0
        fi
    fi
    if grep -Fq -- "--ffmpeg $FFMPEG" "$JF_SETUP"; then
        log "Jellyfin already points to package FFmpeg"
        return 0
    fi
    if grep -Fq -- "--ffmpeg $JF_DEFAULT" "$JF_SETUP"; then
        previous=$JF_DEFAULT
    elif grep -Fq -- "--ffmpeg $JF_LEGACY" "$JF_SETUP"; then
        previous=$JF_LEGACY
    else
        log "Jellyfin uses an unrecognised FFmpeg argument; left unchanged"
        return 0
    fi
    mkdir -p "$STATE_DIR"
    [ -e "$BACKUP" ] || cp -p "$JF_SETUP" "$BACKUP"
    printf '%s\n' "$previous" > "$OLD_PATH_FILE"
    replace_argument "$previous" "$FFMPEG" || {
        log "failed to update Jellyfin service-setup"; return 1;
    }
    log "Jellyfin FFmpeg path changed to $FFMPEG"
    if ! restart_jellyfin_if_running; then
        replace_argument "$FFMPEG" "$previous" || log "Jellyfin argument rollback failed"
        restart_jellyfin_if_running || true
        return 1
    fi
}

uninstall() {
    [ -f "$JF_SETUP" ] || return 0
    grep -Fq -- "--ffmpeg $FFMPEG" "$JF_SETUP" || return 0
    previous="$(cat "$OLD_PATH_FILE" 2>/dev/null || true)"
    [ -x "$previous" ] || previous=$JF_DEFAULT
    replace_argument "$FFMPEG" "$previous" || {
        echo "NVIDIA FFmpeg: could not restore Jellyfin FFmpeg path" >&2; return 1;
    }
    log "Jellyfin FFmpeg path restored to $previous"
    restart_jellyfin_if_running
}

case "${1:-}" in
    postinst|start|configure) configure ;;
    uninstall) uninstall ;;
    *) exit 2 ;;
esac
