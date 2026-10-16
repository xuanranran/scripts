#!/bin/bash

# Allow the documented `sh update_openwrt.sh` invocation to enter Bash.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo "错误：请先安装 Bash，再运行此脚本。" >&2
    exit 1
fi

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
CHECKSUM_FILENAME="sha256sums"                                             # 校验和文件名 (无 .txt 后缀)
TMP_DIR="/tmp"                                                             # 临时文件目录
IMAGE_PATH_GZ="$TMP_DIR/$IMAGE_FILENAME_GZ"                                # 压缩固件的完整路径
IMAGE_PATH_IMG="$TMP_DIR/$IMAGE_FILENAME_IMG"                              # 解压后固件的完整路径
CHECKSUM_PATH="$TMP_DIR/$CHECKSUM_FILENAME"                                # 校验和文件的完整路径
THRESHOLD_KIB=614400                                                       # 保留数据的空间阈值 (600 MiB in KiB)
MEM_THRESHOLD_KIB=1048576                                                  # 运行脚本的最低内存阈值 (1 GiB = 1024*1024 KiB)

# GitHub 访问方式配置（将在用户选择后设置）
GITHUB_PROXY=""  # GitHub 代理前缀

# 两个平台脚本保持独立，以下通用函数应同步维护。
read_input() {
    # EOF 不应当被当成回车，从而意外接受升级默认值。
    if ! IFS= read -r -p "$1" "$2"; then
        printf '\n输入已关闭，操作中止。\n' >&2
        exit 1
    fi
}

download_file() {
    local url="$1" destination="$2" timeout="${3:-1800}" show_progress="${4:-0}"
    local partial="${destination}.part" attempt
    local -a curl_options=(-fsSL) wget_options=(-q)
    # 固件使用原生进度表显示进度、速度和剩余时间；版本信息和校验文件保持安静。
    if [[ "$show_progress" == 1 ]]; then
        curl_options=(-fL)
        wget_options=()
    fi
    # 先写入临时文件，避免失败的下载被当成完整文件使用。
    if command -v curl >/dev/null 2>&1; then
        if curl "${curl_options[@]}" --connect-timeout 15 --max-time "$timeout" --retry 2 \
            -o "$partial" "$url"; then
            mv -f -- "$partial" "$destination"
            return $?
        fi
    fi
    if command -v wget >/dev/null 2>&1; then
        for attempt in 1 2 3; do
            ((attempt == 1)) || printf '正在重试下载（%s/3）...\n' "$attempt" >&2
            if wget "${wget_options[@]}" -T 30 -O "$partial" "$url"; then
                mv -f -- "$partial" "$destination"
                return $?
            fi
        done
    fi
    rm -f -- "$partial"
    printf '下载失败：%s\n' "$url" >&2
    return 1
}

fetch_release_json() {
    local url="$1"
    download_file "$url" "$TMP_DIR/release-api.json" 60 || return 1
    # 同时拒绝 HTML、空响应和非 JSON 响应。
    jq -e 'type == "object" or type == "array"' "$TMP_DIR/release-api.json" >/dev/null || {
        printf 'GitHub API 返回了无效数据。\n' >&2
        return 1
    }
    cat "$TMP_DIR/release-api.json"
}

