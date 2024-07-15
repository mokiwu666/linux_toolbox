#!/usr/bin/env bash
# blog: https://blog.935g.cn/

Green="\033[32m"
Font="\033[0m"
Red="\033[31m"
SWAPFILE="/swapfile"
FSTAB="/etc/fstab"

trap 'echo -e "${Red}脚本执行失败！${Font}"; exit 1' ERR

log() {
    echo -e "$1"
}

check_root() {
    [[ $EUID -eq 0 ]] || { log "${Red}Error: 必须以 root 身份运行此脚本！${Font}"; exit 1; }
}

check_ovz() {
    [[ -d "/proc/vz" ]] && { log "${Red}您的 VPS 是基于 OpenVZ，不支持！${Font}"; exit 1; }
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || { log "${Red}未找到命令: $1${Font}"; return 1; }
}

prompt_input() {
    local prompt_msg="$1"
    read -p "$prompt_msg" user_input
    if [[ -z "$user_input" ]]; then
        log "${Red}输入不能为空！${Font}"
        return 1
    fi
    echo "$user_input"
}

confirm_action() {
    local prompt_msg="$1"
    read -p "$prompt_msg (y/n): " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        return 0
    else
        log "${Red}操作已取消。${Font}"
        return 1
    fi
}

setup_ntp() {
    log "${Green}请选择 NTP 服务器来源：${Font}"
    log "${Green}1. 国外 (默认使用 Google NTP)${Font}"
    log "${Green}2. 国内 (使用阿里云 NTP)${Font}"

    local choice
    choice=$(prompt_input "请输入选择 [1-2] (默认选择 1): ")
    [[ -z "$choice" ]] && choice=1

    local ntp_servers
    case "$choice" in
        1) ntp_servers="time1.google.com time2.google.com time3.google.com time4.google.com" ;;
        2) ntp_servers="ntp.aliyun.com ntp1.aliyun.com ntp2.aliyun.com ntp3.aliyun.com ntp4.aliyun.com ntp5.aliyun.com ntp6.aliyun.com ntp7.aliyun.com" ;;
        *) log "${Red}无效的选择，使用默认国外 NTP 服务器。${Font}" && ntp_servers="time1.google.com time2.google.com time3.google.com time4.google.com" ;;
    esac

    log "${Green}正在安装和配置 NTP 服务...${Font}"
    if confirm_action "确定要安装 NTP 服务？"; then
        check_command "apt"
        apt-get update -qq && apt-get install -y --no-install-recommends systemd-timesyncd || { log "${Red}安装失败！${Font}"; exit 1; }
        
        systemctl enable systemd-timesyncd
        systemctl start systemd-timesyncd

        echo "NTP=$ntp_servers" >> /etc/systemd/timesyncd.conf

        systemctl restart systemd-timesyncd
        timedatectl set-local-rtc 0
        timedatectl set-ntp true

        log "${Green}时间同步配置完成，当前时间状态：${Font}"
        timedatectl status
    fi
}

set_timezone() {
    log "${Green}可用时区列表：${Font}"
    timedatectl list-timezones | grep "$1"

    local timezone
    timezone=$(prompt_input "请输入时区 (例如 Asia/Shanghai): ")
    if [[ $? -ne 0 ]]; then return; fi

    if confirm_action "确定要设置时区为 $timezone？"; then
        timedatectl set-timezone "$timezone" && log "${Green}时区设置为 $timezone${Font}" || log "${Red}时区设置失败！${Font}"
        timedatectl
    fi
}

add_swap() {
    local swapsize
    swapsize=$(prompt_input "请输入需要添加的 swap，建议为内存的 2 倍！ 请输入 swap 数值 (MB): ")
    if [[ $? -ne 0 ]]; then return; fi

    if ! [[ "$swapsize" =~ ^[0-9]+$ ]] || [[ "$swapsize" -le 0 || "$swapsize" -gt 20480 ]]; then
        log "${Red}请输入合理的 swap 大小（建议不超过 20GB）！${Font}"
        return
    fi

    if ! grep -q "$SWAPFILE" "$FSTAB"; then
        log "${Green}swapfile 未发现，正在创建 swapfile${Font}"
        if confirm_action "确定要创建 swapfile？"; then
            dd if=/dev/zero of="$SWAPFILE" bs=1M count="$swapsize" status=progress && \
            chmod 600 "$SWAPFILE" && \
            mkswap "$SWAPFILE" && \
            swapon "$SWAPFILE" || { log "${Red}创建 swap 失败！${Font}"; return 1; }
            echo "$SWAPFILE none swap defaults 0 0" >> "$FSTAB"
            log "${Green}swap 创建成功，信息如下：${Font}"
            swapon --show
            grep Swap /proc/meminfo
        fi
    else
        log "${Red}swapfile 已存在，请先删除现有 swapfile 后再重新设置！${Font}"
    fi
}

