#!/usr/bin/env bash
# Linux 工具箱 Pro Final
# 功能:
# - Swap 管理
# - NTP 配置
# - 时区设置
# - Docker / Docker Compose
# - 卸载 virtio_balloon
# - WARP 菜单
# - 内核脚本
# - 3x-ui
# - InstallNET DD 重装（可自主选择系统/版本）
# - 执行前环境检查
# - yes/no 输入优化
# - InstallNET 密码隐藏输入 + 二次确认

set -Eeuo pipefail

readonly GREEN="\033[32m"
readonly RED="\033[31m"
readonly YELLOW="\033[33m"
readonly BLUE="\033[36m"
readonly RESET="\033[0m"

readonly SWAPFILE="/swapfile"
readonly FSTAB="/etc/fstab"
readonly TIMESYNCD_CONF="/etc/systemd/timesyncd.conf"
readonly LOG_FILE="/var/log/linux-toolbox.log"
readonly TMP_DIR="/tmp/linux-toolbox.$$"

PKG_MANAGER=""
OS_FAMILY=""

trap 'on_error ${LINENO} "$BASH_COMMAND"' ERR
trap 'cleanup' EXIT

on_error() {
    local line="$1"
    local cmd="$2"
    echo -e "${RED}[错误] 脚本执行失败！行号: ${line}，命令: ${cmd}${RESET}"
    echo "[ERROR] $(date '+%F %T') line=${line} cmd=${cmd}" >> "$LOG_FILE" 2>/dev/null || true
    exit 1
}

cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null || true
}

log() {
    echo -e "${GREEN}[信息] $*${RESET}"
    echo "[INFO] $(date '+%F %T') $*" >> "$LOG_FILE" 2>/dev/null || true
}

warn() {
    echo -e "${YELLOW}[警告] $*${RESET}"
    echo "[WARN] $(date '+%F %T') $*" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    echo -e "${RED}[错误] $*${RESET}"
    echo "[ERROR] $(date '+%F %T') $*" >> "$LOG_FILE" 2>/dev/null || true
}

info() {
    echo -e "${BLUE}[提示] $*${RESET}"
}

pause() {
    read -r -p "按回车继续..."
}

require_root() {
    [[ ${EUID} -eq 0 ]] || {
        error "必须以 root 身份运行此脚本！"
        exit 1
    }
}

check_virtualization_basic() {
    if [[ -d /proc/vz ]] && ! command -v systemd-detect-virt >/dev/null 2>&1; then
        error "检测到 OpenVZ 环境，部分功能可能不支持。"
        exit 1
    fi
}

detect_os() {
    [[ -r /etc/os-release ]] || {
        error "无法识别系统类型：缺少 /etc/os-release"
        exit 1
    }

    # shellcheck disable=SC1091
    source /etc/os-release

    case "${ID_LIKE:-$ID}" in
        *debian*|*ubuntu*)
            PKG_MANAGER="apt"
            OS_FAMILY="debian"
            ;;
        *rhel*|*fedora*|*centos*|*rocky*|*almalinux*)
            if command -v dnf >/dev/null 2>&1; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            OS_FAMILY="rhel"
            ;;
        *)
            error "暂不支持该发行版：${PRETTY_NAME:-unknown}"
            exit 1
            ;;
    esac
}

run_pkg_update() {
    case "$PKG_MANAGER" in
        apt) apt-get update -qq ;;
        dnf) dnf makecache -q ;;
        yum) yum makecache -q ;;
    esac
}

install_packages() {
    local packages=("$@")
    [[ ${#packages[@]} -gt 0 ]] || return 0

    case "$PKG_MANAGER" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
            ;;
        dnf)
            dnf install -y "${packages[@]}"
            ;;
        yum)
            yum install -y "${packages[@]}"
            ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

ensure_base_tools() {
    run_pkg_update
    case "$OS_FAMILY" in
        debian)
            install_packages ca-certificates curl wget gnupg lsb-release sed grep coreutils systemd iproute2 kmod
            ;;
        rhel)
            install_packages ca-certificates curl wget gnupg2 sed grep coreutils systemd iproute kmod
            ;;
    esac
}

