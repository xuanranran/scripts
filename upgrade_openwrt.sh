#!/bin/bash

# --- 配置 ---
REPO="xuanranran/OpenWRT-X86_64"
IMAGE_FILENAME_GZ="immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz" # 压缩文件名
# 从压缩文件名自动生成解压后的文件名（移除 .gz）
IMAGE_FILENAME_IMG="${IMAGE_FILENAME_GZ%.gz}"
TMP_DIR="/tmp"
IMAGE_PATH_GZ="$TMP_DIR/$IMAGE_FILENAME_GZ"
IMAGE_PATH_IMG="$TMP_DIR/$IMAGE_FILENAME_IMG"

# --- 退出脚本时清理临时文件 ---
cleanup() {
  echo "INFO: 清理临时文件..."
  rm -f "$IMAGE_PATH_GZ" "$IMAGE_PATH_IMG" # 清理压缩包和解压后的文件
}
trap cleanup EXIT

# --- 设置：如果任何命令失败则退出 ---
set -e

# --- 1. 检查依赖项 (自动检测 opkg 或 apk, 但不安装) ---
echo "INFO: Checking required tools (wget, jq, gunzip)..."

PKG_MANAGER=""
INSTALL_CMD_VERB="" # e.g., "install" or "add"
UPDATE_CMD_EXAMPLE="" # e.g., "opkg update" or "apk update"

# Detect package manager
if command -v opkg >/dev/null 2>&1; then
    echo "INFO: Detected 'opkg' package manager (Standard OpenWrt)."
    PKG_MANAGER="opkg"
    INSTALL_CMD_VERB="install"
    UPDATE_CMD_EXAMPLE="opkg update"
elif command -v apk >/dev/null 2>&1; then
    echo "INFO: Detected 'apk' package manager (Alpine/Recent OpenWrt Snapshot?)."
    PKG_MANAGER="apk"
    INSTALL_CMD_VERB="add" # apk uses 'add'
    UPDATE_CMD_EXAMPLE="apk update"
else
    echo >&2 "错误：无法检测到 'opkg' 或 'apk' 包管理器。"
    echo >&2 "请确保其中一个已安装并位于 PATH 中，或手动安装依赖项 (wget, jq, gzip)。"
    exit 1
fi

# --- Define required commands and check ---
# Maps required command -> package name providing it
required_pkgs_map=( ["wget"]="wget" ["jq"]="jq" ["gunzip"]="gzip" )
missing_pkgs=() # List of package names to install
missing_cmds=() # List of commands not found

for cmd in "${!required_pkgs_map[@]}"; do
    if ! command -v $cmd >/dev/null 2>&1; then
        missing_cmds+=("$cmd") # Add the command that wasn't found
        pkg_name=${required_pkgs_map[$cmd]}
        # Add package name to list only if not already added
        if ! [[ " ${missing_pkgs[@]} " =~ " ${pkg_name} " ]]; then
             missing_pkgs+=("$pkg_name")
        fi
    fi
done

