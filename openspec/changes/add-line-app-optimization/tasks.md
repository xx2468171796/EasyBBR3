# Tasks: Add LINE App Optimization Mode

## 1. Core Implementation
- [x] 1.1 Add `line` mode to `get_scene_name()` function
- [x] 1.2 Add `line` mode to `get_scene_description()` function
- [x] 1.3 Implement `get_line_sysctl_params()` function with LINE-specific sysctl parameters
- [x] 1.4 Add `line` case to `get_scene_params()` function

## 2. Menu Integration
- [x] 2.1 Add LINE optimization entry to `scene_config_menu()` (as option 12)
- [x] 2.2 Update menu choice handling for LINE mode (`line_optimization_menu`)

## 3. LINE-Specific Sysctl Parameters
- [x] 3.1 Implement UDP buffer optimization for voice/video calls (26MB buffers)
- [x] 3.2 Implement low-latency TCP parameters for messaging (tcp_notsent_lowat=8192)
- [x] 3.3 Implement conntrack optimization for connection stability (UDP timeout=30s)
- [x] 3.4 Implement jitter reduction parameters (netdev_budget_usecs=4000)

## 4. Proactive Optimization (主动优化)
- [x] 4.1 Define LINE domain list (LINE_DOMAINS array with 9 domains)
- [x] 4.2 Implement `line_dns_prefetch()` for DNS pre-resolution and caching
- [x] 4.3 Implement `line_tcp_warmup()` for TCP pre-connection to LINE servers
- [x] 4.4 Implement `line_create_keepalive_service()` systemd timer for periodic warmup
- [x] 4.5 Create `/etc/bbr3-line-ips.conf` for IP list management

## 5. Passive Optimization (被动优化)
- [x] 5.1 Implement `line_route_optimize()` for LINE IP route priority (metric 10)
- [x] 5.2 Implement `line_qos_setup()` for traffic marking with iptables (DSCP=EF)
- [x] 5.3 Implement conntrack optimization in `get_line_sysctl_params()` (UDP/TCP timeouts)
- [x] 5.4 Create iptables LINE_QOS chain for traffic prioritization

## 6. LINE IP Management
- [x] 6.1 Create LINE domain list for dynamic IP resolution
- [x] 6.2 Implement DNS-based IP list updates in `line_dns_prefetch()`
- [x] 6.3 Add IP list validation (grep for valid IPv4 format)

## 7. Compatibility
- [x] 7.1 LINE mode uses separate config file (`99-bbr-line.conf`) - coexists with proxy mode
- [x] 7.2 LINE sysctl params are additive, don't conflict with base optimization
- [x] 7.3 Implement `line_remove_optimization()` for complete rollback

## 8. Documentation
- [x] 8.1 Update README.md with LINE optimization mode description
- [x] 8.2 Add inline comments explaining LINE-specific tuning rationale
- [x] 8.3 Document proactive/passive optimization features in README

## 9. Validation
- [x] 9.1 Code review of LINE mode parameter generation
- [x] 9.2 Verified separate config files for coexistence with proxy mode
- [x] 9.3 Code review of DNS prefetch and TCP warmup functions
- [x] 9.4 Code review of QoS and route optimization
- [ ] 9.5 Manual validation on test VPS (pending user testing)
