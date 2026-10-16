#!/usr/bin/env bash
# Canonical, fail-closed build profile for the tested DSM 7.4 / K5 580
# Proprietary NVIDIA module set. This script creates local candidate assets
# only; it never updates release-assets-nvidia or publishes anything.
set -Eeuo pipefail

readonly PROFILE="kver5-580-proprietary"
readonly DRIVER="580.173.02"
readonly DSM_VERSION="7.4"
readonly KERNEL_VERSION="5.10.55"
readonly KERNEL_SHORT="51055"
readonly JOBS="12"
readonly IMAGE_TAG="dante90/syno-compiler:7.4"
readonly IMAGE_DIGEST="sha256:08cedce8be257c7b3f2b32c8edde034cc53754f0bad1f974b63c76607d7eab1f"
readonly IMAGE_REF="dante90/syno-compiler@${IMAGE_DIGEST}"
readonly RUN_REL="run/NVIDIA-Linux-x86_64-${DRIVER}.run"
readonly RUN_SHA256="8d8eb9001e05a9a8a663d3d5d304feb64ef2844ee185ccdfd952786820f46e1b"
readonly PLATFORMS=(epyc7002 epyc7003 geminilakenk icelaked r1000nk v1000nk)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
readonly SHARED_DIR="$ROOT/out/release-assets-nvidia/shared/${DRIVER%%.*}"
readonly SHARED_USERSPACE="$SHARED_DIR/nv-userspace-${DRIVER}.tgz"
readonly SHARED_GSP="$SHARED_DIR/nv-gsp-${DRIVER}.tgz"

usage() {
  cat <<'EOF'
Usage:
  scripts/build-kver5-580-proprietary.sh [--dry-run]

Builds the fixed 580.173.02 Proprietary / DSM 7.4 / kernel 5.10.55 profile
for its six supported platforms. No version, flavor, platform, or compiler
image overrides are accepted. Outputs are placed in a unique local candidate
directory under out/regular-builds; release assets are never modified.
EOF
}

