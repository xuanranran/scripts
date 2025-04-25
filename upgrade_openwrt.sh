#!/bin/bash

# --- 配置 ---
REPO="xuanranran/OpenWRT-X86_64"                                           # 目标 GitHub 仓库
IMAGE_FILENAME_GZ="immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz" # 压缩固件的文件名
IMAGE_FILENAME_IMG="${IMAGE_FILENAME_GZ%.gz}"                             # 解压后的固件文件名 (自动从压缩文件名生成)
CHECKSUM_FILENAME="sha256sums"                                             # 校验和文件名 (假设)
TMP_DIR="/tmp"                                                             # 临时文件目录
IMAGE_PATH_GZ="$TMP_DIR/$IMAGE_FILENAME_GZ"                                # 压缩固件的完整路径
IMAGE_PATH_IMG="$TMP_DIR/$IMAGE_FILENAME_IMG"                              # 解压后固件的完整路径
CHECKSUM_PATH="$TMP_DIR/$CHECKSUM_FILENAME"                                # 校验和文件的完整路径
THRESHOLD_KIB=1887437                                                      # 保留数据的空间阈值 (1.8 GiB in KiB)

# --- 退出脚本时清理临时文件 ---
# cleanup() {
  # echo # 清理前空一行
  # echo "信息：正在清理临时文件..."
  # rm -f "$IMAGE_PATH_GZ" "$IMAGE_PATH_IMG" "$CHECKSUM_PATH" # 清理压缩包、解压后的文件和校验文件
# }
# trap cleanup EXIT

