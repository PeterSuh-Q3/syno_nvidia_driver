#!/bin/sh
# Root-only backend called through container-runtime-helper.  It deliberately
# modifies only the NVIDIA runtime entry it owns; existing foreign Docker
# runtime registrations are never overwritten.
set -eu

SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
PKG_TARGET="${SCRIPTDIR%/bin}"
PACKAGE="syno-nvidia-container-runtime"
PAYLOAD="$PKG_TARGET/runtime"
CRDIR=/usr/local/nvidia-runtime
LEGACY_BACKUP=/usr/local/.nvidia-runtime.pre-syno-container-runtime
CFGDIR=/etc/nvidia-container-runtime
CFG="$CFGDIR/config.toml"
CFG_BACKUP="$CFGDIR/config.toml.pre-syno-container-runtime"
CMPKG=/var/packages/ContainerManager
DOCKER_JSON="$CMPKG/etc/dockerd.json"
LOG=/var/log/nvidia-container-runtime.log

log() { echo "$(date '+%F %T') nvidia-container-runtime: $*" >> "$LOG" 2>/dev/null || true; }

lock_payload() {
  chown -R root:root "$PAYLOAD" 2>/dev/null || true
  chmod -R go-w "$PAYLOAD" 2>/dev/null || true
  chmod 755 "$PAYLOAD" "$PAYLOAD/bin" "$PAYLOAD/tools" 2>/dev/null || true
  chmod 755 "$PAYLOAD"/bin/* "$PAYLOAD"/tools/* 2>/dev/null || true
}

adopt_runtime_path() {
  if [ -L "$CRDIR" ] && [ "$(readlink "$CRDIR" 2>/dev/null || true)" = "$PAYLOAD" ]; then
    return 0
  fi
  if [ -e "$CRDIR" ] || [ -L "$CRDIR" ]; then
    if [ -e "$LEGACY_BACKUP" ] || [ -L "$LEGACY_BACKUP" ]; then
      echo "NVIDIA Container Runtime: refusing to overwrite both $CRDIR and backup $LEGACY_BACKUP" >&2
      return 1
    fi
    mv "$CRDIR" "$LEGACY_BACKUP"
    log "preserved pre-package runtime at $LEGACY_BACKUP"
  fi
  ln -s "$PAYLOAD" "$CRDIR"
}

write_config() {
  mkdir -p "$CFGDIR"
  if [ -f "$CFG" ] && ! grep -q '^# managed by syno-nvidia-container-runtime$' "$CFG" 2>/dev/null; then
    [ -e "$CFG_BACKUP" ] || cp -p "$CFG" "$CFG_BACKUP"
  fi
  cat > "$CFG" <<EOF
# managed by syno-nvidia-container-runtime
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
EOF
}

build_ldcache() {
  "$CRDIR/tools/ldconfig" -C "$CRDIR/ld.so.cache" /usr/lib "$CRDIR/lib" 2>/dev/null || {
    echo "NVIDIA Container Runtime: unable to generate ld.so.cache" >&2
    return 1
  }
  # DSM normally has no ldconfig.  Keep a package-owned copy only when absent;
  # never replace a binary supplied by DSM or another package.
  if [ ! -e /usr/sbin/ldconfig ]; then
    cp "$CRDIR/tools/ldconfig" /usr/sbin/ldconfig
    chmod 755 /usr/sbin/ldconfig
  fi
}

register_docker_runtime() {
  [ -d "$CMPKG" ] || { log "Container Manager not installed; runtime staged only"; return 0; }
  [ -f "$DOCKER_JSON" ] || { log "Container Manager dockerd.json missing; runtime staged only"; return 0; }
  command -v jq >/dev/null 2>&1 || { echo "NVIDIA Container Runtime: jq is required to safely update dockerd.json" >&2; return 1; }
  current="$(jq -r '.runtimes.nvidia.path // empty' "$DOCKER_JSON" 2>/dev/null || true)"
  if [ -n "$current" ] && [ "$current" != "$CRDIR/bin/nvidia-container-runtime" ]; then
    echo "NVIDIA Container Runtime: existing foreign nvidia runtime at $current was left unchanged" >&2
    return 1
  fi
  updated="$(jq --arg path "$CRDIR/bin/nvidia-container-runtime" '.runtimes.nvidia = {"path": $path, "runtimeArgs": []}' "$DOCKER_JSON")"
  printf '%s\n' "$updated" > "$DOCKER_JSON"
  log "registered Docker runtime in $DOCKER_JSON"
}

configure() {
  lock_payload
  adopt_runtime_path
  build_ldcache
  write_config
  register_docker_runtime
}

cleanup() {
  if [ -f "$DOCKER_JSON" ] && command -v jq >/dev/null 2>&1; then
    current="$(jq -r '.runtimes.nvidia.path // empty' "$DOCKER_JSON" 2>/dev/null || true)"
    if [ "$current" = "$CRDIR/bin/nvidia-container-runtime" ]; then
      jq 'del(.runtimes.nvidia)' "$DOCKER_JSON" > "$DOCKER_JSON.tmp" && mv "$DOCKER_JSON.tmp" "$DOCKER_JSON"
    fi
  fi
  if [ -f "$CFG" ] && grep -q '^# managed by syno-nvidia-container-runtime$' "$CFG" 2>/dev/null; then
    rm -f "$CFG"
    [ -f "$CFG_BACKUP" ] && mv "$CFG_BACKUP" "$CFG"
  fi
  if [ -L "$CRDIR" ] && [ "$(readlink "$CRDIR" 2>/dev/null || true)" = "$PAYLOAD" ]; then
    rm -f "$CRDIR"
    [ -e "$LEGACY_BACKUP" ] || [ -L "$LEGACY_BACKUP" ] && mv "$LEGACY_BACKUP" "$CRDIR"
  fi
  # Delete only the ldconfig binary this package installed.
  if [ -f /usr/sbin/ldconfig ] && [ -f "$PAYLOAD/tools/ldconfig" ] && cmp -s /usr/sbin/ldconfig "$PAYLOAD/tools/ldconfig"; then
    rm -f /usr/sbin/ldconfig
  fi
}

case "${1:-}" in
  postinst|start) configure ;;
  uninstall) cleanup ;;
  *) echo "NVIDIA Container Runtime: invalid lifecycle action" >&2; exit 1 ;;
esac
