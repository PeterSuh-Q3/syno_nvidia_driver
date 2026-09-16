#!/usr/bin/env bash
# Build the version-independent NVIDIA Container Runtime SPK with a Debian
# toolchain container.  The NVIDIA runtime archive is an already published,
# pinned release asset; only the narrow DSM setuid helper is compiled here.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="$ROOT/container-runtime-spk"
PACKAGE=syno-nvidia-container-runtime
VERSION=1.19.1-1
ARCH=x86_64
ASSET=nv-container-runtime-1.19.1.tgz
ASSET_SHA256=5c39123aa2cc2a2539828aa557f812b14a789fc865ce2cf242e625381de0257e
RELEASE=https://github.com/PeterSuh-Q3/syno_nvidia_driver/releases/download/nvidia
WORK="$ROOT/work/$PACKAGE-$ARCH"
OUT="$ROOT/dist"
BUILD_IMAGE=${CONTAINER_RUNTIME_BUILD_IMAGE:-gcc:14-bookworm}

rm -rf "$WORK"
mkdir -p "$WORK/dl" "$WORK/target/bin/helper" "$WORK/scripts" "$WORK/conf" "$OUT"

curl -sL --fail "$RELEASE/$ASSET" -o "$WORK/dl/$ASSET"
echo "$ASSET_SHA256  $WORK/dl/$ASSET" | sha256sum -c -
mkdir -p "$WORK/target/runtime"
tar -xzf "$WORK/dl/$ASSET" -C "$WORK/target/runtime"

cp "$SOURCE/bin/container-runtime-backend.sh" "$WORK/target/bin/"
chmod 0755 "$WORK/target/bin/container-runtime-backend.sh"
cp "$SOURCE/scripts/"* "$WORK/scripts/"
chmod 0755 "$WORK/scripts/"*
cp "$SOURCE/conf/privilege" "$WORK/conf/privilege"

docker run --rm --platform linux/amd64 \
  -v "$SOURCE/helper:/src:ro" -v "$WORK/target/bin/helper:/out" -w /src "$BUILD_IMAGE" \
  gcc -O2 -s -static -Wall -Wextra -Werror \
    -DTARGET_SCRIPT="\"/var/packages/$PACKAGE/target/bin/container-runtime-backend.sh\"" \
    -o /out/container-runtime-helper.x86_64 container-runtime-helper.c
chmod 0755 "$WORK/target/bin/helper/container-runtime-helper.x86_64"

cp "$SOURCE/INFO" "$WORK/INFO"
tar -C "$WORK/target" -czf "$WORK/package.tgz" .
CHECKSUM=$(md5sum "$WORK/package.tgz" | awk '{print $1}')
EXTRACT_SIZE=$(du -sk "$WORK/target" | awk '{print $1}')
{
  printf 'extractsize="%s"\n' "$EXTRACT_SIZE"
  printf 'create_time="%s"\n' "$(date +%Y%m%d-%H:%M:%S)"
  printf 'checksum="%s"\n' "$CHECKSUM"
} >> "$WORK/INFO"

SPK="$OUT/$PACKAGE-$VERSION-$ARCH.spk"
tar -C "$WORK" -cf "$SPK" INFO package.tgz scripts conf
echo "Built $SPK ($(du -h "$SPK" | cut -f1))"
tar -tf "$SPK"