ask_input() {
    local prompt="$1"
    local default="${2:-}"
    local input=""

    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " input
        echo "${input:-$default}"
    else
        read -r -p "$prompt: " input
        echo "$input"
    fi
}

ask_nonempty() {
    local prompt="$1"
    local default="${2:-}"
    local value=""

    while true; do
        value="$(ask_input "$prompt" "$default")"
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
        error "输入不能为空！"
    done
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-no}"
    local answer=""

    while true; do
        case "$default" in
            yes) read -r -p "$prompt [Y/n]: " answer ;;
            no)  read -r -p "$prompt [y/N]: " answer ;;
            *)   read -r -p "$prompt [y/n]: " answer ;;
        esac

        answer="${answer,,}"
        [[ -z "$answer" ]] && answer="$default"

        case "$answer" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) warn "请输入 yes/y 或 no/n。" ;;
        esac
    done
}

confirm() {
    ask_yes_no "$1" "no"
}

confirm_default_yes() {
    ask_yes_no "$1" "yes"
}

danger_confirm() {
    local prompt="$1"
    warn "$prompt"
    warn "这是高危操作。"
    local answer=""
    while true; do
        read -r -p "请输入 yes 或 no 确认是否继续 [no]: " answer
        answer="${answer,,}"
        [[ -z "$answer" ]] && answer="no"
        case "$answer" in
            yes|y) return 0 ;;
            no|n)  warn "已取消操作。"; return 1 ;;
            *) warn "请输入 yes/y 或 no/n。" ;;
        esac
    done
}

ask_password_twice() {
    local prompt="${1:-请输入密码}"
    local pwd1=""
    local pwd2=""

    while true; do
        read -r -s -p "${prompt}: " pwd1
        echo
        [[ -n "$pwd1" ]] || {
            error "密码不能为空！"
            continue
        }

        read -r -s -p "请再次输入密码: " pwd2
        echo

        [[ "$pwd1" == "$pwd2" ]] || {
            error "两次输入的密码不一致，请重新输入。"
            continue
        }

        echo "$pwd1"
        return 0
    done
}

backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    cp -a "$file" "${file}.bak.$(date +%Y%m%d_%H%M%S)"
}

download_to() {
    local url="$1"
    local output="$2"

    mkdir -p "$TMP_DIR"

    if command_exists curl; then
        curl -fsSL "$url" -o "$output"
    elif command_exists wget; then
        wget -qO "$output" "$url"
    else
        error "系统缺少 curl/wget，无法下载文件。"
        return 1
    fi
}

run_remote_script() {
    local name="$1"
    local url="$2"
    shift 2
    local script_path="${TMP_DIR}/${name}.sh"

    log "正在下载 ${name} 脚本..."
    download_to "$url" "$script_path"
    chmod +x "$script_path"

    log "开始执行 ${name}..."
    bash "$script_path" "$@"
}

get_virtualization_type() {
    if command_exists systemd-detect-virt; then
        systemd-detect-virt 2>/dev/null || echo "none"
    elif [[ -d /proc/vz ]]; then
        echo "openvz"
    else
        echo "unknown"
    fi
}

is_kvm() {
    local virt
    virt="$(get_virtualization_type)"
    [[ "$virt" == "kvm" || "$virt" == "qemu" ]]
}

has_tun_device() {
    [[ -c /dev/net/tun ]]
}

has_systemd() {
    [[ -d /run/systemd/system ]] && command_exists systemctl
}

get_default_iface() {
    ip route 2>/dev/null | awk '/default/ {print $5; exit}'
}

get_default_gateway() {
    ip route 2>/dev/null | awk '/default/ {print $3; exit}'
}

get_ipv4_by_iface() {
    local iface="${1:-}"
    [[ -n "$iface" ]] || return 0
    ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet / {print $2}' | head -n1
}

get_ipv6_by_iface() {
    local iface="${1:-}"
    [[ -n "$iface" ]] || return 0
    ip -6 addr show dev "$iface" 2>/dev/null | awk '/inet6 / && $2 !~ /^fe80/ {print $2}' | head -n1
}