# --- Report missing packages and exit ---
if [ ${#missing_pkgs[@]} -gt 0 ]; then
    # Convert arrays to space-separated strings for printing
    missing_cmds_str=$(IFS=" "; echo "${missing_cmds[*]}")
    missing_pkgs_str=$(IFS=" "; echo "${missing_pkgs[*]}")

    echo >&2 "错误：脚本运行缺少必要的命令: ${missing_cmds_str}"
    echo >&2 "检测到包管理器为 '$PKG_MANAGER'。请安装对应的包: ${missing_pkgs_str}"
    # Provide the example install command
    echo >&2 "请运行: ${UPDATE_CMD_EXAMPLE} && ${PKG_MANAGER} ${INSTALL_CMD_VERB} ${missing_pkgs_str}"
    exit 1
fi

echo "INFO: All required dependencies are available."

# --- 2. 临时增大 /tmp 分区 ---
echo "INFO: 尝试临时将 /tmp 重新挂载为更大内存（RAM 的 100%）。.."
echo "      注意：此更改仅在本次运行期间有效，重启后失效。"
mount -t tmpfs -o remount,size=100% tmpfs /tmp || echo "WARN: remount /tmp 可能失败或不受支持，继续执行..."
echo "INFO: /tmp 当前挂载信息和大小:"
mount | grep " /tmp " || echo "INFO: /tmp 可能未显示在 mount 输出中，或不是独立挂载点。"
df -h /tmp

# --- 3. 获取最新 Release 信息 ---
echo "INFO: 正在从 GitHub 获取 '$REPO' 的最新版本信息..."
API_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_INFO=$(wget -qO- --no-check-certificate "$API_URL")

if [ -z "$RELEASE_INFO" ]; then
    echo >&2 "错误：无法从 GitHub API 获取版本信息。请检查网络连接或仓库 '$REPO' 是否存在。"
    exit 1
fi

# --- 4. 查找固件文件 URL ---
echo "INFO: 正在查找压缩固件 '$IMAGE_FILENAME_GZ' 的下载链接..."
# 使用 jq 解析 JSON
IMAGE_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$IMAGE_FILENAME_GZ" '.assets[] | select(.name==$NAME) | .browser_download_url')
RELEASE_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name // "未知标签"') # 获取版本标签

# 检查是否成功找到 URL
if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" == "null" ]; then
    echo >&2 "错误：在最新版本 '$RELEASE_TAG' 中未找到压缩固件文件 '$IMAGE_FILENAME_GZ'。请检查仓库发布或脚本中的文件名配置。"
    exit 1
fi
echo "INFO: 找到最新版本 '$RELEASE_TAG'"
echo "INFO: 压缩固件下载链接: $IMAGE_URL"

# --- 5. 下载压缩固件 ---
echo "INFO: 正在下载压缩固件 '$IMAGE_FILENAME_GZ' 到 '$IMAGE_PATH_GZ' ..."
wget --progress=bar:force --no-check-certificate -O "$IMAGE_PATH_GZ" "$IMAGE_URL"
echo "INFO: 压缩固件下载完成。"

# --- 6. 解压固件 ---
echo "INFO: 正在解压固件 '$IMAGE_PATH_GZ' -> '$IMAGE_PATH_IMG' ..."
# gunzip 默认会删除源文件 (.gz)
gunzip "$IMAGE_PATH_GZ"

# 检查解压后的文件是否存在
if [ ! -f "$IMAGE_PATH_IMG" ]; then
     echo >&2 "错误：解压命令似乎已执行，但未找到预期的解压后文件 '$IMAGE_PATH_IMG'。"
     exit 1
fi
echo "INFO: 固件解压完成。解压后文件: '$IMAGE_PATH_IMG'"
ls -lh "$IMAGE_PATH_IMG" # 显示解压后文件的大小
echo "警告：已跳过文件完整性校验！请自行承担风险。"


# --- 7. 执行升级 (仍使用 sysupgrade，请确认这在 apk 基础的快照上是否仍然适用) ---
echo "---------------------------------------------------------------------"
echo "警告：即将开始系统升级！"
echo "      假定 'sysupgrade' 仍然是适用于此系统的升级命令。"
echo "      (如果你的系统基于 apk 且升级方式已改变，请勿继续！)"
echo "将使用以下 *解压后* 的固件文件进行升级："
echo "$IMAGE_PATH_IMG"
echo ""
echo "警告：本次升级未进行文件完整性校验！"
echo "升级过程中，请务必保持设备通电，不要中断操作！"
echo "升级会尝试保留现有配置，但建议提前备份重要数据。"
echo "---------------------------------------------------------------------"
read -p "确认要开始执行 sysupgrade 升级吗？(y/N): " confirm_upgrade

if [[ "$confirm_upgrade" =~ ^[Yy]$ ]]; then
    echo "INFO: 正在执行 sysupgrade 命令..."
    # 使用解压后的文件进行升级
    sysupgrade "$IMAGE_PATH_IMG"

    # 如果 sysupgrade 成功，系统通常会自动重启
    echo "INFO: sysupgrade 命令已执行。如果成功，系统将会重启。"
    exit 0
else
    echo "操作已取消。解压后的固件文件保留在 '$IMAGE_PATH_IMG'，您可以手动升级或删除它。"
    # trap 会自动清理
    exit 0
fi

exit 0 # 备用退出点