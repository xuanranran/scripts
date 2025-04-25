#!/bin/bash

# --- 颜色定义 ---
C_RESET='\033[0m'       # 重置所有属性
C_RED='\033[0;31m'       # 红色
C_GREEN='\033[0;32m'     # 绿色
C_YELLOW='\033[0;33m'    # 黄色
C_BLUE='\033[0;34m'      # 蓝色
C_CYAN='\033[0;36m'      # 青色
C_B_RED='\033[1;31m'      # 粗体红色
C_B_GREEN='\033[1;32m'    # 粗体绿色
C_B_YELLOW='\033[1;33m'   # 粗体黄色

# --- 配置 ---
REPO="xuanranran/OpenWRT-X86_64"                                           # 目标 GitHub 仓库
IMAGE_FILENAME_GZ="immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz" # 压缩固件的文件名
IMAGE_FILENAME_IMG="${IMAGE_FILENAME_GZ%.gz}"                             # 解压后的固件文件名
CHECKSUM_FILENAME="sha256sums"                                             # 校验和文件名
TMP_DIR="/tmp"                                                             # 临时文件目录
IMAGE_PATH_GZ="$TMP_DIR/$IMAGE_FILENAME_GZ"                                # 压缩固件的完整路径
IMAGE_PATH_IMG="$TMP_DIR/$IMAGE_FILENAME_IMG"                              # 解压后固件的完整路径
CHECKSUM_PATH="$TMP_DIR/$CHECKSUM_FILENAME"                                # 校验和文件的完整路径
THRESHOLD_KIB=1887437                                                      # 保留数据的空间阈值 (1.8 GiB in KiB)

# --- 退出脚本时清理临时文件 ---
cleanup() {
  echo # 清理前空一行
  echo -e "${C_BLUE}信息：${C_RESET}正在清理临时文件..."
  rm -f "$IMAGE_PATH_GZ" "$IMAGE_PATH_IMG" "$CHECKSUM_PATH" # 清理压缩包、解压后的文件和校验文件
}
# 设置陷阱：当脚本退出时（EXIT信号），执行 cleanup 函数
# trap cleanup EXIT

# --- 设置：如果任何命令失败则立即退出 ---
# 在依赖项安装步骤中会临时禁用此设置
# set -e

echo
echo -e "${C_BLUE}=====================================================================${C_RESET}"
echo -e "${C_BLUE} OpenWRT/ImmortalWrt 自动升级脚本 ${C_RESET}"
echo -e "${C_BLUE}=====================================================================${C_RESET}"
echo

# --- 1. 检查并尝试安装依赖项 ---
echo -e "${C_BLUE}--- 步骤 1: 检查并尝试安装依赖项 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}检查所需工具 (wget, jq, gunzip, awk, sha256sum)..."

PKG_MANAGER=""
UPDATE_CMD=""
INSTALL_CMD=""

# 检测包管理器
if command -v opkg >/dev/null 2>&1; then
    PKG_MANAGER="opkg"; UPDATE_CMD="opkg update"; INSTALL_CMD="opkg install";
elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"; UPDATE_CMD="apk update"; INSTALL_CMD="apk add";
else
    echo -e "${C_B_RED}错误：${C_RESET}无法检测到 'opkg' 或 'apk' 包管理器。" >&2
    echo -e "请确保其中一个已安装并位于 PATH 中，或手动安装依赖项 (wget, jq, gzip, coreutils)。awk 通常包含在 busybox 中。" >&2
    exit 1
fi
echo -e "${C_BLUE}信息：${C_RESET}检测到包管理器: ${C_CYAN}${PKG_MANAGER}${C_RESET}"

update_run=0
required_cmds=( "wget" "jq" "gunzip" "awk" "sha256sum" )
missing_pkgs=()
missing_cmds_found_initially=()

for cmd_to_check in "${required_cmds[@]}"; do
    if ! command -v "$cmd_to_check" >/dev/null 2>&1; then
        pkg_name=""
        if [ "$cmd_to_check" == "gunzip" ]; then pkg_name="gzip";
        elif [ "$cmd_to_check" == "sha256sum" ]; then pkg_name="coreutils";
        elif [ "$cmd_to_check" == "wget" ] || [ "$cmd_to_check" == "jq" ]; then pkg_name="$cmd_to_check"; fi

        missing_cmds_found_initially+=("$cmd_to_check")
        if [ -n "$pkg_name" ] && ! [[ " ${missing_pkgs[@]} " =~ " ${pkg_name} " ]]; then
             missing_pkgs+=("$pkg_name")
        fi
    fi
