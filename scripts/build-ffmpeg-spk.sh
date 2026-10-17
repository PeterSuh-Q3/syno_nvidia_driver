#!/usr/bin/env bash
# Build driver-pinned NVIDIA FFmpeg SPKs. Source archives and hashes are fixed;
# this script never guesses a compatible FFmpeg from the host driver.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="$ROOT/ffmpeg-spk"
DL="$ROOT/work/nvidia-ffmpeg-spk/dl"
OUT="$ROOT/dist"
IMAGE=${FFMPEG_HELPER_BUILD_IMAGE:-gcc:14-bookworm}
RELEASE=https://github.com/PeterSuh-Q3/syno_nvidia_driver/releases/download/nvidia

usage() { echo "Usage: $0 {550.163.01|580.173.02|580.173.02-ffmpeg8|595.99.02|all}" >&2; exit 2; }
selected=${1:-all}
case "$selected" in
    all) versions=(550.163.01 580.173.02 580.173.02-ffmpeg8 595.99.02) ;;
    550.163.01|580.173.02|580.173.02-ffmpeg8|595.99.02) versions=("$selected") ;;
    *) usage ;;
esac

fetch() {
    local url=$1 file=$2 expected=$3
    mkdir -p "$DL"
    if [[ -f "$file" ]] && printf '%s  %s\n' "$expected" "$file" | sha256sum -c - >/dev/null; then return; fi
    curl --fail --location --retry 3 --connect-timeout 20 "$url" -o "$file.part"
    printf '%s  %s\n' "$expected" "$file.part" | sha256sum -c -
    mv "$file.part" "$file"
}

