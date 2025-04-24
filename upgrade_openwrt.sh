#!/bin/bash

# --- 配置 ---
REPO="xuanranran/OpenWRT-X86_64"                                           # 目标 GitHub 仓库
IMAGE_FILENAME_GZ="immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz" # 压缩固件的文件名
IMAGE_FILENAME_IMG="${IMAGE_FILENAME_GZ%.gz}"                             # 解压后的固件文件名 (自动从压缩文件名生成)
TMP_DIR="/tmp"                                                             # 临时文件目录
IMAGE_PATH_GZ="$TMP_DIR/$IMAGE_FILENAME_GZ"                                # 压缩固件的完整路径
IMAGE_PATH_IMG="$TMP_DIR/$IMAGE_FILENAME_IMG"                              # 解压后固件的完整路径
THRESHOLD_KIB=1887437                                                      # 保留数据的空间阈值 (1.8 GiB in KiB)

# --- 退出脚本时清理临时文件 ---
cleanup() {
  echo "信息：正在清理临时文件..."
  rm -f "$IMAGE_PATH_GZ" "$IMAGE_PATH_IMG" # 清理压缩包和解压后的文件
}
trap cleanup EXIT

# --- 设置：如果任何命令失败则立即退出 ---
# 在依赖项安装步骤中会临时禁用此设置
# set -e

# --- 1. 检查并尝试安装依赖项 (检查 wget, jq, gunzip, awk) ---
echo "信息：正在检查并尝试安装所需工具 (wget, jq, gunzip, awk)..." # 添加了 awk

PKG_MANAGER=""             # 检测到的包管理器 (opkg 或 apk)
UPDATE_CMD=""              # 更新命令
INSTALL_CMD=""             # 安装命令

# 检测包管理器
if command -v opkg >/dev/null 2>&1; then
    echo "信息：检测到 'opkg' 包管理器 (OpenWrt 24.10.1-Snapshot)。"
    PKG_MANAGER="opkg"
    UPDATE_CMD="opkg update"
    INSTALL_CMD="opkg install"
elif command -v apk >/dev/null 2>&1; then
    echo "信息：检测到 'apk' 包管理器 (OpenWrt Snapshot)。"
    PKG_MANAGER="apk"
    UPDATE_CMD="apk update"
    INSTALL_CMD="apk add" # apk 使用 'add'
else
    echo >&2 "错误：无法检测到 'opkg' 或 'apk' 包管理器。"
    # 注意：gunzip 命令通常由 gzip 包提供, awk 通常由 busybox 提供
    echo >&2 "请确保其中一个已安装并位于 PATH 中，或手动安装依赖项 (wget, jq, gzip)。awk 通常包含在 busybox 中。"
    exit 1
fi

update_run=0 # 标记更新命令是否已运行

# --- 定义需要的 '命令' 并检查 ---
required_cmds=( "wget" "jq" "gunzip" "awk" ) # 需要检查的命令
missing_pkgs=()                        # 需要安装的软件包列表 (不包含 busybox/awk)
missing_cmds_found_initially=()        # 初始检查时未找到的命令列表

echo "信息：正在检查所需的 命令 (wget, jq, gunzip, awk) 并识别需要安装的 软件包..."
for cmd_to_check in "${required_cmds[@]}"; do
    echo "信息：  检查 命令 '$cmd_to_check'..."
    if ! command -v "$cmd_to_check" >/dev/null 2>&1; then
        pkg_name="" # 假设初始没有独立包
        # 确定提供该命令的包名
        if [ "$cmd_to_check" == "gunzip" ]; then
            pkg_name="gzip"
        elif [ "$cmd_to_check" == "wget" ] || [ "$cmd_to_check" == "jq" ]; then
             pkg_name="$cmd_to_check"
        fi

        echo "信息：  命令 '$cmd_to_check' 未找到。"
        missing_cmds_found_initially+=("$cmd_to_check") # 记录未找到的 命令

        # 只将明确需要安装的包加入列表
        if [ -n "$pkg_name" ]; then
            echo "        这个命令通常由 软件包 '$pkg_name' 提供。"
            if ! [[ " ${missing_pkgs[@]} " =~ " ${pkg_name} " ]]; then
                 missing_pkgs+=("$pkg_name")
            fi
        else
             # awk 通常是 busybox 的一部分
             echo "        这个命令 ('$cmd_to_check') 通常由系统基础包 (如 busybox) 提供。"
        fi
    else
        echo "信息：  命令 '$cmd_to_check' 已找到。"
    fi
