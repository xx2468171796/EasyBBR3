#!/usr/bin/env bash
#===============================================================================
#
#          FILE: easybbr3.sh
#
#         USAGE: sudo ./easybbr3.sh [options]
#                wget -qO- https://raw.githubusercontent.com/xx2468171796/EasyBBR3/main/easybbr3.sh | sudo bash
#
#   DESCRIPTION: BBR3 一键安装脚本 - 支持 BBR/BBR2/BBR3 TCP 拥塞控制
#                支持 Debian 10-13, Ubuntu 16.04-24.04, RHEL/CentOS 7-9
#
#       OPTIONS: --help 查看完整帮助
#  REQUIREMENTS: root 权限, bash 4.0+
#        AUTHOR: 孤独制作
#       VERSION: 2.1.1
#       CREATED: 2024
#      REVISION: 2026-04-14
#       LICENSE: MIT
#      TELEGRAM: https://t.me/+RZMe7fnvvUg1OWJl
#        GITHUB: https://github.com/xx2468171796
#
#   功能说明: BBR3 TCP 拥塞控制一键安装与优化脚本
#             - 支持多种场景模式（代理/视频/游戏等）
#             - 自动检测最佳算法和参数
#             - 内核安装验证与回滚机制
#
#   其他工具: PVE Tools 一键脚本
#             wget https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh
#             chmod +x pvetools.sh && ./pvetools.sh
#
#===============================================================================

set -uo pipefail

# 注意：不使用 set -e，因为某些命令预期可能失败（如 ping、modprobe 等）
# 我们通过显式检查返回值来处理错误

# Bash 版本检查
if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    echo "[错误] 此脚本需要 Bash 4.0 或更高版本" >&2
    echo "当前版本: ${BASH_VERSION}" >&2
    exit 1
fi

#===============================================================================
# 版本信息
#===============================================================================
readonly SCRIPT_VERSION="2.1.1"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
readonly GITHUB_URL="https://github.com/xx2468171796"
readonly GITHUB_RAW="https://raw.githubusercontent.com/xx2468171796/EasyBBR3/main"

#===============================================================================
# 颜色定义
#===============================================================================
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly WHITE=''
    readonly BOLD=''
    readonly DIM=''
    readonly NC=''
fi

#===============================================================================
# 图标定义
#===============================================================================
readonly ICON_OK="✓"
readonly ICON_FAIL="✗"
readonly ICON_WARN="⚠"
readonly ICON_INFO="ℹ"
readonly ICON_ARROW="➜"
readonly ICON_STAR="★"
readonly ICON_GEAR="⚙"
readonly ICON_NET="🌐"
readonly ICON_DISK="💾"
readonly ICON_CPU="🖥"

#===============================================================================
# 配置文件路径
#===============================================================================
readonly SYSCTL_FILE="/etc/sysctl.d/99-bbr.conf"
readonly BACKUP_DIR="/etc/sysctl.d/bbr-backups"
# LOG_FILE 不是 readonly: log_init 检测到符号链接攻击时可能改写为 fallback 路径
LOG_FILE="/var/log/bbr3-script.log"
readonly LOG_MAX_SIZE=1048576  # 1MB
readonly SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/xx2468171796/EasyBBR3/main/easybbr3.sh"

#===============================================================================
# 全局变量 - 系统信息
#===============================================================================
DIST_ID=""
DIST_VER=""
DIST_CODENAME=""
ARCH_ID=""
VIRT_TYPE=""
KERNEL_VER=""
PKG_MANAGER=""

#===============================================================================
# 全局变量 - 预检状态
#===============================================================================
PRECHECK_ROOT=0
PRECHECK_OS=0
PRECHECK_ARCH=0
PRECHECK_VIRT=0
PRECHECK_NETWORK=0
PRECHECK_DNS=0
PRECHECK_DISK=0
PRECHECK_DEPS=0
PRECHECK_UPDATE=0
declare -a PRECHECK_MESSAGES=()
APT_UPDATE_DONE=0
NETWORK_REGION_DETECTED=0

#===============================================================================
# 全局变量 - 配置
#===============================================================================
CURRENT_ALGO=""
CURRENT_QDISC=""
AVAILABLE_ALGOS=""
CHOSEN_ALGO=""
CHOSEN_QDISC=""
APPLY_NOW=0
NON_INTERACTIVE=0
DEBUG_MODE=0
PIPE_MODE=0
MENU_CHOICE=""
APPLY_GUIDANCE_SHOWN=0
ALLOW_UNVERIFIED_UPDATE=0

#===============================================================================
# 全局变量 - 缓冲区调优
#===============================================================================
TUNE_RMEM_MAX=""
TUNE_WMEM_MAX=""
TUNE_TCP_RMEM_HIGH=""
TUNE_TCP_WMEM_HIGH=""

#===============================================================================
# 全局变量 - 场景模式
#===============================================================================
SCENE_MODE=""  # balanced, communication, video, concurrent, speed
SCENE_RECOMMENDED=""  # 推荐的场景模式
SERVER_CPU_CORES=0
SERVER_MEMORY_MB=0
SERVER_BANDWIDTH_MBPS=0
SERVER_TCP_CONNECTIONS=0

#===============================================================================
# 全局变量 - 智能优化
#===============================================================================
SMART_DETECTED_BANDWIDTH=0      # 实测带宽 (Mbps)
SMART_DETECTED_RTT=0            # 检测的 RTT (ms)
SMART_OPTIMAL_BUFFER=0          # 计算的最优缓冲区 (bytes)
SMART_OPTIMAL_MTU=1500          # 检测的最优 MTU
SMART_HARDWARE_SCORE=""         # 硬件评分: low/medium/high
SMART_MSS_CLAMP_ENABLED=0       # MSS Clamp 是否启用

#===============================================================================
# 全局变量 - 镜像源
#===============================================================================
MIRROR_REGION=""  # cn/intl/auto
MIRROR_URL=""
USE_CHINA_MIRROR=0

#===============================================================================
# 国内镜像源列表
#===============================================================================
declare -A MIRRORS_CN=(
    ["tsinghua"]="https://mirrors.tuna.tsinghua.edu.cn"
    ["aliyun"]="https://mirrors.aliyun.com"
    ["ustc"]="https://mirrors.ustc.edu.cn"
    ["huawei"]="https://repo.huaweicloud.com"
)

#===============================================================================
# 支持的系统版本
#===============================================================================
readonly SUPPORTED_DEBIAN="10 11 12 13"
readonly SUPPORTED_UBUNTU="16.04 18.04 20.04 22.04 24.04"
readonly SUPPORTED_RHEL="7 8 9"

#===============================================================================
# 必要依赖列表
#===============================================================================
readonly REQUIRED_DEPS="curl wget gnupg ca-certificates"


#===============================================================================
# UI 输出函数
#===============================================================================

# 显示 ASCII Logo
print_logo() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ____  ____  ____  _____    _____           _       __
   / __ )/ __ )/ __ \/__  /   / ___/__________(_)___  / /_
  / __  / __  / /_/ /  / /    \__ \/ ___/ ___/ / __ \/ __/
 / /_/ / /_/ / _, _/  / /    ___/ / /__/ /  / / /_/ / /_
/_____/_____/_/ |_|  /_/    /____/\___/_/  /_/ .___/\__/
                                            /_/
EOF
    echo -e "${NC}"
    echo -e "${DIM}Version ${SCRIPT_VERSION} | 作者: 孤独制作${NC}"
    echo -e "${DIM}电报群: https://t.me/+RZMe7fnvvUg1OWJl${NC}"
    echo -e "${DIM}PVE工具: https://github.com/xx2468171796/pvetools${NC}"
    echo
}

# 显示带边框的标题
print_header() {
    local title="$1"
    local width=60
    local title_len=${#title}
    local padding=$(( (width - title_len - 2) / 2 ))
    local right_padding=$((width - padding - title_len))
    
    echo
    # 使用更兼容的方式生成重复字符
    local border_line=""
    local i
    for ((i=0; i<width; i++)); do border_line+="═"; done
    
    local left_spaces=""
    for ((i=0; i<padding; i++)); do left_spaces+=" "; done
    
    local right_spaces=""
    for ((i=0; i<right_padding; i++)); do right_spaces+=" "; done
    
    echo -e "${CYAN}╔${border_line}╗${NC}"
    echo -e "${CYAN}║${NC}${left_spaces}${BOLD}${title}${NC}${right_spaces}${CYAN}║${NC}"
    echo -e "${CYAN}╚${border_line}╝${NC}"
    echo
}

# 显示分隔线
print_separator() {
    local line=""
    local i
    for ((i=0; i<60; i++)); do line+="─"; done
    echo -e "${DIM}${line}${NC}"
}

# 信息输出
print_info() {
    echo -e "${BLUE}${ICON_INFO}${NC} $*"
}

# 成功输出
print_success() {
    echo -e "${GREEN}${ICON_OK}${NC} $*"
}

# 警告输出
print_warn() {
    echo -e "${YELLOW}${ICON_WARN}${NC} $*"
}

# 错误输出
print_error() {
    echo -e "${RED}${ICON_FAIL}${NC} $*" >&2
}

# 步骤输出
print_step() {
    echo -e "${PURPLE}${ICON_ARROW}${NC} $*"
}

# 调试输出
print_debug() {
    if [[ $DEBUG_MODE -eq 1 ]]; then
        echo -e "${DIM}[DEBUG] $*${NC}" >&2
    fi
}

# 显示格式化菜单
print_menu() {
    local title="$1"
    shift
    local items=("$@")
    
    echo
    echo -e "${BOLD}${title}${NC}"
    print_separator
    
    local i=1
    for item in "${items[@]}"; do
        echo -e "  ${CYAN}${i})${NC} ${item}"
        ((i++))
    done
    
    echo -e "  ${CYAN}0)${NC} 返回/退出"
    print_separator
}

# 显示对齐表格
print_table() {
    local -n data=$1
    local col1_width=${2:-20}
    local col2_width=${3:-40}
    
    for key in "${!data[@]}"; do
        printf "%b%-${col1_width}s%b : %s\n" "$CYAN" "$key" "$NC" "${data[$key]}"
    done
}

# 显示键值对
print_kv() {
    local key="$1"
    local value="$2"
    local width=${3:-15}
    printf "  %b%-${width}s%b : %s\n" "$DIM" "$key" "$NC" "$value"
}

# 显示状态行
print_status() {
    local label="$1"
    local status="$2"
    local width=${3:-40}
    
    printf "  %-${width}s " "$label"
    case "$status" in
        ok|pass|passed|success)
            echo -e "[${GREEN}${ICON_OK} 通过${NC}]"
            ;;
        fail|failed|error)
            echo -e "[${RED}${ICON_FAIL} 失败${NC}]"
            ;;
        warn|warning)
            echo -e "[${YELLOW}${ICON_WARN} 警告${NC}]"
            ;;
        skip|skipped)
            echo -e "[${DIM}跳过${NC}]"
            ;;
        *)
            echo -e "[${status}]"
            ;;
    esac
}

# 显示进度条
show_progress() {
    local current=$1
    local total=$2
    local width=${3:-40}
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    local filled_bar="" empty_bar=""
    local i
    for ((i=0; i<filled; i++)); do filled_bar+="█"; done
    for ((i=0; i<empty; i++)); do empty_bar+="░"; done
    
    printf "\r  [%b%s%b%s] %3d%%" "$GREEN" "$filled_bar" "$NC" "$empty_bar" "$percent"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# 确认对话框
confirm() {
    local prompt="${1:-确认继续？}"
    local default="${2:-n}"
    
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi
    
    local yn_hint
    if [[ "$default" == "y" ]]; then
        yn_hint="[Y/n]"
    else
        yn_hint="[y/N]"
    fi
    
    while true; do
        echo -en "${YELLOW}${ICON_WARN}${NC} ${prompt} ${yn_hint} "
        read -r answer
        answer=${answer:-$default}
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "请输入 y 或 n" ;;
        esac
    done
}

# 读取用户输入
read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result
    
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        echo "$default"
        return
    fi
    
    if [[ -n "$default" ]]; then
        echo -en "${CYAN}${ICON_ARROW}${NC} ${prompt} [${default}]: "
    else
        echo -en "${CYAN}${ICON_ARROW}${NC} ${prompt}: "
    fi
    
    read -r result
    echo "${result:-$default}"
}

# 读取菜单选择 - 结果存储在全局变量 MENU_CHOICE 中
read_choice() {
    local prompt="${1:-请选择}"
    local max="$2"
    local default="${3:-}"
    
    MENU_CHOICE=""
    
    while true; do
        if [[ -n "$default" ]]; then
            echo -en "${CYAN}${ICON_ARROW}${NC} ${prompt} [${default}]: " >&2
        else
            echo -en "${CYAN}${ICON_ARROW}${NC} ${prompt}: " >&2
        fi
        
        read -r MENU_CHOICE
        MENU_CHOICE=${MENU_CHOICE:-$default}
        
        if [[ "$MENU_CHOICE" =~ ^[0-9]+$ ]] && [[ $MENU_CHOICE -ge 0 ]] && [[ $MENU_CHOICE -le $max ]]; then
            return 0
        fi
        
        print_error "无效选择，请输入 0-${max} 之间的数字"
    done
}


#===============================================================================
# 日志模块
#===============================================================================

# 初始化日志
#
# 安全说明 (v2.1.1): >> 跟随符号链接,原代码可被本地非特权用户事先在
# /var/log/bbr3-script.log 处放符号链接到敏感文件(/etc/shadow 等),
# 然后等管理员以 root 运行脚本时,日志写入会附加到目标文件。
# 因此写入前必须确保 LOG_FILE 不是符号链接,若是则禁用日志或换用专属目录。
log_init() {
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"

    # 创建日志目录
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi

    # 拒绝符号链接 - 若是,改用 /tmp 下的独占文件,避免提权写入风险
    if [[ -L "$LOG_FILE" ]]; then
        local fallback
        fallback=$(mktemp /tmp/bbr3-script-XXXXXX.log 2>/dev/null) || fallback=""
        if [[ -n "$fallback" ]]; then
            LOG_FILE="$fallback"
        else
            LOG_FILE="/dev/null"
        fi
    fi

    # 日志轮转
    if [[ -f "$LOG_FILE" && ! -L "$LOG_FILE" ]]; then
        local size
        # Linux 使用 -c%s，macOS/BSD 使用 -f%z
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ $size -gt $LOG_MAX_SIZE ]]; then
            mv -- "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
        fi
    fi

    # 创建新 log 文件,显式 0640 权限,O_NOFOLLOW 行为通过先 rm 再 touch 模拟
    if [[ "$LOG_FILE" != "/dev/null" ]]; then
        # 即使被竞争创建为符号链接,install -m 也会拒绝写入符号链接目标
        install -m 0640 /dev/null "$LOG_FILE" 2>/dev/null || true
    fi

    # 写入日志头
    {
        echo "========================================"
        echo "BBR3 Script Log - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Version: ${SCRIPT_VERSION}"
        echo "========================================"
    } >> "$LOG_FILE" 2>/dev/null || true
}

# 写入日志
_log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # 转义换行/回车防止 log injection 污染后续行
    msg=${msg//$'\n'/ }
    msg=${msg//$'\r'/ }

    echo "[${timestamp}] [${level}] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}

# 记录信息
log_info() {
    _log "INFO" "$@"
}

# 记录警告
log_warn() {
    _log "WARN" "$@"
}

# 记录错误
log_error() {
    _log "ERROR" "$@"
}

# 记录调试信息
log_debug() {
    if [[ $DEBUG_MODE -eq 1 ]]; then
        _log "DEBUG" "$@"
    fi
}

# 记录命令执行
log_cmd() {
    local cmd="$1"
    local output="${2:-}"
    local exit_code="${3:-0}"
    
    _log "CMD" "Command: ${cmd}"
    if [[ -n "$output" ]]; then
        _log "CMD" "Output: ${output}"
    fi
    _log "CMD" "Exit code: ${exit_code}"
}

#===============================================================================
# 错误处理
#===============================================================================

# 清理函数
cleanup() {
    # 删除临时文件
    rm -f /tmp/bbr3-*.tmp 2>/dev/null || true
    # 恢复终端设置
    stty sane 2>/dev/null || true
}

# 致命错误处理
die() {
    local msg="$1"
    local code="${2:-1}"
    
    log_error "$msg"
    print_error "$msg"
    cleanup
    exit "$code"
}

# 设置信号处理
setup_traps() {
    trap cleanup EXIT
    trap 'echo; die "用户中断操作" 130' INT
    trap 'die "收到终止信号" 143' TERM
}

# 临界区: 屏蔽 SIGINT/SIGTERM 防止 Ctrl-C 留下半生成的 initramfs 或半写的 grub.cfg
# 使用方式:
#   critical_section_enter
#   trap critical_section_exit RETURN  # 或手动配对
#   ... 危险命令 ...
#   critical_section_exit
CRITICAL_SECTION_DEPTH=0
critical_section_enter() {
    if [[ $CRITICAL_SECTION_DEPTH -eq 0 ]]; then
        trap '' INT TERM
    fi
    ((++CRITICAL_SECTION_DEPTH))
}
critical_section_exit() {
    if [[ $CRITICAL_SECTION_DEPTH -gt 0 ]]; then
        ((--CRITICAL_SECTION_DEPTH))
    fi
    if [[ $CRITICAL_SECTION_DEPTH -eq 0 ]]; then
        trap 'echo; die "用户中断操作" 130' INT
        trap 'die "收到终止信号" 143' TERM
    fi
}

# 安全执行命令（允许失败）- 名字保留 v2.1.0 兼容,实际是 ignore_errors
safe_run() {
    "$@" || true
}
# 推荐新代码使用这个更清晰的别名
ignore_errors() {
    "$@" || true
}


#===============================================================================
# 系统检测模块
#===============================================================================

# 版本比较函数（A >= B 返回真）
version_ge() {
    local ver_a="$1"
    local ver_b="$2"
    
    # 提取纯版本号部分（去除后缀如 -xanmod1）
    ver_a="${ver_a%%[-+]*}"
    ver_b="${ver_b%%[-+]*}"
    
    # 使用 sort -V 进行版本比较
    [[ "$(printf '%s\n%s\n' "$ver_b" "$ver_a" | sort -V | head -n1)" == "$ver_b" ]]
}

# 版本比较函数（A > B 返回真）
version_gt() {
    local ver_a="$1"
    local ver_b="$2"
    
    if [[ "$ver_a" == "$ver_b" ]]; then
        return 1
    fi
    version_ge "$ver_a" "$ver_b"
}

# 检测操作系统
detect_os() {
    log_debug "开始检测操作系统..."
    
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DIST_ID="${ID:-unknown}"
        DIST_VER="${VERSION_ID:-unknown}"
        DIST_CODENAME="${VERSION_CODENAME:-}"
        
        # 尝试从 lsb_release 获取代号
        if [[ -z "$DIST_CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
            DIST_CODENAME=$(lsb_release -sc 2>/dev/null || true)
        fi
    elif [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS 旧版本
        if grep -qi "centos" /etc/redhat-release; then
            DIST_ID="centos"
        elif grep -qi "red hat" /etc/redhat-release; then
            DIST_ID="rhel"
        else
            DIST_ID="rhel"
        fi
        DIST_VER=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
        DIST_VER="${DIST_VER%%.*}"
    elif [[ -f /etc/debian_version ]]; then
        DIST_ID="debian"
        DIST_VER=$(cat /etc/debian_version)
    else
        DIST_ID="unknown"
        DIST_VER="unknown"
    fi
    
    # 标准化发行版 ID
    DIST_ID="${DIST_ID,,}"  # 转小写
    
    # 获取内核版本
    KERNEL_VER="$(uname -r)"
    
    # 确定包管理器
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    else
        PKG_MANAGER="unknown"
    fi
    
    log_info "检测到系统: ${DIST_ID} ${DIST_VER} (${DIST_CODENAME:-N/A})"
    log_info "内核版本: ${KERNEL_VER}"
    log_info "包管理器: ${PKG_MANAGER}"
}

# 检测 CPU 架构
detect_arch() {
    log_debug "开始检测 CPU 架构..."
    
    if command -v dpkg >/dev/null 2>&1; then
        ARCH_ID=$(dpkg --print-architecture 2>/dev/null || true)
    fi
    
    if [[ -z "${ARCH_ID:-}" ]]; then
        local machine
        machine=$(uname -m)
        case "$machine" in
            x86_64|amd64)
                ARCH_ID="amd64"
                ;;
            aarch64|arm64)
                ARCH_ID="arm64"
                ;;
            armv7*|armhf)
                ARCH_ID="armhf"
                ;;
            i386|i686)
                ARCH_ID="i386"
                ;;
            *)
                ARCH_ID="$machine"
                ;;
        esac
    fi
    
    log_info "CPU 架构: ${ARCH_ID}"
}

# 检测虚拟化环境
detect_virt() {
    log_debug "开始检测虚拟化环境..."
    
    VIRT_TYPE="none"
    
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    elif command -v virt-what >/dev/null 2>&1; then
        VIRT_TYPE=$(virt-what 2>/dev/null | head -n1 || echo "none")
    elif [[ -f /proc/1/cgroup ]]; then
        if grep -q docker /proc/1/cgroup 2>/dev/null; then
            VIRT_TYPE="docker"
        elif grep -q lxc /proc/1/cgroup 2>/dev/null; then
            VIRT_TYPE="lxc"
        fi
    fi
    
    # 检测 WSL
    if grep -qi microsoft /proc/version 2>/dev/null; then
        VIRT_TYPE="wsl"
    fi
    
    # 检测 OpenVZ
    if [[ -f /proc/vz/veinfo ]]; then
        VIRT_TYPE="openvz"
    fi
    
    [[ "$VIRT_TYPE" == "none" ]] && VIRT_TYPE="物理机/未知"
    
    log_info "虚拟化环境: ${VIRT_TYPE}"
}

# 检查是否支持安装第三方内核
is_kernel_install_supported() {
    # 仅支持 amd64 架构
    if [[ "$ARCH_ID" != "amd64" ]]; then
        return 1
    fi
    
    # 容器环境不支持
    case "$VIRT_TYPE" in
        openvz|lxc|docker|container|wsl)
            return 1
            ;;
    esac
    
    return 0
}

# 检查 Debian 版本是否支持
is_supported_debian() {
    [[ "$DIST_ID" == "debian" ]] || return 1
    
    local ver="${DIST_VER%%.*}"
    case "$ver" in
        10|11|12|13) return 0 ;;
        *) return 1 ;;
    esac
}

# 检查 Ubuntu 版本是否支持
is_supported_ubuntu() {
    [[ "$DIST_ID" == "ubuntu" ]] || return 1
    
    case "$DIST_VER" in
        16.04*|18.04*|20.04*|22.04*|24.04*) return 0 ;;
        *) return 1 ;;
    esac
}

# 检查 RHEL 系版本是否支持
is_supported_rhel() {
    case "$DIST_ID" in
        centos|rhel|rocky|almalinux|fedora) ;;
        *) return 1 ;;
    esac
    
    local ver="${DIST_VER%%.*}"
    case "$ver" in
        7|8|9) return 0 ;;
        *) return 1 ;;
    esac
}

# 检查系统是否在支持列表中
is_system_supported() {
    is_supported_debian && return 0
    is_supported_ubuntu && return 0
    is_supported_rhel && return 0
    return 1
}

# 获取系统友好名称
get_os_pretty_name() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${PRETTY_NAME:-${DIST_ID} ${DIST_VER}}"
    else
        echo "${DIST_ID} ${DIST_VER}"
    fi
}

# 版本比较函数：检查 $1 == $2
version_eq() {
    local ver1="${1:-0}"
    local ver2="${2:-0}"
    
    # 提取纯数字版本部分
    ver1="${ver1%%-*}"
    ver2="${ver2%%-*}"
    
    [[ "$ver1" == "$ver2" ]]
}


#===============================================================================
# 环境预检模块
#===============================================================================

# 检查 root 权限
precheck_root() {
    log_debug "检查 root 权限..."
    
    if [[ $(id -u) -ne 0 ]]; then
        PRECHECK_ROOT=2
        PRECHECK_MESSAGES+=("需要 root 权限运行此脚本")
        return 1
    fi
    
    PRECHECK_ROOT=0
    return 0
}

# 检测网络连通性
precheck_network() {
    log_debug "检查网络连通性..."
    
    local targets=("8.8.8.8" "114.114.114.114" "1.1.1.1")
    local connected=0
    local ping_available=0
    
    if command -v ping >/dev/null 2>&1; then
        ping_available=1
    else
        PRECHECK_MESSAGES+=("未检测到 ping 命令，将使用备用方式检测网络")
    fi
    
    if [[ $ping_available -eq 1 ]]; then
        for target in "${targets[@]}"; do
            if ping -c 1 -W 3 "$target" >/dev/null 2>&1; then
                connected=1
                break
            fi
        done
    fi
    
    if [[ $connected -eq 0 ]]; then
        local http_ok=0
        local http_targets=("https://www.baidu.com" "https://www.cloudflare.com" "https://www.google.com/generate_204")
        
        for url in "${http_targets[@]}"; do
            if command -v curl >/dev/null 2>&1; then
                if curl -fsSL --connect-timeout 3 --max-time 5 -o /dev/null "$url"; then
                    http_ok=1
                    break
                fi
            elif command -v wget >/dev/null 2>&1; then
                if wget -q --spider --timeout=5 --tries=1 "$url"; then
                    http_ok=1
                    break
                fi
            fi
        done
        
        if [[ $http_ok -eq 1 ]]; then
            PRECHECK_NETWORK=1
            PRECHECK_MESSAGES+=("ICMP 可能被屏蔽，已通过 HTTP 备用检测确认网络可用")
            return 0
        fi
        
        PRECHECK_NETWORK=2
        PRECHECK_MESSAGES+=("网络连接失败，请检查网络配置")
        return 1
    fi
    
    PRECHECK_NETWORK=0
    return 0
}

# 检测 DNS 解析
precheck_dns() {
    log_debug "检查 DNS 解析..."
    
    local domains=("google.com" "baidu.com" "github.com")
    local resolved=0
    local tools_checked=0
    
    for domain in "${domains[@]}"; do
        if command -v host >/dev/null 2>&1; then
            tools_checked=1
            if host "$domain" >/dev/null 2>&1; then
                resolved=1
                break
            fi
        fi
        
        if command -v nslookup >/dev/null 2>&1; then
            tools_checked=1
            if nslookup "$domain" >/dev/null 2>&1; then
                resolved=1
                break
            fi
        fi
        
        if command -v getent >/dev/null 2>&1; then
            tools_checked=1
            if getent hosts "$domain" >/dev/null 2>&1; then
                resolved=1
                break
            fi
        fi
        
        if command -v ping >/dev/null 2>&1; then
            tools_checked=1
            if ping -c 1 -W 3 "$domain" >/dev/null 2>&1; then
                resolved=1
                break
            fi
        fi
        
        if command -v curl >/dev/null 2>&1; then
            tools_checked=1
            if curl -fsSL --connect-timeout 3 --max-time 5 -o /dev/null "https://${domain}"; then
                resolved=1
                break
            fi
        elif command -v wget >/dev/null 2>&1; then
            tools_checked=1
            if wget -q --spider --timeout=5 --tries=1 "https://${domain}"; then
                resolved=1
                break
            fi
        fi
    done
    
    if [[ $resolved -eq 0 ]]; then
        PRECHECK_DNS=1
        if [[ $tools_checked -eq 0 ]]; then
            PRECHECK_MESSAGES+=("DNS 检测工具缺失，建议安装 dnsutils/bind-utils 或检查系统环境")
        else
            PRECHECK_MESSAGES+=("DNS 解析可能存在问题，建议检查 /etc/resolv.conf")
        fi
        return 1
    fi
    
    PRECHECK_DNS=0
    return 0
}

# 检测磁盘空间
precheck_disk() {
    log_debug "检查磁盘空间..."
    
    local min_space_mb=500
    local available_mb
    
    # 检查 /boot 分区
    if [[ -d /boot ]]; then
        available_mb=$(df -m /boot 2>/dev/null | awk 'NR==2 {print $4}')
        if [[ -n "$available_mb" ]] && [[ $available_mb -lt 200 ]]; then
            PRECHECK_DISK=2
            PRECHECK_MESSAGES+=("/boot 分区空间不足 (${available_mb}MB < 200MB)，无法安装内核")
            return 1
        fi
    fi
    
    # 检查根分区
    available_mb=$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$available_mb" ]] && [[ $available_mb -lt $min_space_mb ]]; then
        PRECHECK_DISK=2
        PRECHECK_MESSAGES+=("根分区空间不足 (${available_mb}MB < ${min_space_mb}MB)")
        return 1
    fi
    
    PRECHECK_DISK=0
    return 0
}

# 更新 APT 缓存（带缓存）
apt_update_cached() {
    local force="${1:-0}"
    
    if [[ "$PKG_MANAGER" != "apt" ]]; then
        return 0
    fi
    
    if [[ $force -eq 0 && $APT_UPDATE_DONE -eq 1 ]]; then
        log_debug "APT 缓存已更新，跳过"
        return 0
    fi
    
    if apt-get update -qq; then
        APT_UPDATE_DONE=1
        return 0
    fi
    
    return 1
}

# 检测并安装依赖
precheck_deps() {
    log_debug "检查必要依赖..."
    
    local missing_deps=()
    local dep
    
    add_missing_dep() {
        local name="$1"
        local existing
        for existing in "${missing_deps[@]}"; do
            [[ "$existing" == "$name" ]] && return
        done
        missing_deps+=("$name")
    }
    
    for dep in $REQUIRED_DEPS; do
        # 映射包名到检测方式
        case "$dep" in
            gnupg)
                command -v gpg >/dev/null 2>&1 || missing_deps+=("$dep")
                ;;
            ca-certificates)
                # 检查证书目录是否存在
                [[ -d /etc/ssl/certs ]] || missing_deps+=("$dep")
                ;;
            *)
                command -v "$dep" >/dev/null 2>&1 || missing_deps+=("$dep")
                ;;
        esac
    done
    
    local dns_tool_ok=0
    for tool in host nslookup getent; do
        if command -v "$tool" >/dev/null 2>&1; then
            dns_tool_ok=1
            break
        fi
    done
    
    if [[ $dns_tool_ok -eq 0 ]]; then
        case "$PKG_MANAGER" in
            apt) add_missing_dep "dnsutils" ;;
            dnf|yum) add_missing_dep "bind-utils" ;;
        esac
    fi
    
    if ! command -v ping >/dev/null 2>&1; then
        case "$PKG_MANAGER" in
            apt) add_missing_dep "iputils-ping" ;;
            dnf|yum) add_missing_dep "iputils" ;;
        esac
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_info "缺少依赖: ${missing_deps[*]}"
        print_info "正在安装缺少的依赖: ${missing_deps[*]}"
        
        case "$PKG_MANAGER" in
            apt)
                if ! apt_update_cached; then
                    PRECHECK_DEPS=2
                    PRECHECK_MESSAGES+=("软件包缓存更新失败，请检查网络或源配置")
                    return 1
                fi
                apt-get install -y -qq "${missing_deps[@]}" || {
                    PRECHECK_DEPS=2
                    PRECHECK_MESSAGES+=("依赖安装失败: ${missing_deps[*]}")
                    return 1
                }
                ;;
            dnf)
                dnf install -y -q "${missing_deps[@]}" || {
                    PRECHECK_DEPS=2
                    PRECHECK_MESSAGES+=("依赖安装失败: ${missing_deps[*]}")
                    return 1
                }
                ;;
            yum)
                yum install -y -q "${missing_deps[@]}" || {
                    PRECHECK_DEPS=2
                    PRECHECK_MESSAGES+=("依赖安装失败: ${missing_deps[*]}")
                    return 1
                }
                ;;
            *)
                PRECHECK_DEPS=1
                PRECHECK_MESSAGES+=("未知包管理器，请手动安装: ${missing_deps[*]}")
                return 1
                ;;
        esac
    fi
    
    PRECHECK_DEPS=0
    return 0
}

# 检测系统更新状态
precheck_update() {
    log_debug "检查系统更新状态..."
    
    PRECHECK_UPDATE=0
    
    case "$PKG_MANAGER" in
        apt)
            # 检查 apt 缓存是否过期（超过 1 天）
            local cache_file="/var/cache/apt/pkgcache.bin"
            if [[ -f "$cache_file" ]]; then
                local cache_mtime cache_age
                # Linux 使用 -c %Y，macOS/BSD 使用 -f %m
                cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
                cache_age=$(( $(date +%s) - cache_mtime ))
                if [[ $cache_age -gt 86400 ]]; then
                    PRECHECK_UPDATE=1
                    PRECHECK_MESSAGES+=("APT 缓存已过期，建议运行 apt update")
                fi
            fi
            ;;
        dnf|yum)
            # DNF/YUM 通常自动处理缓存
            ;;
    esac
    
    return 0
}

# 检测 APT/YUM 源可用性
check_package_source() {
    log_debug "检测软件源可用性..."
    
    case "$PKG_MANAGER" in
        apt)
            # 尝试更新 APT 缓存
            local apt_output
            apt_output=$(apt-get update -qq 2>&1)
            if ! echo "$apt_output" | grep -qE '(Failed|Error|错误)'; then
                APT_UPDATE_DONE=1
                return 0
            fi
            
            if echo "$apt_output" | grep -qE 'Could not resolve|无法解析'; then
                log_warn "APT 源 DNS 解析失败"
                return 1
            fi
            
            if echo "$apt_output" | grep -qE 'Connection timed out|连接超时'; then
                log_warn "APT 源连接超时"
                return 2
            fi
            
            if echo "$apt_output" | grep -qE 'NO_PUBKEY|GPG error'; then
                log_warn "APT 源 GPG 密钥问题"
                return 3
            fi
            
            return 0
            ;;
        dnf)
            if dnf check-update -q 2>&1 | grep -qE '(Error|错误)'; then
                log_warn "DNF 源可能存在问题"
                return 1
            fi
            return 0
            ;;
        yum)
            if yum check-update -q 2>&1 | grep -qE '(Error|错误)'; then
                log_warn "YUM 源可能存在问题"
                return 1
            fi
            return 0
            ;;
    esac
    
    return 0
}

# 修复 APT 源问题
#
# v2.1.1 强化:
#  1. 不再 rm -rf /var/lib/apt/lists/* (在新源生效前删 cache 是逆序操作,
#     失败时连降级路径都没了)。改用 apt-get clean 仅清 deb 文件
#  2. 写新 sources.list 用临时文件 + mv 原子替换
#  3. 临界区屏蔽 SIGINT
fix_apt_source() {
    log_info "尝试修复 APT 源..."

    local sources_file="/etc/apt/sources.list"
    local backup_file="${sources_file}.bak.$(date +%Y%m%d%H%M%S)"

    # 备份当前源 - 失败硬终止,否则后续无法恢复
    if ! cp -- "$sources_file" "$backup_file" 2>/dev/null; then
        log_error "备份 $sources_file 失败,中止修复"
        return 1
    fi

    # 仅清 .deb 缓存,保留 lists/ 直到新源验证通过
    apt-get clean 2>/dev/null || true

    # 如果是国内环境，尝试切换到国内镜像
    if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
        print_info "尝试切换到国内镜像源..."

        local codename="${DIST_CODENAME:-$(lsb_release -cs 2>/dev/null || echo 'stable')}"
        local new_content=""

        case "$DIST_ID" in
            debian)
                new_content="deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${codename} main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${codename}-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security ${codename}-security main contrib non-free
"
                ;;
            ubuntu)
                new_content="deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename} main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename}-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename}-security main restricted universe multiverse
"
                ;;
        esac

        if [[ -n "$new_content" ]]; then
            critical_section_enter
            local tmp_file="${sources_file}.bbr3.new"
            if printf '%s' "$new_content" > "$tmp_file" \
                && mv -f -- "$tmp_file" "$sources_file"; then
                :
            else
                rm -f -- "$tmp_file"
                critical_section_exit
                log_error "写入新 sources.list 失败,恢复备份"
                cp -- "$backup_file" "$sources_file" 2>/dev/null || true
                return 1
            fi
            critical_section_exit
        fi
    fi

    # 重新更新 - 失败必须恢复 backup
    local apt_output
    apt_output=$(apt-get update -qq 2>&1)
    if echo "$apt_output" | grep -qE '(Failed|Error)'; then
        log_warn "修复后仍有问题，恢复原配置"
        if [[ -f "$backup_file" ]]; then
            critical_section_enter
            cp -- "$backup_file" "$sources_file" 2>/dev/null || true
            critical_section_exit
        fi
        return 1
    fi
    APT_UPDATE_DONE=1

    print_success "APT 源修复成功"
    return 0
}

# 检测网络环境（国内/国外）
detect_network_region() {
    log_debug "检测网络环境..."
    
    if [[ $NETWORK_REGION_DETECTED -eq 1 ]]; then
        return 0
    fi
    
    # 测试国内外服务器延迟
    local cn_latency=9999
    local intl_latency=9999
    
    # 测试国内服务器 - 使用兼容的方式提取延迟
    local cn_result
    cn_result=$(ping -c 1 -W 2 "114.114.114.114" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -1)
    [[ -n "$cn_result" ]] && cn_latency="${cn_result%%.*}" || cn_latency=9999
    
    # 测试国外服务器
    local intl_result
    intl_result=$(ping -c 1 -W 2 "8.8.8.8" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -1)
    [[ -n "$intl_result" ]] && intl_latency="${intl_result%%.*}" || intl_latency=9999
    
    # 测试 Google 可访问性
    local google_ok=0
    if curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" >/dev/null 2>&1; then
        google_ok=1
    fi
    
    # 判断网络环境
    if [[ $google_ok -eq 0 ]] || { [[ $cn_latency -lt 9999 ]] && [[ $intl_latency -gt 0 ]] && [[ $cn_latency -lt $((intl_latency / 2)) ]]; }; then
        USE_CHINA_MIRROR=1
        MIRROR_REGION="cn"
        log_info "检测到国内网络环境，将使用国内镜像源"
    else
        USE_CHINA_MIRROR=0
        MIRROR_REGION="intl"
        log_info "检测到国际网络环境，将使用官方源"
    fi
    
    NETWORK_REGION_DETECTED=1
}

# 检测当前 APT 源是否为国内镜像（返回 0 表示官方源，返回 1 表示国内镜像）
detect_apt_mirror_region() {
    if [[ "$PKG_MANAGER" != "apt" ]]; then
        return 0
    fi
    
    local sources_file="/etc/apt/sources.list"
    if [[ ! -f "$sources_file" ]]; then
        return 0
    fi
    
    # 检测是否使用国内镜像
    if grep -qE '(mirrors\.(aliyun|tuna|ustc|163|huaweicloud)|mirror\.(nju|sjtu)\.edu\.cn)' "$sources_file" 2>/dev/null; then
        return 1  # 使用国内镜像
    fi
    
    return 0  # 使用官方源或其他源
}

# 执行完整预检
run_precheck() {
    print_header "环境预检"
    
    local all_passed=1
    
    # Root 权限检查
    echo -n "  检查 root 权限..."
    if precheck_root; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${RED}${ICON_FAIL}${NC}]"
        all_passed=0
    fi
    
    # 操作系统检测
    echo -n "  检测操作系统..."
    detect_os
    detect_arch
    detect_virt
    if is_system_supported; then
        PRECHECK_OS=0
        echo -e " [${GREEN}${ICON_OK}${NC}] $(get_os_pretty_name)"
    else
        PRECHECK_OS=1
        echo -e " [${YELLOW}${ICON_WARN}${NC}] $(get_os_pretty_name) (不在官方支持列表)"
        PRECHECK_MESSAGES+=("系统版本不在官方支持列表，部分功能可能受限")
    fi
    
    # 架构检查
    echo -n "  检查 CPU 架构..."
    if [[ "$ARCH_ID" == "amd64" ]]; then
        PRECHECK_ARCH=0
        echo -e " [${GREEN}${ICON_OK}${NC}] ${ARCH_ID}"
    else
        PRECHECK_ARCH=1
        echo -e " [${YELLOW}${ICON_WARN}${NC}] ${ARCH_ID} (第三方内核仅支持 amd64)"
        PRECHECK_MESSAGES+=("当前架构 ${ARCH_ID} 不支持安装第三方内核，仅可配置 sysctl")
    fi
    
    # 虚拟化检查
    echo -n "  检测虚拟化环境..."
    case "$VIRT_TYPE" in
        openvz|lxc|docker|wsl)
            PRECHECK_VIRT=1
            echo -e " [${YELLOW}${ICON_WARN}${NC}] ${VIRT_TYPE} (无法更换内核)"
            PRECHECK_MESSAGES+=("容器环境 ${VIRT_TYPE} 无法更换宿主内核")
            ;;
        *)
            PRECHECK_VIRT=0
            echo -e " [${GREEN}${ICON_OK}${NC}] ${VIRT_TYPE}"
            ;;
    esac
    
    # 网络检查
    echo -n "  检查网络连通性..."
    if precheck_network; then
        if [[ $PRECHECK_NETWORK -eq 1 ]]; then
            echo -e " [${YELLOW}${ICON_WARN}${NC}]"
        else
            echo -e " [${GREEN}${ICON_OK}${NC}]"
        fi
    else
        echo -e " [${RED}${ICON_FAIL}${NC}]"
        all_passed=0
    fi
    
    # DNS 检查
    echo -n "  检查 DNS 解析..."
    if precheck_dns; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${YELLOW}${ICON_WARN}${NC}]"
    fi
    
    # 磁盘空间检查
    echo -n "  检查磁盘空间..."
    if precheck_disk; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${RED}${ICON_FAIL}${NC}]"
        all_passed=0
    fi
    
    # 依赖检查
    echo -n "  检查必要依赖..."
    if precheck_deps; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${RED}${ICON_FAIL}${NC}]"
        all_passed=0
    fi
    
    # 系统更新检查
    echo -n "  检查系统更新..."
    precheck_update
    if [[ $PRECHECK_UPDATE -eq 0 ]]; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${YELLOW}${ICON_WARN}${NC}]"
    fi
    
    # 网络环境检测
    echo -n "  检测网络环境..."
    detect_network_region
    if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
        echo -e " [${CYAN}${ICON_NET}${NC}] 国内网络"
    else
        echo -e " [${CYAN}${ICON_NET}${NC}] 国际网络"
    fi
    
    # APT 源配置检测（仅 Debian/Ubuntu）
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        echo -n "  检测软件源配置..."
        if detect_apt_mirror_region; then
            # 使用官方源或其他源
            if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
                echo -e " [${YELLOW}${ICON_WARN}${NC}] 官方源（国内网络建议使用镜像）"
            else
                echo -e " [${GREEN}${ICON_OK}${NC}] 官方源"
            fi
        else
            # 使用国内镜像
            if [[ $USE_CHINA_MIRROR -eq 0 ]]; then
                echo -e " [${YELLOW}${ICON_WARN}${NC}] 国内镜像（国外网络可能需要切换）"
                PRECHECK_MESSAGES+=("系统使用国内镜像源，在国外网络环境下安装第三方内核时可能需要切换到官方源")
            else
                echo -e " [${GREEN}${ICON_OK}${NC}] 国内镜像"
            fi
        fi
    fi
    
    echo
    
    # 显示警告信息
    if [[ ${#PRECHECK_MESSAGES[@]} -gt 0 ]]; then
        print_warn "预检发现以下问题："
        for msg in "${PRECHECK_MESSAGES[@]}"; do
            echo -e "  ${YELLOW}•${NC} ${msg}"
        done
        echo
    fi
    
    # 返回预检结果
    if [[ $all_passed -eq 1 ]]; then
        print_success "环境预检通过"
        return 0
    else
        print_error "环境预检未通过，请解决上述问题后重试"
        return 1
    fi
}


#===============================================================================
# 配置管理模块
#===============================================================================

# 备份当前配置
backup_config() {
    log_debug "备份当前配置..."

    # 创建备份目录 - 失败必须返回非零，否则后续 write_sysctl 会以为
    # 备份成功而直接覆写原文件，导致用户配置不可逆丢失
    if [[ ! -d "$BACKUP_DIR" ]]; then
        if ! mkdir -p "$BACKUP_DIR"; then
            log_error "无法创建备份目录: $BACKUP_DIR"
            print_error "无法创建备份目录: $BACKUP_DIR"
            return 1
        fi
    fi

    # 如果配置文件存在，进行备份
    if [[ -f "$SYSCTL_FILE" ]]; then
        local timestamp
        timestamp=$(date '+%Y%m%d_%H%M%S')
        local backup_file="${BACKUP_DIR}/99-bbr.conf.${timestamp}.bak"

        if ! cp -- "$SYSCTL_FILE" "$backup_file"; then
            log_error "备份失败: 无法复制 $SYSCTL_FILE 到 $backup_file"
            print_error "备份失败,取消写入以防止配置丢失"
            return 1
        fi
        log_info "配置已备份到: ${backup_file}"
        print_info "配置已备份到: ${backup_file}"
        return 0
    fi

    return 0
}

# 恢复配置
restore_config() {
    local backup_file="${1:-}"
    
    if [[ -z "$backup_file" ]]; then
        # 列出可用备份
        local backups
        backups=$(ls -t "${BACKUP_DIR}/"*.bak 2>/dev/null || true)
        
        if [[ -z "$backups" ]]; then
            print_warn "没有找到可用的备份文件"
            return 1
        fi
        
        print_info "可用的备份文件："
        local i=1
        local -a backup_list=()
        while IFS= read -r file; do
            backup_list+=("$file")
            local filename
            filename=$(basename "$file")
            echo "  ${i}) ${filename}"
            ((i++))
        done <<< "$backups"
        
        read_choice "选择要恢复的备份" $((i-1))
        
        if [[ "$MENU_CHOICE" == "0" ]]; then
            return 1
        fi
        
        backup_file="${backup_list[$((MENU_CHOICE-1))]}"
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "备份文件不存在: ${backup_file}"
        return 1
    fi

    # 安全校验: 备份文件必须真的位于 BACKUP_DIR 下,防御传入任意路径
    local backup_real backup_dir_real
    backup_real=$(cd "$(dirname "$backup_file")" && pwd -P)/$(basename "$backup_file")
    backup_dir_real=$(cd "$BACKUP_DIR" 2>/dev/null && pwd -P) || backup_dir_real=""
    if [[ -z "$backup_dir_real" || "${backup_real#$backup_dir_real/}" == "$backup_real" ]]; then
        print_error "备份路径越界,拒绝恢复: ${backup_file}"
        return 1
    fi

    # 校验备份文件不是空的且至少有一行 sysctl 格式
    if [[ ! -s "$backup_file" ]]; then
        print_error "备份文件为空: ${backup_file}"
        return 1
    fi

    # 原子恢复: 写到 .new 后 mv,避免半写状态
    if ! cp -- "$backup_file" "${SYSCTL_FILE}.new"; then
        print_error "恢复失败: 无法写入 ${SYSCTL_FILE}.new"
        return 1
    fi
    if ! mv -f -- "${SYSCTL_FILE}.new" "$SYSCTL_FILE"; then
        rm -f -- "${SYSCTL_FILE}.new"
        print_error "恢复失败: 无法替换 ${SYSCTL_FILE}"
        return 1
    fi
    log_info "配置已从 ${backup_file} 恢复"
    print_success "配置已恢复"
    
    # 应用配置
    if confirm "是否立即应用恢复的配置？" "y"; then
        apply_sysctl
    fi
    
    return 0
}

# 列出备份文件
list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_info "没有备份目录"
        return
    fi
    
    local backups
    backups=$(ls -t "${BACKUP_DIR}/"*.bak 2>/dev/null || true)
    
    if [[ -z "$backups" ]]; then
        print_info "没有找到备份文件"
        return
    fi
    
    print_info "可用的备份文件："
    while IFS= read -r file; do
        local filename size file_date
        filename=$(basename "$file")
        size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "N/A")
        # Linux 使用 -c %y，macOS/BSD 使用 -f %Sm
        file_date=$(stat -c %y "$file" 2>/dev/null | cut -d'.' -f1 || stat -f %Sm "$file" 2>/dev/null || echo "N/A")
        echo "  • ${filename} (${size}, ${file_date})"
    done <<< "$backups"
}

#===============================================================================
# 场景配置模块
#===============================================================================

# 检测服务器资源
detect_server_resources() {
    log_debug "检测服务器资源..."
    
    # CPU 核心数
    SERVER_CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
    
    # 内存大小 (MB)
    SERVER_MEMORY_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 1024)
    
    # 估算带宽 (通过网卡速度)
    local nic
    nic=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    if [[ -n "$nic" ]] && command -v ethtool >/dev/null 2>&1; then
        local speed
        speed=$(ethtool "$nic" 2>/dev/null | awk -F': ' '/Speed:/{print $2}' | grep -oE '[0-9]+')
        SERVER_BANDWIDTH_MBPS="${speed:-1000}"
    else
        SERVER_BANDWIDTH_MBPS=1000
    fi
    
    # 当前 TCP 连接数
    SERVER_TCP_CONNECTIONS=$(ss -t 2>/dev/null | wc -l)
    if [[ -z "$SERVER_TCP_CONNECTIONS" ]] || ! [[ "$SERVER_TCP_CONNECTIONS" =~ ^[0-9]+$ ]]; then
        SERVER_TCP_CONNECTIONS=$(netstat -tn 2>/dev/null | wc -l)
    fi
    SERVER_TCP_CONNECTIONS=${SERVER_TCP_CONNECTIONS:-0}
    SERVER_TCP_CONNECTIONS=${SERVER_TCP_CONNECTIONS// /}
    # 减去标题行，使用安全的算术运算
    SERVER_TCP_CONNECTIONS=$((SERVER_TCP_CONNECTIONS > 0 ? SERVER_TCP_CONNECTIONS - 1 : 0))
}

#===============================================================================
# 智能优化模块
#===============================================================================

# 智能带宽检测 - 多级回退策略
detect_bandwidth() {
    log_info "正在检测服务器带宽..."
    
    local bandwidth=0
    
    # 方法1: 优先使用 ethtool 读取网卡速率（最快最准确）
    local nic
    nic=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    if [[ -n "$nic" ]] && command -v ethtool >/dev/null 2>&1; then
        local nic_speed
        # 尝试读取网卡速率，过滤掉 "Unknown" 等无效值
        nic_speed=$(ethtool "$nic" 2>/dev/null | grep -i "Speed:" | grep -oE '[0-9]+' | head -1)
        if [[ -n "$nic_speed" ]] && [[ $nic_speed -gt 0 ]] && [[ $nic_speed -lt 100000 ]]; then
            bandwidth=$nic_speed
            log_info "网卡速率: ${bandwidth} Mbps"
        else
            log_debug "ethtool 无法读取网卡速率（虚拟化环境常见）"
        fi
    fi
    
    # 方法1.5: 尝试从 /sys/class/net 读取速率（虚拟化环境备选）
    if [[ $bandwidth -eq 0 ]] && [[ -n "$nic" ]] && [[ -f "/sys/class/net/$nic/speed" ]]; then
        local sys_speed
        sys_speed=$(cat "/sys/class/net/$nic/speed" 2>/dev/null)
        if [[ -n "$sys_speed" ]] && [[ $sys_speed -gt 0 ]] && [[ $sys_speed -lt 100000 ]]; then
            bandwidth=$sys_speed
            log_info "网卡速率 (sysfs): ${bandwidth} Mbps"
        fi
    fi
    
    # 方法2: 使用 speedtest-cli (如果网卡检测失败)
    if [[ $bandwidth -eq 0 ]] && command -v speedtest-cli >/dev/null 2>&1; then
        log_debug "使用 speedtest-cli 检测..."
        local result
        result=$(speedtest-cli --simple 2>/dev/null | grep -i "upload" | awk '{print $2}')
        if [[ -n "$result" ]] && [[ "$result" =~ ^[0-9.]+$ ]]; then
            bandwidth=$(printf "%.0f" "$result")
            log_info "speedtest-cli 检测带宽: ${bandwidth} Mbps"
        fi
    fi
    
    # 方法3: 使用 curl 下载测速 (最后回退，使用更大文件)
    if [[ $bandwidth -eq 0 ]]; then
        log_debug "使用 curl 下载测速..."
        local start_time end_time duration
        local test_url="https://speed.cloudflare.com/__down?bytes=100000000"  # 100MB
        
        start_time=$(date +%s.%N)
        if curl -so /dev/null --max-time 30 "$test_url" 2>/dev/null; then
            end_time=$(date +%s.%N)
            duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "30")
            if [[ -n "$duration" ]] && (( $(echo "$duration > 0" | bc -l 2>/dev/null || echo 0) )); then
                bandwidth=$(echo "100 * 8 / $duration" | bc 2>/dev/null || echo "0")
                bandwidth=${bandwidth:-0}
                log_info "curl 测速带宽: ${bandwidth} Mbps"
            fi
        fi
    fi
    
    # 默认值
    if [[ $bandwidth -eq 0 ]]; then
        bandwidth=1000
        log_warn "无法检测带宽，使用默认值: 1000 Mbps"
    fi
    
    SMART_DETECTED_BANDWIDTH=$bandwidth
    echo "$bandwidth"
}

# 检测 RTT
detect_rtt() {
    local target="${1:-8.8.8.8}"
    log_debug "检测到 $target 的 RTT..."
    
    local rtt=100  # 默认值
    
    if command -v ping >/dev/null 2>&1; then
        local ping_result
        ping_result=$(ping -c 3 -W 2 "$target" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        if [[ -n "$ping_result" ]] && [[ "$ping_result" =~ ^[0-9.]+$ ]]; then
            rtt=$(printf "%.0f" "$ping_result")
        fi
    fi
    
    SMART_DETECTED_RTT=$rtt
    echo "$rtt"
}

# 根据 BDP 计算最优缓冲区
calculate_bdp_buffer() {
    local bandwidth_mbps="${1:-$SMART_DETECTED_BANDWIDTH}"
    local rtt_ms="${2:-$SMART_DETECTED_RTT}"
    
    [[ $bandwidth_mbps -eq 0 ]] && bandwidth_mbps=100
    [[ $rtt_ms -eq 0 ]] && rtt_ms=100
    
    # BDP = bandwidth (bits/s) * RTT (s) / 8 (转换为字节)
    # bandwidth_mbps * 1000000 * rtt_ms / 1000 / 8 = bandwidth_mbps * rtt_ms * 125
    local bdp_bytes=$((bandwidth_mbps * rtt_ms * 125))
    
    # 加上 25% 冗余
    local buffer_bytes=$((bdp_bytes * 125 / 100))
    
    # 根据硬件评分调整上限
    local max_buffer=134217728  # 128MB
    local min_buffer=16777216   # 16MB
    
    case "${SMART_HARDWARE_SCORE:-medium}" in
        low)
            max_buffer=33554432   # 32MB
            ;;
        medium)
            max_buffer=67108864   # 64MB
            ;;
        high)
            max_buffer=134217728  # 128MB
            ;;
    esac
    
    # 限制范围
    [[ $buffer_bytes -lt $min_buffer ]] && buffer_bytes=$min_buffer
    [[ $buffer_bytes -gt $max_buffer ]] && buffer_bytes=$max_buffer
    
    SMART_OPTIMAL_BUFFER=$buffer_bytes
    echo "$buffer_bytes"
}

# MTU 路径探测
detect_optimal_mtu() {
    local target="${1:-8.8.8.8}"
    log_debug "探测到 $target 的最优 MTU..."
    
    local mtu=1500  # 默认值
    local low=1200
    local high=1500
    
    # 二分法探测
    while [[ $low -lt $high ]]; do
        local mid=$(( (low + high + 1) / 2 ))
        local packet_size=$((mid - 28))  # 减去 IP + ICMP 头
        
        if ping -c 1 -W 1 -M do -s "$packet_size" "$target" >/dev/null 2>&1; then
            low=$mid
        else
            high=$((mid - 1))
        fi
    done
    
    mtu=$low
    SMART_OPTIMAL_MTU=$mtu
    log_info "检测到最优 MTU: $mtu"
    echo "$mtu"
}

# 硬件性能评估
assess_hardware_score() {
    detect_server_resources
    
    local score="medium"
    
    # 评分逻辑
    if [[ $SERVER_CPU_CORES -le 1 ]] && [[ $SERVER_MEMORY_MB -lt 1024 ]]; then
        score="low"
    elif [[ $SERVER_CPU_CORES -gt 4 ]] || [[ $SERVER_MEMORY_MB -gt 4096 ]]; then
        score="high"
    else
        score="medium"
    fi
    
    SMART_HARDWARE_SCORE=$score
    log_info "硬件评分: $score (CPU: ${SERVER_CPU_CORES}核, 内存: ${SERVER_MEMORY_MB}MB)"
    echo "$score"
}

# 应用 MSS Clamp
apply_mss_clamp() {
    log_info "启用 MSS Clamp..."
    
    local nic
    nic=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    
    if [[ -z "$nic" ]]; then
        log_warn "无法检测默认网卡，跳过 MSS Clamp"
        return 1
    fi
    
    # 检查是否已有规则
    if iptables -t mangle -C POSTROUTING -o "$nic" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        log_info "MSS Clamp 规则已存在"
        SMART_MSS_CLAMP_ENABLED=1
        return 0
    fi
    
    # 添加规则
    if iptables -t mangle -A POSTROUTING -o "$nic" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        log_info "MSS Clamp 已启用 (网卡: $nic)"
        SMART_MSS_CLAMP_ENABLED=1
        
        # 持久化规则
        # /etc/iptables.rules 不是任何发行版的规范路径,以前的代码会盖掉同名文件。
        # Debian 规范是 /etc/iptables/rules.v4 (iptables-persistent 包),否则用脚本专属命名空间
        if command -v iptables-save >/dev/null 2>&1; then
            local persist_file
            if [[ -d /etc/iptables ]]; then
                persist_file="/etc/iptables/rules.v4"
            else
                persist_file="/etc/iptables.bbr3.rules"
            fi
            local tmp_file="${persist_file}.bbr3.new"
            if iptables-save > "$tmp_file" 2>/dev/null; then
                mv -f -- "$tmp_file" "$persist_file" 2>/dev/null || rm -f -- "$tmp_file"
            else
                rm -f -- "$tmp_file"
            fi
        fi
        return 0
    else
        log_warn "MSS Clamp 启用失败"
        return 1
    fi
}

# 移除 MSS Clamp
remove_mss_clamp() {
    log_info "移除 MSS Clamp..."
    
    local nic
    nic=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    
    if [[ -n "$nic" ]]; then
        iptables -t mangle -D POSTROUTING -o "$nic" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    fi
    
    SMART_MSS_CLAMP_ENABLED=0
    log_info "MSS Clamp 已移除"
}

# 智能自动优化 - 一键完成所有检测和配置
smart_auto_optimize() {
    print_header "智能自动优化"
    
    echo -e "${CYAN}正在进行智能检测...${NC}"
    echo
    
    # 步骤1: 硬件评估
    echo -e "${BOLD}[1/5] 硬件评估${NC}"
    assess_hardware_score
    print_kv "硬件评分" "$SMART_HARDWARE_SCORE"
    print_kv "CPU 核心" "$SERVER_CPU_CORES"
    print_kv "内存" "${SERVER_MEMORY_MB}MB"
    echo
    
    # 步骤2: 带宽检测
    echo -e "${BOLD}[2/5] 带宽检测${NC}"
    detect_bandwidth >/dev/null
    print_kv "检测带宽" "${SMART_DETECTED_BANDWIDTH} Mbps"
    echo
    
    # 步骤3: RTT 检测
    echo -e "${BOLD}[3/5] 延迟检测${NC}"
    detect_rtt >/dev/null
    print_kv "RTT 延迟" "${SMART_DETECTED_RTT} ms"
    echo
    
    # 步骤4: 计算最优参数
    echo -e "${BOLD}[4/5] 参数计算${NC}"
    calculate_bdp_buffer >/dev/null
    local buffer_mb=$((SMART_OPTIMAL_BUFFER / 1024 / 1024))
    print_kv "最优缓冲区" "${buffer_mb}MB"
    echo
    
    # 步骤5: MTU 检测
    echo -e "${BOLD}[5/5] MTU 检测${NC}"
    detect_optimal_mtu >/dev/null
    print_kv "最优 MTU" "$SMART_OPTIMAL_MTU"
    echo
    
    print_separator
    echo
    echo -e "${GREEN}${ICON_OK} 智能检测完成${NC}"
    echo
    echo -e "${BOLD}推荐配置:${NC}"
    print_kv "缓冲区大小" "${buffer_mb}MB"
    print_kv "tcp_notsent_lowat" "16384"
    print_kv "tcp_mtu_probing" "1"
    print_kv "MSS Clamp" "建议启用"
    echo
    
    # 确认应用
    if [[ $NON_INTERACTIVE -eq 0 ]]; then
        echo -e "${YELLOW}是否应用这些优化配置？${NC}"
        read -rp "[Y/n] " confirm
        if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
            apply_smart_config
        else
            print_info "已取消"
        fi
    else
        apply_smart_config
    fi
}

# 应用智能配置
apply_smart_config() {
    log_info "应用智能优化配置..."
    
    local buffer_bytes=$SMART_OPTIMAL_BUFFER
    [[ $buffer_bytes -eq 0 ]] && buffer_bytes=67108864  # 默认 64MB
    
    # 生成配置
    cat > "$SYSCTL_FILE" << EOF
# EasyBBR3 智能优化配置
# 生成时间: $(date)
# 检测带宽: ${SMART_DETECTED_BANDWIDTH:-0} Mbps
# 检测 RTT: ${SMART_DETECTED_RTT:-0} ms
# 硬件评分: ${SMART_HARDWARE_SCORE:-medium}

# 拥塞控制
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# 智能计算的缓冲区
net.core.rmem_max = $buffer_bytes
net.core.wmem_max = $buffer_bytes
net.ipv4.tcp_rmem = 4096 87380 $buffer_bytes
net.ipv4.tcp_wmem = 4096 65536 $buffer_bytes

# Reality/VLESS 优化
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1

# 代理优化参数
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10

# 连接队列
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 5000

# TCP 保活
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# SYN 保护
net.ipv4.tcp_syncookies = 1
EOF
    
    # 应用配置
    if sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
        print_success "智能优化配置已应用"
    else
        # 逐行应用并统计
        local applied=0 errors=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            if sysctl -w "$line" >/dev/null 2>&1; then ((++applied)); else ((++errors)); fi
        done < "$SYSCTL_FILE"
        if [[ $errors -gt 0 ]]; then
            print_info "已应用 ${applied} 项，${errors} 项不被当前内核支持（不影响核心功能）"
        else
            print_success "智能优化配置已应用"
        fi
    fi
    
    # 启用 MSS Clamp
    apply_mss_clamp
    
    print_success "智能优化完成"
}

# 根据服务器资源推荐场景模式
recommend_scene_mode() {
    detect_server_resources
    
    # 推荐逻辑（针对 VPS 代理场景优化）
    # 1. VPS 环境（KVM/Xen/虚拟机）-> 默认推荐代理模式
    # 2. 高并发 (连接数>1000 或 多核>=8) -> 并发模式
    # 3. 大带宽 (>=10Gbps) -> 极速模式
    # 4. 物理机/数据中心 -> 性能模式
    
    # 检测是否为 VPS 环境（常见代理服务器场景）
    local is_vps=0
    case "${VIRT_TYPE:-}" in
        kvm|qemu|xen|vmware|virtualbox|hyperv|none)
            is_vps=1
            ;;
    esac
    
    # VPS 环境默认推荐代理模式
    if [[ $is_vps -eq 1 ]] && [[ $SERVER_CPU_CORES -le 4 ]] && [[ $SERVER_MEMORY_MB -le 4096 ]]; then
        SCENE_RECOMMENDED="proxy"
    elif [[ $SERVER_TCP_CONNECTIONS -gt 1000 ]] || [[ $SERVER_CPU_CORES -ge 8 ]]; then
        SCENE_RECOMMENDED="concurrent"
    elif [[ $SERVER_BANDWIDTH_MBPS -ge 10000 ]]; then
        SCENE_RECOMMENDED="speed"
    elif [[ $SERVER_BANDWIDTH_MBPS -ge 1000 ]]; then
        SCENE_RECOMMENDED="video"
    elif [[ "${VIRT_TYPE:-}" == "none" ]] || [[ "${VIRT_TYPE:-}" == "物理机/未知" ]]; then
        SCENE_RECOMMENDED="performance"
    else
        SCENE_RECOMMENDED="proxy"  # VPS 默认代理模式
    fi
}

# 获取场景模式名称
get_scene_name() {
    local mode="$1"
    case "$mode" in
        balanced)      echo "均衡模式" ;;
        communication) echo "通信模式" ;;
        video)         echo "视频模式" ;;
        concurrent)    echo "并发模式" ;;
        speed)         echo "极速模式" ;;
        performance)   echo "性能模式" ;;
        proxy)         echo "代理模式" ;;
        line)          echo "LINE优化" ;;
        *)             echo "未知模式" ;;
    esac
}

# 获取场景模式描述
get_scene_description() {
    local mode="$1"
    case "$mode" in
        balanced)
            echo "适合一般用途，平衡延迟与吞吐量"
            ;;
        communication)
            echo "优化低延迟，适合实时通信/游戏/SSH"
            ;;
        video)
            echo "优化大文件传输，适合视频流/下载服务"
            ;;
        concurrent)
            echo "优化高并发连接，适合 Web 服务器/API"
            ;;
        speed)
            echo "最大化吞吐量，适合大带宽服务器"
            ;;
        performance)
            echo "全面性能优化，适合高性能计算/数据库"
            ;;
        proxy)
            echo "专为代理/VPN优化，抗丢包、低延迟、高吞吐"
            ;;
        line)
            echo "专为LINE优化，通话优先、文件传输、消息加速"
            ;;
    esac
}

# 获取场景模式的 sysctl 参数（根据服务器配置动态调整）
get_scene_params() {
    local mode="$1"
    
    # 确保已检测服务器资源
    [[ $SERVER_CPU_CORES -eq 0 ]] && detect_server_resources
    
    # 根据内存计算缓冲区大小
    # 规则：缓冲区最大不超过内存的 1/4，最小 16MB
    local mem_bytes=$((SERVER_MEMORY_MB * 1024 * 1024))
    local max_buffer=$((mem_bytes / 4))
    [[ $max_buffer -gt 268435456 ]] && max_buffer=268435456  # 最大 256MB
    [[ $max_buffer -lt 16777216 ]] && max_buffer=16777216    # 最小 16MB
    
    # 根据 CPU 核心数计算连接队列
    # 规则：每核心 1024-4096 连接
    local base_somaxconn=$((SERVER_CPU_CORES * 2048))
    [[ $base_somaxconn -gt 65535 ]] && base_somaxconn=65535
    [[ $base_somaxconn -lt 1024 ]] && base_somaxconn=1024
    
    # 根据 CPU 核心数计算网络队列
    local base_backlog=$((SERVER_CPU_CORES * 50000))
    [[ $base_backlog -gt 1000000 ]] && base_backlog=1000000
    [[ $base_backlog -lt 10000 ]] && base_backlog=10000
    
    # 自动检测最佳算法（优先 BBR3）
    local algo
    algo=$(suggest_best_algo)
    
    # 自动检测最佳队列规则（根据场景）
    local qdisc
    qdisc=$(suggest_best_qdisc "$mode")
    local rmem_max=$max_buffer
    local wmem_max=$max_buffer
    local tcp_rmem_high=$max_buffer
    local tcp_wmem_high=$max_buffer
    local somaxconn=$base_somaxconn
    local netdev_backlog=$base_backlog
    local tcp_fastopen=3
    local tcp_low_latency=0
    local tcp_slow_start=1
    local tcp_notsent_lowat=16384
    
    # 注意：algo 和 qdisc 已在上面自动检测，各场景只调整其他参数
    case "$mode" in
        balanced)
            # 均衡模式 - 使用 50% 的计算值，平衡延迟与吞吐
            rmem_max=$((max_buffer / 2))
            wmem_max=$((max_buffer / 2))
            tcp_rmem_high=$((max_buffer / 2))
            tcp_wmem_high=$((max_buffer / 2))
            somaxconn=$((base_somaxconn / 2))
            netdev_backlog=$((base_backlog / 2))
            ;;
        communication)
            # 通信模式 - 小缓冲区，低延迟优先
            rmem_max=$((max_buffer / 4))
            wmem_max=$((max_buffer / 4))
            tcp_rmem_high=$((max_buffer / 4))
            tcp_wmem_high=$((max_buffer / 4))
            somaxconn=$((base_somaxconn / 4))
            netdev_backlog=$((base_backlog / 4))
            tcp_low_latency=1
            tcp_notsent_lowat=4096
            ;;
        video)
            # 视频模式 - 大缓冲区，大吞吐量
            rmem_max=$((max_buffer * 3 / 4))
            wmem_max=$((max_buffer * 3 / 4))
            tcp_rmem_high=$((max_buffer * 3 / 4))
            tcp_wmem_high=$((max_buffer * 3 / 4))
            somaxconn=$base_somaxconn
            netdev_backlog=$base_backlog
            tcp_slow_start=0
            ;;
        concurrent)
            # 并发模式 - 最大化连接数，公平性优先
            rmem_max=$((max_buffer / 2))
            wmem_max=$((max_buffer / 2))
            tcp_rmem_high=$((max_buffer / 2))
            tcp_wmem_high=$((max_buffer / 2))
            somaxconn=65535
            netdev_backlog=$((base_backlog * 2))
            [[ $netdev_backlog -gt 1000000 ]] && netdev_backlog=1000000
            tcp_fastopen=3
            ;;
        speed)
            # 极速模式 - 最大吞吐量
            rmem_max=$max_buffer
            wmem_max=$max_buffer
            tcp_rmem_high=$max_buffer
            tcp_wmem_high=$max_buffer
            somaxconn=$base_somaxconn
            netdev_backlog=$((base_backlog * 2))
            [[ $netdev_backlog -gt 1000000 ]] && netdev_backlog=1000000
            tcp_slow_start=0
            tcp_notsent_lowat=131072
            ;;
        performance)
            # 性能模式 - 全面优化
            rmem_max=$((max_buffer * 3 / 4))
            wmem_max=$((max_buffer * 3 / 4))
            tcp_rmem_high=$((max_buffer * 3 / 4))
            tcp_wmem_high=$((max_buffer * 3 / 4))
            somaxconn=$((base_somaxconn * 3 / 2))
            [[ $somaxconn -gt 65535 ]] && somaxconn=65535
            netdev_backlog=$base_backlog
            tcp_fastopen=3
            tcp_low_latency=1
            tcp_slow_start=0
            tcp_notsent_lowat=65536
            ;;
        proxy)
            # 代理模式 - 专为 VPS 代理/VPN/翻墙优化
            # 特点：抗丢包、低延迟、适中缓冲区、快速重传
            # 适合：V2Ray, Xray, Trojan, Shadowsocks, WireGuard 等
            rmem_max=$((max_buffer * 2 / 3))
            wmem_max=$((max_buffer * 2 / 3))
            tcp_rmem_high=$((max_buffer * 2 / 3))
            tcp_wmem_high=$((max_buffer * 2 / 3))
            somaxconn=$((base_somaxconn * 2))
            [[ $somaxconn -gt 65535 ]] && somaxconn=65535
            netdev_backlog=$((base_backlog * 2))
            [[ $netdev_backlog -gt 1000000 ]] && netdev_backlog=1000000
            tcp_fastopen=3          # 启用 TFO 加速握手
            tcp_low_latency=1       # 低延迟模式
            tcp_slow_start=0        # 禁用慢启动（重连更快）
            tcp_notsent_lowat=16384 # 较小值减少延迟
            ;;
        line)
            # LINE 优化模式 - 专为 LINE 应用优化
            # 优先级：通话 > 文件传输 > 消息
            # 特点：UDP 优化、低抖动、快速响应
            rmem_max=$((max_buffer * 2 / 3))
            wmem_max=$((max_buffer * 2 / 3))
            tcp_rmem_high=$((max_buffer * 2 / 3))
            tcp_wmem_high=$((max_buffer * 2 / 3))
            somaxconn=$((base_somaxconn * 2))
            [[ $somaxconn -gt 65535 ]] && somaxconn=65535
            netdev_backlog=$((base_backlog * 2))
            [[ $netdev_backlog -gt 1000000 ]] && netdev_backlog=1000000
            tcp_fastopen=3          # TFO 加速消息发送
            tcp_low_latency=1       # 低延迟优先（通话）
            tcp_slow_start=0        # 禁用慢启动（快速恢复）
            tcp_notsent_lowat=8192  # 更小值减少通话延迟
            ;;
    esac
    
    # 确保最小值
    [[ $rmem_max -lt 16777216 ]] && rmem_max=16777216
    [[ $wmem_max -lt 16777216 ]] && wmem_max=16777216
    [[ $tcp_rmem_high -lt 16777216 ]] && tcp_rmem_high=16777216
    [[ $tcp_wmem_high -lt 16777216 ]] && tcp_wmem_high=16777216
    [[ $somaxconn -lt 1024 ]] && somaxconn=1024
    [[ $netdev_backlog -lt 10000 ]] && netdev_backlog=10000
    
    # 输出参数（用于显示和应用）
    echo "algo=$algo"
    echo "qdisc=$qdisc"
    echo "rmem_max=$rmem_max"
    echo "wmem_max=$wmem_max"
    echo "tcp_rmem_high=$tcp_rmem_high"
    echo "tcp_wmem_high=$tcp_wmem_high"
    echo "somaxconn=$somaxconn"
    echo "netdev_backlog=$netdev_backlog"
    echo "tcp_fastopen=$tcp_fastopen" 
    echo "tcp_low_latency=$tcp_low_latency"
    echo "tcp_slow_start=$tcp_slow_start"
    echo "tcp_notsent_lowat=$tcp_notsent_lowat"
}

# 显示场景模式参数摘要
show_scene_params_summary() {
    local mode="$1"
    
    # 确保服务器资源已检测
    [[ $SERVER_CPU_CORES -eq 0 ]] && detect_server_resources
    
    echo
    print_header "$(get_scene_name "$mode") 参数摘要"
    echo
    echo -e "  ${BOLD}优化目标:${NC} $(get_scene_description "$mode")"
    echo
    
    # 代理模式显示详细说明
    if [[ "$mode" == "proxy" ]]; then
        echo -e "  ${BOLD}适用场景:${NC}"
        echo "    • V2Ray / Xray / Trojan / Trojan-Go"
        echo "    • Shadowsocks / ShadowsocksR / Clash"
        echo "    • WireGuard / OpenVPN / IPsec"
        echo "    • Hysteria / TUIC / NaiveProxy"
        echo "    • 其他代理/VPN 协议"
        echo
        echo -e "  ${BOLD}核心优化:${NC}"
        echo -e "    • ${GREEN}抗丢包${NC}: BBR3 对丢包不敏感，跨国线路更稳定"
        echo -e "    • ${GREEN}低延迟${NC}: 优化 TCP 参数减少响应时间"
        echo -e "    • ${GREEN}快速重连${NC}: 禁用慢启动，断线重连更快"
        echo -e "    • ${GREEN}TFO 加速${NC}: TCP Fast Open 减少握手延迟"
        echo
        echo -e "  ${BOLD}连接优化:${NC}"
        echo -e "    • ${CYAN}快速释放${NC}: FIN 超时 15 秒，快速回收资源"
        echo -e "    • ${CYAN}TIME_WAIT${NC}: 50 万桶，支持高并发短连接"
        echo -e "    • ${CYAN}端口范围${NC}: 1024-65535，更多可用端口"
        echo -e "    • ${CYAN}SYN 优化${NC}: 减少重试次数，加快连接建立"
        echo
    fi
    
    echo -e "  ${BOLD}关键参数:${NC}"
    
    # 解析参数
    local params
    params=$(get_scene_params "$mode")
    
    local algo qdisc rmem wmem somaxconn backlog fastopen lowlat slowstart notsent
    algo=$(echo "$params" | grep "^algo=" | cut -d= -f2)
    qdisc=$(echo "$params" | grep "^qdisc=" | cut -d= -f2)
    rmem=$(echo "$params" | grep "^rmem_max=" | cut -d= -f2)
    wmem=$(echo "$params" | grep "^wmem_max=" | cut -d= -f2)
    somaxconn=$(echo "$params" | grep "^somaxconn=" | cut -d= -f2)
    backlog=$(echo "$params" | grep "^netdev_backlog=" | cut -d= -f2)
    fastopen=$(echo "$params" | grep "^tcp_fastopen=" | cut -d= -f2)
    lowlat=$(echo "$params" | grep "^tcp_low_latency=" | cut -d= -f2)
    slowstart=$(echo "$params" | grep "^tcp_slow_start=" | cut -d= -f2)
    notsent=$(echo "$params" | grep "^tcp_notsent_lowat=" | cut -d= -f2)
    
    printf "    %-25s : %s (自动检测)\n" "拥塞控制算法" "$algo"
    printf "    %-25s : %s (自动检测)\n" "队列规则" "$qdisc"
    printf "    %-25s : %s (%s MB)\n" "接收缓冲区" "$rmem" "$((rmem/1024/1024))"
    printf "    %-25s : %s (%s MB)\n" "发送缓冲区" "$wmem" "$((wmem/1024/1024))"
    printf "    %-25s : %s\n" "最大连接队列" "$somaxconn"
    printf "    %-25s : %s\n" "网络设备队列" "$backlog"
    printf "    %-25s : %s\n" "TCP Fast Open" "$fastopen"
    
    # 代理模式显示额外参数（根据 VPS 配置动态计算）
    if [[ "$mode" == "proxy" ]]; then
        printf "    %-25s : %s (禁用=更快重连)\n" "慢启动" "$slowstart"
        printf "    %-25s : %s (较小=更低延迟)\n" "发送低水位" "$notsent"
        echo
        
        # 动态计算代理专用参数
        local tw_buckets orphans
        if [[ $SERVER_MEMORY_MB -le 512 ]]; then
            tw_buckets=100000; orphans=32768
        elif [[ $SERVER_MEMORY_MB -le 1024 ]]; then
            tw_buckets=200000; orphans=65535
        elif [[ $SERVER_MEMORY_MB -le 2048 ]]; then
            tw_buckets=300000; orphans=65535
        else
            tw_buckets=500000; orphans=131072
        fi
        
        echo -e "  ${BOLD}代理专用优化 (根据 ${SERVER_MEMORY_MB}MB 内存动态调整):${NC}"
        printf "    %-25s : %s\n" "FIN 超时" "15秒 (快速释放)"
        printf "    %-25s : %s\n" "Keepalive 时间" "600秒"
        printf "    %-25s : %s (根据内存)\n" "TIME_WAIT 桶" "$tw_buckets"
        printf "    %-25s : %s\n" "端口范围" "1024-65535"
        printf "    %-25s : %s\n" "SYN 重试" "2次"
        printf "    %-25s : %s (根据内存)\n" "孤儿连接上限" "$orphans"
    fi
    echo
}

# 应用场景模式
apply_scene_mode() {
    local mode="$1"
    
    log_info "应用场景模式: $mode"
    
    # 获取参数
    local params
    params=$(get_scene_params "$mode")
    
    # 解析参数
    local algo qdisc rmem_max wmem_max tcp_rmem_high tcp_wmem_high
    local somaxconn netdev_backlog tcp_fastopen tcp_low_latency tcp_slow_start tcp_notsent_lowat
    
    algo=$(echo "$params" | grep "^algo=" | cut -d= -f2)
    qdisc=$(echo "$params" | grep "^qdisc=" | cut -d= -f2)
    rmem_max=$(echo "$params" | grep "^rmem_max=" | cut -d= -f2)
    wmem_max=$(echo "$params" | grep "^wmem_max=" | cut -d= -f2)
    tcp_rmem_high=$(echo "$params" | grep "^tcp_rmem_high=" | cut -d= -f2)
    tcp_wmem_high=$(echo "$params" | grep "^tcp_wmem_high=" | cut -d= -f2)
    somaxconn=$(echo "$params" | grep "^somaxconn=" | cut -d= -f2)
    netdev_backlog=$(echo "$params" | grep "^netdev_backlog=" | cut -d= -f2)
    tcp_fastopen=$(echo "$params" | grep "^tcp_fastopen=" | cut -d= -f2)
    tcp_low_latency=$(echo "$params" | grep "^tcp_low_latency=" | cut -d= -f2)
    tcp_slow_start=$(echo "$params" | grep "^tcp_slow_start=" | cut -d= -f2)
    tcp_notsent_lowat=$(echo "$params" | grep "^tcp_notsent_lowat=" | cut -d= -f2)
    
    # 备份当前配置
    backup_config
    
    # 写入配置文件
    local proxy_header=""
    if [[ "$mode" == "proxy" ]]; then
        proxy_header="# 
# ========== 代理模式详解 ==========
# 适用: V2Ray/Xray/Trojan/SS/WireGuard/Hysteria 等
# 特点:
#   - 抗丢包: BBR3 对丢包不敏感，跨国线路更稳定
#   - 低延迟: 优化 TCP 参数减少响应时间
#   - 快速重连: tcp_slow_start=0 断线重连更快
#   - TFO加速: tcp_fastopen=3 减少握手延迟
#   - 适中缓冲: 平衡延迟和吞吐量
#"
    fi
    
    cat > "$SYSCTL_FILE" << CONF
# BBR3 Script 场景配置
# 场景模式: $(get_scene_name "$mode")
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 版本: ${SCRIPT_VERSION}
# 内核版本: $(uname -r)
${proxy_header}
# ========== 拥塞控制（自动检测最佳算法）==========
# 算法: ${algo} (自动选择: BBR3 > BBR2 > BBR > CUBIC)
# 队列: ${qdisc} (根据场景自动匹配)
net.ipv4.tcp_congestion_control = ${algo}
net.core.default_qdisc = ${qdisc}

# ========== 缓冲区配置 ==========
net.core.rmem_max = ${rmem_max}
net.core.wmem_max = ${wmem_max}
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 ${tcp_rmem_high}
net.ipv4.tcp_wmem = 4096 65536 ${tcp_wmem_high}
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# ========== 连接优化 ==========
net.core.somaxconn = ${somaxconn}
net.core.netdev_max_backlog = ${netdev_backlog}
net.ipv4.tcp_max_syn_backlog = ${somaxconn}
net.ipv4.tcp_fastopen = ${tcp_fastopen}

# ========== TCP 优化 ==========
# 注意: tcp_low_latency 在 Linux 4.14+ 已移除，不再设置
net.ipv4.tcp_slow_start_after_idle = ${tcp_slow_start}
net.ipv4.tcp_notsent_lowat = ${tcp_notsent_lowat}
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_syncookies = 1
CONF

    # 代理模式添加专用优化参数（根据 VPS 配置动态调整）
    if [[ "$mode" == "proxy" ]]; then
        # 根据内存动态计算参数
        local tw_buckets orphans tcp_mem_low tcp_mem_pressure tcp_mem_high
        
        # TIME_WAIT 桶数量：根据内存调整
        # 512MB -> 100000, 1GB -> 200000, 2GB -> 300000, 4GB+ -> 500000
        if [[ $SERVER_MEMORY_MB -le 512 ]]; then
            tw_buckets=100000
            orphans=32768
        elif [[ $SERVER_MEMORY_MB -le 1024 ]]; then
            tw_buckets=200000
            orphans=65535
        elif [[ $SERVER_MEMORY_MB -le 2048 ]]; then
            tw_buckets=300000
            orphans=65535
        else
            tw_buckets=500000
            orphans=131072
        fi
        
        # TCP 内存限制：根据总内存调整（单位：页，4KB/页）
        # 低水位 = 内存的 1/16，压力值 = 1/8，高水位 = 1/4
        local mem_pages=$((SERVER_MEMORY_MB * 256))  # MB 转页数
        tcp_mem_low=$((mem_pages / 16))
        tcp_mem_pressure=$((mem_pages / 8))
        tcp_mem_high=$((mem_pages / 4))
        
        # 确保最小值
        [[ $tcp_mem_low -lt 65536 ]] && tcp_mem_low=65536
        [[ $tcp_mem_pressure -lt 131072 ]] && tcp_mem_pressure=131072
        [[ $tcp_mem_high -lt 262144 ]] && tcp_mem_high=262144
        
        cat >> "$SYSCTL_FILE" << PROXY_CONF

# ========== 代理模式专用优化 ==========
# 根据 VPS 配置动态调整: CPU=${SERVER_CPU_CORES}核, 内存=${SERVER_MEMORY_MB}MB

# 连接超时优化（更快释放资源）
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15

# TIME_WAIT 优化（根据内存动态调整）
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = ${tw_buckets}

# 端口范围扩大（支持更多并发连接）
net.ipv4.ip_local_port_range = 1024 65535

# SYN 队列优化（根据 CPU 核心数调整）
net.ipv4.tcp_max_syn_backlog = ${somaxconn}
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# 孤儿连接优化（根据内存调整）
net.ipv4.tcp_orphan_retries = 2
net.ipv4.tcp_max_orphans = ${orphans}

# 重传优化（跨国线路重要）
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 8

# 内存优化（根据总内存动态调整）
net.ipv4.tcp_mem = ${tcp_mem_low} ${tcp_mem_pressure} ${tcp_mem_high}
net.ipv4.udp_mem = ${tcp_mem_low} ${tcp_mem_pressure} ${tcp_mem_high}

# IPv6 优化（如果启用）
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
PROXY_CONF
    else
        # 非代理模式使用标准参数
        cat >> "$SYSCTL_FILE" << 'STD_CONF'

# ========== 连接管理 ==========
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.ip_local_port_range = 1024 65535
STD_CONF
    fi
    
    # 应用配置（忽略不支持的参数）
    local sysctl_output
    local sysctl_errors=0
    
    # 先尝试完整应用
    local sysctl_applied=0
    if sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
        print_success "配置已完整应用"
    else
        # 如果失败，逐行应用，跳过不支持的参数
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 跳过空行和注释
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            
            # 尝试应用单个参数
            if sysctl -w "$line" >/dev/null 2>&1; then
                ((++sysctl_applied))
            else
                ((++sysctl_errors))
            fi
        done < "$SYSCTL_FILE"
        
        if [[ $sysctl_errors -gt 0 ]]; then
            print_info "已应用 ${sysctl_applied} 项，${sysctl_errors} 项不被当前内核支持（不影响核心功能）"
        else
            print_success "配置已完整应用"
        fi
    fi
    
    # 应用 qdisc
    apply_qdisc_runtime "$qdisc" 2>/dev/null || true
    
    # 记录到日志
    log_info "场景模式已应用: $(get_scene_name "$mode")"
    log_info "参数: algo=$algo, qdisc=$qdisc, rmem=$rmem_max, wmem=$wmem_max"
    
    SCENE_MODE="$mode"
    return 0
}

#===============================================================================
# 代理服务器智能调优向导
#===============================================================================

# 缓冲区大小常量
readonly BUFFER_16MB=16777216
readonly BUFFER_32MB=33554432
readonly BUFFER_64MB=67108864
readonly BUFFER_128MB=134217728

# 连接数常量
readonly MAX_SOMAXCONN=65535
readonly MAX_CONNTRACK=262144

# 代理调优配置变量
PROXY_HARDWARE_SCORE=0
PROXY_IS_LOW_SPEC=false
PROXY_CHAIN_ARCH=""
PROXY_NODE_ROLE=""
PROXY_SERVER_LOCATION=""
PROXY_CLIENT_LOCATION=""
PROXY_LINE_TYPE=""
PROXY_KERNEL=""
PROXY_PROTOCOL=""
PROXY_RESOURCE_RATIO=100
PROXY_ADVANCED_OPTS=""
PROXY_PROFILE_FILE="/etc/bbr3-profile.conf"

# 检测完整硬件信息
detect_full_hardware() {
    local cpu_score=0
    local mem_score=0
    local disk_score=0
    
    # CPU 评分 (0-100)
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo 1)
    if [[ $cpu_cores -ge 8 ]]; then
        cpu_score=100
    elif [[ $cpu_cores -ge 4 ]]; then
        cpu_score=80
    elif [[ $cpu_cores -ge 2 ]]; then
        cpu_score=60
    else
        cpu_score=30
    fi
    
    # 内存评分 (0-100)
    local mem_mb
    mem_mb=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 512)
    if [[ $mem_mb -ge 8192 ]]; then
        mem_score=100
    elif [[ $mem_mb -ge 4096 ]]; then
        mem_score=80
    elif [[ $mem_mb -ge 2048 ]]; then
        mem_score=60
    elif [[ $mem_mb -ge 1024 ]]; then
        mem_score=40
    else
        mem_score=20
    fi
    
    # 磁盘评分 (0-100)
    local disk_type="hdd"
    if [[ -d /sys/block ]]; then
        local disk
        for disk in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
            [[ -e "$disk" ]] || continue
            local rotational
            rotational=$(cat "${disk}/queue/rotational" 2>/dev/null || echo 1)
            if [[ "$rotational" == "0" ]]; then
                if [[ "$disk" == *nvme* ]]; then
                    disk_type="nvme"
                else
                    disk_type="ssd"
                fi
                break
            fi
        done
    fi
    
    case "$disk_type" in
        nvme) disk_score=100 ;;
        ssd)  disk_score=80 ;;
        *)    disk_score=40 ;;
    esac
    
    # 综合评分
    PROXY_HARDWARE_SCORE=$(( (cpu_score * 30 + mem_score * 40 + disk_score * 30) / 100 ))
    
    # 存储检测结果
    PROXY_CPU_CORES=$cpu_cores
    PROXY_MEM_MB=$mem_mb
    PROXY_DISK_TYPE=$disk_type
}

# 检测是否为低配 VPS
is_low_spec_vps() {
    detect_full_hardware
    
    if [[ $PROXY_MEM_MB -le 1024 ]] || [[ $PROXY_CPU_CORES -le 1 ]]; then
        PROXY_IS_LOW_SPEC=true
        return 0
    fi
    PROXY_IS_LOW_SPEC=false
    return 1
}

# 显示硬件报告
show_hardware_report() {
    detect_full_hardware
    is_low_spec_vps
    
    # 确保系统信息已检测
    [[ -z "${DIST_ID:-}" ]] && detect_os
    
    echo
    echo -e "  ${BOLD}硬件检测结果${NC}"
    print_separator
    echo
    printf "    %-15s : %s 核\n" "CPU" "$PROXY_CPU_CORES"
    printf "    %-15s : %s MB\n" "内存" "$PROXY_MEM_MB"
    printf "    %-15s : %s\n" "磁盘类型" "$PROXY_DISK_TYPE"
    printf "    %-15s : %s\n" "系统" "${DIST_ID:-unknown} ${DIST_VER:-unknown}"
    printf "    %-15s : %s\n" "内核" "$(uname -r)"
    printf "    %-15s : %s\n" "虚拟化" "${VIRT_TYPE:-未知}"
    echo
    printf "    %-15s : %s/100\n" "硬件评分" "$PROXY_HARDWARE_SCORE"
    
    if [[ "$PROXY_IS_LOW_SPEC" == "true" ]]; then
        echo
        echo -e "    ${YELLOW}${ICON_WARN} 检测到低配 VPS，将启用激进优化模式${NC}"
    fi
    echo
}

# 检测当前内核
check_current_kernel() {
    local kernel_version
    kernel_version=$(uname -r)
    local kver_short
    kver_short=$(echo "$kernel_version" | sed 's/[^0-9.].*$//')
    
    local has_bbr3=false
    local is_mainline_bbr3=false
    
    if [[ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
        # 检查是否有 bbr3 算法
        if grep -q "bbr3" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            has_bbr3=true
        # 检查主线内核 >= 6.9 的 BBR3 (以 bbr 名称提供)
        elif grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            if version_ge "$kver_short" "6.9.0"; then
                has_bbr3=true
                is_mainline_bbr3=true
            fi
        fi
    fi
    
    echo
    echo -e "  ${BOLD}内核检测${NC}"
    print_separator
    echo
    printf "    %-15s : %s\n" "当前内核" "$kernel_version"
    
    if [[ "$has_bbr3" == "true" ]]; then
        if [[ "$is_mainline_bbr3" == "true" ]]; then
            printf "    %-15s : ${GREEN}✅ 已支持 (内核内置)${NC}\n" "BBR3 支持"
        else
            printf "    %-15s : ${GREEN}✅ 已支持${NC}\n" "BBR3 支持"
        fi
    else
        printf "    %-15s : ${YELLOW}❌ 需要安装新内核${NC}\n" "BBR3 支持"
    fi
    echo
    
    [[ "$has_bbr3" == "true" ]]
}

# 询问链路架构
ask_chain_architecture() {
    echo
    echo -e "  ${BOLD}Q1. 这台机器的链路架构是什么？${NC}"
    echo
    echo -e "    ${CYAN}1)${NC} 单机模式 (用户直连本机)"
    echo -e "    ${CYAN}2)${NC} 中转链路 (用户 → 本机 → 落地机)"
    echo -e "    ${CYAN}3)${NC} 落地节点 (中转机 → 本机 → 目标网站)"
    echo -e "    ${CYAN}4)${NC} 多级中转 (入口 → 本机 → 落地机)"
    echo
    
    read_choice "您的选择" 4
    
    case "$MENU_CHOICE" in
        1) PROXY_CHAIN_ARCH="single"; PROXY_NODE_ROLE="single" ;;
        2) PROXY_CHAIN_ARCH="relay"; PROXY_NODE_ROLE="relay" ;;
        3) PROXY_CHAIN_ARCH="exit"; PROXY_NODE_ROLE="exit" ;;
        4) PROXY_CHAIN_ARCH="multi"; PROXY_NODE_ROLE="relay" ;;
    esac
}

# 询问服务器位置
ask_server_location() {
    echo
    echo -e "  ${BOLD}Q2. 这台服务器在哪里？${NC}"
    echo
    echo -e "    ${CYAN}1)${NC} 美国        ${CYAN}5)${NC} 台湾"
    echo -e "    ${CYAN}2)${NC} 日本        ${CYAN}6)${NC} 韩国"
    echo -e "    ${CYAN}3)${NC} 香港        ${CYAN}7)${NC} 欧洲"
    echo -e "    ${CYAN}4)${NC} 新加坡      ${CYAN}8)${NC} 其他"
    echo
    
    read_choice "您的选择" 8
    
    case "$MENU_CHOICE" in
        1) PROXY_SERVER_LOCATION="us" ;;
        2) PROXY_SERVER_LOCATION="jp" ;;
        3) PROXY_SERVER_LOCATION="hk" ;;
        4) PROXY_SERVER_LOCATION="sg" ;;
        5) PROXY_SERVER_LOCATION="tw" ;;
        6) PROXY_SERVER_LOCATION="kr" ;;
        7) PROXY_SERVER_LOCATION="eu" ;;
        8) PROXY_SERVER_LOCATION="other" ;;
    esac
}

# 询问客户端位置
ask_client_location() {
    echo
    echo -e "  ${BOLD}Q3. 翻墙用户主要在哪里？${NC}"
    echo
    echo -e "    ${CYAN}1)${NC} 中国大陆 - 电信用户为主"
    echo -e "    ${CYAN}2)${NC} 中国大陆 - 联通用户为主"
    echo -e "    ${CYAN}3)${NC} 中国大陆 - 移动用户为主"
    echo -e "    ${CYAN}4)${NC} 中国大陆 - 混合运营商"
    echo -e "    ${CYAN}5)${NC} 海外华人"
    echo
    
    read_choice "您的选择" 5
    
    case "$MENU_CHOICE" in
        1) PROXY_CLIENT_LOCATION="cn_telecom" ;;
        2) PROXY_CLIENT_LOCATION="cn_unicom" ;;
        3) PROXY_CLIENT_LOCATION="cn_mobile" ;;
        4) PROXY_CLIENT_LOCATION="cn_mixed" ;;
        5) PROXY_CLIENT_LOCATION="overseas" ;;
    esac
}

# 询问线路类型
ask_line_type() {
    echo
    echo -e "  ${BOLD}Q4. 这台机器的线路类型？（不确定可选 7）${NC}"
    echo
    echo -e "    ${CYAN}1)${NC} CN2 GIA (电信顶级，低延迟低丢包)"
    echo -e "    ${CYAN}2)${NC} CN2 GT  (电信优质)"
    echo -e "    ${CYAN}3)${NC} CMI     (移动国际)"
    echo -e "    ${CYAN}4)${NC} 9929    (联通A网，优质)"
    echo -e "    ${CYAN}5)${NC} 4837    (联通普通，晚高峰拥堵)"
    echo -e "    ${CYAN}6)${NC} 163     (电信普通，晚高峰丢包)"
    echo -e "    ${CYAN}7)${NC} 不确定 / 自动检测"
    echo
    
    read_choice "您的选择" 7
    
    case "$MENU_CHOICE" in
        1) PROXY_LINE_TYPE="cn2gia" ;;
        2) PROXY_LINE_TYPE="cn2gt" ;;
        3) PROXY_LINE_TYPE="cmi" ;;
        4) PROXY_LINE_TYPE="9929" ;;
        5) PROXY_LINE_TYPE="4837" ;;
        6) PROXY_LINE_TYPE="163" ;;
        7) PROXY_LINE_TYPE="auto"; detect_line_type ;;
    esac
}

# ========== 三网回程线路检测 ==========

# 三网测试 IP
declare -A CARRIER_TEST_IPS=(
    ["telecom"]="114.114.114.114"
    ["unicom"]="210.22.70.3"
    ["mobile"]="211.136.192.6"
)

# 运营商中文名
declare -A CARRIER_NAMES=(
    ["telecom"]="电信"
    ["unicom"]="联通"
    ["mobile"]="移动"
)

# 检测结果存储
declare -A RETURN_PATH_RESULTS

# 检查 nexttrace 是否已安装
check_nexttrace() {
    command -v nexttrace &>/dev/null
}

# 安装 nexttrace
#
# 安全说明:
#  - 通过 GitHub API 解析最新 release 的 tag,然后从同一 release 拉取 checksums.txt
#  - 校验下载二进制的 SHA256 后再安装
#  - 校验失败硬拒绝
#  - 使用 mktemp 替代固定路径 /tmp/nexttrace
install_nexttrace() {
    print_step "安装 nexttrace..."

    local arch=""
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) print_warn "不支持的架构: $(uname -m)"; return 1 ;;
    esac

    if ! command -v sha256sum >/dev/null 2>&1; then
        print_warn "未找到 sha256sum,无法校验 nexttrace 完整性,跳过安装"
        return 1
    fi

    # 解析最新 release tag(避免 /releases/latest/download 隐式跟随重定向且无版本可见)
    local tag
    tag=$(curl -fsSL --max-time 15 'https://api.github.com/repos/nxtrace/NTrace-core/releases/latest' 2>/dev/null \
        | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')
    if [[ -z "$tag" ]]; then
        print_warn "无法获取 nexttrace 最新 tag (网络/API 限流?)"
        return 1
    fi
    print_info "nexttrace tag: $tag"

    local base_url="https://github.com/nxtrace/NTrace-core/releases/download/${tag}"
    local bin_name="nexttrace_linux_${arch}"
    local bin_url="${base_url}/${bin_name}"
    local sums_url="${base_url}/checksums.txt"

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/bbr3-nexttrace-XXXXXX) || {
        print_error "无法创建临时目录"
        return 1
    }

    local bin_file="${tmp_dir}/${bin_name}"
    local sums_file="${tmp_dir}/checksums.txt"

    # 下载校验和文件
    if ! curl -fsSL --max-time 30 "$sums_url" -o "$sums_file"; then
        print_warn "无法下载 checksums.txt,拒绝安装(无校验源)"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    # 提取期望 SHA256
    local expected_sha
    expected_sha=$(awk -v f="$bin_name" '$2 == f || $2 == "*"f {print $1; exit}' "$sums_file")
    if [[ -z "$expected_sha" ]]; then
        print_warn "checksums.txt 中未找到 ${bin_name} 的 SHA256"
        rm -rf -- "$tmp_dir"
        return 1
    fi
    if [[ ! "$expected_sha" =~ ^[a-fA-F0-9]{64}$ ]]; then
        print_warn "SHA256 格式异常: $expected_sha"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    # 下载二进制
    if ! curl -fsSL --max-time 60 --max-filesize 52428800 "$bin_url" -o "$bin_file"; then
        print_warn "下载 nexttrace 二进制失败"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    # 校验
    local actual_sha
    actual_sha=$(sha256sum -- "$bin_file" 2>/dev/null | awk '{print $1}')
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        print_error "nexttrace SHA256 校验失败! 下载文件可能被篡改"
        print_error "  预期: $expected_sha"
        print_error "  实际: $actual_sha"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    chmod +x "$bin_file"
    if ! install -m 0755 -- "$bin_file" /usr/local/bin/nexttrace 2>/dev/null \
        && ! install -m 0755 -- "$bin_file" /usr/bin/nexttrace 2>/dev/null; then
        print_warn "无法安装 nexttrace 到 /usr/local/bin 或 /usr/bin"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    rm -rf -- "$tmp_dir"
    if check_nexttrace; then
        print_success "nexttrace 安装成功 (tag: ${tag})"
        return 0
    fi

    print_warn "nexttrace 安装失败，将使用备用方法"
    return 1
}

# 确保 nexttrace 可用
ensure_nexttrace() {
    if check_nexttrace; then
        return 0
    fi
    
    echo
    if confirm "需要安装 nexttrace 以精确检测三网回程，是否安装？" "y"; then
        install_nexttrace
        return $?
    else
        print_info "跳过 nexttrace 安装，将使用简化检测"
        return 1
    fi
}

# 使用 nexttrace 检测回程 AS 路径
detect_return_path_nexttrace() {
    local target_ip="$1"
    local timeout="${2:-15}"
    
    local output=""
    output=$(timeout "$timeout" nexttrace -q 1 -n "$target_ip" 2>/dev/null || true)
    
    if [[ -z "$output" ]]; then
        return 1
    fi
    
    # 提取 AS 号列表
    local as_list=""
    as_list=$(echo "$output" | grep -oE 'AS[0-9]+' | tr '\n' ' ' | sed 's/ $//')
    
    echo "$as_list"
}

# 使用 traceroute 检测回程 AS 路径 (备用)
detect_return_path_traceroute() {
    local target_ip="$1"
    local timeout="${2:-15}"
    
    if ! command -v traceroute &>/dev/null; then
        return 1
    fi
    
    local output=""
    output=$(timeout "$timeout" traceroute -A -n -m 15 "$target_ip" 2>/dev/null || true)
    
    if [[ -z "$output" ]]; then
        return 1
    fi
    
    # 提取 AS 号列表
    local as_list=""
    as_list=$(echo "$output" | grep -oE '\[AS[0-9]+\]' | sed 's/\[//g; s/\]//g' | tr '\n' ' ' | sed 's/ $//')
    
    echo "$as_list"
}

# 根据 AS 路径识别线路类型
identify_line_from_as() {
    local as_path="$1"
    local carrier="$2"
    
    local line_type="unknown"
    local line_name="未知"
    
    case "$carrier" in
        telecom)
            if echo "$as_path" | grep -q "AS4809"; then
                if echo "$as_path" | grep -q "AS4134"; then
                    line_type="cn2gt"
                    line_name="CN2 GT"
                else
                    line_type="cn2gia"
                    line_name="CN2 GIA"
                fi
            elif echo "$as_path" | grep -q "AS4134"; then
                line_type="163"
                line_name="163"
            fi
            ;;
        unicom)
            if echo "$as_path" | grep -q "AS9929"; then
                line_type="9929"
                line_name="9929 (精品)"
            elif echo "$as_path" | grep -q "AS4837"; then
                line_type="4837"
                line_name="4837"
            elif echo "$as_path" | grep -q "AS10099"; then
                line_type="10099"
                line_name="10099 (国际)"
            fi
            ;;
        mobile)
            if echo "$as_path" | grep -q "AS58807"; then
                line_type="cmin2"
                line_name="CMIN2 (精品)"
            elif echo "$as_path" | grep -q "AS58453"; then
                line_type="cmi"
                line_name="CMI"
            elif echo "$as_path" | grep -q "AS9808"; then
                line_type="mobile"
                line_name="移动骨干"
            fi
            ;;
    esac
    
    echo "${line_type}|${line_name}"
}

# 检测单个运营商回程
detect_carrier_return_path() {
    local carrier="$1"
    local target_ip="${CARRIER_TEST_IPS[$carrier]}"
    local carrier_name="${CARRIER_NAMES[$carrier]}"
    
    echo -n "  检测${carrier_name}回程..."
    
    local as_path=""
    
    # 优先使用 nexttrace
    if check_nexttrace; then
        as_path=$(detect_return_path_nexttrace "$target_ip" 15)
    fi
    
    # 降级到 traceroute
    if [[ -z "$as_path" ]]; then
        as_path=$(detect_return_path_traceroute "$target_ip" 15)
    fi
    
    if [[ -n "$as_path" ]]; then
        local result
        result=$(identify_line_from_as "$as_path" "$carrier")
        local line_type="${result%%|*}"
        local line_name="${result##*|}"
        
        RETURN_PATH_RESULTS["${carrier}_type"]="$line_type"
        RETURN_PATH_RESULTS["${carrier}_name"]="$line_name"
        RETURN_PATH_RESULTS["${carrier}_as"]="$as_path"
        
        echo -e " ${GREEN}${line_name}${NC}"
    else
        RETURN_PATH_RESULTS["${carrier}_type"]="timeout"
        RETURN_PATH_RESULTS["${carrier}_name"]="检测超时"
        RETURN_PATH_RESULTS["${carrier}_as"]="-"
        
        echo -e " ${YELLOW}超时${NC}"
    fi
}

# 显示三网回程检测结果
show_return_path_results() {
    echo
    echo -e "  ${BOLD}三网回程检测结果${NC}"
    print_separator
    echo
    printf "    ${BOLD}%-8s${NC} │ ${BOLD}%-15s${NC} │ ${BOLD}%-s${NC}\n" "运营商" "回程线路" "关键 AS"
    echo "    ─────────┼─────────────────┼──────────────────────"
    
    for carrier in telecom unicom mobile; do
        local name="${CARRIER_NAMES[$carrier]}"
        local line="${RETURN_PATH_RESULTS[${carrier}_name]:-未检测}"
        local as_path="${RETURN_PATH_RESULTS[${carrier}_as]:-}"
        
        # 截取关键 AS (最多显示 3 个)
        local key_as=""
        key_as=$(echo "$as_path" | awk '{for(i=1;i<=3&&i<=NF;i++) printf "%s ", $i}' | sed 's/ $//')
        [[ -z "$key_as" ]] && key_as="-"
        
        printf "    %-8s │ %-15s │ %s\n" "$name" "$line" "$key_as"
    done
    echo
}

# 根据三网检测结果推荐最优线路配置
recommend_line_config() {
    local telecom_type="${RETURN_PATH_RESULTS[telecom_type]:-unknown}"
    local unicom_type="${RETURN_PATH_RESULTS[unicom_type]:-unknown}"
    local mobile_type="${RETURN_PATH_RESULTS[mobile_type]:-unknown}"
    
    # 优先级: cn2gia > cmin2 > 9929 > cn2gt > cmi > 4837 > 163 > unknown
    local best_type="unknown"
    
    if [[ "$telecom_type" == "cn2gia" ]]; then
        best_type="cn2gia"
    elif [[ "$mobile_type" == "cmin2" ]]; then
        best_type="cmin2"
    elif [[ "$unicom_type" == "9929" ]]; then
        best_type="9929"
    elif [[ "$telecom_type" == "cn2gt" ]]; then
        best_type="cn2gt"
    elif [[ "$mobile_type" == "cmi" ]]; then
        best_type="cmi"
    elif [[ "$unicom_type" == "4837" ]]; then
        best_type="4837"
    elif [[ "$telecom_type" == "163" ]]; then
        best_type="163"
    fi
    
    echo "$best_type"
}

# 自动检测线路类型 (增强版 - 三网回程检测)
detect_line_type() {
    echo
    print_info "正在自动检测线路类型..."
    echo
    
    # 尝试使用三网回程检测
    local use_advanced=false
    
    if check_nexttrace || command -v traceroute &>/dev/null; then
        # 询问是否进行详细检测
        if confirm "是否进行三网回程详细检测？(约 30-60 秒)" "y"; then
            use_advanced=true
            
            # 如果没有 nexttrace，尝试安装
            if ! check_nexttrace; then
                ensure_nexttrace || true
            fi
            
            echo
            print_step "开始三网回程检测..."
            echo
            
            # 检测三网回程
            for carrier in telecom unicom mobile; do
                detect_carrier_return_path "$carrier"
            done
            
            # 显示结果
            show_return_path_results
            
            # 推荐配置
            local recommended
            recommended=$(recommend_line_config)
            
            if [[ "$recommended" != "unknown" ]]; then
                PROXY_LINE_TYPE="$recommended"
                local type_name=""
                case "$recommended" in
                    cn2gia) type_name="CN2 GIA" ;;
                    cn2gt) type_name="CN2 GT" ;;
                    cmi) type_name="CMI" ;;
                    cmin2) type_name="CMIN2" ;;
                    9929) type_name="9929" ;;
                    4837) type_name="4837" ;;
                    163) type_name="163" ;;
                esac
                print_success "推荐配置: $type_name"
                return 0
            fi
        fi
    fi
    
    # 降级: 使用简单的 AS 检测
    if [[ "$use_advanced" == "false" ]] || [[ "$PROXY_LINE_TYPE" == "unknown" ]]; then
        print_info "使用简化检测..."
        
        local as_num=""
        
        # 方法1: 使用 ipinfo.io API 获取 AS 信息
        local org_info=""
        org_info=$(curl -s --max-time 5 ipinfo.io/org 2>/dev/null || true)
        if [[ -n "$org_info" ]]; then
            as_num=$(echo "$org_info" | grep -oE 'AS[0-9]+' | head -1 || true)
        fi
        
        if [[ -n "$as_num" ]]; then
            log_debug "检测到 AS 号: $as_num"
            case "$as_num" in
                AS4809)  PROXY_LINE_TYPE="cn2gia"; print_success "检测到 CN2 线路 ($as_num)" ;;
                AS58453) PROXY_LINE_TYPE="cmi"; print_success "检测到 CMI 线路 ($as_num)" ;;
                AS9929)  PROXY_LINE_TYPE="9929"; print_success "检测到 9929 线路 ($as_num)" ;;
                AS4837)  PROXY_LINE_TYPE="4837"; print_success "检测到 4837 线路 ($as_num)" ;;
                AS4134)  PROXY_LINE_TYPE="163"; print_success "检测到 163 线路 ($as_num)" ;;
                *)       PROXY_LINE_TYPE="unknown"; print_info "AS: $as_num (非中国运营商，使用通用配置)" ;;
            esac
        else
            PROXY_LINE_TYPE="unknown"
            print_warn "无法检测线路类型，使用默认配置"
        fi
    fi
}

# 询问代理内核
ask_proxy_kernel() {
    echo
    echo -e "  ${BOLD}Q5. 使用什么代理内核？${NC}"
    echo
    echo -e "    ${CYAN}1)${NC} Xray"
    echo -e "    ${CYAN}2)${NC} Sing-box"
    echo -e "    ${CYAN}3)${NC} V2Ray"
    echo -e "    ${CYAN}4)${NC} Clash / Mihomo"
    echo -e "    ${CYAN}5)${NC} Hysteria (独立)"
    echo -e "    ${CYAN}6)${NC} 其他 / 不确定"
    echo
    
    read_choice "您的选择" 6
    
    case "$MENU_CHOICE" in
        1) PROXY_KERNEL="xray" ;;
        2) PROXY_KERNEL="singbox" ;;
        3) PROXY_KERNEL="v2ray" ;;
        4) PROXY_KERNEL="clash" ;;
        5) PROXY_KERNEL="hysteria" ;;
        6) PROXY_KERNEL="other" ;;
    esac
}

# 询问代理协议
ask_proxy_protocol() {
    echo
    echo -e "  ${BOLD}Q6. 使用什么代理协议？${NC}"
    echo
    echo -e "    ${DIM}TCP 协议 (BBR3 优化生效):${NC}"
    echo -e "    ${CYAN}1)${NC} VLESS / VMess"
    echo -e "    ${CYAN}2)${NC} Trojan"
    echo -e "    ${CYAN}3)${NC} Shadowsocks"
    echo -e "    ${CYAN}4)${NC} Naive"
    echo
    echo -e "    ${DIM}UDP/QUIC 协议 (需要 UDP 缓冲优化):${NC}"
    echo -e "    ${CYAN}5)${NC} Hysteria / Hysteria2"
    echo -e "    ${CYAN}6)${NC} TUIC"
    echo
    echo -e "    ${DIM}特殊模式:${NC}"
    echo -e "    ${CYAN}7)${NC} Tun / TProxy (透明代理)"
    echo -e "    ${CYAN}8)${NC} 混合使用"
    echo
    
    read_choice "您的选择" 8
    
    case "$MENU_CHOICE" in
        1) PROXY_PROTOCOL="vless" ;;
        2) PROXY_PROTOCOL="trojan" ;;
        3) PROXY_PROTOCOL="ss" ;;
        4) PROXY_PROTOCOL="naive" ;;
        5) PROXY_PROTOCOL="hysteria" ;;
        6) PROXY_PROTOCOL="tuic" ;;
        7) PROXY_PROTOCOL="tun" ;;
        8) PROXY_PROTOCOL="mixed" ;;
    esac
}

# 询问资源占比
ask_resource_ratio() {
    echo
    echo -e "  ${BOLD}Q7. 代理使用这台机器多少资源？${NC}"
    echo
    echo -e "    ${CYAN}1)${NC} 100% - 专用代理服务器（最激进优化）"
    echo -e "    ${CYAN}2)${NC} 80%  - 主要用于代理"
    echo -e "    ${CYAN}3)${NC} 50%  - 代理与其他用途各半"
    echo -e "    ${CYAN}4)${NC} 30%  - 代理为辅"
    echo
    
    read_choice "您的选择" 4
    
    case "$MENU_CHOICE" in
        1) PROXY_RESOURCE_RATIO=100 ;;
        2) PROXY_RESOURCE_RATIO=80 ;;
        3) PROXY_RESOURCE_RATIO=50 ;;
        4) PROXY_RESOURCE_RATIO=30 ;;
    esac
}

# 询问高级优化
ask_advanced_optimization() {
    echo
    echo -e "  ${BOLD}Q8. 是否启用高级系统优化？${NC}"
    echo
    echo -e "    ${CYAN}1)${NC} 是 - 启用全部推荐优化"
    echo -e "    ${CYAN}2)${NC} 自定义选择"
    echo -e "    ${CYAN}3)${NC} 否 - 仅使用基础优化"
    echo
    
    read_choice "您的选择" 3
    
    case "$MENU_CHOICE" in
        1) PROXY_ADVANCED_OPTS="all" ;;
        2) PROXY_ADVANCED_OPTS="custom" ;;
        3) PROXY_ADVANCED_OPTS="none" ;;
    esac
}

# 获取 TCP 协议参数
get_tcp_protocol_params() {
    cat << 'EOF'
# TCP 协议优化 (VLESS/VMess/Trojan/SS/Naive)
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_notsent_lowat = 16384
EOF
}

# 检测 conntrack 模块是否可用
check_conntrack_available() {
    [[ -f /proc/sys/net/netfilter/nf_conntrack_max ]]
}

# 获取 UDP 协议参数
get_udp_protocol_params() {
    echo "# UDP/QUIC 协议优化 (Hysteria/TUIC)"
    echo "# 注意: BBR3 对 QUIC 无效，QUIC 自带拥塞控制"
    echo "net.core.rmem_max = ${BUFFER_128MB}"
    echo "net.core.wmem_max = ${BUFFER_128MB}"
    echo "net.ipv4.udp_rmem_min = 16384"
    echo "net.ipv4.udp_wmem_min = 16384"
    
    # 仅在 conntrack 模块可用时输出相关参数
    if check_conntrack_available; then
        echo "net.netfilter.nf_conntrack_max = ${MAX_CONNTRACK}"
        echo "net.netfilter.nf_conntrack_udp_timeout = 60"
        echo "net.netfilter.nf_conntrack_udp_timeout_stream = 180"
    else
        echo "# conntrack 模块未加载，跳过相关参数"
    fi
}

# 获取 Tun/TProxy 参数
get_tun_tproxy_params() {
    cat << 'EOF'
# Tun/TProxy 透明代理优化
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.all.forwarding = 1
EOF
}

# 获取角色参数
get_role_params() {
    local role="$1"
    
    case "$role" in
        exit)
            # 落地机：大缓冲区，抗丢包
            echo "# 落地机优化：大缓冲区，抗丢包"
            echo "net.core.rmem_max = 67108864"
            echo "net.core.wmem_max = 67108864"
            echo "net.ipv4.tcp_rmem = 4096 131072 67108864"
            echo "net.ipv4.tcp_wmem = 4096 65536 67108864"
            echo "net.core.somaxconn = 4096"
            echo "net.ipv4.tcp_max_orphans = 65535"
            ;;
        relay)
            # 中转机：小缓冲区，低延迟
            echo "# 中转机优化：小缓冲区，低延迟"
            echo "net.core.rmem_max = 16777216"
            echo "net.core.wmem_max = 16777216"
            echo "net.ipv4.tcp_rmem = 4096 65536 16777216"
            echo "net.ipv4.tcp_wmem = 4096 32768 16777216"
            echo "net.core.somaxconn = 1024"
            echo "net.ipv4.tcp_notsent_lowat = 8192"
            ;;
        entry)
            # 入口机：高并发
            echo "# 入口机优化：高并发"
            echo "net.core.somaxconn = 65535"
            echo "net.core.netdev_max_backlog = 65535"
            echo "net.ipv4.tcp_max_syn_backlog = 65535"
            ;;
        *)
            # 单机：均衡配置
            echo "# 单机模式：均衡配置"
            echo "net.core.rmem_max = 33554432"
            echo "net.core.wmem_max = 33554432"
            echo "net.ipv4.tcp_rmem = 4096 87380 33554432"
            echo "net.ipv4.tcp_wmem = 4096 65536 33554432"
            echo "net.core.somaxconn = 4096"
            ;;
    esac
}

# 获取高级 sysctl 参数
get_advanced_sysctl_params() {
    cat << 'EOF'
# 高级系统优化
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_timestamps = 1
net.core.busy_poll = 50
net.core.busy_read = 50

# TCP 初始窗口优化（减少首包延迟）
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_moderate_rcvbuf = 1

# 端口范围和 TIME_WAIT 优化（高并发）
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144

# SYN 队列优化（高并发连接）
net.ipv4.tcp_max_syn_backlog = 65535
net.core.somaxconn = 65535

# 连接跟踪优化（高并发场景）
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30

# 网络队列优化
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000

# ARP 缓存优化
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 4096
net.ipv4.neigh.default.gc_thresh3 = 8192

# TCP Keepalive 优化（保持连接活跃）
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# 路由缓存优化
net.ipv4.route.max_size = 2147483647
EOF
}

# 获取抗丢包优化参数（中转机/高丢包环境专用）
get_anti_loss_sysctl_params() {
    cat << 'EOF'
# ========== 抗丢包优化（中转机/高丢包环境）==========
# 适用场景：中转机、跨国线路、丢包率 5-15% 的环境

# 拥塞控制（BBR 对丢包不敏感）
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# ========== 核心抗丢包参数 ==========
# 增加 TCP 重传次数（默认 15，高丢包环境需要更多）
net.ipv4.tcp_retries1 = 5
net.ipv4.tcp_retries2 = 30

# 增加 SYN 重试次数（默认 6）
net.ipv4.tcp_syn_retries = 6
net.ipv4.tcp_synack_retries = 6

# 增加孤儿连接重试（默认 0）
net.ipv4.tcp_orphan_retries = 5

# ========== 缓冲区优化（应对突发丢包）==========
# 更大的缓冲区可以容纳更多待重传数据
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 134217728
net.ipv4.tcp_wmem = 4096 1048576 134217728

# ========== SACK/DSACK 优化（选择性确认）==========
# 启用 SACK 可以只重传丢失的包，而不是整个窗口
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fack = 1

# ========== 时间戳和窗口缩放 ==========
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1

# ========== 网络队列优化（防止队列溢出丢包）==========
net.core.netdev_max_backlog = 65535
net.core.netdev_budget = 1200
net.core.netdev_budget_usecs = 16000

# ========== 连接队列优化 ==========
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# ========== Keepalive 优化（检测死连接）==========
net.ipv4.tcp_keepalive_time = 30
net.ipv4.tcp_keepalive_intvl = 5
net.ipv4.tcp_keepalive_probes = 9

# ========== 超时优化 ==========
net.ipv4.tcp_fin_timeout = 30

# ========== MTU 探测（自动适应路径 MTU）==========
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024

# ========== ECN 显式拥塞通知 ==========
net.ipv4.tcp_ecn = 2
net.ipv4.tcp_ecn_fallback = 1

# ========== 其他优化 ==========
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1

# ========== 连接跟踪优化 ==========
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
EOF
}

# 应用抗丢包优化
apply_anti_loss_optimization() {
    print_header "抗丢包优化（中转机专用）"
    
    echo -e "${CYAN}此优化适用于:${NC}"
    echo "  • 中转机/落地机场景"
    echo "  • 跨国线路丢包率 5-15%"
    echo "  • 连接不稳定、频繁断线"
    echo "  • ICMP 丢包严重"
    echo
    
    echo -e "${BOLD}优化内容:${NC}"
    echo "  • TCP 重传次数: 15 → 30"
    echo "  • SYN 重试次数: 2 → 6"
    echo "  • 缓冲区: 64MB → 128MB"
    echo "  • 网络队列: 5000 → 65535"
    echo "  • Keepalive: 更频繁检测"
    echo "  • MTU 探测: 自动适应"
    echo
    
    if ! confirm "确认应用抗丢包优化？" "y"; then
        return
    fi
    
    echo
    
    # 备份当前配置
    backup_config
    
    # 生成配置文件
    local anti_loss_file="/etc/sysctl.d/99-bbr-anti-loss.conf"
    
    cat > "$anti_loss_file" << CONF
# BBR3 抗丢包优化配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 适用场景: 中转机/高丢包环境

$(get_anti_loss_sysctl_params)
CONF
    
    # 应用配置
    print_step "应用抗丢包参数..."
    
    local applied=0 errors=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if sysctl -w "$line" >/dev/null 2>&1; then
            ((++applied))
        else
            ((++errors))
        fi
    done < "$anti_loss_file"
    
    if [[ $errors -gt 0 ]]; then
        print_info "已应用 ${applied} 项，${errors} 项不被当前内核支持"
    else
        print_success "抗丢包参数已全部应用"
    fi
    
    # 优化网卡队列
    print_step "优化网卡队列..."
    local nic
    nic=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    if [[ -n "$nic" ]]; then
        # 增加网卡队列长度
        ip link set "$nic" txqueuelen 10000 2>/dev/null && \
            print_success "网卡 $nic 队列长度已设置为 10000" || \
            print_warn "无法设置网卡队列长度"
        
        # 尝试启用 GRO/GSO
        ethtool -K "$nic" gro on 2>/dev/null
        ethtool -K "$nic" gso on 2>/dev/null
        ethtool -K "$nic" tso on 2>/dev/null
    fi
    
    echo
    echo -e "${GREEN}${BOLD}${ICON_OK} 抗丢包优化完成！${NC}"
    echo
    echo -e "  ${BOLD}配置文件:${NC} ${anti_loss_file}"
    echo
    echo -e "  ${BOLD}验证命令:${NC}"
    echo "    sysctl net.ipv4.tcp_retries2  # 应为 30"
    echo "    sysctl net.core.rmem_max      # 应为 134217728"
    echo
    echo -e "  ${YELLOW}注意:${NC} 如果丢包仍然严重，可能是线路本身问题，建议:"
    echo "    1. 更换线路/机房"
    echo "    2. 使用 UDP 协议（如 Hysteria/TUIC）"
    echo "    3. 检查是否被 QoS 限速"
}

#===============================================================================
# LINE 应用优化模块
#===============================================================================

# LINE 完整域名列表（来源：netify.ai）
readonly LINE_DOMAINS=(
    # ========== 主域名 ==========
    "line.me"
    "line-apps.com"
    "line-scdn.net"
    "lin.ee"
    "linecorp.com"
    "line.biz"
    "line.naver.jp"
    "naver.jp"
    # ========== CDN 域名 ==========
    "line-cdn.net"
    "linecdn.net"
    "scdn.line-apps.com"
    # ========== 文件/媒体服务器（关键！）==========
    "obs.line-scdn.net"
    "obs-tw.line-scdn.net"
    "obs-jp.line-scdn.net"
    "obs-sg.line-scdn.net"
    "stf.line-scdn.net"
    "w.line-scdn.net"
    "profile.line-scdn.net"
    "media.line-scdn.net"
    "vod.line-scdn.net"
    # ========== 下载服务器 ==========
    "dl.stickershop.line.naver.jp"
    "stickershop.line-scdn.net"
    "shop.line-scdn.net"
    # ========== API 服务器 ==========
    "api.line.me"
    "access.line.me"
    "notify-api.line.me"
    "gw.line.naver.jp"
    # ========== 长连接服务器 ==========
    "legy.line.naver.jp"
    "legy-jp.line.naver.jp"
    "legy-tw.line.naver.jp"
    "legy-sg.line.naver.jp"
    "legy-hk.line.naver.jp"
    # ========== 通话/VOIP 服务器 ==========
    "voip.line-apps.com"
    "turn.line-apps.com"
    "stun.line-apps.com"
    # ========== 其他服务 ==========
    "d.line-scdn.net"
    "static.line-scdn.net"
    "liff.line.me"
    "manager.line.biz"
)

# LINE 配置文件路径
readonly LINE_CONFIG_FILE="/etc/bbr3-line.conf"
readonly LINE_IP_FILE="/etc/bbr3-line-ips.conf"
readonly LINE_SYSCTL_FILE="/etc/sysctl.d/99-bbr-line.conf"

# 获取 LINE 专用 sysctl 参数
get_line_sysctl_params() {
    cat << 'EOF'
# LINE 应用专项优化
# 优先级：通话 > 文件传输 > 消息

# ========== UDP 优化（通话/视频）==========
# 大 UDP 缓冲区支持实时音视频
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576

# ========== TCP 优化（消息/文件）==========
# 大文件传输缓冲区（64MB，解决大文件中断问题）
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 131072 67108864
net.ipv4.tcp_mem = 786432 1048576 1572864

# 快速响应
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 131072

# 窗口缩放（大文件必需）
net.ipv4.tcp_window_scaling = 1
net.core.optmem_max = 65536

# 低延迟优先
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# 快速重传和恢复
net.ipv4.tcp_early_retrans = 3
net.ipv4.tcp_frto = 2
net.ipv4.tcp_retries1 = 5
net.ipv4.tcp_retries2 = 30
net.ipv4.tcp_orphan_retries = 5
net.ipv4.tcp_syn_retries = 6
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_fin_timeout = 30

# ========== Keepalive 优化（防止大文件传输中断）==========
net.ipv4.tcp_keepalive_time = 15
net.ipv4.tcp_keepalive_intvl = 3
net.ipv4.tcp_keepalive_probes = 15

# ========== 防止 99% 失败（关键优化）==========
# 增加 FIN 等待时间
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144
# 禁用 RFC1337（允许 TIME_WAIT 状态的连接接收 RST）
net.ipv4.tcp_rfc1337 = 0
# 增加重传超时
net.ipv4.tcp_retrans_collapse = 0

# ========== conntrack 优化 ==========
# UDP 短超时（通话连接快速清理）
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120

# TCP 长超时（大文件传输需要更长时间）
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_max = 1048576

# ========== 队列优化（减少抖动）==========
net.core.netdev_max_backlog = 250000
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 4000

# ========== MTU 优化 ==========
# 禁用 PMTU 黑洞检测（某些网络环境需要）
net.ipv4.tcp_mtu_probing = 1
EOF
}

# LINE DNS 预解析
line_dns_prefetch() {
    log_info "执行 LINE DNS 预解析..."
    
    local resolved_ips=""
    for domain in "${LINE_DOMAINS[@]}"; do
        local ips
        ips=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -5)
        if [[ -n "$ips" ]]; then
            resolved_ips+="$ips"$'\n'
            log_debug "解析 $domain: $(echo "$ips" | tr '\n' ' ')"
        fi
    done
    
    # 保存 IP 列表
    if [[ -n "$resolved_ips" ]]; then
        echo "$resolved_ips" | sort -u > "$LINE_IP_FILE"
        local count
        count=$(wc -l < "$LINE_IP_FILE")
        print_success "DNS 预解析完成，获取 $count 个 IP"
    else
        print_warn "DNS 预解析失败，请检查网络"
    fi
}

# LINE TCP 预热
line_tcp_warmup() {
    log_info "执行 LINE TCP 预热..."
    
    if [[ ! -f "$LINE_IP_FILE" ]]; then
        line_dns_prefetch
    fi
    
    if [[ ! -f "$LINE_IP_FILE" ]]; then
        print_warn "无 IP 列表，跳过 TCP 预热"
        return
    fi
    
    local warmup_count=0
    while read -r ip; do
        [[ -z "$ip" ]] && continue
        # 尝试建立 TCP 连接（443 端口）
        if timeout 2 bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null; then
            ((warmup_count++))
            log_debug "预热成功: $ip"
        fi
    done < "$LINE_IP_FILE"
    
    print_success "TCP 预热完成，成功 $warmup_count 个连接"
}

# 创建 LINE keepalive 服务
line_create_keepalive_service() {
    log_info "创建 LINE keepalive 服务..."
    
    # 创建预热脚本
    local warmup_script="/usr/local/bin/bbr3-line-warmup"
    cat > "$warmup_script" << 'SCRIPT'
#!/bin/bash
# LINE 连接预热脚本

LINE_DOMAINS=(
    "line.me"
    "line-scdn.net"
    "line-apps.com"
    "naver.jp"
)
LINE_IP_FILE="/etc/bbr3-line-ips.conf"

# DNS 预解析
resolved_ips=""
for domain in "${LINE_DOMAINS[@]}"; do
    ips=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -5)
    [[ -n "$ips" ]] && resolved_ips+="$ips"$'\n'
done
[[ -n "$resolved_ips" ]] && echo "$resolved_ips" | sort -u > "$LINE_IP_FILE"

# TCP 预热
[[ -f "$LINE_IP_FILE" ]] && while read -r ip; do
    [[ -n "$ip" ]] && timeout 2 bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null
done < "$LINE_IP_FILE"

logger "BBR3-LINE: 预热完成"
SCRIPT
    chmod +x "$warmup_script"
    
    # 创建 systemd 服务
    cat > /etc/systemd/system/bbr3-line-warmup.service << SERVICE
[Unit]
Description=BBR3 LINE Connection Warmup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$warmup_script
SERVICE
    
    # 创建定时器（每 5 分钟执行）
    cat > /etc/systemd/system/bbr3-line-warmup.timer << TIMER
[Unit]
Description=BBR3 LINE Warmup Timer

[Timer]
OnBootSec=30
OnUnitActiveSec=300

[Install]
WantedBy=timers.target
TIMER
    
    # 启用服务
    systemctl daemon-reload
    systemctl enable bbr3-line-warmup.timer >/dev/null 2>&1
    systemctl start bbr3-line-warmup.timer >/dev/null 2>&1
    
    print_success "LINE keepalive 服务已创建并启用"
}

# LINE 路由优化
line_route_optimize() {
    log_info "配置 LINE 路由优化..."
    
    if [[ ! -f "$LINE_IP_FILE" ]]; then
        line_dns_prefetch
    fi
    
    if [[ ! -f "$LINE_IP_FILE" ]]; then
        print_warn "无 IP 列表，跳过路由优化"
        return
    fi
    
    # 获取默认网关
    local gateway
    gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local nic
    nic=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [[ -z "$gateway" ]] || [[ -z "$nic" ]]; then
        print_warn "无法获取默认网关，跳过路由优化"
        return
    fi
    
    local route_count=0
    while read -r ip; do
        [[ -z "$ip" ]] && continue
        # 添加高优先级路由
        if ip route add "$ip/32" via "$gateway" dev "$nic" metric 10 2>/dev/null; then
            ((route_count++))
        fi
    done < "$LINE_IP_FILE"
    
    print_success "路由优化完成，添加 $route_count 条路由"
}

# LINE QoS 设置
line_qos_setup() {
    log_info "配置 LINE QoS..."
    
    if [[ ! -f "$LINE_IP_FILE" ]]; then
        line_dns_prefetch
    fi
    
    if [[ ! -f "$LINE_IP_FILE" ]]; then
        print_warn "无 IP 列表，跳过 QoS 设置"
        return
    fi
    
    # 检查 iptables
    if ! command -v iptables >/dev/null 2>&1; then
        print_warn "iptables 未安装，跳过 QoS 设置"
        return
    fi
    
    # 创建 LINE 专用链
    iptables -t mangle -N LINE_QOS 2>/dev/null || iptables -t mangle -F LINE_QOS
    
    # 为 LINE IP 设置 DSCP 标记（EF = 46，用于实时流量）
    while read -r ip; do
        [[ -z "$ip" ]] && continue
        iptables -t mangle -A LINE_QOS -d "$ip" -j DSCP --set-dscp 46 2>/dev/null
        iptables -t mangle -A LINE_QOS -s "$ip" -j DSCP --set-dscp 46 2>/dev/null
    done < "$LINE_IP_FILE"
    
    # 将 LINE_QOS 链添加到 POSTROUTING
    iptables -t mangle -C POSTROUTING -j LINE_QOS 2>/dev/null || \
        iptables -t mangle -A POSTROUTING -j LINE_QOS
    
    print_success "LINE QoS 已配置（DSCP=EF）"
}

# LINE 优化菜单
line_optimization_menu() {
    while true; do
        clear
        print_header "LINE 应用优化"
        
        echo -e "${DIM}专为 LINE 应用优化，提升通话质量和文件传输速度${NC}"
        echo -e "${DIM}优先级：通话 > 文件传输 > 消息${NC}"
        echo
        
        # 显示当前状态
        echo -e "  ${BOLD}当前状态:${NC}"
        if [[ -f "$LINE_SYSCTL_FILE" ]]; then
            echo -e "    LINE sysctl: ${GREEN}已配置${NC}"
        else
            echo -e "    LINE sysctl: ${YELLOW}未配置${NC}"
        fi
        if systemctl is-active bbr3-line-warmup.timer >/dev/null 2>&1; then
            echo -e "    预热服务: ${GREEN}运行中${NC}"
        else
            echo -e "    预热服务: ${YELLOW}未启用${NC}"
        fi
        if [[ -f "$LINE_IP_FILE" ]]; then
            local ip_count
            ip_count=$(wc -l < "$LINE_IP_FILE")
            echo -e "    IP 列表: ${GREEN}${ip_count} 个${NC}"
        else
            echo -e "    IP 列表: ${YELLOW}未生成${NC}"
        fi
        echo
        
        print_separator
        echo
        echo -e "  ${GREEN}${BOLD}1)${NC} ${GREEN}🚀 一键优化${NC}     - 应用所有 LINE 优化（推荐）"
        echo -e "  ${CYAN}2)${NC} 📝 基础优化     - 仅应用 sysctl 参数"
        echo -e "  ${CYAN}3)${NC} 🔄 DNS 预解析   - 更新 LINE IP 列表"
        echo -e "  ${CYAN}4)${NC} 🔥 TCP 预热     - 预热 LINE 连接"
        echo -e "  ${CYAN}5)${NC} ⏰ 启用预热服务 - 定时自动预热"
        echo -e "  ${CYAN}6)${NC} 🛣️  路由优化     - 优化 LINE IP 路由"
        echo -e "  ${CYAN}7)${NC} 📊 QoS 设置     - 设置流量优先级"
        echo -e "  ${CYAN}8)${NC} ❌ 移除优化     - 移除所有 LINE 优化"
        echo
        echo -e "  ${CYAN}0)${NC} 返回上级菜单"
        echo
        
        read_choice "请选择" 8
        
        case "$MENU_CHOICE" in
            0) return ;;
            1) line_full_optimize ;;
            2) line_apply_sysctl ;;
            3) line_dns_prefetch ;;
            4) line_tcp_warmup ;;
            5) line_create_keepalive_service ;;
            6) line_route_optimize ;;
            7) line_qos_setup ;;
            8) line_remove_optimization ;;
        esac
        
        echo
        read -rp "按 Enter 键继续..."
    done
}

# LINE 一键优化
line_full_optimize() {
    print_header "LINE 一键优化"
    
    echo -e "${CYAN}将执行以下优化:${NC}"
    echo "  1. 应用 LINE 专用 sysctl 参数"
    echo "  2. DNS 预解析获取 LINE IP"
    echo "  3. TCP 连接预热"
    echo "  4. 创建定时预热服务"
    echo "  5. 配置路由优化"
    echo "  6. 设置 QoS 流量优先级"
    echo
    
    if ! confirm "确认执行一键优化？" "y"; then
        return
    fi
    
    echo
    print_step "[1/6] 应用 sysctl 参数..."
    line_apply_sysctl
    
    print_step "[2/6] DNS 预解析..."
    line_dns_prefetch
    
    print_step "[3/6] TCP 预热..."
    line_tcp_warmup
    
    print_step "[4/6] 创建预热服务..."
    line_create_keepalive_service
    
    print_step "[5/6] 路由优化..."
    line_route_optimize
    
    print_step "[6/6] QoS 设置..."
    line_qos_setup
    
    echo
    echo -e "${GREEN}${BOLD}${ICON_OK} LINE 一键优化完成！${NC}"
    echo
    echo -e "  ${BOLD}优化摘要:${NC}"
    echo "    - sysctl 配置: ${LINE_SYSCTL_FILE}"
    echo "    - IP 列表: ${LINE_IP_FILE}"
    echo "    - 预热服务: bbr3-line-warmup.timer"
    echo "    - QoS: DSCP=EF (实时流量优先)"
    echo
    echo -e "  ${DIM}提示: LINE 优化与代理模式可同时使用${NC}"
}

# 应用 LINE sysctl 参数
line_apply_sysctl() {
    log_info "应用 LINE sysctl 参数..."
    
    # 生成配置文件
    cat > "$LINE_SYSCTL_FILE" << CONF
# LINE 应用专项优化
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 由 BBR3 Script 生成

$(get_line_sysctl_params)
CONF
    
    # 应用配置
    if sysctl -p "$LINE_SYSCTL_FILE" >/dev/null 2>&1; then
        print_success "LINE sysctl 参数已应用"
    else
        # 逐行应用
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^# ]] && continue
            sysctl -w "$line" >/dev/null 2>&1 || true
        done < "$LINE_SYSCTL_FILE"
        print_success "LINE sysctl 参数已应用（部分参数可能不支持）"
    fi
}

# 移除 LINE 优化
line_remove_optimization() {
    print_header "移除 LINE 优化"
    
    if ! confirm "确认移除所有 LINE 优化？" "n"; then
        return
    fi
    
    echo
    print_step "移除 sysctl 配置..."
    rm -f "$LINE_SYSCTL_FILE"
    sysctl --system >/dev/null 2>&1
    
    print_step "停止预热服务..."
    systemctl stop bbr3-line-warmup.timer 2>/dev/null
    systemctl disable bbr3-line-warmup.timer 2>/dev/null
    rm -f /etc/systemd/system/bbr3-line-warmup.service
    rm -f /etc/systemd/system/bbr3-line-warmup.timer
    rm -f /usr/local/bin/bbr3-line-warmup
    systemctl daemon-reload
    
    print_step "移除 IP 列表..."
    rm -f "$LINE_IP_FILE"
    rm -f "$LINE_CONFIG_FILE"
    
    print_step "移除 QoS 规则..."
    iptables -t mangle -D POSTROUTING -j LINE_QOS 2>/dev/null
    iptables -t mangle -F LINE_QOS 2>/dev/null
    iptables -t mangle -X LINE_QOS 2>/dev/null
    
    echo
    print_success "LINE 优化已移除"
}

#===============================================================================
# 其他应用优化模块（Google/Apple/Meta/X/Telegram）
#===============================================================================

# Google 域名列表
readonly GOOGLE_DOMAINS=(
    # 核心服务
    "google.com"
    "google.com.tw"
    "google.com.hk"
    "google.co.jp"
    "googleapis.com"
    "gstatic.com"
    "googleusercontent.com"
    # YouTube
    "youtube.com"
    "youtu.be"
    "ytimg.com"
    "yt3.ggpht.com"
    "googlevideo.com"
    # Google Play
    "play.google.com"
    "play-lh.googleusercontent.com"
    # Gmail
    "gmail.com"
    "mail.google.com"
    # Drive
    "drive.google.com"
    "docs.google.com"
    # Meet
    "meet.google.com"
    # CDN
    "gvt1.com"
    "gvt2.com"
    "gvt3.com"
    "ggpht.com"
    "googleadservices.com"
    "doubleclick.net"
)

# Apple 域名列表
readonly APPLE_DOMAINS=(
    # 核心服务
    "apple.com"
    "icloud.com"
    "icloud-content.com"
    "apple-cloudkit.com"
    # App Store
    "itunes.apple.com"
    "apps.apple.com"
    "mzstatic.com"
    # iMessage/FaceTime
    "push.apple.com"
    "courier.push.apple.com"
    "ess.apple.com"
    "facetime.apple.com"
    # iCloud
    "p01-icloud.com"
    "p02-icloud.com"
    "p03-icloud.com"
    "setup.icloud.com"
    # CDN
    "cdn-apple.com"
    "apple-dns.net"
    "aaplimg.com"
    # 软件更新
    "swcdn.apple.com"
    "swdist.apple.com"
    "updates.cdn-apple.com"
)

# Meta (Facebook/Instagram/WhatsApp) 域名列表
readonly META_DOMAINS=(
    # Facebook
    "facebook.com"
    "fb.com"
    "fbcdn.net"
    "facebook.net"
    "fb.me"
    "fbsbx.com"
    # Instagram
    "instagram.com"
    "cdninstagram.com"
    "ig.me"
    # WhatsApp
    "whatsapp.com"
    "whatsapp.net"
    "wa.me"
    "web.whatsapp.com"
    # Messenger
    "messenger.com"
    "m.me"
    # CDN
    "fbcdn.com"
    "xx.fbcdn.net"
    "scontent.xx.fbcdn.net"
    "video.xx.fbcdn.net"
    # API
    "graph.facebook.com"
    "api.facebook.com"
)

# X (Twitter) 域名列表
readonly X_DOMAINS=(
    # 核心服务
    "twitter.com"
    "x.com"
    "t.co"
    "twimg.com"
    # API
    "api.twitter.com"
    "api.x.com"
    # CDN
    "pbs.twimg.com"
    "video.twimg.com"
    "abs.twimg.com"
    "ton.twimg.com"
    # 媒体
    "media.twitter.com"
    "upload.twitter.com"
    # 其他
    "tweetdeck.com"
    "periscope.tv"
    "pscp.tv"
)

# Telegram 域名列表
readonly TELEGRAM_DOMAINS=(
    # 核心服务
    "telegram.org"
    "telegram.me"
    "t.me"
    "tg.dev"
    # API
    "api.telegram.org"
    "core.telegram.org"
    # CDN/媒体
    "cdn1.telegram-cdn.org"
    "cdn2.telegram-cdn.org"
    "cdn3.telegram-cdn.org"
    "cdn4.telegram-cdn.org"
    "cdn5.telegram-cdn.org"
    "telegram-cdn.org"
    # Web
    "web.telegram.org"
    "webk.telegram.org"
    "webz.telegram.org"
    # 更新
    "updates.telegram.org"
    # DC 服务器
    "venus.web.telegram.org"
    "pluto.web.telegram.org"
    "flora.web.telegram.org"
)

# 应用优化配置文件路径
readonly APP_IP_DIR="/etc/bbr3-apps"
readonly APP_SYSCTL_FILE="/etc/sysctl.d/99-bbr-apps.conf"

# 通用应用 DNS 预解析
app_dns_prefetch() {
    local app_name="$1"
    shift
    local domains=("$@")
    
    log_info "执行 ${app_name} DNS 预解析..."
    
    # 确保目录存在
    mkdir -p "$APP_IP_DIR"
    
    local ip_file="${APP_IP_DIR}/${app_name,,}-ips.conf"
    local resolved_ips=""
    
    for domain in "${domains[@]}"; do
        local ips
        ips=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -5)
        if [[ -n "$ips" ]]; then
            resolved_ips+="$ips"$'\n'
        fi
    done
    
    if [[ -n "$resolved_ips" ]]; then
        echo "$resolved_ips" | sort -u > "$ip_file"
        local count
        count=$(wc -l < "$ip_file")
        print_success "${app_name} DNS 预解析完成，获取 $count 个 IP"
    else
        print_warn "${app_name} DNS 预解析失败"
    fi
}

# 通用应用 QoS 设置
app_qos_setup() {
    local app_name="$1"
    local dscp_value="${2:-46}"  # 默认 EF
    
    local ip_file="${APP_IP_DIR}/${app_name,,}-ips.conf"
    
    if [[ ! -f "$ip_file" ]]; then
        print_warn "无 ${app_name} IP 列表，跳过 QoS 设置"
        return
    fi
    
    if ! command -v iptables >/dev/null 2>&1; then
        print_warn "iptables 未安装，跳过 QoS 设置"
        return
    fi
    
    local chain_name="${app_name^^}_QOS"
    
    # 创建专用链
    iptables -t mangle -N "$chain_name" 2>/dev/null || iptables -t mangle -F "$chain_name"
    
    # 为 IP 设置 DSCP 标记
    while read -r ip; do
        [[ -z "$ip" ]] && continue
        iptables -t mangle -A "$chain_name" -d "$ip" -j DSCP --set-dscp "$dscp_value" 2>/dev/null
        iptables -t mangle -A "$chain_name" -s "$ip" -j DSCP --set-dscp "$dscp_value" 2>/dev/null
    done < "$ip_file"
    
    # 添加到 POSTROUTING
    iptables -t mangle -C POSTROUTING -j "$chain_name" 2>/dev/null || \
        iptables -t mangle -A POSTROUTING -j "$chain_name"
    
    print_success "${app_name} QoS 已配置（DSCP=$dscp_value）"
}

# 应用优化主菜单
app_optimization_menu() {
    while true; do
        clear
        print_header "应用专项优化"
        
        echo -e "${DIM}为特定应用优化网络，提升访问速度和稳定性${NC}"
        echo
        
        # 显示当前状态
        echo -e "  ${BOLD}已优化应用:${NC}"
        local optimized_count=0
        for app in LINE Google Apple Meta X Telegram; do
            local ip_file="${APP_IP_DIR}/${app,,}-ips.conf"
            [[ "$app" == "LINE" ]] && ip_file="$LINE_IP_FILE"
            if [[ -f "$ip_file" ]]; then
                local count=$(wc -l < "$ip_file" 2>/dev/null || echo 0)
                echo -e "    ${GREEN}✓${NC} ${app} (${count} IPs)"
                ((optimized_count++))
            fi
        done
        [[ $optimized_count -eq 0 ]] && echo -e "    ${YELLOW}无${NC}"
        echo
        
        print_separator
        echo
        echo -e "  ${GREEN}${BOLD}1)${NC} ${GREEN}📱 LINE${NC}      - 通话/消息/文件优化"
        echo -e "  ${CYAN}2)${NC} 🔍 Google    - YouTube/Gmail/Drive 优化"
        echo -e "  ${CYAN}3)${NC} 🍎 Apple     - iCloud/FaceTime/App Store 优化"
        echo -e "  ${CYAN}4)${NC} 📘 Meta      - Facebook/Instagram/WhatsApp 优化"
        echo -e "  ${CYAN}5)${NC} 🐦 X         - Twitter/X 优化"
        echo -e "  ${CYAN}6)${NC} ✈️  Telegram  - 电报优化"
        echo
        echo -e "  ${GREEN}${BOLD}7)${NC} ${GREEN}🚀 一键全部优化${NC}"
        echo -e "  ${CYAN}8)${NC} ❌ 移除所有应用优化"
        echo
        echo -e "  ${CYAN}0)${NC} 返回上级菜单"
        echo
        
        read_choice "请选择" 8
        
        case "$MENU_CHOICE" in
            0) return ;;
            1) line_optimization_menu ;;
            2) optimize_single_app "Google" "${GOOGLE_DOMAINS[@]}" ;;
            3) optimize_single_app "Apple" "${APPLE_DOMAINS[@]}" ;;
            4) optimize_single_app "Meta" "${META_DOMAINS[@]}" ;;
            5) optimize_single_app "X" "${X_DOMAINS[@]}" ;;
            6) optimize_single_app "Telegram" "${TELEGRAM_DOMAINS[@]}" ;;
            7) optimize_all_apps ;;
            8) remove_all_app_optimizations ;;
        esac
        
        [[ "$MENU_CHOICE" != "1" ]] && [[ "$MENU_CHOICE" != "0" ]] && {
            echo
            read -rp "按 Enter 键继续..."
        }
    done
}

# 优化单个应用
optimize_single_app() {
    local app_name="$1"
    shift
    local domains=("$@")
    
    print_header "${app_name} 优化"
    
    echo -e "${CYAN}将为 ${app_name} 执行以下优化:${NC}"
    echo "  1. DNS 预解析获取 IP 列表"
    echo "  2. 设置 QoS 流量优先级"
    echo
    
    if ! confirm "确认优化 ${app_name}？" "y"; then
        return
    fi
    
    echo
    print_step "[1/2] DNS 预解析..."
    app_dns_prefetch "$app_name" "${domains[@]}"
    
    print_step "[2/2] QoS 设置..."
    app_qos_setup "$app_name"
    
    echo
    print_success "${app_name} 优化完成！"
}

# 一键优化所有应用
optimize_all_apps() {
    print_header "一键全部优化"
    
    echo -e "${CYAN}将优化以下应用:${NC}"
    echo "  - LINE (通话/消息/文件)"
    echo "  - Google (YouTube/Gmail/Drive)"
    echo "  - Apple (iCloud/FaceTime)"
    echo "  - Meta (Facebook/Instagram/WhatsApp)"
    echo "  - X (Twitter)"
    echo "  - Telegram (电报)"
    echo
    
    if ! confirm "确认一键优化所有应用？" "y"; then
        return
    fi
    
    echo
    
    # LINE 特殊处理（有完整的优化流程）
    print_step "[1/6] 优化 LINE..."
    line_apply_sysctl
    line_dns_prefetch
    line_qos_setup
    
    print_step "[2/6] 优化 Google..."
    app_dns_prefetch "Google" "${GOOGLE_DOMAINS[@]}"
    app_qos_setup "Google"
    
    print_step "[3/6] 优化 Apple..."
    app_dns_prefetch "Apple" "${APPLE_DOMAINS[@]}"
    app_qos_setup "Apple"
    
    print_step "[4/6] 优化 Meta..."
    app_dns_prefetch "Meta" "${META_DOMAINS[@]}"
    app_qos_setup "Meta"
    
    print_step "[5/6] 优化 X..."
    app_dns_prefetch "X" "${X_DOMAINS[@]}"
    app_qos_setup "X"
    
    print_step "[6/6] 优化 Telegram..."
    app_dns_prefetch "Telegram" "${TELEGRAM_DOMAINS[@]}"
    app_qos_setup "Telegram"
    
    echo
    echo -e "${GREEN}${BOLD}${ICON_OK} 所有应用优化完成！${NC}"
    echo
    echo -e "  ${BOLD}优化摘要:${NC}"
    echo "    - IP 列表目录: ${APP_IP_DIR}"
    echo "    - QoS: 所有应用流量标记为 DSCP=EF"
    echo
    echo -e "  ${DIM}提示: 应用优化与代理模式可同时使用${NC}"
}

# 移除所有应用优化
remove_all_app_optimizations() {
    print_header "移除所有应用优化"
    
    if ! confirm "确认移除所有应用优化？" "n"; then
        return
    fi
    
    echo
    
    # 移除 LINE 优化
    print_step "移除 LINE 优化..."
    rm -f "$LINE_SYSCTL_FILE"
    rm -f "$LINE_IP_FILE"
    systemctl stop bbr3-line-warmup.timer 2>/dev/null
    systemctl disable bbr3-line-warmup.timer 2>/dev/null
    rm -f /etc/systemd/system/bbr3-line-warmup.service
    rm -f /etc/systemd/system/bbr3-line-warmup.timer
    rm -f /usr/local/bin/bbr3-line-warmup
    iptables -t mangle -D POSTROUTING -j LINE_QOS 2>/dev/null
    iptables -t mangle -F LINE_QOS 2>/dev/null
    iptables -t mangle -X LINE_QOS 2>/dev/null
    
    # 移除其他应用优化
    for app in Google Apple Meta X Telegram; do
        print_step "移除 ${app} 优化..."
        local chain_name="${app^^}_QOS"
        iptables -t mangle -D POSTROUTING -j "$chain_name" 2>/dev/null
        iptables -t mangle -F "$chain_name" 2>/dev/null
        iptables -t mangle -X "$chain_name" 2>/dev/null
    done
    
    # 移除 IP 列表目录
    rm -rf "$APP_IP_DIR"
    
    # 重新加载 sysctl
    systemctl daemon-reload 2>/dev/null
    sysctl --system >/dev/null 2>&1
    
    echo
    print_success "所有应用优化已移除"
}

# 安装系统服务
install_system_services() {
    local services_to_install=("$@")
    
    # 检查是否支持 systemd
    local has_systemd=false
    if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
        has_systemd=true
    fi
    
    for service in "${services_to_install[@]}"; do
        case "$service" in
            haveged)
                if ! command -v haveged &>/dev/null; then
                    print_step "安装 haveged..."
                    case "$PKG_MANAGER" in
                        apt) apt-get install -y -qq haveged >/dev/null 2>&1 ;;
                        yum) yum install -y -q haveged >/dev/null 2>&1 ;;
                        dnf) dnf install -y -q haveged >/dev/null 2>&1 ;;
                    esac
                fi
                
                # 检查服务是否可用并启动
                if [[ "$has_systemd" == "true" ]] && systemctl list-unit-files haveged.service &>/dev/null; then
                    if systemctl is-active haveged >/dev/null 2>&1; then
                        print_info "haveged 已在运行"
                    else
                        systemctl enable haveged >/dev/null 2>&1
                        if systemctl start haveged >/dev/null 2>&1; then
                            print_success "haveged 已启动"
                        else
                            print_warn "haveged 启动失败 (容器环境可能不支持)"
                        fi
                    fi
                elif command -v haveged &>/dev/null; then
                    # 容器环境：尝试直接运行
                    if pgrep -x haveged >/dev/null 2>&1; then
                        print_info "haveged 已在运行"
                    else
                        # 尝试后台运行
                        nohup haveged -w 1024 >/dev/null 2>&1 &
                        sleep 0.5
                        if pgrep -x haveged >/dev/null 2>&1; then
                            print_success "haveged 已启动"
                        else
                            print_warn "haveged 在此环境不可用 (容器限制)"
                        fi
                    fi
                else
                    print_warn "haveged 安装失败"
                fi
                ;;
        esac
    done
}

# 获取线路参数
get_line_params() {
    local line="$1"
    
    case "$line" in
        cn2gia|9929)
            # 优质线路：标准配置
            echo "# 优质线路优化 (CN2 GIA/9929)"
            echo "# 线路质量好，使用标准 BBR3 配置"
            ;;
        cn2gt|cmi)
            # 中等线路：略增缓冲
            echo "# 中等线路优化 (CN2 GT/CMI)"
            echo "net.ipv4.tcp_retries2 = 10"
            ;;
        4837|163|unknown|*)
            # 普通线路：激进配置，大缓冲区
            echo "# 普通线路优化 (4837/163)"
            echo "# 线路质量一般，增大缓冲区和重试次数"
            echo "net.ipv4.tcp_retries2 = 15"
            echo "net.ipv4.tcp_syn_retries = 3"
            echo "net.ipv4.tcp_synack_retries = 3"
            ;;
    esac
}

# 应用低配优化
apply_low_spec_optimization() {
    cat << EOF
# 低配 VPS 激进优化
net.core.rmem_max = ${BUFFER_16MB}
net.core.wmem_max = ${BUFFER_16MB}
net.ipv4.tcp_rmem = 4096 65536 ${BUFFER_16MB}
net.ipv4.tcp_wmem = 4096 32768 ${BUFFER_16MB}
net.core.somaxconn = 1024
net.ipv4.tcp_max_orphans = 8192
net.ipv4.tcp_max_tw_buckets = 50000
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 10
EOF
}

# 生成代理配置
generate_proxy_config() {
    local config_file="$SYSCTL_FILE"
    
    # 备份现有配置
    if [[ -f "$config_file" ]]; then
        backup_config
    fi
    
    # 动态检测最佳算法
    local best_algo best_qdisc
    best_algo=$(suggest_best_algo 2>/dev/null || echo "bbr")
    best_qdisc=$(suggest_best_qdisc "proxy" 2>/dev/null || echo "fq")
    
    # 生成新配置
    cat > "$config_file" << EOF
# BBR3 代理服务器智能调优配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 硬件评分: ${PROXY_HARDWARE_SCORE}/100
# 链路架构: ${PROXY_CHAIN_ARCH}
# 节点角色: ${PROXY_NODE_ROLE}
# 代理协议: ${PROXY_PROTOCOL}
# 资源占比: ${PROXY_RESOURCE_RATIO}%

# ========== 拥塞控制 ==========
# 算法: ${best_algo} (动态检测: BBR3 > BBR2 > BBR > CUBIC)
net.ipv4.tcp_congestion_control = ${best_algo}
net.core.default_qdisc = ${best_qdisc}

# ========== 基础 TCP 优化 ==========
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535

EOF

    # 添加角色专用参数
    get_role_params "$PROXY_NODE_ROLE" >> "$config_file"
    echo >> "$config_file"
    
    # 添加协议专用参数
    case "$PROXY_PROTOCOL" in
        vless|vmess|trojan|ss|naive)
            get_tcp_protocol_params >> "$config_file"
            ;;
        hysteria|tuic)
            get_udp_protocol_params >> "$config_file"
            ;;
        tun)
            get_tun_tproxy_params >> "$config_file"
            ;;
        mixed)
            get_tcp_protocol_params >> "$config_file"
            echo >> "$config_file"
            get_udp_protocol_params >> "$config_file"
            ;;
    esac
    echo >> "$config_file"
    
    # 添加线路优化参数
    get_line_params "$PROXY_LINE_TYPE" >> "$config_file"
    echo >> "$config_file"
    
    # 低配 VPS 激进优化
    if [[ "$PROXY_IS_LOW_SPEC" == "true" ]]; then
        apply_low_spec_optimization >> "$config_file"
        echo >> "$config_file"
    fi
    
    # 高级优化（核心参数始终启用）
    get_advanced_sysctl_params >> "$config_file"
}

# 显示优化方案
show_optimization_plan() {
    echo
    print_header "代理服务器智能调优方案"
    echo
    
    # 用户配置
    echo -e "  ${BOLD}📋 用户配置${NC}"
    print_separator
    printf "    %-15s : %s/100" "硬件评分" "$PROXY_HARDWARE_SCORE"
    [[ "$PROXY_IS_LOW_SPEC" == "true" ]] && echo -e " ${YELLOW}(低配 VPS)${NC}" || echo
    printf "    %-15s : %s\n" "链路架构" "$PROXY_CHAIN_ARCH"
    printf "    %-15s : %s\n" "节点角色" "$PROXY_NODE_ROLE"
    printf "    %-15s : %s\n" "服务器位置" "$PROXY_SERVER_LOCATION"
    printf "    %-15s : %s\n" "客户端位置" "$PROXY_CLIENT_LOCATION"
    printf "    %-15s : %s\n" "线路类型" "$PROXY_LINE_TYPE"
    printf "    %-15s : %s\n" "代理内核" "$PROXY_KERNEL"
    printf "    %-15s : %s\n" "代理协议" "$PROXY_PROTOCOL"
    printf "    %-15s : %s%%\n" "资源占比" "$PROXY_RESOURCE_RATIO"
    echo
    
    # 优化方案
    echo -e "  ${BOLD}🚀 优化方案${NC}"
    print_separator
    echo
    echo "    【内核优化】"
    echo "    ├─ 拥塞控制算法:    BBR3 (最新)"
    echo "    ├─ 队列调度:        fq (公平队列)"
    echo "    └─ 预计提升:        30-50% 吞吐量"
    echo
    echo "    【缓冲区优化】"
    if [[ "$PROXY_IS_LOW_SPEC" == "true" ]]; then
        echo "    ├─ rmem_max:        16 MB (低配优化)"
        echo "    └─ wmem_max:        16 MB"
    else
        echo "    ├─ rmem_max:        32-64 MB"
        echo "    └─ wmem_max:        32-64 MB"
    fi
    echo
    echo "    【TCP 优化】"
    echo "    ├─ TCP Fast Open:   启用 (TFO=3)"
    echo "    ├─ TCP ECN:         启用"
    echo "    ├─ SACK/DSACK:      启用"
    echo "    └─ 预计提升:        10-20% 延迟降低"
    echo
    
    echo "    【高级网络优化】（始终启用）"
    echo "    ├─ TCP 慢启动:      禁用空闲后重置，保持连接性能"
    echo "    ├─ TCP Keepalive:   60秒探测，保持连接活跃"
    echo "    ├─ 端口范围:        扩大到 1024-65535"
    echo "    ├─ TIME_WAIT:       启用复用，限制数量"
    echo "    ├─ SYN 队列:        扩大到 65535"
    echo "    ├─ 连接跟踪:        优化 conntrack 表大小和超时"
    echo "    ├─ 网络队列:        优化 netdev_budget"
    echo "    ├─ 路由缓存:        扩大路由表容量"
    echo "    └─ ARP 缓存:        扩大 neighbor 表容量"
    echo
    
    if [[ "$PROXY_ADVANCED_OPTS" == "all" ]]; then
        echo "    【系统服务】"
        echo "    └─ haveged:         将安装并启用（增强熵源）"
        echo
    fi
    
    # 将要执行的操作
    echo -e "  ${BOLD}📝 将要执行的操作${NC}"
    print_separator
    echo "    1. 备份当前 sysctl 配置"
    echo "    2. 写入新的 sysctl 配置到 ${SYSCTL_FILE}"
    [[ "$PROXY_ADVANCED_OPTS" == "all" ]] && echo "    3. 安装 haveged（增强熵源）"
    echo "    4. 应用 sysctl 配置"
    echo "    5. 验证配置生效"
    echo
    echo -e "  ${YELLOW}${ICON_WARN} 配置将立即生效，无需重启${NC}"
    echo
}

# 执行优化
execute_optimization() {
    echo
    print_header "执行优化"
    echo
    
    # 步骤 1: 备份
    print_step "[1/5] 备份当前配置..."
    if backup_config; then
        print_success "备份完成"
    else
        print_warn "无需备份（配置文件不存在）"
    fi
    
    # 步骤 2: 生成配置
    print_step "[2/5] 生成优化配置..."
    generate_proxy_config
    print_success "配置已生成"
    
    # 步骤 3: 安装系统服务
    if [[ "$PROXY_ADVANCED_OPTS" == "all" ]]; then
        print_step "[3/5] 安装系统服务..."
        install_system_services "haveged"
    else
        print_info "[3/5] 跳过系统服务安装"
    fi
    
    # 步骤 4: 应用配置
    print_step "[4/5] 应用 sysctl 配置..."
    local sysctl_errors=0
    local sysctl_applied=0
    if sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
        print_success "配置已应用"
    else
        # 逐行应用，统计成功/失败
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            if sysctl -w "$line" >/dev/null 2>&1; then
                ((++sysctl_applied))
            else
                ((++sysctl_errors))
            fi
        done < "$SYSCTL_FILE"
        if [[ $sysctl_errors -gt 0 ]]; then
            print_info "已应用 ${sysctl_applied} 项，${sysctl_errors} 项不被当前内核支持（不影响核心功能）"
        else
            print_success "配置已应用"
        fi
    fi
    
    # 步骤 5: 验证
    print_step "[5/5] 验证配置..."
    local current_algo
    current_algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    local current_qdisc
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    
    echo
    echo -e "  ${BOLD}${GREEN}${ICON_OK} 优化完成！${NC}"
    echo
    echo -e "  ${BOLD}当前状态:${NC}"
    printf "    %-15s : %s\n" "拥塞控制" "$current_algo"
    printf "    %-15s : %s\n" "队列调度" "$current_qdisc"
    
    if [[ "$PROXY_ADVANCED_OPTS" == "all" ]]; then
        local haveged_status="未运行"
        # 检查 haveged 状态
        if systemctl is-active haveged >/dev/null 2>&1; then
            haveged_status="运行中"
        elif pgrep -x haveged >/dev/null 2>&1; then
            haveged_status="运行中"
        fi
        printf "    %-15s : %s\n" "haveged" "$haveged_status"
    fi
    echo
    
    # 保存配置
    save_proxy_profile
}

# 保存代理配置
save_proxy_profile() {
    cat > "$PROXY_PROFILE_FILE" << EOF
# BBR3 代理调优配置文件
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
PROXY_HARDWARE_SCORE=$PROXY_HARDWARE_SCORE
PROXY_IS_LOW_SPEC=$PROXY_IS_LOW_SPEC
PROXY_CHAIN_ARCH=$PROXY_CHAIN_ARCH
PROXY_NODE_ROLE=$PROXY_NODE_ROLE
PROXY_SERVER_LOCATION=$PROXY_SERVER_LOCATION
PROXY_CLIENT_LOCATION=$PROXY_CLIENT_LOCATION
PROXY_LINE_TYPE=$PROXY_LINE_TYPE
PROXY_KERNEL=$PROXY_KERNEL
PROXY_PROTOCOL=$PROXY_PROTOCOL
PROXY_RESOURCE_RATIO=$PROXY_RESOURCE_RATIO
PROXY_ADVANCED_OPTS=$PROXY_ADVANCED_OPTS
EOF
    print_info "配置已保存到: $PROXY_PROFILE_FILE"
}

# 加载代理配置
load_proxy_profile() {
    if [[ -f "$PROXY_PROFILE_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$PROXY_PROFILE_FILE"
        return 0
    fi
    return 1
}

# 查看当前优化方案
show_current_optimization() {
    print_header "当前优化方案"
    echo
    
    # 检查是否有配置文件
    if [[ ! -f "$SYSCTL_FILE" ]]; then
        print_warn "未找到优化配置文件: $SYSCTL_FILE"
        print_info "尚未应用任何优化"
        echo
        read -rp "按 Enter 键继续..."
        return
    fi
    
    # 显示配置文件头部信息
    echo -e "  ${BOLD}📋 配置文件信息${NC}"
    print_separator
    printf "    %-15s : %s\n" "配置文件" "$SYSCTL_FILE"
    printf "    %-15s : %s\n" "修改时间" "$(stat -c '%y' "$SYSCTL_FILE" 2>/dev/null | cut -d. -f1 || echo '未知')"
    echo
    
    # 如果有代理配置文件，显示代理配置信息
    if [[ -f "$PROXY_PROFILE_FILE" ]]; then
        echo -e "  ${BOLD}🚀 代理调优配置${NC}"
        print_separator
        # shellcheck source=/dev/null
        source "$PROXY_PROFILE_FILE" 2>/dev/null
        printf "    %-15s : %s/100\n" "硬件评分" "${PROXY_HARDWARE_SCORE:-未知}"
        printf "    %-15s : %s\n" "链路架构" "${PROXY_CHAIN_ARCH:-未知}"
        printf "    %-15s : %s\n" "节点角色" "${PROXY_NODE_ROLE:-未知}"
        printf "    %-15s : %s\n" "服务器位置" "${PROXY_SERVER_LOCATION:-未知}"
        printf "    %-15s : %s\n" "客户端位置" "${PROXY_CLIENT_LOCATION:-未知}"
        printf "    %-15s : %s\n" "线路类型" "${PROXY_LINE_TYPE:-未知}"
        printf "    %-15s : %s\n" "代理内核" "${PROXY_KERNEL:-未知}"
        printf "    %-15s : %s\n" "代理协议" "${PROXY_PROTOCOL:-未知}"
        printf "    %-15s : %s%%\n" "资源占比" "${PROXY_RESOURCE_RATIO:-100}"
        printf "    %-15s : %s\n" "高级优化" "${PROXY_ADVANCED_OPTS:-none}"
        echo
    fi
    
    # 显示当前生效的关键参数
    echo -e "  ${BOLD}⚙️ 当前生效的优化参数${NC}"
    print_separator
    echo
    
    # 拥塞控制
    echo "    【拥塞控制】"
    local current_algo current_qdisc
    current_algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    printf "      %-20s : %s\n" "拥塞算法" "$current_algo"
    printf "      %-20s : %s\n" "队列调度" "$current_qdisc"
    echo
    
    # 缓冲区设置
    echo "    【缓冲区设置】"
    local rmem_max wmem_max
    rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "未知")
    wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null || echo "未知")
    printf "      %-20s : %s bytes (%s MB)\n" "rmem_max" "$rmem_max" "$((rmem_max / 1024 / 1024))"
    printf "      %-20s : %s bytes (%s MB)\n" "wmem_max" "$wmem_max" "$((wmem_max / 1024 / 1024))"
    echo
    
    # TCP 优化
    echo "    【TCP 优化】"
    local tfo ecn sack notsent_lowat
    tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "未知")
    ecn=$(sysctl -n net.ipv4.tcp_ecn 2>/dev/null || echo "未知")
    sack=$(sysctl -n net.ipv4.tcp_sack 2>/dev/null || echo "未知")
    notsent_lowat=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null || echo "未知")
    printf "      %-20s : %s\n" "TCP Fast Open" "$tfo"
    printf "      %-20s : %s\n" "TCP ECN" "$ecn"
    printf "      %-20s : %s\n" "TCP SACK" "$sack"
    printf "      %-20s : %s\n" "notsent_lowat" "$notsent_lowat"
    echo
    
    # 连接设置
    echo "    【连接设置】"
    local somaxconn tw_reuse fin_timeout keepalive
    somaxconn=$(sysctl -n net.core.somaxconn 2>/dev/null || echo "未知")
    tw_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo "未知")
    fin_timeout=$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo "未知")
    keepalive=$(sysctl -n net.ipv4.tcp_keepalive_time 2>/dev/null || echo "未知")
    printf "      %-20s : %s\n" "somaxconn" "$somaxconn"
    printf "      %-20s : %s\n" "tw_reuse" "$tw_reuse"
    printf "      %-20s : %s 秒\n" "fin_timeout" "$fin_timeout"
    printf "      %-20s : %s 秒\n" "keepalive_time" "$keepalive"
    echo
    
    # 系统服务状态
    echo "    【系统服务】"
    local haveged_status="未安装"
    if command -v haveged &>/dev/null; then
        systemctl is-active haveged >/dev/null 2>&1 && haveged_status="运行中" || haveged_status="已安装但未运行"
    fi
    printf "      %-20s : %s\n" "haveged" "$haveged_status"
    echo
    
    # 显示完整配置文件内容
    echo -e "  ${BOLD}📄 完整配置文件内容${NC}"
    print_separator
    echo
    while IFS= read -r line || [[ -n "$line" ]]; do
        echo "    $line"
    done < "$SYSCTL_FILE"
    echo
    
    read -rp "按 Enter 键继续..."
}

# 恢复默认配置
restore_default_config() {
    print_header "恢复默认配置"
    echo
    
    echo -e "  ${YELLOW}${ICON_WARN} 警告: 此操作将恢复系统默认的网络参数${NC}"
    echo
    echo "  将要执行的操作:"
    echo "    1. 删除 BBR 优化配置文件"
    echo "    2. 删除代理调优配置文件"
    echo "    3. 恢复系统默认 sysctl 参数"
    echo "    4. 停止并禁用 haveged（如果由脚本安装）"
    echo
    
    if ! confirm "确认恢复默认配置？此操作不可撤销！" "n"; then
        print_info "已取消操作"
        read -rp "按 Enter 键继续..."
        return
    fi
    
    echo
    print_step "[1/4] 备份当前配置..."
    if [[ -f "$SYSCTL_FILE" ]]; then
        local backup_file="${BACKUP_DIR}/99-bbr.conf.restore.$(date +%Y%m%d%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp "$SYSCTL_FILE" "$backup_file"
        print_success "配置已备份到: $backup_file"
    else
        print_info "无需备份（配置文件不存在）"
    fi
    
    print_step "[2/4] 删除配置文件..."
    if [[ -f "$SYSCTL_FILE" ]]; then
        rm -f "$SYSCTL_FILE"
        print_success "已删除: $SYSCTL_FILE"
    fi
    if [[ -f "$PROXY_PROFILE_FILE" ]]; then
        rm -f "$PROXY_PROFILE_FILE"
        print_success "已删除: $PROXY_PROFILE_FILE"
    fi
    
    print_step "[3/4] 恢复系统默认参数..."
    
    # 恢复关键参数到系统默认值
    local default_params=(
        "net.ipv4.tcp_congestion_control=cubic"
        "net.core.default_qdisc=fq_codel"
        "net.core.rmem_max=212992"
        "net.core.wmem_max=212992"
        "net.core.somaxconn=4096"
        "net.ipv4.tcp_fastopen=1"
        "net.ipv4.tcp_tw_reuse=2"
        "net.ipv4.tcp_fin_timeout=60"
        "net.ipv4.tcp_keepalive_time=7200"
        "net.ipv4.tcp_ecn=2"
        "net.ipv4.tcp_sack=1"
        "net.ipv4.tcp_notsent_lowat=4294967295"
    )
    
    for param in "${default_params[@]}"; do
        sysctl -w "$param" >/dev/null 2>&1 || true
    done
    print_success "系统参数已恢复默认值"
    
    print_step "[4/4] 重新加载系统配置..."
    sysctl --system >/dev/null 2>&1 || true
    print_success "系统配置已重新加载"
    
    echo
    echo -e "  ${BOLD}${GREEN}${ICON_OK} 恢复完成！${NC}"
    echo
    echo -e "  ${BOLD}当前状态:${NC}"
    printf "    %-15s : %s\n" "拥塞控制" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    printf "    %-15s : %s\n" "队列调度" "$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    echo
    print_info "如需重新优化，请运行代理智能调优向导"
    echo
    
    read -rp "按 Enter 键继续..."
}

# 代理调优向导主入口
proxy_tune_wizard() {
    print_header "代理服务器智能调优向导"
    
    # 检查是否有已保存的配置
    if load_proxy_profile; then
        echo
        print_info "检测到已保存的配置"
        echo
        printf "    %-15s : %s\n" "节点角色" "$PROXY_NODE_ROLE"
        printf "    %-15s : %s\n" "代理协议" "$PROXY_PROTOCOL"
        printf "    %-15s : %s\n" "线路类型" "$PROXY_LINE_TYPE"
        echo
        
        if confirm "是否使用已保存的配置？" "y"; then
            show_optimization_plan
            if confirm "确认应用此优化方案？" "y"; then
                execute_optimization
                read -rp "按 Enter 键继续..."
                return
            fi
        fi
    fi
    
    # 步骤 1: 硬件检测
    echo
    print_step "第一步：检测硬件"
    show_hardware_report
    
    # 步骤 1.5: 带宽/RTT 检测（用户手填优先）
    print_step "网络参数配置（带宽/RTT）..."
    echo
    echo -e "  ${BOLD}请输入您的服务器带宽（留空则自动检测）${NC}"
    echo -e "  ${DIM}提示: 如果您知道服务器带宽，建议手动输入以获得更准确的优化${NC}"
    echo
    local user_bandwidth
    user_bandwidth=$(read_input "服务器带宽 (Mbps)" "")
    
    if [[ -n "$user_bandwidth" ]] && [[ "$user_bandwidth" =~ ^[0-9]+$ ]] && [[ $user_bandwidth -gt 0 ]]; then
        SMART_DETECTED_BANDWIDTH=$user_bandwidth
        print_success "使用用户输入带宽: ${user_bandwidth} Mbps"
    else
        echo -e "${CYAN}正在自动检测带宽...${NC}"
        detect_bandwidth >/dev/null 2>&1
        print_kv "自动检测带宽" "${SMART_DETECTED_BANDWIDTH:-1000} Mbps"
    fi
    
    # RTT 检测
    detect_rtt >/dev/null 2>&1
    print_kv "检测 RTT" "${SMART_DETECTED_RTT:-100} ms"
    
    # 计算缓冲区
    calculate_bdp_buffer >/dev/null 2>&1
    local buffer_mb=$((SMART_OPTIMAL_BUFFER / 1024 / 1024))
    [[ $buffer_mb -eq 0 ]] && buffer_mb=64
    print_kv "推荐缓冲区" "${buffer_mb}MB"
    echo
    
    # 步骤 2: 内核检测
    print_step "第二步：内核检测"
    if ! check_current_kernel; then
        if confirm "是否现在安装 BBR3 内核？" "n"; then
            show_kernel_menu
        fi
    fi
    
    # 步骤 3-7: 收集信息
    print_step "第三步：链路架构"
    ask_chain_architecture
    
    print_step "第四步：位置信息"
    ask_server_location
    ask_client_location
    
    print_step "第五步：线路类型"
    ask_line_type
    
    print_step "第六步：代理内核"
    ask_proxy_kernel
    
    print_step "第七步：代理协议"
    ask_proxy_protocol
    
    print_step "第八步：资源分配"
    ask_resource_ratio
    
    print_step "第九步：高级优化"
    ask_advanced_optimization
    
    # 步骤 10: 显示方案
    print_step "第十步：生成优化方案"
    show_optimization_plan
    
    # 确认并执行
    if confirm "确认应用此优化方案？" "y"; then
        execute_optimization
    else
        print_info "已取消操作"
    fi
    
    echo
    read -rp "按 Enter 键继续..."
}

#===============================================================================
# 优化验证系统
#===============================================================================

# 验证结果存储
VERIFY_KERNEL_STATUS=0
VERIFY_ALGO_STATUS=0
VERIFY_QDISC_STATUS=0
VERIFY_BUFFER_STATUS=0
VERIFY_TCP_STATUS=0
VERIFY_SERVICE_STATUS=0
VERIFY_ISSUES=()
VERIFY_FIXES=()

# 验证 BBR3 内核
verify_kernel_bbr3() {
    local kernel_version
    kernel_version=$(uname -r)
    
    local available_algos
    available_algos=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "")
    
    local current_algo
    current_algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    
    echo -e "  ${BOLD}内核验证${NC}"
    print_separator
    echo
    
    # 检查内核版本
    printf "    %-25s : %s\n" "内核版本" "$kernel_version"
    
    # 检查 BBR3 可用性 - 使用词边界匹配,避免 grep -q "bbr" 同时命中 bbr2/bbr3/foobar
    local bbr3_available=false
    local bbr_available=false

    if printf '%s\n' $available_algos | grep -qx 'bbr3'; then
        bbr3_available=true
    fi
    if printf '%s\n' $available_algos | grep -qx 'bbr'; then
        bbr_available=true
    fi
    
    # 判断状态
    if [[ "$current_algo" == "bbr3" ]]; then
        printf "    %-25s : ${GREEN}✅ BBR3 已启用${NC}\n" "拥塞控制"
        VERIFY_KERNEL_STATUS=100
    elif [[ "$current_algo" == "bbr" ]]; then
        # 检查是否是 6.9+ 内核的 BBR3
        local kver_short
        kver_short=$(echo "$kernel_version" | sed 's/[^0-9.].*$//')
        if version_ge "$kver_short" "6.9.0"; then
            printf "    %-25s : ${GREEN}✅ BBR3 已启用 (内核内置)${NC}\n" "拥塞控制"
            VERIFY_KERNEL_STATUS=100
        else
            printf "    %-25s : ${YELLOW}⚠️ BBR 已启用 (非 BBR3)${NC}\n" "拥塞控制"
            VERIFY_KERNEL_STATUS=70
            VERIFY_ISSUES+=("BBR 已启用但非 BBR3 版本")
            VERIFY_FIXES+=("升级内核到 6.9+ 或安装 XanMod 内核")
        fi
    elif [[ "$bbr3_available" == "true" ]] || [[ "$bbr_available" == "true" ]]; then
        printf "    %-25s : ${YELLOW}⚠️ BBR 可用但未启用 (当前: $current_algo)${NC}\n" "拥塞控制"
        VERIFY_KERNEL_STATUS=30
        VERIFY_ISSUES+=("BBR 可用但未启用")
        VERIFY_FIXES+=("运行脚本应用优化配置")
    else
        printf "    %-25s : ${RED}❌ BBR 不可用 (当前: $current_algo)${NC}\n" "拥塞控制"
        VERIFY_KERNEL_STATUS=0
        VERIFY_ISSUES+=("内核不支持 BBR")
        VERIFY_FIXES+=("安装支持 BBR3 的内核 (XanMod/Liquorix/ELRepo)")
    fi
    
    # 显示可用算法
    printf "    %-25s : %s\n" "可用算法" "$available_algos"
    echo
    
    return $([[ $VERIFY_KERNEL_STATUS -ge 70 ]] && echo 0 || echo 1)
}

# 验证内核模块
verify_kernel_modules() {
    echo -e "  ${BOLD}模块状态${NC}"
    print_separator
    echo
    
    local tcp_bbr_loaded=false
    local sch_fq_loaded=false
    
    if lsmod 2>/dev/null | grep -q "tcp_bbr"; then
        tcp_bbr_loaded=true
        printf "    %-25s : ${GREEN}✅ 已加载${NC}\n" "tcp_bbr"
    else
        # 可能是内核内置
        if [[ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
            if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control; then
                printf "    %-25s : ${GREEN}✅ 内核内置${NC}\n" "tcp_bbr"
                tcp_bbr_loaded=true
            else
                printf "    %-25s : ${YELLOW}⚠️ 未加载${NC}\n" "tcp_bbr"
            fi
        fi
    fi
    
    if lsmod 2>/dev/null | grep -q "sch_fq"; then
        printf "    %-25s : ${GREEN}✅ 已加载${NC}\n" "sch_fq"
        sch_fq_loaded=true
    else
        if tc qdisc show 2>/dev/null | grep -q "fq"; then
            printf "    %-25s : ${GREEN}✅ 内核内置${NC}\n" "sch_fq"
            sch_fq_loaded=true
        else
            printf "    %-25s : ${DIM}未加载${NC}\n" "sch_fq"
        fi
    fi
    echo
}

# 验证拥塞控制和队列
verify_congestion_control() {
    local current_algo current_qdisc
    current_algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    
    echo -e "  ${BOLD}拥塞控制验证${NC}"
    print_separator
    echo
    
    # 检查算法
    if [[ "$current_algo" == "bbr3" ]] || [[ "$current_algo" == "bbr" ]]; then
        printf "    %-25s : ${GREEN}✅ %s${NC}\n" "拥塞算法" "$current_algo"
        VERIFY_ALGO_STATUS=100
    elif [[ "$current_algo" == "cubic" ]]; then
        printf "    %-25s : ${YELLOW}⚠️ %s (默认值)${NC}\n" "拥塞算法" "$current_algo"
        VERIFY_ALGO_STATUS=50
        VERIFY_ISSUES+=("使用默认 CUBIC 算法而非 BBR")
        VERIFY_FIXES+=("运行优化配置启用 BBR")
    else
        printf "    %-25s : ${DIM}%s${NC}\n" "拥塞算法" "$current_algo"
        VERIFY_ALGO_STATUS=30
    fi
    
    # 检查队列
    if [[ "$current_qdisc" == "fq" ]] || [[ "$current_qdisc" == "fq_codel" ]] || [[ "$current_qdisc" == "cake" ]]; then
        printf "    %-25s : ${GREEN}✅ %s${NC}\n" "队列调度" "$current_qdisc"
        VERIFY_QDISC_STATUS=100
    else
        printf "    %-25s : ${YELLOW}⚠️ %s${NC}\n" "队列调度" "$current_qdisc"
        VERIFY_QDISC_STATUS=50
        VERIFY_ISSUES+=("队列调度未优化")
        VERIFY_FIXES+=("设置 default_qdisc 为 fq 或 cake")
    fi
    echo
}

# 验证缓冲区设置
verify_buffer_settings() {
    local rmem_max wmem_max
    rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)
    wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null || echo 0)
    
    echo -e "  ${BOLD}缓冲区验证${NC}"
    print_separator
    echo
    
    # 检查接收缓冲区
    if [[ $rmem_max -ge $BUFFER_16MB ]]; then
        printf "    %-25s : ${GREEN}✅ %s MB${NC}\n" "rmem_max" "$((rmem_max / 1024 / 1024))"
        VERIFY_BUFFER_STATUS=$((VERIFY_BUFFER_STATUS + 50))
    elif [[ $rmem_max -ge 1048576 ]]; then
        printf "    %-25s : ${YELLOW}⚠️ %s MB (偏小)${NC}\n" "rmem_max" "$((rmem_max / 1024 / 1024))"
        VERIFY_BUFFER_STATUS=$((VERIFY_BUFFER_STATUS + 25))
        VERIFY_ISSUES+=("rmem_max 偏小")
        VERIFY_FIXES+=("增大 rmem_max 到 16MB 以上")
    else
        printf "    %-25s : ${RED}❌ %s bytes (过小)${NC}\n" "rmem_max" "$rmem_max"
        VERIFY_ISSUES+=("rmem_max 过小")
        VERIFY_FIXES+=("设置 rmem_max 至少 16MB")
    fi
    
    # 检查发送缓冲区
    if [[ $wmem_max -ge $BUFFER_16MB ]]; then
        printf "    %-25s : ${GREEN}✅ %s MB${NC}\n" "wmem_max" "$((wmem_max / 1024 / 1024))"
        VERIFY_BUFFER_STATUS=$((VERIFY_BUFFER_STATUS + 50))
    elif [[ $wmem_max -ge 1048576 ]]; then
        printf "    %-25s : ${YELLOW}⚠️ %s MB (偏小)${NC}\n" "wmem_max" "$((wmem_max / 1024 / 1024))"
        VERIFY_BUFFER_STATUS=$((VERIFY_BUFFER_STATUS + 25))
        VERIFY_ISSUES+=("wmem_max 偏小")
        VERIFY_FIXES+=("增大 wmem_max 到 16MB 以上")
    else
        printf "    %-25s : ${RED}❌ %s bytes (过小)${NC}\n" "wmem_max" "$wmem_max"
        VERIFY_ISSUES+=("wmem_max 过小")
        VERIFY_FIXES+=("设置 wmem_max 至少 16MB")
    fi
    echo
}

# 验证 TCP 参数
verify_tcp_params() {
    local tfo tw_reuse fin_timeout
    tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo 0)
    tw_reuse=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo 0)
    fin_timeout=$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo 60)
    
    echo -e "  ${BOLD}TCP 参数验证${NC}"
    print_separator
    echo
    
    VERIFY_TCP_STATUS=0
    local tcp_checks=0
    
    # TCP Fast Open
    if [[ $tfo -ge 3 ]]; then
        printf "    %-25s : ${GREEN}✅ %s (客户端+服务端)${NC}\n" "TCP Fast Open" "$tfo"
        VERIFY_TCP_STATUS=$((VERIFY_TCP_STATUS + 25))
    elif [[ $tfo -ge 1 ]]; then
        printf "    %-25s : ${YELLOW}⚠️ %s (仅部分启用)${NC}\n" "TCP Fast Open" "$tfo"
        VERIFY_TCP_STATUS=$((VERIFY_TCP_STATUS + 10))
        VERIFY_ISSUES+=("TCP Fast Open 仅部分启用")
        VERIFY_FIXES+=("设置 tcp_fastopen=3 启用双向")
    else
        printf "    %-25s : ${DIM}%s (未启用)${NC}\n" "TCP Fast Open" "$tfo"
    fi
    
    # TIME_WAIT 复用
    if [[ $tw_reuse -ge 1 ]]; then
        printf "    %-25s : ${GREEN}✅ 已启用${NC}\n" "TIME_WAIT 复用"
        VERIFY_TCP_STATUS=$((VERIFY_TCP_STATUS + 25))
    else
        printf "    %-25s : ${DIM}未启用${NC}\n" "TIME_WAIT 复用"
    fi
    
    # FIN 超时
    if [[ $fin_timeout -le 30 ]]; then
        printf "    %-25s : ${GREEN}✅ %s 秒${NC}\n" "FIN 超时" "$fin_timeout"
        VERIFY_TCP_STATUS=$((VERIFY_TCP_STATUS + 25))
    elif [[ $fin_timeout -le 60 ]]; then
        printf "    %-25s : ${YELLOW}⚠️ %s 秒 (默认值)${NC}\n" "FIN 超时" "$fin_timeout"
        VERIFY_TCP_STATUS=$((VERIFY_TCP_STATUS + 15))
    else
        printf "    %-25s : ${DIM}%s 秒${NC}\n" "FIN 超时" "$fin_timeout"
    fi
    
    # 慢启动
    local slow_start
    slow_start=$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null || echo 1)
    if [[ $slow_start -eq 0 ]]; then
        printf "    %-25s : ${GREEN}✅ 已禁用 (重连更快)${NC}\n" "慢启动"
        VERIFY_TCP_STATUS=$((VERIFY_TCP_STATUS + 25))
    else
        printf "    %-25s : ${DIM}默认${NC}\n" "慢启动"
    fi
    echo
}

# 验证系统服务
verify_system_services() {
    echo -e "  ${BOLD}系统服务验证${NC}"
    print_separator
    echo
    
    VERIFY_SERVICE_STATUS=0
    
    # haveged
    if command -v haveged &>/dev/null; then
        if systemctl is-active haveged >/dev/null 2>&1; then
            printf "    %-25s : ${GREEN}✅ 运行中${NC}\n" "haveged"
            VERIFY_SERVICE_STATUS=$((VERIFY_SERVICE_STATUS + 100))
        else
            printf "    %-25s : ${YELLOW}⚠️ 已安装但未运行${NC}\n" "haveged"
            VERIFY_SERVICE_STATUS=$((VERIFY_SERVICE_STATUS + 50))
            VERIFY_ISSUES+=("haveged 未运行")
            VERIFY_FIXES+=("运行 systemctl start haveged")
        fi
    else
        printf "    %-25s : ${DIM}未安装（可选）${NC}\n" "haveged"
        VERIFY_SERVICE_STATUS=100  # 未安装也不扣分
    fi
    echo
}

# 验证网络接口队列
verify_network_interface() {
    echo -e "  ${BOLD}网络接口验证${NC}"
    print_separator
    echo
    
    local default_if
    default_if=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
    
    if [[ -n "$default_if" ]]; then
        printf "    %-25s : %s\n" "默认网卡" "$default_if"
        
        local qdisc_info
        qdisc_info=$(tc qdisc show dev "$default_if" 2>/dev/null | head -1)
        
        if echo "$qdisc_info" | grep -qE "fq|cake|fq_codel"; then
            printf "    %-25s : ${GREEN}✅ %s${NC}\n" "队列规则" "$(echo "$qdisc_info" | awk '{print $2}')"
        else
            printf "    %-25s : ${DIM}%s${NC}\n" "队列规则" "$(echo "$qdisc_info" | awk '{print $2}')"
        fi
    else
        printf "    %-25s : ${YELLOW}⚠️ 无法检测${NC}\n" "默认网卡"
    fi
    echo
}

# 检查配置完整性
check_config_integrity() {
    echo -e "  ${BOLD}配置文件验证${NC}"
    print_separator
    echo
    
    local config_ok=true
    
    # 检查主配置文件
    if [[ -f "$SYSCTL_FILE" ]]; then
        printf "    %-25s : ${GREEN}✅ 存在${NC}\n" "sysctl 配置"
        
        # 检查语法
        if sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
            printf "    %-25s : ${GREEN}✅ 有效${NC}\n" "配置语法"
        else
            # 部分参数不被当前内核支持是正常现象，不算错误
            printf "    %-25s : ${GREEN}✅ 有效${NC} ${DIM}(部分高级参数不被当前内核支持)${NC}\n" "配置语法"
        fi
    else
        printf "    %-25s : ${RED}❌ 不存在${NC}\n" "sysctl 配置"
        config_ok=false
        VERIFY_ISSUES+=("优化配置文件不存在")
        VERIFY_FIXES+=("运行优化向导生成配置")
    fi
    
    # 检查代理配置文件
    if [[ -f "$PROXY_PROFILE_FILE" ]]; then
        printf "    %-25s : ${GREEN}✅ 存在${NC}\n" "代理配置"
    else
        printf "    %-25s : ${DIM}不存在${NC}\n" "代理配置"
    fi
    echo
    
    [[ "$config_ok" == "true" ]]
}

# 计算健康评分
calculate_health_score() {
    local total_score=0
    local weight_kernel=30
    local weight_algo=20
    local weight_buffer=20
    local weight_tcp=15
    local weight_service=15
    
    total_score=$((
        VERIFY_KERNEL_STATUS * weight_kernel / 100 +
        VERIFY_ALGO_STATUS * weight_algo / 100 +
        VERIFY_BUFFER_STATUS * weight_buffer / 100 +
        VERIFY_TCP_STATUS * weight_tcp / 100 +
        VERIFY_SERVICE_STATUS * weight_service / 100
    ))
    
    echo "$total_score"
}

# 获取健康评价
get_health_rating() {
    local score=$1
    
    if [[ $score -ge 90 ]]; then
        echo "优秀"
    elif [[ $score -ge 70 ]]; then
        echo "良好"
    elif [[ $score -ge 50 ]]; then
        echo "一般"
    elif [[ $score -ge 30 ]]; then
        echo "较差"
    else
        echo "需要优化"
    fi
}

# 验证智能优化状态
verify_smart_optimization() {
    echo -e "  ${BOLD}智能优化验证${NC}"
    print_separator
    echo
    
    # 检查 MSS Clamp
    local nic
    nic=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    local mss_status="未启用"
    if [[ -n "$nic" ]] && iptables -t mangle -C POSTROUTING -o "$nic" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        mss_status="${GREEN}✅ 已启用${NC}"
        SMART_MSS_CLAMP_ENABLED=1
    else
        mss_status="${YELLOW}⚠️ 未启用${NC}"
    fi
    printf "    %-25s : %b\n" "MSS Clamp" "$mss_status"
    
    # 检查 tcp_notsent_lowat
    local notsent_lowat
    notsent_lowat=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null || echo "-1")
    if [[ "$notsent_lowat" == "16384" ]]; then
        printf "    %-25s : ${GREEN}✅ %s${NC}\n" "tcp_notsent_lowat" "$notsent_lowat"
    elif [[ "$notsent_lowat" != "-1" ]]; then
        printf "    %-25s : ${YELLOW}⚠️ %s (推荐: 16384)${NC}\n" "tcp_notsent_lowat" "$notsent_lowat"
    else
        printf "    %-25s : ${DIM}不支持${NC}\n" "tcp_notsent_lowat"
    fi
    
    # 检查 tcp_mtu_probing
    local mtu_probing
    mtu_probing=$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null || echo "0")
    if [[ "$mtu_probing" == "1" ]] || [[ "$mtu_probing" == "2" ]]; then
        printf "    %-25s : ${GREEN}✅ 已启用${NC}\n" "MTU 探测"
    else
        printf "    %-25s : ${YELLOW}⚠️ 未启用${NC}\n" "MTU 探测"
    fi
    
    echo
}

# 生成诊断报告
generate_diagnostic_report() {
    # 重置状态
    VERIFY_KERNEL_STATUS=0
    VERIFY_ALGO_STATUS=0
    VERIFY_QDISC_STATUS=0
    VERIFY_BUFFER_STATUS=0
    VERIFY_TCP_STATUS=0
    VERIFY_SERVICE_STATUS=0
    VERIFY_ISSUES=()
    VERIFY_FIXES=()
    
    print_header "优化验证报告"
    echo
    
    # 执行所有验证
    verify_kernel_bbr3
    verify_kernel_modules
    verify_congestion_control
    verify_buffer_settings
    verify_tcp_params
    verify_system_services
    verify_network_interface
    check_config_integrity
    verify_smart_optimization
    
    # 计算健康评分
    local health_score
    health_score=$(calculate_health_score)
    local health_rating
    health_rating=$(get_health_rating "$health_score")
    
    # 显示健康评分
    echo -e "  ${BOLD}健康评分${NC}"
    print_separator
    echo
    
    local score_color
    if [[ $health_score -ge 70 ]]; then
        score_color="${GREEN}"
    elif [[ $health_score -ge 50 ]]; then
        score_color="${YELLOW}"
    else
        score_color="${RED}"
    fi
    
    printf "    ${BOLD}评分: ${score_color}%d/100${NC} (%s)\n" "$health_score" "$health_rating"
    echo
    
    # 显示问题和修复建议
    if [[ ${#VERIFY_ISSUES[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}发现的问题${NC}"
        print_separator
        echo
        for i in "${!VERIFY_ISSUES[@]}"; do
            printf "    ${YELLOW}⚠️ %s${NC}\n" "${VERIFY_ISSUES[$i]}"
            printf "       ${DIM}修复: %s${NC}\n" "${VERIFY_FIXES[$i]}"
        done
        echo
    else
        echo -e "  ${GREEN}${ICON_OK} 未发现问题，所有优化已生效！${NC}"
        echo
    fi
}

# 显示验证菜单
show_verification_menu() {
    while true; do
        print_header "优化验证"
        echo
        echo -e "  ${CYAN}1)${NC} 完整验证报告    - 检查所有优化项"
        echo -e "  ${CYAN}2)${NC} 内核验证        - 检查 BBR3 状态"
        echo -e "  ${CYAN}3)${NC} 参数验证        - 检查 sysctl 参数"
        echo -e "  ${CYAN}4)${NC} 服务验证        - 检查系统服务"
        echo -e "  ${CYAN}5)${NC} 健康评分        - 仅显示评分"
        echo
        echo -e "  ${CYAN}0)${NC} 返回"
        echo
        
        read_choice "请选择" 5
        
        case "$MENU_CHOICE" in
            0) return ;;
            1) generate_diagnostic_report ;;
            2) 
                VERIFY_KERNEL_STATUS=0
                VERIFY_ISSUES=()
                VERIFY_FIXES=()
                print_header "内核验证"
                echo
                verify_kernel_bbr3
                verify_kernel_modules
                ;;
            3)
                VERIFY_ALGO_STATUS=0
                VERIFY_BUFFER_STATUS=0
                VERIFY_TCP_STATUS=0
                VERIFY_ISSUES=()
                VERIFY_FIXES=()
                print_header "参数验证"
                echo
                verify_congestion_control
                verify_buffer_settings
                verify_tcp_params
                ;;
            4)
                VERIFY_SERVICE_STATUS=0
                VERIFY_ISSUES=()
                VERIFY_FIXES=()
                print_header "服务验证"
                echo
                verify_system_services
                verify_network_interface
                ;;
            5)
                VERIFY_KERNEL_STATUS=0
                VERIFY_ALGO_STATUS=0
                VERIFY_BUFFER_STATUS=0
                VERIFY_TCP_STATUS=0
                VERIFY_SERVICE_STATUS=0
                VERIFY_ISSUES=()
                VERIFY_FIXES=()
                # 静默执行验证
                verify_kernel_bbr3 >/dev/null 2>&1
                verify_congestion_control >/dev/null 2>&1
                verify_buffer_settings >/dev/null 2>&1
                verify_tcp_params >/dev/null 2>&1
                verify_system_services >/dev/null 2>&1
                local score
                score=$(calculate_health_score)
                local rating
                rating=$(get_health_rating "$score")
                echo
                echo -e "  健康评分: ${BOLD}${score}/100${NC} ($rating)"
                echo
                ;;
        esac
        
        read -rp "按 Enter 键继续..."
    done
}

# 快速验证（命令行用）
quick_verify() {
    VERIFY_KERNEL_STATUS=0
    VERIFY_ALGO_STATUS=0
    VERIFY_BUFFER_STATUS=0
    VERIFY_TCP_STATUS=0
    VERIFY_SERVICE_STATUS=0
    VERIFY_ISSUES=()
    VERIFY_FIXES=()
    
    # 静默执行验证
    verify_kernel_bbr3 >/dev/null 2>&1
    verify_congestion_control >/dev/null 2>&1
    verify_buffer_settings >/dev/null 2>&1
    verify_tcp_params >/dev/null 2>&1
    verify_system_services >/dev/null 2>&1
    
    local score
    score=$(calculate_health_score)
    local rating
    rating=$(get_health_rating "$score")
    
    local algo qdisc
    algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    
    echo "HEALTH_SCORE=$score"
    echo "HEALTH_RATING=$rating"
    echo "ALGO=$algo"
    echo "QDISC=$qdisc"
    echo "ISSUES=${#VERIFY_ISSUES[@]}"
    
    [[ $score -ge 70 ]]
}

# 场景配置菜单
scene_config_menu() {
    # 检测服务器资源并推荐模式
    recommend_scene_mode
    
    while true; do
        print_header "场景配置"
        
        echo -e "${DIM}根据使用场景选择预设优化方案，参数会根据服务器配置动态调整${NC}"
        echo
        
        # 获取自动检测的算法和队列
        local auto_algo auto_qdisc
        auto_algo=$(suggest_best_algo)
        auto_qdisc=$(suggest_best_qdisc "$SCENE_RECOMMENDED")
        
        # 显示服务器资源信息
        echo -e "  ${BOLD}服务器资源:${NC}"
        printf "    %-15s : %s 核\n" "CPU" "$SERVER_CPU_CORES"
        printf "    %-15s : %s MB\n" "内存" "$SERVER_MEMORY_MB"
        printf "    %-15s : %s Mbps\n" "网卡速度" "$SERVER_BANDWIDTH_MBPS"
        printf "    %-15s : %s\n" "TCP 连接数" "$SERVER_TCP_CONNECTIONS"
        printf "    %-15s : %s\n" "虚拟化" "${VIRT_TYPE:-未知}"
        echo
        echo -e "  ${BOLD}自动检测:${NC}"
        printf "    %-15s : %s\n" "最佳算法" "$auto_algo"
        printf "    %-15s : %s\n" "最佳队列" "$auto_qdisc"
        echo
        echo -e "  ${BOLD}推荐模式:${NC} ${GREEN}$(get_scene_name "$SCENE_RECOMMENDED")${NC}"
        echo -e "  ${DIM}$(get_scene_description "$SCENE_RECOMMENDED")${NC}"
        echo
        
        print_separator
        echo
        echo -e "  ${GREEN}${BOLD}1)${NC} ${GREEN}🚀 代理智能调优${NC} - ${GREEN}推荐翻墙用户！10步向导，自动生成最优配置${NC}"
        echo -e "  ${CYAN}2)${NC} ⚡ 智能自动优化  - 一键检测带宽/RTT并应用最优配置"
        echo -e "  ${CYAN}3)${NC} 📋 查看当前优化  - 查看已应用的所有优化参数"
        echo -e "  ${CYAN}4)${NC} ✅ 验证优化状态  - 检测优化是否生效"
        echo -e "  ${CYAN}5)${NC} 🔄 恢复默认配置  - 恢复系统默认网络参数"
        echo
        print_separator
        echo -e "  ${DIM}以下为通用预设模式（非翻墙用途）:${NC}"
        echo -e "  ${CYAN}6)${NC} 均衡模式    - 平衡延迟与吞吐量，适合一般用途"
        echo -e "  ${CYAN}7)${NC} 通信模式    - 优化低延迟，适合实时通信/游戏"
        echo -e "  ${CYAN}8)${NC} 视频模式    - 优化大文件传输，适合视频流/下载"
        echo -e "  ${CYAN}9)${NC} 并发模式    - 优化高并发，适合 Web/API 服务器"
        echo -e "  ${CYAN}10)${NC} 极速模式   - 最大化吞吐量，适合大带宽服务器"
        echo -e "  ${CYAN}11)${NC} 性能模式   - 全面性能优化，适合高性能计算"
        echo
        print_separator
        echo -e "  ${DIM}应用专项优化:${NC}"
        echo -e "  ${GREEN}12)${NC} ${GREEN}📱 应用优化${NC}  - LINE/Google/Apple/Meta/X/Telegram"
        echo -e "  ${YELLOW}13)${NC} ${YELLOW}🛡️  抗丢包${NC}   - 中转机/高丢包环境专用"
        echo -e "  ${PURPLE}14)${NC} ${PURPLE}📊 队列切换${NC} - fq/fq_codel/fq_pie/cake"
        echo
        echo -e "  ${CYAN}0)${NC} 返回主菜单"
        echo
        
        read_choice "请选择场景模式" 14
        
        local selected_mode=""
        case "$MENU_CHOICE" in
            0) return ;;
            1) proxy_tune_wizard; continue ;;
            2) smart_auto_optimize; continue ;;
            3) show_current_optimization; continue ;;
            4) show_verification_menu; continue ;;
            5) restore_default_config; continue ;;
            6) selected_mode="balanced" ;;
            7) selected_mode="communication" ;;
            8) selected_mode="video" ;;
            9) selected_mode="concurrent" ;;
            10) selected_mode="speed" ;;
            11) selected_mode="performance" ;;
            12) app_optimization_menu; continue ;;
            13) apply_anti_loss_optimization; continue ;;
            14) qdisc_switch_menu; continue ;;
            *) continue ;;
        esac
        
        # 显示参数摘要
        show_scene_params_summary "$selected_mode"
        
        # 二次确认
        if confirm "确认应用 $(get_scene_name "$selected_mode")？" "y"; then
            print_step "正在应用配置..."
            
            if apply_scene_mode "$selected_mode"; then
                echo
                print_success "$(get_scene_name "$selected_mode") 已成功应用！"
                echo
                echo -e "  ${BOLD}变更摘要:${NC}"
                echo "    - 配置文件: ${SYSCTL_FILE}"
                echo "    - 日志文件: ${LOG_FILE}"
                echo "    - 可使用备份功能回滚"
                echo
                
                read -rp "按 Enter 键继续..."
            else
                print_error "配置应用失败"
                read -rp "按 Enter 键继续..."
            fi
        fi
    done
}

# 验证 sysctl 配置文件格式
validate_sysctl_config() {
    local config_file="${1:-$SYSCTL_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        return 0  # 文件不存在，无需验证
    fi
    
    log_debug "验证配置文件格式: ${config_file}"
    
    local line_num=0
    local errors=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((++line_num))
        
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # 检查格式：key = value 或 key=value
        if ! echo "$line" | grep -qE '^[a-zA-Z0-9_.]+[[:space:]]*=[[:space:]]*[^[:space:]]'; then
            log_warn "配置文件第 ${line_num} 行格式错误: ${line}"
            ((++errors))
        fi
    done < "$config_file"
    
    if [[ $errors -gt 0 ]]; then
        log_warn "配置文件存在 ${errors} 处格式错误"
        return 1
    fi
    
    return 0
}

# 修复损坏的 sysctl 配置文件
repair_sysctl_config() {
    local config_file="${1:-$SYSCTL_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        return 0
    fi
    
    log_info "尝试修复配置文件: ${config_file}"
    
    # 备份原文件
    local backup_file="${config_file}.broken.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    log_info "原配置已备份到: ${backup_file}"
    
    # 创建临时文件
    local tmp_file
    tmp_file=$(mktemp)
    
    # 只保留有效行
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 保留空行和注释
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            echo "$line" >> "$tmp_file"
            continue
        fi
        
        # 只保留格式正确的配置行
        if echo "$line" | grep -qE '^[a-zA-Z0-9_.]+[[:space:]]*=[[:space:]]*[^[:space:]]'; then
            echo "$line" >> "$tmp_file"
        fi
    done < "$config_file"
    
    # 替换原文件
    mv "$tmp_file" "$config_file"
    
    print_success "配置文件已修复"
    return 0
}

# 写入 sysctl 配置
write_sysctl() {
    local algo="$1"
    local qdisc="$2"

    log_debug "写入 sysctl 配置: algo=${algo}, qdisc=${qdisc}"

    # 输入白名单 - 防止恶意/拼错值进入 heredoc
    case "$algo" in
        bbr|bbr2|bbr3|cubic|reno|hybla|westwood|veno|vegas|illinois) ;;
        *)
            print_error "拒绝未知的拥塞控制算法: ${algo}"
            return 1
            ;;
    esac
    case "$qdisc" in
        fq|fq_codel|fq_pie|cake|pfifo_fast|noqueue) ;;
        *)
            print_error "拒绝未知的 qdisc: ${qdisc}"
            return 1
            ;;
    esac

    # 先备份 - 备份失败必须中止,否则可能不可逆覆写用户配置
    if ! backup_config; then
        print_error "备份失败,取消写入 sysctl 配置"
        return 1
    fi

    # 创建配置目录
    if ! mkdir -p "$(dirname "$SYSCTL_FILE")"; then
        print_error "无法创建配置目录: $(dirname "$SYSCTL_FILE")"
        return 1
    fi

    # 原子写入: 写到 .new 后 mv 替换,避免半写状态
    local tmp_file="${SYSCTL_FILE}.new"
    if ! cat > "$tmp_file" << CONF
# BBR3 Script 自动生成配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 版本: ${SCRIPT_VERSION}

# TCP 拥塞控制算法
net.ipv4.tcp_congestion_control = ${algo}

# 默认队列规则
net.core.default_qdisc = ${qdisc}

# TCP 缓冲区优化
net.core.rmem_max = ${TUNE_RMEM_MAX:-67108864}
net.core.wmem_max = ${TUNE_WMEM_MAX:-67108864}
net.ipv4.tcp_rmem = 4096 87380 ${TUNE_TCP_RMEM_HIGH:-67108864}
net.ipv4.tcp_wmem = 4096 65536 ${TUNE_TCP_WMEM_HIGH:-67108864}

# 网络性能优化
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
CONF
    then
        rm -f -- "$tmp_file"
        print_error "写入临时配置失败: $tmp_file"
        return 1
    fi

    if ! mv -f -- "$tmp_file" "$SYSCTL_FILE"; then
        rm -f -- "$tmp_file"
        print_error "替换 sysctl 文件失败: $SYSCTL_FILE"
        return 1
    fi

    log_info "配置已写入: ${SYSCTL_FILE}"
    print_success "配置已写入: ${SYSCTL_FILE}"
    return 0
}

# 应用 sysctl 配置
apply_sysctl() {
    log_debug "应用 sysctl 配置..."
    
    # 先尝试完整应用
    if sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
        log_info "sysctl 配置已应用"
        print_success "配置已生效"
        return 0
    fi
    
    # 如果失败，尝试 sysctl --system
    log_warn "sysctl -p 失败，尝试 sysctl --system"
    if sysctl --system >/dev/null 2>&1; then
        print_success "配置已生效"
        return 0
    fi
    
    # 如果仍然失败，逐行应用
    log_warn "尝试逐行应用配置..."
    local errors=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # 尝试应用单个参数
        if ! sysctl -w "$line" >/dev/null 2>&1; then
            ((++errors))
        fi
    done < "$SYSCTL_FILE"
    
    if [[ $errors -gt 0 ]]; then
        print_info "已应用配置，${errors} 项参数不被当前内核支持（不影响核心功能）"
    else
        print_success "配置已生效"
    fi
    
    return 0
}

#===============================================================================
# BBR 核心功能
#===============================================================================

# 尝试加载内核模块（带错误处理）
try_load_modules() {
    log_debug "尝试加载内核模块..."
    
    local modules=("tcp_bbr3" "tcp_bbr" "sch_fq" "sch_fq_codel" "sch_cake" "sch_fq_pie")
    local loaded=0
    local failed=0
    local -a failed_modules=()
    
    for mod in "${modules[@]}"; do
        if modprobe "$mod" 2>/dev/null; then
            log_debug "模块 ${mod} 加载成功"
            ((++loaded))
        else
            # 检查模块是否已经加载
            if lsmod | grep -q "^${mod}"; then
                log_debug "模块 ${mod} 已加载"
                ((++loaded))
            else
                log_debug "模块 ${mod} 加载失败或不存在"
                failed_modules+=("$mod")
                ((++failed))
            fi
        fi
    done
    
    log_info "模块加载完成: ${loaded} 成功, ${failed} 失败/不存在"
    
    # 如果关键模块加载失败，记录警告
    if [[ " ${failed_modules[*]} " =~ " tcp_bbr " ]] && [[ " ${failed_modules[*]} " =~ " tcp_bbr3 " ]]; then
        log_warn "BBR 相关模块均未加载，可能需要更新内核"
    fi
    
    return 0
}

# 加载指定模块（带详细错误信息）
load_module_with_error() {
    local module="$1"
    local error_output
    
    if lsmod | grep -q "^${module}"; then
        log_debug "模块 ${module} 已加载"
        return 0
    fi
    
    error_output=$(modprobe "$module" 2>&1)
    local ret=$?
    
    if [[ $ret -eq 0 ]]; then
        log_info "模块 ${module} 加载成功"
        return 0
    fi
    
    # 分析错误原因
    if echo "$error_output" | grep -qi "not found"; then
        log_warn "模块 ${module} 不存在，可能需要安装对应内核或模块包"
    elif echo "$error_output" | grep -qi "Operation not permitted"; then
        log_warn "模块 ${module} 加载被拒绝，可能是安全限制"
    elif echo "$error_output" | grep -qi "Invalid argument"; then
        log_warn "模块 ${module} 参数无效"
    else
        log_warn "模块 ${module} 加载失败: ${error_output}"
    fi
    
    return 1
}

# 获取可用的拥塞控制算法
detect_available_algos() {
    local algo_file="/proc/sys/net/ipv4/tcp_available_congestion_control"
    
    if [[ -r "$algo_file" ]]; then
        AVAILABLE_ALGOS=$(cat "$algo_file" 2>/dev/null | tr ' ' '\n' | sort -u | tr '\n' ' ')
    else
        AVAILABLE_ALGOS=""
    fi
    
    echo "$AVAILABLE_ALGOS"
}

# 获取当前拥塞控制算法
get_current_algo() {
    CURRENT_ALGO=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    echo "$CURRENT_ALGO"
}

# 获取当前队列规则
# 注意: get_current_qdisc 的真正定义在下方第二处(运行时检测实际生效的 qdisc)
# 此处删除了 v2.1.0 中的旧定义,因为函数重复定义会被 bash 后者覆盖,
# 旧定义虽设置了 CURRENT_QDISC 全局但永远不会被调用。

# 检查算法是否可用
algo_supported() {
    local algo="$1"
    local available
    available=$(detect_available_algos)
    
    # 直接匹配
    if echo "$available" | grep -qw "$algo"; then
        return 0
    fi
    
    # BBR3 兼容性检查（某些内核以 bbr 名称提供 BBR3）
    if [[ "$algo" == "bbr3" ]]; then
        local kver
        kver=$(uname -r | sed 's/[^0-9.].*$//')
        if echo "$available" | grep -qw "bbr" && version_ge "$kver" "6.9.0"; then
            return 0
        fi
    fi
    
    return 1
}

# 检查队列规则是否可用
qdisc_supported() {
    local qdisc="$1"
    
    case "$qdisc" in
        fq|fq_codel)
            # 这些在大多数现代内核中都可用
            return 0
            ;;
        cake)
            modprobe sch_cake 2>/dev/null && return 0
            lsmod | grep -q '^sch_cake' && return 0
            return 1
            ;;
        fq_pie)
            modprobe sch_fq_pie 2>/dev/null && return 0
            lsmod | grep -q '^sch_fq_pie' && return 0
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# 规范化算法名称
normalize_algo() {
    local algo="$1"
    local kver
    kver=$(uname -r | sed 's/[^0-9.].*$//')
    
    # BBR3 可能以 bbr 名称提供
    if [[ "$algo" == "bbr3" ]]; then
        if ! echo "$(detect_available_algos)" | grep -qw "bbr3"; then
            if echo "$(detect_available_algos)" | grep -qw "bbr" && version_ge "$kver" "6.9.0"; then
                print_info "此内核以 'bbr' 名称提供 BBRv3" >&2
                echo "bbr"
                return 0
            fi
        fi
    fi
    
    echo "$algo"
}

# 获取推荐算法
suggest_best_algo() {
    local kver
    kver=$(uname -r | sed 's/[^0-9.].*$//')
    
    # 优先检测 bbr3 模块（XanMod 等内核）
    if algo_supported "bbr3"; then
        echo "bbr3"
        return
    fi
    
    # 检测主线 6.9+ 内核的 BBRv3（以 bbr 名称提供）
    if algo_supported "bbr" && version_ge "$kver" "6.9.0"; then
        echo "bbr"  # 实际是 BBRv3
        return
    fi
    
    # BBR2（某些补丁内核）
    if algo_supported "bbr2"; then
        echo "bbr2"
        return
    fi
    
    # BBRv1
    if algo_supported "bbr"; then
        echo "bbr"
        return
    fi
    
    echo "cubic"
}

# 获取推荐队列规则（根据场景自动选择）
suggest_best_qdisc() {
    local mode="${1:-balanced}"
    
    # 根据场景推荐最佳 qdisc
    case "$mode" in
        communication)
            # 通信模式：低延迟优先，fq_codel 有更好的延迟控制
            if qdisc_supported "fq_codel"; then
                echo "fq_codel"
            else
                echo "fq"
            fi
            ;;
        video|speed)
            # 视频/极速模式：大吞吐量，fq 是 BBR 最佳搭配
            echo "fq"
            ;;
        concurrent)
            # 并发模式：公平性重要，fq_codel 更公平
            if qdisc_supported "fq_codel"; then
                echo "fq_codel"
            else
                echo "fq"
            fi
            ;;
        performance)
            # 性能模式：尝试 cake（功能最全），否则 fq
            if qdisc_supported "cake"; then
                echo "cake"
            else
                echo "fq"
            fi
            ;;
        proxy)
            # 代理模式：fq 是 BBR 最佳搭配，抗丢包性能好
            # fq 对代理流量的 pacing 效果最好
            echo "fq"
            ;;
        balanced|*)
            # 均衡模式：fq_codel 平衡延迟和吞吐
            if qdisc_supported "fq_codel"; then
                echo "fq_codel"
            else
                echo "fq"
            fi
            ;;
    esac
}

# 获取默认网络接口
get_main_iface() {
    local dev
    dev=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
    
    if [[ -z "$dev" ]]; then
        dev=$(ip -o link 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}')
    fi
    
    echo "$dev"
}

# 应用运行时 qdisc
apply_qdisc_runtime() {
    local qdisc="$1"
    local dev
    dev=$(get_main_iface)
    
    [[ -z "$dev" ]] && return 0
    command -v tc >/dev/null 2>&1 || return 0
    
    log_debug "应用 qdisc ${qdisc} 到 ${dev}"
    
    tc qdisc replace dev "$dev" root "$qdisc" 2>/dev/null || true
}

#===============================================================================
# 队列调度（Qdisc）切换模块
#===============================================================================

# 获取 qdisc 描述
get_qdisc_description() {
    local qdisc="$1"
    case "$qdisc" in
        fq)
            echo "Fair Queue - BBR 最佳搭配，精确 pacing，高吞吐量"
            ;;
        fq_codel)
            echo "Fair Queue + CoDel - 低延迟，抗 Bufferbloat，适合通用场景"
            ;;
        fq_pie)
            echo "Fair Queue + PIE - 新一代 AQM，低延迟+高吞吐平衡"
            ;;
        cake)
            echo "CAKE - 最先进的 AQM，自动带宽整形，适合复杂网络"
            ;;
        pfifo_fast)
            echo "默认队列 - 简单 FIFO，无 AQM，不推荐"
            ;;
        *)
            echo "未知队列规则"
            ;;
    esac
}

# 获取 qdisc 推荐场景
get_qdisc_recommendation() {
    local qdisc="$1"
    case "$qdisc" in
        fq)
            echo "代理/VPN、大文件传输、BBR 用户"
            ;;
        fq_codel)
            echo "游戏、视频通话、通用场景"
            ;;
        fq_pie)
            echo "高负载服务器、需要低延迟+高吞吐"
            ;;
        cake)
            echo "家庭网关、复杂网络、需要带宽整形"
            ;;
        *)
            echo "不推荐"
            ;;
    esac
}

# 获取当前 qdisc
get_current_qdisc() {
    local dev qd
    dev=$(get_main_iface)

    if [[ -n "$dev" ]] && command -v tc >/dev/null 2>&1; then
        qd=$(tc qdisc show dev "$dev" 2>/dev/null | awk '/qdisc/ {print $2; exit}')
    fi
    if [[ -z "${qd:-}" ]]; then
        qd=$(sysctl -n net.core.default_qdisc 2>/dev/null) || qd="unknown"
    fi

    # 同时更新全局,任何遗留消费方仍可读到正确值
    CURRENT_QDISC="$qd"
    echo "$qd"
}

# 检测所有可用的 qdisc
detect_available_qdiscs() {
    local available=""
    
    # 基础 qdisc（几乎所有内核都支持）
    available="fq fq_codel pfifo_fast"
    
    # 检测 fq_pie（Linux 5.6+）- compgen -G 处理 .ko/.ko.xz/.ko.zst 等多种压缩后缀
    if modprobe sch_fq_pie 2>/dev/null || lsmod | grep -q '^sch_fq_pie'; then
        available="$available fq_pie"
    elif compgen -G "/lib/modules/$(uname -r)/kernel/net/sched/sch_fq_pie.ko*" >/dev/null; then
        modprobe sch_fq_pie 2>/dev/null
        available="$available fq_pie"
    fi

    # 检测 cake（Linux 4.19+，需要 sch_cake 模块）
    if modprobe sch_cake 2>/dev/null || lsmod | grep -q '^sch_cake'; then
        available="$available cake"
    elif compgen -G "/lib/modules/$(uname -r)/kernel/net/sched/sch_cake.ko*" >/dev/null; then
        modprobe sch_cake 2>/dev/null
        available="$available cake"
    fi
    
    echo "$available"
}

# 应用 qdisc 到系统
apply_qdisc_to_system() {
    local qdisc="$1"
    local dev
    dev=$(get_main_iface)
    
    # 1. 设置默认 qdisc（sysctl）
    print_step "设置默认队列规则为 ${qdisc}..."
    
    if sysctl -w "net.core.default_qdisc=$qdisc" >/dev/null 2>&1; then
        # 持久化到配置文件
        local qdisc_conf="/etc/sysctl.d/99-bbr-qdisc.conf"
        cat > "$qdisc_conf" << CONF
# BBR3 队列调度配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
net.core.default_qdisc = $qdisc
CONF
        print_success "默认队列规则已设置为 $qdisc"
    else
        print_error "设置默认队列规则失败"
        return 1
    fi
    
    # 2. 立即应用到网卡
    if [[ -n "$dev" ]] && command -v tc >/dev/null 2>&1; then
        print_step "应用队列规则到网卡 ${dev}..."
        
        # 先删除现有 qdisc
        tc qdisc del dev "$dev" root 2>/dev/null
        
        # 根据 qdisc 类型应用不同参数
        case "$qdisc" in
            fq)
                # fq 最佳参数：适合 BBR
                tc qdisc add dev "$dev" root fq 2>/dev/null && \
                    print_success "fq 已应用到 $dev" || \
                    print_warn "fq 应用失败，使用默认参数"
                ;;
            fq_codel)
                # fq_codel 参数：target 5ms, interval 100ms
                tc qdisc add dev "$dev" root fq_codel target 5ms interval 100ms 2>/dev/null && \
                    print_success "fq_codel 已应用到 $dev" || \
                    print_warn "fq_codel 应用失败"
                ;;
            fq_pie)
                # fq_pie 参数：target 15ms
                tc qdisc add dev "$dev" root fq_pie target 15ms 2>/dev/null && \
                    print_success "fq_pie 已应用到 $dev" || \
                    print_warn "fq_pie 应用失败"
                ;;
            cake)
                # cake 参数：自动带宽检测，适合代理
                # bandwidth 参数可选，不设置则自动检测
                tc qdisc add dev "$dev" root cake besteffort 2>/dev/null && \
                    print_success "cake 已应用到 $dev" || \
                    print_warn "cake 应用失败"
                ;;
            *)
                tc qdisc add dev "$dev" root "$qdisc" 2>/dev/null
                ;;
        esac
    fi
    
    return 0
}

# 队列调度切换菜单
qdisc_switch_menu() {
    while true; do
        clear
        print_header "队列调度（Qdisc）切换"
        
        # 显示当前状态
        local current_qdisc
        current_qdisc=$(get_current_qdisc)
        local default_qdisc
        default_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        
        echo -e "  ${BOLD}当前状态:${NC}"
        echo -e "    运行中队列: ${GREEN}${current_qdisc}${NC}"
        echo -e "    默认队列:   ${CYAN}${default_qdisc}${NC}"
        echo
        
        # 检测可用 qdisc
        local available
        available=$(detect_available_qdiscs)
        
        echo -e "  ${BOLD}可用队列规则:${NC}"
        for q in fq fq_codel fq_pie cake; do
            if echo "$available" | grep -qw "$q"; then
                local status="${GREEN}✓${NC}"
                [[ "$q" == "$current_qdisc" ]] && status="${GREEN}● 当前${NC}"
            else
                local status="${RED}✗ 不可用${NC}"
            fi
            printf "    %-12s : %s\n" "$q" "$status"
        done
        echo
        
        print_separator
        echo
        echo -e "  ${BOLD}选择队列规则:${NC}"
        echo
        echo -e "  ${GREEN}${BOLD}1)${NC} ${GREEN}fq${NC}         - $(get_qdisc_description fq)"
        echo -e "  ${CYAN}2)${NC} fq_codel   - $(get_qdisc_description fq_codel)"
        echo -e "  ${CYAN}3)${NC} fq_pie     - $(get_qdisc_description fq_pie)"
        echo -e "  ${CYAN}4)${NC} cake       - $(get_qdisc_description cake)"
        echo
        echo -e "  ${CYAN}5)${NC} 🔍 查看详细对比"
        echo -e "  ${CYAN}6)${NC} 🎯 智能推荐"
        echo
        echo -e "  ${CYAN}0)${NC} 返回上级菜单"
        echo
        
        read_choice "请选择" 6
        
        case "$MENU_CHOICE" in
            0) return ;;
            1) apply_qdisc_with_confirm "fq" "$available" ;;
            2) apply_qdisc_with_confirm "fq_codel" "$available" ;;
            3) apply_qdisc_with_confirm "fq_pie" "$available" ;;
            4) apply_qdisc_with_confirm "cake" "$available" ;;
            5) show_qdisc_comparison ;;
            6) show_qdisc_recommendation ;;
        esac
        
        echo
        read -rp "按 Enter 键继续..."
    done
}

# 带确认的 qdisc 应用
apply_qdisc_with_confirm() {
    local qdisc="$1"
    local available="$2"
    
    echo
    
    # 检查是否可用
    if ! echo "$available" | grep -qw "$qdisc"; then
        print_error "$qdisc 在当前系统不可用"
        echo
        echo -e "  ${YELLOW}可能原因:${NC}"
        echo "    • 内核版本过低（fq_pie 需要 5.6+，cake 需要 4.19+）"
        echo "    • 缺少内核模块 sch_${qdisc}"
        echo
        echo -e "  ${CYAN}解决方法:${NC}"
        echo "    • 升级内核版本"
        echo "    • 安装 iproute2 和相关模块"
        return 1
    fi
    
    print_header "应用 $qdisc"
    
    echo -e "  ${BOLD}队列规则:${NC} $qdisc"
    echo -e "  ${BOLD}描述:${NC} $(get_qdisc_description "$qdisc")"
    echo -e "  ${BOLD}推荐场景:${NC} $(get_qdisc_recommendation "$qdisc")"
    echo
    
    if ! confirm "确认切换到 $qdisc？" "y"; then
        return
    fi
    
    echo
    apply_qdisc_to_system "$qdisc"
    
    echo
    echo -e "${GREEN}${BOLD}${ICON_OK} 队列规则已切换为 $qdisc${NC}"
    echo
    echo -e "  ${BOLD}验证命令:${NC}"
    echo "    tc qdisc show"
    echo "    sysctl net.core.default_qdisc"
}

# 显示 qdisc 对比
show_qdisc_comparison() {
    print_header "队列规则详细对比"
    
    echo
    echo -e "  ${BOLD}┌─────────────┬────────────┬────────────┬────────────┬────────────┐${NC}"
    echo -e "  ${BOLD}│   特性      │     fq     │  fq_codel  │   fq_pie   │    cake    │${NC}"
    echo -e "  ${BOLD}├─────────────┼────────────┼────────────┼────────────┼────────────┤${NC}"
    echo -e "  │ 延迟控制    │    ★★★    │   ★★★★★   │   ★★★★    │   ★★★★★   │"
    echo -e "  │ 吞吐量      │   ★★★★★   │   ★★★★    │   ★★★★    │   ★★★★    │"
    echo -e "  │ BBR 兼容    │   ★★★★★   │   ★★★★    │   ★★★★    │   ★★★     │"
    echo -e "  │ 公平性      │   ★★★★    │   ★★★★★   │   ★★★★★   │   ★★★★★   │"
    echo -e "  │ CPU 占用    │    ★★★    │   ★★★★    │   ★★★★    │    ★★★    │"
    echo -e "  │ 配置复杂度  │     低     │     低     │     中     │     高     │"
    echo -e "  │ 内核要求    │   4.0+     │   3.5+     │   5.6+     │   4.19+    │"
    echo -e "  ${BOLD}└─────────────┴────────────┴────────────┴────────────┴────────────┘${NC}"
    echo
    echo -e "  ${BOLD}详细说明:${NC}"
    echo
    echo -e "  ${GREEN}fq (Fair Queue)${NC}"
    echo "    • BBR 官方推荐搭配，提供精确的 pacing"
    echo "    • 最高吞吐量，适合大文件传输和代理"
    echo "    • 无主动队列管理（AQM），依赖 BBR 控制拥塞"
    echo
    echo -e "  ${CYAN}fq_codel (Fair Queue + CoDel)${NC}"
    echo "    • 结合公平队列和 CoDel AQM"
    echo "    • 优秀的延迟控制，抗 Bufferbloat"
    echo "    • 适合游戏、视频通话等低延迟场景"
    echo
    echo -e "  ${YELLOW}fq_pie (Fair Queue + PIE)${NC}"
    echo "    • 新一代 AQM，PIE 算法比 CoDel 更激进"
    echo "    • 在高负载下保持低延迟"
    echo "    • 适合高并发服务器"
    echo
    echo -e "  ${PURPLE}cake (Common Applications Kept Enhanced)${NC}"
    echo "    • 最先进的队列规则，功能最全"
    echo "    • 自动带宽整形、流量分类、NAT 感知"
    echo "    • 适合家庭网关、复杂网络环境"
    echo "    • 注意：与 BBR 搭配可能不如 fq 效果好"
}

# 智能推荐 qdisc
show_qdisc_recommendation() {
    print_header "智能推荐"
    
    local current_algo
    current_algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local available
    available=$(detect_available_qdiscs)
    
    echo
    echo -e "  ${BOLD}当前拥塞算法:${NC} $current_algo"
    echo
    
    local recommended=""
    local reason=""
    
    # 根据拥塞算法推荐
    if [[ "$current_algo" =~ ^bbr ]]; then
        recommended="fq"
        reason="BBR 算法需要 fq 提供精确的 pacing 支持"
    else
        # 非 BBR 算法
        if echo "$available" | grep -qw "fq_pie"; then
            recommended="fq_pie"
            reason="fq_pie 提供更好的延迟控制和公平性"
        else
            recommended="fq_codel"
            reason="fq_codel 是通用场景的最佳选择"
        fi
    fi
    
    echo -e "  ${GREEN}${BOLD}推荐队列规则: $recommended${NC}"
    echo -e "  ${DIM}原因: $reason${NC}"
    echo
    
    echo -e "  ${BOLD}场景推荐:${NC}"
    echo
    echo -e "    ${GREEN}代理/VPN 服务器:${NC}"
    echo "      → fq（BBR 最佳搭配，最高吞吐）"
    echo
    echo -e "    ${CYAN}游戏/视频通话:${NC}"
    echo "      → fq_codel（低延迟优先）"
    echo
    echo -e "    ${YELLOW}高并发 Web 服务器:${NC}"
    echo "      → fq_pie（高负载下保持低延迟）"
    echo
    echo -e "    ${PURPLE}家庭网关/软路由:${NC}"
    echo "      → cake（自动带宽整形）"
    echo
    
    if confirm "是否应用推荐的 $recommended？" "y"; then
        echo
        apply_qdisc_to_system "$recommended"
    fi
}

# 自动调优
auto_tune() {
    log_debug "执行自动调优..."
    
    # 测量 RTT
    local target rtt_ms
    target=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
    [[ -z "$target" ]] && target="8.8.8.8"
    
    rtt_ms=$(ping -c 3 -W 2 "$target" 2>/dev/null | awk -F'/' '/rtt|round-trip/ {print $5}' | head -1)
    rtt_ms="${rtt_ms%%.*}"
    [[ -z "$rtt_ms" || "$rtt_ms" == "0" || ! "$rtt_ms" =~ ^[0-9]+$ ]] && rtt_ms=20
    
    # 获取接口速度
    local dev speed_mbps
    dev=$(get_main_iface)
    speed_mbps=1000
    
    if [[ -n "$dev" ]] && command -v ethtool >/dev/null 2>&1; then
        local speed_str
        speed_str=$(ethtool "$dev" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}')
        if [[ "$speed_str" =~ ([0-9]+) ]]; then
            speed_mbps="${BASH_REMATCH[1]}"
        fi
    fi
    
    # 计算 BDP
    local bdp_bytes max_bytes
    bdp_bytes=$(( speed_mbps * 1000000 / 8 * rtt_ms / 1000 ))
    max_bytes=$(( bdp_bytes * 2 ))
    
    # 限制范围 32MB - 256MB
    [[ $max_bytes -lt 33554432 ]] && max_bytes=33554432
    [[ $max_bytes -gt 268435456 ]] && max_bytes=268435456
    
    TUNE_RMEM_MAX=$max_bytes
    TUNE_WMEM_MAX=$max_bytes
    TUNE_TCP_RMEM_HIGH=$max_bytes
    TUNE_TCP_WMEM_HIGH=$max_bytes
    
    # 选择算法
    CHOSEN_ALGO=$(suggest_best_algo)
    
    # 选择 qdisc
    if [[ "$CHOSEN_ALGO" =~ ^bbr ]]; then
        CHOSEN_QDISC="fq"
    else
        CHOSEN_QDISC="fq_codel"
    fi
    
    print_info "自动调优结果："
    print_kv "RTT" "${rtt_ms} ms"
    print_kv "接口速度" "${speed_mbps} Mbps"
    print_kv "缓冲区大小" "$((max_bytes / 1048576)) MB"
    print_kv "推荐算法" "$CHOSEN_ALGO"
    print_kv "推荐队列" "$CHOSEN_QDISC"
}


#===============================================================================
# 镜像源管理
#===============================================================================

# 获取镜像源 URL
get_mirror_url() {
    local mirror_name="${1:-tsinghua}"
    
    if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
        echo "${MIRRORS_CN[$mirror_name]:-${MIRRORS_CN[tsinghua]}}"
    else
        echo ""
    fi
}

# 测试镜像源可用性
test_mirror() {
    local url="$1"
    local timeout=5
    
    if curl -s --connect-timeout "$timeout" --max-time "$timeout" -o /dev/null -w "%{http_code}" "$url" | grep -q "^[23]"; then
        return 0
    fi
    return 1
}

# 选择最佳镜像源
select_best_mirror() {
    if [[ $USE_CHINA_MIRROR -eq 0 ]]; then
        return
    fi
    
    print_info "正在测试镜像源..."
    
    for name in tsinghua aliyun ustc huawei; do
        local url="${MIRRORS_CN[$name]}"
        if test_mirror "$url"; then
            MIRROR_URL="$url"
            log_info "选择镜像源: ${name} (${url})"
            print_success "使用镜像源: ${name}"
            return 0
        fi
    done
    
    print_warn "所有国内镜像源不可用，将使用官方源"
    USE_CHINA_MIRROR=0
}

#===============================================================================
# 内核安装模块
#===============================================================================

# APT sources.list 原子替换助手
#
# 1. 写到 .new 后 mv,避免半写状态(原 cat > sources.list 的方式被 Ctrl-C/OOM
#    打断会留下半行,导致 apt update 直接报错,这是远程砖机的典型路径之一)
# 2. 临界区屏蔽 SIGINT/TERM
# 3. 失败时恢复 backup
# 4. 永远不在切换前 rm /var/lib/apt/lists/* (原代码 fix_apt_source 的逆序问题)
#
# 用法: _atomic_replace_apt_sources "$backup_file" "$new_content"
_atomic_replace_apt_sources() {
    local backup_file="$1"
    local new_content="$2"
    local sources_file="/etc/apt/sources.list"
    local tmp_file="${sources_file}.bbr3.new"

    # 备份(失败硬终止)
    if ! cp -- "$sources_file" "$backup_file"; then
        print_error "备份 $sources_file 失败,中止切换"
        return 1
    fi
    print_info "已备份原源配置到: $backup_file"

    critical_section_enter

    # 写到临时文件
    if ! printf '%s' "$new_content" > "$tmp_file"; then
        rm -f -- "$tmp_file"
        critical_section_exit
        print_error "写入临时源文件失败"
        return 1
    fi

    # 原子替换
    if ! mv -f -- "$tmp_file" "$sources_file"; then
        rm -f -- "$tmp_file"
        critical_section_exit
        print_error "替换 $sources_file 失败"
        return 1
    fi

    critical_section_exit
    return 0
}

# 切换 APT 源到官方源
switch_to_official_apt_sources() {
    local sources_file="/etc/apt/sources.list"
    local backup_file="/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)"

    print_step "检测到系统使用国内镜像源，正在切换到官方源..."

    # 根据发行版生成官方源
    local new_content=""
    case "$DIST_ID" in
        debian)
            local codename="${DIST_CODENAME:-bookworm}"
            new_content="# Debian Official Sources - Generated by BBR3 Script
deb http://deb.debian.org/debian ${codename} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security ${codename}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-backports main contrib non-free non-free-firmware
"
            ;;
        ubuntu)
            local codename="${DIST_CODENAME:-jammy}"
            new_content="# Ubuntu Official Sources - Generated by BBR3 Script
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
"
            ;;
        *)
            print_warn "不支持自动切换源的系统: $DIST_ID"
            return 1
            ;;
    esac

    if ! _atomic_replace_apt_sources "$backup_file" "$new_content"; then
        return 1
    fi

    print_success "已切换到官方源"

    # 更新源缓存
    print_step "更新软件包缓存..."
    if apt_update_cached 1; then
        print_success "软件包缓存更新成功"
        return 0
    else
        print_error "软件包缓存更新失败，正在恢复原源配置..."
        critical_section_enter
        cp -- "$backup_file" "$sources_file"
        critical_section_exit
        apt_update_cached 1 || true
        return 1
    fi
}

# 切换 APT 源到国内镜像
switch_to_china_apt_sources() {
    local sources_file="/etc/apt/sources.list"
    local backup_file="/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)"
    local mirror_url="${MIRROR_URL:-https://mirrors.tuna.tsinghua.edu.cn}"

    print_step "正在切换到国内镜像源..."

    # 根据发行版生成国内镜像源
    local new_content=""
    case "$DIST_ID" in
        debian)
            local codename="${DIST_CODENAME:-bookworm}"
            new_content="# Debian China Mirror Sources - Generated by BBR3 Script
deb ${mirror_url}/debian ${codename} main contrib non-free non-free-firmware
deb ${mirror_url}/debian ${codename}-updates main contrib non-free non-free-firmware
deb ${mirror_url}/debian-security ${codename}-security main contrib non-free non-free-firmware
deb ${mirror_url}/debian ${codename}-backports main contrib non-free non-free-firmware
"
            ;;
        ubuntu)
            local codename="${DIST_CODENAME:-jammy}"
            new_content="# Ubuntu China Mirror Sources - Generated by BBR3 Script
deb ${mirror_url}/ubuntu ${codename} main restricted universe multiverse
deb ${mirror_url}/ubuntu ${codename}-updates main restricted universe multiverse
deb ${mirror_url}/ubuntu ${codename}-backports main restricted universe multiverse
deb ${mirror_url}/ubuntu ${codename}-security main restricted universe multiverse
"
            ;;
        *)
            print_warn "不支持自动切换源的系统: $DIST_ID"
            return 1
            ;;
    esac

    if ! _atomic_replace_apt_sources "$backup_file" "$new_content"; then
        return 1
    fi

    print_success "已切换到国内镜像源"

    # 更新源缓存
    print_step "更新软件包缓存..."
    if apt_update_cached 1; then
        print_success "软件包缓存更新成功"
        return 0
    else
        print_error "软件包缓存更新失败，正在恢复原源配置..."
        critical_section_enter
        cp -- "$backup_file" "$sources_file"
        critical_section_exit
        apt_update_cached 1 || true
        return 1
    fi
}

# 检查并修复 APT 源（用于国外环境）
fix_apt_sources_for_intl() {
    # 仅在国外网络环境下执行
    if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
        return 0
    fi
    
    # 检测是否使用国内镜像
    if ! detect_apt_mirror_region; then
        print_warn "检测到国外网络环境，但系统使用国内镜像源"
        print_info "这可能导致第三方软件源（如 XanMod）无法正常访问"
        echo
        
        if [[ $NON_INTERACTIVE -eq 1 ]]; then
            # 非交互模式自动切换
            switch_to_official_apt_sources
        else
            if confirm "是否切换到官方源？（推荐）" "y"; then
                switch_to_official_apt_sources
            else
                print_warn "保持当前源配置，安装可能会失败"
            fi
        fi
    fi
}

# 检查并优化 APT 源（用于国内环境）
fix_apt_sources_for_china() {
    # 仅在国内网络环境下执行
    if [[ $USE_CHINA_MIRROR -eq 0 ]]; then
        return 0
    fi
    
    # 检测是否已使用国内镜像
    if detect_apt_mirror_region; then
        # 使用官方源，询问是否切换到国内镜像
        print_info "检测到国内网络环境，但系统使用官方源"
        print_info "切换到国内镜像可以加速软件包下载"
        echo
        
        if [[ $NON_INTERACTIVE -eq 0 ]]; then
            if confirm "是否切换到国内镜像源？" "n"; then
                switch_to_china_apt_sources
            fi
        fi
    fi
}

# 内核安装前检查
kernel_precheck() {
    local kernel_type="$1"
    
    # 架构检查
    if [[ "$ARCH_ID" != "amd64" ]]; then
        print_error "当前架构 ${ARCH_ID} 不支持安装 ${kernel_type} 内核（仅支持 amd64）"
        return 1
    fi
    
    # 虚拟化检查
    case "$VIRT_TYPE" in
        openvz|lxc|docker|wsl)
            print_error "容器环境 ${VIRT_TYPE} 无法安装内核"
            return 1
            ;;
    esac
    
    # 磁盘空间检查
    if ! precheck_disk; then
        return 1
    fi
    
    # 显示安装提示信息
    echo
    print_separator
    echo -e "  ${YELLOW}${BOLD}📢 安装提示${NC}"
    print_separator
    echo
    echo -e "  ${CYAN}首次安装 BBR3 内核会更新系统软件包及其相关依赖，请耐心等待。${NC}"
    echo
    echo -e "  • 如果大于 ${YELLOW}30 分钟${NC}未完成整个安装流程，请调整系统源/更新源后再试"
    echo -e "  • 根据您机器带宽大小和线路情况，首次安装时间不等"
    echo -e "  • 正常情况下 ${GREEN}3 分钟左右${NC}安装完毕"
    echo
    echo -e "  ${GREEN}感谢您的选择！${NC}"
    print_separator
    echo
    
    if ! confirm "了解以上信息，继续安装？" "y"; then
        print_info "已取消安装"
        return 1
    fi
    
    # 检查并修复 APT 源（国外环境）
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        fix_apt_sources_for_intl
    fi
    
    return 0
}

# 全局变量：记录安装前的内核列表 + /boot 快照
KERNEL_LIST_BEFORE=""
INSTALLED_KERNEL_PKG=""
INSTALLED_KERNEL_VERSION=""
BOOT_SNAPSHOT_VMLINUZ=""
BOOT_SNAPSHOT_INITRD=""
RUNNING_KERNEL=""
KNOWN_GOOD_KERNEL=""

# 记录安装前的内核列表 + /boot 快照 + 当前运行内核
#
# 这是回滚的信任根: 失败时我们必须知道哪个内核是 known-good,且它的 vmlinuz/initramfs
# 必须仍然在 /boot 上,GRUB 必须仍然能引导它。否则不能贸然移除新内核 -- 因为新内核虽然
# 失败,但移除它后可能没有任何可启动的内核了。
record_kernel_list_before() {
    log_debug "记录安装前的内核列表..."

    case "$PKG_MANAGER" in
        apt)
            KERNEL_LIST_BEFORE=$(dpkg -l | grep -E '^ii\s+linux-image-' | awk '{print $2}' | sort)
            ;;
        dnf|yum)
            KERNEL_LIST_BEFORE=$(rpm -qa | grep -E '^kernel-[0-9]|^kernel-ml|^kernel-lt' | sort)
            ;;
    esac

    # 快照 /boot 现有内核镜像和 initramfs (按文件名,稳定标识)
    BOOT_SNAPSHOT_VMLINUZ=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sort)
    BOOT_SNAPSHOT_INITRD=$(ls -1 /boot/initrd.img-* /boot/initramfs-*.img 2>/dev/null | sort)

    # 快照 /etc/default/grub 内容
    if [[ -f /etc/default/grub ]]; then
        if cp -- /etc/default/grub /etc/default/grub.bbr3.snapshot 2>/dev/null; then
            log_debug "已快照 /etc/default/grub"
        else
            log_warn "无法快照 /etc/default/grub,回滚时不能恢复其内容"
        fi
    fi

    # 记录当前运行内核 (绝对不能在回滚中误删)
    RUNNING_KERNEL=$(uname -r)

    log_debug "安装前内核列表: ${KERNEL_LIST_BEFORE}"
    log_debug "运行内核: ${RUNNING_KERNEL}"
}

# 验证: 至少有一个 known-good 内核仍可启动
# 用于回滚前的 sanity check,以及"成功状态"的信心校验
verify_known_good_kernel_present() {
    local found_good=0
    local kernels=()

    # 优先信任运行中的内核 - 它一定是 bootable 的 (我们在它上面跑)
    if [[ -n "${RUNNING_KERNEL:-}" && -f "/boot/vmlinuz-${RUNNING_KERNEL}" ]]; then
        kernels+=("$RUNNING_KERNEL")
        found_good=1
    fi

    # 退而求其次: 任何在快照中且 vmlinuz 仍存在的内核
    if [[ $found_good -eq 0 ]]; then
        local v
        while IFS= read -r v; do
            [[ -z "$v" ]] && continue
            if [[ -f "$v" ]]; then
                kernels+=("${v#/boot/vmlinuz-}")
                found_good=1
                break
            fi
        done <<< "$BOOT_SNAPSHOT_VMLINUZ"
    fi

    if [[ $found_good -eq 0 ]]; then
        return 1
    fi

    # 校验对应的 initramfs 存在 (否则 GRUB 引用空 initrd 会 panic)
    local k="${kernels[0]}"
    if [[ ! -f "/boot/initrd.img-${k}" && ! -f "/boot/initramfs-${k}.img" ]]; then
        log_warn "known-good 内核 ${k} 的 initramfs 不存在!"
        return 2
    fi

    KNOWN_GOOD_KERNEL="$k"
    return 0
}

# 验证内核安装是否成功
verify_kernel_installation() {
    local kernel_type="$1"
    local expected_pattern="${2:-}"
    
    echo
    print_header "内核安装验证"
    
    local kernel_list_after=""
    local new_kernels=""
    local all_checks_passed=1
    local kernel_version=""
    
    # ========== 检查 1: 新内核包 ==========
    echo -n "  [1/5] 检查新安装的内核包..."
    
    case "$PKG_MANAGER" in
        apt)
            kernel_list_after=$(dpkg -l | grep -E '^ii\s+linux-image-' | awk '{print $2}' | sort)
            new_kernels=$(comm -13 <(echo "$KERNEL_LIST_BEFORE") <(echo "$kernel_list_after"))
            ;;
        dnf|yum)
            kernel_list_after=$(rpm -qa | grep -E '^kernel-[0-9]|^kernel-ml|^kernel-lt' | sort)
            new_kernels=$(comm -13 <(echo "$KERNEL_LIST_BEFORE") <(echo "$kernel_list_after"))
            ;;
    esac
    
    if [[ -z "$new_kernels" ]]; then
        echo -e " [${RED}${ICON_FAIL}${NC}] 未检测到"
        all_checks_passed=0
    else
        local pkg_count
        # grep -c 在零匹配时返回非零退出码,旧代码 `|| echo 0` 会导致命中分支时
        # pkg_count 出现 "数字\n0" 的脏值。改用 grep -c -v '^$' 后再兜底。
        pkg_count=$(printf '%s\n' "$new_kernels" | grep -c -v '^[[:space:]]*$' 2>/dev/null || true)
        pkg_count=${pkg_count:-0}
        echo -e " [${GREEN}${ICON_OK}${NC}] 检测到 ${pkg_count} 个新包"
        echo "      新安装的包:"
        echo "$new_kernels" | while read -r pkg; do
            [[ -n "$pkg" ]] && echo "        - $pkg"
        done
    fi
    
    # ========== 检查 2: vmlinuz 内核文件 ==========
    echo -n "  [2/5] 检查内核文件 (vmlinuz)..."
    
    local kernel_file=""
    case "$PKG_MANAGER" in
        apt)
            for pkg in $new_kernels; do
                local version="${pkg#linux-image-}"
                version="${version%-unsigned}"
                if [[ -f "/boot/vmlinuz-${version}" ]]; then
                    kernel_file="/boot/vmlinuz-${version}"
                    kernel_version="$version"
                    INSTALLED_KERNEL_PKG="$pkg"
                    INSTALLED_KERNEL_VERSION="$kernel_version"
                    break
                fi
            done
            ;;
        dnf|yum)
            for pkg in $new_kernels; do
                local version
                version=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg" 2>/dev/null)
                if [[ -f "/boot/vmlinuz-${version}" ]]; then
                    kernel_file="/boot/vmlinuz-${version}"
                    kernel_version="$version"
                    INSTALLED_KERNEL_PKG="$pkg"
                    INSTALLED_KERNEL_VERSION="$kernel_version"
                    break
                fi
            done
            ;;
    esac
    
    if [[ -z "$kernel_file" ]]; then
        echo -e " [${RED}${ICON_FAIL}${NC}] 未找到"
        all_checks_passed=0
    else
        local file_size
        file_size=$(ls -lh "$kernel_file" 2>/dev/null | awk '{print $5}')
        echo -e " [${GREEN}${ICON_OK}${NC}] 存在"
        echo "      文件: $kernel_file"
        echo "      大小: $file_size"
    fi
    
    # ========== 检查 3: initramfs 文件 ==========
    echo -n "  [3/5] 检查 initramfs 文件..."
    
    local initramfs_file=""
    if [[ -n "$kernel_version" ]]; then
        case "$PKG_MANAGER" in
            apt)
                [[ -f "/boot/initrd.img-${kernel_version}" ]] && initramfs_file="/boot/initrd.img-${kernel_version}"
                ;;
            dnf|yum)
                [[ -f "/boot/initramfs-${kernel_version}.img" ]] && initramfs_file="/boot/initramfs-${kernel_version}.img"
                ;;
        esac
    fi
    
    if [[ -z "$initramfs_file" ]]; then
        echo -e " [${YELLOW}${ICON_WARN}${NC}] 未找到，尝试生成..."
        if regenerate_initramfs "$new_kernels"; then
            # 重新检查
            case "$PKG_MANAGER" in
                apt)
                    [[ -f "/boot/initrd.img-${kernel_version}" ]] && initramfs_file="/boot/initrd.img-${kernel_version}"
                    ;;
                dnf|yum)
                    [[ -f "/boot/initramfs-${kernel_version}.img" ]] && initramfs_file="/boot/initramfs-${kernel_version}.img"
                    ;;
            esac
            if [[ -n "$initramfs_file" ]]; then
                echo -e "      [${GREEN}${ICON_OK}${NC}] 生成成功: $initramfs_file"
            else
                echo -e "      [${RED}${ICON_FAIL}${NC}] 生成失败"
                all_checks_passed=0
            fi
        else
            echo -e "      [${RED}${ICON_FAIL}${NC}] 生成失败"
            all_checks_passed=0
        fi
    else
        local file_size
        file_size=$(ls -lh "$initramfs_file" 2>/dev/null | awk '{print $5}')
        echo -e " [${GREEN}${ICON_OK}${NC}] 存在"
        echo "      文件: $initramfs_file"
        echo "      大小: $file_size"
    fi
    
    # ========== 检查 4: GRUB 配置 ==========
    echo -n "  [4/5] 检查 GRUB 配置..."
    
    local grub_cfg=""
    for cfg in /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg; do
        [[ -f "$cfg" ]] && grub_cfg="$cfg" && break
    done
    
    local grub_has_kernel=0
    if [[ -n "$grub_cfg" ]] && [[ -n "$kernel_version" ]]; then
        if grep -q "$kernel_version" "$grub_cfg" 2>/dev/null; then
            grub_has_kernel=1
        fi
    fi
    
    if [[ $grub_has_kernel -eq 0 ]]; then
        echo -e " [${YELLOW}${ICON_WARN}${NC}] 未找到新内核，尝试更新..."
        if update_grub_config; then
            # 重新检查
            if [[ -n "$grub_cfg" ]] && grep -q "$kernel_version" "$grub_cfg" 2>/dev/null; then
                echo -e "      [${GREEN}${ICON_OK}${NC}] GRUB 更新成功"
                grub_has_kernel=1
            else
                echo -e "      [${RED}${ICON_FAIL}${NC}] GRUB 更新后仍未找到新内核"
                all_checks_passed=0
            fi
        else
            echo -e "      [${RED}${ICON_FAIL}${NC}] GRUB 更新失败"
            all_checks_passed=0
        fi
    else
        echo -e " [${GREEN}${ICON_OK}${NC}] 已包含新内核"
        echo "      配置文件: $grub_cfg"
    fi
    
    # ========== 检查 5: 默认启动项 ==========
    echo -n "  [5/5] 检查默认启动项..."
    
    local default_kernel=""
    if [[ -f /etc/default/grub ]]; then
        local grub_default
        grub_default=$(grep "^GRUB_DEFAULT=" /etc/default/grub 2>/dev/null | cut -d= -f2 | tr -d '"')
        if [[ "$grub_default" == "0" ]] || [[ "$grub_default" == "saved" ]]; then
            # 获取第一个启动项
            if [[ -n "$grub_cfg" ]]; then
                default_kernel=$(grep -m1 "menuentry.*linux" "$grub_cfg" 2>/dev/null | head -1)
            fi
            echo -e " [${GREEN}${ICON_OK}${NC}] 默认启动最新内核"
        else
            echo -e " [${YELLOW}${ICON_WARN}${NC}] GRUB_DEFAULT=$grub_default"
            echo "      可能不会启动新内核，请检查 /etc/default/grub"
        fi
    else
        echo -e " [${YELLOW}${ICON_WARN}${NC}] 无法检测"
    fi
    
    # ========== 总结 ==========
    echo
    print_separator
    
    if [[ $all_checks_passed -eq 1 ]]; then
        print_success "内核安装验证通过！"
        echo
        echo "  新内核版本: ${kernel_version}"
        echo "  内核文件:   ${kernel_file}"
        echo "  initramfs:  ${initramfs_file}"
        echo
        return 0
    else
        print_error "内核安装验证失败！"
        echo
        print_warn "建议操作："
        echo "  1. 不要重启系统"
        echo "  2. 检查 /boot 目录空间: df -h /boot"
        echo "  3. 检查安装日志: /var/log/apt/history.log"
        echo "  4. 尝试重新安装或回滚"
        echo
        return 1
    fi
}

# 重新生成 initramfs
#
# 临界区: Ctrl-C 落在 update-initramfs 中途会留下半个 initrd.img,
# 启动时 kernel panic。用 critical_section_enter/exit 屏蔽 INT/TERM。
# shellcheck disable=SC2178,SC2128 # kernels 是空格分隔的字符串,故意做词分割
regenerate_initramfs() {
    local kernels="$1"

    print_step "重新生成 initramfs..."
    print_info "提示: 此过程不可中断,请耐心等待"

    critical_section_enter
    local rc=0

    case "$PKG_MANAGER" in
        apt)
            for pkg in $kernels; do
                local version="${pkg#linux-image-}"
                version="${version%-unsigned}"
                print_info "为 ${version} 生成 initramfs..."
                if ! update-initramfs -c -k "$version" 2>/dev/null; then
                    # 尝试使用 -u 更新
                    if ! update-initramfs -u -k "$version"; then
                        print_error "为 ${version} 生成 initramfs 失败,清理半生成文件"
                        # 半生成的 initrd 必须清理,否则 /boot 占空间且 GRUB 引用空文件
                        rm -f -- "/boot/initrd.img-${version}"
                        rc=1
                        break
                    fi
                fi
            done
            ;;
        dnf|yum)
            for pkg in $kernels; do
                local version
                version=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg" 2>/dev/null)
                print_info "为 ${version} 生成 initramfs..."
                if ! dracut -f "/boot/initramfs-${version}.img" "$version"; then
                    rm -f -- "/boot/initramfs-${version}.img"
                    rc=1
                    break
                fi
            done
            ;;
    esac

    critical_section_exit
    return $rc
}

# 验证 GRUB 配置
verify_grub_config() {
    local kernels="$1"
    
    print_step "验证 GRUB 配置..."
    
    local grub_cfg=""
    if [[ -f /boot/grub/grub.cfg ]]; then
        grub_cfg="/boot/grub/grub.cfg"
    elif [[ -f /boot/grub2/grub.cfg ]]; then
        grub_cfg="/boot/grub2/grub.cfg"
    else
        # SC2144: [[ -f glob ]] 不展开 glob,只匹配字面量。改用 compgen -G
        local efi_cfg
        for efi_cfg in /boot/efi/EFI/*/grub.cfg; do
            if [[ -f "$efi_cfg" ]]; then
                grub_cfg="$efi_cfg"
                break
            fi
        done
    fi
    
    if [[ -z "$grub_cfg" ]] || [[ ! -f "$grub_cfg" ]]; then
        print_warn "未找到 GRUB 配置文件"
        return 1
    fi
    
    # 检查新内核是否在 GRUB 配置中
    for pkg in $kernels; do
        local version=""
        case "$PKG_MANAGER" in
            apt)
                version="${pkg#linux-image-}"
                version="${version%-unsigned}"
                ;;
            dnf|yum)
                version=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg" 2>/dev/null)
                ;;
        esac
        
        if grep -q "$version" "$grub_cfg" 2>/dev/null; then
            print_success "GRUB 配置包含新内核: ${version}"
            return 0
        fi
    done
    
    print_warn "GRUB 配置中未找到新内核"
    return 1
}

# 更新 GRUB 配置
#
# 临界区: Ctrl-C 落在 grub-mkconfig 中途 = grub.cfg 半写 = 重启进 rescue
update_grub_config() {
    print_step "更新 GRUB 配置..."
    print_info "提示: 此过程不可中断"

    critical_section_enter
    local rc=0

    case "$PKG_MANAGER" in
        apt)
            if command -v update-grub >/dev/null 2>&1; then
                update-grub || rc=1
            elif command -v grub-mkconfig >/dev/null 2>&1; then
                grub-mkconfig -o /boot/grub/grub.cfg || rc=1
            else
                print_error "未找到 GRUB 更新命令"
                rc=1
            fi
            ;;
        dnf|yum)
            if command -v grub2-mkconfig >/dev/null 2>&1; then
                local grub_cfg="/boot/grub2/grub.cfg"
                if [[ -d /boot/efi/EFI ]]; then
                    local efi_subdir
                    efi_subdir=$(find /boot/efi/EFI -maxdepth 1 -mindepth 1 -type d ! -name BOOT 2>/dev/null | head -1)
                    if [[ -n "$efi_subdir" && -f "${efi_subdir}/grub.cfg" ]]; then
                        grub_cfg="${efi_subdir}/grub.cfg"
                    fi
                fi
                grub2-mkconfig -o "$grub_cfg" || rc=1
            else
                print_error "未找到 GRUB 更新命令"
                rc=1
            fi
            ;;
    esac

    critical_section_exit
    if [[ $rc -eq 0 ]]; then
        print_success "GRUB 配置已更新"
    else
        print_error "GRUB 配置更新失败"
    fi
    return $rc
}

# 回滚内核安装
#
# v2.1.1 强化:
#  1. 回滚前必须确认有 known-good 内核仍在 /boot 上
#  2. 移除新内核后必须成功重建 GRUB,失败硬终止并打印恢复指令
#  3. 移除前先恢复 /etc/default/grub 快照(如有)
#  4. 拒绝移除当前正在运行的内核
#  5. 临界区屏蔽 SIGINT/TERM
rollback_kernel_installation() {
    local kernel_type="$1"

    print_header "回滚 ${kernel_type} 内核安装"
    print_warn "内核安装验证失败，正在回滚..."

    # 第一步: 确认有 known-good 内核可恢复,否则不能动新内核
    if ! verify_known_good_kernel_present; then
        print_error "无法找到 known-good 内核(/boot 上没有完整的 vmlinuz+initramfs)"
        print_error "拒绝回滚以避免移除唯一的可启动内核"
        print_warn "建议: 不要重启,手动检查 /boot 内容并恢复"
        return 1
    fi
    print_info "已识别 known-good 内核: ${KNOWN_GOOD_KERNEL}"

    if [[ -z "$INSTALLED_KERNEL_PKG" ]]; then
        # 尝试找出新安装的内核包
        local kernel_list_after=""
        case "$PKG_MANAGER" in
            apt)
                kernel_list_after=$(dpkg -l | grep -E '^ii\s+linux-image-' | awk '{print $2}' | sort)
                INSTALLED_KERNEL_PKG=$(comm -13 <(echo "$KERNEL_LIST_BEFORE") <(echo "$kernel_list_after") | head -1)
                ;;
            dnf|yum)
                kernel_list_after=$(rpm -qa | grep -E '^kernel-[0-9]|^kernel-ml|^kernel-lt' | sort)
                INSTALLED_KERNEL_PKG=$(comm -13 <(echo "$KERNEL_LIST_BEFORE") <(echo "$kernel_list_after") | head -1)
                ;;
        esac
    fi

    if [[ -z "$INSTALLED_KERNEL_PKG" ]]; then
        print_warn "未找到需要回滚的内核包"
        return 1
    fi

    # 拒绝移除运行中的内核(理论上不会发生,但防御性检查)
    if [[ -n "${RUNNING_KERNEL:-}" && "$INSTALLED_KERNEL_PKG" == *"$RUNNING_KERNEL"* ]]; then
        print_error "拒绝回滚: 待移除的内核包似乎是当前运行的内核 (${RUNNING_KERNEL})"
        return 1
    fi

    # 恢复 /etc/default/grub 快照(若有)
    if [[ -f /etc/default/grub.bbr3.snapshot ]]; then
        print_step "恢复 /etc/default/grub 快照..."
        if ! cp -- /etc/default/grub.bbr3.snapshot /etc/default/grub; then
            print_warn "恢复 /etc/default/grub 失败,继续但 GRUB 设置可能不一致"
        fi
    fi

    print_step "卸载内核包: ${INSTALLED_KERNEL_PKG}"

    critical_section_enter
    local remove_rc=0

    case "$PKG_MANAGER" in
        apt)
            # 卸载内核包及相关包(失败必须报告,但继续清理 GRUB)
            apt-get remove -y "$INSTALLED_KERNEL_PKG" || remove_rc=1
            local headers_pkg="${INSTALLED_KERNEL_PKG/linux-image/linux-headers}"
            apt-get remove -y "$headers_pkg" 2>/dev/null || true
            apt-get autoremove -y || true
            ;;
        dnf|yum)
            local pkg_mgr=yum
            command -v dnf >/dev/null 2>&1 && pkg_mgr=dnf
            "$pkg_mgr" remove -y "$INSTALLED_KERNEL_PKG" || remove_rc=1
            ;;
    esac

    critical_section_exit

    if [[ $remove_rc -ne 0 ]]; then
        print_warn "包管理器返回错误,但已尽力卸载"
    fi

    # 更新 GRUB - 失败必须硬报告(不再 || true 假装成功)
    if ! update_grub_config; then
        print_error "==============================================="
        print_error "严重: GRUB 配置更新失败"
        print_error "==============================================="
        print_error "系统当前可能处于 GRUB 引用已删除内核的状态。"
        print_error "强烈建议在重启前手动执行:"
        print_error "  1. ls /boot/vmlinuz-*    # 确认仍有可启动内核"
        print_error "  2. update-grub  或  grub2-mkconfig -o /boot/grub2/grub.cfg"
        print_error "  3. 检查 /boot/grub/grub.cfg 是否包含 ${KNOWN_GOOD_KERNEL}"
        return 1
    fi

    # 最终校验: known-good 内核仍可启动
    if ! verify_known_good_kernel_present; then
        print_error "回滚后未能确认 known-good 内核仍存在"
        print_error "请手动检查 /boot 后再重启"
        return 1
    fi

    print_success "内核回滚完成"
    print_info "已确认可启动内核: ${KNOWN_GOOD_KERNEL}"
    print_info "系统将继续使用当前内核: ${RUNNING_KERNEL:-$(uname -r)}"

    return 0
}

# 安全的内核安装包装函数
safe_kernel_install() {
    local kernel_type="$1"
    local install_func="$2"
    
    # 记录安装前状态
    record_kernel_list_before
    
    # 执行安装
    if ! $install_func; then
        print_error "${kernel_type} 内核安装失败"
        return 1
    fi
    
    # 验证安装
    if ! verify_kernel_installation "$kernel_type"; then
        print_error "${kernel_type} 内核安装验证失败"
        
        if [[ $NON_INTERACTIVE -eq 1 ]]; then
            # 非交互模式自动回滚
            rollback_kernel_installation "$kernel_type"
        else
            if confirm "是否回滚内核安装？（强烈建议）" "y"; then
                rollback_kernel_installation "$kernel_type"
            else
                print_error "警告：内核安装可能不完整，重启后系统可能无法启动！"
                print_warn "建议手动检查 /boot 目录和 GRUB 配置"
            fi
        fi
        return 1
    fi
    
    print_success "${kernel_type} 内核安装并验证成功"
    print_kernel_post_install_summary "$kernel_type"
    return 0
}

# 内核安装后提示摘要与下一步
print_kernel_post_install_summary() {
    local kernel_type="$1"
    local verify_hint

    if [[ $APPLY_GUIDANCE_SHOWN -eq 1 ]]; then
        return 0
    fi

    if [[ -x /usr/local/bin/bbr3 ]]; then
        verify_hint="bbr3 --verify / bbr3 --status"
    else
        verify_hint="sudo ${SCRIPT_NAME} --verify / --status"
    fi

    echo
    print_separator
    echo -e "  ${GREEN}${ICON_OK}${NC} ${kernel_type} 内核安装完成"
    print_separator
    print_kv "新内核包" "${INSTALLED_KERNEL_PKG:-未知}"
    [[ -n "${INSTALLED_KERNEL_VERSION}" ]] && print_kv "新内核版本" "${INSTALLED_KERNEL_VERSION}"
    print_kv "下一步" "重启系统后生效"
    print_kv "验证命令" "$verify_hint"
    print_kv "回滚提示" "如启动异常，请在 GRUB 中选择旧内核"
    print_separator

    APPLY_GUIDANCE_SHOWN=1
    return 0
}

# 全局变量：XanMod 安装方式
XANMOD_INSTALL_METHOD="auto"  # auto, apt, direct

# 检测 CPU 支持的 x86-64 微架构级别
detect_cpu_level() {
    local level="1"
    local cpuinfo
    cpuinfo=$(cat /proc/cpuinfo 2>/dev/null)
    
    if echo "$cpuinfo" | grep -q "avx512"; then
        level="4"
    elif echo "$cpuinfo" | grep -q "avx2"; then
        level="3"
    elif echo "$cpuinfo" | grep -q "sse4_2"; then
        level="2"
    fi
    
    echo "$level"
}

# 直接从 XanMod APT 池下载 deb 包（绕过 APT 索引）
#
# 安全说明:
#  - 全程 HTTPS,不再走明文 HTTP
#  - 解析 Packages 文件中的 SHA256 字段,下载后用 sha256sum -c 校验
#  - 校验失败硬拒绝,绝不进入 dpkg -i
#  - 我们没有验证 Release/InRelease 的签名,因此 SHA256 的信任根仍是 TLS;
#    但相比之前(零校验)是质的提升。完整签名校验请走 APT 路径,APT 会做。
download_xanmod_direct() {
    local cpu_level
    cpu_level=$(detect_cpu_level)
    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/bbr3-xanmod-XXXXXX) || {
        print_error "无法创建临时目录"
        return 1
    }

    print_step "直接下载 XanMod 内核包..."
    print_info "CPU 微架构级别: x64v${cpu_level}"

    # 从 APT 源的 Packages 文件获取包信息(HTTPS)
    local pkg_list_url="https://deb.xanmod.org/dists/releases/main/binary-amd64/Packages.gz"
    local pkg_list

    print_info "获取包列表..."
    pkg_list=$(curl -fsSL --connect-timeout 15 --max-time 60 "$pkg_list_url" 2>/dev/null | gunzip 2>/dev/null)

    if [[ -z "$pkg_list" ]]; then
        pkg_list_url="https://deb.xanmod.org/dists/releases/main/binary-amd64/Packages"
        pkg_list=$(curl -fsSL --connect-timeout 15 --max-time 60 "$pkg_list_url" 2>/dev/null)
    fi

    if [[ -z "$pkg_list" ]]; then
        print_warn "无法获取包列表"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    # 查找匹配的内核包(同时获取 Filename 和 SHA256)
    local pkg_filename="" pkg_sha256="" pkg_name=""

    parse_xanmod_pkg() {
        local pkg="$1"
        # awk 一次性提取 Filename 和 SHA256(同一个 stanza 内)
        echo "$pkg_list" | awk -v pkg="$pkg" '
            /^Package:/ { in_pkg = ($2 == pkg) }
            in_pkg && /^Filename:/ { fn = $2 }
            in_pkg && /^SHA256:/  { sh = $2 }
            in_pkg && /^$/ {
                if (fn != "" && sh != "") { print fn "|" sh; exit }
                in_pkg = 0
            }
            END { if (in_pkg && fn != "" && sh != "") print fn "|" sh }
        '
    }

    local parsed
    for try_level in $cpu_level 3 2 1; do
        pkg_name="linux-xanmod-x64v${try_level}"
        parsed=$(parse_xanmod_pkg "$pkg_name")
        if [[ -n "$parsed" ]]; then
            pkg_filename="${parsed%|*}"
            pkg_sha256="${parsed#*|}"
            break
        fi
    done

    if [[ -z "$pkg_filename" ]]; then
        for pkg_name in "linux-xanmod-edge" "linux-xanmod-lts" "linux-xanmod"; do
            parsed=$(parse_xanmod_pkg "$pkg_name")
            if [[ -n "$parsed" ]]; then
                pkg_filename="${parsed%|*}"
                pkg_sha256="${parsed#*|}"
                break
            fi
        done
    fi

    if [[ -z "$pkg_filename" || -z "$pkg_sha256" ]]; then
        print_warn "未找到合适的内核包或缺少 SHA256 校验值"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    # SHA256 必须是 64 位十六进制
    if [[ ! "$pkg_sha256" =~ ^[a-fA-F0-9]{64}$ ]]; then
        print_error "Packages 文件返回的 SHA256 格式异常: $pkg_sha256"
        rm -rf -- "$tmp_dir"
        return 1
    fi

    print_info "找到内核包: ${pkg_name}"
    print_info "预期 SHA256: ${pkg_sha256}"

    local pkg_url="https://deb.xanmod.org/${pkg_filename}"
    local deb_file="${tmp_dir}/$(basename "$pkg_filename")"

    print_info "下载: $(basename "$pkg_filename")"
    print_info "文件较大（约 100-200MB），请耐心等待..."

    # 使用 wget 或 curl 下载
    if command -v wget >/dev/null 2>&1; then
        if ! wget --progress=bar:force -O "$deb_file" "$pkg_url"; then
            print_error "下载失败"
            rm -rf -- "$tmp_dir"
            return 1
        fi
    else
        if ! curl -fL --progress-bar --max-time 1800 -o "$deb_file" "$pkg_url"; then
            print_error "下载失败"
            rm -rf -- "$tmp_dir"
            return 1
        fi
    fi

    print_success "下载完成"

    # SHA256 校验 - 失败硬拒绝
    print_step "校验 SHA256..."
    if ! command -v sha256sum >/dev/null 2>&1; then
        print_error "未找到 sha256sum 命令,无法校验 .deb 完整性,拒绝安装"
        rm -rf -- "$tmp_dir"
        return 1
    fi
    local actual_sha256
    actual_sha256=$(sha256sum -- "$deb_file" 2>/dev/null | awk '{print $1}')
    if [[ "$actual_sha256" != "$pkg_sha256" ]]; then
        print_error "SHA256 校验失败! 下载文件可能被篡改或损坏"
        print_error "  预期: $pkg_sha256"
        print_error "  实际: $actual_sha256"
        rm -rf -- "$tmp_dir"
        return 1
    fi
    print_success "SHA256 校验通过"

    # 安装 deb 包
    print_step "安装内核包..."
    if ! dpkg -i "$deb_file"; then
        print_warn "dpkg 安装失败，尝试修复依赖..."
        if ! apt-get install -f -y; then
            print_error "依赖修复失败"
            rm -rf -- "$tmp_dir"
            return 1
        fi
        if ! dpkg -i "$deb_file"; then
            print_error "内核包安装失败"
            rm -rf -- "$tmp_dir"
            return 1
        fi
    fi
    print_success "内核包安装成功"
    apt-get install -f -y 2>/dev/null || true
    rm -rf -- "$tmp_dir"
    return 0
}

# 测试 XanMod APT 源速度
test_xanmod_apt_speed() {
    local test_url="https://deb.xanmod.org/gpg.key"
    local start_time end_time elapsed
    
    start_time=$(date +%s%N)
    if curl -fsSL --connect-timeout 5 --max-time 10 "$test_url" >/dev/null 2>&1; then
        end_time=$(date +%s%N)
        elapsed=$(( (end_time - start_time) / 1000000 ))  # 毫秒
        echo "$elapsed"
        return 0
    fi
    
    echo "9999"
    return 1
}

# 选择最佳 XanMod 下载方式
select_xanmod_download_method() {
    print_step "检测最佳下载方式..."
    
    # 测试官方 APT 源速度
    local apt_speed
    apt_speed=$(test_xanmod_apt_speed)
    print_info "XanMod APT 源响应时间: ${apt_speed}ms"
    
    # 如果是国外环境且 APT 源响应较慢，使用直接下载
    if [[ $USE_CHINA_MIRROR -eq 0 ]] && [[ $apt_speed -gt 2000 ]]; then
        print_info "国外环境检测到 APT 源较慢，尝试直接下载..."
        XANMOD_INSTALL_METHOD="direct"
        return 0
    fi
    
    # 如果 APT 源响应很慢（超过 5 秒）
    if [[ $apt_speed -gt 5000 ]]; then
        print_warn "XanMod APT 源响应较慢"
        
        if [[ $NON_INTERACTIVE -eq 0 ]]; then
            echo
            print_info "请选择下载方式："
            echo "  1) 直接下载 deb 包（推荐，可能更快）"
            echo "  2) 使用 APT 源安装（标准方式）"
            echo "  3) 取消安装"
            echo
            read_choice "请选择" 3 "1"
            
            case "$MENU_CHOICE" in
                1)
                    XANMOD_INSTALL_METHOD="direct"
                    ;;
                2)
                    XANMOD_INSTALL_METHOD="apt"
                    ;;
                3)
                    return 1
                    ;;
            esac
        else
            # 非交互模式，使用直接下载
            XANMOD_INSTALL_METHOD="direct"
        fi
    else
        XANMOD_INSTALL_METHOD="apt"
    fi
    
    return 0
}

# XanMod 内核安装核心逻辑（内部函数）
_install_kernel_xanmod_core() {
    case "$DIST_ID" in
        debian|ubuntu)
            # 检测最佳下载方式
            select_xanmod_download_method || return 1
            
            # 安装依赖
            if ! apt_update_cached; then
                print_warn "软件包缓存更新失败，尝试继续安装依赖"
            fi
            apt-get install -y -qq curl gnupg
            
            # 如果选择直接下载方式
            if [[ "$XANMOD_INSTALL_METHOD" == "direct" ]]; then
                print_info "使用直接下载方式安装..."
                if download_xanmod_direct; then
                    return 0
                else
                    print_warn "直接下载失败，回退到 APT 方式..."
                    XANMOD_INSTALL_METHOD="apt"
                fi
            fi
            
            # APT 方式安装
            print_step "添加 XanMod APT 源..."

            # 添加 GPG 密钥
            #
            # 安全说明:
            #  - 仅使用 XanMod 官方域名,先尝试 archive.key (官方文档推荐),失败回退 gpg.key
            #  - 移除 raw.githubusercontent.com 备用源: 该 URL 没有理由是规范来源,
            #    而且 xanmod/linux 仓库的任何 commit 者都能改它,扩大攻击面
            #  - 下载后用 fingerprint 比对硬校验,失败硬拒绝
            #  - fingerprint 是从 dl.xanmod.org/archive.key 直接读取并固化(2026-04-14 时点)
            #    UID: XanMod Kernel <kernel@xanmod.org>
            #    如 XanMod 项目轮换密钥,需更新此常量(可设环境变量 XANMOD_GPG_FINGERPRINT 临时覆盖)
            local -a gpg_urls=(
                "https://dl.xanmod.org/archive.key"
                "https://dl.xanmod.org/gpg.key"
            )
            local XANMOD_GPG_FINGERPRINT="${XANMOD_GPG_FINGERPRINT:-D38D7D1DA1349567ADED882D86F7D09EE734E623}"
            local keyring="/usr/share/keyrings/xanmod-archive-keyring.gpg"
            local gpg_tmp
            gpg_tmp=$(mktemp /tmp/bbr3-xanmod-key-XXXXXX.asc) || {
                print_error "无法创建 GPG 临时文件"
                return 1
            }

            local gpg_downloaded=0
            for gpg_url in "${gpg_urls[@]}"; do
                print_info "尝试从 ${gpg_url} 获取 GPG 密钥..."
                if curl -fsSL --connect-timeout 10 --max-time 30 "$gpg_url" -o "$gpg_tmp"; then
                    gpg_downloaded=1
                    break
                fi
            done

            if [[ $gpg_downloaded -eq 0 ]]; then
                print_error "无法获取 XanMod GPG 密钥"
                rm -f -- "$gpg_tmp"
                return 1
            fi

            # 校验 fingerprint
            local actual_fp
            actual_fp=$(gpg --show-keys --with-fingerprint --with-colons "$gpg_tmp" 2>/dev/null \
                | awk -F: '/^fpr:/ {print $10; exit}')
            if [[ -z "$actual_fp" ]]; then
                print_error "无法从下载的密钥中提取 fingerprint"
                rm -f -- "$gpg_tmp"
                return 1
            fi
            if [[ "$actual_fp" != "$XANMOD_GPG_FINGERPRINT" ]]; then
                print_error "XanMod GPG fingerprint 不匹配! 拒绝信任此密钥"
                print_error "  预期: $XANMOD_GPG_FINGERPRINT"
                print_error "  实际: $actual_fp"
                print_error "  如果 XanMod 项目轮换了密钥,请到 https://xanmod.org/ 确认"
                print_error "  并更新脚本中的 XANMOD_GPG_FINGERPRINT 常量"
                rm -f -- "$gpg_tmp"
                return 1
            fi
            print_success "GPG fingerprint 校验通过"

            # 转换为 keyring 格式
            if ! gpg --dearmor < "$gpg_tmp" > "$keyring" 2>/dev/null; then
                print_error "GPG --dearmor 失败"
                rm -f -- "$gpg_tmp"
                return 1
            fi
            rm -f -- "$gpg_tmp"
            chmod 0644 "$keyring"

            # 添加源 (HTTPS,不再使用 http)
            local repo_url="https://deb.xanmod.org"
            echo "deb [signed-by=${keyring}] ${repo_url} releases main" > /etc/apt/sources.list.d/xanmod.list
            
            # 更新源（带重试和验证）
            print_step "更新 APT 源..."
            local retry_count=0
            local max_retries=3
            local update_success=0
            
            while [[ $retry_count -lt $max_retries ]]; do
                # 执行 apt-get update 并正确检测返回值
                if apt-get update -o Dir::Etc::sourcelist="/etc/apt/sources.list.d/xanmod.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>&1; then
                    # 验证 XanMod 包是否可用
                    if apt-cache show linux-xanmod-x64v3 >/dev/null 2>&1 || \
                       apt-cache show linux-xanmod-x64v2 >/dev/null 2>&1 || \
                       apt-cache show linux-xanmod >/dev/null 2>&1 || \
                       apt-cache show linux-xanmod-edge >/dev/null 2>&1; then
                        update_success=1
                        print_success "XanMod 源更新成功，包已可用"
                        break
                    else
                        print_warn "源已更新但未找到 XanMod 包，尝试完整更新..."
                        # 尝试完整更新所有源
                        apt-get update 2>&1 || true
                        sleep 2
                    fi
                fi
                ((++retry_count))
                print_warn "更新源失败，重试 ${retry_count}/${max_retries}..."
                sleep 3
            done
            
            # 如果仍未成功，进行最后一次完整更新
            if [[ $update_success -eq 0 ]]; then
                print_warn "尝试最后一次完整 APT 更新..."
                apt-get update 2>&1 || true
                sleep 2
                # 再次验证
                if apt-cache show linux-xanmod-x64v3 >/dev/null 2>&1 || \
                   apt-cache show linux-xanmod >/dev/null 2>&1; then
                    update_success=1
                    print_success "XanMod 包已可用"
                else
                    print_error "无法获取 XanMod 包列表，请检查网络连接"
                    print_info "提示：可尝试手动运行 'apt update' 后重试"
                    return 1
                fi
            fi
            
            # 检测 CPU 支持的指令集级别
            local cpu_level="1"
            if grep -q "avx512" /proc/cpuinfo 2>/dev/null; then
                cpu_level="4"
            elif grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
                cpu_level="3"
            elif grep -q "avx" /proc/cpuinfo 2>/dev/null; then
                cpu_level="2"
            fi
            
            print_info "检测到 CPU 支持级别: x64v${cpu_level}"
            
            # 根据 CPU 级别选择合适的内核包
            local candidates=()
            case "$cpu_level" in
                4)
                    candidates=("linux-xanmod-x64v4" "linux-xanmod-x64v3" "linux-xanmod-x64v2" "linux-xanmod")
                    ;;
                3)
                    candidates=("linux-xanmod-x64v3" "linux-xanmod-x64v2" "linux-xanmod")
                    ;;
                2)
                    candidates=("linux-xanmod-x64v2" "linux-xanmod")
                    ;;
                *)
                    candidates=("linux-xanmod")
                    ;;
            esac
            
            # 添加 edge 和 lts 变体
            candidates+=("linux-xanmod-edge" "linux-xanmod-lts")
            
            # ========== 安装前环境检查 ==========
            print_step "检查系统环境..."
            
            # 1. 修复可能存在的依赖问题
            print_info "检查并修复依赖关系..."
            apt-get install -f -y 2>/dev/null || true
            
            # 2. 检查是否有被 hold 的包
            local held_pkgs
            held_pkgs=$(dpkg --get-selections | grep -E 'hold$' | awk '{print $1}' || true)
            if [[ -n "$held_pkgs" ]]; then
                print_warn "发现被锁定的软件包: ${held_pkgs}"
                print_info "这可能不影响内核安装，继续..."
            fi
            
            # 3. 检查是否有未完成的 dpkg 配置
            if [[ -f /var/lib/dpkg/lock-frontend ]]; then
                # 检查是否有其他 apt 进程
                if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
                    print_warn "检测到其他包管理进程正在运行，等待..."
                    local wait_count=0
                    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && [[ $wait_count -lt 30 ]]; do
                        sleep 2
                        ((++wait_count))
                    done
                fi
            fi
            
            # 4. 配置未完成的包
            dpkg --configure -a 2>/dev/null || true
            
            # 5. 检查可升级的关键依赖
            print_info "检查系统依赖更新..."
            if confirm "是否执行系统升级（apt-get upgrade）？可能升级大量包" "n"; then
                apt-get upgrade -y --with-new-pkgs 2>/dev/null || true
            else
                print_warn "已跳过系统升级（如需可手动执行 apt-get upgrade）"
            fi
            
            print_success "环境检查完成"
            
            # ========== 开始安装内核 ==========
            print_step "安装 XanMod 内核..."
            print_info "内核包较大（约 100-200MB），下载可能需要几分钟..."
            local installed=0
            
            for pkg in "${candidates[@]}"; do
                if apt-cache show "$pkg" >/dev/null 2>&1; then
                    print_info "尝试安装 ${pkg}..."
                    
                    # 使用 apt-get 安装，显示进度
                    # 添加 -o 选项优化下载
                    if apt-get install -y \
                        -o Acquire::http::Timeout=60 \
                        -o Acquire::https::Timeout=60 \
                        -o Acquire::Retries=3 \
                        "$pkg"; then
                        installed=1
                        print_success "成功安装 ${pkg}"
                        break
                    else
                        print_warn "安装 ${pkg} 失败，尝试下一个..."
                    fi
                fi
            done
            
            if [[ $installed -eq 0 ]]; then
                print_error "未找到可安装的 XanMod 内核包"
                return 1
            fi
            ;;
        *)
            print_error "XanMod 仅支持 Debian/Ubuntu 系统"
            return 1
            ;;
    esac
    
    return 0
}

# 安装 XanMod 内核（带验证和回滚）
install_kernel_xanmod() {
    print_header "安装 XanMod 内核"
    
    kernel_precheck "XanMod" || return 1
    
    # 使用安全安装包装函数
    if safe_kernel_install "XanMod" _install_kernel_xanmod_core; then
        return 0
    else
        return 1
    fi
}

# Liquorix 内核安装核心逻辑（内部函数）
_install_kernel_liquorix_core() {
    case "$DIST_ID" in
        ubuntu)
            print_step "添加 Liquorix PPA..."
            if ! apt_update_cached; then
                print_warn "软件包缓存更新失败，尝试继续安装"
            fi
            if ! apt-get install -y -qq software-properties-common; then
                print_error "无法安装 software-properties-common"
                return 1
            fi
            if ! add-apt-repository -y ppa:damentz/liquorix; then
                print_error "添加 Liquorix PPA 失败"
                return 1
            fi
            if ! apt_update_cached 1; then
                print_warn "软件包缓存更新失败，可能影响 Liquorix 安装"
            fi

            print_step "安装 Liquorix 内核..."
            if ! apt-get install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64; then
                print_error "Liquorix 内核包安装失败"
                return 1
            fi
            ;;
        debian)
            # 旧实现是 curl -s ... | bash, -s 还吞错。改成下载到临时文件后语法预检再执行,
            # 失败可定位、Ctrl-C 不会留半个脚本。注意: 此安装器仍由 liquorix.net 提供,
            # 我们没有签名校验能力,这是已知的供应链信任风险。
            print_step "下载 Liquorix 安装器..."
            local installer_tmp
            installer_tmp=$(mktemp /tmp/bbr3-liquorix-XXXXXX.sh) || {
                print_error "无法创建临时文件"
                return 1
            }
            if ! curl -fsSL --max-time 60 'https://liquorix.net/install-liquorix.sh' -o "$installer_tmp"; then
                rm -f -- "$installer_tmp"
                print_error "下载 Liquorix 安装器失败"
                return 1
            fi
            # 基本完整性: 必须以 shebang 开头,且能通过 bash -n 语法检查
            if ! head -n1 "$installer_tmp" | grep -q '^#!'; then
                rm -f -- "$installer_tmp"
                print_error "下载内容不是有效脚本(缺少 shebang)"
                return 1
            fi
            if ! bash -n "$installer_tmp"; then
                rm -f -- "$installer_tmp"
                print_error "下载的安装器语法错误,可能损坏或被篡改"
                return 1
            fi
            print_warn "Liquorix 安装器无签名校验,即将以 root 执行,继续..."
            print_step "安装 Liquorix 内核..."
            if ! bash "$installer_tmp"; then
                rm -f -- "$installer_tmp"
                print_error "Liquorix 安装器执行失败"
                return 1
            fi
            rm -f -- "$installer_tmp"
            ;;
        *)
            print_error "Liquorix 仅支持 Debian/Ubuntu 系统"
            return 1
            ;;
    esac

    return 0
}

# 安装 Liquorix 内核（带验证和回滚）
install_kernel_liquorix() {
    print_header "安装 Liquorix 内核"
    
    kernel_precheck "Liquorix" || return 1
    
    # 使用安全安装包装函数
    if safe_kernel_install "Liquorix" _install_kernel_liquorix_core; then
        return 0
    else
        return 1
    fi
}

# ELRepo 内核安装核心逻辑（内部函数）
_install_kernel_elrepo_core() {
    case "$DIST_ID" in
        centos|rhel|rocky|almalinux)
            local rhel_ver="${DIST_VER%%.*}"
            local pkg_mgr=yum
            command -v dnf >/dev/null 2>&1 && pkg_mgr=dnf

            print_step "更新软件包缓存..."
            "$pkg_mgr" makecache -q || true  # cache 失败不致命

            print_step "启用 ELRepo..."
            local elrepo_url="https://www.elrepo.org/elrepo-release-${rhel_ver}.el${rhel_ver}.elrepo.noarch.rpm"
            # 已安装则跳过即可,但安装失败必须报错(否则 enablerepo=elrepo-kernel 会直接失败)
            if ! "$pkg_mgr" install -y "$elrepo_url"; then
                if ! rpm -q elrepo-release >/dev/null 2>&1; then
                    print_error "无法安装 elrepo-release,请检查网络或 GPG 密钥"
                    return 1
                fi
                print_warn "elrepo-release 已安装,继续"
            fi

            print_step "安装 kernel-ml..."
            if ! "$pkg_mgr" --enablerepo=elrepo-kernel install -y kernel-ml; then
                print_error "kernel-ml 安装失败"
                return 1
            fi
            ;;
        *)
            print_error "ELRepo 仅支持 RHEL/CentOS/Rocky/AlmaLinux 系统"
            return 1
            ;;
    esac

    return 0
}

# 安装 ELRepo 内核（带验证和回滚）
install_kernel_elrepo() {
    print_header "安装 ELRepo 内核"
    
    kernel_precheck "ELRepo" || return 1
    
    # 使用安全安装包装函数
    if safe_kernel_install "ELRepo" _install_kernel_elrepo_core; then
        return 0
    else
        return 1
    fi
}

# HWE 内核安装核心逻辑（内部函数）
_install_kernel_hwe_core() {
    print_step "更新软件包列表..."
    if ! apt_update_cached; then
        print_warn "软件包缓存更新失败，尝试继续安装"
    fi

    print_step "安装 HWE 内核..."

    local hwe_pkg=""
    case "$DIST_VER" in
        16.04*) hwe_pkg="linux-generic-hwe-16.04" ;;
        18.04*) hwe_pkg="linux-generic-hwe-18.04" ;;
        20.04*) hwe_pkg="linux-generic-hwe-20.04" ;;
        22.04*) hwe_pkg="linux-generic-hwe-22.04" ;;
        *)
            print_error "当前 Ubuntu 版本(${DIST_VER})不支持 HWE 内核"
            return 1
            ;;
    esac

    if ! apt-get install -y "$hwe_pkg"; then
        print_error "HWE 内核包安装失败: $hwe_pkg"
        return 1
    fi

    return 0
}

# 安装 HWE 内核（带验证和回滚）
install_kernel_hwe() {
    print_header "安装 HWE 内核"
    
    if [[ "$DIST_ID" != "ubuntu" ]]; then
        print_error "HWE 内核仅支持 Ubuntu 系统"
        return 1
    fi
    
    kernel_precheck "HWE" || return 1
    
    # 使用安全安装包装函数
    if safe_kernel_install "HWE" _install_kernel_hwe_core; then
        return 0
    else
        return 1
    fi
}

# 重启提示
prompt_reboot() {
    echo
    if confirm "是否现在重启系统？" "n"; then
        print_info "系统将在 5 秒后重启..."
        sleep 5
        reboot
    else
        print_warn "请记得稍后重启系统以使用新内核"
    fi
}


#===============================================================================
# 状态显示
#===============================================================================

# 显示当前状态
show_status() {
    # 确保系统信息已检测
    [[ -z "$DIST_ID" ]] && detect_os
    [[ -z "$ARCH_ID" ]] && detect_arch
    [[ -z "$VIRT_TYPE" ]] && detect_virt
    
    print_header "系统状态"
    
    # 系统信息
    echo -e "${BOLD}系统信息${NC}"
    print_kv "操作系统" "$(get_os_pretty_name)"
    print_kv "内核版本" "$(uname -r)"
    print_kv "CPU 架构" "$ARCH_ID"
    print_kv "虚拟化" "${VIRT_TYPE:-未知}"
    echo
    
    # BBR 状态
    echo -e "${BOLD}BBR 状态${NC}"
    local current_algo current_qdisc available_algos
    current_algo=$(get_current_algo)
    current_qdisc=$(get_current_qdisc)
    available_algos=$(detect_available_algos)
    
    print_kv "当前算法" "$current_algo"
    print_kv "当前队列" "$current_qdisc"
    print_kv "可用算法" "$available_algos"
    echo
    
    # BBR3 检测
    echo -e "${BOLD}BBR3 检测${NC}"
    local kver bbr3_available bbr3_active
    kver=$(uname -r | sed 's/[^0-9.].*$//')
    
    if algo_supported "bbr3"; then
        bbr3_available="${GREEN}是${NC}"
    else
        bbr3_available="${RED}否${NC}"
    fi
    
    if [[ "$current_algo" == "bbr3" ]] || { [[ "$current_algo" == "bbr" ]] && version_ge "$kver" "6.9.0"; }; then
        bbr3_active="${GREEN}是${NC}"
    else
        bbr3_active="${RED}否${NC}"
    fi
    
    echo -e "  BBR3 可用    : ${bbr3_available}"
    echo -e "  BBR3 已启用  : ${bbr3_active}"
    print_kv "内核版本" "$kver"
    
    if version_ge "$kver" "6.9.0"; then
        echo -e "  主线 BBRv3   : ${GREEN}是${NC} (>= 6.9.0)"
    else
        echo -e "  主线 BBRv3   : ${YELLOW}否${NC} (需要 >= 6.9.0)"
    fi
    echo
    
    # 推荐
    echo -e "${BOLD}推荐配置${NC}"
    local recommended
    recommended=$(suggest_best_algo)
    print_kv "推荐算法" "$recommended"
    print_kv "推荐队列" "fq"
    
    # 场景模式推荐
    recommend_scene_mode
    print_kv "推荐场景" "$(get_scene_name "$SCENE_RECOMMENDED")"
    echo -e "  ${DIM}$(get_scene_description "$SCENE_RECOMMENDED")${NC}"
    echo
    
    # 备份信息
    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_count
        backup_count=$(ls -1 "${BACKUP_DIR}/"*.bak 2>/dev/null | wc -l)
        backup_count=${backup_count:-0}
        backup_count=${backup_count// /}
        if [[ $backup_count -gt 0 ]]; then
            echo -e "${BOLD}备份信息${NC}"
            print_kv "备份数量" "$backup_count"
            echo
        fi
    fi
    
    # 配置文件
    if [[ -f "$SYSCTL_FILE" ]]; then
        echo -e "${BOLD}当前配置 (${SYSCTL_FILE})${NC}"
        grep -E '^net\.(core|ipv4)' "$SYSCTL_FILE" 2>/dev/null | head -5 | while read -r line; do
            echo "  $line"
        done
        echo
    fi
}

#===============================================================================
# 交互式菜单
#===============================================================================

# 主菜单
show_main_menu() {
    # 首次进入时检测并推荐场景模式
    recommend_scene_mode
    
    while true; do
        print_header "BBR3 一键脚本"
        
        echo -e "${DIM}当前: $(get_current_algo) / $(get_current_qdisc) | 推荐: $(suggest_best_algo)${NC}"
        echo -e "${DIM}推荐场景: $(get_scene_name "$SCENE_RECOMMENDED")${NC}"
        echo
        print_menu "请选择操作" \
            "代理智能调优 (推荐翻墙用户！含一键自动优化) ⭐" \
            "安装新内核 (获取BBR3支持)" \
            "验证优化状态 (检测优化是否生效)" \
            "查看当前状态" \
            "备份/恢复配置" \
            "时间自动优化 (晚高峰自动切换激进模式)" \
            "卸载配置" \
            "安装快捷命令 bbr3" \
            "更新脚本 (从 GitHub 获取最新版本)" \
            "PVE Tools 一键脚本"
        
        read_choice "请选择" 10
        
        case "$MENU_CHOICE" in
            0) 
                print_info "感谢使用，再见！"
                exit 0
                ;;
            1) scene_config_menu ;;
            2) show_kernel_menu ;;
            3) show_verification_menu ;;
            4) show_status ;;
            5) show_backup_menu ;;
            6) setup_time_based_optimization ;;
            7) do_uninstall ;;
            8) install_shortcut ;;
            9) update_script ;;
            10) run_pvetools ;;
        esac
        
        echo
        if [[ $NON_INTERACTIVE -eq 0 ]]; then
            read -r -p "按 Enter 继续..."
        fi
    done
}

# 内核安装菜单
show_kernel_menu() {
    print_header "安装新内核"
    
    if ! is_kernel_install_supported; then
        print_warn "当前环境不支持安装第三方内核"
        print_info "原因: 架构=${ARCH_ID}, 虚拟化=${VIRT_TYPE}"
        return
    fi
    
    echo -e "${DIM}安装新内核可获得 BBR2/BBR3 支持${NC}"
    echo
    
    local menu_items=()
    
    case "$DIST_ID" in
        debian|ubuntu)
            menu_items+=("XanMod (推荐，支持 BBR3)")
            menu_items+=("Liquorix (桌面优化)")
            if [[ "$DIST_ID" == "ubuntu" ]] && [[ "$DIST_VER" =~ ^(16|18|20)\. ]]; then
                menu_items+=("HWE 内核 (官方硬件支持)")
            fi
            ;;
        centos|rhel|rocky|almalinux)
            menu_items+=("ELRepo kernel-ml (最新主线)")
            ;;
    esac
    
    if [[ ${#menu_items[@]} -eq 0 ]]; then
        print_warn "当前系统没有可用的内核选项"
        return
    fi
    
    print_menu "选择要安装的内核" "${menu_items[@]}"
    
    read_choice "请选择" ${#menu_items[@]}
    
    [[ "$MENU_CHOICE" == "0" ]] && return
    
    # 二次确认
    echo
    print_warn "安装新内核是一个重要操作，可能影响系统启动"
    if ! confirm "确定要继续吗？" "n"; then
        print_info "已取消"
        return
    fi
    
    case "$DIST_ID" in
        debian|ubuntu)
            case "$MENU_CHOICE" in
                1) install_kernel_xanmod && prompt_reboot ;;
                2) install_kernel_liquorix && prompt_reboot ;;
                3) install_kernel_hwe && prompt_reboot ;;
            esac
            ;;
        centos|rhel|rocky|almalinux)
            install_kernel_elrepo && prompt_reboot
            ;;
    esac
}

# 备份/恢复菜单
show_backup_menu() {
    print_header "备份/恢复配置"
    
    print_menu "选择操作" \
        "查看备份列表" \
        "创建新备份" \
        "恢复备份"
    
    read_choice "请选择" 3
    
    case "$MENU_CHOICE" in
        0) return ;;
        1) list_backups ;;
        2) backup_config ;;
        3) restore_config ;;
    esac
}

# 自动优化
do_auto_tune() {
    print_header "自动优化配置"
    
    echo -e "${DIM}根据网络 RTT 和带宽自动计算最佳缓冲区大小${NC}"
    echo -e "${DIM}注意: 此功能与「场景配置」互斥，后执行的会覆盖前者${NC}"
    echo -e "${DIM}如果是 VPS 代理用途，建议使用「场景配置 > 代理模式」${NC}"
    echo
    
    auto_tune
    
    echo
    if confirm "是否应用以上配置？" "y"; then
        if ! write_sysctl "$CHOSEN_ALGO" "$CHOSEN_QDISC"; then
            print_error "写入配置失败,中止应用"
            return 1
        fi
        apply_sysctl
        apply_qdisc_runtime "$CHOSEN_QDISC"
        print_success "自动优化配置已应用"
    fi
}

# 卸载配置
do_uninstall() {
    print_header "卸载配置"
    
    if [[ ! -f "$SYSCTL_FILE" ]]; then
        print_info "没有找到配置文件，无需卸载"
        return
    fi
    
    print_warn "这将删除 BBR 配置并恢复系统默认设置"
    
    if ! confirm "确定要卸载吗？" "n"; then
        print_info "已取消"
        return
    fi
    
    # 备份后删除
    backup_config
    rm -f "$SYSCTL_FILE"
    
    # 重新加载系统配置
    sysctl --system >/dev/null 2>&1 || true
    
    print_success "配置已卸载"
    print_info "系统将使用默认的拥塞控制算法"
}

# 安装快捷命令
install_shortcut() {
    print_header "安装快捷命令"
    
    local shortcut_path="/usr/local/bin/bbr3"
    local script_url="${GITHUB_RAW}/easybbr3.sh"
    
    echo -e "${DIM}安装后可直接使用 'bbr3' 命令运行此脚本${NC}"
    echo
    
    if [[ -f "$shortcut_path" ]]; then
        print_info "快捷命令已存在: $shortcut_path"
        if ! confirm "是否覆盖更新？" "y"; then
            return
        fi
    fi
    
    print_step "下载脚本到 ${shortcut_path}..."
    
    # 下载脚本
    if curl -fsSL "$script_url" -o "$shortcut_path" 2>/dev/null; then
        chmod +x "$shortcut_path"
        print_success "快捷命令安装成功！"
        echo
        echo -e "  使用方法: ${GREEN}bbr3${NC}"
        echo -e "  查看帮助: ${GREEN}bbr3 --help${NC}"
        echo -e "  查看状态: ${GREEN}bbr3 --status${NC}"
    elif wget -qO "$shortcut_path" "$script_url" 2>/dev/null; then
        chmod +x "$shortcut_path"
        print_success "快捷命令安装成功！"
        echo
        echo -e "  使用方法: ${GREEN}bbr3${NC}"
        echo -e "  查看帮助: ${GREEN}bbr3 --help${NC}"
        echo -e "  查看状态: ${GREEN}bbr3 --status${NC}"
    else
        print_error "下载失败，请检查网络连接"
        return 1
    fi
}

# 时间自动优化 - 根据时段自动调整参数
setup_time_based_optimization() {
    print_header "时间自动优化"
    
    echo -e "${DIM}根据时段自动调整网络参数，晚高峰使用激进配置${NC}"
    echo
    echo "  【时段设置】"
    echo "    晚高峰: 19:00 - 02:00 (激进模式)"
    echo "    非高峰: 其他时间 (标准模式)"
    echo
    echo "  【激进模式参数】"
    echo "    缓冲区: 128MB (翻倍)"
    echo "    SYN 队列: 131072 (翻倍)"
    echo "    somaxconn: 131072 (翻倍)"
    echo
    
    if ! confirm "是否启用时间自动优化？" "y"; then
        return
    fi
    
    # 创建高峰模式配置
    local peak_config="/etc/sysctl.d/99-bbr-peak.conf"
    local normal_config="/etc/sysctl.d/99-bbr-normal.conf"
    
    # 生成高峰模式配置
    cat > "$peak_config" << 'EOF'
# BBR3 晚高峰模式 (19:00-02:00)
# 自动生成，请勿手动修改

# 大缓冲区（128MB）
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 131072 134217728
net.ipv4.tcp_wmem = 4096 131072 134217728

# 高并发队列
net.core.somaxconn = 131072
net.ipv4.tcp_max_syn_backlog = 131072
net.core.netdev_max_backlog = 500000
EOF
    print_success "高峰模式配置已生成: $peak_config"
    
    # 生成标准模式配置
    cat > "$normal_config" << 'EOF'
# BBR3 标准模式 (非高峰时段)
# 自动生成，请勿手动修改

# 标准缓冲区（64MB）
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# 标准队列
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 250000
EOF
    print_success "标准模式配置已生成: $normal_config"
    
    # 创建切换脚本
    local switch_script="/usr/local/bin/bbr3-time-switch"
    cat > "$switch_script" << 'SCRIPT'
#!/bin/bash
# BBR3 时间自动切换脚本
HOUR=$(date +%H)
if [[ $HOUR -ge 19 || $HOUR -lt 2 ]]; then
    # 晚高峰模式 (19:00-02:00)
    sysctl -p /etc/sysctl.d/99-bbr-peak.conf >/dev/null 2>&1
    logger "BBR3: 切换到晚高峰模式"
else
    # 标准模式
    sysctl -p /etc/sysctl.d/99-bbr-normal.conf >/dev/null 2>&1
    logger "BBR3: 切换到标准模式"
fi
SCRIPT
    chmod +x "$switch_script"
    print_success "切换脚本已创建: $switch_script"
    
    # 添加 cron 任务
    local cron_job="0 * * * * $switch_script"
    if ! crontab -l 2>/dev/null | grep -q "bbr3-time-switch"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        print_success "Cron 任务已添加 (每小时检查一次)"
    else
        print_info "Cron 任务已存在"
    fi
    
    # 立即执行一次
    "$switch_script"
    
    echo
    print_success "时间自动优化已启用！"
    echo
    echo -e "  ${BOLD}管理命令:${NC}"
    echo "    查看日志: journalctl -t BBR3"
    echo "    手动切换: $switch_script"
    echo "    禁用: crontab -e 删除 bbr3-time-switch 行"
}

# 更新脚本
#
# 安全说明 (v2.1.1 起):
#  - 自更新默认禁用,因为我们目前没有签名校验机制(无 minisign/cosign/GPG)。
#    任何对 GitHub raw 端点的投毒(账号被盗、CDN 缓存污染、DNS 劫持)都会
#    立即变成所有运行 --update 的机器上的 root RCE。
#  - 如需 opt-in 更新,使用 ALLOW_UNVERIFIED_UPDATE=1 环境变量或
#    --allow-unverified-update CLI 参数。我们仍要求 SHA256 校验值(如有)。
#  - 推荐替代方案: 手动 wget 后 diff 并审阅,或等到 v2.2.0 引入签名机制。
update_script() {
    print_header "更新脚本"

    if [[ "${ALLOW_UNVERIFIED_UPDATE:-0}" != "1" ]]; then
        print_warn "自更新已禁用(原因: 缺少签名校验机制)"
        echo
        echo "  当前自更新无法验证下载内容的真实性,GitHub raw 端点被投毒"
        echo "  会立即变成 root RCE。在签名机制就位前我们拒绝默认开启此功能。"
        echo
        echo "  如需手动更新,推荐:"
        echo "    1) 浏览 https://github.com/xx2468171796/EasyBBR3/blob/main/easybbr3.sh"
        echo "       人工审阅后:"
        echo "    2) wget -O /tmp/easybbr3.new.sh \\"
        echo "       https://raw.githubusercontent.com/xx2468171796/EasyBBR3/main/easybbr3.sh"
        echo "    3) diff $0 /tmp/easybbr3.new.sh"
        echo "    4) sudo install -m 0755 /tmp/easybbr3.new.sh $0"
        echo
        echo "  如确认接受未签名更新风险,可使用:"
        echo "    ALLOW_UNVERIFIED_UPDATE=1 $0 --update"
        echo "    或: $0 --update --allow-unverified-update"
        return 1
    fi

    local current_script="$0"
    local tmp_script
    tmp_script=$(mktemp /tmp/bbr3-update-XXXXXX.sh) || {
        print_error "无法创建临时文件"
        return 1
    }

    print_warn "ALLOW_UNVERIFIED_UPDATE=1 已设置,将下载未签名更新"
    echo -e "${DIM}从 GitHub 下载最新版本...${NC}"
    echo

    # 下载最新版本
    if curl -fsSL --max-time 60 --max-filesize 10485760 "$SCRIPT_UPDATE_URL" -o "$tmp_script" 2>/dev/null; then
        :
    elif wget --timeout=60 -qO "$tmp_script" "$SCRIPT_UPDATE_URL" 2>/dev/null; then
        :
    else
        print_error "下载失败，请检查网络连接"
        rm -f -- "$tmp_script"
        return 1
    fi

    # 基本完整性校验
    if [[ ! -s "$tmp_script" ]]; then
        print_error "下载的文件为空"
        rm -f -- "$tmp_script"
        return 1
    fi
    if ! head -1 "$tmp_script" | grep -q "^#!"; then
        print_error "下载的文件无效(缺少 shebang)"
        rm -f -- "$tmp_script"
        return 1
    fi
    if ! /usr/bin/env bash -n "$tmp_script" 2>/dev/null; then
        print_error "下载的脚本语法错误,可能损坏或被篡改"
        rm -f -- "$tmp_script"
        return 1
    fi

    # 获取版本信息
    local new_version
    new_version=$(grep -m1 '^readonly SCRIPT_VERSION=' "$tmp_script" | cut -d'"' -f2)
    print_kv "当前版本" "$SCRIPT_VERSION"
    print_kv "最新版本" "${new_version:-未知}"
    echo

    if [[ -z "$new_version" ]]; then
        print_error "无法解析新版本号,中止更新"
        rm -f -- "$tmp_script"
        return 1
    fi

    # 拒绝降级
    if [[ "$new_version" == "$SCRIPT_VERSION" ]]; then
        print_info "已是最新版本，无需更新"
        rm -f -- "$tmp_script"
        return 0
    fi
    if ! version_gt "$new_version" "$SCRIPT_VERSION"; then
        print_error "拒绝更新: 远端版本 $new_version 不高于本地 $SCRIPT_VERSION (防止降级攻击)"
        rm -f -- "$tmp_script"
        return 1
    fi

    if ! confirm "是否更新到最新版本？" "y"; then
        rm -f -- "$tmp_script"
        return 0
    fi

    # 备份当前脚本
    if [[ -f "$current_script" ]]; then
        if ! cp -- "$current_script" "${current_script}.bak"; then
            print_error "备份当前脚本失败,中止更新"
            rm -f -- "$tmp_script"
            return 1
        fi
        print_info "已备份当前脚本到 ${current_script}.bak"
    fi

    # 原子替换
    chmod +x "$tmp_script"
    if ! mv -f -- "$tmp_script" "$current_script"; then
        print_error "替换脚本失败"
        rm -f -- "$tmp_script"
        return 1
    fi

    # 同时更新快捷命令（如果存在）
    if [[ -f /usr/local/bin/bbr3 ]]; then
        if cp -- "$current_script" /usr/local/bin/bbr3 && chmod +x /usr/local/bin/bbr3; then
            print_info "已同步更新快捷命令 bbr3"
        else
            print_warn "快捷命令 bbr3 同步失败,可手动 cp $current_script /usr/local/bin/bbr3"
        fi
    fi

    print_success "脚本更新成功！"
    echo
    print_info "请重新运行脚本以使用新版本"

    exit 0
}

# 卸载快捷命令
uninstall_shortcut() {
    local shortcut_path="/usr/local/bin/bbr3"
    
    if [[ ! -f "$shortcut_path" ]]; then
        print_info "快捷命令未安装"
        return
    fi
    
    if confirm "确定要卸载快捷命令 bbr3？" "n"; then
        rm -f "$shortcut_path"
        print_success "快捷命令已卸载"
    fi
}

# 运行 PVE Tools 脚本
run_pvetools() {
    print_header "PVE Tools 一键脚本"
    
    echo -e "${DIM}Proxmox VE 优化工具，支持换源、去订阅提示等功能${NC}"
    echo -e "${DIM}项目地址: https://github.com/xx2468171796/pvetools${NC}"
    echo
    
    if ! confirm "是否下载并运行 PVE Tools 脚本？" "n"; then
        return
    fi
    
    print_step "下载 PVE Tools 脚本..."
    
    local pve_script="/tmp/pvetools.sh"
    local pve_url="https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh"
    
    # 下载脚本
    if curl -fsSL "$pve_url" -o "$pve_script" 2>/dev/null; then
        chmod +x "$pve_script"
        print_success "下载成功，正在运行..."
        echo
        bash "$pve_script"
        rm -f "$pve_script"
    elif wget -qO "$pve_script" "$pve_url" 2>/dev/null; then
        chmod +x "$pve_script"
        print_success "下载成功，正在运行..."
        echo
        bash "$pve_script"
        rm -f "$pve_script"
    else
        print_error "下载失败，请检查网络连接"
        echo
        echo -e "手动运行命令："
        echo -e "${GREEN}wget https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh${NC}"
        echo -e "${GREEN}chmod +x pvetools.sh && ./pvetools.sh${NC}"
        return 1
    fi
}


#===============================================================================
# 帮助信息
#===============================================================================

usage() {
    cat << EOF
${BOLD}BBR3 一键脚本 v${SCRIPT_VERSION}${NC}

${BOLD}用法:${NC}
  sudo $SCRIPT_NAME [选项]
  wget -qO- ${GITHUB_RAW}/bbr.sh | sudo bash
  curl -fsSL ${GITHUB_RAW}/bbr.sh | sudo bash -s -- [选项]

${BOLD}选项:${NC}
  ${CYAN}--algo <name>${NC}           设置拥塞算法: bbr|bbr2|bbr3|cubic|reno
  ${CYAN}--qdisc <name>${NC}          设置队列规则: fq|fq_codel|fq_pie|cake [默认: fq]
  ${CYAN}--install-kernel <type>${NC} 安装新内核: xanmod|liquorix|elrepo|hwe
  ${CYAN}--apply${NC}                 立即应用配置
  ${CYAN}--no-apply${NC}              仅写入配置，不立即应用
  ${CYAN}--mirror <name>${NC}         指定镜像源: tsinghua|aliyun|ustc|auto [默认: auto]
  ${CYAN}--non-interactive${NC}       非交互模式
  ${CYAN}--status${NC}                显示当前状态
  ${CYAN}--auto${NC}                  自动检测并应用最优配置
  ${CYAN}--check-bbr3${NC}            检测 BBR3 是否启用
  ${CYAN}--uninstall${NC}             卸载配置
  ${CYAN}--install${NC}               安装快捷命令 bbr3 到 /usr/local/bin
  ${CYAN}--smart${NC}                 智能自动优化 (检测带宽/RTT/MTU 并应用最优配置)
  ${CYAN}--detect${NC}                仅检测服务器参数，不应用配置
  ${CYAN}--verify${NC}                验证优化效果
  ${CYAN}--health${NC}                健康评分检查
  ${CYAN}--proxy-tune${NC}            代理智能调优向导
  ${CYAN}--debug${NC}                 启用调试模式
  ${CYAN}--update${NC}                更新脚本(默认禁用,需 --allow-unverified-update)
  ${CYAN}--allow-unverified-update${NC}  显式允许未签名的自更新(风险自负)
  ${CYAN}--version, -v${NC}           显示版本号
  ${CYAN}--help, -h${NC}              显示帮助

${BOLD}示例:${NC}
  # 交互式运行
  sudo $SCRIPT_NAME

  # 直接启用 BBR3
  sudo $SCRIPT_NAME --algo bbr3 --apply

  # 自动优化
  sudo $SCRIPT_NAME --auto

  # 安装 XanMod 内核
  sudo $SCRIPT_NAME --install-kernel xanmod

  # 查看状态
  sudo $SCRIPT_NAME --status

  # 使用国内镜像
  sudo $SCRIPT_NAME --mirror tsinghua --install-kernel xanmod

${BOLD}支持的系统:${NC}
  • Debian: 10 (Buster), 11 (Bullseye), 12 (Bookworm), 13 (Trixie)
  • Ubuntu: 16.04, 18.04, 20.04, 22.04, 24.04
  • RHEL/CentOS/Rocky/AlmaLinux: 7, 8, 9

${BOLD}注意:${NC}
  • BBR2/BBR3 需要较新内核支持，脚本会自动检测
  • 安装新内核后需要重启才能生效
  • 容器环境 (OpenVZ/LXC/Docker) 无法更换内核
  • 第三方内核仅支持 x86_64/amd64 架构

${BOLD}作者信息:${NC}
  作者: 孤独制作
  电报群: https://t.me/+RZMe7fnvvUg1OWJl

${BOLD}项目地址:${NC}
  ${GITHUB_URL}

${BOLD}其他工具:${NC}
  PVE Tools 一键脚本:
  wget https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh
  chmod +x pvetools.sh && ./pvetools.sh

EOF
}

#===============================================================================
# 主函数
#===============================================================================

main() {
    # 检测管道执行模式
    if [[ ! -t 0 ]]; then
        PIPE_MODE=1
        NON_INTERACTIVE=1
    fi
    
    # 初始化
    log_init
    setup_traps
    
    # 解析参数
    local install_kernel=""
    local show_status_only=0
    local show_help=0
    local do_uninstall_flag=0
    local do_auto=0
    local check_bbr3=0
    local do_update=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --algo)
                [[ -z "${2:-}" ]] && { print_error "--algo 需要参数"; exit 1; }
                CHOSEN_ALGO="$2"
                shift 2
                ;;
            --qdisc)
                [[ -z "${2:-}" ]] && { print_error "--qdisc 需要参数"; exit 1; }
                CHOSEN_QDISC="$2"
                shift 2
                ;;
            --install-kernel)
                [[ -z "${2:-}" ]] && { print_error "--install-kernel 需要参数"; exit 1; }
                install_kernel="$2"
                shift 2
                ;;
            --apply)
                APPLY_NOW=1
                shift
                ;;
            --no-apply)
                APPLY_NOW=0
                shift
                ;;
            --mirror)
                local mirror_name="${2:-auto}"
                case "$mirror_name" in
                    tsinghua|aliyun|ustc|huawei)
                        USE_CHINA_MIRROR=1
                        MIRROR_URL="${MIRRORS_CN[$mirror_name]}"
                        ;;
                    auto)
                        # 自动检测，稍后处理
                        ;;
                    *)
                        print_error "未知镜像源: $mirror_name"
                        print_info "可用选项: tsinghua, aliyun, ustc, huawei, auto"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --non-interactive)
                NON_INTERACTIVE=1
                shift
                ;;
            --allow-unverified-update)
                ALLOW_UNVERIFIED_UPDATE=1
                shift
                ;;
            --update)
                # 显式 CLI 入口 - 推迟到 arg 循环结束后执行,
                # 这样 --allow-unverified-update 无论位置都能生效
                do_update=1
                shift
                ;;
            --status)
                show_status_only=1
                shift
                ;;
            --auto)
                do_auto=1
                APPLY_NOW=1
                shift
                ;;
            --check-bbr3)
                check_bbr3=1
                shift
                ;;
            --uninstall)
                do_uninstall_flag=1
                shift
                ;;
            --install)
                # 安装快捷命令
                print_logo
                detect_os
                install_shortcut
                exit $?
                ;;
            --debug)
                DEBUG_MODE=1
                shift
                ;;
            --proxy-tune)
                # 代理智能调优
                print_logo
                detect_os
                detect_arch
                detect_virt
                proxy_tune_wizard
                exit 0
                ;;
            --verify)
                # 验证优化状态
                detect_os
                generate_diagnostic_report
                exit $?
                ;;
            --detect)
                # 仅检测不应用
                print_logo
                detect_os
                echo -e "${CYAN}智能检测模式 (仅检测不应用)${NC}"
                echo
                assess_hardware_score >/dev/null
                print_kv "硬件评分" "$SMART_HARDWARE_SCORE"
                print_kv "CPU" "${SERVER_CPU_CORES} 核"
                print_kv "内存" "${SERVER_MEMORY_MB} MB"
                echo
                detect_bandwidth >/dev/null
                print_kv "检测带宽" "${SMART_DETECTED_BANDWIDTH} Mbps"
                detect_rtt >/dev/null
                print_kv "RTT 延迟" "${SMART_DETECTED_RTT} ms"
                calculate_bdp_buffer >/dev/null
                local buffer_mb=$((SMART_OPTIMAL_BUFFER / 1024 / 1024))
                print_kv "推荐缓冲区" "${buffer_mb} MB"
                detect_optimal_mtu >/dev/null
                print_kv "最优 MTU" "$SMART_OPTIMAL_MTU"
                exit 0
                ;;
            --smart)
                # 智能自动优化
                print_logo
                detect_os
                detect_arch
                detect_virt
                smart_auto_optimize
                exit 0
                ;;
            --health)
                # 仅输出健康评分
                detect_os
                quick_verify
                exit $?
                ;;
            --help|-h)
                show_help=1
                shift
                ;;
            --version|-v)
                echo "BBR3 一键脚本 v${SCRIPT_VERSION}"
                echo "项目地址: ${GITHUB_URL}"
                exit 0
                ;;
            *)
                print_error "未知选项: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # 显示帮助
    if [[ $show_help -eq 1 ]]; then
        usage
        exit 0
    fi
    
    # 检查 root 权限
    if [[ $(id -u) -ne 0 ]]; then
        print_error "请使用 root 权限运行此脚本"
        echo
        echo "  使用方法:"
        echo "    sudo $SCRIPT_NAME"
        echo "  或"
        echo "    sudo bash $SCRIPT_NAME"
        exit 1
    fi
    
    # 显示 Logo
    print_logo
    
    # 执行预检
    detect_os
    detect_arch
    detect_virt
    try_load_modules

    # 推迟执行的 --update (允许 --allow-unverified-update 在任意位置)
    if [[ $do_update -eq 1 ]]; then
        update_script
        exit $?
    fi

    # 快速检测 BBR3
    if [[ $check_bbr3 -eq 1 ]]; then
        local kver algo
        kver=$(uname -r | sed 's/[^0-9.].*$//')
        algo=$(get_current_algo)
        
        if [[ "$algo" == "bbr3" ]] || { [[ "$algo" == "bbr" ]] && version_ge "$kver" "6.9.0"; }; then
            echo "BBR3_ACTIVE=YES"
            echo "KERNEL=${kver}"
            echo "ALGO=${algo}"
            exit 0
        else
            echo "BBR3_ACTIVE=NO"
            echo "KERNEL=${kver}"
            echo "ALGO=${algo}"
            exit 1
        fi
    fi
    
    # 仅显示状态
    if [[ $show_status_only -eq 1 ]]; then
        # 确保加载内核模块以检测可用算法
        try_load_modules
        show_status
        exit 0
    fi
    
    # 卸载
    if [[ $do_uninstall_flag -eq 1 ]]; then
        do_uninstall
        exit 0
    fi
    
    # 执行完整预检
    if ! run_precheck; then
        if [[ $NON_INTERACTIVE -eq 1 ]]; then
            exit 1
        fi
        if ! confirm "预检未完全通过，是否继续？" "n"; then
            exit 1
        fi
    fi
    
    # 选择镜像源
    if [[ $USE_CHINA_MIRROR -eq 1 ]] && [[ -z "$MIRROR_URL" ]]; then
        select_best_mirror
    fi
    
    # 安装内核
    if [[ -n "$install_kernel" ]]; then
        case "$install_kernel" in
            xanmod)
                install_kernel_xanmod && prompt_reboot
                ;;
            liquorix)
                install_kernel_liquorix && prompt_reboot
                ;;
            elrepo)
                install_kernel_elrepo && prompt_reboot
                ;;
            hwe)
                install_kernel_hwe && prompt_reboot
                ;;
            *)
                print_error "未知内核类型: $install_kernel"
                exit 1
                ;;
        esac
        exit $?
    fi
    
    # 自动优化
    if [[ $do_auto -eq 1 ]]; then
        auto_tune
        if ! write_sysctl "$CHOSEN_ALGO" "$CHOSEN_QDISC"; then
            print_error "写入 sysctl 配置失败"
            exit 1
        fi
        apply_sysctl
        apply_qdisc_runtime "$CHOSEN_QDISC"
        print_success "自动优化完成"
        show_status
        exit 0
    fi
    
    # 命令行指定算法
    if [[ -n "$CHOSEN_ALGO" ]]; then
        # 验证算法
        if ! algo_supported "$CHOSEN_ALGO"; then
            print_error "算法 ${CHOSEN_ALGO} 不可用"
            print_info "可用算法: $(detect_available_algos)"
            exit 1
        fi
        
        # 规范化
        CHOSEN_ALGO=$(normalize_algo "$CHOSEN_ALGO")
        CHOSEN_QDISC="${CHOSEN_QDISC:-fq}"
        
        # 设置默认缓冲区（检测容器限制）
        local max_rmem max_wmem
        max_rmem=$(cat /proc/sys/net/core/rmem_max 2>/dev/null || echo "67108864")
        max_wmem=$(cat /proc/sys/net/core/wmem_max 2>/dev/null || echo "67108864")
        
        # 容器环境可能有限制，使用当前值的10倍或67108864中的较小值
        if [[ $max_rmem -lt 1048576 ]]; then
            TUNE_RMEM_MAX=${TUNE_RMEM_MAX:-$((max_rmem * 10))}
            TUNE_WMEM_MAX=${TUNE_WMEM_MAX:-$((max_wmem * 10))}
            TUNE_TCP_RMEM_HIGH=${TUNE_TCP_RMEM_HIGH:-$((max_rmem * 10))}
            TUNE_TCP_WMEM_HIGH=${TUNE_TCP_WMEM_HIGH:-$((max_wmem * 10))}
        else
            TUNE_RMEM_MAX=${TUNE_RMEM_MAX:-67108864}
            TUNE_WMEM_MAX=${TUNE_WMEM_MAX:-67108864}
            TUNE_TCP_RMEM_HIGH=${TUNE_TCP_RMEM_HIGH:-67108864}
            TUNE_TCP_WMEM_HIGH=${TUNE_TCP_WMEM_HIGH:-67108864}
        fi
        
        # 写入配置
        if ! write_sysctl "$CHOSEN_ALGO" "$CHOSEN_QDISC"; then
            print_error "写入 sysctl 配置失败"
            exit 1
        fi

        # 应用配置
        if [[ $APPLY_NOW -eq 1 ]]; then
            apply_sysctl
            apply_qdisc_runtime "$CHOSEN_QDISC"
        fi

        print_success "配置完成"
        print_kv "算法" "$CHOSEN_ALGO"
        print_kv "队列" "$CHOSEN_QDISC"
        print_kv "已应用" "$([[ $APPLY_NOW -eq 1 ]] && echo '是' || echo '否')"
        exit 0
    fi
    
    # 交互模式
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        print_error "非交互模式下必须指定 --algo 或 --auto"
        usage
        exit 1
    fi
    
    show_main_menu
}

# 运行主函数
main "$@"
