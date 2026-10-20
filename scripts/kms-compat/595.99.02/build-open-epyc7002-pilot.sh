#!/usr/bin/env bash
# Isolated NVIDIA 595.99.02 Open KMS pilot for EPYC7002 / DSM 7.4.
# Run in the pinned dante90/syno-compiler:7.4 container after preparing the
# matching 26.10.15 quad-DRM provider inputs with prepare-open-epyc7002-provider.sh.
set -Eeuo pipefail

readonly ROOT=/work
readonly DRIVER=595.99.02
readonly PLATFORM=epyc7002
readonly DSM_VERSION=7.4
readonly KERNEL=5.10.55
readonly KERNEL_SHORT=51055
readonly IMAGE_DIGEST=sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f
readonly RUN_FILE="$ROOT/run/NVIDIA-Linux-x86_64-${DRIVER}.run"
readonly RUN_SHA256=e87477958bf763070549324bd5ad6c948eba6ed210e44005b3eff84940f6e1ec
readonly SHARED_DIR="$ROOT/out/release-assets-nvidia/shared/595"
readonly USERSPACE="$SHARED_DIR/nv-userspace-${DRIVER}.tgz"
readonly GSP="$SHARED_DIR/nv-gsp-${DRIVER}.tgz"
readonly PROVIDER_DIR="$ROOT/out/kms-expansion/inputs/epyc7002-26.10.15-provider-build"
readonly PROVIDER="$PROVIDER_DIR/provider-pack.tgz"
readonly PROVIDER_SOURCE="$PROVIDER_DIR/source"
readonly PROVIDER_SYMVERS="$PROVIDER_DIR/provider-Module.symvers"
readonly SHIM="$ROOT/scripts/kms-compat/580.173.02/focused3-shim/drm-provider-symbol-aliases.h"
readonly SHIM_SHA256=a04daa03b8059439b2397ef31cd3a2a4e5b1563493b6519a9807669f3ab38ff9
readonly EXPECTED_PROVIDER_SHA256=1e2485c6c5e963c7f392781c5375b3cb8374f0bd8541b7c0fab866b5434dd64c
readonly BASELINE="$ROOT/out/kms-expansion/kver5-595-open/20261020T100200Z-design-recheck/baseline/nv-ko-${DRIVER}-open-${PLATFORM}-${KERNEL_SHORT}.tgz"
readonly BASELINE_SHA256=5bff988dff8ffe8ccd052db8ae075bfa87b5e6eb75864a1f14524dcc2c59ad99
readonly KSRC="/opt/${PLATFORM}/build"
readonly TCBIN="/opt/${PLATFORM}/bin"
readonly CANDIDATE_ROOT="$ROOT/out/kms-expansion/kver5-595-open"
OUT_DIR="${OUT_DIR:-$CANDIDATE_ROOT/epyc7002-$(date -u +%Y%m%dT%H%M%SZ)}"

die() { printf '[595-open-kms-pilot] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[595-open-kms-pilot] %s\n' "$*" >&2; }
sha() { sha256sum "$1" | awk '{print $1}'; }

[[ "${NV_BUILD_IMAGE_DIGEST:-}" == "$IMAGE_DIGEST" ]] || die 'compiler image digest is not the pinned DSM 7.4 image'
case "$OUT_DIR" in "$CANDIDATE_ROOT"/epyc7002-*) ;; *) die "unexpected candidate path: $OUT_DIR" ;; esac
[[ ! -e "$OUT_DIR" ]] || die "candidate path already exists; refusing overwrite: $OUT_DIR"
[[ "$(sha "$RUN_FILE")" == "$RUN_SHA256" ]] || die 'NVIDIA .run checksum mismatch'
[[ -s "$USERSPACE" && -s "$GSP" ]] || die 'canonical shared NVIDIA userspace/GSP archive is missing'
[[ "$(tar -xOzf "$USERSPACE" ./VERSION 2>/dev/null | tr -d '\r\n')" == "$DRIVER" ]] || die 'shared userspace version mismatch'
tar -tzf "$GSP" | grep -E '(^|/)gsp_[^/]+\.bin$' >/dev/null || die 'shared GSP archive lacks firmware'
[[ -s "$BASELINE" && "$(sha "$BASELINE")" == "$BASELINE_SHA256" ]] || die 'preserved no-KMS baseline is absent or changed'
[[ -s "$PROVIDER" && "$(sha "$PROVIDER")" == "$EXPECTED_PROVIDER_SHA256" ]] || die 'provider pack is not the 26.10.15 EPYC7002 asset'
[[ -s "$PROVIDER_SYMVERS" && -s "$PROVIDER_DIR/provider.config" ]] || die 'matching provider build inputs are missing'
grep -qx 'provider_source_commit=a89571ecf197c83c04e16b1f09c516732defe91e' "$PROVIDER_DIR/PROVIDER-RECEIPT.txt" || die 'provider source commit does not match 26.10.15'
[[ -s "$PROVIDER_SOURCE/drm-include/drm/drm_drv.h" ]] || die 'provider DRM headers are missing'
[[ -s "$PROVIDER_SOURCE/i915-include/linux/iosys-map.h" ]] || die 'provider i915 iosys-map header is missing'
[[ -s "$SHIM" && "$(sha "$SHIM")" == "$SHIM_SHA256" ]] || die 'pinned focused3 DMA-BUF alias shim is missing or changed'
[[ "$(cat "$KSRC/include/config/kernel.release")" == "$KERNEL+" ]] || die 'unexpected DSM kernel release'
[[ -x "$TCBIN/x86_64-pc-linux-gnu-gcc" ]] || die 'platform cross-compiler is missing'
bash "$ROOT/scripts/check-shared-nvidia-layers.sh" || die 'shared NVIDIA-layer invariant failed'
tar -tzf "$PROVIDER" | grep -E '^(\./)?ast\.ko$' >/dev/null || die '26.10.15 provider archive is missing ast.ko'