show_precheck_summary() {
    local virt iface gw ipv4 ipv6 kernel distro systemd_status tun_status

    virt="$(get_virtualization_type)"
    iface="$(get_default_iface)"
    gw="$(get_default_gateway)"
    ipv4="$(get_ipv4_by_iface "$iface")"
    ipv6="$(get_ipv6_by_iface "$iface")"
    kernel="$(uname -r)"
    distro="$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")"

    if has_systemd; then
        systemd_status="yes"
    else
        systemd_status="no"
    fi

    if has_tun_device; then
        tun_status="yes"
    else
        tun_status="no"
    fi

    echo "---------------- 环境检查 ----------------"
    echo "虚拟化类型     : ${virt}"
    echo "是否 KVM/QEMU  : $(is_kvm && echo yes || echo no)"
    echo "TUN 设备存在   : ${tun_status}"
    echo "systemd 可用   : ${systemd_status}"
    echo "内核版本       : ${kernel}"
    echo "发行版         : ${distro}"
    echo "默认网卡       : ${iface:-unknown}"
    echo "IPv4 地址      : ${ipv4:-none}"
    echo "IPv6 地址      : ${ipv6:-none}"
    echo "默认网关       : ${gw:-unknown}"
    echo "----------------------------------------"
}

precheck_base_network() {
    command_exists ip || {
        error "缺少 ip 命令，请先安装 iproute2/iproute。"
        return 1
    }

    local iface
    iface="$(get_default_iface)"
    [[ -n "$iface" ]] || {
        error "未检测到默认网卡，网络环境异常。"
        return 1
    }

    return 0
}

precheck_for_warp() {
    show_precheck_summary
    precheck_base_network || return 1

    if ! has_tun_device; then
        warn "未检测到 /dev/net/tun，WARP 很可能无法正常工作。"
        confirm "仍然继续运行 WARP 菜单？" || return 1
    fi

    return 0
}

precheck_for_kernel() {
    show_precheck_summary
    precheck_base_network || return 1

    if ! has_systemd; then
        warn "当前系统未检测到 systemd，部分内核脚本流程可能异常。"
        confirm "仍然继续运行内核脚本？" || return 1
    fi

    if ! is_kvm; then
        warn "当前虚拟化类型不是 KVM/QEMU，内核更换后可能存在兼容性风险。"
        confirm "仍然继续运行内核脚本？" || return 1
    fi

    return 0
}

precheck_for_installnet() {
    show_precheck_summary
    precheck_base_network || return 1

    if ! has_systemd; then
        warn "当前系统未检测到 systemd，环境较特殊。"
    fi

    if ! is_kvm; then
        warn "当前并非 KVM/QEMU，DD 后网络驱动/启动兼容性风险更高。"
    fi

    return 0
}

show_header() {
    clear
    echo "————————————————————————————————————————————"
    echo -e "${GREEN}Linux 工具箱 Pro Final${RESET}"
    echo "————————————————————————————————————————————"
}

show_menu() {
    echo -e "${GREEN}1.${RESET} 添加 Swap"
    echo -e "${GREEN}2.${RESET} 删除 Swap"
    echo -e "${GREEN}3.${RESET} 安装和配置 NTP"
    echo -e "${GREEN}4.${RESET} 设置时区"
    echo -e "${GREEN}5.${RESET} 安装 Docker"
    echo -e "${GREEN}6.${RESET} 安装 Docker Compose 插件"
    echo -e "${GREEN}7.${RESET} 卸载 virtio_balloon 模块"
    echo -e "${GREEN}8.${RESET} DD 重装系统（InstallNET，可自主选择）"
    echo -e "${GREEN}9.${RESET} 安装 WARP 菜单"
    echo -e "${GREEN}10.${RESET} 运行内核管理脚本"
    echo -e "${GREEN}11.${RESET} 安装 3x-ui"
    echo -e "${GREEN}12.${RESET} 查看系统信息"
    echo -e "${GREEN}0.${RESET} 退出脚本"
    echo "————————————————————————————————————————————"
}

