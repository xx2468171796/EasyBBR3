# Change: v2.1.1 Critical Safety & Supply-Chain Fixes

## Why
独立审计发现 6 个 CRITICAL、6 个 HIGH、4 个 MEDIUM 严重性的安全与可靠性缺陷。这些问题可能导致:

1. **远程砖机风险**: `safe_kernel_install` 的回滚路径只是"表演",`update-initramfs`/`grub-mkconfig` 临界区不屏蔽 SIGINT,APT 源切换非原子,任意一个失败时机都可能让用户的 VPS 重启后无法启动。
2. **静默配置丢失**: `backup_config` 不检查 `mkdir`/`cp` 返回值,失败时仍 `return 0`,`write_sysctl` 以为备份成功就直接覆写,导致用户 sysctl 配置不可逆丢失。
3. **供应链信任链空洞**: XanMod 内核 .deb 走明文 HTTP 后 `dpkg -i`,`update_script` 自更新只校验首行 `#!/`,Liquorix 安装器是 `curl | bash`,`install_nexttrace` 二进制无校验。任意一处 MITM 或上游被投毒 = 全量 root RCE。
4. **静默逻辑错误**: `get_current_qdisc` 重复定义导致全局变量 `CURRENT_QDISC` 不再被赋值;`verify_kernel_bbr3` 用 `grep -q "bbr"` 误匹配 `bbr2/bbr3/foobar`;`SC2144` 三处 `[[ -f path/*.ko ]]` 模块检测分支永远不命中。

VPS 用户的核心需求是"一行命令、不砖机、能重启"。这些缺陷直接威胁第一硬约束。

## What Changes

### 防砖优先(最高优先级)
- **backup_config**: `mkdir`/`cp` 失败时返回非零,`write_sysctl` 在备份失败时拒绝写入
- **safe_kernel_install**: 回滚前快照 `/boot` + `/etc/default/grub`;回滚时验证至少一个 known-good 内核仍在 GRUB 中且对应 vmlinuz/initramfs 存在;`update_grub_config` 失败硬终止而非 `|| true`
- **临界区屏蔽 SIGINT**: `update-initramfs`、`grub-mkconfig`、APT 源写入期间 `trap '' INT`,延迟到下个安全检查点
- **APT 源原子写入**: 写到 `${file}.new` → `fsync` → `mv`,移除"先 `rm -rf /var/lib/apt/lists/*` 再切换"的逆序

### 供应链加固
- **XanMod direct download**: `http://` → `https://`,从 Packages 文件解析 `SHA256:` 字段,`sha256sum -c` 校验,失败硬拒绝
- **XanMod GPG key**: 嵌入 fingerprint 常量,`gpg --show-keys --with-fingerprint` 比对,移除 GitHub raw 备用 URL
- **XanMod APT 仓库行**: `http://deb.xanmod.org` → `https://deb.xanmod.org`
- **update_script**: 默认禁用,加 `--allow-unverified-update` 显式开关;后续版本接入 minisign 签名(本 PR 不实现)
- **Liquorix 安装器**: `curl | bash` → 下载到临时文件 → `bash -n` 语法预检 → `bash` 执行,临时文件 `mktemp`
- **install_nexttrace**: pin 到具体 release tag,从 release assets 拉取 `*.sha256`,验证后安装,`mktemp` 替代 `/tmp/nexttrace`
- **_install_kernel_liquorix/elrepo/hwe_core**: 全部 `apt-get install` 检查返回值,任一失败则 `return 1`

### 已知逻辑 bug
- 删除 `easybbr3.sh:6045-6048` 重复的 `get_current_qdisc` 定义;统一所有 `CURRENT_QDISC` 消费方为 `CURRENT_QDISC=$(get_current_qdisc)`
- `verify_kernel_installation` 第 6959 行 `grep -c . || echo 0` → `grep -c -v '^$' || true; pkg_count=${pkg_count:-0}`
- `verify_kernel_bbr3` 第 5127-5132 行 `grep -q "bbr"` → `tr ' ' '\n' | grep -qx "bbr"`
- 三处 `SC2144` `[[ -f path/*.ko ]]` glob bug → `compgen -G` 或 `for f in glob; do [[ -f $f ]] && ...; done`

### 操作安全细节
- `iptables-save > /etc/iptables.rules` → 检测 `/etc/iptables/rules.v4` (Debian) 优先,否则写到 `/etc/iptables.bbr3.rules`,临时文件 + `mv` 原子
- `log_init` 写日志前检查 `[[ ! -L $LOG_FILE ]]` 拒绝符号链接
- 版本号 `2.1.0` → `2.1.1`,头部注释 `VERSION:` 同步

## Impact
- **Affected specs**: 新增 `safety-hardening` capability
- **Affected code**: `easybbr3.sh` — 涉及 ~25 个函数的内部逻辑修改,**零结构变动**(为 v2.2.0 的模块拆分让路)
- **向后兼容**:
  - 默认行为变更: `update_script` 现在拒绝运行(打印 banner 解释如何 opt-in 或手动 `wget`)
  - 默认行为变更: `_install_kernel_liquorix_core` 在 Debian 路径下下载 + 执行(而非 pipe),用户体验等同
  - 静默修复(不改变 happy path 行为): 所有 backup_config / kernel rollback / iptables 路径
- **风险**: 修改集中在错误处理与下载流程,无新增功能,理论上对 happy path 零影响。但作者(Claude)无法在 Linux VPS 上端到端验证内核安装路径,需要人工验证(见 `tasks.md` 的 verification checklist)。

## Out of Scope (deferred to v2.2.0)
- 模块拆分(8 个 lib 文件 + build.sh)
- 性能优化(并行 precheck、缓存 main_iface/nproc)
- die() 全面替换 print_error+exit
- 错误信息加 next step
- 启动时间优化
- shellcheck CI gate
