# Linux 工具箱 Pro Final

一个面向 **Debian / Ubuntu / CentOS / Rocky / AlmaLinux / Fedora** 等常见 Linux 发行版的交互式运维工具箱脚本。

该脚本集成了 **Swap 管理、NTP 配置、时区设置、Docker 安装、Docker Compose 安装、WARP 菜单、内核管理、3x-ui 安装、virtio_balloon 模块卸载、InstallNET DD 重装系统** 等常用功能，并加入了 **执行前环境检查、统一日志记录、yes/no 输入优化、高危操作二次确认** 等增强能力。

---

## 功能简介

本工具箱适合用于 VPS、云服务器、测试机等 Linux 环境的基础维护与快速初始化。

### 已集成功能

- 添加 Swap
- 删除 Swap
- 安装和配置 NTP（Google NTP / 阿里云 NTP）
- 设置系统时区
- 安装 Docker
- 安装 Docker Compose 插件
- 卸载 `virtio_balloon` 模块
- 安装或运行 WARP 菜单脚本
- 运行内核管理脚本
- 安装 3x-ui
- 使用 InstallNET 执行 DD/网络重装系统
- 查看系统信息与环境检查摘要

### 增强特性

- 支持 `yes / y / no / n` 交互输入
- 高危操作增加单独确认
- InstallNET 密码必须手动输入，且隐藏回显、二次确认
- 在执行 WARP / 内核 / InstallNET 前自动进行环境检查
- 自动记录日志到本地文件
- 统一远程脚本下载与执行流程
- 自动清理临时文件

---

## 适用环境

### 支持的系统

理论上适用于以下主流发行版：

- Debian
- Ubuntu
- CentOS
- RockyLinux
- AlmaLinux
- Fedora

### 基本要求

- 必须使用 `root` 身份运行
- 系统中需要具备基本网络连接能力
- 推荐在 KVM / QEMU 虚拟化环境下使用
- 若执行 WARP，建议存在 `/dev/net/tun`
- 若执行 InstallNET，建议具备 VNC / 控制台访问能力

---

## 快速开始

### 1. 下载脚本

```bash
wget -O toolbox.sh <你的脚本地址>
chmod +x toolbox.sh
```

或者：

```bash
curl -fsSL <你的脚本地址> -o toolbox.sh
chmod +x toolbox.sh
```

### 2. 运行脚本

```bash
bash toolbox.sh
```

或者：

```bash
./toolbox.sh
```

---

## 菜单功能说明

运行脚本后，会显示类似如下菜单：

```text
1. 添加 Swap
2. 删除 Swap
3. 安装和配置 NTP
4. 设置时区
5. 安装 Docker
6. 安装 Docker Compose 插件
7. 卸载 virtio_balloon 模块
8. DD 重装系统（InstallNET，可自主选择）
9. 安装 WARP 菜单
10. 运行内核管理脚本
11. 安装 3x-ui
12. 查看系统信息
0. 退出脚本
```

### 1）添加 Swap

用于为系统创建新的 `/swapfile` 交换分区文件。

特点：

- 支持输入自定义大小（单位 MB）
- 自动检查是否已存在 `/swapfile`
- 优先使用 `fallocate`，失败后回退到 `dd`
- 自动写入 `/etc/fstab`

适用场景：

- 小内存 VPS 扩展可用交换空间
- 编译、安装大型程序时避免内存不足

---

### 2）删除 Swap

用于关闭并删除 `/swapfile`。

特点：

- 自动执行 `swapoff`
- 自动移除 `/etc/fstab` 中对应条目
- 自动删除交换文件

---

### 3）安装和配置 NTP

用于启用系统时间同步，并配置时间服务器。

支持两种预设：

- Google NTP（海外）
- 阿里云 NTP（国内）

特点：

- 自动安装 `systemd-timesyncd`
- 自动修改 `/etc/systemd/timesyncd.conf`
- 避免重复追加 NTP 配置
- 自动重启同步服务