select_release() {
    local latest_info history_info choices count raw_count choice index
    local page=1 page_size=10 last_page=0 tag available
    if ! latest_info=$(fetch_release_json "https://api.github.com/repos/$REPO/releases/latest"); then
        printf '无法获取最新版本信息，请检查网络后重试。\n' >&2
        return 1
    fi
    if ! jq -e '(.tag_name | type == "string" and length > 0) and
        (.assets | type == "array")' <<< "$latest_info" >/dev/null; then
        printf '无法读取 Release：%s\n' "$(jq -r '.message // "缺少版本标签或附件列表"' <<< "$latest_info")" >&2
        return 1
    fi
    printf '\n最新版本：%s\n' "$(jq -r '.tag_name' <<< "$latest_info")"
    while true; do
        read_input '选择版本：0/回车 = 最新版本，h = 历史版本，q = 取消：' choice
        case "$choice" in
            ''|0) RELEASE_INFO="$latest_info"; break ;;
            h|H) break ;;
            q|Q) echo '操作已取消。'; exit 0 ;;
            *) echo '请输入 0、h 或 q。' ;;
        esac
    done
    if [[ "$choice" == h || "$choice" == H ]]; then
        while true; do
            if ! history_info=$(fetch_release_json "https://api.github.com/repos/$REPO/releases?per_page=$page_size&page=$page"); then
                printf '无法获取历史版本列表。\n' >&2
                return 1
            fi
            if ! jq -e 'type == "array"' <<< "$history_info" >/dev/null; then
                printf '无法读取历史版本：%s\n' "$(jq -r '.message // "无效的版本列表"' <<< "$history_info")" >&2
                return 1
            fi
            raw_count=$(jq 'length' <<< "$history_info")
            choices=$(jq '[.[] | select(.draft != true and .prerelease != true)
                | select((.tag_name | type) == "string" and (.assets | type) == "array")]' <<< "$history_info")
            count=$(jq 'length' <<< "$choices")
            printf '\n历史版本（第 %s 页）：\n' "$page"
            # 一次 jq 调用生成整页列表，避免逐个版本重复解析 JSON。
            while IFS=$'\t' read -r index tag available; do
                if [[ "$available" == true ]]; then
                    printf '  %2d) %s\n' "$index" "$tag"
                else
                    printf '  %2d) %s（无当前型号/类型固件，不可选）\n' "$index" "$tag"
                fi
            done < <(jq -r --arg name "$IMAGE_FILENAME_GZ" '
                to_entries[] | [(.key + 1), .value.tag_name,
                    any(.value.assets[]; .name == $name)] | @tsv' <<< "$choices")
            ((count > 0)) || echo '  本页没有可显示的正式版本。'
            ((raw_count < page_size)) && last_page=1 || last_page=0
            while true; do
                read_input '输入编号；n = 下一页，p = 上一页，0/回车 = 最新版本，q = 取消：' choice
                case "$choice" in
                    ''|0) RELEASE_INFO="$latest_info"; break 2 ;;
                    n|N)
                        if ((last_page)); then echo '已经是最后一页。'; else page=$((page+1)); break; fi ;;
                    p|P)
                        if ((page == 1)); then echo '已经是第一页。'; else page=$((page-1)); break; fi ;;
                    q|Q) echo '操作已取消。'; exit 0 ;;
                    *)
                        if [[ "$choice" =~ ^[1-9][0-9]?$ ]] && ((10#$choice <= count)); then
                            index=$((10#$choice-1))
                            if jq -e --argjson index "$index" --arg name "$IMAGE_FILENAME_GZ" \
                                'any(.[$index].assets[]; .name == $name)' <<< "$choices" >/dev/null; then
                                RELEASE_INFO=$(jq -c --argjson index "$index" '.[$index]' <<< "$choices")
                                break 2
                            fi
                            echo '该版本没有当前型号/类型的固件，请选择其他版本。'
                        else
                            echo '无效的版本编号，请重新选择。'
                        fi ;;
                esac
            done
        done
    fi
    RELEASE_TAG=$(jq -r '.tag_name' <<< "$RELEASE_INFO")
    printf '已选择版本：%s\n' "$RELEASE_TAG"
}

get_expected_checksum() {
    # 精确匹配文件名，兼容 sha256sum 的文本/二进制标记和 ./ 前缀。
    awk -v name="$IMAGE_FILENAME_GZ" '
        { filename=$2; sub(/\r$/, "", filename); sub(/^\*/, "", filename); sub(/^\.\//, "", filename) }
        filename == name { hash=$1; matches++ }
        END {
            if (matches == 1 && length(hash) == 64 && hash !~ /[^0-9a-fA-F]/) print tolower(hash)
            else exit 1
        }' "$CHECKSUM_PATH"
}

check_dependencies() {
    local cmd package manager
    local -a missing=() required=(jq gunzip awk sha256sum lsblk)
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        required+=(wget)
    fi
    for cmd in "${required[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 && continue
        case "$cmd" in
            gunzip) package=gzip ;;
            sha256sum) package=coreutils-sha256sum ;;
            wget) package=wget-ssl ;;
            *) package="$cmd" ;;
        esac
        missing+=("$package")
    done
    PKG_MANAGER='无需安装依赖'
    if ((${#missing[@]})); then
        if command -v opkg >/dev/null 2>&1; then manager=opkg
        elif command -v apk >/dev/null 2>&1; then manager=apk
        else echo "错误：缺少依赖 ${missing[*]}，且未找到 opkg/apk。" >&2; return 1
        fi
        PKG_MANAGER="$manager"
        "$manager" update || echo '警告：软件包列表更新失败，仍尝试安装。' >&2
        if [[ "$manager" == opkg ]]; then
            "$manager" install "${missing[@]}" || return 1
        else
            "$manager" add "${missing[@]}" || return 1
        fi
    fi
    for cmd in "${required[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || {
            printf '错误：仍缺少命令 %s。\n' "$cmd" >&2
            return 1
        }
    done
    UBUS_PRESENT=0
    if command -v ubus >/dev/null 2>&1; then UBUS_PRESENT=1; fi
    required_cmds_list="${required[*]}"
}

# --- 选择 GitHub 访问方式 ---
select_github_access() {
    echo
    echo -e "${C_CYAN}╔═══════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}                 ${C_B_YELLOW}[#] GitHub 访问方式选择${C_RESET}                    ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚═══════════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo
    echo -e "${C_CYAN}┌───────────────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET} ${C_B_BLUE}选择下载方式${C_RESET}                                                      ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}├───────────────────────────────────────────────────────────────────────┤${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}                                                                       ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}  ${C_GREEN}1)${C_RESET} ${C_B_GREEN}ghfast.top 镜像加速${C_RESET} ${C_YELLOW}(推荐)${C_RESET}                               ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}     ${C_CYAN}•${C_RESET} 适合网络受限环境                                           ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}     ${C_CYAN}•${C_RESET} 下载速度更快                                               ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}                                                                       ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}  ${C_BLUE}2)${C_RESET} GitHub 官方直连                                              ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}     ${C_CYAN}•${C_RESET} 需要稳定的国际网络连接                                     ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}     ${C_CYAN}•${C_RESET} 直接从官方服务器下载                                       ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}│${C_RESET}                                                                       ${C_CYAN}│${C_RESET}"
    echo -e "${C_CYAN}└───────────────────────────────────────────────────────────────────────┘${C_RESET}"
    echo
    read_input "$(echo -e "${C_YELLOW}❓ 请选择访问方式 [1-2] (默认: ${C_B_GREEN}1${C_RESET}${C_YELLOW}): ${C_RESET}")" github_choice
    github_choice=${github_choice:-1}
    
    echo
    case "$github_choice" in
        1)
            echo -e "${C_B_GREEN}✓ 已选择：${C_RESET}ghfast.top 镜像加速"
            GITHUB_PROXY="https://ghfast.top/"
            ;;
        2)
            echo -e "${C_B_GREEN}✓ 已选择：${C_RESET}GitHub 官方直连"
            GITHUB_PROXY=""
            ;;
        *)
            echo -e "${C_YELLOW}⚠ 无效选项，使用默认方式：${C_RESET}GitHub 官方直连"
            GITHUB_PROXY=""
            ;;
    esac
    echo
}

# --- 退出脚本时清理本次任务的临时文件 ---
cleanup() {
    local file
    for file in "${IMAGE_PATH_GZ:-}" "${CHECKSUM_PATH:-}"; do
        if [[ -n "$file" ]]; then rm -f -- "$file" "$file.part"; fi
    done
    rm -f -- "$TMP_DIR/release-api.json" "$TMP_DIR/release-api.json.part"
    # 保留已解压的镜像，延续取消后可手动升级的行为。
    rmdir -- "$TMP_DIR" 2>/dev/null || true
}

