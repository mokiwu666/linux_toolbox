# Linux Toolbox

一个适用于 **Debian / Ubuntu / CentOS / Rocky / AlmaLinux / Fedora** 等常见 Linux 发行版的交互式运维工具箱脚本。

集成了 **Swap 管理、NTP 配置、时区设置、Docker 安装、WARP 菜单、内核管理、3x-ui 安装、InstallNET DD 重装系统** 等常用功能，适合用于 VPS、云服务器和测试机的快速初始化与日常维护。

---

## 功能特性

- 添加 / 删除 Swap
- 安装并配置 NTP
- 设置系统时区
- 安装 Docker
- 安装 Docker Compose 插件
- 卸载 `virtio_balloon` 模块
- 安装或运行 WARP 菜单
- 运行内核管理脚本
- 安装 3x-ui
- 使用 InstallNET 执行 DD 重装系统
- 查看系统信息

### 增强能力

- 统一交互式菜单
- 支持 `y/yes` 与 `n/no` 输入
- 高危操作二次确认
- 自动环境检查
- 自动记录日志
- 统一远程脚本下载与执行流程
- 自动清理临时文件

---

## 支持环境

### 支持的系统

- Debian
- Ubuntu
- CentOS
- RockyLinux
- AlmaLinux
- Fedora

### 基本要求

- 必须使用 `root` 身份运行
- 需要具备基础网络连接
- 推荐在 **KVM / QEMU** 环境使用
- 使用 WARP 时建议存在 `/dev/net/tun`
- 使用 InstallNET 时建议具备 **VNC / 控制台访问能力**

---

## 快速开始

### 一键运行

```bash
wget https://raw.githubusercontent.com/mokiwu666/linux_toolbox/main/linux_toolbox.sh && bash linux_toolbox.sh