show_system_info() {
    local virt iface gw ipv4 ipv6

    virt="$(get_virtualization_type)"
    iface="$(get_default_iface)"
    gw="$(get_default_gateway)"
    ipv4="$(get_ipv4_by_iface "$iface")"
    ipv6="$(get_ipv6_by_iface "$iface")"

    log "系统信息如下："
    uname -a || true
    echo
    cat /etc/os-release || true
    echo
    echo "虚拟化类型: ${virt}"
    echo "是否 KVM/QEMU: $(is_kvm && echo yes || echo no)"
    echo "systemd 可用: $(has_systemd && echo yes || echo no)"
    echo "TUN 设备存在: $(has_tun_device && echo yes || echo no)"
    echo "默认网卡: ${iface:-unknown}"
    echo "IPv4 地址: ${ipv4:-none}"
    echo "IPv6 地址: ${ipv6:-none}"
    echo "默认网关: ${gw:-unknown}"
    echo
    free -h || true
    echo
    swapon --show || true
    echo
    lsmod | grep virtio_balloon || true
    echo
    timedatectl status --no-pager || true
    echo
    if command_exists docker; then
        docker --version || true
    fi
    if docker compose version >/dev/null 2>&1; then
        docker compose version || true
    elif command_exists docker-compose; then
        docker-compose --version || true
    fi
}

setup_ntp() {
    log "请选择 NTP 服务器来源："
    echo "1) 国外（Google NTP）"
    echo "2) 国内（阿里云 NTP）"

    local choice ntp_servers
    choice="$(ask_input "请输入选择" "1")"

    case "$choice" in
        1) ntp_servers="time1.google.com time2.google.com time3.google.com time4.google.com" ;;
        2) ntp_servers="ntp.aliyun.com ntp1.aliyun.com ntp2.aliyun.com ntp3.aliyun.com ntp4.aliyun.com ntp5.aliyun.com ntp6.aliyun.com ntp7.aliyun.com" ;;
        *) warn "无效选择，已使用默认 Google NTP。"; ntp_servers="time1.google.com time2.google.com time3.google.com time4.google.com" ;;
    esac

    confirm "确定要安装并配置 NTP 服务吗？" || { warn "已取消操作。"; return 0; }

    run_pkg_update
    case "$OS_FAMILY" in
        debian) install_packages systemd-timesyncd ;;
        rhel) install_packages systemd ;;
    esac

    backup_file "$TIMESYNCD_CONF"
    mkdir -p /etc/systemd

    if [[ ! -f "$TIMESYNCD_CONF" ]]; then
        cat > "$TIMESYNCD_CONF" <<EOF
[Time]
NTP=${ntp_servers}
FallbackNTP=
EOF
    else
        if grep -q '^\[Time\]' "$TIMESYNCD_CONF"; then
            if grep -q '^NTP=' "$TIMESYNCD_CONF"; then
                sed -i "s|^NTP=.*|NTP=${ntp_servers}|" "$TIMESYNCD_CONF"
            else
                sed -i "/^\[Time\]/a NTP=${ntp_servers}" "$TIMESYNCD_CONF"
            fi
            if grep -q '^FallbackNTP=' "$TIMESYNCD_CONF"; then
                sed -i 's|^FallbackNTP=.*|FallbackNTP=|' "$TIMESYNCD_CONF"
            else
                sed -i '/^\[Time\]/a FallbackNTP=' "$TIMESYNCD_CONF"
            fi
        else
            cat >> "$TIMESYNCD_CONF" <<EOF

[Time]
NTP=${ntp_servers}
FallbackNTP=
EOF
        fi
    fi

    systemctl enable systemd-timesyncd >/dev/null 2>&1 || true
    systemctl restart systemd-timesyncd || true
    timedatectl set-local-rtc 0 || true
    timedatectl set-ntp true || true

    log "NTP 配置完成。"
    timedatectl status --no-pager || true
}