done

# --- 尝试安装缺失的软件包 (wget, jq, gzip only) ---
if [ ${#missing_pkgs[@]} -gt 0 ]; then
    missing_pkgs_str=$(IFS=" "; echo "${missing_pkgs[*]}")
    echo "信息：检测到缺失必需的软件包: ${missing_pkgs_str}"
    echo "信息：正在尝试使用 '$PKG_MANAGER' 进行安装..."

    # 运行一次更新命令
    if [ "$update_run" -eq 0 ]; then
        echo "信息：正在运行软件包列表更新 ($UPDATE_CMD)..."
        set +e; $UPDATE_CMD; update_status=$?; set -e
        if [ $update_status -ne 0 ]; then
             echo "警告：软件包列表更新命令 '$UPDATE_CMD' 失败 (退出码 $update_status)，但仍将尝试安装..."
        fi
        update_run=1
    fi

    # 安装缺失的软件包
    echo "信息：正在运行安装命令 ($INSTALL_CMD ${missing_pkgs_str})..."
    set +e; $INSTALL_CMD ${missing_pkgs_str}; install_status=$?; set -e
    if [ $install_status -ne 0 ]; then
        echo "警告：软件包安装命令 '$INSTALL_CMD ${missing_pkgs_str}' 的退出码为 $install_status。"
    fi

    # 重新检查所有最初缺失的命令（包括可能未尝试安装的 awk）
    echo "信息：正在重新检查依赖项..."
    final_recheck_missing_cmds=()
    for cmd_to_recheck in "${missing_cmds_found_initially[@]}"; do
        if ! command -v "$cmd_to_recheck" >/dev/null 2>&1; then
             final_recheck_missing_cmds+=("$cmd_to_recheck")
        fi
    done

    # 如果安装后仍然有命令缺失，则报错退出
    if [ ${#final_recheck_missing_cmds[@]} -gt 0 ]; then
         final_missing_cmds_str=$(IFS=" "; echo "${final_recheck_missing_cmds[*]}")
         echo >&2 "错误：必需的依赖项安装失败或仍然缺失。"
         echo >&2 "       仍然缺失以下命令: ${final_missing_cmds_str}"
         if [[ " ${final_missing_cmds_str} " =~ " awk " ]]; then
            echo >&2 "       'awk' 命令缺失通常表明系统基础不完整。"
         else
            echo >&2 "       请检查网络连接、$PKG_MANAGER 配置，并尝试手动安装。"
         fi
         exit 1
     else
         echo "信息：所有必需的软件包似乎都已成功安装。"
     fi
fi

# 最终确认所有命令都存在
echo "信息：依赖项最终检查..."
final_check_missing_cmds=()
for cmd_to_verify in "${required_cmds[@]}"; do
    if ! command -v "$cmd_to_verify" >/dev/null 2>&1; then
        final_check_missing_cmds+=("$cmd_to_verify")
    fi
done

if [ ${#final_check_missing_cmds[@]} -gt 0 ]; then
    final_missing_cmds_str=$(IFS=" "; echo "${final_check_missing_cmds[*]}")
    echo >&2 "错误：脚本运行缺少必要的命令: ${final_missing_cmds_str}"
    # 提示具体原因
    if [[ " ${final_missing_cmds_str} " =~ " awk " ]]; then
         echo >&2 "       'awk' 命令缺失，这通常表明系统基础 (busybox) 不完整，脚本无法继续。"
    else
         echo >&2 "       请检查之前的安装日志或尝试手动安装。"
    fi
    exit 1
fi
echo "信息：所有必需的依赖项 (wget, jq, gunzip, awk) 都已找到。"

# 启用严格错误检查
set -e

# --- 2. 临时增大 /tmp 分区 ---
echo "信息：尝试临时将 /tmp 重新挂载为更大内存（RAM 的 100%）..."
echo "      注意：此更改仅在本次运行期间有效，重启后失效。"
mount -t tmpfs -o remount,size=100% tmpfs /tmp || echo "警告：重新挂载 /tmp 可能失败或不受支持，继续执行..."
echo "信息：/tmp 当前挂载信息和大小:"
mount | grep " /tmp " || echo "信息：/tmp 可能未显示在 mount 输出中，或不是独立挂载点。"
df -h /tmp

# --- 3. 获取最新 Release 信息 ---
echo "信息：正在从 GitHub 仓库 '$REPO' 获取最新版本信息..."
API_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_INFO=$(wget -qO- --no-check-certificate "$API_URL")

if [ -z "$RELEASE_INFO" ]; then
    echo >&2 "错误：无法从 GitHub API 获取版本信息。请检查网络连接或仓库 '$REPO' 是否存在。"
    exit 1
fi

# --- 4. 查找固件文件 URL ---
echo "信息：正在查找压缩固件 '$IMAGE_FILENAME_GZ' 的下载链接..."
IMAGE_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$IMAGE_FILENAME_GZ" '.assets[] | select(.name==$NAME) | .browser_download_url')
RELEASE_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name // "未知标签"')

if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" == "null" ]; then
    echo >&2 "错误：在最新版本 '$RELEASE_TAG' 中未找到压缩固件文件 '$IMAGE_FILENAME_GZ'。"
    echo >&2 "       请检查仓库发布或脚本中的文件名配置。"
    exit 1
fi
echo "信息：找到最新版本 '$RELEASE_TAG'"
echo "信息：压缩固件下载链接: $IMAGE_URL"

# --- 5. 下载压缩固件 ---
echo "信息：正在下载压缩固件 '$IMAGE_FILENAME_GZ' 到 '$IMAGE_PATH_GZ' ..."
wget --progress=bar:force --no-check-certificate -O "$IMAGE_PATH_GZ" "$IMAGE_URL"
echo "信息：压缩固件下载完成。"

# --- 6. 解压固件 (需要 gunzip 命令) ---
echo "信息：正在解压固件 '$IMAGE_PATH_GZ' -> '$IMAGE_PATH_IMG' ..."
gunzip "$IMAGE_PATH_GZ"

if [ ! -f "$IMAGE_PATH_IMG" ]; then
     echo >&2 "错误：解压命令似乎已执行，但未找到预期的解压后文件 '$IMAGE_PATH_IMG'。"
     exit 1
fi
echo "信息：固件解压完成。解压后文件: '$IMAGE_PATH_IMG'"
ls -lh "$IMAGE_PATH_IMG"
echo "警告：已跳过文件完整性校验！请自行承担风险。"


# --- 7. 检查空间并确定升级选项 ---
echo "信息：正在检查 /tmp 可用空间以确定升级选项..."
AVAILABLE_KIB=$(df -k /tmp | awk 'NR==2 {print $4}')

SYSUPGRADE_ARGS="" # sysupgrade 命令参数，默认为空（保留配置）
KEEP_DATA_ALLOWED=1 # 标记是否允许保留数据 (1=允许, 0=不允许)

if [ -z "$AVAILABLE_KIB" ] || ! [[ "$AVAILABLE_KIB" =~ ^[0-9]+$ ]]; then
    echo "警告：无法准确获取 /tmp 可用空间。将允许用户选择是否保留配置。"
    KEEP_DATA_ALLOWED=1 # 获取失败时，允许用户选择以防误判
elif [ "$AVAILABLE_KIB" -lt "$THRESHOLD_KIB" ]; then
    echo "警告：/tmp 可用空间 (${AVAILABLE_KIB} KiB) 低于所需阈值 (${THRESHOLD_KIB} KiB)。"
    echo "      为了保证升级成功，将强制不保留配置数据进行升级 (使用 -n 选项)。"
    SYSUPGRADE_ARGS="-n"
    KEEP_DATA_ALLOWED=0
else
    echo "信息：/tmp 可用空间 (${AVAILABLE_KIB} KiB) 充足，可以选择是否保留配置数据。"
    KEEP_DATA_ALLOWED=1
fi

# 如果空间允许，询问用户是否保留数据
if [ "$KEEP_DATA_ALLOWED" -eq 1 ]; then
    # 默认为 Y (保留数据)
    read -p "您想在升级时保留配置数据吗？(Y/n): " confirm_keep_data
    # 只有当用户明确输入 n 或 N 时才不保留数据
    if [[ "$confirm_keep_data" =~ ^[Nn]$ ]]; then
        echo "信息：用户选择不保留配置数据进行升级。"
        SYSUPGRADE_ARGS="-n"
    else
        echo "信息：将尝试保留配置数据进行升级。"
        SYSUPGRADE_ARGS="" # 明确设置为空，表示保留数据
    fi
# 如果空间不允许，SYSUPGRADE_ARGS 已经被设为 "-n"
fi

# --- 8. 执行升级 ---
# 设置最终的提示信息，告知用户配置是否保留
UPGRADE_INFO="将使用以下 *解压后* 的固件文件进行升级：\n$IMAGE_PATH_IMG\n"
if [ "$SYSUPGRADE_ARGS" == "-n" ]; then
    UPGRADE_INFO="${UPGRADE_INFO}\n注意：升级将不会保留现有的配置数据！(使用 -n 选项)\n"
else
    UPGRADE_INFO="${UPGRADE_INFO}\n注意：升级将尝试保留现有的配置数据。\n"
fi

echo "---------------------------------------------------------------------"
echo -e "警告：即将开始系统升级！" # 使用 -e 来解释 \n 换行符
echo "      假定 'sysupgrade' 仍然是适用于此系统的升级命令。"
echo "      (如果你的系统基于 apk 且升级方式已改变，请勿继续！)"
echo -e "$UPGRADE_INFO" # 打印包含配置保留状态的升级信息
echo "警告：本次升级未进行文件完整性校验！"
echo "升级过程中，请务必保持设备通电，不要中断操作！"
# 只有在尝试保留配置时才强烈建议备份（不保留配置则无需此建议）
if [ -z "$SYSUPGRADE_ARGS" ]; then
    echo "建议提前备份重要数据。"
fi
echo "---------------------------------------------------------------------"
# 最终确认
read -p "确认要开始执行 sysupgrade 升级吗？ (y/N): " confirm_upgrade

if [[ "$confirm_upgrade" =~ ^[Yy]$ ]]; then
    echo "信息：正在执行 sysupgrade 命令 (参数: '$SYSUPGRADE_ARGS')..."
    # 使用解压后的文件和确定的参数进行升级
    sysupgrade $SYSUPGRADE_ARGS "$IMAGE_PATH_IMG"

    # 如果 sysupgrade 成功，系统通常会自动重启
    echo "信息：sysupgrade 命令已执行。如果成功，系统将会重启。"
    exit 0
else
    echo "操作已取消。解压后的固件文件保留在 '$IMAGE_PATH_IMG'，您可以手动升级或删除它。"
    # trap 会自动清理
    exit 0
fi

exit 0 # 备用退出点