if [[ $(id -u) != 0 ]]; then
    echo '错误：请以 root 用户运行升级脚本。' >&2
    exit 1
fi

# 每次运行使用独立目录，不删除 /tmp 中其他任务的镜像或脚本。
TMP_DIR=$(mktemp -d /tmp/openwrt-upgrade.XXXXXX) || exit 1
if [[ -n ${IMAGE_FILENAME_GZ:-} ]]; then
    IMAGE_PATH_GZ="$TMP_DIR/$IMAGE_FILENAME_GZ"
    IMAGE_PATH_IMG="$TMP_DIR/$IMAGE_FILENAME_IMG"
    CHECKSUM_PATH="$TMP_DIR/$CHECKSUM_FILENAME"
fi
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "信息：本次任务的临时目录为 $TMP_DIR"

echo
echo -e "${C_BLUE}=====================================================================${C_RESET}"
echo -e "${C_BLUE} OpenWRT/ImmortalWrt 自动升级脚本 ${C_RESET}"
echo -e "${C_BLUE}=====================================================================${C_RESET}"
echo

# --- 1. 检查并尝试安装依赖项 ---
echo -e "${C_BLUE}--- 步骤 1: 检查并尝试安装依赖项 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}检查所需工具 (curl/wget, jq, gunzip, awk, sha256sum, lsblk)..."

check_dependencies || exit 1

# 显示依赖项检查总结表格
echo
echo -e "${C_CYAN}┌──────────────────────────┬────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_CYAN}│${C_RESET} ${C_B_BLUE}依赖项检查总结${C_RESET}           ${C_CYAN}│${C_RESET} ${C_B_BLUE}状态${C_RESET}                                   ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}╞══════════════════════════╪════════════════════════════════════════════╡${C_RESET}"
printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "包管理器" "$PKG_MANAGER"
echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "必需命令" "已找到所有依赖 ($required_cmds_list)"
echo -e "${C_CYAN}└──────────────────────────┴────────────────────────────────────────────┘${C_RESET}"
echo -e "${C_BLUE}--- 步骤 1 完成 ---${C_RESET}"
echo

# 启用严格错误检查
set -e

# --- 2. 显示系统和磁盘信息 ---
echo -e "${C_BLUE}--- 步骤 2: 显示系统信息并检查内存 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在收集当前系统信息..."
echo

# --- 内存检查 (必须 >= 1GiB) ---
echo -e "${C_CYAN}>> 内存检查:${C_RESET}"
mem_total_kib=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')

if [ -z "$mem_total_kib" ]; then
    echo -e "  ${C_YELLOW}警告：无法读取总内存大小，跳过内存检查。${C_RESET}"
elif [ "$mem_total_kib" -lt "$MEM_THRESHOLD_KIB" ]; then
    mem_total_mib=$(awk -v total_kib="$mem_total_kib" 'BEGIN { printf "%.0f", total_kib/1024 }')
    echo -e "  ${C_B_RED}错误：系统总内存 (${mem_total_mib} MiB) 低于运行此脚本所需的最低要求 (1024 MiB)。${C_RESET}" >&2
    echo -e "        为避免下载或解压失败，脚本将退出。" >&2
    exit 1
else
    mem_total_mib=$(awk -v total_kib="$mem_total_kib" 'BEGIN { printf "%.0f", total_kib/1024 }')
    echo -e "  ${C_GREEN}内存检查通过 (总计: ${mem_total_mib} MiB)。${C_RESET}"
fi
echo

# --- 显示简化内存信息 ---
echo -e "${C_CYAN}>> 内存信息 (当前):${C_RESET}"
mem_avail_kib=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')

if [ -n "$mem_total_kib" ]; then
    if [ -n "$mem_avail_kib" ]; then
        awk -v total_kib="$mem_total_kib" -v avail_kib="$mem_avail_kib" 'BEGIN { printf "  总计: %.0f MiB / 可用: %.0f MiB\n", total_kib/1024, avail_kib/1024 }'
    else
         awk -v total_kib="$mem_total_kib" 'BEGIN { printf "  总计: %.0f MiB\n", total_kib/1024 }'
         echo -e "  ${C_YELLOW}(无法获取可用内存信息)${C_RESET}"
    fi
else
    echo -e "  ${C_YELLOW}无法从 /proc/meminfo 获取内存信息。${C_RESET}"
fi
echo

# --- 其他系统信息 ---
echo -e "${C_CYAN}>> 设备型号/主板信息:${C_RESET}"
model_info_found=0
if [ $UBUS_PRESENT -eq 1 ]; then
    ubus_output=$(ubus call system board 2>/dev/null);
    if [ -n "$ubus_output" ]; then
        model=$(echo "$ubus_output" | jq -r '.model // empty'); board=$(echo "$ubus_output" | jq -r '.board_name // empty');
        if [ -n "$model" ] || [ -n "$board" ]; then
             echo "  来源: ubus"; [ -n "$model" ] && echo "    型号: $model"; [ -n "$board" ] && echo "    主板: $board"; model_info_found=1;
        else echo -e "  ${C_YELLOW}(ubus 未返回有效型号/主板信息)${C_RESET}"; fi
    else echo -e "  ${C_YELLOW}(ubus 命令执行失败或无输出)${C_RESET}"; fi
fi
if [ $model_info_found -eq 0 ] && [ -f /tmp/sysinfo/model ]; then
    model_sysinfo=$(cat /tmp/sysinfo/model); if [ -n "$model_sysinfo" ]; then echo "  来源: /tmp/sysinfo/model"; echo "    型号: $model_sysinfo"; model_info_found=1; fi
fi
if [ $model_info_found -eq 0 ] && [ -r /proc/device-tree/model ]; then
     model_dt=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0'); if [ -n "$model_dt" ]; then echo "  来源: /proc/device-tree/model"; echo "    型号: $model_dt"; model_info_found=1; fi
fi
if [ $model_info_found -eq 0 ]; then echo -e "  ${C_YELLOW}无法自动确定设备型号或主板名称。${C_RESET}"; fi
echo

