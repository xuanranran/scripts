#!/bin/bash

# --- 棰滆壊瀹氫箟 ---
C_RESET='\033[0m'       # 閲嶇疆鎵€鏈夊睘鎬?
C_RED='\033[0;31m'       # 绾㈣壊
C_GREEN='\033[0;32m'     # 缁胯壊
C_YELLOW='\033[0;33m'    # 榛勮壊
C_BLUE='\033[0;34m'      # 钃濊壊
C_CYAN='\033[0;36m'      # 闈掕壊
C_B_RED='\033[1;31m'      # 绮椾綋绾㈣壊
C_B_GREEN='\033[1;32m'    # 绮椾綋缁胯壊
C_B_YELLOW='\033[1;33m'   # 绮椾綋榛勮壊

# --- 閰嶇疆 ---
REPO="xuanranran/OpenWRT-X86_64"                                           # 鐩爣 GitHub 浠撳簱
IMAGE_FILENAME_GZ="immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz" # 鍘嬬缉鍥轰欢鐨勬枃浠跺悕
IMAGE_FILENAME_IMG="${IMAGE_FILENAME_GZ%.gz}"                             # 瑙ｅ帇鍚庣殑鍥轰欢鏂囦欢鍚?
CHECKSUM_FILENAME="sha256sums"                                             # 鏍￠獙鍜屾枃浠跺悕 (鏃?.txt 鍚庣紑)
TMP_DIR="/tmp"                                                             # 涓存椂鏂囦欢鐩綍
IMAGE_PATH_GZ="$TMP_DIR/$IMAGE_FILENAME_GZ"                                # 鍘嬬缉鍥轰欢鐨勫畬鏁磋矾寰?
IMAGE_PATH_IMG="$TMP_DIR/$IMAGE_FILENAME_IMG"                              # 瑙ｅ帇鍚庡浐浠剁殑瀹屾暣璺緞
CHECKSUM_PATH="$TMP_DIR/$CHECKSUM_FILENAME"                                # 鏍￠獙鍜屾枃浠剁殑瀹屾暣璺緞
THRESHOLD_KIB=614400                                                       # 淇濈暀鏁版嵁鐨勭┖闂撮槇鍊?(600 MiB in KiB)
MEM_THRESHOLD_KIB=1048576                                                  # 杩愯鑴氭湰鐨勬渶浣庡唴瀛橀槇鍊?(1 GiB = 1024*1024 KiB)

# GitHub 璁块棶鏂瑰紡閰嶇疆锛堝皢鍦ㄧ敤鎴烽€夋嫨鍚庤缃級
GITHUB_PROXY=""  # GitHub 浠ｇ悊鍓嶇紑

# --- 閫夋嫨 GitHub 璁块棶鏂瑰紡 ---
select_github_access() {
    echo
    echo -e "${C_CYAN}鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{C_RESET}"
    echo -e "${C_CYAN}鈺?{C_RESET}                 ${C_B_YELLOW}[#] GitHub 璁块棶鏂瑰紡閫夋嫨${C_RESET}                    ${C_CYAN}鈺?{C_RESET}"
    echo -e "${C_CYAN}鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{C_RESET}"
    echo
    echo -e "${C_CYAN}鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}閫夋嫨涓嬭浇鏂瑰紡${C_RESET}                                                      ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET}                                                                       ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET}  ${C_GREEN}1)${C_RESET} ${C_B_GREEN}gh-proxy.com 闀滃儚鍔犻€?{C_RESET} ${C_YELLOW}(鎺ㄨ崘)${C_RESET}                             ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET}     ${C_CYAN}鈥?{C_RESET} 閫傚悎缃戠粶鍙楅檺鐜                                           ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET}     ${C_CYAN}鈥?{C_RESET} 涓嬭浇閫熷害鏇村揩                                               ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET}                                                                       ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET}  ${C_BLUE}2)${C_RESET} GitHub 瀹樻柟鐩磋繛                                              ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET}     ${C_CYAN}鈥?{C_RESET} 闇€瑕佺ǔ瀹氱殑鍥介檯缃戠粶杩炴帴                                     ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET}     ${C_CYAN}鈥?{C_RESET} 鐩存帴浠庡畼鏂规湇鍔″櫒涓嬭浇                                       ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹?{C_RESET}                                                                       ${C_CYAN}鈹?{C_RESET}"
    echo -e "${C_CYAN}鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
    echo
    read -p "$(echo -e "${C_YELLOW}鉂?璇烽€夋嫨璁块棶鏂瑰紡 [1-2] (榛樿: ${C_B_GREEN}1${C_RESET}${C_YELLOW}): ${C_RESET}")" github_choice
    github_choice=${github_choice:-1}
    
    echo
    case "$github_choice" in
        1)
            echo -e "${C_B_GREEN}鉁?宸查€夋嫨锛?{C_RESET}gh-proxy.com 闀滃儚鍔犻€?
            GITHUB_PROXY="https://gh-proxy.com/"
            ;;
        2)
            echo -e "${C_B_GREEN}鉁?宸查€夋嫨锛?{C_RESET}GitHub 瀹樻柟鐩磋繛"
            GITHUB_PROXY=""
            ;;
        *)
            echo -e "${C_YELLOW}鈿?鏃犳晥閫夐」锛屼娇鐢ㄩ粯璁ゆ柟寮忥細${C_RESET}gh-proxy.com 闀滃儚鍔犻€?
            GITHUB_PROXY="https://gh-proxy.com/"
            ;;
    esac
    echo
}

# --- 閫€鍑鸿剼鏈椂娓呯悊涓存椂鏂囦欢 ---
cleanup() {
  # 杩欎釜鍑芥暟浼氬湪鑴氭湰閫€鍑烘椂鎵ц锛屾竻鐞嗘湰娆¤繍琛屼骇鐢熺殑鏂囦欢
  echo # 娓呯悊鍓嶇┖涓€琛?
  echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪娓呯悊鏈杩愯鏃朵骇鐢熺殑涓存椂鏂囦欢..."
  rm -f "$IMAGE_PATH_GZ" "$IMAGE_PATH_IMG" "$CHECKSUM_PATH"
}
# 璁剧疆闄烽槺锛氬綋鑴氭湰閫€鍑烘椂锛圗XIT淇″彿锛夛紝鎵ц cleanup 鍑芥暟
# trap cleanup EXIT # 鍗囩骇鎴愬姛涓嶄細鎵ц

# --- 璁剧疆锛氬鏋滀换浣曞懡浠ゅけ璐ュ垯绔嬪嵆閫€鍑?---
# 鍦ㄤ緷璧栭」瀹夎/妫€鏌ユ楠や腑浼氫复鏃剁鐢ㄦ璁剧疆
# set -e