done

# --- 尝试安装缺失的软件包 ---
if [ ${#missing_pkgs[@]} -gt 0 ]; then
    missing_pkgs_str=$(IFS=" "; echo "${missing_pkgs[*]}")
    echo -e "${C_YELLOW}警告：${C_RESET}检测到缺失必需的软件包: ${C_CYAN}${missing_pkgs_str}${C_RESET}"
    echo -e "${C_BLUE}信息：${C_RESET}正在尝试使用 '$PKG_MANAGER' 进行安装 (需要 root 权限和网络)..."
    if [ "$update_run" -eq 0 ]; then
        echo -e "${C_BLUE}信息：${C_RESET}  正在运行软件包列表更新 (${C_CYAN}${UPDATE_CMD}${C_RESET})..."
        set +e; $UPDATE_CMD; update_status=$?; set -e
        if [ $update_status -ne 0 ]; then echo -e "${C_YELLOW}警告：${C_RESET}  软件包列表更新失败 (退出码 $update_status)，但仍尝试安装..."; fi
        update_run=1
    fi
    echo -e "${C_BLUE}信息：${C_RESET}  正在运行安装命令 (${C_CYAN}${INSTALL_CMD} ${missing_pkgs_str}${C_RESET})..."
    set +e; $INSTALL_CMD ${missing_pkgs_str}; install_status=$?; set -e
    if [ $install_status -ne 0 ]; then echo -e "${C_YELLOW}警告：${C_RESET}  软件包安装命令退出码为 $install_status。"; fi

    # 重新检查依赖项
    final_recheck_missing_cmds=()
    for cmd_to_recheck in "${missing_cmds_found_initially[@]}"; do
         pkg_to_find=""
         if [ "$cmd_to_recheck" == "gunzip" ]; then pkg_to_find="gzip";
         elif [ "$cmd_to_recheck" == "sha256sum" ]; then pkg_to_find="coreutils";
         elif [ "$cmd_to_recheck" == "wget" ]; then pkg_to_find="wget";
         elif [ "$cmd_to_recheck" == "jq" ]; then pkg_to_find="jq"; fi
         if [[ " ${missing_pkgs[@]} " =~ " ${pkg_to_find} " ]]; then
             if ! command -v "$cmd_to_recheck" >/dev/null 2>&1; then final_recheck_missing_cmds+=("$cmd_to_recheck"); fi
         fi
    done
    if [ ${#final_recheck_missing_cmds[@]} -gt 0 ]; then
         final_missing_cmds_str=$(IFS=" "; echo "${final_recheck_missing_cmds[*]}")
         echo -e "${C_B_RED}错误：${C_RESET}必需的依赖项安装失败或仍然缺失。" >&2
         echo -e "       仍然缺失以下命令: ${C_RED}${final_missing_cmds_str}${C_RESET}" >&2
         exit 1
     else
         echo -e "${C_B_GREEN}信息：${C_RESET}所有尝试安装的必需软件包似乎都已成功安装。"
     fi
fi

# 最终确认所有命令都存在
final_check_missing_cmds=()
for cmd_to_verify in "${required_cmds[@]}"; do if ! command -v "$cmd_to_verify" >/dev/null 2>&1; then final_check_missing_cmds+=("$cmd_to_verify"); fi; done
if [ ${#final_check_missing_cmds[@]} -gt 0 ]; then
    final_missing_cmds_str=$(IFS=" "; echo "${final_check_missing_cmds[*]}")
    echo -e "${C_B_RED}错误：${C_RESET}脚本运行缺少必要的命令: ${C_RED}${final_missing_cmds_str}${C_RESET}" >&2
    exit 1
fi
echo -e "${C_B_GREEN}信息：${C_RESET}所有必需的依赖项 (wget, jq, gunzip, awk, sha256sum) 都已找到。"
echo -e "${C_BLUE}--- 步骤 1 完成 ---${C_RESET}"
echo

# 启用严格错误检查
set -e

# --- 2. 临时增大 /tmp 分区 ---
echo -e "${C_BLUE}--- 步骤 2: 临时增大 /tmp 分区 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}尝试临时将 /tmp 重新挂载为更大内存（RAM 的 100%）..."
echo -e "      ${C_YELLOW}注意：${C_RESET}此更改仅在本次运行期间有效，重启后失效。"
mount -t tmpfs -o remount,size=100% tmpfs /tmp || echo -e "${C_YELLOW}警告：${C_RESET}重新挂载 /tmp 可能失败或不受支持，继续执行..."
echo -e "${C_BLUE}信息：${C_RESET}/tmp 当前挂载信息和大小:"
df -h /tmp
echo -e "${C_BLUE}--- 步骤 2 完成 ---${C_RESET}"
echo

# --- 3. 获取最新 Release 信息 ---
echo -e "${C_BLUE}--- 步骤 3: 获取最新 Release 信息 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在从 GitHub 仓库 '${C_CYAN}${REPO}${C_RESET}' 获取最新版本信息..."
API_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_INFO=$(wget -qO- --no-check-certificate "$API_URL")
if [ -z "$RELEASE_INFO" ]; then echo -e "${C_B_RED}错误：${C_RESET}无法从 GitHub API 获取版本信息。" >&2; exit 1; fi
RELEASE_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name // "未知标签"')
echo -e "${C_BLUE}信息：${C_RESET}找到最新版本标签: ${C_GREEN}${RELEASE_TAG}${C_RESET}"
echo -e "${C_BLUE}--- 步骤 3 完成 ---${C_RESET}"
echo

# --- 4. 查找固件和校验文件 URL ---
echo -e "${C_BLUE}--- 步骤 4: 查找文件 URL ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在查找固件 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 和校验文件 '${C_CYAN}${CHECKSUM_FILENAME}${C_RESET}'..."
IMAGE_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$IMAGE_FILENAME_GZ" '.assets[] | select(.name==$NAME) | .browser_download_url')
CHECKSUM_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$CHECKSUM_FILENAME" '.assets[] | select(.name==$NAME) | .browser_download_url')

SKIP_CHECKSUM=0
if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" == "null" ]; then echo -e "${C_B_RED}错误：${C_RESET}在版本 '${C_YELLOW}${RELEASE_TAG}${C_RESET}' 中未找到固件文件 '${C_RED}${IMAGE_FILENAME_GZ}${C_RESET}'。" >&2; exit 1; fi
echo -e "${C_BLUE}信息：${C_RESET}找到固件下载链接: ${C_CYAN}${IMAGE_URL}${C_RESET}"
if [ -z "$CHECKSUM_URL" ] || [ "$CHECKSUM_URL" == "null" ]; then echo -e "${C_YELLOW}警告：${C_RESET}未找到校验文件 '${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}'，将跳过校验。"; SKIP_CHECKSUM=1; else echo -e "${C_BLUE}信息：${C_RESET}找到校验文件下载链接: ${C_CYAN}${CHECKSUM_URL}${C_RESET}"; fi
echo -e "${C_BLUE}--- 步骤 4 完成 ---${C_RESET}"
echo

# --- 5. 下载前确认 ---
echo -e "${C_BLUE}--- 步骤 5: 下载前确认 ---${C_RESET}"
echo "---------------------------------------------------------------------"
echo -e "${C_BLUE}已找到固件文件，详情如下：${C_RESET}"
echo -e "  版本标签: ${C_GREEN}${RELEASE_TAG}${C_RESET}"
echo -e "  固件链接: ${C_CYAN}${IMAGE_URL}${C_RESET}"
if [ $SKIP_CHECKSUM -eq 1 ]; then echo -e "  校验文件: ${C_YELLOW}未找到${C_RESET}"; else echo -e "  校验链接: ${C_CYAN}${CHECKSUM_URL}${C_RESET}"; fi
echo -e "  目标路径: ${C_CYAN}${IMAGE_PATH_GZ}${C_RESET}"
echo "---------------------------------------------------------------------"
read -p "$(echo -e "${C_YELLOW}❓ 是否开始下载此固件文件？ (y/N): ${C_RESET}")" confirm_download
if [[ ! "$confirm_download" =~ ^[Yy]$ ]]; then echo -e "${C_YELLOW}操作已取消，未下载固件。${C_RESET}"; exit 0; fi
echo

# --- 6. 下载文件 ---
echo -e "${C_BLUE}--- 步骤 6: 下载文件 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在下载压缩固件 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 到 '${C_CYAN}${IMAGE_PATH_GZ}${C_RESET}' ..."
wget --progress=bar:force --no-check-certificate -O "$IMAGE_PATH_GZ" "$IMAGE_URL"
echo -e "${C_B_GREEN}信息：${C_RESET}压缩固件下载完成。"

# 下载校验文件
if [ $SKIP_CHECKSUM -eq 0 ]; then
    echo -e "${C_BLUE}信息：${C_RESET}正在下载校验文件 '${C_CYAN}${CHECKSUM_FILENAME}${C_RESET}' 到 '${C_CYAN}${CHECKSUM_PATH}${C_RESET}' ..."
    set +e; wget -q --no-check-certificate -O "$CHECKSUM_PATH" "$CHECKSUM_URL"; dl_status=$?; set -e
    if [ $dl_status -ne 0 ]; then
        echo -e "${C_YELLOW}警告：${C_RESET}下载校验文件 '${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}' 失败，将跳过文件完整性校验。"
        rm -f "$CHECKSUM_PATH"; SKIP_CHECKSUM=1;
    else echo -e "${C_B_GREEN}信息：${C_RESET}校验文件下载完成。"; fi
fi
echo -e "${C_BLUE}--- 步骤 6 完成 ---${C_RESET}"
echo

# --- 7. 校验固件完整性 ---
echo -e "${C_BLUE}--- 步骤 7: 校验固件完整性 (SHA256) ---${C_RESET}"
if [ $SKIP_CHECKSUM -eq 1 ]; then
    echo -e "${C_YELLOW}信息：跳过文件完整性校验。${C_RESET}"
else
    echo -e "${C_BLUE}信息：${C_RESET}正在校验文件 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 的 SHA256 哈希值..."
    EXPECTED_SUM=$(grep "$IMAGE_FILENAME_GZ" "$CHECKSUM_PATH" | awk '{print $1}')
    if [ -z "$EXPECTED_SUM" ]; then
         echo -e "${C_YELLOW}警告：${C_RESET}在校验文件 '${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}' 中未能找到固件 '${C_YELLOW}${IMAGE_FILENAME_GZ}${C_RESET}' 的校验信息。跳过校验。"
    else
        CALCULATED_SUM=$(sha256sum "$IMAGE_PATH_GZ" | awk '{print $1}')
        echo -e "  >> ${C_BLUE}期望 SHA256:${C_RESET} ${EXPECTED_SUM}"
        echo -e "  >> ${C_BLUE}计算 SHA256:${C_RESET} ${CALCULATED_SUM}"
        if [ "$EXPECTED_SUM" == "$CALCULATED_SUM" ]; then
            echo -e "${C_B_GREEN}✅ 校验成功！文件完整。${C_RESET}"
        else
            echo # 空行分隔
            echo -e "${C_B_RED}❌ 错误：SHA256 校验和不匹配！文件可能已损坏或不完整。${C_RESET}"
            echo # 空行分隔
            read -p "$(echo -e "${C_B_YELLOW}❓ 警告：文件校验失败！是否仍要继续升级？(y/N): ${C_RESET}")" confirm_checksum
            if [[ ! "$confirm_checksum" =~ ^[Yy]$ ]]; then echo -e "${C_YELLOW}操作中止。${C_RESET}"; exit 1; fi
            echo -e "${C_YELLOW}信息：用户选择忽略校验失败并继续。${C_RESET}"
        fi
    fi
fi
rm -f "$CHECKSUM_PATH" # 清理校验文件
echo -e "${C_BLUE}--- 步骤 7 完成 ---${C_RESET}"
echo

# --- 8. 解压固件 ---
echo -e "${C_BLUE}--- 步骤 8: 解压固件 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在解压固件 '${C_CYAN}${IMAGE_PATH_GZ}${C_RESET}' -> '${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}' ..."
gunzip "$IMAGE_PATH_GZ"
if [ ! -f "$IMAGE_PATH_IMG" ]; then echo -e "${C_B_RED}错误：${C_RESET}解压后未找到文件 '${C_RED}${IMAGE_PATH_IMG}${C_RESET}'。" >&2; exit 1; fi
echo -e "${C_B_GREEN}信息：${C_RESET}固件解压完成。解压后文件: '${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}'"
ls -lh "$IMAGE_PATH_IMG"
echo -e "${C_BLUE}--- 步骤 8 完成 ---${C_RESET}"
echo

# --- 9. 检查空间并确定升级选项 ---
echo -e "${C_BLUE}--- 步骤 9: 检查空间并确定升级选项 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在检查 /tmp 可用空间以确定升级选项..."
AVAILABLE_KIB=$(df -k /tmp | awk 'NR==2 {print $4}')

SYSUPGRADE_ARGS=""
KEEP_DATA_ALLOWED=1

if [ -z "$AVAILABLE_KIB" ] || ! [[ "$AVAILABLE_KIB" =~ ^[0-9]+$ ]]; then
    echo -e "${C_YELLOW}警告：${C_RESET}无法准确获取 /tmp 可用空间。将允许用户选择是否保留配置。"
    KEEP_DATA_ALLOWED=1
elif [ "$AVAILABLE_KIB" -lt "$THRESHOLD_KIB" ]; then
    echo -e "${C_YELLOW}警告：${C_RESET}/tmp 可用空间 (${C_YELLOW}${AVAILABLE_KIB}${C_RESET} KiB) 低于所需阈值 (${C_YELLOW}${THRESHOLD_KIB}${C_RESET} KiB)。"
    echo -e "      将强制【${C_B_YELLOW}不保留配置${C_RESET}】数据进行升级 (使用 -n 选项)。"
    SYSUPGRADE_ARGS="-n"; KEEP_DATA_ALLOWED=0;
else
    echo -e "${C_GREEN}信息：${C_RESET}/tmp 可用空间 (${C_GREEN}${AVAILABLE_KIB}${C_RESET} KiB) 充足。"
    KEEP_DATA_ALLOWED=1
fi

if [ "$KEEP_DATA_ALLOWED" -eq 1 ]; then
    echo
    read -p "$(echo -e "${C_YELLOW}❓ 您想在升级时保留配置数据吗？(Y/n): ${C_RESET}")" confirm_keep_data
    if [[ "$confirm_keep_data" =~ ^[Nn]$ ]]; then
        echo -e "${C_BLUE}信息：${C_RESET}用户选择【${C_YELLOW}不保留${C_RESET}】配置数据进行升级。"
        SYSUPGRADE_ARGS="-n"
    else
        echo -e "${C_BLUE}信息：${C_RESET}将尝试【${C_GREEN}保留${C_RESET}】配置数据进行升级。"
        SYSUPGRADE_ARGS=""
    fi
fi
echo -e "${C_BLUE}--- 步骤 9 完成 ---${C_RESET}"
echo

# --- 10. 询问可选参数并最终确认 ---
echo -e "${C_BLUE}--- 步骤 10: 配置可选参数并最终确认 ---${C_RESET}"
UPGRADE_INFO="将使用以下固件文件进行升级：\n  >> ${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}\n\n"
if [ "$SYSUPGRADE_ARGS" == "-n" ]; then UPGRADE_INFO="${UPGRADE_INFO}升级模式:\n  >> ${C_YELLOW}不保留配置数据${C_RESET} (使用 -n 选项)\n"; else UPGRADE_INFO="${UPGRADE_INFO}升级模式:\n  >> ${C_GREEN}尝试保留配置数据${C_RESET}\n"; fi
if [ $SKIP_CHECKSUM -eq 1 ]; then UPGRADE_INFO="${UPGRADE_INFO}\n文件校验:\n  >> ${C_YELLOW}跳过或未执行${C_RESET}\n"; else UPGRADE_INFO="${UPGRADE_INFO}\n文件校验:\n  >> ${C_GREEN}SHA256 校验通过${C_RESET} (或用户忽略失败)\n"; fi

# --- 询问是否强制升级 (-F) ---
FORCE_FLAG=""
FORCE_WARN="\n\n!!!!!!!!!!!!!!!!!!!!!!!!!!!! ${C_B_RED}危 险 操 作 提 示${C_RESET} !!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
FORCE_WARN="${FORCE_WARN} ${C_YELLOW}'-F' (force) 选项会跳过固件兼容性检查。${C_RESET}\n"
FORCE_WARN="${FORCE_WARN} ${C_RED}错误或不兼容的固件配合 -F 选项极易导致设备变砖！${C_RESET}\n"
FORCE_WARN="${FORCE_WARN} ${C_YELLOW}仅在您完全确定固件正确且了解风险时才应使用。${C_RESET}\n"
FORCE_WARN="${FORCE_WARN}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
echo -e "$FORCE_WARN"
read -p "$(echo -e "${C_B_YELLOW}❓ 是否要在本次升级中使用强制 '-F' 选项？ (y/N): ${C_RESET}")" confirm_force
FORCE_FLAG_INFO=""
if [[ "$confirm_force" =~ ^[Yy]$ ]]; then
    echo -e "${C_BLUE}信息：${C_RESET}用户选择【${C_B_RED}使用${C_RESET}】强制 '-F' 选项！"
    FORCE_FLAG="-F"; FORCE_FLAG_INFO="\n强制执行:\n  >> ${C_B_RED}是 (-F 选项)${C_RESET}\n";
else
    echo -e "${C_BLUE}信息：${C_RESET}本次升级将【${C_GREEN}不使用${C_RESET}】强制 '-F' 选项。"
    FORCE_FLAG=""; FORCE_FLAG_INFO="\n强制执行:\n  >> ${C_GREEN}否${C_RESET}\n";
fi
UPGRADE_INFO="${UPGRADE_INFO}${FORCE_FLAG_INFO}"

# --- 询问是否详细输出 (-v) ---
VERBOSE_FLAG=""
echo # 空行分隔
read -p "$(echo -e "${C_YELLOW}❓ 是否要在本次升级中启用详细输出模式 '-v' (verbose)？ (y/N): ${C_RESET}")" confirm_verbose
VERBOSE_FLAG_INFO=""
if [[ "$confirm_verbose" =~ ^[Yy]$ ]]; then
    echo -e "${C_BLUE}信息：${C_RESET}用户选择【${C_GREEN}启用${C_RESET}】详细输出模式 (-v)。"
    VERBOSE_FLAG="-v"; VERBOSE_FLAG_INFO="\n详细输出:\n  >> ${C_GREEN}是 (-v 选项)${C_RESET}\n";
else
    echo -e "${C_BLUE}信息：${C_RESET}本次升级将【${C_YELLOW}不启用${C_RESET}】详细输出模式。"
    VERBOSE_FLAG=""; VERBOSE_FLAG_INFO="\n详细输出:\n  >> ${C_YELLOW}否${C_RESET}\n";
fi
UPGRADE_INFO="${UPGRADE_INFO}${VERBOSE_FLAG_INFO}"

# --- 最终确认与执行 ---
echo
echo -e "${C_BLUE}========================= 升 级 前 最 终 确 认 ========================${C_RESET}"
echo -e "$UPGRADE_INFO" # 显示包含所有选项状态的最终信息
if [ -z "$SYSUPGRADE_ARGS" ]; then echo -e "${C_YELLOW}建议提前备份重要数据。${C_RESET}\n"; fi
echo -e "${C_B_YELLOW}升级过程中，请务必保持设备通电，不要中断操作！${C_RESET}"
echo -e "${C_BLUE}=====================================================================${C_RESET}"
echo
read -p "$(echo -e "${C_B_YELLOW}❓ 确认要开始执行 sysupgrade 升级吗？ (y/N): ${C_RESET}")" confirm_upgrade

if [[ "$confirm_upgrade" =~ ^[Yy]$ ]]; then
    # 构造最终执行信息
    MSG_DESC="信息：正在执行 sysupgrade 命令 ("
    FLAG_DESC=""
    [ -n "$FORCE_FLAG" ] && FLAG_DESC="${C_B_RED}强制${C_RESET}${FLAG_DESC}"
    [ -n "$VERBOSE_FLAG" ] && FLAG_DESC="${FLAG_DESC}${FLAG_DESC:+, }${C_GREEN}详细${C_RESET}" # Add comma if needed

    if [ -z "$SYSUPGRADE_ARGS" ]; then DATA_DESC="${C_GREEN}保留数据${C_RESET}"; else DATA_DESC="${C_YELLOW}不保留数据${C_RESET}"; fi
    if [ -n "$FLAG_DESC" ]; then MSG_DESC="${MSG_DESC}${FLAG_DESC}, ${DATA_DESC})..."; else MSG_DESC="${MSG_DESC}${DATA_DESC})..."; fi
    echo -e "$MSG_DESC"

    # 执行命令
    sysupgrade $FORCE_FLAG $VERBOSE_FLAG $SYSUPGRADE_ARGS "$IMAGE_PATH_IMG"

    echo # 换行
    echo -e "${C_B_GREEN}✅ 信息：sysupgrade 命令已执行。如果成功，系统将会重启。${C_RESET}"
    # *** 修改点：确保 trap cleanup EXIT 仍然有效 ***
    # trap - EXIT # 这一行已被移除，确保 cleanup 会执行
    exit 0 # 正常退出，此时 cleanup 会被执行
else
    echo # 换行
    echo -e "${C_YELLOW}操作已取消。${C_RESET}解压后的固件文件保留在 '${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}'，您可以手动升级或删除它。"
    # 此路径退出时，cleanup 也会被执行
    exit 0
fi

exit 0 # 备用退出点 (cleanup 会被执行)