---

### 4）设置时区

用于设置系统时区，例如：

- `Asia/Shanghai`
- `Asia/Tokyo`
- `America/Los_Angeles`

特点：

- 支持先按关键字过滤时区
- 自动校验时区是否合法

---

### 5）安装 Docker

使用官方仓库安装 Docker。

特点：

- Debian / Ubuntu 使用官方 apt 仓库
- CentOS / Rocky / AlmaLinux / Fedora 使用官方 yum/dnf 仓库
- 自动安装：
  - `docker-ce`
  - `docker-ce-cli`
  - `containerd.io`
  - `docker-buildx-plugin`
  - `docker-compose-plugin`
- 安装后自动启动并设置开机自启

---

### 6）安装 Docker Compose 插件

用于安装 Docker 官方 Compose 插件。

说明：

- 优先使用 `docker compose`
- 若系统已存在旧版 `docker-compose`，脚本会进行兼容检测

---

### 7）卸载 virtio_balloon 模块

用于尝试卸载 `virtio_balloon` 内核模块。

说明：

- 适用于某些 VPS 场景中关闭气球内存功能
- 执行前会提示风险
- 若模块未加载，会直接提示并退出

风险提示：

- 某些虚拟化平台依赖此模块，卸载后可能影响内存管理机制

---

### 8）DD 重装系统（InstallNET）

这是脚本中最危险的功能之一。

它会调用 `leitbogioro/Tools` 项目的 `InstallNET.sh`，实现通过网络方式重装系统。

支持从菜单中选择目标系统，包括但不限于：

- Debian
- Ubuntu
- Kali
- AlpineLinux
- CentOS
- RockyLinux
- AlmaLinux
- Fedora
- Windows

特点：

- 可自主选择系统与版本
- 密码必须手动输入
- 密码隐藏显示
- 需要输入两次确认一致
- 可选指定 SSH 端口
- 可选指定镜像源
- 执行前自动进行环境检查
- 执行前显示参数预览
- 最后需再次手动确认 `yes`

强烈建议：

- 先备份所有重要数据
- 确保拥有 VNC / 控制台访问权限
- 在 KVM / QEMU 环境中使用更稳妥

---

### 9）安装 WARP 菜单

用于执行第三方 WARP 管理菜单脚本。

执行前会检查：

- 是否存在默认网卡
- 是否存在 `/dev/net/tun`
- 当前系统基础网络是否正常

说明：

- 如果未检测到 `/dev/net/tun`，脚本会警告并询问是否继续

---

### 10）运行内核管理脚本

用于执行第三方内核升级/切换脚本。

执行前会检查：

- 当前虚拟化环境
- 当前是否为 KVM / QEMU
- 是否存在 systemd
- 当前网络基本状态

风险提示：

- 更换内核后通常需要重启
- 可能影响网卡驱动、磁盘驱动或兼容性
- 在非 KVM 环境下请谨慎使用

---

### 11）安装 3x-ui

用于执行第三方 3x-ui 安装脚本。

特点：

- 使用统一远程脚本下载函数
- 安装前会要求手动确认

---

### 12）查看系统信息

用于查看当前主机的系统摘要。

显示内容包括：

- 系统版本
- 内核版本
- 虚拟化类型
- 是否为 KVM / QEMU
- 是否启用 systemd
- 是否存在 TUN 设备
- 默认网卡
- IPv4 / IPv6 地址
- 默认网关
- 内存 / Swap 信息
- Docker / Compose 版本信息

---

## 环境检查说明

在执行以下功能前，脚本会自动做环境检查：

- WARP
- 内核管理脚本
- InstallNET

检查内容包括：

- 虚拟化类型
- 是否 KVM / QEMU
- 是否存在 `/dev/net/tun`
- 当前内核版本
- 当前发行版
- 是否启用 systemd
- 默认网卡名
- IPv4 地址
- IPv6 地址
- 默认路由网关

这样可以帮助你提前判断目标环境是否适合执行相关操作。

