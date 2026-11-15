#!/bin/bash

# Allow the documented `sh update_openwrt.sh` invocation to enter Bash.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo "❌ 错误：请先安装 Bash，再运行此脚本。" >&2
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
REPO="xuanranran/OpenWrt_RockChip"                                        # 目标 GitHub 仓库
# 注意：固件文件名将根据机型和Docker选择动态生成
TMP_DIR="/tmp"                                                             # 临时文件目录
WORK_RESERVE_KIB=65536                                                    # 为烧录环境和解压缓冲预留 64 MiB
CONFIG_BACKUP_BYTES=0                                                    # 本次运行只测量一次备份大小
KEEP_IMAGE=0                                                             # 完成压缩流检查后，取消/失败时保留镜像
KEEP_CONFIG=1                                                            # 是否把当前配置迁移到目标介质

# GitHub 访问方式配置（将在用户选择后设置）
GITHUB_PROXY=""  # GitHub 代理前缀

# Docker 版本选择（将在用户选择后设置）
USE_DOCKER=false  # 是否使用 Docker 版本

# 设备型号（将自动检测）
DEVICE_MODEL=""  # 设备型号标识
BOOT_DISK=""     # 当前启动盘，由系统烧录函数识别
BOOT_MEDIUM="未识别"
TARGET_DISK=""
TARGET_CID=""
TARGET_SECTORS=0
TARGET_KIND=""
TARGET_MEDIUM=""
OD_COMMAND=(od)
MEDIA_BOOT_MOUNTED=0

# 动态文件名（将在检测型号和Docker选择后生成）
IMAGE_FILENAME_GZ=""  # 压缩固件的文件名
CHECKSUM_FILENAME=""  # 校验和文件名
IMAGE_PATH_GZ=""  # 压缩固件的完整路径
IMAGE_PATH_IMG="" # 解压固件的完整路径
IMAGE_PATH=""     # 最终用于烧录的压缩镜像
CHECKSUM_PATH=""  # 校验和文件的完整路径

# 两个平台脚本保持独立，以下通用函数应同步维护。
# 独立标题框与留白选项框；不足 60 列时信息汇总改为单列，宽屏样式保持不变。
UI_OPEN=0
UI_TITLE=""
UI_ROWS=()

ui_section() {
    ui_end
    UI_TITLE="$1"
    UI_TITLE_COLOR="${2:-$C_B_YELLOW}"
    UI_HAS_OPTIONS=0
    UI_ROWS=()
    UI_OPEN=1
}

