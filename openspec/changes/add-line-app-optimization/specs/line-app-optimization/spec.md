## ADDED Requirements

### Requirement: LINE App Optimization Mode
The system SHALL provide a dedicated LINE application optimization mode that optimizes network parameters for LINE voice/video calls, messaging, and file transfers.

#### Scenario: User selects LINE optimization mode
- **WHEN** user selects LINE optimization mode from the scene configuration menu
- **THEN** the system applies LINE-specific sysctl parameters optimized for:
  - Low-latency voice/video calls (UDP optimization)
  - Fast message delivery (small packet optimization)
  - Stable file transfers (throughput optimization)

#### Scenario: LINE mode coexists with proxy mode
- **WHEN** user has previously applied proxy optimization
- **AND** user applies LINE optimization mode
- **THEN** LINE-specific parameters are applied without removing proxy-specific parameters
- **AND** overlapping parameters use LINE-optimized values

### Requirement: LINE Voice/Video Call Optimization
The system SHALL optimize UDP and real-time communication parameters for LINE voice and video calls.

#### Scenario: UDP buffer optimization for calls
- **WHEN** LINE optimization mode is applied
- **THEN** UDP receive/send buffers are set to values suitable for real-time audio/video (e.g., 26214400 bytes)
- **AND** conntrack UDP timeout is reduced to improve connection responsiveness

#### Scenario: Jitter reduction for calls
- **WHEN** LINE optimization mode is applied
- **THEN** network queue parameters are tuned to minimize jitter
- **AND** TCP timestamps and SACK are enabled for better packet ordering

### Requirement: LINE File Transfer Optimization
The system SHALL optimize TCP parameters for stable and fast file transfers in LINE.

#### Scenario: Large file upload/download
- **WHEN** LINE optimization mode is applied
- **THEN** TCP buffer sizes support efficient large file transfers
- **AND** TCP window scaling is enabled
- **AND** tcp_notsent_lowat is set for responsive uploads

### Requirement: LINE Message Optimization
The system SHALL optimize parameters for fast and reliable message delivery.

#### Scenario: Small packet optimization
- **WHEN** LINE optimization mode is applied
- **THEN** TCP_NODELAY behavior is optimized for small packets
- **AND** TCP Fast Open is enabled for quick connection establishment
- **AND** tcp_slow_start_after_idle is disabled for consistent performance

### Requirement: LINE Proactive Optimization
The system SHALL provide proactive optimization features that pre-warm connections to LINE servers.

#### Scenario: DNS pre-resolution
- **WHEN** LINE proactive optimization is enabled
- **THEN** the system periodically resolves LINE domain names (*.line.me, *.line-scdn.net, *.line-apps.com, *.naver.jp)
- **AND** caches the resolved IP addresses for faster connection establishment

#### Scenario: TCP connection warmup
- **WHEN** LINE proactive optimization is enabled
- **THEN** the system establishes and maintains warm TCP connections to LINE servers
- **AND** reduces cold-start latency for LINE app connections

#### Scenario: Keepalive service
- **WHEN** LINE proactive optimization is enabled
- **THEN** a systemd service periodically refreshes DNS cache and TCP connections
- **AND** the service can be enabled/disabled independently

### Requirement: LINE Passive Optimization
The system SHALL provide passive optimization features that prioritize LINE traffic.

#### Scenario: Route optimization for LINE IPs
- **WHEN** LINE passive optimization is enabled
- **THEN** the system configures optimized routes for known LINE IP ranges
- **AND** LINE traffic uses lower latency routing when available

#### Scenario: QoS traffic marking
- **WHEN** LINE passive optimization is enabled
- **THEN** the system marks LINE traffic with appropriate DSCP values using iptables
- **AND** tc qdisc prioritizes marked LINE traffic

#### Scenario: Conntrack optimization for LINE
- **WHEN** LINE passive optimization is enabled
- **THEN** conntrack timeouts are optimized specifically for LINE IP ranges
- **AND** UDP conntrack entries for LINE have shorter timeouts for faster cleanup

### Requirement: LINE Domain and IP Management
The system SHALL maintain a configurable list of LINE domains and IP ranges.

#### Scenario: Domain list configuration
- **WHEN** LINE optimization is configured
- **THEN** the system reads LINE domains from /etc/bbr3-line-domains.conf
- **AND** supports wildcard domain patterns (*.line.me)

#### Scenario: IP list updates
- **WHEN** user requests IP list update
- **THEN** the system resolves current LINE domains to IP addresses
- **AND** updates the internal IP list for route and QoS optimization

### Requirement: LINE Mode Menu Entry
The system SHALL provide a menu entry for LINE optimization in the scene configuration menu.

#### Scenario: Menu display
- **WHEN** user opens scene configuration menu
- **THEN** LINE optimization mode is displayed as a selectable option
- **AND** description indicates it is optimized for LINE calls and file transfers

#### Scenario: Menu selection
- **WHEN** user selects LINE optimization option
- **THEN** system displays LINE-specific parameter summary
- **AND** prompts for confirmation before applying
- **AND** offers sub-options for proactive and passive optimization