del_swap() {
    if grep -q "$SWAPFILE" "$FSTAB"; then
        log "${Green}swapfile 已发现，正在移除...${Font}"
        if confirm_action "确定要删除 swapfile？"; then
            sed -i "/$SWAPFILE/d" "$FSTAB"
            swapoff "$SWAPFILE"
            rm -f "$SWAPFILE"
            log "${Green}swap 已删除！${Font}"
        fi
    else
        log "${Red}swapfile 未发现，无法删除！${Font}"
    fi
}

install_docker() {
    log "${Green}正在安装 Docker...${Font}"
    if confirm_action "确定要安装 Docker？"; then
        check_command "apt"
        apt-get update -qq && apt-get install -y wget vim || { log "${Red}安装失败！${Font}"; exit 1; }
        
        wget -qO- get.docker.com | bash && systemctl start docker && systemctl enable docker || { log "${Red}Docker 安装失败！${Font}"; exit 1; }
        log "${Green}Docker 安装完成，当前版本信息：${Font}"
        docker version
        log "${Green}Docker 运行状态：${Font}"
        systemctl status docker
    fi
}

install_docker_compose() {
    log "${Green}正在安装 Docker Compose...${Font}"

    check_command "curl"
    check_command "chmod"

    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        armv7l) arch="armv7" ;;
        *) 
            log "${Red}不支持的系统架构: $arch${Font}"
            exit 1
            ;;
    esac

    local latest_version="2.28.1"  # 给定一个默认值
    local install_latest
    install_latest=$(prompt_input "是否安装最新版本的 Docker Compose?")
    if [[ $? -ne 0 ]]; then return; fi

    if [[ "$install_latest" =~ ^[yY]$ ]]; then
        latest_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/') || { log "${Red}获取最新版本失败！${Font}"; return; }
        log "${Green}最新版本的 Docker Compose 是 ${latest_version}${Font}"
    else
        local specific_version
        specific_version=$(prompt_input "请输入要安装的 Docker Compose 版本 (例如 1.29.2): ")
        if [[ $? -ne 0 ]]; then return; fi
        latest_version="$specific_version"
    fi

    if confirm_action "确定要安装 Docker Compose 版本 $latest_version？ "; then
        if ! curl -L "https://github.com/docker/compose/releases/download/$latest_version/docker-compose-linux-$arch" -o /usr/local/bin/docker-compose; then
            log "${Red}下载 Docker Compose 失败！${Font}"
            return
        fi
        chmod +x /usr/local/bin/docker-compose

        log "${Green}Docker Compose 安装完成，当前版本信息：${Font}"
        docker-compose --version
    fi
}

main() {

    while true; do
        local num
        check_root
        check_ovz
        clear
        echo -e "———————————————————————————————————————"
        log "${Green}Linux工具箱${Font}"
        log "${Green}1. 添加 swap${Font}"
        log "${Green}2. 删除 swap${Font}"
        log "${Green}3. 安装和配置 NTP 服务${Font}"
        log "${Green}4. 设置时区${Font}"
        log "${Green}5. 安装 Docker${Font}"
        log "${Green}6. 安装 Docker Compose${Font}"
        log "${Green}0. 退出脚本${Font}"
        echo -e "———————————————————————————————————————"
        num=$(prompt_input "请输入数字 [0-6]: ")
        if [[ $? -ne 0 ]]; then continue; fi
        
        case "$num" in
            0) 
                log "${Green}退出脚本。${Font}"
                exit 0 ;;
            1) add_swap ;;
            2) del_swap ;;
            3) setup_ntp ;;
            4) 
                local keyword
                keyword=$(prompt_input "请输入要过滤的时区关键字 (例如 Asia): ")
                if [[ $? -ne 0 ]]; then continue; fi
                set_timezone "$keyword" ;;
            5) install_docker ;;
            6) install_docker_compose ;;
            *)
                log "${Red}请输入正确数字 [0-6]${Font}" ;;
        esac
    done
}

main