ui_add_row() {
    local label="${2//$'\t'/ }" value="${3//$'\t'/ }"
    label=${label//$'\n'/ }
    value=${value//$'\n'/ }
    UI_ROWS+=("$1"$'\t'"$label"$'\t'"$value")
}

ui_field() {
    ui_add_row field "$1" "$2"
}

ui_option() {
    local hint="${3:-}"
    [[ -z "$hint" ]] || hint="（$hint）"
    UI_HAS_OPTIONS=1
    ui_add_row option "$1" "$2$hint"
}

ui_end() {
    [[ ${UI_OPEN:-0} == 1 ]] || return 0
    local columns="${COLUMNS:-80}" terminal_size
    # SSH 终端未必导出 COLUMNS；可用时读取实际终端宽度。
    if [[ -t 1 ]] && command -v stty >/dev/null 2>&1; then
        terminal_size=$(stty size </dev/tty 2>/dev/null) || terminal_size=""
        if [[ "$terminal_size" =~ ^[0-9]+[[:space:]]+([1-9][0-9]{0,3})$ ]]; then
            columns=${BASH_REMATCH[1]}
        fi
    fi
    [[ "$columns" =~ ^[1-9][0-9]{0,3}$ ]] || columns=80
    ((columns >= 20)) || columns=20
    ((columns <= 100)) || columns=100
    local border title_color reset green blue yellow
    printf -v border '%b' "$C_CYAN"
    printf -v title_color '%b' "${UI_TITLE_COLOR:-$C_B_YELLOW}"
    printf -v reset '%b' "$C_RESET"
    printf -v green '%b' "$C_B_GREEN"
    printf -v blue '%b' "$C_BLUE"
    printf -v yellow '%b' "$C_YELLOW"
    # awk 固定使用字节模式，自行读取 UTF-8；兼容 BusyBox awk 和 GNU awk。
    {
        if ((${#UI_ROWS[@]})); then printf '%s\n' "${UI_ROWS[@]}"; fi
    } | LC_ALL=C UI_TABLE_TITLE="$UI_TITLE" UI_TABLE_MENU="${UI_HAS_OPTIONS:-0}" \
        UI_TABLE_COUNT="${#UI_ROWS[@]}" UI_TABLE_BORDER="$border" UI_TABLE_TITLE_COLOR="$title_color" \
        UI_TABLE_RESET="$reset" UI_TABLE_GREEN="$green" UI_TABLE_BLUE="$blue" UI_TABLE_YELLOW="$yellow" \
        awk -v width="$((columns - 2))" '
        function clean(s) {
            gsub(/\033\[[0-?]*[ -\/]*[@-~]/, "", s)
            gsub(/[[:cntrl:]]/, " ", s)
            return s
        }
        function glyph(s, p,    b, n, i) {
            b = byte[substr(s, p, 1)]; size = 1; code = b
            if (b >= 194 && b <= 223) { size = 2; code = b - 192 }
            else if (b >= 224 && b <= 239) { size = 3; code = b - 224 }
            else if (b >= 240 && b <= 244) { size = 4; code = b - 240 }
            for (i = 1; i < size; i++) code = code * 64 + byte[substr(s, p + i, 1)] - 128
            cells = 1
            if ((code >= 768 && code <= 879) || (code >= 6832 && code <= 6911) ||
                (code >= 7616 && code <= 7679) || (code >= 8400 && code <= 8447) ||
                (code >= 65024 && code <= 65039) || (code >= 65056 && code <= 65071) ||
                (code >= 917760 && code <= 917999) || code == 8205) cells = 0
            else if ((code >= 4352 && code <= 4447) || code == 9001 || code == 9002 ||
                (code >= 11904 && code <= 42191 && code != 12351) ||
                (code >= 44032 && code <= 55203) || (code >= 63744 && code <= 64255) ||
                (code >= 65040 && code <= 65049) || (code >= 65072 && code <= 65135) ||
                (code >= 65281 && code <= 65376) || (code >= 65504 && code <= 65510) ||
                (code >= 127744 && code <= 129791) || (code >= 131072 && code <= 262141)) cells = 2
            return substr(s, p, size)
        }
        function repeat(s, n,    out) {
            out = ""; while (n-- > 0) out = out s
            return out
        }
        function splitcell(s, limit, out,    p, ch, used, count) {
            s = clean(s); p = 1; used = 0; count = 1; out[1] = ""
            while (p <= length(s)) {
                ch = glyph(s, p)
                if (used + cells > limit) { count++; out[count] = ""; used = 0 }
                out[count] = out[count] ch; used += cells; p += size
            }
            return count
        }
        function padded(s, limit,    p, used) {
            p = 1; used = 0
            while (p <= length(s)) { glyph(s, p); used += cells; p += size }
            return s repeat(" ", limit - used)
        }
        function edge(s) { return border s reset }
        function rule(a, b, c) { print edge(a repeat("─", left + 2) b repeat("─", right + 2) c) }
        function fullrule(a, b, c) { print edge(a repeat(b, width - 2) c) }
        function fullrow(s, style, indent,    n, i, parts) {
            n = splitcell(s, width - 4 - indent, parts)
            for (i = 1; i <= n; i++)
                print edge("│") " " style repeat(" ", indent) padded(parts[i], width - 4 - indent) reset " " edge("│")
        }
        function title_row(s,    used, p, gap) {
            used = 0; p = 1
            while (p <= length(s)) { glyph(s, p); used += cells; p += size }
            gap = int((width - 4 - used) / 2)
            print edge("║") " " title_color repeat(" ", gap) padded(s, width - 4 - gap) reset " " edge("║")
        }
        function row(a, b,    ac, bc, n, i, aa, bb) {
            ac = splitcell(a, left, aa); bc = splitcell(b, right, bb)
            n = ac > bc ? ac : bc
            for (i = 1; i <= n; i++)
                print edge("│") " " padded(aa[i], left) " " edge("│") " " padded(bb[i], right) " " edge("│")
        }
        BEGIN {
            for (i = 1; i < 256; i++) byte[sprintf("%c", i)] = i
            border = ENVIRON["UI_TABLE_BORDER"]; reset = ENVIRON["UI_TABLE_RESET"]
            title_color = ENVIRON["UI_TABLE_TITLE_COLOR"]; green = ENVIRON["UI_TABLE_GREEN"]
            blue = ENVIRON["UI_TABLE_BLUE"]; yellow = ENVIRON["UI_TABLE_YELLOW"]
            menu = ENVIRON["UI_TABLE_MENU"] == "1"
            compact = width < 58
            left = 10; right = width - left - 7
            print ""; fullrule("╔", "═", "╗")
            n = splitcell(ENVIRON["UI_TABLE_TITLE"], width - 4, title)
            for (i = 1; i <= n; i++) title_row(title[i])
            fullrule("╚", "═", "╝")
            if (ENVIRON["UI_TABLE_COUNT"] > 0) {
                print ""
                if (compact) {
                    fullrule("┌", "─", "┐")
                } else if (menu) {
                    heading = "选择操作"
                    if (index(ENVIRON["UI_TABLE_TITLE"], "GitHub")) heading = "选择下载方式"
                    else if (ENVIRON["UI_TABLE_TITLE"] == "固件类型选择") heading = "选择固件类型"
                    else if (index(ENVIRON["UI_TABLE_TITLE"], "版本")) heading = "选择固件版本"
                    fullrule("┌", "─", "┐"); fullrow(heading, reset, 0)
                    fullrule("├", "─", "┤"); fullrow("", reset, 0)
                } else {
                    rule("┌", "┬", "┐"); row("项目", "详情"); rule("├", "┼", "┤")
                }
            }
        }
        {
            tab = index($0, "\t"); kind = substr($0, 1, tab - 1); data = substr($0, tab + 1)
            tab = index(data, "\t"); label = substr(data, 1, tab - 1); value = substr(data, tab + 1)
            if (menu) {
                if (kind == "option") {
                    if (NR > 1) fullrow("", reset, 0)
                    style = index(value, "默认") || index(value, "推荐") ? green : blue
                    hint = compact ? index(value, "（默认") : 0
                    if (compact && !hint) hint = index(value, "（推荐")
                    if (hint) {
                        fullrow(label ") " substr(value, 1, hint - 1), style, 0)
                        fullrow(substr(value, hint), style, 2)
                    } else fullrow(label ") " value, style, compact ? 0 : 1)
                    seen_option = 1
                } else if (label == "说明" && seen_option) {
                    fullrow("• " value, reset, compact ? 2 : 4)
                } else {
                    fullrow(label "：" value, label == "注意" ? yellow : reset, compact ? 0 : 1)
                }
            } else if (compact) {
                if (NR > 1) fullrow("", reset, 0)
                fullrow(label "：", reset, 0)
                fullrow(value, label == "注意" ? yellow : reset, 1)
            } else {
                if (NR > 1) rule("├", "┼", "┤")
                row(label, value)
            }
        }
        END {
            if (NR && (menu || compact)) { fullrow("", reset, 0); fullrule("└", "─", "┘") }
            else if (NR) rule("└", "┴", "┘")
        }
    '
    UI_OPEN=0
    UI_ROWS=()
}

ui_confirm() {
    if [[ "$1" == Y ]]; then
        ui_option y "$2" '默认'
        ui_option n "$3"
    else
        ui_option y "$2"
        ui_option n "$3" '默认'
    fi
    ui_end
    printf '\n'
}

ui_prompt() {
    if [[ "$1" == Y ]]; then
        printf '请选择 [Y/n]（默认：y）：'
    else
        printf '请选择 [y/N]（默认：n）：'
    fi
}

read_input() {
    ui_end
    local input_prompt
    printf -v input_prompt '%b❓ %s%b' "$C_YELLOW" "$1" "$C_RESET"
    # EOF 不应当被当成回车，从而意外接受烧录默认值。
    if ! IFS= read -r -p "$input_prompt" "$2"; then
        printf '\n❌ 输入已关闭，操作中止。\n' >&2
        exit 1
    fi
}

prepare_aria2() {
    command -v aria2c >/dev/null 2>&1 && return 0
    # aria2 是可选加速工具，安装失败不能阻断已有下载方式。
    [[ ${ARIA2_CHECKED:-0} == 0 ]] || return 1
    ARIA2_CHECKED=1
    local manager action
    if command -v opkg >/dev/null 2>&1; then manager=opkg; action=install
    elif command -v apk >/dev/null 2>&1; then manager=apk; action=add
    else
        echo '未找到 aria2c，使用 wget/curl 下载。' >&2
        return 1
    fi
    echo '正在安装 aria2，以启用 4 连接分段下载...' >&2
    if "$manager" update && "$manager" "$action" aria2 && command -v aria2c >/dev/null 2>&1; then
        return 0
    fi
    echo 'aria2 不可用，继续使用 wget/curl 下载。' >&2
    return 1
}

download_file() {
    local url="$1" destination="$2" timeout="${3:-1800}" show_progress="${4:-0}"
    local partial="${destination}.part" attempt client downloaded
    local -a curl_options=(-fsSL) wget_options=(-q) aria2_options=() clients=(curl wget)
    # 仅固件启用分段下载，版本信息和校验文件保持安静。
    if [[ "$show_progress" == 1 ]]; then
        curl_options=(-fL)
        wget_options=()
        clients=(aria2c wget curl)
    fi
    # 只限制 ghfast.top 的连接；其他下载源和 API 仍使用原有地址族选择。
    if [[ "${url,,}" =~ ^https?://ghfast[.]top(:[0-9]+)?(/|$) ]]; then
        curl_options+=(-4)
        wget_options+=(-4)
        aria2_options+=(--disable-ipv6=true)
    fi
    # 先写入临时文件，避免失败的下载被当成完整文件使用。
    for client in "${clients[@]}"; do
        # 每种工具从空的临时文件开始，避免把上次失败的残片当作新结果。
        rm -f -- "$partial" "$partial.aria2" || return 1
        downloaded=0
        case "$client" in
            aria2c)
                prepare_aria2 || continue
                echo '使用 aria2c 下载固件（最多 4 个连接）...' >&2
                if aria2c "${aria2_options[@]}" --no-conf=true --split=4 --max-connection-per-server=4 \
                    --min-split-size=4M --file-allocation=none --disk-cache=0 \
                    --auto-file-renaming=false --allow-overwrite=true \
                    --connect-timeout=15 --timeout=30 --max-tries=3 --retry-wait=2 \
                    --stop="$timeout" --summary-interval=0 --console-log-level=warn \
                    --download-result=hide --enable-color=true --stderr=true \
                    --dir="$(dirname -- "$partial")" --out="$(basename -- "$partial")" "$url" \
                    && [[ -s "$partial" && ! -e "$partial.aria2" ]]; then
                    downloaded=1
                else
                    echo '提示：分段下载未完成，切换到 wget/curl 继续尝试...' >&2
                    # 分段文件可能包含空洞，下一种工具启动前会清除残片。
                fi
                ;;
            wget)
                command -v wget >/dev/null 2>&1 || continue
                for attempt in 1 2 3; do
                    ((attempt == 1)) || printf '正在重试下载（%s/3）...\n' "$attempt" >&2
                    rm -f -- "$partial" || return 1
                    if wget "${wget_options[@]}" -T 30 -O "$partial" "$url" && [[ -s "$partial" ]]; then
                        downloaded=1
                        break
                    fi
                done
                ;;
            curl)
                command -v curl >/dev/null 2>&1 || continue
                if curl "${curl_options[@]}" --connect-timeout 15 --max-time "$timeout" --retry 2 \
                    -o "$partial" "$url" && [[ -s "$partial" ]]; then
                    downloaded=1
                fi
                ;;
        esac
        if [[ "$downloaded" == 1 ]]; then
            rm -f -- "$partial.aria2" || return 1
            mv -f -- "$partial" "$destination"
            return $?
        fi
    done
    rm -f -- "$partial" "$partial.aria2"
    printf '❌ 下载失败：%s\n' "$url" >&2
    return 1
}

fetch_release_json() {
    local url="$1" candidate filter='type == "object" or type == "array"'
    local response="$TMP_DIR/release-api.json"
    local -a urls=("$url")
    # API 加速独立于固件下载选项，保留历史列表的分页查询参数。
    [[ "$url" != https://api.github.com/* ]] || urls+=("https://gh-proxy.org/$url")
    case "$url" in
        */releases/latest)
            filter='type == "object" and (.tag_name | type == "string" and length > 0) and (.assets | type == "array")' ;;
        */releases\?*) filter='type == "array"' ;;
    esac
    for candidate in "${urls[@]}"; do
        if [[ "$candidate" != "$url" ]]; then
            printf '提示：GitHub API 直连未成功，正在切换加速访问...\n' >&2
        fi
        # 每次从空响应开始，避免失败时误用上一次查询的结果。
        rm -f -- "$response" || return 1
        if download_file "$candidate" "$response" 60; then
            # 同时拒绝 HTML、空响应、限流错误对象和结构不符的数据。
            if jq -e "$filter" "$response" >/dev/null 2>&1; then
                cat "$response"
                return $?
            fi
            printf '提示：GitHub API 返回了无效数据，无法读取版本信息。\n' >&2
            jq -r 'objects | .message // empty' "$response" >&2 2>/dev/null || :
        fi
    done
    printf '❌ 获取 GitHub 版本信息失败，请稍后重试。\n' >&2
    return 1
}

select_release() {
    local latest_info history_info choices count raw_count choice index
    local page=1 page_size=10 last_page=0 tag available
    if ! latest_info=$(fetch_release_json "https://api.github.com/repos/$REPO/releases/latest"); then
        printf '❌ 无法获取最新版本信息，请检查网络后重试。\n' >&2
        return 1
    fi
    if ! jq -e '(.tag_name | type == "string" and length > 0) and
        (.assets | type == "array")' <<< "$latest_info" >/dev/null; then
        printf '❌ 无法读取 Release：%s\n' "$(jq -r '.message // "缺少版本标签或附件列表"' <<< "$latest_info")" >&2
        return 1
    fi
    ui_section '固件版本选择'
    ui_field '最新版本' "$(jq -r '.tag_name' <<< "$latest_info")"
    printf '\n'
    ui_option 0 '最新版本' '默认，直接回车'
    ui_option h '历史版本'
    ui_option q '取消烧录'
    printf '\n'
    while true; do
        read_input '请选择 [0/h/q]（默认：0）：' choice
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
                printf '❌ 无法获取历史版本列表。\n' >&2
                return 1
            fi
            if ! jq -e 'type == "array"' <<< "$history_info" >/dev/null; then
                printf '❌ 无法读取历史版本：%s\n' "$(jq -r '.message // "无效的版本列表"' <<< "$history_info")" >&2
                return 1
            fi
            raw_count=$(jq 'length' <<< "$history_info")
            choices=$(jq '[.[] | select(.draft != true and .prerelease != true)
                | select((.tag_name | type) == "string" and (.assets | type) == "array")]' <<< "$history_info")
            count=$(jq 'length' <<< "$choices")
            ui_section "历史版本（第 $page 页）"
            # 一次 jq 调用生成整页列表，避免逐个版本重复解析 JSON。
            while IFS=$'\t' read -r index tag available; do
                if [[ "$available" == true ]]; then
                    ui_option "$index" "$tag"
                else
                    ui_option "$index" "$tag" '无当前型号/类型固件，不可选'
                fi
            done < <(jq -r --arg name "$IMAGE_FILENAME_GZ" '
                to_entries[] | [(.key + 1), .value.tag_name,
                    any(.value.assets[]; .name == $name)] | @tsv' <<< "$choices")
            ((count > 0)) || ui_field '说明' '本页没有可显示的正式版本。'
            ((raw_count < page_size)) && last_page=1 || last_page=0
            printf '\n'
            ui_option n '下一页'
            ui_option p '上一页'
            ui_option 0 '最新版本' '默认，直接回车'
            ui_option q '取消烧录'
            printf '\n'
            while true; do
                read_input '请选择版本编号或操作（默认：0）：' choice
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
    printf '✅ 已选择版本：%s\n' "$RELEASE_TAG"
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

# 计算失败与内容不匹配分开处理，不能把文件读取错误当作校验失败让用户忽略。
calculate_firmware_checksum() {
    local calculated
    calculated=$(set -o pipefail; sha256sum "$IMAGE_PATH_GZ" | awk '{print $1}') || {
        echo '❌ 错误：读取固件或计算 SHA256 失败，停止烧录。' >&2
        return 1
    }
    if [[ ! "$calculated" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo '❌ 错误：未能取得有效的固件 SHA256，停止烧录。' >&2
        return 1
    fi
    printf '%s\n' "${calculated,,}"
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
        else echo "❌ 错误：缺少依赖 ${missing[*]}，且未找到 opkg/apk。" >&2; return 1
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
            printf '❌ 错误：仍缺少命令 %s。\n' "$cmd" >&2
            return 1
        }
    done
    UBUS_PRESENT=0
    if command -v ubus >/dev/null 2>&1; then UBUS_PRESENT=1; fi
    required_cmds_list="${required[*]}"
    if prepare_aria2; then
        ARIA2_STATUS='已就绪，支持 4 连接分段下载'
    else
        ARIA2_STATUS='未就绪，本次使用 wget/curl 下载'
    fi
    if command -v opkg >/dev/null 2>&1; then PKG_MANAGER=opkg
    elif command -v apk >/dev/null 2>&1; then PKG_MANAGER=apk
    fi
}

# BusyBox 精简版 od 可能存在但不支持 -A/-t/-j/-N，必须实测本脚本使用的格式。
od_supports_media_options() {
    local hex decimal
    hex=$(set -o pipefail; printf '\000\125\252\377' | "$@" -An -tx1 -j 1 -N 2 2>/dev/null) || return 1
    decimal=$(set -o pipefail; printf '\000\125\252\377' | "$@" -An -tu1 -j 3 -N 1 2>/dev/null) || return 1
    [[ "${hex//[[:space:]]/}" == 55aa && "${decimal//[[:space:]]/}" == 255 ]]
}

prepare_media_od() {
    if command -v od >/dev/null 2>&1 && od_supports_media_options od; then
        OD_COMMAND=(od)
    elif command -v busybox >/dev/null 2>&1 && od_supports_media_options busybox od; then
        OD_COMMAND=(busybox od)
    else
        return 1
    fi
}

media_od() { "${OD_COMMAND[@]}" "$@"; }

# 只为介质操作准备额外依赖，只检查烧录需要的工具。
check_media_dependencies() {
    local mode="${1:-flash}" show_result="${2:-1}" cmd package manager action
    local -a required=(dd partx mount umount) missing=()
    [[ "$mode" == flash ]] || return 1
    for cmd in "${required[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 && continue
        case "$cmd" in
            dd) package=coreutils-dd ;;
            partx) package=partx-utils ;;
            mount|umount) package=mount-utils ;;
        esac
        [[ " ${missing[*]} " == *" $package "* ]] || missing+=("$package")
    done
    if [[ "$mode" == flash ]] && ! prepare_media_od; then
        missing+=(coreutils-od)
    fi
    if ((${#missing[@]})); then
        if command -v opkg >/dev/null 2>&1; then manager=opkg; action=install
        elif command -v apk >/dev/null 2>&1; then manager=apk; action=add
        else
            printf '❌ 错误：介质操作需要 %s，但未找到 opkg/apk，未写盘。\n' "${missing[*]}" >&2
            return 1
        fi
        printf '信息：正在安装介质操作依赖：%s...\n' "${missing[*]}"
        "$manager" update || echo '警告：软件包列表更新失败，仍尝试安装。' >&2
        "$manager" "$action" "${missing[@]}" || {
            echo '❌ 错误：介质操作依赖安装失败，停止操作，未写盘。' >&2; return 1;
        }
        hash -r
    fi
    for cmd in "${required[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || {
            printf '❌ 错误：安装后仍缺少工具 %s，未写盘。\n' "$cmd" >&2; return 1;
        }
    done
    if [[ "$mode" == flash ]] && ! prepare_media_od; then
        echo '❌ 错误：仍缺少兼容的 od（需要 coreutils-od），停止操作，未写盘。' >&2
        return 1
    fi
    [[ "$show_result" != 1 ]] || echo '✅ 信息：介质操作工具检查通过。'
    return 0
}

# --- 选择 GitHub 访问方式 ---
select_github_access() {
    ui_section 'GitHub 访问方式'
    ui_option 1 'ghfast.top 镜像加速' '默认，推荐'
    ui_field '说明' '适合网络受限环境。'
    ui_field '说明' '通过镜像加速下载。'
    ui_option 2 'GitHub 官方直连'
    ui_field '说明' '需要稳定的国际网络连接。'
    ui_field '说明' '直接从官方服务器下载。'
    read_input '请选择 [1/2]（默认：1）：' github_choice
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

# --- 选择 Docker 版本 ---
select_docker_version() {
    ui_section '固件类型选择'
    ui_option 1 '标准版固件' '默认，推荐'
    ui_field '说明' '常规 OpenWrt 固件，适合日常使用。'
    ui_option 2 'Docker 版固件'
    ui_field '说明' '包含 Docker 支持，适合运行容器。'
    read_input '请选择 [1/2]（默认：1）：' docker_choice
    docker_choice=${docker_choice:-1}

    echo
    case "$docker_choice" in
        1)
            echo -e "${C_B_GREEN}✓ 已选择：${C_RESET}标准版固件"
            USE_DOCKER=false
            ;;
        2)
            echo -e "${C_B_GREEN}✓ 已选择：${C_RESET}Docker 版本固件"
            USE_DOCKER=true
            ;;
        *)
            echo -e "${C_YELLOW}⚠ 无效选项，使用默认：${C_RESET}标准版固件"
            USE_DOCKER=false
            ;;
    esac
    echo
}

# --- 检测设备型号 ---
detect_device_model() {
    echo -e "${C_BLUE}信息：${C_RESET}正在检测设备型号..."

    local detected_model=""
    local board_name=""
    local source_info="未找到"
    local raw_info="未知"

    # 优先从 /proc/device-tree/model 读取
    if [ -r /proc/device-tree/model ]; then
        detected_model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        source_info="/proc/device-tree/model"
        raw_info="$detected_model"
    fi

    # 如果未获取到，尝试从 openwrt_release 读取
    if [ -z "$detected_model" ] && [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        if [ -n "$DISTRIB_TARGET" ]; then
            detected_model="$DISTRIB_TARGET"
            source_info="/etc/openwrt_release"
            raw_info="$detected_model"
        fi
    fi

    # 尝试从ubus获取board_name
    if command -v ubus >/dev/null 2>&1; then
        local ubus_board
        ubus_board=$(ubus call system board 2>/dev/null | jq -r '.board_name // empty') || ubus_board=""
        if [ -n "$ubus_board" ]; then
            board_name="$ubus_board"
            # 如果之前没找到信息，或者ubus更准确，更新source
            source_info="ubus system board"
            raw_info="$board_name"
        fi
    fi

    # 根据检测到的信息映射到固件文件名格式
    if [ -n "$board_name" ]; then
        # board_name通常由于设备树原因可能包含逗号 (如 "friendlyarm,nanopi-r4s")
        # 需将其替换为下划线以匹配Release文件名 (如 "friendlyarm_nanopi-r4s")
        DEVICE_MODEL="${board_name//,/_}"
    elif [ -n "$detected_model" ]; then
        # 如果只有model名称，也尝试替换逗号
        DEVICE_MODEL="${detected_model//,/_}"
        # 这里可能还需要处理空格等其他字符
        DEVICE_MODEL="${DEVICE_MODEL// /_}"
    else
        echo -e "${C_B_RED}❌ 错误：${C_RESET}无法检测设备型号" >&2
        echo -e "${C_YELLOW}提示：${C_RESET}请手动指定设备型号或检查系统信息" >&2
        return 1
    fi

    ui_section '设备型号检测'
    ui_field '检测来源' "$source_info"
    ui_field '原始信息' "$raw_info"
    ui_field '匹配型号' "$DEVICE_MODEL"
    ui_end
    printf '\n'
    return 0
}

# 从实际挂载根分区识别启动盘，避免克隆介质 PARTUUID 相同时识别错盘。
detect_boot_medium() {
    local info
    BOOT_DISK=$(get_media_boot_disk) || BOOT_DISK=""
    BOOT_MEDIUM='未识别'
    if [[ -n "$BOOT_DISK" ]] && info=$(get_mmc_info "$BOOT_DISK"); then
        if [[ "$info" == SD\ * ]]; then BOOT_MEDIUM='SD 卡'; else BOOT_MEDIUM=eMMC; fi
        printf '信息：当前启动介质：%s；启动盘：/dev/%s。\n' "$BOOT_MEDIUM" "$BOOT_DISK"
    else
        echo '信息：无法识别实际 SD/eMMC 启动盘，将停止烧录。'
    fi
}

# 只接受 SD/eMMC 用户区整盘，排除 boot0、boot1、rpmb 和分区节点。
get_mmc_info() {
    local disk="$1" kind cid sectors
    [[ "$disk" =~ ^mmcblk[0-9]+$ && -b "/dev/$disk" ]] || return 1
    kind=$(cat "/sys/class/block/$disk/device/type") || return 1
    cid=$(cat "/sys/class/block/$disk/device/cid") || return 1
    sectors=$(cat "/sys/class/block/$disk/size") || return 1
    [[ "$kind" == SD || "$kind" == MMC ]] || return 1
    [[ "$cid" =~ ^[a-fA-F0-9]{32}$ && "$sectors" =~ ^[1-9][0-9]{0,11}$ ]] || return 1
    printf '%s %s %s\n' "$kind" "$cid" "$sectors"
}

list_mmc_disks() {
    local path disk info
    for path in /sys/class/block/mmcblk*; do
        disk=${path##*/}
        info=$(get_mmc_info "$disk" 2>/dev/null) || continue
        printf '%s %s\n' "$disk" "$info"
    done
}

# 新写入的 SD 可能与 eMMC 有相同 PARTUUID，不能仅按启动参数中的 UUID 猜盘。
# 从已挂载的 /rom（squashfs）或 /（ext4）的设备号识别正在运行的实际介质。
get_media_boot_disk() {
    local device path disk
    device=$(awk '$5 == "/rom" {rom=$3} $5 == "/" {root=$3}
        END {if (rom != "") print rom; else print root}' /proc/self/mountinfo) || return 1
    [[ "$device" =~ ^[0-9]+:[0-9]+$ && "$device" != 0:* ]] || return 1
    path=$(readlink -f "/sys/dev/block/$device") || return 1
    disk=${path##*/}
    if [[ -f "/sys/class/block/$disk/partition" ]]; then
        path=${path%/*}; disk=${path##*/}
    fi
    get_mmc_info "$disk" >/dev/null || return 1
    printf '%s\n' "$disk"
}

# 每次写盘前重新检查启动盘、CID、容量、挂载点、swap 和设备持有者。
check_inactive_mmc() {
    local disk="$1" cid="$2" kind="$3" sectors="$4" boot info mounts holder swap_status
    [[ "$disk" =~ ^mmcblk[0-9]+$ ]] || return 1
    boot=$(get_media_boot_disk) || { echo '❌ 错误：无法确定当前启动盘，禁止写盘。' >&2; return 1; }
    [[ -n "$boot" && "$boot" != "$disk" ]] || {
        echo '❌ 错误：禁止覆盖当前启动盘。' >&2; return 1;
    }
    info=$(get_mmc_info "$disk") || return 1
    [[ "$info" == "$kind $cid $sectors" ]] || {
        echo '❌ 错误：目标介质已拔出、更换或容量发生变化，停止操作。' >&2; return 1;
    }
    mounts=$(lsblk -nr -o MOUNTPOINT "/dev/$disk") || return 1
    [[ -z "${mounts//[[:space:]]/}" ]] || {
        echo "❌ 错误：/dev/$disk 有已挂载分区，请先卸载后重新运行。" >&2; return 1;
    }
    swap_status=$(awk -v disk="/dev/$disk" '$1 == disk || index($1, disk "p") == 1 { busy=1 } END { print busy+0 }' /proc/swaps) || {
        echo '❌ 错误：无法读取 swap 状态，禁止写盘。' >&2; return 1;
    }
    [[ "$swap_status" == 0 ]] || { echo '❌ 错误：目标介质正在用于 swap。' >&2; return 1; }
    for holder in "/sys/class/block/$disk/holders/"* "/sys/class/block/$disk/""$disk"p*/holders/*; do
        [[ ! -e "$holder" ]] || { echo '❌ 错误：目标介质正在被其他块设备使用。' >&2; return 1; }
    done
}

choose_mmc_disk() {
    local kind="$1" cid_filter="${2:-}" disk found_kind cid sectors choice index=0
    local -a names=() ids=() sizes=()
    ui_section '选择目标介质'
    while read -r disk found_kind cid sectors; do
        [[ "$found_kind" == "$kind" && "$disk" != "$BOOT_DISK" ]] || continue
        [[ -z "$cid_filter" || "$cid_filter" == "$cid" ]] || continue
        names+=("$disk"); ids+=("$cid"); sizes+=("$sectors")
        index=$((index + 1))
        ui_option "$index" "/dev/$disk" "$(format_kib "$((sectors / 2))")"
    done < <(list_mmc_disks)
    ((${#names[@]} > 0)) || { ui_end; echo '❌ 未找到可用的目标介质。' >&2; return 1; }
    ui_option q '取消操作'
    while true; do
        read_input '请选择目标编号 [无默认选项，q 取消]：' choice
        [[ "$choice" != q && "$choice" != Q ]] || return 1
        if [[ "$choice" =~ ^[1-9][0-9]{0,2}$ ]] && ((choice <= ${#names[@]})); then
            TARGET_DISK=${names[choice-1]}; TARGET_CID=${ids[choice-1]}; TARGET_SECTORS=${sizes[choice-1]}
            TARGET_KIND=$kind
            if [[ "$kind" == SD ]]; then TARGET_MEDIUM='SD 卡'; else TARGET_MEDIUM=eMMC; fi
            check_inactive_mmc "$TARGET_DISK" "$TARGET_CID" "$kind" "$TARGET_SECTORS"
            return $?
        fi
        echo '请明确输入有效的目标编号或 q。'
    done
}

confirm_media_write() {
    local action="$1" answer
    ui_section "$action" "$C_B_RED"
    ui_field '目标整盘' "/dev/$TARGET_DISK"
    ui_field '容量' "$(format_kib "$((TARGET_SECTORS / 2))")"
    ui_field '设备标识' "$TARGET_CID"
    ui_field '注意' '目标整盘的所有分区和数据都将丢失，此操作不可撤销。'
    ui_field '当前启动盘' "/dev/$BOOT_DISK（不会写入）"
    read_input "请输入完整设备名 /dev/$TARGET_DISK 确认，其他输入取消：" answer
    [[ "$answer" == "/dev/$TARGET_DISK" ]] || { echo '操作已取消，未写入目标介质。'; return 1; }
}

# 仅从当前 SD/eMMC 启动盘烧录到另一种介质，缺少任一介质时停止。
select_install_target() {
    local boot_info target_kind
    BOOT_DISK=$(get_media_boot_disk) || {
        echo '❌ 错误：无法确认实际启动盘，停止烧录。' >&2; return 1;
    }
    boot_info=$(get_mmc_info "$BOOT_DISK") || return 1
    case "$boot_info" in
        SD\ *) BOOT_MEDIUM='SD 卡'; target_kind=MMC; TARGET_MEDIUM=eMMC ;;
        MMC\ *) BOOT_MEDIUM=eMMC; target_kind=SD; TARGET_MEDIUM='SD 卡' ;;
        *) echo '❌ 错误：当前启动介质不是 SD 卡或 eMMC，停止烧录。' >&2; return 1 ;;
    esac
    ui_section "$BOOT_MEDIUM → $TARGET_MEDIUM 烧录"
    ui_field '当前启动盘' "/dev/$BOOT_DISK（不会写入）"
    ui_field '目标介质' "$TARGET_MEDIUM（只允许选择另一种介质）"
    ui_end
    choose_mmc_disk "$target_kind" || return 1
    check_media_dependencies flash || return 1
}

media_image_stream() {
    stream_image
}

# 完整 MiB 使用大块读取，尾部按扇区读；校验范围与镜像完全相同。
read_media_image_bytes() {
    local bytes="$1" blocks tail_sectors
    blocks=$((bytes / 4194304)); tail_sectors=$((bytes % 4194304 / 512))
    if ((blocks > 0)); then
        dd if="/dev/$TARGET_DISK" bs=4M count="$blocks" || return 1
    fi
    if ((tail_sectors > 0)); then
        dd if="/dev/$TARGET_DISK" bs=512 skip="$((blocks * 8192))" count="$tail_sectors" || return 1
    fi
}

# 本项目 Rockchip 镜像为 MBR，U-Boot 动态读取分区 UUID。
# 给目标介质单独的磁盘签名，避免相同固件的 SD/eMMC 并存时 root/配置恢复选错盘。
validate_media_mbr() {
    local header="$TMP_DIR/media-mbr.bin" magic part_type offset
    [[ $(wc -c < "$header") == 512 ]] || return 1
    magic=$(media_od -An -tx1 -j 510 -N 2 "$header") || return 1
    [[ "${magic//[[:space:]]/}" == 55aa ]] || return 1
    for offset in 450 466 482 498; do
        part_type=$(media_od -An -tu1 -j "$offset" -N 1 "$header") || return 1
        if [[ "${part_type//[[:space:]]/}" == 238 ]]; then
            echo '❌ 错误：当前介质烧录模式仅支持本项目的 MBR 镜像，不修改 GPT 磁盘。' >&2
            return 1
        fi
    done
}

# 消费完整压缩流；仅保留前 512 字节，不生成完整解压镜像。
capture_media_image_size() {
    local remainder
    # BusyBox head 使用 stdio 缓冲，可能从管道多读但只输出 512 字节，
    # 导致随后的 wc 少算长度。dd 按 1 字节读取 512 次，不消费后续数据。
    if ! dd bs=1 count=512 of="$TMP_DIR/media-mbr.bin" 2> "$TMP_DIR/media-header.log"; then
        cat "$TMP_DIR/media-header.log" >&2
        echo '❌ 错误：无法读取完整镜像头，未写盘。' >&2
        return 1
    fi
    [[ $(wc -c < "$TMP_DIR/media-mbr.bin") == 512 ]] || {
        echo '❌ 错误：镜像头不足 512 字节，未写盘。' >&2; return 1;
    }
    remainder=$(wc -c) || return 1
    remainder=${remainder//[[:space:]]/}
    [[ "$remainder" =~ ^[0-9]{1,12}$ ]] || return 1
    printf '%s\n' "$((remainder + 512))"
}

verify_media_readback() {
    local image_bytes="$1" expected actual log="$TMP_DIR/media-readback.log"
    printf '信息：读回校验范围：前 %s 字节（%s）。\n' "$image_bytes" "$(format_kib "$(((image_bytes + 1023) / 1024))")"
    expected=$(set -o pipefail; media_image_stream | sha256sum | awk '{print $1}') || {
        echo '❌ 错误：读取源镜像或计算 SHA256 失败，停止后续操作。' >&2; return 1;
    }
    actual=$(set -o pipefail; read_media_image_bytes "$image_bytes" 2> "$log" | sha256sum | awk '{print $1}') || {
        cat "$log" >&2
        echo '❌ 错误：目标介质读回或 SHA256 计算失败，当前启动盘未被写入。' >&2; return 1;
    }
    [[ "$expected" =~ ^[a-fA-F0-9]{64}$ && "$actual" =~ ^[a-fA-F0-9]{64}$ ]] || {
        echo '❌ 错误：未取得有效的 SHA256 校验值，停止后续操作。' >&2; return 1;
    }
    if [[ "$expected" != "$actual" ]]; then
        printf '镜像 SHA256：%s\n读回 SHA256：%s\n' "$expected" "$actual" >&2
        cat "$log" >&2
        echo '❌ 错误：目标介质写入读回校验失败，当前启动盘未被写入。' >&2
        return 1
    fi
    rm -f -- "$log"
}

set_media_disk_signature() {
    local header="$TMP_DIR/media-mbr.bin" signature_file="$TMP_DIR/media-id.bin"
    local original boot_signature signature actual attempt
    check_inactive_mmc "$TARGET_DISK" "$TARGET_CID" "$TARGET_KIND" "$TARGET_SECTORS" || return 1
    dd if="/dev/$TARGET_DISK" of="$header" bs=512 count=1 || return 1
    validate_media_mbr || return 1
    original=$(media_od -An -tx1 -j 440 -N 4 "$header") || return 1
    boot_signature=$(set -o pipefail; dd if="/dev/$BOOT_DISK" bs=1 skip=440 count=4 | media_od -An -tx1) || return 1
    original=${original//[[:space:]]/}; boot_signature=${boot_signature//[[:space:]]/}
    [[ "$original" =~ ^[a-f0-9]{8}$ && "$boot_signature" =~ ^[a-f0-9]{8}$ ]] || return 1
    for attempt in 1 2 3 4; do
        dd if=/dev/urandom of="$signature_file" bs=4 count=1 || return 1
        signature=$(media_od -An -tx1 "$signature_file") || return 1
        signature=${signature//[[:space:]]/}
        [[ "$signature" =~ ^[a-f0-9]{8}$ && "$signature" != 00000000 &&
            "$signature" != "$original" && "$signature" != "$boot_signature" ]] && break
    done
    [[ "$signature" =~ ^[a-f0-9]{8}$ && "$signature" != 00000000 &&
        "$signature" != "$original" && "$signature" != "$boot_signature" ]] || return 1
    check_inactive_mmc "$TARGET_DISK" "$TARGET_CID" "$TARGET_KIND" "$TARGET_SECTORS" || return 1
    dd if="$signature_file" of="/dev/$TARGET_DISK" bs=1 seek=440 count=4 conv=notrunc,fsync || return 1
    actual=$(set -o pipefail; dd if="/dev/$TARGET_DISK" bs=1 skip=440 count=4 | media_od -An -tx1) || return 1
    [[ "${actual//[[:space:]]/}" == "$signature" ]] || return 1
    echo '✅ 信息：已设置目标介质的独立磁盘标识，避免与当前启动盘的分区 UUID 冲突。'
}

write_media_image() {
    local image_bytes backup="$TMP_DIR/media-config.tgz" mount_dir="$TMP_DIR/media-boot" info available required expected actual source_boot source_info
    [[ "$TARGET_KIND" == SD || "$TARGET_KIND" == MMC ]] || return 1
    source_boot=$(get_media_boot_disk) || return 1
    source_info=$(get_mmc_info "$source_boot") || return 1
    if [[ ! ( "$source_info" == SD\ * && "$TARGET_KIND" == MMC ) &&
          ! ( "$source_info" == MMC\ * && "$TARGET_KIND" == SD ) ]]; then
        echo '❌ 错误：仅允许 SD 卡与 eMMC 之间双向烧录，停止写入。' >&2
        return 1
    fi
    check_media_dependencies flash 0 || return 1
    check_inactive_mmc "$TARGET_DISK" "$TARGET_CID" "$TARGET_KIND" "$TARGET_SECTORS" || return 1
    echo '信息：正在计算完整镜像大小并检查目标容量，不生成完整解压镜像...'
    image_bytes=$(set -o pipefail; media_image_stream | capture_media_image_size) || return 1
    image_bytes=${image_bytes//[[:space:]]/}
    [[ "$image_bytes" =~ ^[1-9][0-9]{0,11}$ ]] && ((image_bytes % 512 == 0 && image_bytes <= TARGET_SECTORS * 512)) || {
        echo '❌ 错误：镜像大小无效或目标介质容量不足，未写盘。' >&2; return 1;
    }
    validate_media_mbr || { echo '❌ 错误：烧录镜像的分区表不受支持，未写盘。' >&2; return 1; }
    confirm_media_write "确认整盘烧录到 $TARGET_MEDIUM" || return 1
    check_upgrade_resources || return 1
    if [[ "$KEEP_CONFIG" == 1 ]]; then
        echo "信息：正在生成迁移到 $TARGET_MEDIUM 的配置备份..."
        sysupgrade -b "$backup" || return 1
        [[ -s "$backup" ]] || return 1
    fi
    check_inactive_mmc "$TARGET_DISK" "$TARGET_CID" "$TARGET_KIND" "$TARGET_SECTORS" || return 1
    echo "信息：正在整盘写入 $TARGET_MEDIUM /dev/$TARGET_DISK，请勿移除介质或断电..."
    (set -o pipefail; media_image_stream | dd of="/dev/$TARGET_DISK" bs=4M conv=fsync) || {
        echo '❌ 错误：目标介质写入失败，当前启动盘未被写入。' >&2; return 1;
    }
    sync || return 1
    # 写入后读回完整镜像范围，避免仅凭 dd 退出码就提示烧录成功。
    echo "信息：正在读回 $TARGET_MEDIUM 并校验完整镜像，请稍候..."
    verify_media_readback "$image_bytes" || return 1
    set_media_disk_signature || { echo '❌ 错误：目标介质磁盘标识设置失败，请保留当前启动盘。' >&2; return 1; }
    if [[ "$KEEP_CONFIG" == 1 ]]; then
        check_inactive_mmc "$TARGET_DISK" "$TARGET_CID" "$TARGET_KIND" "$TARGET_SECTORS" || return 1
        partx -d - "/dev/$TARGET_DISK" && partx -a - "/dev/$TARGET_DISK" || return 1
        info=$(get_mmc_info "$TARGET_DISK") || return 1
        [[ "$info" == "$TARGET_KIND $TARGET_CID $TARGET_SECTORS" && -b "/dev/${TARGET_DISK}p1" ]] || return 1
        mkdir -p "$mount_dir" || return 1
        mount -o rw,noatime "/dev/${TARGET_DISK}p1" "$mount_dir" || return 1
        MEDIA_BOOT_MOUNTED=1
        available=$(set -o pipefail; df -Pk "$mount_dir" | awk 'END {print $4}') || return 1
        required=$(wc -c < "$backup") || return 1
        [[ "$available" =~ ^[0-9]+$ ]] && ((available >= (required + 1023) / 1024 + 1024)) || {
            echo '❌ 错误：目标启动分区无法容纳配置备份；请保留当前启动盘。' >&2; return 1;
        }
        cp -f -- "$backup" "$mount_dir/sysupgrade.tgz" || return 1
        expected=$(set -o pipefail; sha256sum "$backup" | awk '{print $1}') || return 1
        actual=$(set -o pipefail; sha256sum "$mount_dir/sysupgrade.tgz" | awk '{print $1}') || return 1
        [[ "$expected" =~ ^[a-fA-F0-9]{64}$ && "$expected" == "$actual" ]] || return 1
        sync && umount "$mount_dir" || return 1
        MEDIA_BOOT_MOUNTED=0
        rmdir "$mount_dir" || return 1
        echo '✅ 信息：配置备份已放入目标启动分区，供新系统首次启动恢复。'
    fi
    echo "✅ 信息：$TARGET_MEDIUM 整盘烧录及读回校验完成，当前启动盘未被写入。"
    echo "信息：请关机后切换到 $TARGET_MEDIUM 启动，确认新系统及配置正常；原启动介质保持不变。"
}

# 大小提示统一使用 KiB / MiB；内部资源计算仍使用 KiB。
format_kib() {
    local size_kib="$1" fraction
    if ((size_kib < 1024)); then
        printf '%s KiB' "$size_kib"
    else
        fraction=$(((size_kib % 1024 * 100 + 512) / 1024))
        printf '%d.%02d MiB' "$((size_kib / 1024 + fraction / 100))" "$((fraction % 100))"
    fi
}

# 按实际剩余资源检查；不把 tmpfs 挂载上限当作物理内存。
check_available_resources() {
    local additional_kib="$1" phase="$2" available_kib filesystem memory_kib required_kib space_info
    # 一次 df 同时读取文件系统类型和可用空间，保持单位为 KiB。
    space_info=$(set -o pipefail; df -PkT "$TMP_DIR" 2>/dev/null | awk 'END {print $2, $5}') || {
        echo '❌ 错误：无法读取临时目录的实际可用空间，停止烧录。' >&2
        return 1
    }
    read -r filesystem available_kib <<< "$space_info"
    memory_kib=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo) || {
        echo '❌ 错误：无法读取 MemAvailable，停止烧录。' >&2
        return 1
    }
    if [[ ! "$available_kib" =~ ^[0-9]+$ || ! "$memory_kib" =~ ^[0-9]+$ || -z "$filesystem" ]]; then
        echo '❌ 错误：无法读取实际可用空间或 MemAvailable，停止烧录。' >&2
        return 1
    fi
    required_kib=$((additional_kib + WORK_RESERVE_KIB))
    if ((available_kib < required_kib)); then
        printf '❌ 错误：%s需要至少 %s 临时空间（含工作余量），当前仅 %s。不会自动清除配置。\n' \
            "$phase" "$(format_kib "$required_kib")" "$(format_kib "$available_kib")" >&2
        return 1
    fi
    # tmpfs/ramfs 的文件会占用内存；扩大挂载上限不会增加物理内存。
    if [[ "$filesystem" != tmpfs && "$filesystem" != ramfs ]]; then
        required_kib=$WORK_RESERVE_KIB
    fi
    if ((memory_kib < required_kib)); then
        printf '❌ 错误：%s需要至少 %s 可用内存（含工作余量），当前仅 %s。请释放内存后重试。\n' \
            "$phase" "$(format_kib "$required_kib")" "$(format_kib "$memory_kib")" >&2
        return 1
    fi
    printf '✅ 信息：%s资源检查通过，临时空间 %s，可用内存 %s。\n' \
        "$phase" "$(format_kib "$available_kib")" "$(format_kib "$memory_kib")"
}

check_download_resources() {
    local size_bytes
    size_bytes=$(jq -r --arg name "$IMAGE_FILENAME_GZ" \
        '[.assets[] | select(.name == $name)] | if length == 1 then .[0].size else null end' \
        <<< "$RELEASE_INFO") || return 1
    if [[ ! "$size_bytes" =~ ^[1-9][0-9]{0,11}$ ]]; then
        echo '❌ 错误：Release 未提供有效的压缩固件大小，无法检查下载空间。' >&2
        return 1
    fi
    check_available_resources "$(((size_bytes + 1023) / 1024))" '下载压缩固件'
}

validate_compressed_image() {
    local status=0
    [[ -s "$IMAGE_PATH_GZ" ]] || { echo '❌ 错误：压缩固件不存在或为空。' >&2; return 1; }
    # 只检查压缩流和 CRC，不生成 .img；保留尾部的 fwtool 元数据。
    gunzip -t "$IMAGE_PATH_GZ" || status=$?
    case "$status" in
        0) echo '✅ 信息：压缩镜像完整性检查通过。' ;;
        2) echo '✅ 信息：压缩流检查完成，检测到固件尾部附加数据；继续检查镜像分区表。' ;;
        *) printf '❌ 错误：压缩固件检查失败（退出码 %s），停止烧录。\n' "$status" >&2; return 1 ;;
    esac
}

stream_image() {
    local status=0
    gunzip -c "$IMAGE_PATH_GZ" || status=$?
    # 与原解压方案一致：允许 fwtool 尾部数据引起的警告，不忽略真正的解压错误。
    [[ "$status" == 0 || "$status" == 2 ]]
}

prepare_upgrade_image() {
    check_available_resources 0 '检查压缩镜像' || return 1
    validate_compressed_image || return 1
    KEEP_IMAGE=1
    IMAGE_PATH="$IMAGE_PATH_GZ"
    echo '信息：使用压缩镜像流式烧录，不生成完整 .img 文件。'
}

check_upgrade_resources() {
    local backup_bytes=0 extra_kib=0 backup_started backup_kib growth_kib
    if [[ "$KEEP_CONFIG" == 1 ]]; then
        # 本次运行只测量一次；正式配置备份仍由 sysupgrade 重新生成。
        if [[ "$CONFIG_BACKUP_BYTES" =~ ^[1-9][0-9]{0,11}$ ]]; then
            backup_bytes=$CONFIG_BACKUP_BYTES
        else
            check_available_resources 0 '准备烧录' || return 1
            # 流式测量实际配置备份，不先在内存文件系统中生成一份大归档。
            echo '信息：正在打包配置并检查备份大小，请稍候（耗时取决于配置大小和设备性能）...'
            backup_started=$SECONDS
            backup_bytes=$(set -o pipefail; sysupgrade -b - | wc -c) || {
                echo '❌ 错误：配置备份预检查失败，停止烧录；不会改为不保留配置。' >&2
                return 1
            }
            backup_bytes=${backup_bytes//[[:space:]]/}
            if [[ ! "$backup_bytes" =~ ^[1-9][0-9]{0,11}$ ]]; then
                echo '❌ 错误：配置备份为空或大小无效，停止烧录。' >&2
                return 1
            fi
            CONFIG_BACKUP_BYTES=$backup_bytes
            printf '✅ 信息：配置备份约 %s，检查耗时 %s 秒，将保留配置烧录。\n' \
                "$(format_kib "$(((backup_bytes + 1023) / 1024))")" "$((SECONDS - backup_started))"
        fi
        # 烧录前在 /tmp 创建一份归档，随后复制到目标启动分区。
        # 复制缓冲计入原有 64 MiB 工作余量，不额外预留一份完整归档。
        # 另留 10%（至少 4 MiB）应对正式备份相对本次测量的小幅增长。
        backup_kib=$(((backup_bytes + 1023) / 1024))
        growth_kib=$(((backup_kib + 9) / 10))
        ((growth_kib >= 4096)) || growth_kib=4096
        extra_kib=$((backup_kib + growth_kib))
    fi
    # 每次都重新读取可用空间和内存，不复用资源检查结果。
    check_available_resources "$extra_kib" '固件烧录'
}

# 正在运行的脚本、已交接给 sysupgrade 的镜像，以及挂载点都不能清理。
upgrade_dir_in_use() {
    local directory="$1" owner_pid="" cmdline proc_root="${2:-/proc}" mount_status=0
    if [[ -r "$directory/.updater-pid" ]]; then
        IFS= read -r owner_pid < "$directory/.updater-pid" || owner_pid=""
        if [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$owner_pid" 2>/dev/null; then
            return 0
        fi
    fi
    if [[ -r "$proc_root/self/mountinfo" ]]; then
        awk -v path="$directory" '$5 == path || index($5, path "/") == 1 { found=1 } END { exit !found }' \
            "$proc_root/self/mountinfo" || mount_status=$?
        # 找到挂载点或读取检查出错时都保留目录。
        ((mount_status == 1)) || return 0
    fi
    # 兼容旧脚本没有 PID 标记、或脚本退出后原生烧录仍在读取镜像的情况。
    for cmdline in "$proc_root"/[0-9]*/cmdline; do
        [[ -r "$cmdline" ]] || continue
        if tr '\0' '\n' < "$cmdline" 2>/dev/null | grep -F -- "$directory/" >/dev/null; then
            return 0
        fi
    done
    return 1
}

cleanup_old_upgrade_dirs() {
    local root="$1" directory name removed=0
    root=$(cd -- "$root" && pwd -P) || return 1
    for directory in "$root"/openwrt-upgrade.*; do
        [[ -d "$directory" && ! -L "$directory" ]] || continue
        name=${directory##*/}
        # 仅匹配 mktemp 创建的六位后缀；删除目标必须是该临时目录的直接子目录。
        [[ "$name" =~ ^openwrt-upgrade[.][A-Za-z0-9]{6}$ && "${directory%/*}" == "$root" ]] || continue
        [[ "$name" != "${TMP_DIR##*/}" ]] || continue
        if upgrade_dir_in_use "$directory"; then
            printf '信息：保留正在使用的烧录临时目录：%s。\n' "$directory"
            continue
        fi
        if ! rm -rf -- "$directory"; then
            printf '❌ 错误：无法清理旧烧录临时目录：%s，停止运行。\n' "$directory" >&2
            return 1
        fi
        removed=$((removed + 1))
    done
    if ((removed > 0)); then
        printf '✅ 信息：已清理 %s 个旧烧录临时目录。\n' "$removed"
    fi
    return 0
}

# --- 退出脚本时清理本次任务的临时文件 ---
cleanup() {
    local file
    if [[ "$MEDIA_BOOT_MOUNTED" == 1 ]]; then
        umount "$TMP_DIR/media-boot" || { echo '警告：目标启动分区仍被挂载，请手动卸载。' >&2; return 1; }
        MEDIA_BOOT_MOUNTED=0
    fi
    rm -f -- "$TMP_DIR/media-config.tgz" "$TMP_DIR/media-mbr.bin" "$TMP_DIR/media-id.bin"
    rm -f -- "$TMP_DIR/media-header.log"
    [[ ${KEEP_IMAGE:-0} == 1 ]] || rm -f -- "$TMP_DIR/media-readback.log"
    rmdir "$TMP_DIR/media-boot" 2>/dev/null || :
    for file in "${IMAGE_PATH_GZ:-}" "${IMAGE_PATH_IMG:-}" "${CHECKSUM_PATH:-}"; do
        if [[ -n "$file" ]]; then
            if [[ ${KEEP_IMAGE:-0} != 1 ||
                ( "$file" != "${IMAGE_PATH_GZ:-}" && "$file" != "${IMAGE_PATH:-}" ) ]]; then
                rm -f -- "$file"
            fi
            rm -f -- "$file.part" "$file.part.aria2"
        fi
    done
    rm -f -- "$TMP_DIR/release-api.json" "$TMP_DIR/release-api.json.part" "$TMP_DIR/.updater-pid"
    # 保留检查通过的镜像，取消或失败后可手动烧录。
    rmdir -- "$TMP_DIR" 2>/dev/null || true
}

if [[ $(id -u) != 0 ]]; then
    echo '❌ 错误：请以 root 用户运行烧录脚本。' >&2
    exit 1
fi

# 每次运行使用独立目录，不删除 /tmp 中其他任务的镜像或脚本。
TMP_DIR=$(mktemp -d /tmp/openwrt-upgrade.XXXXXX) || exit 1
if [[ -n ${IMAGE_FILENAME_GZ:-} ]]; then
    IMAGE_PATH_GZ="$TMP_DIR/$IMAGE_FILENAME_GZ"
    CHECKSUM_PATH="$TMP_DIR/$CHECKSUM_FILENAME"
fi
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 先登记本次任务，再清理同一临时根目录下不再使用的旧任务。
printf '%s\n' "$$" > "$TMP_DIR/.updater-pid" || exit 1
cleanup_old_upgrade_dirs "${TMP_DIR%/*}" || exit 1

# 首次绘制前刷新 Bash 的终端列数，兼容没有 stty 的 OpenWrt。
# 外部命令在主流程执行，避免首个标题先用默认宽度绘制。
if [[ -t 1 ]]; then shopt -s checkwinsize; fi
command -p uname >/dev/null 2>&1 || true

echo "信息：本次任务的临时目录为 $TMP_DIR"

echo
ui_section 'Rockchip SD / eMMC 双向烧录'
ui_end
echo

# --- 1. 检查并尝试安装依赖项 ---
echo -e "${C_BLUE}--- 步骤 1: 检查并尝试安装依赖项 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}检查所需工具 (curl/wget, jq, gunzip, awk, sha256sum, lsblk)，并准备 aria2c 下载加速..."

check_dependencies || exit 1

ui_section '依赖检查结果'
ui_field '包管理器' "$PKG_MANAGER"
ui_field '必需命令' "$required_cmds_list"
ui_field 'Aria2' "$ARIA2_STATUS"
ui_end
echo
echo -e "${C_BLUE}✅ --- 步骤 1 完成 ---${C_RESET}"
echo

# 启用严格错误检查
set -e

# --- 2. 显示系统和磁盘信息 ---
echo -e "${C_BLUE}--- 步骤 2: 显示系统信息并检查内存 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在收集当前系统信息..."
echo

# 总内存用于选择烧录方案，实际可用内存用于后续资源检查。
echo -e "${C_CYAN}>> 内存检查:${C_RESET}"
mem_total_kib=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)
echo '信息：本脚本仅烧录到另一种介质，使用压缩镜像流式写入。'
echo

# --- 显示简化内存信息 ---
echo -e "${C_CYAN}>> 内存信息 (当前):${C_RESET}"
mem_avail_kib=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)

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
detect_boot_medium
echo

# 文件系统使用情况和类型 (df)
echo -e "${C_CYAN}>> 文件系统使用情况 (df -hT):${C_RESET}"
df -hT | sed 's/^/  /' || echo -e "  ${C_YELLOW}无法获取文件系统使用情况。${C_RESET}"
echo

ui_section '系统信息汇总'
if [[ -n "$mem_total_kib" ]]; then
    mem_total_mib=$(awk -v total_kib="$mem_total_kib" 'BEGIN { printf "%.0f MiB", total_kib/1024 }')
else
    mem_total_mib='无法获取'
fi
if [[ -n "$mem_avail_kib" ]]; then
    mem_avail_mib=$(awk -v avail_kib="$mem_avail_kib" 'BEGIN { printf "%.0f MiB", avail_kib/1024 }')
else
    mem_avail_mib='无法获取'
fi
ui_field '设备型号' "${model:-${model_sysinfo:-${model_dt:-未知}}}"
ui_field '内存总量' "$mem_total_mib"
ui_field '可用内存' "$mem_avail_mib"
ui_field '启动介质' "$BOOT_MEDIUM"
ui_field '启动磁盘' "${BOOT_DISK:+/dev/}${BOOT_DISK:-未识别}"
tmp_size=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $2}')
tmp_avail=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $4}')
ui_field '临时空间' "总计: ${tmp_size:-未知} / 可用: ${tmp_avail:-未知}"
ui_end
echo
echo -e "${C_BLUE}✅ --- 步骤 2 完成 ---${C_RESET}"
echo

# 选择 GitHub 访问方式
select_install_target || exit 1
select_github_access

# 选择 Docker 版本
select_docker_version

# 检测设备型号并生成文件名
if ! detect_device_model; then
    echo -e "${C_B_RED}❌ 错误：${C_RESET}设备型号检测失败，无法继续。" >&2
    exit 1
fi

# 根据检测到的型号和Docker选择生成文件名
echo
echo -e "${C_BLUE}信息：${C_RESET}正在生成固件文件名..."

FIRMWARE_TYPE_STR=""
if [ "$USE_DOCKER" = true ]; then
    IMAGE_FILENAME_GZ="docker-immortalwrt-rockchip-armv8-${DEVICE_MODEL}-squashfs-sysupgrade.img.gz"
    CHECKSUM_FILENAME="docker-sha256sums"
    FIRMWARE_TYPE_STR="Docker 版本固件"
else
    IMAGE_FILENAME_GZ="immortalwrt-rockchip-armv8-${DEVICE_MODEL}-squashfs-sysupgrade.img.gz"
    CHECKSUM_FILENAME="sha256sums"
    FIRMWARE_TYPE_STR="标准版固件"
fi

IMAGE_PATH_GZ="$TMP_DIR/$IMAGE_FILENAME_GZ"
IMAGE_PATH_IMG="${IMAGE_PATH_GZ%.gz}"
CHECKSUM_PATH="$TMP_DIR/$CHECKSUM_FILENAME"

ui_section '固件参数'
ui_field '固件类型' "$FIRMWARE_TYPE_STR"
ui_field '固件文件' "$IMAGE_FILENAME_GZ"
ui_field '校验文件' "$CHECKSUM_FILENAME"
ui_end
echo

# 启用严格错误检查
set -e

# --- 3. 选择固件版本 ---
echo -e "${C_BLUE}--- 步骤 3: 选择最新或历史版本 ---${C_RESET}"
select_release || exit 1
echo -e "${C_BLUE}✅ --- 步骤 3 完成 ---${C_RESET}"
echo

# --- 4. 临时增大 /tmp 分区 ---
echo -e "${C_BLUE}--- 步骤 4: 临时增大 /tmp 分区 ---${C_RESET}"
ui_section '临时扩大 /tmp 分区'
ui_field '说明' '将 /tmp 挂载上限临时调整到 RAM 的 100%，重启后失效。'
ui_field '说明' '用于存储固件和配置备份，不会增加物理内存。'
ui_field '临时空间' "$(df -h /tmp | awk 'NR==2 {printf "总计: %s / 可用: %s", $2, $4}')"
ui_confirm Y '临时扩大 /tmp 分区' '保持当前大小'
read_input "$(ui_prompt Y)" confirm_resize_tmp
confirm_resize_tmp=${confirm_resize_tmp:-Y}  # 默认为Y

if [[ "$confirm_resize_tmp" =~ ^[Yy]$ ]]; then
    echo -e "${C_BLUE}信息：${C_RESET}正在尝试将 /tmp 重新挂载为更大内存（RAM 的 100%）..."
    mount -t tmpfs -o remount,size=100% tmpfs /tmp || echo -e "${C_YELLOW}警告：${C_RESET}重新挂载 /tmp 可能失败或不受支持，继续执行..."
    echo -e "${C_BLUE}信息：${C_RESET}/tmp 扩容后大小:"
    df -h /tmp | sed 's/^/  /'
else
    echo -e "${C_YELLOW}信息：${C_RESET}用户选择跳过 /tmp 分区扩容。"
fi
echo -e "${C_BLUE}✅ --- 步骤 4 完成 ---${C_RESET}"
echo

# --- 5. 查找固件和校验文件 URL ---
echo -e "${C_BLUE}--- 步骤 5: 查找文件 URL ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在查找固件 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 和校验文件 '${C_CYAN}${CHECKSUM_FILENAME}${C_RESET}'..."
IMAGE_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$IMAGE_FILENAME_GZ" '.assets[] | select(.name==$NAME) | .browser_download_url')
CHECKSUM_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$CHECKSUM_FILENAME" '.assets[] | select(.name==$NAME) | .browser_download_url')

SKIP_CHECKSUM=0
if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" == "null" ]; then echo -e "${C_B_RED}❌ 错误：${C_RESET}在版本 '${C_YELLOW}${RELEASE_TAG}${C_RESET}' 中未找到固件文件 '${C_RED}${IMAGE_FILENAME_GZ}${C_RESET}'。" >&2; exit 1; fi
echo -e "${C_BLUE}信息：${C_RESET}找到固件下载链接: ${C_CYAN}${IMAGE_URL}${C_RESET}"
if [ -z "$CHECKSUM_URL" ] || [ "$CHECKSUM_URL" == "null" ]; then echo -e "${C_YELLOW}警告：${C_RESET}未找到校验文件 '${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}'，将【自动跳过】文件完整性校验。"; SKIP_CHECKSUM=1; else echo -e "${C_BLUE}信息：${C_RESET}找到校验文件下载链接: ${C_CYAN}${CHECKSUM_URL}${C_RESET}"; fi
echo -e "${C_BLUE}✅ --- 步骤 5 完成 ---${C_RESET}"
echo

# --- 6. 下载前确认 ---
echo -e "${C_BLUE}--- 步骤 6: 下载前确认 ---${C_RESET}"
ui_section '固件下载确认'
ui_field '版本标签' "$RELEASE_TAG"
ui_field '固件文件' "$IMAGE_FILENAME_GZ"
if [[ "$SKIP_CHECKSUM" == 1 ]]; then
    ui_field '校验文件' '未找到，将跳过 SHA256 校验'
else
    ui_field '校验文件' "$CHECKSUM_FILENAME"
fi
ui_field '保存路径' "$TMP_DIR"
printf '\n'
ui_confirm Y '开始下载固件' '取消下载'
read_input "$(ui_prompt Y)" confirm_download
confirm_download=${confirm_download:-Y}  # 默认为Y
if [[ ! "$confirm_download" =~ ^[Yy]$ ]]; then echo -e "${C_YELLOW}操作已取消，未下载固件。${C_RESET}"; exit 0; fi
echo

# --- 7. 下载文件 ---
echo -e "${C_BLUE}--- 步骤 7: 下载文件 ---${C_RESET}"
echo -e "${C_BLUE}信息：${C_RESET}正在下载压缩固件 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 到 '${C_CYAN}${IMAGE_PATH_GZ}${C_RESET}' ..."
check_download_resources || exit 1
download_file "${GITHUB_PROXY}${IMAGE_URL}" "$IMAGE_PATH_GZ" 1800 1 || exit 1
echo -e "${C_B_GREEN}✅ 信息：${C_RESET}压缩固件下载完成。"

# 下载校验文件
if [ $SKIP_CHECKSUM -eq 0 ]; then
    echo -e "${C_BLUE}信息：${C_RESET}正在下载校验文件 '${C_CYAN}${CHECKSUM_FILENAME}${C_RESET}' 到 '${C_CYAN}${CHECKSUM_PATH}${C_RESET}' ..."
    dl_status=0
    download_file "${GITHUB_PROXY}${CHECKSUM_URL}" "$CHECKSUM_PATH" 120 || dl_status=$?
    if [ $dl_status -ne 0 ]; then
        echo -e "${C_YELLOW}警告：${C_RESET}下载校验文件 '${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}' 失败，将跳过文件完整性校验。"
        rm -f "$CHECKSUM_PATH"; SKIP_CHECKSUM=1;
    else echo -e "${C_B_GREEN}✅ 信息：${C_RESET}校验文件下载完成。"; fi
fi
echo -e "${C_BLUE}✅ --- 步骤 7 完成 ---${C_RESET}"
echo

# --- 8. 校验固件完整性 (询问是否执行) ---
echo -e "${C_BLUE}--- 步骤 8: 校验固件完整性 (SHA256) ---${C_RESET}"
if [ $SKIP_CHECKSUM -eq 1 ]; then
    echo -e "${C_YELLOW}信息：由于之前步骤未能找到或下载校验文件，跳过文件完整性校验。${C_RESET}"
else
    ui_section '固件完整性校验'
    ui_field '说明' '推荐执行 SHA256 校验，检查固件是否损坏或被篡改。'
    ui_field '注意' '跳过校验可能导致烧录失败或系统损坏。'
    ui_confirm Y '执行 SHA256 校验' '跳过 SHA256 校验'
    read_input "$(ui_prompt Y)" confirm_run_checksum
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
            CALCULATED_SUM=$(calculate_firmware_checksum) || exit 1
            ui_section 'SHA256 校验结果'
            ui_field '期望校验' "$EXPECTED_SUM"
            ui_field '实际校验' "$CALCULATED_SUM"
            ui_end
            printf '\n'
            if [ "$EXPECTED_SUM" == "$CALCULATED_SUM" ]; then
                echo -e "${C_B_GREEN}✅ 校验成功！文件完整。${C_RESET}"
            else
                echo; echo -e "${C_B_RED}❌ 错误：SHA256 校验和不匹配！文件可能已损坏或不完整。${C_RESET}"; echo
                confirm_checksum_fail=""
                ui_section '校验失败后的操作' "$C_B_RED"
                ui_confirm N '忽略校验失败，继续烧录' '中止烧录'
                read_input "$(ui_prompt N)" confirm_checksum_fail
                if [[ ! "$confirm_checksum_fail" =~ ^[Yy]$ ]]; then echo -e "${C_YELLOW}操作中止。${C_RESET}"; exit 1; fi
                echo -e "${C_YELLOW}信息：用户选择忽略校验失败并继续。${C_RESET}"
                SKIP_CHECKSUM=1
            fi
        fi
    fi
fi
rm -f "$CHECKSUM_PATH" # 清理校验文件
echo -e "${C_BLUE}✅ --- 步骤 8 完成 ---${C_RESET}"
echo

# --- 9. 检查用于流式烧录的压缩镜像 ---
echo -e "${C_BLUE}--- 步骤 9: 检查并准备烧录镜像 ---${C_RESET}"
prepare_upgrade_image || exit 1
ls -lh "$IMAGE_PATH" 2>/dev/null || ls -l "$IMAGE_PATH" || true
echo -e "${C_BLUE}✅ --- 步骤 9 完成 ---${C_RESET}"
echo

# --- 10. 检查空间并确定烧录选项 ---
echo -e "${C_BLUE}--- 步骤 10: 检查空间并确定配置保留选项 ---${C_RESET}"
echo '信息：按实际配置备份大小检查资源，空间不足时停止，不自动清除配置。'
KEEP_CONFIG=1
ui_section '配置数据保留'
ui_confirm Y '保留当前配置到目标介质' '目标介质使用默认配置'
read_input "$(ui_prompt Y)" confirm_keep_data
confirm_keep_data=${confirm_keep_data:-Y}  # 默认为Y
if [[ "$confirm_keep_data" =~ ^[Nn]$ ]]; then
    echo -e "${C_BLUE}信息：${C_RESET}用户选择【${C_YELLOW}不保留${C_RESET}】配置数据进行烧录。"
    KEEP_CONFIG=0
else
    echo -e "${C_BLUE}信息：${C_RESET}将尝试【${C_GREEN}保留${C_RESET}】配置数据进行烧录。"
    KEEP_CONFIG=1
fi
check_upgrade_resources || exit 1
echo -e "${C_BLUE}✅ --- 步骤 10 完成 ---${C_RESET}"
echo

write_media_image || exit 1
exit 0