set_timezone() {
    local keyword timezone
    keyword="$(ask_nonempty "请输入要过滤的时区关键字（例如 Asia）" "Asia")"

    log "匹配到的时区："
    timedatectl list-timezones | grep -i "$keyword" || warn "未找到匹配项，可手动输入完整时区。"

    timezone="$(ask_nonempty "请输入时区（例如 Asia/Shanghai）" "Asia/Shanghai")"

    if ! timedatectl list-timezones | grep -Fxq "$timezone"; then
        error "无效时区：$timezone"
        return 1
    fi

    confirm "确定要设置时区为 $timezone 吗？" || { warn "已取消操作。"; return 0; }

    timedatectl set-timezone "$timezone"
    log "时区已设置为 $timezone"
    timedatectl status --no-pager
}

swap_exists() {
    swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$SWAPFILE"
}

add_swap() {
    local swapsize
    swapsize="$(ask_nonempty "请输入要添加的 Swap 大小（MB，最大 20480）" "1024")"

    [[ "$swapsize" =~ ^[0-9]+$ ]] || { error "请输入数字。"; return 1; }
    (( swapsize > 0 && swapsize <= 20480 )) || { error "请输入合理的 Swap 大小（1~20480 MB）。"; return 1; }

    if grep -qE "^[^#].*\s${SWAPFILE}\s" "$FSTAB" || [[ -f "$SWAPFILE" ]] || swap_exists; then
        error "检测到已存在的 /swapfile，请先删除后再重新添加。"
        return 1
    fi

    confirm "确定要创建 ${swapsize}MB 的 Swap 吗？" || { warn "已取消操作。"; return 0; }

    if command_exists fallocate; then
        if ! fallocate -l "${swapsize}M" "$SWAPFILE"; then
            warn "fallocate 失败，自动改用 dd 创建。"
            dd if=/dev/zero of="$SWAPFILE" bs=1M count="$swapsize" status=progress
        fi
    else
        dd if=/dev/zero of="$SWAPFILE" bs=1M count="$swapsize" status=progress
    fi

    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
    swapon "$SWAPFILE"

    if ! grep -qF "$SWAPFILE none swap sw 0 0" "$FSTAB"; then
        echo "$SWAPFILE none swap sw 0 0" >> "$FSTAB"
    fi

    log "Swap 创建成功。"
    swapon --show
    grep -E 'MemTotal|SwapTotal|SwapFree' /proc/meminfo
}

del_swap() {
    if ! grep -qF "$SWAPFILE" "$FSTAB" && [[ ! -f "$SWAPFILE" ]] && ! swap_exists; then
        error "未发现 /swapfile，无法删除。"
        return 1
    fi

    confirm "确定要删除 /swapfile 吗？" || { warn "已取消操作。"; return 0; }

    swapoff "$SWAPFILE" 2>/dev/null || true
    sed -i "\|^${SWAPFILE}[[:space:]]|d" "$FSTAB"
    rm -f "$SWAPFILE"

    log "Swap 已删除。"
    swapon --show || true
}

install_docker_debian() {
    run_pkg_update
    install_packages ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    local arch codename distro_id
    arch="$(dpkg --print-architecture)"
    distro_id="$(. /etc/os-release && echo "$ID")"
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"

    cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${distro_id} ${codename} stable
EOF

    run_pkg_update
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_rhel() {
    run_pkg_update
    install_packages yum-utils curl ca-certificates

    case "$PKG_MANAGER" in
        dnf) dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo ;;
        yum) yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo ;;
    esac

    run_pkg_update
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker() {
    confirm "确定要安装 Docker 吗？" || { warn "已取消操作。"; return 0; }

    case "$OS_FAMILY" in
        debian) install_docker_debian ;;
        rhel) install_docker_rhel ;;
        *) error "当前系统不支持自动安装 Docker。"; return 1 ;;
    esac

    systemctl enable docker
    systemctl restart docker

    log "Docker 安装完成。"
    docker --version
    docker info >/dev/null 2>&1 && log "Docker 服务运行正常。" || warn "Docker 已安装，但服务状态异常，请检查。"
    systemctl status docker --no-pager -l || true
}

