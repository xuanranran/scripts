#!/bin/bash

# --- 配置 ---
REPO="xuanranran/OpenWRT-X86_64"
IMAGE_FILENAME="immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz"
TMP_DIR="/tmp"
IMAGE_PATH="$TMP_DIR/$IMAGE_FILENAME"

# --- 退出脚本时清理临时文件 ---
cleanup() {
  echo "INFO: 清理临时文件 '$IMAGE_PATH'..."
  rm -f "$IMAGE_PATH"
}
trap cleanup EXIT

# --- 设置：如果任何命令失败则退出 ---
set -e

# --- 1. 临时增大 /tmp 分区 ---
echo "INFO: 尝试临时将 /tmp 重新挂载为更大内存（RAM 的 100%）。.."
echo "      注意：此更改仅在本次运行期间有效，重启后失效。"
mount -t tmpfs -o remount,size=100% tmpfs /tmp
echo "INFO: /tmp 当前挂载信息和大小:"
mount | grep " /tmp "
df -h /tmp

# --- 2. 获取最新 Release 信息 ---
echo "INFO: 正在从 GitHub 获取 '$REPO' 的最新版本信息..."
# 假设 wget 和 jq 已安装
API_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_INFO=$(wget -qO- --no-check-certificate "$API_URL") # 使用 wget -qO- 获取内容到标准输出

if [ -z "$RELEASE_INFO" ]; then
    echo >&2 "错误：无法从 GitHub API 获取版本信息。请检查网络连接或仓库 '$REPO' 是否存在，并确保已安装 'wget'。"
    exit 1
fi

# --- 3. 查找固件文件 URL ---
echo "INFO: 正在查找固件文件的下载链接..."
# 使用 jq 解析 JSON，提取所需文件的下载 URL
# 假设 jq 已安装
IMAGE_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$IMAGE_FILENAME" '.assets[] | select(.name==$NAME) | .browser_download_url')
RELEASE_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name // "未知标签"') # 获取版本标签

# 检查是否成功找到 URL
if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" == "null" ]; then
    echo >&2 "错误：在最新版本 '$RELEASE_TAG' 中未找到固件文件 '$IMAGE_FILENAME'。请检查仓库发布、脚本中的文件名配置，并确保已安装 'jq'。"
    exit 1
fi
echo "INFO: 找到最新版本 '$RELEASE_TAG'"
echo "INFO: 固件下载链接: $IMAGE_URL"

# --- 4. 下载固件 ---
echo "INFO: 正在下载固件 '$IMAGE_FILENAME' 到 '$IMAGE_PATH' ..."
# 假设 wget 已安装
wget --progress=bar:force --no-check-certificate -O "$IMAGE_PATH" "$IMAGE_URL"
if [ $? -ne 0 ]; then
    echo >&2 "错误：下载固件失败。"
    # trap 会自动清理
    exit 1
fi
echo "INFO: 固件下载完成。"
echo "警告：已跳过文件完整性校验！请自行承担风险。"

# --- 5. 执行升级 ---
echo "---------------------------------------------------------------------"
echo "警告：即将开始系统升级！"
echo "将使用以下固件文件进行升级："
echo "$IMAGE_PATH"
echo ""
echo "警告：本次升级未进行文件完整性校验！"
echo "升级过程中，请务必保持设备通电，不要中断操作！"
echo "升级会尝试保留现有配置，但建议提前备份重要数据。"
echo "---------------------------------------------------------------------"
read -p "确认要开始执行 sysupgrade 升级吗？(y/N): " confirm_upgrade

if [[ "$confirm_upgrade" =~ ^[Yy]$ ]]; then
    echo "INFO: 正在执行 sysupgrade 命令..."
    # 执行升级，通常会保留配置（默认行为）
    sysupgrade "$IMAGE_PATH"

    # 如果 sysupgrade 成功，系统通常会自动重启
    echo "INFO: sysupgrade 命令已执行。如果成功，系统将会重启。"
    exit 0
else
    echo "操作已取消。固件文件已下载在 '$IMAGE_PATH'，您可以手动升级或删除它。"
    # trap 会自动清理
    exit 0
fi

exit 0