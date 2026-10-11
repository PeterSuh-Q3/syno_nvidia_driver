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
HOOK_LINK=/usr/local/bin/nvidia-container-runtime-hook
LEGACY_BACKUP=/usr/local/.nvidia-runtime.pre-syno-container-runtime
CFGDIR=/etc/nvidia-container-runtime
CFG="$CFGDIR/config.toml"
CFG_BACKUP="$CFGDIR/config.toml.pre-syno-container-runtime"
CMPKG=/var/packages/ContainerManager
DOCKER_JSON="$CMPKG/etc/dockerd.json"
LOG=/var/log/nvidia-container-runtime.log
HOOK_LINK_CREATED=0

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

expose_docker_device_hook() {
  expected="$CRDIR/bin/nvidia-container-runtime-hook"
  if [ -L "$HOOK_LINK" ]; then
    current="$(readlink "$HOOK_LINK" 2>/dev/null || true)"
    if [ "$current" = "$expected" ]; then
      return 0
    fi
    echo "NVIDIA Container Runtime: refusing to replace foreign hook path $HOOK_LINK -> $current" >&2
    return 1
  fi
  if [ -e "$HOOK_LINK" ]; then
    echo "NVIDIA Container Runtime: refusing to overwrite existing $HOOK_LINK" >&2
    return 1
  fi
  ln -s "$expected" "$HOOK_LINK"
  HOOK_LINK_CREATED=1
  log "exposed NVIDIA device hook at $HOOK_LINK for Docker daemon PATH discovery"
}

restart_docker_for_device_hook() {
  [ "$HOOK_LINK_CREATED" -eq 1 ] || return 0
  [ -d "$CMPKG" ] || return 0

  # Docker 24 registers its built-in NVIDIA DeviceDriver only when the
  # nvidia-container-runtime-hook executable is visible in dockerd's PATH
  # during daemon startup.  Registering runtimes.nvidia alone is insufficient
  # for Compose DeviceRequests (deploy.resources.reservations.devices).
  # Restart only when this package has just created the link; routine package
  # starts/boots with the existing link do not bounce Container Manager.
  if command -v synosystemctl >/dev/null 2>&1; then
    if synosystemctl try-restart pkg-ContainerManager-dockerd.service >/dev/null 2>&1; then
      log "restarted Container Manager dockerd after exposing NVIDIA device hook"
    else
      log "Container Manager dockerd was not restarted automatically; restart it to enable Compose GPU reservations"
      echo "NVIDIA Container Runtime: restart Container Manager to enable Compose GPU device reservations" >&2
    fi
  else
    log "synosystemctl unavailable; restart Container Manager to enable Compose GPU device reservations"
    echo "NVIDIA Container Runtime: restart Container Manager to enable Compose GPU device reservations" >&2
  fi
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
ldcache = "/etc/ld.so.cache"
ldconfig = "@/usr/sbin/ldconfig"
environment = ["LD_LIBRARY_PATH=$CRDIR/lib", "NVC_INSECURE_MODE=1"]

[nvidia-container-runtime]
mode = "legacy"
runtimes = ["/var/packages/ContainerManager/target/usr/bin/runc"]

[nvidia-container-runtime-hook]
path = "$CRDIR/bin/nvidia-container-runtime-hook"

[nvidia-ctk]
path = "$CRDIR/bin/nvidia-ctk"
EOF
}

build_ldcache() {
  # libnvidia-container consults the system cache while collecting the host
  # driver files.  A private cache is therefore insufficient: after a driver
  # upgrade it can leave an obsolete fully-versioned NVIDIA path selected.
  #
  # DSM may invoke this package's boot hook before the NVIDIA driver package
  # has staged its userspace libraries.  That is an expected ordering race,
  # not a broken container-runtime installation.  Returning an error here
  # makes Package Center leave a persistent startFailed marker and repeatedly
  # offer Repair even though the runtime registration itself is valid.  Leave
  # the existing system cache alone until the next normal runtime activation.
  if ! find /usr/local/nvidia/lib /usr/lib -maxdepth 1 -type f -name 'libnvidia-ml.so.*' \
      -print -quit 2>/dev/null | grep -q .; then
    log "NVIDIA userspace is not available yet; skipped ld.so.cache rebuild"
    return 0
  fi

  # Generate one complete replacement in /etc, never a symlink into package
  # storage, so it also remains a normal DSM loader cache after this package
  # is upgraded or removed.
  cache_tmp=/etc/.ld.so.cache.syno-nvidia-container-runtime.$$
  rm -f "$cache_tmp"
  "$CRDIR/tools/ldconfig" -C "$cache_tmp" /lib /usr/lib "$CRDIR/lib" 2>/dev/null || {
    rm -f "$cache_tmp"
    echo "NVIDIA Container Runtime: unable to generate system ld.so.cache" >&2
    return 1
  }
  if ! "$CRDIR/tools/ldconfig" -p -C "$cache_tmp" 2>/dev/null | grep -q 'libnvidia-ml\.so'; then
    rm -f "$cache_tmp"
    echo "NVIDIA Container Runtime: generated cache does not contain NVIDIA libraries" >&2
    return 1
  fi
  chown root:root "$cache_tmp"
  chmod 644 "$cache_tmp"
  mv -f "$cache_tmp" /etc/ld.so.cache
  log "rebuilt /etc/ld.so.cache from current /lib and /usr/lib libraries"
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
  expose_docker_device_hook
  build_ldcache
  write_config
  register_docker_runtime
  restart_docker_for_device_hook
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
  # Remove only the exact symlink this package owns; preserve any replacement
  # installed by DSM or another package.
  if [ -L "$HOOK_LINK" ] && [ "$(readlink "$HOOK_LINK" 2>/dev/null || true)" = "$CRDIR/bin/nvidia-container-runtime-hook" ]; then
    rm -f "$HOOK_LINK"
    log "removed package-owned Docker device hook link at $HOOK_LINK"
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
