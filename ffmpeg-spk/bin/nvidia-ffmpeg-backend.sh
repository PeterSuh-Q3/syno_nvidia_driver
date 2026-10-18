#!/bin/sh
# Fixed-action backend: only the package-owned FFmpeg files and a recognised
# SynoCommunity Jellyfin launch argument may be touched.
set -eu
ACTION=${1:-}

PKG_ID="$(cat "$(dirname "$0")/../share/package-id" 2>/dev/null || true)"
[ -n "$PKG_ID" ] || { echo "NVIDIA FFmpeg: package ID metadata missing" >&2; exit 1; }
PKG="/var/packages/$PKG_ID"
TARGET="$PKG/target"
FFMPEG="$TARGET/bin/ffmpeg"
FFPROBE="$TARGET/bin/ffprobe"
EXPECTED="$(cat "$TARGET/share/driver-version" 2>/dev/null || true)"
JELLYFIN_MAJOR="$(cat "$TARGET/share/jellyfin-min-major" 2>/dev/null || true)"
LOG=/var/log/nvidia-ffmpeg-spk.log
JF_SETUP=/var/packages/jellyfin/scripts/service-setup
JF_DEFAULT="$(cat "$TARGET/share/jellyfin-default-ffmpeg" 2>/dev/null || true)"
JF_LEGACY=/usr/local/nvidia/bin/ffmpeg
BACKUP="$JF_SETUP.pre-$PKG_ID.bak"
STATE_DIR="$PKG/var"
OLD_PATH_FILE="$STATE_DIR/previous-ffmpeg-path"

log() { printf '%s NVIDIA FFmpeg: %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null || true; }

emit_install_result() {
    [ "$ACTION" = postinst ] || return 0
    printf 'NVIDIA_FFMPEG_RESULT=%s\n' "$1"
}

active_driver() {
    if [ -r /sys/module/nvidia/version ]; then
        cat /sys/module/nvidia/version
    elif [ -x /usr/bin/nvidia-smi ]; then
        /usr/bin/nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1
    fi
}

installed_driver() {
    for package in \
        syno-nvidia-driver-kver5-580-open \
        syno-nvidia-driver-kver5-580-proprietary \
        syno-nvidia-driver-kver5-595-open \
        syno-nvidia-driver-kver5-595-proprietary \
        syno-nvidia-driver-kver5 \
        syno-nvidia-driver-kver4-dsm72 \
        syno-nvidia-driver-kver4-dsm70; do
        info="/var/packages/$package/INFO"
        [ -r "$info" ] || continue
        version="$(sed -n 's/^version="\([0-9][0-9.]*\)-[0-9][0-9]*"$/\1/p' "$info" | head -1)"
        [ -n "$version" ] && printf '%s\n' "$version"
    done
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

is_jellyfin_running() {
    [ -x /usr/syno/bin/synopkg ] && /usr/syno/bin/synopkg status jellyfin >/dev/null 2>&1
}

jellyfin_process_uses_ffmpeg() {
    for cmdline in /proc/[0-9]*/cmdline; do
        [ -r "$cmdline" ] || continue
        args="$(tr '\000' ' ' < "$cmdline" 2>/dev/null || true)"
        case "$args" in *[Jj]ellyfin*) ;; *) continue ;; esac
        case "$args" in *"$FFMPEG"*) return 0 ;; esac
    done
    return 1
}

wait_for_jellyfin_ready() {
    elapsed=0
    stable=0
    while [ "$elapsed" -lt 120 ]; do
        if is_jellyfin_running && jellyfin_process_uses_ffmpeg; then
            stable=$((stable + 1))
            [ "$stable" -ge 2 ] && return 0
        else
            stable=0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

restart_jellyfin_after_path_change() {
    is_jellyfin_running || {
        log "FFmpeg path updated while Jellyfin was stopped; restart deferred"
        emit_install_result jellyfin_not_running
        return 0
    }
    /usr/syno/bin/synopkg restart jellyfin >/dev/null 2>&1 || {
        log "Jellyfin restart command failed"
        return 1
    }
    if wait_for_jellyfin_ready; then
        log "Jellyfin returned to running with the NVIDIA FFmpeg path"
        emit_install_result jellyfin_restart_success
        return 0
    fi
    log "Jellyfin readiness check timed out after 120 seconds"
    return 2
}

configure() {
    [ -x "$FFMPEG" ] && [ -x "$FFPROBE" ] || {
        echo "NVIDIA FFmpeg: FFmpeg/FFprobe payload missing" >&2; return 1;
    }
    case "$EXPECTED" in *[!0-9.]*|'') echo "NVIDIA FFmpeg: invalid driver version" >&2; return 1 ;; esac
    installed="$(installed_driver || true)"
    if ! printf '%s\n' "$installed" | grep -Fxq "$EXPECTED"; then
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
    if [ -n "$JF_DEFAULT" ] && grep -Fq -- "--ffmpeg $JF_DEFAULT" "$JF_SETUP"; then
        previous=$JF_DEFAULT
    elif grep -Fq -- "--ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg" "$JF_SETUP"; then
        previous=/var/packages/ffmpeg7/target/bin/ffmpeg
    elif grep -Fq -- "--ffmpeg /var/packages/ffmpeg8/target/bin/ffmpeg" "$JF_SETUP"; then
        previous=/var/packages/ffmpeg8/target/bin/ffmpeg
    elif grep -Fq -- "--ffmpeg /var/packages/syno-nvidia-ffmpeg/target/bin/ffmpeg" "$JF_SETUP"; then
        previous=/var/packages/syno-nvidia-ffmpeg/target/bin/ffmpeg
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
    restart_result=0
    restart_jellyfin_after_path_change || restart_result=$?
    if [ "$restart_result" -ne 0 ]; then
        replace_argument "$FFMPEG" "$previous" || log "Jellyfin argument rollback failed"
        if is_jellyfin_running; then
            /usr/syno/bin/synopkg restart jellyfin >/dev/null 2>&1 || log "Jellyfin restart after path rollback failed"
        fi
        if [ "$restart_result" -eq 2 ]; then
            emit_install_result jellyfin_restart_timeout
        else
            emit_install_result jellyfin_restart_failed
        fi
        log "Jellyfin FFmpeg path rolled back; package remains installed"
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
    if is_jellyfin_running; then
        /usr/syno/bin/synopkg restart jellyfin >/dev/null 2>&1 || {
            log "Jellyfin restart failed after restoring previous FFmpeg path"
            return 1
        }
    fi
}

case "${1:-}" in
    postinst|start|configure) configure ;;
    uninstall) uninstall ;;
    *) exit 2 ;;
esac
