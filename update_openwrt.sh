#!/bin/bash

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
X86_SCRIPT="$SCRIPT_DIR/upgrade_openwrt_x86.sh"
ROCKCHIP_SCRIPT="$SCRIPT_DIR/upgrade_openwrt_rockchip.sh"

detect_platform() {
  local machine
  machine="$(uname -m 2>/dev/null)"

  case "$machine" in
    x86_64|amd64|i386|i486|i586|i686)
      echo "x86"
      return 0
      ;;
    aarch64|arm64|armv7l|armv8*|arm*)
      if [ -r /proc/device-tree/compatible ] && tr '\0' '\n' </proc/device-tree/compatible | grep -qi 'rockchip'; then
        echo "rockchip"
        return 0
      fi
      if [ -r /proc/cpuinfo ] && grep -qi 'rockchip' /proc/cpuinfo; then
        echo "rockchip"
        return 0
      fi
      ;;
  esac

  if [ -f /etc/openwrt_release ] && grep -Eqi 'rockchip|rk33|rk35|rk356|rk358' /etc/openwrt_release; then
    echo "rockchip"
    return 0
  fi

  echo "unknown"
  return 1
}

platform="$(detect_platform)"
case "$platform" in
  x86)
    [ -f "$X86_SCRIPT" ] || { echo "Error: missing $X86_SCRIPT" >&2; exit 1; }
    exec bash "$X86_SCRIPT" "$@"
    ;;
  rockchip)
    [ -f "$ROCKCHIP_SCRIPT" ] || { echo "Error: missing $ROCKCHIP_SCRIPT" >&2; exit 1; }
    exec bash "$ROCKCHIP_SCRIPT" "$@"
    ;;
  *)
    echo "Error: unsupported platform (uname -m=$(uname -m 2>/dev/null))." >&2
    echo "Only x86 and rockchip are supported." >&2
    exit 1
    ;;
esac