---

## yes/no 输入说明

脚本中的确认提示统一支持以下输入：

- `y`
- `yes`
- `n`
- `no`

特点：

- 不区分大小写
- 输入非法内容会重复提示
- 部分高危操作默认值为 `no`

示例：

```text
确定继续安装 Docker 吗？ [y/N]
```

可输入：

```text
y
```

或者：

```text
yes
```

---

## InstallNET 使用说明

### 使用流程

选择菜单项：

```text
8. DD 重装系统（InstallNET，可自主选择）
```

然后依次完成：

1. 读取环境检查摘要
2. 选择目标系统
3. 输入目标版本
4. 输入新系统密码（隐藏输入）
5. 再次输入密码确认
6. 可选输入 SSH 端口
7. 可选输入镜像源
8. 查看参数预览
9. 最终输入 `yes` 确认执行

### 支持的系统示例

- Debian 12
- Ubuntu 22.04
- Kali rolling
- Alpine edge
- RockyLinux 9
- AlmaLinux 9
- Fedora 43
- Windows 11

### 注意事项

- Ubuntu 在上游项目中存在原生安装限制，22.04+ 需要特别谨慎
- Windows 重装后更依赖 VNC / 控制台进行排障
- 非 KVM 环境下使用 DD 风险更高

---

## 日志说明

脚本会记录运行日志到：

```bash
/var/log/linux-toolbox.log
```

日志内容包括：

- 普通信息
- 警告信息
- 错误信息
- 执行失败的命令与行号

适合用于后续排障和审计。

---

## 风险提示

以下功能属于高风险操作，请务必谨慎：

- 卸载 `virtio_balloon`
- 运行内核管理脚本
- InstallNET DD 重装系统

使用这些功能前，请确保：

- 已备份重要数据
- 已确认服务器支持当前操作
- 具备控制台 / VNC / 救援模式访问能力
- 知道如何在网络异常或启动失败时恢复系统

---

## 常见使用场景

### 小内存服务器扩容 Swap

适合：

- 512MB / 1GB VPS
- 编译程序时内存不足
- Docker 容器运行时容易 OOM

推荐操作：

- 菜单 1：添加 Swap

---

### 国内服务器同步时间

适合：

- 中国大陆地区 VPS
- 希望使用国内时间源

推荐操作：

- 菜单 3：配置 NTP
- 选择阿里云 NTP

---

### 初始化 Docker 环境

适合：

- 新服务器部署容器环境

推荐操作：

- 菜单 5：安装 Docker
- 菜单 6：安装 Docker Compose 插件

---

### 更换系统

适合：

- VPS 当前系统损坏
- 需要快速更换为 Debian / RockyLinux / Windows 等

推荐操作：

- 菜单 8：DD 重装系统

前提：

- 一定要有 VNC / 控制台
- 一定要确认数据已备份

---

## 免责声明

本脚本集成了多个第三方脚本与系统级操作能力。

请在了解功能与风险后自行使用。因误操作、环境不兼容、第三方脚本异常、网络故障、内核切换失败、重装失败等造成的数据丢失、系统损坏、服务中断等问题，使用者需自行承担风险。

---

## 后续可扩展方向

如果你打算继续增强该项目，建议后续加入：

- 二级菜单（普通功能 / 高危功能分离）
- 命令行参数模式（非交互执行）
- 卸载 Docker
- 一键开启 BBR
- 防火墙基础配置
- SSH 端口修改
- Fail2ban 安装
- 一键系统更新
- GitHub Actions 自动发布

---

## 致谢

本脚本部分功能依赖或调用了以下项目：

- leitbogioro/Tools
- fscarmen/warp
- kernel 管理脚本项目
- mhsanaei/3x-ui

感谢相关项目作者提供的开源工具与脚本。


运行命令：
wget https://raw.githubusercontent.com/mokiwu666/linux_toolbox/main/linux_toolbox.sh && bash linux_toolbox.sh