install_docker_compose() {
    if ! command_exists docker; then
        error "请先安装 Docker。"
        return 1
    fi

    if docker compose version >/dev/null 2>&1; then
        log "Docker Compose 插件已安装："
        docker compose version
        return 0
    fi

    confirm "确定要安装 Docker Compose 插件吗？" || { warn "已取消操作。"; return 0; }

    case "$OS_FAMILY" in
        debian|rhel)
            run_pkg_update
            install_packages docker-compose-plugin
            ;;
        *)
            error "当前系统不支持自动安装 Docker Compose 插件。"
            return 1
            ;;
    esac

    if docker compose version >/dev/null 2>&1; then
        log "Docker Compose 插件安装完成。"
        docker compose version
    elif command_exists docker-compose; then
        log "检测到旧版 docker-compose："
        docker-compose --version
    else
        error "Docker Compose 安装失败。"
        return 1
    fi
}

remove_virtio_balloon() {
    warn "该操作会尝试卸载 virtio_balloon 内核模块。"
    warn "如果你的 VPS/虚拟化平台依赖该模块，可能影响内存气球机制。"

    confirm "确定继续尝试卸载 virtio_balloon 吗？" || { warn "已取消操作。"; return 0; }

    if ! lsmod | grep -q '^virtio_balloon'; then
        warn "当前系统未加载 virtio_balloon 模块。"
        return 0
    fi

    modprobe -r virtio_balloon || rmmod virtio_balloon
    log "virtio_balloon 卸载完成。"
    lsmod | grep virtio_balloon || true
}

install_warp_menu() {
    warn "即将运行第三方 WARP 菜单脚本。"

    precheck_for_warp || {
        warn "环境检查未通过，已取消。"
        return 1
    }

    confirm "确定继续安装/运行 WARP 菜单吗？" || { warn "已取消操作。"; return 0; }

    run_remote_script "warp-menu" "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh"
}

run_kernel_script() {
    warn "即将运行第三方内核管理脚本。"
    warn "内核变更通常需要重启，可能影响网络驱动与兼容性。"

    precheck_for_kernel || {
        warn "环境检查未通过，已取消。"
        return 1
    }

    confirm "确定继续运行内核管理脚本吗？" || { warn "已取消操作。"; return 0; }

    run_remote_script "kernel-manager" "https://git.io/kernel.sh"
}

install_3x_ui() {
    warn "即将运行第三方 3x-ui 安装脚本。"
    confirm "确定继续安装 3x-ui 吗？" || { warn "已取消操作。"; return 0; }

    run_remote_script "3x-ui-install" "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
}

installnet_select_release() {
    echo "请选择目标系统："
    echo "1) Debian"
    echo "2) Ubuntu"
    echo "3) Kali"
    echo "4) AlpineLinux"
    echo "5) CentOS"
    echo "6) RockyLinux"
    echo "7) AlmaLinux"
    echo "8) Fedora"
    echo "9) Windows"
    local choice
    choice="$(ask_nonempty "请输入数字" "1")"

    case "$choice" in
        1) echo "debian" ;;
        2) echo "ubuntu" ;;
        3) echo "kali" ;;
        4) echo "alpine" ;;
        5) echo "centos" ;;
        6) echo "rockylinux" ;;
        7) echo "almalinux" ;;
        8) echo "fedora" ;;
        9) echo "windows" ;;
        *) error "无效选择"; return 1 ;;
    esac
}