# *** 鍒濆娓呯悊 /tmp ***
echo
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪娓呯悊 /tmp 鐩綍涓彲鑳藉瓨鍦ㄧ殑鏃у浐浠跺強鏍￠獙鏂囦欢..."
rm -f "$IMAGE_PATH_GZ" "$IMAGE_PATH_IMG" "$CHECKSUM_PATH"
echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}  姝ｅ湪娓呯悊 /tmp 鐩綍涓嬫墍鏈夌殑 ${C_RED}*.img${C_RESET} 鍜?${C_RED}*.gz${C_RESET} 鏂囦欢锛?
/bin/rm -f ${TMP_DIR}/*.img ${TMP_DIR}/*.gz
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}  .img / .gz 鏂囦欢娓呯悊瀹屾垚銆?
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}  姝ｅ湪娓呯悊 /tmp 鐩綍涓嬪悕绉板惈 'upgrade' 鎴?'update' 鐨?.sh 鑴氭湰..."
/bin/rm -f ${TMP_DIR}/*upgrade*.sh ${TMP_DIR}/*update*.sh
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}  鐩稿叧 .sh 鑴氭湰娓呯悊瀹屾垚銆?
echo -e "${C_B_YELLOW}娉ㄦ剰锛?{C_RESET}鑴氭湰銆愪笉浼氥€戞竻鐞?${C_RED}/root${C_RESET} 鐩綍涓嬬殑浠讳綍鏂囦欢銆傚鏈夐渶瑕佽鎵嬪姩娓呯悊銆?
echo -e "${C_B_GREEN}鍒濆娓呯悊瀹屾垚銆?{C_RESET}"
# *** 娓呯悊缁撴潫 ***

echo
echo -e "${C_BLUE}=====================================================================${C_RESET}"
echo -e "${C_BLUE} OpenWRT/ImmortalWrt 鑷姩鍗囩骇鑴氭湰 ${C_RESET}"
echo -e "${C_BLUE}=====================================================================${C_RESET}"
echo

# --- 1. 妫€鏌ュ苟灏濊瘯瀹夎渚濊禆椤?(浣跨敤瀛楃涓蹭唬鏇挎暟缁? ---
echo -e "${C_BLUE}--- 姝ラ 1: 妫€鏌ュ苟灏濊瘯瀹夎渚濊禆椤?---${C_RESET}"
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}妫€鏌ユ墍闇€宸ュ叿 (wget, jq, gunzip, awk, sha256sum, lsblk)..."

PKG_MANAGER=""
UPDATE_CMD=""
INSTALL_CMD=""
UBUS_PRESENT=0

# 妫€娴嬪寘绠＄悊鍣?(涓嶅彉)
if command -v opkg >/dev/null 2>&1; then
    PKG_MANAGER="opkg"; UPDATE_CMD="opkg update"; INSTALL_CMD="opkg install";
elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"; UPDATE_CMD="apk update"; INSTALL_CMD="apk add";
else
    echo -e "${C_B_RED}閿欒锛?{C_RESET}鏃犳硶妫€娴嬪埌 'opkg' 鎴?'apk' 鍖呯鐞嗗櫒銆? >&2; exit 1;
fi
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}妫€娴嬪埌鍖呯鐞嗗櫒: ${C_CYAN}${PKG_MANAGER}${C_RESET}"

if command -v ubus >/dev/null 2>&1; then UBUS_PRESENT=1; fi

update_run=0
# *** 淇敼鐐癸細浣跨敤瀛楃涓蹭唬鏇挎暟缁?***
missing_pkgs_str=""                 # 绌烘牸鍒嗛殧鐨勫緟瀹夎鍖呭悕
missing_cmds_found_initially_str="" # 绌烘牸鍒嗛殧鐨勫垵濮嬬己澶卞懡浠ゅ悕
required_cmds_list="wget jq gunzip awk sha256sum lsblk" # 闇€瑕佹鏌ョ殑鍛戒护鍒楄〃瀛楃涓?

echo "淇℃伅锛氭鍦ㄦ鏌ユ墍闇€鐨?鍛戒护 ($required_cmds_list) 骞惰瘑鍒渶瑕佸畨瑁呯殑 杞欢鍖?.."
for cmd_to_check in $required_cmds_list; do # 鐩存帴杩唬瀛楃涓插垪琛?
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}  妫€鏌?鍛戒护 '${C_CYAN}${cmd_to_check}${C_RESET}'..."
    if ! command -v "$cmd_to_check" >/dev/null 2>&1; then
        pkg_name=""
        if [ "$cmd_to_check" == "gunzip" ]; then pkg_name="gzip";
        elif [ "$cmd_to_check" == "sha256sum" ]; then pkg_name="coreutils";
        elif [ "$cmd_to_check" == "lsblk" ]; then pkg_name="lsblk";
        elif [ "$cmd_to_check" == "wget" ] || [ "$cmd_to_check" == "jq" ]; then pkg_name="$cmd_to_check"; fi

        echo -e "  ${C_YELLOW}>> 鍛戒护 '$cmd_to_check' 鏈壘鍒般€?{C_RESET}"
        # 杩藉姞缂哄け鍛戒护鍒板瓧绗︿覆
        [ -n "$missing_cmds_found_initially_str" ] && missing_cmds_found_initially_str="$missing_cmds_found_initially_str "
        missing_cmds_found_initially_str="$missing_cmds_found_initially_str$cmd_to_check"

        if [ -n "$pkg_name" ]; then
            echo -e "     杩欎釜鍛戒护閫氬父鐢?杞欢鍖?'${C_YELLOW}${pkg_name}${C_RESET}' 鎻愪緵銆?
            # 妫€鏌ュ寘鍚嶆槸鍚﹀凡鍦ㄥ緟瀹夎鍒楄〃瀛楃涓蹭腑 (浣跨敤 grep)
            if ! echo " $missing_pkgs_str " | grep -q " $pkg_name "; then
                 # 杩藉姞缂哄け鍖呭悕鍒板瓧绗︿覆
                 [ -n "$missing_pkgs_str" ] && missing_pkgs_str="$missing_pkgs_str "
                 missing_pkgs_str="$missing_pkgs_str$pkg_name"
            fi
        else
             echo -e "     杩欎釜鍛戒护 ('$cmd_to_check') 閫氬父鐢辩郴缁熷熀纭€鍖?(濡?busybox) 鎻愪緵銆?
        fi
    else
        echo -e "  ${C_GREEN}>> 鍛戒护 '$cmd_to_check' 宸叉壘鍒般€?{C_RESET}"
    fi
done

# --- 灏濊瘯瀹夎缂哄け鐨勮蒋浠跺寘 ---
if [ -n "$missing_pkgs_str" ]; then # 妫€鏌ュ瓧绗︿覆鏄惁闈炵┖
    echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}妫€娴嬪埌缂哄け蹇呴渶鐨勮蒋浠跺寘: ${C_CYAN}${missing_pkgs_str}${C_RESET}"
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪灏濊瘯浣跨敤 '$PKG_MANAGER' 杩涜瀹夎 (闇€瑕?root 鏉冮檺鍜岀綉缁?..."
    if [ "$update_run" -eq 0 ]; then
        echo -e "${C_BLUE}淇℃伅锛?{C_RESET}  姝ｅ湪杩愯杞欢鍖呭垪琛ㄦ洿鏂?(${C_CYAN}${UPDATE_CMD}${C_RESET})..."
        set +e; $UPDATE_CMD; update_status=$?; set -e
        if [ $update_status -ne 0 ]; then echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}  杞欢鍖呭垪琛ㄦ洿鏂板け璐?(閫€鍑虹爜 $update_status)锛屼絾浠嶅皾璇曞畨瑁?.."; fi
        update_run=1
    fi
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}  姝ｅ湪杩愯瀹夎鍛戒护 (${C_CYAN}${INSTALL_CMD} ${missing_pkgs_str}${C_RESET})..."
    set +e; $INSTALL_CMD $missing_pkgs_str; install_status=$?; set -e # 浣跨敤鍖呭悕瀛楃涓?
    if [ $install_status -ne 0 ]; then echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}  杞欢鍖呭畨瑁呭懡浠ら€€鍑虹爜涓?$install_status銆?; fi

    # 閲嶆柊妫€鏌ヤ緷璧栭」
    echo "淇℃伅锛氭鍦ㄩ噸鏂版鏌ヤ緷璧栭」..."
    final_recheck_missing_cmds_str=""
    # 杩唬鍒濆缂哄け鐨勫懡浠ゅ瓧绗︿覆
    for cmd_to_recheck in $missing_cmds_found_initially_str; do
        if ! command -v "$cmd_to_recheck" >/dev/null 2>&1; then
             # 妫€鏌ヨ繖涓懡浠ゅ搴旂殑鍖呮槸鍚﹀湪鎴戜滑灏濊瘯瀹夎鐨勫垪琛ㄩ噷
             pkg_to_find=""
             if [ "$cmd_to_recheck" == "gunzip" ]; then pkg_to_find="gzip";
             elif [ "$cmd_to_recheck" == "sha256sum" ]; then pkg_to_find="coreutils";
             elif [ "$cmd_to_recheck" == "lsblk" ]; then pkg_to_find="lsblk";
             elif [ "$cmd_to_recheck" == "wget" ]; then pkg_to_find="wget";
             elif [ "$cmd_to_recheck" == "jq" ]; then pkg_to_find="jq"; fi

             if [ -n "$pkg_to_find" ] && echo " $missing_pkgs_str " | grep -q " $pkg_to_find "; then
                  # 濡傛灉鏄垜浠皾璇曞畨瑁呯殑鍖呭搴旂殑鍛戒护锛屽苟涓旂幇鍦ㄨ繕鎵句笉鍒帮紝鍒欒褰曟渶缁堢己澶?
                  [ -n "$final_recheck_missing_cmds_str" ] && final_recheck_missing_cmds_str="$final_recheck_missing_cmds_str "
                  final_recheck_missing_cmds_str="$final_recheck_missing_cmds_str$cmd_to_recheck"
             fi
        fi
    done
    if [ -n "$final_recheck_missing_cmds_str" ]; then
         echo -e "${C_B_RED}閿欒锛?{C_RESET}蹇呴渶鐨勪緷璧栭」瀹夎澶辫触鎴栦粛鐒剁己澶便€? >&2
         echo -e "       浠嶇劧缂哄け浠ヤ笅鍛戒护: ${C_RED}${final_recheck_missing_cmds_str}${C_RESET}" >&2
         exit 1
     else
         echo -e "${C_B_GREEN}淇℃伅锛?{C_RESET}鎵€鏈夊皾璇曞畨瑁呯殑蹇呴渶杞欢鍖呬技涔庨兘宸叉垚鍔熷畨瑁呫€?
     fi
fi

# 鏈€缁堢‘璁ゆ墍鏈夊懡浠ら兘瀛樺湪
echo "淇℃伅锛氫緷璧栭」鏈€缁堟鏌?.."
final_check_missing_cmds_str=""
# *** 淇敼鐐癸細鐩存帴杩唬鍛戒护瀛楃涓插垪琛ㄨ繘琛屾渶缁堟鏌?***
for cmd_to_verify in $required_cmds_list; do
    if ! command -v "$cmd_to_verify" >/dev/null 2>&1; then
        [ -n "$final_check_missing_cmds_str" ] && final_check_missing_cmds_str="$final_check_missing_cmds_str "
        final_check_missing_cmds_str="$final_check_missing_cmds_str$cmd_to_verify"
    fi
done

if [ -n "$final_check_missing_cmds_str" ]; then # 妫€鏌ュ瓧绗︿覆鏄惁闈炵┖
    echo -e "${C_B_RED}閿欒锛?{C_RESET}鑴氭湰杩愯缂哄皯蹇呰鐨勫懡浠? ${C_RED}${final_check_missing_cmds_str}${C_RESET}" >&2
    exit 1
fi

# 鏄剧ず渚濊禆椤规鏌ユ€荤粨琛ㄦ牸
echo
echo -e "${C_CYAN}鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
echo -e "${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}渚濊禆椤规鏌ユ€荤粨${C_RESET}           ${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}鐘舵€?{C_RESET}                                   ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈺炩晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暘鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{C_RESET}"
printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "鍖呯鐞嗗櫒" "$PKG_MANAGER"
echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "蹇呴渶鍛戒护" "宸叉壘鍒版墍鏈変緷璧?($required_cmds_list)"
echo -e "${C_CYAN}鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹粹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
echo -e "${C_BLUE}--- 姝ラ 1 瀹屾垚 ---${C_RESET}"
echo

# 鍚敤涓ユ牸閿欒妫€鏌?
set -e

# --- 2. 鏄剧ず绯荤粺鍜岀鐩樹俊鎭?---
echo -e "${C_BLUE}--- 姝ラ 2: 鏄剧ず绯荤粺淇℃伅骞舵鏌ュ唴瀛?---${C_RESET}"
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪鏀堕泦褰撳墠绯荤粺淇℃伅..."
echo

# --- 鍐呭瓨妫€鏌?(蹇呴』 >= 1GiB) ---
echo -e "${C_CYAN}>> 鍐呭瓨妫€鏌?${C_RESET}"
mem_total_kib=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')

if [ -z "$mem_total_kib" ]; then
    echo -e "  ${C_YELLOW}璀﹀憡锛氭棤娉曡鍙栨€诲唴瀛樺ぇ灏忥紝璺宠繃鍐呭瓨妫€鏌ャ€?{C_RESET}"
elif [ "$mem_total_kib" -lt "$MEM_THRESHOLD_KIB" ]; then
    mem_total_mib=$(awk -v total_kib="$mem_total_kib" 'BEGIN { printf "%.0f", total_kib/1024 }')
    echo -e "  ${C_B_RED}閿欒锛氱郴缁熸€诲唴瀛?(${mem_total_mib} MiB) 浣庝簬杩愯姝よ剼鏈墍闇€鐨勬渶浣庤姹?(1024 MiB)銆?{C_RESET}" >&2
    echo -e "        涓洪伩鍏嶄笅杞芥垨瑙ｅ帇澶辫触锛岃剼鏈皢閫€鍑恒€? >&2
    exit 1
else
    mem_total_mib=$(awk -v total_kib="$mem_total_kib" 'BEGIN { printf "%.0f", total_kib/1024 }')
    echo -e "  ${C_GREEN}鍐呭瓨妫€鏌ラ€氳繃 (鎬昏: ${mem_total_mib} MiB)銆?{C_RESET}"
fi
echo

# --- 鏄剧ず绠€鍖栧唴瀛樹俊鎭?---
echo -e "${C_CYAN}>> 鍐呭瓨淇℃伅 (褰撳墠):${C_RESET}"
mem_avail_kib=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')

if [ -n "$mem_total_kib" ]; then
    if [ -n "$mem_avail_kib" ]; then
        awk -v total_kib="$mem_total_kib" -v avail_kib="$mem_avail_kib" 'BEGIN { printf "  鎬昏: %.0f MiB / 鍙敤: %.0f MiB\n", total_kib/1024, avail_kib/1024 }'
    else
         awk -v total_kib="$mem_total_kib" 'BEGIN { printf "  鎬昏: %.0f MiB\n", total_kib/1024 }'
         echo -e "  ${C_YELLOW}(鏃犳硶鑾峰彇鍙敤鍐呭瓨淇℃伅)${C_RESET}"
    fi
else
    echo -e "  ${C_YELLOW}鏃犳硶浠?/proc/meminfo 鑾峰彇鍐呭瓨淇℃伅銆?{C_RESET}"
fi
echo

# --- 鍏朵粬绯荤粺淇℃伅 ---
echo -e "${C_CYAN}>> 璁惧鍨嬪彿/涓绘澘淇℃伅:${C_RESET}"
model_info_found=0
if [ $UBUS_PRESENT -eq 1 ]; then
    ubus_output=$(ubus call system board 2>/dev/null);
    if [ -n "$ubus_output" ]; then
        model=$(echo "$ubus_output" | jq -r '.model // empty'); board=$(echo "$ubus_output" | jq -r '.board_name // empty');
        if [ -n "$model" ] || [ -n "$board" ]; then
             echo "  鏉ユ簮: ubus"; [ -n "$model" ] && echo "    鍨嬪彿: $model"; [ -n "$board" ] && echo "    涓绘澘: $board"; model_info_found=1;
        else echo -e "  ${C_YELLOW}(ubus 鏈繑鍥炴湁鏁堝瀷鍙?涓绘澘淇℃伅)${C_RESET}"; fi
    else echo -e "  ${C_YELLOW}(ubus 鍛戒护鎵ц澶辫触鎴栨棤杈撳嚭)${C_RESET}"; fi
fi
if [ $model_info_found -eq 0 ] && [ -f /tmp/sysinfo/model ]; then
    model_sysinfo=$(cat /tmp/sysinfo/model); if [ -n "$model_sysinfo" ]; then echo "  鏉ユ簮: /tmp/sysinfo/model"; echo "    鍨嬪彿: $model_sysinfo"; model_info_found=1; fi
fi
if [ $model_info_found -eq 0 ] && [ -r /proc/device-tree/model ]; then
     model_dt=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0'); if [ -n "$model_dt" ]; then echo "  鏉ユ簮: /proc/device-tree/model"; echo "    鍨嬪彿: $model_dt"; model_info_found=1; fi
fi
if [ $model_info_found -eq 0 ]; then echo -e "  ${C_YELLOW}鏃犳硶鑷姩纭畾璁惧鍨嬪彿鎴栦富鏉垮悕绉般€?{C_RESET}"; fi
echo

# CPU 淇℃伅 (绠€鍖?
echo -e "${C_CYAN}>> CPU:${C_RESET}"
grep 'model name' /proc/cpuinfo | head -n1 | sed 's/^model name[[:space:]]*: /  /' || echo -e "  ${C_YELLOW}鏃犳硶鑾峰彇 CPU 鍨嬪彿銆?{C_RESET}"
echo

# 纾佺洏鍒嗗尯鍜屾寕杞界偣淇℃伅 (lsblk)
echo -e "${C_CYAN}>> 纾佺洏鍒嗗尯甯冨眬 (lsblk):${C_RESET}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | sed 's/^/  /' || echo -e "  ${C_YELLOW}璀﹀憡锛?{C_RESET}'lsblk' 鍛戒护鎵ц澶辫触鎴栨湭瀹夎銆?
echo

# 鏂囦欢绯荤粺浣跨敤鎯呭喌鍜岀被鍨?(df)
echo -e "${C_CYAN}>> 鏂囦欢绯荤粺浣跨敤鎯呭喌 (df -hT):${C_RESET}"
df -hT | sed 's/^/  /' || echo -e "  ${C_YELLOW}鏃犳硶鑾峰彇鏂囦欢绯荤粺浣跨敤鎯呭喌銆?{C_RESET}"
echo

# 绯荤粺淇℃伅鎬荤粨琛ㄦ牸
echo
echo -e "${C_CYAN}鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
echo -e "${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}绯荤粺淇℃伅鎬荤粨${C_RESET}             ${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}璇︽儏${C_RESET}                                   ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈺炩晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暘鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{C_RESET}"

# 鍐呭瓨淇℃伅
if [ -n "$mem_total_kib" ]; then
    mem_total_mib=$(awk -v total_kib="$mem_total_kib" 'BEGIN { printf "%.0f MiB", total_kib/1024 }')
    if [ -n "$mem_avail_kib" ]; then
        mem_avail_mib=$(awk -v avail_kib="$mem_avail_kib" 'BEGIN { printf "%.0f MiB", avail_kib/1024 }')
        printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "鍐呭瓨" "鎬昏: $mem_total_mib / 鍙敤: $mem_avail_mib"
    else
        printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "鍐呭瓨" "鎬昏: $mem_total_mib"
    fi
else
    printf "${C_CYAN}鈹?{C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "鍐呭瓨" "鏃犳硶鑾峰彇"
fi

echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"

# 璁惧鍨嬪彿
if [ $model_info_found -eq 1 ]; then
    if [ -n "$model" ]; then
        # 鎴柇杩囬暱鐨勫瀷鍙峰悕
        if [ ${#model} -gt 42 ]; then
            model_display="${model:0:39}..."
        else
            model_display="$model"
        fi
        printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "璁惧鍨嬪彿" "$model_display"
    elif [ -n "$model_sysinfo" ]; then
        if [ ${#model_sysinfo} -gt 42 ]; then
            model_display="${model_sysinfo:0:39}..."
        else
            model_display="$model_sysinfo"
        fi
        printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "璁惧鍨嬪彿" "$model_display"
    else
        printf "${C_CYAN}鈹?{C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "璁惧鍨嬪彿" "鏈煡"
    fi
else
    printf "${C_CYAN}鈹?{C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "璁惧鍨嬪彿" "鏃犳硶纭畾"
fi

echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"

# /tmp 绌洪棿
tmp_size=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $2}')
tmp_avail=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$tmp_size" ] && [ -n "$tmp_avail" ]; then
    printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_GREEN}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "/tmp 绌洪棿" "鎬昏: $tmp_size / 鍙敤: $tmp_avail"
else
    printf "${C_CYAN}鈹?{C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "/tmp 绌洪棿" "鏃犳硶鑾峰彇"
fi

echo -e "${C_CYAN}鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹粹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"

echo -e "${C_BLUE}--- 姝ラ 2 瀹屾垚 ---${C_RESET}"
echo

# 閫夋嫨 GitHub 璁块棶鏂瑰紡
select_github_access

# 鍚敤涓ユ牸閿欒妫€鏌?
set -e

# --- 3. 涓存椂澧炲ぇ /tmp 鍒嗗尯 ---
echo -e "${C_BLUE}--- 姝ラ 3: 涓存椂澧炲ぇ /tmp 鍒嗗尯 ---${C_RESET}"
echo
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
echo -e "${C_B_YELLOW}[*] /tmp 鍒嗗尯鎵╁閫夐」${C_RESET}"
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
echo -e "  ${C_BLUE}鎻愮ず锛?{C_RESET}鍙互涓存椂灏?/tmp 鍒嗗尯鎵╁ぇ鍒?RAM 鐨?100%"
echo -e "  ${C_GREEN}鈥?鏈夊姪浜庡瓨鍌ㄤ笅杞藉拰瑙ｅ帇鐨勫浐浠舵枃浠?{C_RESET}"
echo -e "  ${C_YELLOW}鈥?姝ゆ洿鏀逛粎鍦ㄦ湰娆¤繍琛屾湡闂存湁鏁堬紝閲嶅惎鍚庡け鏁?{C_RESET}"
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
echo -e "\n${C_BLUE}淇℃伅锛?{C_RESET}/tmp 褰撳墠澶у皬:"
df -h /tmp | sed 's/^/  /'
echo
read -p "$(echo -e "${C_YELLOW}鉂?鏄惁涓存椂鎵╁ぇ /tmp 鍒嗗尯锛?Y/n) [榛樿: ${C_B_GREEN}鏄?{C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_resize_tmp
confirm_resize_tmp=${confirm_resize_tmp:-Y}  # 榛樿涓篩

if [[ "$confirm_resize_tmp" =~ ^[Yy]$ ]]; then
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪灏濊瘯灏?/tmp 閲嶆柊鎸傝浇涓烘洿澶у唴瀛橈紙RAM 鐨?100%锛?.."
    mount -t tmpfs -o remount,size=100% tmpfs /tmp || echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}閲嶆柊鎸傝浇 /tmp 鍙兘澶辫触鎴栦笉鍙楁敮鎸侊紝缁х画鎵ц..."
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}/tmp 鎵╁鍚庡ぇ灏?"
    df -h /tmp | sed 's/^/  /'
else
    echo -e "${C_YELLOW}淇℃伅锛?{C_RESET}鐢ㄦ埛閫夋嫨璺宠繃 /tmp 鍒嗗尯鎵╁銆?
fi
echo -e "${C_BLUE}--- 姝ラ 3 瀹屾垚 ---${C_RESET}"
echo

# --- 4. 鑾峰彇鏈€鏂?Release 淇℃伅 ---
echo -e "${C_BLUE}--- 姝ラ 4: 鑾峰彇鏈€鏂?Release 淇℃伅 ---${C_RESET}"
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪浠?GitHub 浠撳簱 '${C_CYAN}${REPO}${C_RESET}' 鑾峰彇鏈€鏂扮増鏈俊鎭?.."
API_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_INFO=$(wget -qO- --no-check-certificate "$API_URL")
if [ -z "$RELEASE_INFO" ]; then echo -e "${C_B_RED}閿欒锛?{C_RESET}鏃犳硶浠?GitHub API 鑾峰彇鐗堟湰淇℃伅銆? >&2; exit 1; fi
RELEASE_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name // "鏈煡鏍囩"')
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}鎵惧埌鏈€鏂扮増鏈爣绛? ${C_GREEN}${RELEASE_TAG}${C_RESET}"
echo -e "${C_BLUE}--- 姝ラ 4 瀹屾垚 ---${C_RESET}"
echo

# --- 5. 鏌ユ壘鍥轰欢鍜屾牎楠屾枃浠?URL ---
echo -e "${C_BLUE}--- 姝ラ 5: 鏌ユ壘鏂囦欢 URL ---${C_RESET}"
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪鏌ユ壘鍥轰欢 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 鍜屾牎楠屾枃浠?'${C_CYAN}${CHECKSUM_FILENAME}${C_RESET}'..."
IMAGE_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$IMAGE_FILENAME_GZ" '.assets[] | select(.name==$NAME) | .browser_download_url')
CHECKSUM_URL=$(echo "$RELEASE_INFO" | jq -r --arg NAME "$CHECKSUM_FILENAME" '.assets[] | select(.name==$NAME) | .browser_download_url')

SKIP_CHECKSUM=0
if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" == "null" ]; then echo -e "${C_B_RED}閿欒锛?{C_RESET}鍦ㄧ増鏈?'${C_YELLOW}${RELEASE_TAG}${C_RESET}' 涓湭鎵惧埌鍥轰欢鏂囦欢 '${C_RED}${IMAGE_FILENAME_GZ}${C_RESET}'銆? >&2; exit 1; fi
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}鎵惧埌鍥轰欢涓嬭浇閾炬帴: ${C_CYAN}${IMAGE_URL}${C_RESET}"
if [ -z "$CHECKSUM_URL" ] || [ "$CHECKSUM_URL" == "null" ]; then echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}鏈壘鍒版牎楠屾枃浠?'${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}'锛屽皢銆愯嚜鍔ㄨ烦杩囥€戞枃浠跺畬鏁存€ф牎楠屻€?; SKIP_CHECKSUM=1; else echo -e "${C_BLUE}淇℃伅锛?{C_RESET}鎵惧埌鏍￠獙鏂囦欢涓嬭浇閾炬帴: ${C_CYAN}${CHECKSUM_URL}${C_RESET}"; fi
echo -e "${C_BLUE}--- 姝ラ 5 瀹屾垚 ---${C_RESET}"
echo

# --- 6. 涓嬭浇鍓嶇‘璁?---
echo -e "${C_BLUE}--- 姝ラ 6: 涓嬭浇鍓嶇‘璁?---${C_RESET}"
echo
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
echo -e "${C_B_YELLOW}[鈫揮 鍥轰欢涓嬭浇纭${C_RESET}"
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
echo
echo -e "${C_CYAN}鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
echo -e "${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}椤圭洰${C_RESET}                     ${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}璇︽儏${C_RESET}                                   ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈺炩晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暘鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{C_RESET}"
printf "${C_CYAN}鈹?{C_RESET} ${C_CYAN}[#]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} " "鐗堟湰鏍囩"
echo -e "${C_GREEN}${RELEASE_TAG}${C_RESET}$(printf '%*s' $((42 - ${#RELEASE_TAG})) '') ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
printf "${C_CYAN}鈹?{C_RESET} ${C_CYAN}[鈫揮${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} %-42s ${C_CYAN}鈹?{C_RESET}\\n" "鍥轰欢鏂囦欢" "$(basename "$IMAGE_FILENAME_GZ")"
echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
if [ $SKIP_CHECKSUM -eq 1 ]; then 
    printf "${C_CYAN}鈹?{C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} ${C_YELLOW}%-42s${C_RESET} ${C_CYAN}鈹?{C_RESET}\\n" "鏍￠獙鏂囦欢" "鏈壘鍒?
else 
    printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} %-42s ${C_CYAN}鈹?{C_RESET}\\n" "鏍￠獙鏂囦欢" "$(basename "$CHECKSUM_FILENAME")"
fi
echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
printf "${C_CYAN}鈹?{C_RESET} ${C_CYAN}[>]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} %-42s ${C_CYAN}鈹?{C_RESET}\\n" "淇濆瓨璺緞" "$TMP_DIR"
echo -e "${C_CYAN}鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹粹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
echo
read -p "$(echo -e "\n${C_YELLOW}鉂?鏄惁寮€濮嬩笅杞芥鍥轰欢鏂囦欢锛?Y/n) [榛樿: ${C_B_GREEN}鏄?{C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_download
confirm_download=${confirm_download:-Y}  # 榛樿涓篩
if [[ ! "$confirm_download" =~ ^[Yy]$ ]]; then echo -e "${C_YELLOW}鎿嶄綔宸插彇娑堬紝鏈笅杞藉浐浠躲€?{C_RESET}"; exit 0; fi
echo

# --- 7. 涓嬭浇鏂囦欢 ---
echo -e "${C_BLUE}--- 姝ラ 7: 涓嬭浇鏂囦欢 ---${C_RESET}"
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪涓嬭浇鍘嬬缉鍥轰欢 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 鍒?'${C_CYAN}${IMAGE_PATH_GZ}${C_RESET}' ..."
wget --progress=bar:force --no-check-certificate -O "$IMAGE_PATH_GZ" "${GITHUB_PROXY}${IMAGE_URL}"
echo -e "${C_B_GREEN}淇℃伅锛?{C_RESET}鍘嬬缉鍥轰欢涓嬭浇瀹屾垚銆?

# 涓嬭浇鏍￠獙鏂囦欢
if [ $SKIP_CHECKSUM -eq 0 ]; then
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪涓嬭浇鏍￠獙鏂囦欢 '${C_CYAN}${CHECKSUM_FILENAME}${C_RESET}' 鍒?'${C_CYAN}${CHECKSUM_PATH}${C_RESET}' ..."
    set +e; wget -q --no-check-certificate -O "$CHECKSUM_PATH" "${GITHUB_PROXY}${CHECKSUM_URL}"; dl_status=$?; set -e
    if [ $dl_status -ne 0 ]; then
        echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}涓嬭浇鏍￠獙鏂囦欢 '${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}' 澶辫触锛屽皢璺宠繃鏂囦欢瀹屾暣鎬ф牎楠屻€?
        rm -f "$CHECKSUM_PATH"; SKIP_CHECKSUM=1;
    else echo -e "${C_B_GREEN}淇℃伅锛?{C_RESET}鏍￠獙鏂囦欢涓嬭浇瀹屾垚銆?; fi
fi
echo -e "${C_BLUE}--- 姝ラ 7 瀹屾垚 ---${C_RESET}"
echo

# --- 8. 鏍￠獙鍥轰欢瀹屾暣鎬?(璇㈤棶鏄惁鎵ц) ---
echo -e "${C_BLUE}--- 姝ラ 8: 鏍￠獙鍥轰欢瀹屾暣鎬?(SHA256) ---${C_RESET}"
if [ $SKIP_CHECKSUM -eq 1 ]; then
    echo -e "${C_YELLOW}淇℃伅锛氱敱浜庝箣鍓嶆楠ゆ湭鑳芥壘鍒版垨涓嬭浇鏍￠獙鏂囦欢锛岃烦杩囨枃浠跺畬鏁存€ф牎楠屻€?{C_RESET}"
else
    echo
    echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
    echo -e "${C_B_YELLOW}[#] 鏂囦欢瀹屾暣鎬ф牎楠岄€夐」${C_RESET}"
    echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
    echo -e "  ${C_BLUE}鎻愮ず锛?{C_RESET}鎵ц SHA256 鏍￠獙鍙互纭繚鍥轰欢鏂囦欢瀹屾暣鎬?
    echo -e "  ${C_GREEN}鈥?鎺ㄨ崘鎵ц鏍￠獙浠ョ‘淇濆浐浠舵湭琚崯鍧忔垨绡℃敼${C_RESET}"
    echo -e "  ${C_YELLOW}鈥?璺宠繃鏍￠獙鍙兘瀵艰嚧鍗囩骇澶辫触鎴栫郴缁熸崯鍧?{C_RESET}"
    echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
    read -p "$(echo -e "\n${C_YELLOW}鉂?鏄惁鎵ц SHA256 鍥轰欢瀹屾暣鎬ф牎楠岋紵(Y/n) [榛樿: ${C_B_GREEN}鏄?{C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_run_checksum
    confirm_run_checksum=${confirm_run_checksum:-Y}  # 榛樿涓篩

    if [[ "$confirm_run_checksum" =~ ^[Nn]$ ]]; then
        echo -e "${C_YELLOW}淇℃伅锛氱敤鎴烽€夋嫨璺宠繃鏂囦欢瀹屾暣鎬ф牎楠屻€?{C_RESET}"
        SKIP_CHECKSUM=1
    else
        echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪鏍￠獙鏂囦欢 '${C_CYAN}${IMAGE_FILENAME_GZ}${C_RESET}' 鐨?SHA256 鍝堝笇鍊?.."
        EXPECTED_SUM=$(grep "$IMAGE_FILENAME_GZ" "$CHECKSUM_PATH" | awk '{print $1}')
        if [ -z "$EXPECTED_SUM" ]; then
             echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}鍦ㄦ牎楠屾枃浠?'${C_YELLOW}${CHECKSUM_FILENAME}${C_RESET}' 涓湭鑳芥壘鍒板浐浠?'${C_YELLOW}${IMAGE_FILENAME_GZ}${C_RESET}' 鐨勬牎楠屼俊鎭€傝烦杩囨牎楠屻€?
             SKIP_CHECKSUM=1
        else
            CALCULATED_SUM=$(sha256sum "$IMAGE_PATH_GZ" | awk '{print $1}')
            echo
            echo -e "${C_CYAN}鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
            echo -e "${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}鏍￠獙椤?{C_RESET}                   ${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}SHA256 鍝堝笇鍊?{C_RESET}                          ${C_CYAN}鈹?{C_RESET}"
            echo -e "${C_CYAN}鈺炩晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暘鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{C_RESET}"
            printf "${C_CYAN}鈹?{C_RESET} ${C_CYAN}[>]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} %-42s ${C_CYAN}鈹?{C_RESET}\\n" "鏈熸湜鍊? "$EXPECTED_SUM"
            echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
            printf "${C_CYAN}鈹?{C_RESET} ${C_CYAN}[>]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} %-42s ${C_CYAN}鈹?{C_RESET}\\n" "璁＄畻鍊? "$CALCULATED_SUM"
            echo -e "${C_CYAN}鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹粹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
            echo
            if [ "$EXPECTED_SUM" == "$CALCULATED_SUM" ]; then
                echo -e "${C_B_GREEN}鉁?鏍￠獙鎴愬姛锛佹枃浠跺畬鏁淬€?{C_RESET}"
            else
                echo; echo -e "${C_B_RED}鉂?閿欒锛歋HA256 鏍￠獙鍜屼笉鍖归厤锛佹枃浠跺彲鑳藉凡鎹熷潖鎴栦笉瀹屾暣銆?{C_RESET}"; echo
                read -p "$(echo -e "${C_B_YELLOW}鉂?璀﹀憡锛氭枃浠舵牎楠屽け璐ワ紒鏄惁浠嶈缁х画鍗囩骇锛?y/N): ${C_RESET}")" confirm_checksum_fail
                if [[ ! "$confirm_checksum_fail" =~ ^[Yy]$ ]]; then echo -e "${C_YELLOW}鎿嶄綔涓銆?{C_RESET}"; exit 1; fi
                echo -e "${C_YELLOW}淇℃伅锛氱敤鎴烽€夋嫨蹇界暐鏍￠獙澶辫触骞剁户缁€?{C_RESET}"
                SKIP_CHECKSUM=1
            fi
        fi
    fi
fi
rm -f "$CHECKSUM_PATH" # 娓呯悊鏍￠獙鏂囦欢
echo -e "${C_BLUE}--- 姝ラ 8 瀹屾垚 ---${C_RESET}"
echo

# --- 9. 瑙ｅ帇鍥轰欢 ---
echo -e "${C_BLUE}--- 姝ラ 9: 瑙ｅ帇鍥轰欢 ---${C_RESET}"
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪瑙ｅ帇鍥轰欢 '${C_CYAN}${IMAGE_PATH_GZ}${C_RESET}' -> '${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}' ..."
gunzip "$IMAGE_PATH_GZ"
if [ ! -f "$IMAGE_PATH_IMG" ]; then echo -e "${C_B_RED}閿欒锛?{C_RESET}瑙ｅ帇鍚庢湭鎵惧埌鏂囦欢 '${C_RED}${IMAGE_PATH_IMG}${C_RESET}'銆? >&2; exit 1; fi
echo -e "${C_B_GREEN}淇℃伅锛?{C_RESET}鍥轰欢瑙ｅ帇瀹屾垚銆傝В鍘嬪悗鏂囦欢: '${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}'"
ls -lh "$IMAGE_PATH_IMG"
echo -e "${C_BLUE}--- 姝ラ 9 瀹屾垚 ---${C_RESET}"
echo

# --- 10. 妫€鏌ョ┖闂村苟纭畾鍗囩骇閫夐」 ---
echo -e "${C_BLUE}--- 姝ラ 10: 妫€鏌ョ┖闂村苟纭畾鍗囩骇閫夐」 ---${C_RESET}"
echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪妫€鏌?/tmp 鍙敤绌洪棿浠ョ‘瀹氬崌绾ч€夐」..."
AVAILABLE_KIB=$(df -k /tmp | awk 'NR==2 {print $4}')

SYSUPGRADE_ARGS=""
KEEP_DATA_ALLOWED=1

if [ -z "$AVAILABLE_KIB" ] || ! [[ "$AVAILABLE_KIB" =~ ^[0-9]+$ ]]; then
    echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}鏃犳硶鍑嗙‘鑾峰彇 /tmp 鍙敤绌洪棿銆傚皢鍏佽鐢ㄦ埛閫夋嫨鏄惁淇濈暀閰嶇疆銆?
    KEEP_DATA_ALLOWED=1
elif [ "$AVAILABLE_KIB" -lt "$THRESHOLD_KIB" ]; then
    echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}/tmp 鍙敤绌洪棿 (${C_YELLOW}${AVAILABLE_KIB}${C_RESET} KiB) 浣庝簬鎵€闇€闃堝€?(${C_YELLOW}${THRESHOLD_KIB}${C_RESET} KiB)銆?
    echo -e "      灏嗗己鍒躲€?{C_B_YELLOW}涓嶄繚鐣欓厤缃?{C_RESET}銆戞暟鎹繘琛屽崌绾?(浣跨敤 -n 閫夐」)銆?
    SYSUPGRADE_ARGS="-n"; KEEP_DATA_ALLOWED=0;
else
    echo -e "${C_GREEN}淇℃伅锛?{C_RESET}/tmp 鍙敤绌洪棿 (${C_GREEN}${AVAILABLE_KIB}${C_RESET} KiB) 鍏呰冻銆?
    KEEP_DATA_ALLOWED=1
fi

if [ "$KEEP_DATA_ALLOWED" -eq 1 ]; then
    echo
    echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
    echo -e "${C_B_YELLOW}[+] 閰嶇疆鏁版嵁淇濈暀閫夐」${C_RESET}"
    echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
    echo -e "  ${C_BLUE}鎻愮ず锛?{C_RESET}鎮ㄥ彲浠ラ€夋嫨鍦ㄥ崌绾ф椂淇濈暀鎴栨竻闄ら厤缃暟鎹?
    echo -e "  ${C_GREEN}鈥?淇濈暀閰嶇疆${C_RESET} - 鍗囩骇鍚庝繚鐣欏綋鍓嶇郴缁熻缃?
    echo -e "  ${C_YELLOW}鈥?娓呴櫎閰嶇疆${C_RESET} - 鍗囩骇鍚庢仮澶嶄负鍑哄巶璁剧疆"
    echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
    read -p "$(echo -e "\n${C_YELLOW}鉂?鏄惁淇濈暀閰嶇疆鏁版嵁锛?Y/n) [榛樿: ${C_B_GREEN}鏄?{C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_keep_data
    confirm_keep_data=${confirm_keep_data:-Y}  # 榛樿涓篩
    if [[ "$confirm_keep_data" =~ ^[Nn]$ ]]; then
        echo -e "${C_BLUE}淇℃伅锛?{C_RESET}鐢ㄦ埛閫夋嫨銆?{C_YELLOW}涓嶄繚鐣?{C_RESET}銆戦厤缃暟鎹繘琛屽崌绾с€?
        SYSUPGRADE_ARGS="-n"
    else
        echo -e "${C_BLUE}淇℃伅锛?{C_RESET}灏嗗皾璇曘€?{C_GREEN}淇濈暀${C_RESET}銆戦厤缃暟鎹繘琛屽崌绾с€?
        SYSUPGRADE_ARGS=""
    fi
fi
echo -e "${C_BLUE}--- 姝ラ 10 瀹屾垚 ---${C_RESET}"
echo

# --- 11. 璇㈤棶鍙€夊弬鏁板苟鏈€缁堢‘璁?---
echo -e "${C_BLUE}--- 姝ラ 11: 閰嶇疆鍙€夊弬鏁板苟鏈€缁堢‘璁?---${C_RESET}"
# 杩欎簺鍙橀噺鍦ㄥ悗闈㈡瀯寤鸿〃鏍兼椂浣跨敤锛屾澶勪笉鍐嶉渶瑕侀鍏堟瀯寤篣PGRADE_INFO瀛楃涓?

# --- 璇㈤棶鏄惁寮哄埗鍗囩骇 (-F) ---
FORCE_FLAG=""
echo -e "\n${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
echo -e "${C_B_RED}[!] 寮哄埗鍗囩骇閫夐」 (-F)${C_RESET}"
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
echo -e "  ${C_YELLOW}璀﹀憡锛?{C_RESET}'-F' 閫夐」浼氳烦杩囧浐浠跺吋瀹规€ф鏌?
echo -e "  ${C_RED}鈥?浣跨敤涓嶅吋瀹圭殑鍥轰欢鍙兘瀵艰嚧璁惧鍙樼爾锛?{C_RESET}"
echo -e "  ${C_YELLOW}鈥?浠呭湪鎮ㄥ畬鍏ㄧ‘瀹氬浐浠舵纭笖浜嗚В椋庨櫓鏃舵墠浣跨敤${C_RESET}"
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
read -p "$(echo -e "\n${C_B_YELLOW}鉂?鏄惁浣跨敤寮哄埗鍗囩骇 '-F' 閫夐」锛?y/N) [榛樿: ${C_B_GREEN}鍚?{C_RESET}${C_B_YELLOW}]: ${C_RESET}")" confirm_force
confirm_force=${confirm_force:-N}  # 榛樿涓篘
FORCE_FLAG_INFO=""
if [[ "$confirm_force" =~ ^[Yy]$ ]]; then
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}鐢ㄦ埛閫夋嫨銆?{C_B_RED}浣跨敤${C_RESET}銆戝己鍒?'-F' 閫夐」锛?
    FORCE_FLAG="-F"; FORCE_FLAG_INFO="${C_B_RED}鏄?(-F)${C_RESET}";
else
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}鏈鍗囩骇灏嗐€?{C_GREEN}涓嶄娇鐢?{C_RESET}銆戝己鍒?'-F' 閫夐」銆?
    FORCE_FLAG=""; FORCE_FLAG_INFO="${C_GREEN}鍚?{C_RESET}";
fi

# --- 璇㈤棶鏄惁璇︾粏杈撳嚭 (-v) ---
VERBOSE_FLAG=""
echo
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
echo -e "${C_B_YELLOW}[i] 璇︾粏鏃ュ織閫夐」 (-v)${C_RESET}"
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
echo -e "  ${C_BLUE}鎻愮ず锛?{C_RESET}鍚敤璇︾粏杈撳嚭鍙煡鐪嬪崌绾ц繃绋嬬殑璇︾粏淇℃伅"
echo -e "  ${C_YELLOW}鈥?涓€鑸敤鎴峰缓璁娇鐢ㄩ粯璁ゆā寮?{C_RESET}"
echo -e "${C_CYAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${C_RESET}"
read -p "$(echo -e "\n${C_YELLOW}鉂?鏄惁鍚敤璇︾粏杈撳嚭妯″紡锛?y/N) [榛樿: ${C_B_GREEN}鍚?{C_RESET}${C_YELLOW}]: ${C_RESET}")" confirm_verbose
confirm_verbose=${confirm_verbose:-N}  # 榛樿涓篘
VERBOSE_FLAG_INFO=""
if [[ "$confirm_verbose" =~ ^[Yy]$ ]]; then
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}鐢ㄦ埛閫夋嫨銆?{C_GREEN}鍚敤${C_RESET}銆戣缁嗚緭鍑烘ā寮?(-v)銆?
    VERBOSE_FLAG="-v"; VERBOSE_FLAG_INFO="${C_GREEN}鏄?(-v)${C_RESET}";
else
    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}鏈鍗囩骇灏嗐€?{C_YELLOW}涓嶅惎鐢?{C_RESET}銆戣缁嗚緭鍑烘ā寮忋€?
    VERBOSE_FLAG=""; VERBOSE_FLAG_INFO="${C_YELLOW}鍚?{C_RESET}";
fi

# --- 鏈€缁堢‘璁や笌鎵ц ---
echo
echo -e "${C_CYAN}鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{C_RESET}"
echo -e "${C_CYAN}鈺?{C_RESET}                   ${C_B_YELLOW}[=] 鍗囩骇鍓嶆渶缁堢‘璁?{C_RESET}                      ${C_CYAN}鈺?{C_RESET}"
echo -e "${C_CYAN}鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{C_RESET}"
echo

# 鏋勫缓琛ㄦ牸鍐呭
DATA_MODE_INFO=""
if [ "$SYSUPGRADE_ARGS" == "-n" ]; then
    DATA_MODE_INFO="${C_YELLOW}涓嶄繚鐣欓厤缃?(-n)${C_RESET}"
else
    DATA_MODE_INFO="${C_GREEN}淇濈暀閰嶇疆${C_RESET}"
fi

CHECKSUM_INFO=""
if [ $SKIP_CHECKSUM -eq 1 ]; then
    CHECKSUM_INFO="${C_YELLOW}璺宠繃/鏈墽琛?{C_RESET}"
else
    CHECKSUM_INFO="${C_GREEN}SHA256 宸查獙璇?{C_RESET}"
fi

echo -e "${C_CYAN}鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
echo -e "${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}椤圭洰${C_RESET}                     ${C_CYAN}鈹?{C_RESET} ${C_B_BLUE}璇︽儏${C_RESET}                                   ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈺炩晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暘鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?{C_RESET}"
printf "${C_CYAN}鈹?{C_RESET} ${C_CYAN}[>]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} %-42s ${C_CYAN}鈹?{C_RESET}\\n" "鍥轰欢鏂囦欢" "$(basename "$IMAGE_PATH_IMG")"
echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
printf "${C_CYAN}鈹?{C_RESET} ${C_CYAN}[#]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} " "鐗堟湰鏍囩"
echo -e "${C_GREEN}${RELEASE_TAG}${C_RESET}$(printf '%*s' $((42 - ${#RELEASE_TAG})) '') ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
# 閰嶇疆鏁版嵁琛屽甫鍥炬爣
if [ "$SYSUPGRADE_ARGS" == "-n" ]; then
    printf "${C_CYAN}鈹?{C_RESET} ${C_YELLOW}[脳]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} " "閰嶇疆鏁版嵁"
else
    printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET}" "閰嶇疆鏁版嵁"
fi
echo -e "${DATA_MODE_INFO}$(printf '%*s' $((42 - $(echo -e "${DATA_MODE_INFO}" | sed 's/\x1b\[[0-9;]*m//g' | wc -c) + 1)) '') ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
# 寮哄埗鍗囩骇琛?
if [[ "$FORCE_FLAG_INFO" == *"鏄?* ]]; then
    printf "${C_CYAN}鈹?{C_RESET} ${C_B_RED}[!]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} " "寮哄埗鍗囩骇 (-F)"
else
    printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鉁揮${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} " "寮哄埗鍗囩骇 (-F)"
fi
echo -e "${FORCE_FLAG_INFO}$(printf '%*s' $((42 - $(echo -e "${FORCE_FLAG_INFO}" | sed 's/\x1b\[[0-9;]*m//g' | wc -c) + 1)) '') ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
# 璇︾粏杈撳嚭琛?
if [[ "$VERBOSE_FLAG_INFO" == *"鏄?* ]]; then
    printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[i]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} " "璇︾粏杈撳嚭 (-v)"
else
    printf "${C_CYAN}鈹?{C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} " "璇︾粏杈撳嚭 (-v)"
fi
echo -e "${VERBOSE_FLAG_INFO}$(printf '%*s' $((42 - $(echo -e "${VERBOSE_FLAG_INFO}" | sed 's/\x1b\[[0-9;]*m//g' | wc -c) + 1)) '') ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹尖攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
# 鏂囦欢鏍￠獙琛?
if [ $SKIP_CHECKSUM -eq 1 ]; then
    printf "${C_CYAN}鈹?{C_RESET} ${C_YELLOW}[-]${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} " "鏂囦欢鏍￠獙"
else
    printf "${C_CYAN}鈹?{C_RESET} ${C_GREEN}[鈭歖${C_RESET} %-20s ${C_CYAN}鈹?{C_RESET} " "鏂囦欢鏍￠獙"
fi
echo -e "${CHECKSUM_INFO}$(printf '%*s' $((42 - $(echo -e "${CHECKSUM_INFO}" | sed 's/\x1b\[[0-9;]*m//g' | wc -c) + 1)) '') ${C_CYAN}鈹?{C_RESET}"
echo -e "${C_CYAN}鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹粹攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?{C_RESET}"
echo

if [ -z "$SYSUPGRADE_ARGS" ]; then
    echo -e "${C_YELLOW}[*] 鎻愮ず锛?{C_RESET}寤鸿鎻愬墠澶囦唤閲嶈鏁版嵁"
fi
echo -e "${C_B_RED}[!] 璀﹀憡锛?{C_RESET}鍗囩骇杩囩▼涓鍔″繀淇濇寔璁惧閫氱數锛屼笉瑕佷腑鏂搷浣滐紒"
echo
read -p "$(echo -e "${C_B_GREEN}鉂?纭寮€濮嬫墽琛?sysupgrade 鍗囩骇锛?Y/n) [榛樿: ${C_B_GREEN}鏄?{C_RESET}]: ${C_RESET}")" confirm_upgrade
confirm_upgrade=${confirm_upgrade:-Y}  # 榛樿涓篩

if [[ "$confirm_upgrade" =~ ^[Yy]$ ]]; then
    # 鏋勯€犳渶缁堟墽琛屼俊鎭?
    MSG_DESC="淇℃伅锛氭鍦ㄦ墽琛?sysupgrade 鍛戒护 ("
    FLAG_DESC=""
    [ -n "$FORCE_FLAG" ] && FLAG_DESC="${C_B_RED}寮哄埗${C_RESET}${FLAG_DESC}"
    [ -n "$VERBOSE_FLAG" ] && FLAG_DESC="${FLAG_DESC}${FLAG_DESC:+, }${C_GREEN}璇︾粏${C_RESET}" # Add comma if needed

    if [ -z "$SYSUPGRADE_ARGS" ]; then DATA_DESC="${C_GREEN}淇濈暀鏁版嵁${C_RESET}"; else DATA_DESC="${C_YELLOW}涓嶄繚鐣欐暟鎹?{C_RESET}"; fi
    if [ -n "$FLAG_DESC" ]; then MSG_DESC="${MSG_DESC}${FLAG_DESC}, ${DATA_DESC})..."; else MSG_DESC="${MSG_DESC}${DATA_DESC})..."; fi
    echo -e "$MSG_DESC"

    # 鎵ц鍛戒护
    
    if [ -n "$FORCE_FLAG" ]; then
        # 濡傛灉鍚敤浜嗗己鍒跺崌绾э紝浣跨敤 exec 鐩存帴鏇挎崲杩涚▼锛岄槻姝?SSH 鏂紑鍚庣殑璇姤閿欒
        echo -e "${C_B_GREEN}鉁?淇℃伅锛歴ysupgrade 鍛戒护宸插惎鍔ㄣ€係SH 杩炴帴鍗冲皢鏂紑锛岃澶囧皢閲嶅惎銆?{C_RESET}"
        echo
        exec sysupgrade $FORCE_FLAG $VERBOSE_FLAG $SYSUPGRADE_ARGS "$IMAGE_PATH_IMG"
    else
        # 鏈惎鐢ㄥ己鍒跺崌绾?
        # 鍏堣繘琛屾ā鎷熸祴璇?(-T) 浠ユ鏌ュ浐浠舵湁鏁堟€?
        echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪鎵ц鍥轰欢鍏煎鎬ч妫€鏌?(sysupgrade -T)..."
        
        # 涓存椂绂佺敤 strict error checking
        set +e
        sysupgrade -T $SYSUPGRADE_ARGS "$IMAGE_PATH_IMG" >/dev/null 2>&1
        test_status=$?
        set -e
        
        if [ $test_status -eq 0 ]; then
            # 鏍￠獙閫氳繃
            echo -e "${C_B_GREEN}鉁?淇℃伅锛氬浐浠舵牎楠岄€氳繃銆俿ysupgrade 鍛戒护宸插惎鍔ㄣ€係SH 杩炴帴鍗冲皢鏂紑锛岃澶囧皢閲嶅惎銆?{C_RESET}"
            echo
            # 浣跨敤 exec 鎵ц鐪熸鐨勫崌绾?
            exec sysupgrade $VERBOSE_FLAG $SYSUPGRADE_ARGS "$IMAGE_PATH_IMG"
        else
            # 鏍￠獙澶辫触锛屾墽琛屽師鍛戒护浠ユ樉绀洪敊璇苟杩涘叆閿欒澶勭悊娴佺▼
            echo -e "${C_YELLOW}璀﹀憡锛?{C_RESET}鍥轰欢棰勬鏌ユ湭閫氳繃锛屾鍦ㄦ墽琛屽父瑙勫崌绾т互鏄剧ず璇︾粏閿欒..."
            set +e
            sysupgrade $FORCE_FLAG $VERBOSE_FLAG $SYSUPGRADE_ARGS "$IMAGE_PATH_IMG"
            sysupgrade_status=$?
            set -e
        fi

        if [ $sysupgrade_status -eq 0 ]; then
            echo # 鎹㈣
            echo -e "${C_B_GREEN}鉁?淇℃伅锛歴ysupgrade 鍛戒护宸叉墽琛屻€傚鏋滄垚鍔燂紝绯荤粺灏嗕細閲嶅惎銆?{C_RESET}"
            exit 0
        else
            echo
            echo -e "${C_B_RED}鉂?閿欒锛歴ysupgrade 鍛戒护鎵ц澶辫触 (閫€鍑虹爜 $sysupgrade_status)銆?{C_RESET}"
            
            # 濡傛灉涔嬪墠娌＄敤杩?-F锛岃闂槸鍚﹀皾璇曞己鍒跺崌绾?
            if [[ "$FORCE_FLAG" != "-F" ]]; then
                echo -e "${C_YELLOW}鍒嗘瀽锛氬崌绾уけ璐ラ€氬父鏄洜涓哄浐浠剁増鏈鏌ヤ笉閫氳繃 (濡?'Image metadata not present' 鎴?'Image check failed')銆?{C_RESET}"
                echo -e "${C_YELLOW}      杩欏湪璺ㄧ増鏈崌绾ф垨鍒峰啓涓嶅悓鍥轰欢鏃跺緢甯歌銆?{C_RESET}"
                
                read -p "$(echo -e "\n${C_B_YELLOW}鉂?鏄惁灏濊瘯浣跨敤寮哄埗鍗囩骇 '-F' 閫夐」閲嶈瘯锛?y/N) [榛樿: ${C_B_GREEN}鏄?{C_RESET}${C_B_YELLOW}]: ${C_RESET}")" retry_force
                retry_force=${retry_force:-Y}
                
                if [[ "$retry_force" =~ ^[Yy]$ ]]; then
                    echo -e "${C_BLUE}淇℃伅锛?{C_RESET}姝ｅ湪灏濊瘯浣跨敤寮哄埗鍗囩骇閫夐」 (-F) 閲嶈瘯..."
                    FORCE_FLAG="-F"
                    
                    echo -e "${C_B_GREEN}鉁?淇℃伅锛氭鍦ㄦ墽琛屽己鍒跺崌绾у懡浠ゃ€傝繛鎺ュ嵆灏嗘柇寮€锛岃绛夊緟璁惧閲嶅惎...${C_RESET}"
                    echo
                    
                    # 浣跨敤 exec 鏇挎崲褰撳墠 shell 杩涚▼
                    exec sysupgrade $FORCE_FLAG $VERBOSE_FLAG $SYSUPGRADE_ARGS "$IMAGE_PATH_IMG"
                else
                    echo -e "${C_YELLOW}淇℃伅锛氱敤鎴烽€夋嫨涓嶉噸璇曘€傝剼鏈€€鍑恒€?{C_RESET}"
                    exit 1
                fi
            else
                exit 1
            fi
        fi
    fi
else
    echo # 鎹㈣
    echo -e "${C_YELLOW}鎿嶄綔宸插彇娑堛€?{C_RESET}瑙ｅ帇鍚庣殑鍥轰欢鏂囦欢淇濈暀鍦?'${C_CYAN}${IMAGE_PATH_IMG}${C_RESET}'锛屾偍鍙互鎵嬪姩鍗囩骇鎴栧垹闄ゅ畠銆?
    exit 0
fi

exit 0 # 澶囩敤閫€鍑虹偣
