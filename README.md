# BBR3 一键安装脚本

[![GitHub](https://img.shields.io/badge/GitHub-xx2468171796-blue?logo=github)](https://github.com/xx2468171796)
[![Telegram](https://img.shields.io/badge/Telegram-加入群组-blue?logo=telegram)](https://t.me/+RZMe7fnvvUg1OWJl)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> 🚀 一键安装 BBR/BBR2/BBR3 TCP 拥塞控制算法，支持多种场景优化模式
>
> 作者：**孤独制作** | 电报群：[https://t.me/+RZMe7fnvvUg1OWJl](https://t.me/+RZMe7fnvvUg1OWJl)

## ✨ 功能特点

- 🎯 **智能检测** - 自动检测系统环境、内核版本、最佳算法
- 🔧 **场景优化** - 7种预设场景模式（代理/视频/游戏/并发等）
- 📦 **内核安装** - 支持 XanMod/Liquorix/ELRepo/HWE 内核一键安装
- 🛡️ **安全机制** - 内核安装验证、自动回滚、配置备份恢复
- 🌏 **国内优化** - 自动检测网络环境，智能切换镜像源
- 💻 **多系统支持** - Debian/Ubuntu/CentOS/RHEL/Rocky/AlmaLinux

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
wget  https://github.com/xx2468171796/EasyBBR3/blob/main/easybbr3.sh
chmod +x easybbr3.sh
./easybbr3.sh
```

### 下载后运行

```bash
wget https://raw.githubusercontent.com/xx2468171796/bbr3/main/bbr.sh
chmod +x bbr.sh
sudo ./bbr.sh
```

### 安装快捷命令

```bash
sudo ./bbr.sh --install
# 之后可直接使用 bbr3 命令
bbr3
```

## 📖 使用说明

### 交互式菜单

运行脚本后会显示交互式菜单：

```
1) 查看当前状态
2) 启用 BBR (推荐)
3) 启用 BBR2
4) 启用 BBR3
5) 场景配置 (按用途优化，推荐VPS代理使用)
6) 自动优化配置 (按网络环境自动调参)
7) 安装新内核
8) 备份/恢复配置
9) 卸载配置
10) 安装快捷命令 bbr3
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

### 🔥 代理模式（推荐 VPS 使用）

专为代理/VPN 场景优化，适用于：
- V2Ray / Xray / Trojan / Trojan-Go
- Shadowsocks / ShadowsocksR / Clash
- WireGuard / OpenVPN / IPsec
- Hysteria / TUIC / NaiveProxy

核心优化：
- ✅ 抗丢包：BBR3 对丢包不敏感，跨国线路更稳定
- ✅ 低延迟：优化 TCP 参数减少响应时间
- ✅ 快速重连：禁用慢启动，断线重连更快
- ✅ TFO 加速：TCP Fast Open 减少握手延迟

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

## 📞 联系方式

- **作者**：孤独制作
- **电报群**：[https://t.me/+RZMe7fnvvUg1OWJl](https://t.me/+RZMe7fnvvUg1OWJl)
- **GitHub**：[https://github.com/xx2468171796](https://github.com/xx2468171796)

## ⭐ Star History

如果这个项目对你有帮助，请给个 Star ⭐ 支持一下！

## 📄 License

MIT License - 详见 [LICENSE](LICENSE) 文件