# CPU 信息 (简化)
echo -e "${C_CYAN}>> CPU:${C_RESET}"
grep 'model name' /proc/cpuinfo | head -n1 | sed 's/^model name[[:space:]]*: /  /' || echo -e "  ${C_YELLOW}无法获取 CPU 型号。${C_RESET}"
echo

# 磁盘分区和挂载点信息 (lsblk)
echo -e "${C_CYAN}>> 磁盘分区布局 (lsblk):${C_RESET}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | sed 's/^/  /' || echo -e "  ${C_YELLOW}警告：${C_RESET}'lsblk' 命令执行失败或未安装。"
echo

# 文件系统使用情况和类型 (df)
echo -e "${C_CYAN}>> 文件系统使用情况 (df -hT):${C_RESET}"
df -hT | sed 's/^/  /' || echo -e "  ${C_YELLOW}无法获取文件系统使用情况。${C_RESET}"
echo

# 系统信息总结表格
echo
echo -e "${C_CYAN}┌──────────────────────────┬────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_CYAN}│${C_RESET} ${C_B_BLUE}系统信息总结${C_RESET}             ${C_CYAN}│${C_RESET} ${C_B_BLUE}详情${C_RESET}                                   ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}╞══════════════════════════╪════════════════════════════════════════════╡${C_RESET}"

# 内存信息
if [ -n "$mem_total_kib" ]; then
    mem_total_mib=$(awk -v total_kib="$mem_total_kib" 'BEGIN { printf "%.0f MiB", total_kib/1024 }')
    if [ -n "$mem_avail_kib" ]; then
        mem_avail_mib=$(awk -v avail_kib="$mem_avail_kib" 'BEGIN { printf "%.0f MiB", avail_kib/1024 }')
        printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "内存" "总计: $mem_total_mib / 可用: $mem_avail_mib"
    else
        printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "内存" "总计: $mem_total_mib"
    fi
else
    printf "${C_CYAN}│${C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "内存" "无法获取"
fi

echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"

