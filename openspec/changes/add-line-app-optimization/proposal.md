# Change: Add LINE App Optimization Mode

## Why
大陆用户通过 VPN/代理访问 LINE 时，通话质量和文件传输是核心需求。现有的代理模式是通用优化，缺乏针对 LINE 应用特性（实时语音/视频通话、即时消息、文件传输）的专项优化。需要一个独立的应用优化模式，专门针对 LINE 的网络特性进行调优，包括针对 LINE 域名和 IP 的主动/被动优化。

## What Changes
- 新增 `line` 场景模式，与现有场景模式（balanced/communication/video 等）并列
- 针对 LINE 通话优化：低延迟、低抖动、UDP 优先
- 针对 LINE 文件传输优化：稳定吞吐、大文件支持
- 针对 LINE 消息优化：快速响应、小包优化
- **主动优化**：
  - LINE 域名 DNS 预解析和缓存
  - LINE 服务器 IP 预连接/TCP 预热
  - 定时保活连接（减少冷启动延迟）
- **被动优化**：
  - LINE IP 段路由优化（ip route 优先级）
  - LINE 流量 QoS 标记（tc/iptables）
  - conntrack 针对 LINE IP 的专项优化
- 在场景配置菜单中添加 LINE 优化入口
- **兼容性**：与现有代理模式和其他场景模式完全兼容，可叠加使用

## Impact
- Affected specs: 新增 `line-app-optimization` capability
- Affected code: 
  - `easybbr3.sh`: `get_scene_name()`, `get_scene_description()`, `get_scene_params()`, `scene_config_menu()`
  - 新增 `line_proactive_optimize()` 主动优化函数
  - 新增 `line_passive_optimize()` 被动优化函数
  - 新增 LINE 域名/IP 列表配置
- 不影响现有代理模式和其他场景模式

## Technical Context
- LINE 服务器主要在日本/台湾
- 用户场景：大陆设备 → VPN/代理 → 台湾 VPS → LINE 服务器
- 优先级：通话 > 文件传输 > 消息
- LINE 通话使用 UDP，需要优化 UDP 缓冲区和 conntrack

## LINE 域名和 IP 范围
- 主要域名：`*.line.me`, `*.line-scdn.net`, `*.line-apps.com`, `*.naver.jp`
- 主要 IP 段：LINE 使用 Naver 和 AWS 的 IP 段（日本/台湾区域）
- 需要定期更新 IP 列表以保持优化效果
