#!/bin/bash

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
X86_SCRIPT="$SCRIPT_DIR/update_openwrt_x86.sh"
ROCKCHIP_SCRIPT="$SCRIPT_DIR/update_openwrt_rockchip.sh"
REMOTE_BASE_URLS="https://raw.githubusercontent.com/xuanranran/scripts/main/scripts https://raw.githubusercontent.com/xuanranran/scripts/main"

fetch_and_exec() {
  local remote_file="$1"
  local tmp_file
  local base_url
  tmp_file="/tmp/$remote_file"

  for base_url in $REMOTE_BASE_URLS; do
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$base_url/$remote_file" -o "$tmp_file" && exec bash "$tmp_file" "$@"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$tmp_file" "$base_url/$remote_file" && exec bash "$tmp_file" "$@"
    else
      return 1
    fi
  done

  return 1
}

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
    if [ -f "$X86_SCRIPT" ]; then
      exec bash "$X86_SCRIPT" "$@"
    fi
    echo "Info: local script not found, trying remote update_openwrt_x86.sh ..." >&2
    fetch_and_exec "update_openwrt_x86.sh" "$@" || {
      echo "Error: missing $X86_SCRIPT and failed to download remote script." >&2
      exit 1
    }
    ;;
  rockchip)
    if [ -f "$ROCKCHIP_SCRIPT" ]; then
      exec bash "$ROCKCHIP_SCRIPT" "$@"
    fi
    echo "Info: local script not found, trying remote update_openwrt_rockchip.sh ..." >&2
    fetch_and_exec "update_openwrt_rockchip.sh" "$@" || {
      echo "Error: missing $ROCKCHIP_SCRIPT and failed to download remote script." >&2
      exit 1
    }
    ;;
  *)
    echo "Error: unsupported platform (uname -m=$(uname -m 2>/dev/null))." >&2
    echo "Only x86 and rockchip are supported." >&2
    exit 1
    ;;
esac