for driver in "${versions[@]}"; do
    case "$driver" in
        550.163.01)
            package_id=syno-nvidia-ffmpeg
            display_name="Synology NVIDIA FFmpeg 7"
            package_user=sc-nvidia-ffmpeg
            package_group=nvidia-ffmpeg
            ffmpeg_major=7
            jellyfin_default=/var/packages/ffmpeg7/target/bin/ffmpeg
            package_revision=4
            archive=nv-ffmpeg-550.163.01.tgz
            digest=509fd4f7f6e07ae616c7f16f65bee6aaebdd33d34653816c5c4dbc4f708b8165
            source_url="$RELEASE/$archive"
            jellyfin_version=7.0.2-9
            jellyfin_min_major=0
            dsm_min=7.0-00000 ;;
        580.173.02)
            package_id=syno-nvidia-ffmpeg
            display_name="Synology NVIDIA FFmpeg 7"
            package_user=sc-nvidia-ffmpeg
            package_group=nvidia-ffmpeg
            ffmpeg_major=7
            jellyfin_default=/var/packages/ffmpeg7/target/bin/ffmpeg
            package_revision=6
            archive=nv-ffmpeg-580.173.02.tgz
            digest=64ee797d1b391eec07ebf1a9b558079d8ad1bbb2fb48352f3c3cb77a38e242a3
            source_url="$RELEASE/$archive"
            jellyfin_version=7.1.4-3
            jellyfin_min_major=0
            dsm_min=7.2-00000 ;;
        580.173.02-ffmpeg8)
            driver=580.173.02
            package_id=syno-nvidia-ffmpeg8-580
            display_name="Synology NVIDIA FFmpeg 8 (580)"
            package_user=sc-nv-ffmpeg8-580
            package_group=nvidia-ffmpeg8-580
            ffmpeg_major=8
            jellyfin_default=/var/packages/ffmpeg8/target/bin/ffmpeg
            package_revision=1
            archive=jellyfin-ffmpeg_8.1.3-1_portable_linux64-gpl.tar.xz
            digest=b86dc023c64a5a9a410e6e3a938a970460214fae78f31c1553c9f88f1c289b6a
            source_url="https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/v8.1.3-1/$archive"
            jellyfin_version=8.1.3-1
            jellyfin_min_major=12
            dsm_min=7.2-00000 ;;
        595.99.02)
            package_id=syno-nvidia-ffmpeg8
            display_name="Synology NVIDIA FFmpeg 8"
            package_user=sc-nvidia-ffmpeg8
            package_group=nvidia-ffmpeg8
            ffmpeg_major=8
            jellyfin_default=/var/packages/ffmpeg8/target/bin/ffmpeg
            package_revision=3
            archive=jellyfin-ffmpeg_8.1.3-1_portable_linux64-gpl.tar.xz
            digest=b86dc023c64a5a9a410e6e3a938a970460214fae78f31c1553c9f88f1c289b6a
            source_url="https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/v8.1.3-1/$archive"
            jellyfin_version=8.1.3-1
            # Upstream explicitly targets Jellyfin 12, not stable 10.11.
            jellyfin_min_major=12
            dsm_min=7.2-00000 ;;
    esac

    fetch "$source_url" "$DL/$archive" "$digest"
    work="$ROOT/work/nvidia-ffmpeg-spk/build-$selected"
    mkdir -p "$work/target/bin/helper" "$work/target/share" "$work/scripts" "$work/conf" "$OUT"
    if [[ $archive == *.tgz ]]; then
        tar -xzf "$DL/$archive" -C "$work/target" ./bin/ffmpeg ./bin/ffprobe ./SOURCE
        mv "$work/target/SOURCE" "$work/target/share/upstream-SOURCE"
    else
        tar -xJf "$DL/$archive" -C "$work/target/bin" ffmpeg ffprobe
    fi
    chmod 0755 "$work/target/bin/ffmpeg" "$work/target/bin/ffprobe"
    printf '%s\n' "$driver" > "$work/target/share/driver-version"
    printf '%s\n' "$jellyfin_min_major" > "$work/target/share/jellyfin-min-major"
    printf '%s\n' "$package_id" > "$work/target/share/package-id"
    printf '%s\n' "$jellyfin_default" > "$work/target/share/jellyfin-default-ffmpeg"
    {
        printf 'Jellyfin FFmpeg: %s\n' "$jellyfin_version"
        printf 'Source: %s\n' "$source_url"
        printf 'SHA256: %s\n' "$digest"
        printf 'Driver package: syno-nvidia-driver %s\n' "$driver"
        printf 'License and source: https://github.com/jellyfin/jellyfin-ffmpeg/tree/v%s\n' "$jellyfin_version"
        if [[ $driver == 595.99.02 ]]; then
            printf 'Jellyfin automatic integration requires version 12 or later.\n'
        fi
    } > "$work/target/share/SOURCE"

    cp "$SOURCE/bin/nvidia-ffmpeg-backend.sh" "$work/target/bin/"
    chmod 0755 "$work/target/bin/nvidia-ffmpeg-backend.sh"
    docker run --rm --platform linux/amd64 \
        -v "$SOURCE/helper:/src:ro" -v "$work/target/bin/helper:/out" -w /src "$IMAGE" \
        gcc "-DPACKAGE_ID=\"$package_id\"" -O2 -s -static -Wall -Wextra -Werror \
        -o /out/nvidia-ffmpeg-helper.x86_64 nvidia-ffmpeg-helper.c
    chmod 0755 "$work/target/bin/helper/nvidia-ffmpeg-helper.x86_64"
    for script in "$SOURCE/scripts/"*; do
        sed -e "s/__DRIVER__/$driver/g" -e "s/__PACKAGE__/$package_id/g" \
            "$script" > "$work/scripts/$(basename "$script")"
    done
    chmod 0755 "$work/scripts/"*
    sed -e "s/__PACKAGE_USER__/$package_user/g" -e "s/__PACKAGE_GROUP__/$package_group/g" \
        "$SOURCE/conf/privilege" > "$work/conf/privilege"
    sed -e "s/__VERSION__/$driver-$package_revision/g" -e "s/__DRIVER__/$driver/g" \
        -e "s/__PACKAGE__/$package_id/g" -e "s/__DISPLAYNAME__/$display_name/g" \
        -e "s/__FFMPEG_MAJOR__/$ffmpeg_major/g" \
        -e "s/__OS_MIN_VER__/$dsm_min/g" "$SOURCE/INFO" > "$work/INFO"
    cp "$SOURCE/PACKAGE_ICON.PNG" "$SOURCE/PACKAGE_ICON_256.PNG" "$work/"

    tar -C "$work/target" -czf "$work/package.tgz" .
    checksum=$(md5sum "$work/package.tgz" | awk '{print $1}')
    extractsize=$(du -sk "$work/target" | awk '{print $1}')
    {
        printf 'extractsize="%s"\n' "$extractsize"
        printf 'create_time="%s"\n' "$(date +%Y%m%d-%H:%M:%S)"
        printf 'checksum="%s"\n' "$checksum"
    } >> "$work/INFO"
    spk="$OUT/$package_id-$driver-$package_revision-x86_64.spk"
    tar -C "$work" -cf "$spk" INFO package.tgz scripts conf PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG
    tar -tf "$spk" | grep -qx package.tgz
    printf 'Built %s\n' "$spk"
    sha256sum "$spk"
done
