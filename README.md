<div align="center">

# 🚀 EasyBBR3 - BBR3 一键安装脚本

[![GitHub](https://img.shields.io/badge/GitHub-xx2468171796-blue?logo=github)](https://github.com/xx2468171796)
[![Telegram](https://img.shields.io/badge/Telegram-加入群组-blue?logo=telegram)](https://t.me/+RZMe7fnvvUg1OWJl)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.1.0-orange.svg)](https://github.com/xx2468171796/EasyBBR3)
[![Stars](https://img.shields.io/github/stars/xx2468171796/EasyBBR3?style=social)](https://github.com/xx2468171796/EasyBBR3)

**一键安装 BBR/BBR2/BBR3 TCP 拥塞控制算法，支持多种场景优化模式**

[📱 加入电报群](https://t.me/+RZMe7fnvvUg1OWJl) · [🐛 问题反馈](https://github.com/xx2468171796/EasyBBR3/issues) · [⭐ 给个 Star](https://github.com/xx2468171796/EasyBBR3)

</div>

---

## 👨‍💻 作者信息

| 项目 | 信息 |
|------|------|
| **作者** | 孤独制作 |
| **电报群** | [https://t.me/+RZMe7fnvvUg1OWJl](https://t.me/+RZMe7fnvvUg1OWJl) |
| **GitHub** | [https://github.com/xx2468171796](https://github.com/xx2468171796) |

> 💬 **遇到问题？** 欢迎加入电报群交流讨论，获取最新更新和技术支持！

## ✨ 功能特点

- 🎯 **智能检测** - 自动检测系统环境、内核版本、带宽/RTT、最佳算法
- 🔧 **场景优化** - 7种预设场景模式（代理/视频/游戏/并发等）
- 📦 **内核安装** - 支持 XanMod/Liquorix/ELRepo/HWE 内核一键安装
- 🛡️ **安全机制** - 内核安装验证、自动回滚、配置备份恢复
- 🌏 **国内优化** - 自动检测网络环境，智能切换镜像源
- 💻 **多系统支持** - Debian/Ubuntu/CentOS/RHEL/Rocky/AlmaLinux
- ⏰ **时间自动优化** - 晚高峰自动切换激进模式（19:00-23:00）
- 🔄 **一键更新** - 从 GitHub 自动下载最新版本

## 📋 支持的系统

| 系统 | 版本 |
|------|------|
| Debian | 10, 11, 12, 13 |
| Ubuntu | 16.04, 18.04, 20.04, 22.04, 24.04 |
| CentOS/RHEL | 7, 8, 9 |
| Rocky/AlmaLinux | 8, 9 |

## 🚀 快速开始

### 一键运行

```bash
# 方式一：wget
wget -qO- https://raw.githubusercontent.com/xx2468171796/EasyBBR3/main/easybbr3.sh | sudo bash

# 方式二：curl
curl -fsSL https://raw.githubusercontent.com/xx2468171796/EasyBBR3/main/easybbr3.sh | sudo bash
```

### 下载后运行

```bash
wget https://raw.githubusercontent.com/xx2468171796/EasyBBR3/main/easybbr3.sh
chmod +x easybbr3.sh
./easybbr3.sh
```

### 安装快捷命令

```bash
./easybbr3.sh --install
# 之后可直接使用 bbr3 命令
bbr3
```

## 📖 使用说明

### 交互式菜单

运行脚本后会显示交互式菜单：

```
1) 代理智能调优 (推荐翻墙用户！含一键自动优化) ⭐
2) 安装新内核 (获取BBR3支持)
3) 验证优化状态 (检测优化是否生效)
4) 查看当前状态
5) 备份/恢复配置
6) 时间自动优化 (晚高峰自动切换激进模式)
7) 卸载配置
8) 安装快捷命令 bbr3
9) 更新脚本 (从 GitHub 获取最新版本)
10) PVE Tools 一键脚本
0) 返回/退出
```

### 命令行参数

```bash
# 查看状态
sudo bbr3 --status

# 直接启用 BBR3
sudo bbr3 --algo bbr3 --apply

# 自动优化
sudo bbr3 --auto

# 代理智能调优向导（推荐翻墙用户）
sudo bbr3 --proxy-tune

# 验证优化是否生效
sudo bbr3 --verify

# 查看健康评分
sudo bbr3 --health

# 安装 XanMod 内核
sudo bbr3 --install-kernel xanmod

# 使用国内镜像安装内核
sudo bbr3 --mirror tsinghua --install-kernel xanmod

# 查看帮助
sudo bbr3 --help
```

## 🎯 场景模式说明

| 模式 | 适用场景 | 特点 |
|------|----------|------|
| 均衡模式 | 一般用途 | 平衡延迟与吞吐量 |
| 通信模式 | 实时通信/游戏/SSH | 优化低延迟 |
| 视频模式 | 视频流/下载服务 | 优化大文件传输 |
| 并发模式 | Web服务器/API | 优化高并发连接 |
| 极速模式 | 大带宽服务器 | 最大化吞吐量 |
| 性能模式 | 高性能计算/数据库 | 全面性能优化 |
| **代理模式** | **VPS代理/VPN** | **抗丢包、低延迟、快速重连** |

### 🔥 代理智能调优向导（推荐 VPS 使用）

**10 步智能向导**，根据您的具体需求生成最优配置：

1. 硬件检测（自动评分）
2. 内核检测（BBR3 可用性）
3. 链路架构（单机/中转/落地）
4. 服务器位置
5. 客户端位置
6. 线路类型（CN2/CMI/9929 等）
7. 代理内核（Xray/Sing-box 等）
8. 代理协议（VLESS/Hysteria 等）
9. 资源分配
10. 高级优化选项

支持的代理协议：
- **TCP 协议**：VLESS / VMess / Trojan / Shadowsocks / Naive
- **UDP 协议**：Hysteria / TUIC
- **透明代理**：Tun / TProxy

核心优化：
- ✅ 抗丢包：BBR3 对丢包不敏感，跨国线路更稳定
- ✅ 低延迟：优化 TCP 参数减少响应时间
- ✅ 快速重连：禁用慢启动，断线重连更快
- ✅ TFO 加速：TCP Fast Open 减少握手延迟
- ✅ 低配优化：针对小内存 VPS 的激进优化模式
- ✅ 连接保活：TCP Keepalive 60秒探测，保持连接活跃
- ✅ 高并发：conntrack/SYN队列/端口范围优化
- ✅ 路由缓存：扩大路由表容量，加速连接建立

### ⏰ 时间自动优化

晚高峰自动切换激进模式，提升翻墙体验：

```bash
# 在主菜单选择「时间自动优化」启用
```

时段设置：
- **晚高峰 (19:00-02:00)**：128MB 缓冲区、131072 队列（翻倍）
- **非高峰 (02:00-19:00)**：64MB 缓冲区、65535 队列（标准）

工作原理：
- Cron 定时任务每小时检查
- 自动切换配置，无需手动干预
- 不影响其他优化参数（Keepalive/conntrack 等）

### 📊 带宽检测

代理智能调优支持**用户手动输入带宽**（优先）或自动检测：

- 手动输入更准确，推荐使用
- 自动检测支持：ethtool 网卡速率 → sysfs → speedtest-cli → curl 测速

### ✅ 优化验证系统

确保您的优化真正生效：

```bash
sudo bbr3 --verify    # 完整验证报告
sudo bbr3 --health    # 健康评分 (0-100)
```

验证项目：
- 内核状态（BBR3 是否启用）
- 拥塞控制算法
- 队列调度规则
- 缓冲区设置
- TCP 参数
- 系统服务状态

## 📝 常见问题

### Q: 需要重启吗？
- **sysctl 参数**：不需要，立即生效
- **安装新内核**：需要重启才能使用新内核

### Q: 场景配置和自动优化有什么区别？
- **场景配置**：根据使用场景预设优化参数，更全面
- **自动优化**：根据网络 RTT 和带宽自动计算参数
- 两者选一个用即可，后执行的会覆盖前者

### Q: 如何回滚配置？
使用菜单中的「备份/恢复配置」功能，或手动删除配置文件：
```bash
sudo rm /etc/sysctl.d/99-bbr.conf
sudo sysctl --system
```

## 🔗 其他工具

### PVE Tools 一键脚本

Proxmox VE 优化工具，支持换源、去订阅提示等功能：

```bash
wget https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh
chmod +x pvetools.sh
./pvetools.sh
```

项目地址：[https://github.com/xx2468171796/pvetools](https://github.com/xx2468171796/pvetools)

---

## 📞 联系方式 & 技术支持

<div align="center">

### 🔥 加入我们的电报群，获取最新更新和技术支持！

[![Telegram Group](https://img.shields.io/badge/Telegram-加入群组-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/+RZMe7fnvvUg1OWJl)

</div>

| 联系方式 | 链接 |
|----------|------|
| 👤 **作者** | 孤独制作 |
| 📱 **电报群** | [https://t.me/+RZMe7fnvvUg1OWJl](https://t.me/+RZMe7fnvvUg1OWJl) |
| 🐙 **GitHub** | [https://github.com/xx2468171796](https://github.com/xx2468171796) |
| 📧 **问题反馈** | [GitHub Issues](https://github.com/xx2468171796/EasyBBR3/issues) |

> 💡 **提示**：在电报群可以获得更快速的技术支持，以及第一时间获取脚本更新通知！

---

## ⭐ 支持项目

如果这个项目对你有帮助，请给个 **Star ⭐** 支持一下！

您的支持是我持续更新的动力！🙏

[![Star History Chart](https://api.star-history.com/svg?repos=xx2468171796/EasyBBR3&type=Date)](https://star-history.com/#xx2468171796/EasyBBR3&Date)

---

## 📄 License

MIT License - 详见 [LICENSE](LICENSE) 文件

---

<div align="center">

**Made with ❤️ by 孤独制作**

[⬆ 回到顶部](#-easybbr3---bbr3-一键安装脚本)

</div>
