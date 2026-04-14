# Tasks: v2.1.1 Critical Safety & Supply-Chain Fixes

## 1. Brick-Prevention Fixes (最高优先级)
- [ ] 1.1 `backup_config` (1444): 检查 mkdir/cp 返回值,失败 return 1
- [ ] 1.2 `write_sysctl` (5870): 调用 backup_config 时检查返回值,失败拒绝写入
- [ ] 1.3 `safe_kernel_install` (7300): 安装前快照 /boot 列表 + grub.cfg 内容
- [ ] 1.4 `rollback_kernel_installation` (7243): 移除 `|| true`,失败时显式上报;验证 known-good 内核存在后才删除新内核
- [ ] 1.5 `update_grub_config` (7212): 失败硬终止,不再 `|| true`
- [ ] 1.6 `regenerate_initramfs` (7138): 失败时清理半生成的 initrd
- [ ] 1.7 临界区 trap 屏蔽: `update-initramfs`/`grub-mkconfig`/APT 源切换期间 `trap '' INT TERM`,完成后恢复
- [ ] 1.8 `switch_to_china_apt_sources` (6752) / `switch_to_official_apt_sources` (6698) / `fix_apt_source` (1174): 写到 `${file}.new` → `mv`,绝不 `rm /var/lib/apt/lists/*` 在切换前

## 2. Supply-Chain Hardening
- [ ] 2.1 `download_xanmod_direct` (7387): http→https,parse SHA256 from Packages,sha256sum -c,失败 return 1
- [ ] 2.2 `_install_kernel_xanmod_core` (7559): GPG key 嵌入 fingerprint,gpg --show-keys 比对,失败 return 1
- [ ] 2.3 `_install_kernel_xanmod_core` (7609): APT 源行用 https://
- [ ] 2.4 `_install_kernel_xanmod_core` (7586): 移除 GitHub raw 备用 key URL
- [ ] 2.5 `_install_kernel_liquorix_core` (7785): 检查 apt-get install 返回值;Debian 路径 curl|bash → 下载到 mktemp 后 bash -n + bash
- [ ] 2.6 `_install_kernel_elrepo_core` (7829): 检查所有 yum/rpm 返回值
- [ ] 2.7 `_install_kernel_hwe_core` (7881): 检查所有 apt-get 返回值
- [ ] 2.8 `install_nexttrace` (2803): pin tag,fetch sha256,verify,mktemp
- [ ] 2.9 `update_script` (8358): 默认禁用,需 `--allow-unverified-update` 才执行;打印 banner 解释为何禁用 + 手动 wget 命令

## 3. Logic Bugs
- [ ] 3.1 删除重复的 `get_current_qdisc` (6045-6048),保留 6278 的版本
- [ ] 3.2 grep 所有 CURRENT_QDISC 消费点,改成 `CURRENT_QDISC=$(get_current_qdisc)`
- [ ] 3.3 `verify_kernel_installation` (6959): pkg_count grep -c bug
- [ ] 3.4 `verify_kernel_bbr3` (5127-5132): 子串误匹配 → 词边界
- [ ] 3.5 `qdisc_supported` 附近 SC2144: `[[ -f path/*.ko ]]` × 3 处(6299, 6307, 7179)
- [ ] 3.6 `iptables-save` (1786): 路径检测 + 临时文件 + mv

## 4. Operational Safety
- [ ] 4.1 `log_init` (459): 拒绝符号链接
- [ ] 4.2 `safe_run` (563): 重命名为 `ignore_errors` (保留旧名作 alias 以兼容)
- [ ] 4.3 SCRIPT_VERSION → 2.1.1 (line 48)
- [ ] 4.4 头部注释 VERSION → 2.1.1 (line 15)
- [ ] 4.5 头部注释 REVISION → 当前日期

## 5. Validation
- [ ] 5.1 `bash -n easybbr3.sh` 通过
- [ ] 5.2 `shellcheck -S error easybbr3.sh` 0 errors
- [ ] 5.3 `shellcheck -S warning easybbr3.sh` warning 数不增加
- [ ] 5.4 手动 review 每处改动的上下文(确认未引入回归)
- [ ] 5.5 在 mock 环境运行 backup_config / write_sysctl 的 happy/sad path
- [ ] 5.6 写 CHANGELOG-v2.1.1.md
- [ ] 5.7 提交 + 推送分支 + 开 PR(不直接 merge main)

## Verification on Real Linux (人工验证清单 - 给用户)
**作者无法在 macOS 上验证以下场景,merge 前请在测试 VPS 上跑:**
- [ ] V1 Debian 12 全新机器: `./easybbr3.sh --install-kernel xanmod --non-interactive`,验证内核安装、GPG fingerprint 校验、SHA256 校验、reboot 后 `uname -r` 显示 xanmod
- [ ] V2 故意制造失败: 修改脚本让 `dpkg -i` 失败,确认 rollback 真的恢复了 /boot,且 `ls /boot/vmlinuz-*` 仍包含原内核
- [ ] V3 Ctrl-C 测试: 在 `update-initramfs` 跑到一半时按 Ctrl-C,确认提示"操作正在进行中,无法中断",而非中断
- [ ] V4 APT 源切换: `--switch-mirror china` 后立即 `apt update`,确认成功;再 `--switch-mirror official` 同样
- [ ] V5 sysctl 备份目录不可写: `chmod 555 /etc/sysctl.d/bbr-backups`,运行脚本应明确报错"无法创建备份目录"而非静默继续
- [ ] V6 第二次运行幂等性: 完整跑一遍后再跑一遍,/etc/sysctl.d/99-bbr.conf 内容应一致,/etc/iptables.bbr3.rules 不应有重复规则
- [ ] V7 update_script: 默认运行应拒绝并打印 banner;加 `--allow-unverified-update` 后才执行