# 设备型号
if [ $model_info_found -eq 1 ]; then
    if [ -n "$model" ]; then
        # 截断过长的型号名
        if [ ${#model} -gt 42 ]; then
            model_display="${model:0:39}..."
        else
            model_display="$model"
        fi
        printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "设备型号" "$model_display"
    elif [ -n "$model_sysinfo" ]; then
        if [ ${#model_sysinfo} -gt 42 ]; then
            model_display="${model_sysinfo:0:39}..."
        else
            model_display="$model_sysinfo"
        fi
        printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "设备型号" "$model_display"
    else
        printf "${C_CYAN}│${C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "设备型号" "未知"
    fi
else
    printf "${C_CYAN}│${C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "设备型号" "无法确定"
fi

echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"

# /tmp 空间
tmp_size=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $2}')
tmp_avail=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$tmp_size" ] && [ -n "$tmp_avail" ]; then
    printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "/tmp 空间" "总计: $tmp_size / 可用: $tmp_avail"
else
    printf "${C_CYAN}│${C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "/tmp 空间" "无法获取"
fi

echo -e "${C_CYAN}└──────────────────────────┴────────────────────────────────────────────┘${C_RESET}"

echo -e "${C_BLUE}--- 步骤 2 完成 ---${C_RESET}"
echo

# 选择 GitHub 访问方式
select_github_access

# 启用严格错误检查
set -e

# --- 3. 选择固件版本 ---
echo -e "${C_BLUE}--- 步骤 3: 选择最新或历史版本 ---${C_RESET}"
select_release || exit 1
echo -e "${C_BLUE}--- 步骤 3 完成 ---${C_RESET}"
echo

# --- 4. 临时增大 /tmp 分区 ---
echo -e "${C_BLUE}--- 步骤 4: 临时增大 /tmp 分区 ---${C_RESET}"
echo
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${C_B_YELLOW}[*] /tmp 分区扩容选项${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  ${C_BLUE}提示：${C_RESET}可以临时将 /tmp 分区扩大到 RAM 的 100%"
echo -e "  ${C_GREEN}• 有助于存储下载和解压的固件文件${C_RESET}"
echo -e "  ${C_YELLOW}• 此更改仅在本次运行期间有效，重启后失效${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "\n${C_BLUE}信息：${C_RESET}/tmp 当前大小:"
df -h /tmp | sed 's/^/  /'
echo
read_input "$(echo -e "${C_YELLOW}❓ 是否临时扩大 /tmp 分区？(Y/n) [默认: ${C_B_GREEN}是${C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_resize_tmp
confirm_resize_tmp=${confirm_resize_tmp:-Y}  # 默认为Y

if [[ "$confirm_resize_tmp" =~ ^[Yy]$ ]]; then
    echo -e "${C_BLUE}信息：${C_RESET}正在尝试将 /tmp 重新挂载为更大内存（RAM 的 100%）..."
    mount -t tmpfs -o remount,size=100% tmpfs /tmp || echo -e "${C_YELLOW}警告：${C_RESET}重新挂载 /tmp 可能失败或不受支持，继续执行..."
    echo -e "${C_BLUE}信息：${C_RESET}/tmp 扩容后大小:"
    df -h /tmp | sed 's/^/  /'
else
    echo -e "${C_YELLOW}信息：${C_RESET}用户选择跳过 /tmp 分区扩容。"
fi
echo -e "${C_BLUE}--- 步骤 4 完成 ---${C_RESET}"
echo

# --- 5. 查找固件和校验文件 URL ---
echo -e "${C_BLUE}--- 步骤 5: 查找文件 URL ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在查找固件 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 和校验文件 '${C_CYAN}${CHECKSUM_FILENAME}${C_RESET}'..."
IMAGE_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$IMAGE_FILENAME_GZ" '.assets[] | select(.name==$NAME) | .browser_download_url')
CHECKSUM_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$CHECKSUM_FILENAME" '.assets[] | select(.name==$NAME) | .browser_download_url')

SKIP_CHECKSUM=0
if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" == "null" ]; then echo -e "${C_B_RED}错误：${C_RESET}在版本 '${C_YELLOW}${RELEASE_TAG}${C_RESET}' 中未找到固件文件 '${C_RED}${IMAGE_FILENAME_GZ}${C_RESET}'。" >&2; exit 1; fi
echo -e "${C_BLUE}信息：${C_RESET}找到固件下载链接: ${C_CYAN}${IMAGE_URL}${C_RESET}"
if [ -z "$CHECKSUM_URL" ] || [ "$CHECKSUM_URL" == "null" ]; then echo -e "${C_YELLOW}警告：${C_RESET}未找到校验文件 '${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}'，将【自动跳过】文件完整性校验。"; SKIP_CHECKSUM=1; else echo -e "${C_BLUE}信息：${C_RESET}找到校验文件下载链接: ${C_CYAN}${CHECKSUM_URL}${C_RESET}"; fi
echo -e "${C_BLUE}--- 步骤 5 完成 ---${C_RESET}"
echo

# --- 6. 下载前确认 ---
echo -e "${C_BLUE}--- 步骤 6: 下载前确认 ---${C_RESET}"
echo
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${C_B_YELLOW}[↓] 固件下载确认${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo
echo -e "${C_CYAN}┌──────────────────────────┬────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_CYAN}│${C_RESET} ${C_B_BLUE}项目${C_RESET}                     ${C_CYAN}│${C_RESET} ${C_B_BLUE}详情${C_RESET}                                   ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}╞══════════════════════════╪════════════════════════════════════════════╡${C_RESET}"
printf "${C_CYAN}│${C_RESET} ${C_CYAN}[#]${C_RESET} %-20s ${C_CYAN}│${C_RESET} " "版本标签"
echo -e "${C_GREEN}${RELEASE_TAG}${C_RESET}$(printf '%*s' $((42 - ${#RELEASE_TAG})) '') ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
printf "${C_CYAN}│${C_RESET} ${C_CYAN}[↓]${C_RESET} %-20s ${C_CYAN}│${C_RESET} %-42s ${C_CYAN}│${C_RESET}\\n" "固件文件" "$(basename "$IMAGE_FILENAME_GZ")"
echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
if [ $SKIP_CHECKSUM -eq 1 ]; then 
    printf "${C_CYAN}│${C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}│${C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}│${C_RESET}\\n" "校验文件" "未找到"
else 
    printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET} %-42s ${C_CYAN}│${C_RESET}\\n" "校验文件" "$(basename "$CHECKSUM_FILENAME")"
fi
echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
printf "${C_CYAN}│${C_RESET} ${C_CYAN}[>]${C_RESET} %-20s ${C_CYAN}│${C_RESET} %-42s ${C_CYAN}│${C_RESET}\\n" "保存路径" "$TMP_DIR"
echo -e "${C_CYAN}└──────────────────────────┴────────────────────────────────────────────┘${C_RESET}"
echo
read_input "$(echo -e "\n${C_YELLOW}❓ 是否开始下载此固件文件？(Y/n) [默认: ${C_B_GREEN}是${C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_download
confirm_download=${confirm_download:-Y}  # 默认为Y
if [[ ! "$confirm_download" =~ ^[Yy]$ ]]; then echo -e "${C_YELLOW}操作已取消，未下载固件。${C_RESET}"; exit 0; fi
echo

# --- 7. 下载文件 ---
echo -e "${C_BLUE}--- 步骤 7: 下载文件 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在下载压缩固件 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 到 '${C_CYAN}${IMAGE_PATH_GZ}${C_RESET}' ..."
download_file "${GITHUB_PROXY}${IMAGE_URL}" "$IMAGE_PATH_GZ" 1800 1 || exit 1
echo -e "${C_B_GREEN}信息：${C_RESET}压缩固件下载完成。"

# 下载校验文件
if [ $SKIP_CHECKSUM -eq 0 ]; then
    echo -e "${C_BLUE}信息：${C_RESET}正在下载校验文件 '${C_CYAN}${CHECKSUM_FILENAME}${C_RESET}' 到 '${C_CYAN}${CHECKSUM_PATH}${C_RESET}' ..."
    dl_status=0
    download_file "${GITHUB_PROXY}${CHECKSUM_URL}" "$CHECKSUM_PATH" 120 || dl_status=$?
    if [ $dl_status -ne 0 ]; then
        echo -e "${C_YELLOW}警告：${C_RESET}下载校验文件 '${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}' 失败，将跳过文件完整性校验。"
        rm -f "$CHECKSUM_PATH"; SKIP_CHECKSUM=1;
    else echo -e "${C_B_GREEN}信息：${C_RESET}校验文件下载完成。"; fi
fi
echo -e "${C_BLUE}--- 步骤 7 完成 ---${C_RESET}"
echo

# --- 8. 校验固件完整性 (询问是否执行) ---
echo -e "${C_BLUE}--- 步骤 8: 校验固件完整性 (SHA256) ---${C_RESET}"
if [ $SKIP_CHECKSUM -eq 1 ]; then
    echo -e "${C_YELLOW}信息：由于之前步骤未能找到或下载校验文件，跳过文件完整性校验。${C_RESET}"
else
    echo
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_B_YELLOW}[#] 文件完整性校验选项${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "  ${C_BLUE}提示：${C_RESET}执行 SHA256 校验可以确保固件文件完整性"
    echo -e "  ${C_GREEN}• 推荐执行校验以确保固件未被损坏或篡改${C_RESET}"
    echo -e "  ${C_YELLOW}• 跳过校验可能导致升级失败或系统损坏${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    read_input "$(echo -e "\n${C_YELLOW}❓ 是否执行 SHA256 固件完整性校验？(Y/n) [默认: ${C_B_GREEN}是${C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_run_checksum
    confirm_run_checksum=${confirm_run_checksum:-Y}  # 默认为Y

    if [[ "$confirm_run_checksum" =~ ^[Nn]$ ]]; then
        echo -e "${C_YELLOW}信息：用户选择跳过文件完整性校验。${C_RESET}"
        SKIP_CHECKSUM=1
    else
        echo -e "${C_BLUE}信息：${C_RESET}正在校验文件 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 的 SHA256 哈希值..."
        EXPECTED_SUM=$(get_expected_checksum) || EXPECTED_SUM=""
        if [ -z "$EXPECTED_SUM" ]; then
             echo -e "${C_YELLOW}警告：${C_RESET}在校验文件 '${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}' 中未能找到固件 '${C_YELLOW}${IMAGE_FILENAME_GZ}${C_RESET}' 的校验信息。跳过校验。"
             SKIP_CHECKSUM=1
        else
            CALCULATED_SUM=$(sha256sum "$IMAGE_PATH_GZ" | awk '{print $1}')
            echo
            echo -e "${C_CYAN}┌──────────────────────────┬────────────────────────────────────────────┐${C_RESET}"
            echo -e "${C_CYAN}│${C_RESET} ${C_B_BLUE}校验项${C_RESET}                   ${C_CYAN}│${C_RESET} ${C_B_BLUE}SHA256 哈希值${C_RESET}                          ${C_CYAN}│${C_RESET}"
            echo -e "${C_CYAN}╞══════════════════════════╪════════════════════════════════════════════╡${C_RESET}"
            printf "${C_CYAN}│${C_RESET} ${C_CYAN}[>]${C_RESET} %-20s ${C_CYAN}│${C_RESET} %-42s ${C_CYAN}│${C_RESET}\\n" "期望值" "$EXPECTED_SUM"
            echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
            printf "${C_CYAN}│${C_RESET} ${C_CYAN}[>]${C_RESET} %-20s ${C_CYAN}│${C_RESET} %-42s ${C_CYAN}│${C_RESET}\\n" "计算值" "$CALCULATED_SUM"
            echo -e "${C_CYAN}└──────────────────────────┴────────────────────────────────────────────┘${C_RESET}"
            echo
            if [ "$EXPECTED_SUM" == "$CALCULATED_SUM" ]; then
                echo -e "${C_B_GREEN}✅ 校验成功！文件完整。${C_RESET}"
            else
                echo; echo -e "${C_B_RED}❌ 错误：SHA256 校验和不匹配！文件可能已损坏或不完整。${C_RESET}"; echo
                confirm_checksum_fail=""
                read_input "$(echo -e "${C_B_YELLOW}❓ 警告：文件校验失败！是否仍要继续升级？(y/N): ${C_RESET}")" confirm_checksum_fail
                if [[ ! "$confirm_checksum_fail" =~ ^[Yy]$ ]]; then echo -e "${C_YELLOW}操作中止。${C_RESET}"; exit 1; fi
                echo -e "${C_YELLOW}信息：用户选择忽略校验失败并继续。${C_RESET}"
                SKIP_CHECKSUM=1
            fi
        fi
    fi
fi
rm -f "$CHECKSUM_PATH" # 清理校验文件
echo -e "${C_BLUE}--- 步骤 8 完成 ---${C_RESET}"
echo

# --- 9. 解压固件 ---
echo -e "${C_BLUE}--- 步骤 9: 解压固件 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在解压固件 '${C_CYAN}${IMAGE_PATH_GZ}${C_RESET}' -> '${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}' ..."
gunzip "$IMAGE_PATH_GZ"
if [ ! -f "$IMAGE_PATH_IMG" ]; then echo -e "${C_B_RED}错误：${C_RESET}解压后未找到文件 '${C_RED}${IMAGE_PATH_IMG}${C_RESET}'。" >&2; exit 1; fi
echo -e "${C_B_GREEN}信息：${C_RESET}固件解压完成。解压后文件: '${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}'"
ls -lh "$IMAGE_PATH_IMG"
echo -e "${C_BLUE}--- 步骤 9 完成 ---${C_RESET}"
echo

# --- 10. 检查空间并确定升级选项 ---
echo -e "${C_BLUE}--- 步骤 10: 检查空间并确定升级选项 ---${C_RESET}"
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
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_B_YELLOW}[+] 配置数据保留选项${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "  ${C_BLUE}提示：${C_RESET}您可以选择在升级时保留或清除配置数据"
    echo -e "  ${C_GREEN}• 保留配置${C_RESET} - 升级后保留当前系统设置"
    echo -e "  ${C_YELLOW}• 清除配置${C_RESET} - 升级后恢复为出厂设置"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    read_input "$(echo -e "\n${C_YELLOW}❓ 是否保留配置数据？(Y/n) [默认: ${C_B_GREEN}是${C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_keep_data
    confirm_keep_data=${confirm_keep_data:-Y}  # 默认为Y
    if [[ "$confirm_keep_data" =~ ^[Nn]$ ]]; then
        echo -e "${C_BLUE}信息：${C_RESET}用户选择【${C_YELLOW}不保留${C_RESET}】配置数据进行升级。"
        SYSUPGRADE_ARGS="-n"
    else
        echo -e "${C_BLUE}信息：${C_RESET}将尝试【${C_GREEN}保留${C_RESET}】配置数据进行升级。"
        SYSUPGRADE_ARGS=""
    fi
fi
echo -e "${C_BLUE}--- 步骤 10 完成 ---${C_RESET}"
echo

# --- 11. 询问可选参数并最终确认 ---
echo -e "${C_BLUE}--- 步骤 11: 配置可选参数并最终确认 ---${C_RESET}"
# 这些变量在后面构建表格时使用，此处不再需要预先构建UPGRADE_INFO字符串

# --- 询问是否强制升级 (-F) ---
FORCE_FLAG=""
echo -e "\n${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${C_B_RED}[!] 强制升级选项 (-F)${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  ${C_YELLOW}警告：${C_RESET}'-F' 选项会跳过固件兼容性检查"
echo -e "  ${C_RED}• 使用不兼容的固件可能导致设备变砖！${C_RESET}"
echo -e "  ${C_YELLOW}• 仅在您完全确定固件正确且了解风险时才使用${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
read_input "$(echo -e "\n${C_B_YELLOW}❓ 是否使用强制升级 '-F' 选项？(y/N) [默认: ${C_B_GREEN}否${C_RESET}${C_B_YELLOW}]: ${C_RESET}")" confirm_force
confirm_force=${confirm_force:-N}  # 默认为N
FORCE_FLAG_INFO=""
if [[ "$confirm_force" =~ ^[Yy]$ ]]; then
    echo -e "${C_BLUE}信息：${C_RESET}用户选择【${C_B_RED}使用${C_RESET}】强制 '-F' 选项！"
    FORCE_FLAG="-F"; FORCE_FLAG_INFO="${C_B_RED}是 (-F)${C_RESET}";
else
    echo -e "${C_BLUE}信息：${C_RESET}本次升级将【${C_GREEN}不使用${C_RESET}】强制 '-F' 选项。"
    FORCE_FLAG=""; FORCE_FLAG_INFO="${C_GREEN}否${C_RESET}";
fi

# --- 询问是否详细输出 (-v) ---
VERBOSE_FLAG=""
echo
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${C_B_YELLOW}[i] 详细日志选项 (-v)${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  ${C_BLUE}提示：${C_RESET}启用详细输出可查看升级过程的详细信息"
echo -e "  ${C_YELLOW}• 一般用户建议使用默认模式${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
read_input "$(echo -e "\n${C_YELLOW}❓ 是否启用详细输出模式？(y/N) [默认: ${C_B_GREEN}否${C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_verbose
confirm_verbose=${confirm_verbose:-N}  # 默认为N
VERBOSE_FLAG_INFO=""
if [[ "$confirm_verbose" =~ ^[Yy]$ ]]; then
    echo -e "${C_BLUE}信息：${C_RESET}用户选择【${C_GREEN}启用${C_RESET}】详细输出模式 (-v)。"
    VERBOSE_FLAG="-v"; VERBOSE_FLAG_INFO="${C_GREEN}是 (-v)${C_RESET}";
else
    echo -e "${C_BLUE}信息：${C_RESET}本次升级将【${C_YELLOW}不启用${C_RESET}】详细输出模式。"
    VERBOSE_FLAG=""; VERBOSE_FLAG_INFO="${C_YELLOW}否${C_RESET}";
fi

# --- 最终确认与执行 ---
echo
echo -e "${C_CYAN}╔═════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_CYAN}║${C_RESET}                   ${C_B_YELLOW}[=] 升级前最终确认${C_RESET}                      ${C_CYAN}║${C_RESET}"
echo -e "${C_CYAN}╚═════════════════════════════════════════════════════════════════════╝${C_RESET}"
echo

# 构建表格内容
DATA_MODE_INFO=""
if [ "$SYSUPGRADE_ARGS" == "-n" ]; then
    DATA_MODE_INFO="${C_YELLOW}不保留配置 (-n)${C_RESET}"
else
    DATA_MODE_INFO="${C_GREEN}保留配置${C_RESET}"
fi

CHECKSUM_INFO=""
if [ $SKIP_CHECKSUM -eq 1 ]; then
    CHECKSUM_INFO="${C_YELLOW}跳过/未执行${C_RESET}"
else
    CHECKSUM_INFO="${C_GREEN}SHA256 已验证${C_RESET}"
fi

echo -e "${C_CYAN}┌──────────────────────────┬────────────────────────────────────────────┐${C_RESET}"
echo -e "${C_CYAN}│${C_RESET} ${C_B_BLUE}项目${C_RESET}                     ${C_CYAN}│${C_RESET} ${C_B_BLUE}详情${C_RESET}                                   ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}╞══════════════════════════╪════════════════════════════════════════════╡${C_RESET}"
printf "${C_CYAN}│${C_RESET} ${C_CYAN}[>]${C_RESET} %-20s ${C_CYAN}│${C_RESET} %-42s ${C_CYAN}│${C_RESET}\\n" "固件文件" "$(basename "$IMAGE_PATH_IMG")"
echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
printf "${C_CYAN}│${C_RESET} ${C_CYAN}[#]${C_RESET} %-20s ${C_CYAN}│${C_RESET} " "版本标签"
echo -e "${C_GREEN}${RELEASE_TAG}${C_RESET}$(printf '%*s' $((42 - ${#RELEASE_TAG})) '') ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
# 配置数据行带图标
if [ "$SYSUPGRADE_ARGS" == "-n" ]; then
    printf "${C_CYAN}│${C_RESET} ${C_YELLOW}[×]${C_RESET} %-20s ${C_CYAN}│${C_RESET} " "配置数据"
else
    printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET}" "配置数据"
fi
echo -e "${DATA_MODE_INFO}$(printf '%*s' $((42 - $(echo -e "${DATA_MODE_INFO}" | sed 's/\x1b\[[0-9;]*m//g' | wc -c) + 1)) '') ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
# 强制升级行
if [[ "$FORCE_FLAG_INFO" == *"是"* ]]; then
    printf "${C_CYAN}│${C_RESET} ${C_B_RED}[!]${C_RESET} %-20s ${C_CYAN}│${C_RESET} " "强制升级 (-F)"
else
    printf "${C_CYAN}│${C_RESET} ${C_GREEN}[✓]${C_RESET} %-20s ${C_CYAN}│${C_RESET} " "强制升级 (-F)"
fi
echo -e "${FORCE_FLAG_INFO}$(printf '%*s' $((42 - $(echo -e "${FORCE_FLAG_INFO}" | sed 's/\x1b\[[0-9;]*m//g' | wc -c) + 1)) '') ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
# 详细输出行
if [[ "$VERBOSE_FLAG_INFO" == *"是"* ]]; then
    printf "${C_CYAN}│${C_RESET} ${C_GREEN}[i]${C_RESET} %-20s ${C_CYAN}│${C_RESET} " "详细输出 (-v)"
else
    printf "${C_CYAN}│${C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}│${C_RESET} " "详细输出 (-v)"
fi
echo -e "${VERBOSE_FLAG_INFO}$(printf '%*s' $((42 - $(echo -e "${VERBOSE_FLAG_INFO}" | sed 's/\x1b\[[0-9;]*m//g' | wc -c) + 1)) '') ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}├──────────────────────────┼────────────────────────────────────────────┤${C_RESET}"
# 文件校验行
if [ $SKIP_CHECKSUM -eq 1 ]; then
    printf "${C_CYAN}│${C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}│${C_RESET} " "文件校验"
else
    printf "${C_CYAN}│${C_RESET} ${C_GREEN}[√]${C_RESET} %-20s ${C_CYAN}│${C_RESET} " "文件校验"
fi
echo -e "${CHECKSUM_INFO}$(printf '%*s' $((42 - $(echo -e "${CHECKSUM_INFO}" | sed 's/\x1b\[[0-9;]*m//g' | wc -c) + 1)) '') ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}└──────────────────────────┴────────────────────────────────────────────┘${C_RESET}"
echo

if [ -z "$SYSUPGRADE_ARGS" ]; then
    echo -e "${C_YELLOW}[*] 提示：${C_RESET}建议提前备份重要数据"
fi
echo -e "${C_B_RED}[!] 警告：${C_RESET}升级过程中请务必保持设备通电，不要中断操作！"
echo
read_input "$(echo -e "${C_B_GREEN}❓ 确认开始执行 sysupgrade 升级？(Y/n) [默认: ${C_B_GREEN}是${C_RESET}]: ${C_RESET}")" confirm_upgrade
confirm_upgrade=${confirm_upgrade:-Y}  # 默认为Y

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
    
    if [ -n "$FORCE_FLAG" ]; then
        # 如果启用了强制升级，使用 exec 直接替换进程，防止 SSH 断开后的误报错误
        echo -e "${C_B_GREEN}✅ 信息：sysupgrade 命令已启动。SSH 连接即将断开，设备将重启。${C_RESET}"
        echo
        exec sysupgrade ${FORCE_FLAG:+"$FORCE_FLAG"} ${VERBOSE_FLAG:+"$VERBOSE_FLAG"} ${SYSUPGRADE_ARGS:+"$SYSUPGRADE_ARGS"} "$IMAGE_PATH_IMG"
    else
        # 未启用强制升级
        # 先进行模拟测试 (-T) 以检查固件有效性
        echo -e "${C_BLUE}信息：${C_RESET}正在执行固件兼容性预检查 (sysupgrade -T)..."
        
        # 临时禁用 strict error checking
        set +e
        sysupgrade -T ${SYSUPGRADE_ARGS:+"$SYSUPGRADE_ARGS"} "$IMAGE_PATH_IMG" >/dev/null 2>&1
        test_status=$?
        set -e
        
        if [ $test_status -eq 0 ]; then
            # 校验通过
            echo -e "${C_B_GREEN}✅ 信息：固件校验通过。sysupgrade 命令已启动。SSH 连接即将断开，设备将重启。${C_RESET}"
            echo
            # 使用 exec 执行真正的升级
            exec sysupgrade ${VERBOSE_FLAG:+"$VERBOSE_FLAG"} ${SYSUPGRADE_ARGS:+"$SYSUPGRADE_ARGS"} "$IMAGE_PATH_IMG"
        else
            # 校验失败，执行原命令以显示错误并进入错误处理流程
            echo -e "${C_YELLOW}警告：${C_RESET}固件预检查未通过，正在执行常规升级以显示详细错误..."
            set +e
            sysupgrade ${FORCE_FLAG:+"$FORCE_FLAG"} ${VERBOSE_FLAG:+"$VERBOSE_FLAG"} ${SYSUPGRADE_ARGS:+"$SYSUPGRADE_ARGS"} "$IMAGE_PATH_IMG"
            sysupgrade_status=$?
            set -e
        fi

        if [ $sysupgrade_status -eq 0 ]; then
            echo # 换行
            echo -e "${C_B_GREEN}✅ 信息：sysupgrade 命令已执行。如果成功，系统将会重启。${C_RESET}"
            exit 0
        else
            echo
            echo -e "${C_B_RED}❌ 错误：sysupgrade 命令执行失败 (退出码 $sysupgrade_status)。${C_RESET}"
            
            # 如果之前没用过 -F，询问是否尝试强制升级
            if [[ "$FORCE_FLAG" != "-F" ]]; then
                echo -e "${C_YELLOW}分析：升级失败通常是因为固件版本检查不通过 (如 'Image metadata not present' 或 'Image check failed')。${C_RESET}"
                echo -e "${C_YELLOW}      这在跨版本升级或刷写不同固件时很常见。${C_RESET}"
                
                read_input "$(echo -e "\n${C_B_YELLOW}❓ 是否尝试使用强制升级 '-F' 选项重试？(y/N) [默认: ${C_B_GREEN}是${C_RESET}${C_B_YELLOW}]: ${C_RESET}")" retry_force
                retry_force=${retry_force:-Y}
                
                if [[ "$retry_force" =~ ^[Yy]$ ]]; then
                    echo -e "${C_BLUE}信息：${C_RESET}正在尝试使用强制升级选项 (-F) 重试..."
                    FORCE_FLAG="-F"
                    
                    echo -e "${C_B_GREEN}✅ 信息：正在执行强制升级命令。连接即将断开，请等待设备重启...${C_RESET}"
                    echo
                    
                    # 使用 exec 替换当前 shell 进程
                    exec sysupgrade ${FORCE_FLAG:+"$FORCE_FLAG"} ${VERBOSE_FLAG:+"$VERBOSE_FLAG"} ${SYSUPGRADE_ARGS:+"$SYSUPGRADE_ARGS"} "$IMAGE_PATH_IMG"
                else
                    echo -e "${C_YELLOW}信息：用户选择不重试。脚本退出。${C_RESET}"
                    exit 1
                fi
            else
                exit 1
            fi
        fi
    fi
else
    echo # 换行
    echo -e "${C_YELLOW}操作已取消。${C_RESET}解压后的固件文件保留在 '${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}'，您可以手动升级或删除它。"
    exit 0
fi

exit 0 # 备用退出点