mkdir -p "$OUT_DIR/baseline" "$OUT_DIR/artifacts" "$OUT_DIR/logs" "$OUT_DIR/evidence/module"
cp -p "$BASELINE" "$OUT_DIR/baseline/"
printf '%s  %s\n' "$BASELINE_SHA256" "$(basename "$BASELINE")" > "$OUT_DIR/baseline/SHA256SUMS"
cp "$PROVIDER_DIR/PROVIDER-RECEIPT.txt" "$OUT_DIR/evidence/PROVIDER-RECEIPT.txt"
cp "$PROVIDER_SYMVERS" "$OUT_DIR/evidence/provider-Module.symvers"
cp "$PROVIDER_DIR/provider.config" "$OUT_DIR/evidence/provider.config"
cp "$KSRC/.config" "$OUT_DIR/evidence/synology-kernel.config"
cp "$KSRC/Module.symvers" "$OUT_DIR/evidence/synology-kernel.Module.symvers"

# Use the exact 26.10.15 provider headers for conftest and Kbuild. Do not add
# the focused3 DMA-BUF alias shim speculatively: first inspect the imports this
# 595 Open build actually emits and require them to resolve against this pack.
mkdir -p "$KSRC/include/drm" "$KSRC/include/uapi/drm" "$KSRC/include/linux"
cp -R "$PROVIDER_SOURCE/drm-include/drm/." "$KSRC/include/drm/"
cp -R "$PROVIDER_SOURCE/drm-include/uapi/drm/." "$KSRC/include/uapi/drm/"
cp "$PROVIDER_SOURCE/i915-include/linux/iosys-map.h" "$KSRC/include/linux/iosys-map.h"
for header in dma-fence.h dma-fence-array.h dma-resv.h sync_file.h; do
  [[ -s "$PROVIDER_SOURCE/drm-include/linux/$header" ]] || die "matching provider header missing: $header"
  cp "$PROVIDER_SOURCE/drm-include/linux/$header" "$KSRC/include/linux/$header"
done
autoconf="$KSRC/include/generated/autoconf.h"
[[ -s "$autoconf" ]] || die 'generated kernel config is missing'
sed -i -E '/^#(define|undef) CONFIG_DRM(_MODULE)?([[:space:]]|$)/d; /^#(define|undef) CONFIG_DRM_KMS_HELPER(_MODULE)?([[:space:]]|$)/d' "$autoconf"
printf '%s\n' '#define CONFIG_DRM_MODULE 1' '#define CONFIG_DRM_KMS_HELPER_MODULE 1' >> "$autoconf"

export PATH="$TCBIN:$PATH"
candidate_raw="$OUT_DIR/artifacts/nv-ko-${DRIVER}-${PLATFORM}-${KERNEL_SHORT}.tgz"
candidate="$OUT_DIR/artifacts/nv-ko-${DRIVER}-open-${PLATFORM}-${KERNEL_SHORT}.tgz"
log "building flavor=open, platform=$PLATFORM, kernel=$KERNEL, provider=mshell-modules 26.10.15"
log "provider source commit=$(sed -n 's/^provider_source_commit=//p' "$PROVIDER_DIR/PROVIDER-RECEIPT.txt")"
log "provider pack sha256=$(sha "$PROVIDER")"
NV_KERNEL_MODULE_TYPE=open KBUILD_EXTRA_SYMBOLS="$PROVIDER_SYMVERS" \
EXTRA_CFLAGS="-DBPM_VGACON_TEXT_FORCE_NOT_PRESENT -include $SHIM -I$PROVIDER_SOURCE/backport-include -I$PROVIDER_SOURCE/drm-include -I$PROVIDER_SOURCE/i915-include" \
NO_BACKLIGHT=1 NV_DRM_IOSYS_COMPAT=1 JOBS=12 OUT="$OUT_DIR/artifacts" \
  bash "$ROOT/build-nvidia.sh" "$DRIVER" "$PLATFORM" "$KERNEL" \
  2>&1 | tee "$OUT_DIR/logs/build.log"
