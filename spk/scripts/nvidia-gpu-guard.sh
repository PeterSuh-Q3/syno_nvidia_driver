#!/bin/sh
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TABLE="$SCRIPT_DIR/nvidia-gpu-support.tsv"
BRANCH_FILE="$SCRIPT_DIR/target-driver.txt"
LOGFILE="${SYNOPKG_TEMP_LOGFILE:-}"
URL_580="https://github.com/PeterSuh-Q3/syno_nvidia_driver/releases/download/spk/syno-nvidia-driver-kver5-580.173.02-5.spk"
ACTION="${1:-installation}"
DRIVER="$(cat "$BRANCH_FILE" 2>/dev/null || true)"

say() {
  if [ -n "$LOGFILE" ]; then
    printf '%s\n' "$*" >> "$LOGFILE"
  else
    printf '%s\n' "$*" >&2
  fi
}

DEV_ROOT="${NVIDIA_PCI_SYSFS_ROOT:-/sys/bus/pci/devices}"
FOUND=0
OLDER_GPU=""
UNSUPPORTED_GPU=""
UNKNOWN_GPU=""

for dev in "$DEV_ROOT"/*; do
  [ -r "$dev/vendor" ] || continue
  [ "$(cat "$dev/vendor" 2>/dev/null)" = "0x10de" ] || continue
  case "$(cat "$dev/class" 2>/dev/null)" in
    0x0300*|0x0302*|0x1200*) ;;
    *) continue ;;
  esac

  id="10de:$(sed 's/^0x//' "$dev/device" 2>/dev/null | tr 'A-Z' 'a-z')"
  [ "$id" != "10de:" ] || continue
  FOUND=$((FOUND + 1))

  row="$(awk -F '\t' -v id="$id" '$1 == id { print $2 "\t" $3 "\t" $4; exit }' "$TABLE" 2>/dev/null)"
  if [ -n "$row" ]; then
    arch="$(printf '%s\n' "$row" | cut -f1)"
    name="$(printf '%s\n' "$row" | cut -f2)"
    branches="$(printf '%s\n' "$row" | cut -f3)"
  else
    arch="unknown"
    name="Unknown NVIDIA GPU"
    branches=""
  fi
  case "${SYNOPKG_DSM_LANGUAGE:-enu}" in
    krn) say "NVIDIA GPU 감지: $name ($arch, $id)" ;;
    *) say "NVIDIA GPU detected: $name ($arch, $id)" ;;
  esac

  if [ "$DRIVER" = "595.99.02" ]; then
    case "$arch" in
      Turing|Ampere|"Ampere GA100"|Hopper|Ada|Blackwell|"")
        [ "$arch" != "" ] || UNKNOWN_GPU="$UNKNOWN_GPU $id"
        ;;
      *)
        case " $branches " in
          *" 580 "*) OLDER_GPU="${OLDER_GPU}${OLDER_GPU:+; }$name ($arch, $id)" ;;
          *) UNSUPPORTED_GPU="${UNSUPPORTED_GPU}${UNSUPPORTED_GPU:+; }$name ($arch, $id)" ;;
        esac
        ;;
    esac
  fi
done

if [ "$FOUND" -eq 0 ]; then
  say "NVIDIA GPU를 찾지 못해 ${ACTION}을(를) 중단했습니다. NVIDIA GPU를 장착하거나 PCI 패스스루한 뒤 다시 시도하세요."
  say "No NVIDIA GPU was detected. ${ACTION} was stopped. Attach or pass through an NVIDIA GPU, then try again."
  exit 1
fi

if [ "$DRIVER" = "595.99.02" ] && [ -n "$OLDER_GPU" ]; then
  case "${SYNOPKG_DSM_LANGUAGE:-enu}" in
    krn)
      say "감지된 GPU: $OLDER_GPU. NVIDIA 595와 호환되지 않아 드라이버 설치/업데이트를 취소했습니다."
      say "패키지 센터 > 수동 설치에서 NVIDIA 580.173.02-5를 설치하세요: $URL_580"
      ;;
    *)
      say "Detected GPU: $OLDER_GPU. NVIDIA 595 is incompatible; driver installation/upgrade was canceled."
      say "In Package Center, choose Manual Install and install NVIDIA 580.173.02-5: $URL_580"
      ;;
  esac
  exit 1
fi

if [ "$DRIVER" = "595.99.02" ] && [ -n "$UNSUPPORTED_GPU" ]; then
  say "감지된 GPU는 595 계열과 호환되지 않으며, 이 카탈로그에서 호환되는 580 패키지도 확인되지 않았습니다. 설치를 중단합니다."
  say "$UNSUPPORTED_GPU"
  say "The detected GPU is not supported by driver 595, and no compatible 580 package was found in the bundled GPU support table. Installation was stopped."
  exit 1
fi

if [ -n "$UNKNOWN_GPU" ]; then
  say "일부 NVIDIA GPU의 PCI ID가 지원표에 없어 계열을 확인하지 못했습니다. 설치를 계속하지만 호환성을 직접 확인하세요: $UNKNOWN_GPU"
  say "One or more NVIDIA PCI IDs are missing from the support table; compatibility could not be verified. Continuing with manual verification recommended: $UNKNOWN_GPU"
fi

exit 0