#清理文件
clean_up () {
    rm -rf *.img* ${img_path}/*.img* *sha256sums* *update*.sh*
}

# --- 设置：如果任何命令失败则立即退出 ---
# 在依赖项安装步骤中会临时禁用此设置
# set -e

echo
echo "====================================================================="
echo " OpenWRT/ImmortalWrt 自动升级脚本 "
echo "====================================================================="
echo

# --- 1. 检查并尝试安装依赖项 (检查 wget, jq, gunzip, awk, sha256sum) ---
echo "--- 步骤 1: 检查并尝试安装依赖项 ---"
echo "信息：检查所需工具 (wget, jq, gunzip, awk, sha256sum)..."

PKG_MANAGER=""             # 检测到的包管理器 (opkg 或 apk)
UPDATE_CMD=""              # 更新命令
INSTALL_CMD=""             # 安装命令

# 检测包管理器 (省略部分 echo，已包含在上面标题中)
if command -v opkg >/dev/null 2>&1; then
    PKG_MANAGER="opkg"; UPDATE_CMD="opkg update"; INSTALL_CMD="opkg install";
elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"; UPDATE_CMD="apk update"; INSTALL_CMD="apk add";
else
    echo >&2 "错误：无法检测到 'opkg' 或 'apk' 包管理器。"
    echo >&2 "请确保其中一个已安装并位于 PATH 中，或手动安装依赖项 (wget, jq, gzip, coreutils)。awk 通常包含在 busybox 中。"
    exit 1
fi
echo "信息：检测到包管理器: $PKG_MANAGER"

update_run=0 # 标记更新命令是否已运行
required_cmds=( "wget" "jq" "gunzip" "awk" "sha256sum" ) # 需要检查的命令
missing_pkgs=()                        # 需要安装的软件包列表
missing_cmds_found_initially=()        # 初始检查时未找到的命令列表

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
    echo "警告：检测到缺失必需的软件包: ${missing_pkgs_str}"
    echo "信息：正在尝试使用 '$PKG_MANAGER' 进行安装 (需要 root 权限和网络)..."
    if [ "$update_run" -eq 0 ]; then
        echo "信息：  正在运行软件包列表更新 ($UPDATE_CMD)..."
        set +e; $UPDATE_CMD; update_status=$?; set -e
        if [ $update_status -ne 0 ]; then echo "警告：  软件包列表更新失败 (退出码 $update_status)，但仍尝试安装..."; fi
        update_run=1
    fi
    echo "信息：  正在运行安装命令 ($INSTALL_CMD ${missing_pkgs_str})..."
    set +e; $INSTALL_CMD ${missing_pkgs_str}; install_status=$?; set -e
    if [ $install_status -ne 0 ]; then echo "警告：  软件包安装命令退出码为 $install_status。"; fi

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
         echo >&2 "错误：必需的依赖项安装失败或仍然缺失: ${final_missing_cmds_str}"
         exit 1
     else
         echo "信息：所有尝试安装的必需软件包似乎都已成功安装。"
     fi
fi

# 最终确认所有命令都存在
final_check_missing_cmds=()
for cmd_to_verify in "${required_cmds[@]}"; do if ! command -v "$cmd_to_verify" >/dev/null 2>&1; then final_check_missing_cmds+=("$cmd_to_verify"); fi; done
if [ ${#final_check_missing_cmds[@]} -gt 0 ]; then
    final_missing_cmds_str=$(IFS=" "; echo "${final_check_missing_cmds[*]}")
    echo >&2 "错误：脚本运行缺少必要的命令: ${final_missing_cmds_str}"
    exit 1
fi
echo "信息：所有必需的依赖项 (wget, jq, gunzip, awk, sha256sum) 都已找到。"
echo "--- 步骤 1 完成 ---"
echo

# 启用严格错误检查
set -e

# --- 2. 临时增大 /tmp 分区 ---
echo "--- 步骤 2: 临时增大 /tmp 分区 ---"
echo "信息：尝试临时将 /tmp 重新挂载为更大内存（RAM 的 100%）..."
echo "      注意：此更改仅在本次运行期间有效，重启后失效。"
mount -t tmpfs -o remount,size=100% tmpfs /tmp || echo "警告：重新挂载 /tmp 可能失败或不受支持，继续执行..."
echo "信息：/tmp 当前挂载信息和大小:"
df -h /tmp
echo "--- 步骤 2 完成 ---"
echo

# --- 3. 获取最新 Release 信息 ---
echo "--- 步骤 3: 获取最新 Release 信息 ---"
echo "信息：正在从 GitHub 仓库 '$REPO' 获取最新版本信息..."
API_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_INFO=$(wget -qO- --no-check-certificate "$API_URL")
if [ -z "$RELEASE_INFO" ]; then echo >&2 "错误：无法从 GitHub API 获取版本信息。"; exit 1; fi
RELEASE_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name // "未知标签"')
echo "信息：找到最新版本标签: $RELEASE_TAG"
echo "--- 步骤 3 完成 ---"
echo

# --- 4. 查找固件和校验文件 URL ---
echo "--- 步骤 4: 查找文件 URL ---"
echo "信息：正在查找固件 '$IMAGE_FILENAME_GZ' 和校验文件 '$CHECKSUM_FILENAME'..."
IMAGE_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$IMAGE_FILENAME_GZ" '.assets[] | select(.name==$NAME) | .browser_download_url')
CHECKSUM_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$CHECKSUM_FILENAME" '.assets[] | select(.name==$NAME) | .browser_download_url')

SKIP_CHECKSUM=0
if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" == "null" ]; then echo >&2 "错误：在版本 '$RELEASE_TAG' 中未找到固件文件 '$IMAGE_FILENAME_GZ'。"; exit 1; fi
echo "信息：找到固件下载链接: $IMAGE_URL"
if [ -z "$CHECKSUM_URL" ] || [ "$CHECKSUM_URL" == "null" ]; then echo "警告：未找到校验文件 '$CHECKSUM_FILENAME'，将跳过校验。"; SKIP_CHECKSUM=1; else echo "信息：找到校验文件下载链接: $CHECKSUM_URL"; fi
echo "--- 步骤 4 完成 ---"
echo

# --- 5. 下载前确认 ---
echo "--- 步骤 5: 下载前确认 ---"
echo "---------------------------------------------------------------------"
echo "已找到固件文件，详情如下："
echo "  版本标签: $RELEASE_TAG"
echo "  固件链接: $IMAGE_URL"
if [ $SKIP_CHECKSUM -eq 1 ]; then echo "  校验文件: 未找到"; else echo "  校验链接: $CHECKSUM_URL"; fi
echo "  目标路径: $IMAGE_PATH_GZ"
echo "---------------------------------------------------------------------"
read -p "是否开始下载此固件文件？ (y/N): " confirm_download
if [[ ! "$confirm_download" =~ ^[Yy]$ ]]; then echo "操作已取消，未下载固件。"; exit 0; fi
echo

# --- 6. 下载文件 ---
echo "--- 步骤 6: 下载文件 ---"
echo "信息：正在下载压缩固件 '$IMAGE_FILENAME_GZ' 到 '$IMAGE_PATH_GZ' ..."
wget --progress=bar:force --no-check-certificate -O "$IMAGE_PATH_GZ" "$IMAGE_URL"
echo "信息：压缩固件下载完成。"

# 下载校验文件 (如果找到链接的话)
if [ $SKIP_CHECKSUM -eq 0 ]; then
    echo "信息：正在下载校验文件 '$CHECKSUM_FILENAME' 到 '$CHECKSUM_PATH' ..."
    set +e; wget -q --no-check-certificate -O "$CHECKSUM_PATH" "$CHECKSUM_URL"; dl_status=$?; set -e
    if [ $dl_status -ne 0 ]; then
        echo "警告：下载校验文件 '$CHECKSUM_FILENAME' 失败，将跳过文件完整性校验。"
        rm -f "$CHECKSUM_PATH"; SKIP_CHECKSUM=1;
    else echo "信息：校验文件下载完成。"; fi
fi
echo "--- 步骤 6 完成 ---"
echo

# --- 7. 校验固件完整性 ---
echo "--- 步骤 7: 校验固件完整性 (SHA256) ---"
if [ $SKIP_CHECKSUM -eq 1 ]; then
    echo "信息：跳过文件完整性校验。"
else
    echo "信息：正在校验文件 '$IMAGE_FILENAME_GZ' 的 SHA256 哈希值..."
    EXPECTED_SUM=$(grep "$IMAGE_FILENAME_GZ" "$CHECKSUM_PATH" | awk '{print $1}')
    if [ -z "$EXPECTED_SUM" ]; then
         echo "警告：在校验文件 '$CHECKSUM_FILENAME' 中未能找到固件 '$IMAGE_FILENAME_GZ' 的校验信息。跳过校验。"
    else
        CALCULATED_SUM=$(sha256sum "$IMAGE_PATH_GZ" | awk '{print $1}')
        echo "  >> 期望 SHA256: $EXPECTED_SUM"
        echo "  >> 计算 SHA256: $CALCULATED_SUM"
        if [ "$EXPECTED_SUM" == "$CALCULATED_SUM" ]; then
            echo "✅ 校验成功！文件完整。"
        else
            echo "❌ 错误：SHA256 校验和不匹配！文件可能已损坏或不完整。"
            echo
            read -p "❓ 警告：文件校验失败！是否仍要继续升级？(y/N): " confirm_checksum
            if [[ ! "$confirm_checksum" =~ ^[Yy]$ ]]; then echo "操作中止。"; exit 1; fi
            echo "信息：用户选择忽略校验失败并继续。"
        fi
    fi
fi
# 清理校验文件
rm -f "$CHECKSUM_PATH"
echo "--- 步骤 7 完成 ---"
echo

# --- 8. 解压固件 ---
echo "--- 步骤 8: 解压固件 ---"
echo "信息：正在解压固件 '$IMAGE_PATH_GZ' -> '$IMAGE_PATH_IMG' ..."
gunzip "$IMAGE_PATH_GZ"
if [ ! -f "$IMAGE_PATH_IMG" ]; then echo >&2 "错误：解压后未找到文件 '$IMAGE_PATH_IMG'。"; exit 1; fi
echo "信息：固件解压完成。解压后文件: '$IMAGE_PATH_IMG'"
ls -lh "$IMAGE_PATH_IMG"
echo "--- 步骤 8 完成 ---"
echo

# --- 9. 检查空间并确定升级选项 ---
echo "--- 步骤 9: 检查空间并确定升级选项 ---"
echo "信息：正在检查 /tmp 可用空间以确定升级选项..."
AVAILABLE_KIB=$(df -k /tmp | awk 'NR==2 {print $4}')

SYSUPGRADE_ARGS="" # -n 或空
KEEP_DATA_ALLOWED=1 # 是否允许保留数据

if [ -z "$AVAILABLE_KIB" ] || ! [[ "$AVAILABLE_KIB" =~ ^[0-9]+$ ]]; then
    echo "警告：无法准确获取 /tmp 可用空间。将允许用户选择是否保留配置。"
    KEEP_DATA_ALLOWED=1
elif [ "$AVAILABLE_KIB" -lt "$THRESHOLD_KIB" ]; then
    echo "警告：/tmp 可用空间 (${AVAILABLE_KIB} KiB) 低于所需阈值 (${THRESHOLD_KIB} KiB)。"
    echo "      将强制【不保留配置】数据进行升级 (使用 -n 选项)。"
    SYSUPGRADE_ARGS="-n"; KEEP_DATA_ALLOWED=0;
else
    echo "信息：/tmp 可用空间 (${AVAILABLE_KIB} KiB) 充足。"
    KEEP_DATA_ALLOWED=1
fi

if [ "$KEEP_DATA_ALLOWED" -eq 1 ]; then
    echo # 空行让提示更清晰
    read -p "您想在升级时保留配置数据吗？(Y/n): " confirm_keep_data
    if [[ "$confirm_keep_data" =~ ^[Nn]$ ]]; then
        echo "信息：用户选择【不保留】配置数据进行升级。"
        SYSUPGRADE_ARGS="-n"
    else
        echo "信息：将尝试【保留】配置数据进行升级。"
        SYSUPGRADE_ARGS=""
    fi
fi
echo "--- 步骤 9 完成 ---"
echo

# --- 10. 询问可选参数并最终确认 ---
echo "--- 步骤 10: 配置可选参数并最终确认 ---"
# 设置关于数据保留的基本提示信息
UPGRADE_INFO="将使用以下固件文件进行升级：\n  >> $IMAGE_PATH_IMG\n\n" # 增加缩进
if [ "$SYSUPGRADE_ARGS" == "-n" ]; then
    UPGRADE_INFO="${UPGRADE_INFO}升级模式:\n  >> 不保留配置数据 (使用 -n 选项)\n"
else
    UPGRADE_INFO="${UPGRADE_INFO}升级模式:\n  >> 尝试保留配置数据\n"
fi
# 添加校验状态信息
if [ $SKIP_CHECKSUM -eq 1 ]; then
    UPGRADE_INFO="${UPGRADE_INFO}\n文件校验:\n  >> 跳过或未执行\n"
else
     # 如果校验执行过且成功 (或者用户忽略失败继续), 这里可以认为是通过
     UPGRADE_INFO="${UPGRADE_INFO}\n文件校验:\n  >> SHA256 校验通过 (或用户忽略失败)\n"
fi

# --- 询问是否强制升级 (-F) ---
FORCE_FLAG=""
FORCE_WARN="\n!!!!!!!!!!!!!!!!!!!!!!!!!!!! 危 险 操 作 提 示 !!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
FORCE_WARN="${FORCE_WARN} '-F' (force) 选项会跳过固件兼容性检查。\n"
FORCE_WARN="${FORCE_WARN} 错误或不兼容的固件配合 -F 选项极易导致设备变砖！\n"
FORCE_WARN="${FORCE_WARN} 仅在您完全确定固件正确且了解风险时才应使用。\n"
FORCE_WARN="${FORCE_WARN}!!!!!!!!!!!!!!!!!!!!!!!!!!!! 危 险 操 作 提 示 !!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
echo -e "$FORCE_WARN"
read -p "是否要在本次升级中使用强制 '-F' 选项？ (y/N): " confirm_force
FORCE_FLAG_INFO=""
if [[ "$confirm_force" =~ ^[Yy]$ ]]; then
    echo "信息：用户选择【使用】强制 '-F' 选项！"
    FORCE_FLAG="-F"
    FORCE_FLAG_INFO="\n强制执行:\n  >> 是 (-F 选项)\n"
else
    echo "信息：本次升级将【不使用】强制 '-F' 选项。"
    FORCE_FLAG=""
    FORCE_FLAG_INFO="\n强制执行:\n  >> 否\n"
fi
UPGRADE_INFO="${UPGRADE_INFO}${FORCE_FLAG_INFO}" # 添加 -F 状态到摘要

# --- 询问是否详细输出 (-v) ---
VERBOSE_FLAG=""
echo # 空行分隔
read -p "是否要在本次升级中启用详细输出模式 '-v' (verbose)？ (y/N): " confirm_verbose
VERBOSE_FLAG_INFO=""
if [[ "$confirm_verbose" =~ ^[Yy]$ ]]; then
    echo "信息：用户选择【启用】详细输出模式 (-v)。"
    VERBOSE_FLAG="-v"
    VERBOSE_FLAG_INFO="\n详细输出:\n  >> 是 (-v 选项)\n"
else
    echo "信息：本次升级将【不启用】详细输出模式。"
    VERBOSE_FLAG=""
    VERBOSE_FLAG_INFO="\n详细输出:\n  >> 否\n"
fi
UPGRADE_INFO="${UPGRADE_INFO}${VERBOSE_FLAG_INFO}" # 添加 -v 状态到摘要

# --- 最终确认与执行 ---
echo
echo "========================= 升 级 前 最 终 确 认 ========================="
echo -e "$UPGRADE_INFO" # 显示包含所有选项状态的最终信息
if [ -z "$SYSUPGRADE_ARGS" ]; then echo "建议提前备份重要数据。\n"; fi
echo "升级过程中，请务必保持设备通电，不要中断操作！"
echo "====================================================================="
echo
read -p "确认要开始执行 sysupgrade 升级吗？ (y/N): " confirm_upgrade

if [[ "$confirm_upgrade" =~ ^[Yy]$ ]]; then
    # 构造最终执行信息
    MSG_DESC="信息：正在执行 sysupgrade 命令 ("
    FLAG_DESC=""
    [ -n "$FORCE_FLAG" ] && FLAG_DESC="强制$FLAG_DESC"
    [ -n "$VERBOSE_FLAG" ] && FLAG_DESC="${FLAG_DESC}${FLAG_DESC:+, }详细"

    if [ -z "$SYSUPGRADE_ARGS" ]; then DATA_DESC="保留数据"; else DATA_DESC="不保留数据"; fi
    if [ -n "$FLAG_DESC" ]; then MSG_DESC="${MSG_DESC}${FLAG_DESC}, ${DATA_DESC})..."; else MSG_DESC="${MSG_DESC}${DATA_DESC})..."; fi
    echo "$MSG_DESC"

    # 执行命令
    sysupgrade $FORCE_FLAG $VERBOSE_FLAG $SYSUPGRADE_ARGS "$IMAGE_PATH_IMG"

    echo # 换行
    echo "信息：sysupgrade 命令已执行。如果成功，系统将会重启。"
    exit 0
else
    echo # 换行
    echo "操作已取消。解压后的固件文件保留在 '$IMAGE_PATH_IMG'，您可以手动升级或删除它。"
    exit 0
fi

exit 0 # 备用退出点