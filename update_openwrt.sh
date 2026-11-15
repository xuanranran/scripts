#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "错误：请先安装 Bash，再运行此脚本。" >&2
  exit 1
fi

# 在线进程替换（bash <(curl ...)）没有可用的本地脚本目录。
SCRIPT_DIR=""
if [[ -f ${BASH_SOURCE[0]} ]]; then
  script_path=$(readlink -f -- "${BASH_SOURCE[0]}") || exit 1
  SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$script_path")" && pwd) || exit 1
fi
X86_SCRIPT="${SCRIPT_DIR:+$SCRIPT_DIR/}update_openwrt_x86.sh"
ROCKCHIP_SCRIPT="${SCRIPT_DIR:+$SCRIPT_DIR/}update_openwrt_rockchip.sh"
ROCKCHIP_MEDIA_SCRIPT="${SCRIPT_DIR:+$SCRIPT_DIR/}update_openwrt_rockchip_media.sh"
REMOTE_BASE_URL="https://raw.githubusercontent.com/xuanranran/scripts/main"
BOOTSTRAP_DIR=""

cleanup() {
  if [[ -n "$BOOTSTRAP_DIR" ]]; then
    rm -f -- "$BOOTSTRAP_DIR/script.sh" "$BOOTSTRAP_DIR/script.sh.part"
    rmdir -- "$BOOTSTRAP_DIR" 2>/dev/null || true
  fi
}

fetch_and_exec() {
  local remote_file="$1" tmp_file status=0 downloaded=0 attempt
  shift # 文件名用于下载，不应混入传递给平台脚本的参数。
  BOOTSTRAP_DIR=$(mktemp -d /tmp/openwrt-bootstrap.XXXXXX) || return 1
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  tmp_file="$BOOTSTRAP_DIR/script.sh"

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --connect-timeout 15 --max-time 120 --retry 2 \
      "$REMOTE_BASE_URL/$remote_file" -o "$tmp_file.part"; then
      downloaded=1
    fi
  fi
  if [[ "$downloaded" == 0 ]] && command -v wget >/dev/null 2>&1; then
    for attempt in 1 2 3; do
      ((attempt == 1)) || printf 'Retrying download (%s/3)...\n' "$attempt" >&2
      if wget -T 30 -O "$tmp_file.part" "$REMOTE_BASE_URL/$remote_file"; then
        downloaded=1
        break
      fi
    done
  fi
  if [[ "$downloaded" == 0 || ! -s "$tmp_file.part" ]]; then
    echo "Error: failed to download $remote_file." >&2
    return 1
  fi
  # 不运行下载失败产生的空文件、HTML 错误页或不完整脚本。
  if ! head -n 1 "$tmp_file.part" | grep -Eq '^#!.*(ba)?sh'; then
    echo "Error: downloaded response is not a shell script." >&2
    return 1
  fi
  bash -n "$tmp_file.part" || return 1
  mv -- "$tmp_file.part" "$tmp_file" || return 1
  bash "$tmp_file" "$@" || status=$?
  return "$status"
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

# 只识别实际存在的 SD/eMMC 用户区整盘，忽略分区、boot0/boot1 和 rpmb。
# 入口只负责提供脚本选择；写盘前的启动盘、身份和占用检查由介质脚本完成。
has_sd_and_emmc() {
  local path disk kind has_sd=0 has_emmc=0
  for path in /sys/class/block/mmcblk*; do
    disk=${path##*/}
    [[ "$disk" =~ ^mmcblk[0-9]+$ && -b "/dev/$disk" ]] || continue
    kind=$(cat "$path/device/type" 2>/dev/null) || continue
    case "$kind" in
      SD) has_sd=1 ;;
      MMC) has_emmc=1 ;;
    esac
    [[ "$has_sd" != 1 || "$has_emmc" != 1 ]] || return 0
  done
  return 1
}

select_rockchip_script() {
  local choice
  SELECTED_ROCKCHIP_SCRIPT="$ROCKCHIP_SCRIPT"
  SELECTED_ROCKCHIP_REMOTE=update_openwrt_rockchip.sh
  has_sd_and_emmc || return 0
  printf '\n\033[1;33m检测到 SD 卡和 eMMC，请选择脚本\033[0m\n\n'
  printf '  1) 原升级脚本（默认）\n     使用 sysupgrade 升级当前系统\n\n'
  printf '  2) SD/eMMC 双向烧录脚本\n     仅支持 SD 卡烧录到 eMMC，或 eMMC 烧录到 SD 卡\n\n'
  printf '  q) 取消操作\n\n'
  while true; do
    printf '\033[1;33m❓ 请选择 [1/2/q]（默认：1）：\033[0m'
    if ! IFS= read -r choice; then
      printf '\n输入已结束，操作取消。\n' >&2
      return 1
    fi
    printf '\n'
    case "${choice:-1}" in
      1) return 0 ;;
      2)
        SELECTED_ROCKCHIP_SCRIPT="$ROCKCHIP_MEDIA_SCRIPT"
        SELECTED_ROCKCHIP_REMOTE=update_openwrt_rockchip_media.sh
        return 0
        ;;
      q|Q) echo '操作已取消。'; return 1 ;;
      *) echo '无效选项，请输入 1、2 或 q。' ;;
    esac
  done
}

platform="$(detect_platform)"
case "$platform" in
  x86)
    if [[ -n "$SCRIPT_DIR" && -f "$X86_SCRIPT" ]]; then
      exec bash "$X86_SCRIPT" "$@"
    fi
    echo "Info: local script not found, trying remote update_openwrt_x86.sh ..." >&2
    status=0
    fetch_and_exec "update_openwrt_x86.sh" "$@" || status=$?
    exit "$status"
    ;;
  rockchip)
    select_rockchip_script || exit 0
    if [[ -n "$SCRIPT_DIR" && -f "$SELECTED_ROCKCHIP_SCRIPT" ]]; then
      exec bash "$SELECTED_ROCKCHIP_SCRIPT" "$@"
    fi
    echo "Info: local script not found, trying remote $SELECTED_ROCKCHIP_REMOTE ..." >&2
    status=0
    fetch_and_exec "$SELECTED_ROCKCHIP_REMOTE" "$@" || status=$?
    exit "$status"
    ;;
  *)
    echo "Error: unsupported platform (uname -m=$(uname -m 2>/dev/null))." >&2
    echo "Only x86 and rockchip are supported." >&2
    exit 1
    ;;
esac