installnet_select_version() {
    local release="$1"
    case "$release" in
        debian)
            echo "Debian 推荐范围: 7-13"
            ask_nonempty "请输入 Debian 版本" "12"
            ;;
        ubuntu)
            echo "Ubuntu README 列出: 20.04 / 22.04 / 24.04"
            ask_nonempty "请输入 Ubuntu 版本" "22.04"
            ;;
        kali)
            echo "Kali 可选: rolling / dev / experimental"
            ask_nonempty "请输入 Kali 版本" "rolling"
            ;;
        alpine)
            echo "Alpine 推荐: 3.16-3.18 / edge"
            ask_nonempty "请输入 Alpine 版本" "edge"
            ;;
        centos)
            echo "CentOS 推荐: 7 / 8 / 9-stream"
            ask_nonempty "请输入 CentOS 版本" "9-stream"
            ;;
        rockylinux)
            echo "RockyLinux 推荐: 8 / 9"
            ask_nonempty "请输入 RockyLinux 版本" "9"
            ;;
        almalinux)
            echo "AlmaLinux 推荐: 8 / 9"
            ask_nonempty "请输入 AlmaLinux 版本" "9"
            ;;
        fedora)
            echo "Fedora 推荐: 42 / 43"
            ask_nonempty "请输入 Fedora 版本" "43"
            ;;
        windows)
            echo "Windows 可选示例: 10 / 11 / 2012 / 2016 / 2019 / 2022"
            ask_nonempty "请输入 Windows 版本" "11"
            ;;
        *)
            error "未知发行版"
            return 1
            ;;
    esac
}

run_installnet_custom() {
    warn "这是高危操作：会执行 DD/网络重装系统。"
    warn "执行后当前系统环境、数据、网络配置都可能被覆盖。"
    warn "请确保你已经备份重要数据，并确认 VNC/控制台可用。"

    precheck_for_installnet || {
        warn "环境检查未通过，已取消。"
        return 1
    }

    local release version root_pwd ssh_port mirror_url set_cmd installer extra_args confirm_text
    release="$(installnet_select_release)"
    version="$(installnet_select_version "$release")"

    if [[ "$release" == "ubuntu" ]]; then
        warn "Ubuntu 在上游 README 中存在原生安装限制，22.04+ 尤其要谨慎。"
    fi

    if [[ "$release" == "windows" ]]; then
        warn "Windows 安装完成后默认用户通常为 Administrator，且登录/联网排障更依赖控制台。"
    fi

    root_pwd="$(ask_password_twice "请输入新系统密码")"

    ssh_port="$(ask_input "请输入 SSH 端口（Linux 有效，直接回车保持原端口）" "")"
    mirror_url="$(ask_input "请输入镜像源（可留空）" "")"

    extra_args=()
    if [[ -n "$ssh_port" && "$release" != "windows" ]]; then
        extra_args+=("-port" "$ssh_port")
    fi
    if [[ -n "$mirror_url" ]]; then
        extra_args+=("-mirror" "$mirror_url")
    fi

    set_cmd="bash InstallNET.sh -${release} ${version} -pwd '******'"
    if [[ -n "$ssh_port" && "$release" != "windows" ]]; then
        set_cmd="${set_cmd} -port '${ssh_port}'"
    fi
    if [[ -n "$mirror_url" ]]; then
        set_cmd="${set_cmd} -mirror '${mirror_url}'"
    fi

    echo "即将执行参数预览："
    echo "$set_cmd"

    danger_confirm "你即将开始重装到 ${release} ${version}。" || return 0

    mkdir -p "$TMP_DIR"
    installer="${TMP_DIR}/InstallNET.sh"
    download_to "https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh" "$installer"
    chmod +x "$installer"

    log "开始执行 InstallNET..."
    bash "$installer" "-${release}" "$version" -pwd "$root_pwd" "${extra_args[@]}"
}

init_env() {
    mkdir -p "$TMP_DIR"
    touch "$LOG_FILE" 2>/dev/null || true
    require_root
    check_virtualization_basic
    detect_os
    ensure_base_tools
}

main() {
    init_env

    while true; do
        show_header
        show_menu

        local choice
        choice="$(ask_input "请输入数字 [0-12]" "0")"

        case "$choice" in
            0) log "退出脚本。"; exit 0 ;;
            1) add_swap ;;
            2) del_swap ;;
            3) setup_ntp ;;
            4) set_timezone ;;
            5) install_docker ;;
            6) install_docker_compose ;;
            7) remove_virtio_balloon ;;
            8) run_installnet_custom ;;
            9) install_warp_menu ;;
            10) run_kernel_script ;;
            11) install_3x_ui ;;
            12) show_system_info ;;
            *) error "请输入正确数字 [0-12]" ;;
        esac

        echo
        pause
    done
}

main
