#!/bin/sh
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nvidia-module-vermagic.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# A minimal stand-in for a .ko: the vermagic= entry lives NUL-separated in the
# .modinfo section, surrounded by unrelated binary data.
printf 'ELF\000junk\000license=NVIDIA\000vermagic=4.4.302+ SMP mod_unload \000name=nvidia\000' \
  > "$TMP/nvidia.ko"
printf 'ELF\000no modinfo here\000' > "$TMP/broken.ko"

# Reproduce the DSM 7.2 kver4 userland: no modinfo, and a kmod that prints
# its usage text to stdout and exits non-zero for 'kmod modinfo'.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/kmod" <<'EOF'
#!/bin/sh
echo "kmod - Manage kernel modules: list, load, unload, etc"
echo "Usage:"
exit 1
EOF
chmod +x "$TMP/bin/kmod"

eval "$(sed -n '/^module_vermagic() {/,/^}/p' "$ROOT/spk/bin/nvidia-backend.sh")"
SAVED_PATH=$PATH
PATH="$TMP/bin:/usr/bin:/bin"
command -v modinfo >/dev/null 2>&1 && PATH="$TMP/bin:$(dirname "$(command -v tr)")"

vermagic="$(module_vermagic "$TMP/nvidia.ko")" || fail 'vermagic could not be read without modinfo'
[ "${vermagic%% *}" = "4.4.302+" ] \
  || fail "expected module release '4.4.302+', got '${vermagic%% *}' (full: '$vermagic')"

if module_vermagic "$TMP/broken.ko" >/dev/null; then
  fail 'a module without vermagic must be rejected'
fi

PATH=$SAVED_PATH
printf 'module_vermagic tests passed.\n'