if [[ $# -gt 1 ]]; then usage >&2; exit 2; fi
DRY_RUN=0
if [[ $# -eq 1 ]]; then
  [[ "$1" == "--dry-run" ]] || { usage >&2; exit 2; }
  DRY_RUN=1
fi

log() { printf '[%s] %s\n' "$PROFILE" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

[[ -f "$RUN_REL" ]] || die "missing pinned NVIDIA installer: $RUN_REL"
actual_run_sha="$(sha256_file "$RUN_REL")"
[[ "$actual_run_sha" == "$RUN_SHA256" ]] || die ".run SHA-256 mismatch (expected $RUN_SHA256, got $actual_run_sha)"
[[ -s "$SHARED_USERSPACE" ]] || die "shared userspace archive is missing: $SHARED_USERSPACE"
[[ -s "$SHARED_GSP" ]] || die "shared GSP archive is missing: $SHARED_GSP"
tar -tzf "$SHARED_GSP" >/dev/null 2>&1 || die "shared GSP archive is corrupt: $SHARED_GSP"
tar -tzf "$SHARED_GSP" | grep -Eq '(^|/)gsp_[^/]+\.bin$' || die "shared GSP archive contains no firmware: $SHARED_GSP"

log "Locked profile: driver=$DRIVER flavor=proprietary DSM=$DSM_VERSION kernel=$KERNEL_VERSION jobs=$JOBS"
log "Platforms: ${PLATFORMS[*]}"
log "NO_BACKLIGHT=1: epyc7002 epyc7003 icelaked r1000nk v1000nk; NO_BACKLIGHT=0: geminilakenk"
log "Compiler image: $IMAGE_REF"
log "NVIDIA .run SHA-256: $actual_run_sha"

if [[ "$DRY_RUN" == 1 ]]; then
  for platform in "${PLATFORMS[@]}"; do
    no_backlight=1
    [[ "$platform" == geminilakenk ]] && no_backlight=0
    printf 'docker run %s build-nvidia.sh %s %s %s NO_BACKLIGHT=%s JOBS=%s\n' \
      "$IMAGE_REF" "$DRIVER" "$platform" "$KERNEL_VERSION" "$no_backlight" "$JOBS"
  done
  log 'Dry run only; no Docker build or filesystem changes performed.'
  exit 0
fi

command -v docker >/dev/null 2>&1 || die 'Docker CLI is unavailable'
docker info >/dev/null 2>&1 || die 'Docker Desktop engine is not running'
docker_os="$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)"
[[ "$docker_os" == *"Docker Desktop"* ]] || die "expected Docker Desktop, found '${docker_os:-unknown}'"

repo_digests="$(docker image inspect "$IMAGE_TAG" --format '{{json .RepoDigests}}' 2>/dev/null || true)"
[[ "$repo_digests" == *"dante90/syno-compiler@${IMAGE_DIGEST}"* ]] || \
  die "$IMAGE_TAG is not locally present with the pinned RepoDigest $IMAGE_DIGEST; refusing to pull or substitute another image"

# A normal build is allowed only from the committed canonical script and a
# clean tracked source tree. --dry-run remains available before committing.
script_rel="${0#"$ROOT"/}"
git ls-files --error-unmatch "$script_rel" >/dev/null 2>&1 || \
  die "$script_rel is not tracked yet; commit/review the canonical build profile before building"
git ls-files --error-unmatch scripts/validate-kver5-580-proprietary-candidate.sh >/dev/null 2>&1 || \
  die 'the candidate validator is not tracked yet; commit/review it before building'
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || \
  die 'tracked source changes are present; commit/review them before the canonical build'

# Preflight all platform toolchains before spending time on the first compile.
docker run --rm --entrypoint /bin/bash "$IMAGE_REF" -lc '
  set -euo pipefail
  for platform in epyc7002 epyc7003 geminilakenk icelaked r1000nk v1000nk; do
    ks="/opt/${platform}/build"
    gcc="/opt/${platform}/bin/x86_64-pc-linux-gnu-gcc"
    [[ -s "$ks/Module.symvers" ]] || { echo "missing $ks/Module.symvers" >&2; exit 10; }
    [[ -x "$gcc" ]] || { echo "missing toolchain compiler $gcc" >&2; exit 11; }
    version="$("$gcc" -dumpfullversion)"
    [[ "$version" == 12.2.0 ]] || { echo "$platform GCC version is $version, expected 12.2.0" >&2; exit 12; }
    release="$(cat "$ks/include/config/kernel.release" 2>/dev/null || true)"
    [[ "$release" == 5.10.55* ]] || { echo "$platform kernel release is ${release:-unknown}, expected 5.10.55" >&2; exit 13; }
    echo "preflight OK: $platform kernel=$release gcc=$version"
  done
' || die 'toolchain preflight failed; no platform build was started'

readonly BUILD_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(git rev-parse --short HEAD)"
readonly BASE_OUT="$ROOT/out/regular-builds/$PROFILE"
readonly FINAL_DIR="$BASE_OUT/$BUILD_ID"
mkdir -p "$BASE_OUT"
[[ ! -e "$FINAL_DIR" ]] || die "candidate destination already exists: $FINAL_DIR"

readonly LOCK_DIR="$ROOT/out/.lock-$PROFILE"
mkdir "$LOCK_DIR" 2>/dev/null || die "another $PROFILE build may be running (lock: $LOCK_DIR)"

STAGING="$(mktemp -d "$ROOT/out/.staging-$PROFILE.XXXXXXXX")"
STAGING_REL="${STAGING#"$ROOT"/}"
ARTIFACTS="$STAGING/artifacts"
LOG_DIR="$STAGING/logs"
BUILD_OUT="$ARTIFACTS"
mkdir -p "$ARTIFACTS" "$LOG_DIR"

cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
  if [[ -n "${STAGING:-}" && -d "$STAGING" ]]; then
    log "Incomplete candidate retained for diagnosis: $STAGING"
  fi
}
trap cleanup EXIT

log "Candidate staging directory: $STAGING"
for platform in "${PLATFORMS[@]}"; do
  no_backlight=1
  [[ "$platform" == geminilakenk ]] && no_backlight=0
  log "Building $platform (NO_BACKLIGHT=$no_backlight, JOBS=$JOBS)"
  docker run --rm --privileged -u 0 \
    -e "NO_BACKLIGHT=$no_backlight" \
    -e "JOBS=$JOBS" \
    -e "OUT=/work/$STAGING_REL/build" \
    -v "$ROOT":/work \
    "$IMAGE_REF" \
    bash /work/build-nvidia.sh "$DRIVER" "$platform" "$KERNEL_VERSION" \
    2>&1 | tee "$LOG_DIR/$platform.log"

  generated="$BUILD_OUT/nv-ko-${DRIVER}-${platform}-${KERNEL_SHORT}.tgz"
  [[ -s "$generated" ]] || die "$platform build did not produce $generated"
  canonical="$ARTIFACTS/nv-ko-${DRIVER}-proprietary-${platform}-${KERNEL_SHORT}.tgz"
  mv "$generated" "$canonical"
done

log "Using shared userspace layer: $SHARED_USERSPACE"
log "Using shared GSP layer: $SHARED_GSP"

# Validate all six archives using a tracked, read-only validator in the exact
# pinned image. No artifact is promoted unless every check passes.
docker run --rm --entrypoint /bin/bash \
  -v "$ROOT":/work:ro \
  "$IMAGE_REF" \
  /work/scripts/validate-kver5-580-proprietary-candidate.sh \
  "/work/$STAGING_REL/artifacts" \
  "/work/out/release-assets-nvidia/shared/580/nv-userspace-${DRIVER}.tgz" \
  "/work/out/release-assets-nvidia/shared/580/nv-gsp-${DRIVER}.tgz" || die 'artifact validation failed; no candidate was promoted'

(cd "$ARTIFACTS" && shasum -a 256 ./*.tgz > SHA256SUMS)
run_sha="$(sha256_file "$RUN_REL")"
script_sha="$(sha256_file "${BASH_SOURCE[0]}")"
image_digest="$IMAGE_DIGEST"
source_commit="$(git rev-parse HEAD)"
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  printf '{\n'
  printf '  "profile": "%s",\n' "$PROFILE"
  printf '  "driver_version": "%s",\n' "$DRIVER"
  printf '  "flavor": "proprietary",\n'
  printf '  "dsm_version": "%s",\n' "$DSM_VERSION"
  printf '  "kernel_version": "%s",\n' "$KERNEL_VERSION"
  printf '  "compiler_image": "dante90/syno-compiler",\n'
  printf '  "compiler_image_digest": "%s",\n' "$image_digest"
  printf '  "jobs": %s,\n' "$JOBS"
  printf '  "nvidia_run_sha256": "%s",\n' "$run_sha"
  printf '  "source_commit": "%s",\n' "$source_commit"
  printf '  "build_script_sha256": "%s",\n' "$script_sha"
  printf '  "built_at_utc": "%s",\n' "$built_at"
  printf '  "release_published": false,\n'
  printf '  "artifacts": [\n'
  for index in "${!PLATFORMS[@]}"; do
    platform="${PLATFORMS[$index]}"
    file="nv-ko-${DRIVER}-proprietary-${platform}-${KERNEL_SHORT}.tgz"
    digest="$(sha256_file "$ARTIFACTS/$file")"
    no_backlight=true
    [[ "$platform" == geminilakenk ]] && no_backlight=false
    comma=','
    [[ "$index" -eq $((${#PLATFORMS[@]} - 1)) ]] && comma=''
    printf '    {"platform":"%s","no_backlight":%s,"file":"%s","sha256":"%s"}%s\n' \
      "$platform" "$no_backlight" "$file" "$digest" "$comma"
  done
  for file in "$SHARED_USERSPACE" "$SHARED_GSP"; do
    digest="$(sha256_file "$file")"
    printf '    ,{"scope":"shared","file":"%s","sha256":"%s"}\n' "$(basename "$file")" "$digest"
  done
  printf '  ]\n}\n'
} > "$STAGING/BUILD-RECEIPT.json"

cat > "$STAGING/BUILD-RECEIPT.txt" <<EOF
Canonical build profile: $PROFILE
Driver: $DRIVER Proprietary
DSM/kernel: $DSM_VERSION / $KERNEL_VERSION
Compiler image: $IMAGE_REF
NVIDIA .run SHA-256: $run_sha
Source commit: $source_commit
Build script SHA-256: $script_sha
Jobs: $JOBS
Backlight policy: NO_BACKLIGHT=1 on epyc7002, epyc7003, icelaked, r1000nk, v1000nk; NO_BACKLIGHT=0 on geminilakenk
All six module archives and the canonical shared userspace/GSP archives passed the scripted checks.
This directory is a local candidate only. No release asset was modified or published.
EOF

mv "$STAGING" "$FINAL_DIR"
STAGING=""
log "All builds and validations passed. Candidate set: $FINAL_DIR"
log 'Review BUILD-RECEIPT.json and SHA256SUMS before any manual release-asset promotion.'