[[ -s "$candidate_raw" ]] || die "build did not produce expected output: $candidate_raw"
mv "$candidate_raw" "$candidate"

tar -xzf "$candidate" -C "$OUT_DIR/evidence/module"
for module in nvidia.ko nvidia-uvm.ko nvidia-modeset.ko nvidia-drm.ko nvidia-peermem.ko; do
  [[ -s "$OUT_DIR/evidence/module/$module" ]] || die "candidate missing $module"
  vermagic=$(strings -a "$OUT_DIR/evidence/module/$module" | sed -n 's/^vermagic=//p' | head -1)
  [[ "$vermagic" == 5.10.55+* ]] || die "invalid vermagic for $module: $vermagic"
  min_size=1000
  [[ "$module" != nvidia-drm.ko ]] || min_size=50000
  [[ "$(stat -c %s "$OUT_DIR/evidence/module/$module")" -gt "$min_size" ]] || die "$module looks like a stub (size threshold=$min_size bytes)"
done
[[ "$(cat "$OUT_DIR/evidence/module/VERSION")" == "$DRIVER" ]] || die 'candidate version marker mismatch'
[[ "$(cat "$OUT_DIR/evidence/module/PLATFORM")" == "$PLATFORM" ]] || die 'candidate platform marker mismatch'
strings -a "$OUT_DIR/evidence/module/nvidia-drm.ko" | awk 'index($0, "parm=modeset:") == 1 { found = 1 } END { exit !found }' || die 'nvidia-drm lacks modeset parameter'

tar -xzf "$PROVIDER" -C "$OUT_DIR/evidence" --wildcards '*.ko'
bash "$ROOT/scripts/check-drm-abi.sh" "$OUT_DIR/evidence/module/nvidia-drm.ko" "$PROVIDER" \
  | tee "$OUT_DIR/evidence/provider-abi-check.txt"
nm -u "$OUT_DIR/evidence/module/nvidia-drm.ko" | awk '/drm/ {print $NF}' | LC_ALL=C sort -u > "$OUT_DIR/evidence/drm-imports.txt"
nm -g --defined-only "$PROVIDER_DIR/modules"/*.ko 2>/dev/null \
  | awk 'NF >= 2 && $(NF-1) ~ /^[A-Za-z]$/ {print $NF}' | LC_ALL=C sort -u > "$OUT_DIR/evidence/provider-exports.txt"
comm -23 "$OUT_DIR/evidence/drm-imports.txt" "$OUT_DIR/evidence/provider-exports.txt" > "$OUT_DIR/evidence/unresolved-drm-imports.txt"
[[ ! -s "$OUT_DIR/evidence/unresolved-drm-imports.txt" ]] || {
  cat "$OUT_DIR/evidence/unresolved-drm-imports.txt" >&2
  die 'DRM imports are not all exported by the exact provider build'
}

sha "$candidate" > "$OUT_DIR/evidence/candidate.sha256"
sha "$RUN_FILE" > "$OUT_DIR/evidence/nvidia-run.sha256"
sha "$USERSPACE" > "$OUT_DIR/evidence/shared-userspace.sha256"
sha "$GSP" > "$OUT_DIR/evidence/shared-gsp.sha256"
sha "$PROVIDER" > "$OUT_DIR/evidence/provider-pack.sha256"
sha "$PROVIDER_SYMVERS" > "$OUT_DIR/evidence/provider-Module.symvers.sha256"
sha "$KSRC/.config" > "$OUT_DIR/evidence/synology-kernel-config.sha256"
sha "$KSRC/Module.symvers" > "$OUT_DIR/evidence/synology-kernel-Module.symvers.sha256"
printf '%s\n' \
  'profile=kver5-595-open' \
  "driver=$DRIVER" \
  'flavor=open' \
  "platform=$PLATFORM" \
  "dsm=$DSM_VERSION" \
  "kernel=$KERNEL+" \
  "compiler_image=dante90/syno-compiler:7.4@$IMAGE_DIGEST" \
  'provider_release=mshell-modules-26.10.15' \
  "provider_source_commit=a89571ecf197c83c04e16b1f09c516732defe91e" \
  "compatibility_shim=focused3 DMA-BUF alias shim sha256=$SHIM_SHA256 (required by provider dmabufbkpt_* exports)" \
  'runtime_modeset_test=pending' \
  'promotion=not-promoted' > "$OUT_DIR/BUILD-RECEIPT.txt"
log "candidate ready: $candidate"
log "candidate sha256: $(sha "$candidate")"
log 'Static ABI checks passed; physical modeset=1 testing remains required.'
