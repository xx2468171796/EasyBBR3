# CHANGELOG — v2.1.1 关键安全修复

发布日期: 2026-04-14
分支: `fix/v2.1.1-critical-fixes`

本次发布是一组**纯修复版本**,零结构变动,聚焦"防砖"和"供应链信任链"两条主线。
不引入新功能,不重构。模块化拆分(8 个 lib + build.sh)与性能优化推迟到 v2.2.0。

## 修复优先级

按"砖机风险"从高到低排序。**强烈建议升级**——本次修复中至少 4 个 bug 在某些时机下
会让用户的 VPS 重启后无法启动。

---

## 防砖相关 (CRITICAL)

### 1. `safe_kernel_install` 回滚不再是表演 (H3 + H5)
**原状**: 失败回滚使用 `apt-get remove ... || true` 吞错,`update_grub_config || true`
静默失败,回滚后 GRUB 可能仍指向已删除的内核 → 重启进 GRUB rescue。Ctrl-C 落在
`update-initramfs` 或 `grub-mkconfig` 中途留下半生成文件 → 同样可能 panic。

**修复**:
- 新增 `record_kernel_list_before` 完整快照: `/etc/default/grub`、`/boot/vmlinuz-*` 列表、`uname -r`
- 新增 `verify_known_good_kernel_present`: 回滚前必须确认有 known-good 内核(优先运行中的)
  且其 vmlinuz + initramfs 都还在 /boot 上
- 拒绝移除当前正在运行的内核(防御性检查)
- `update_grub_config` 失败现在是硬终止,打印恢复步骤(`update-grub`/`grub2-mkconfig` 命令)
- 移除所有回滚路径中的 `|| true` 假成功
- 新增 `critical_section_enter` / `critical_section_exit`: 在 `update-initramfs`、
  `grub-mkconfig`、APT sources.list 写入期间屏蔽 SIGINT/SIGTERM

### 2. APT 源切换非原子写入 (H4)
**原状**: `switch_to_china_apt_sources`、`switch_to_official_apt_sources`、`fix_apt_source`
均直接 `cat > /etc/apt/sources.list << EOF`。Ctrl-C/OOM/断电打断 = 半行写入 = `apt update`
直接报错 = 用户从此无法装安全更新,需要手动登录修复。

**修复**:
- 新增 `_atomic_replace_apt_sources` 助手: 写到 `${file}.new` 后 `mv -f` 原子替换
- 写入临界区屏蔽 SIGINT/SIGTERM
- `fix_apt_source` 不再先 `rm -rf /var/lib/apt/lists/*` 再切换(逆序操作),改为只 `apt-get clean`
  保留 lists/ 直到新源验证通过
- 失败时同样在临界区内 cp 恢复 backup

### 3. `backup_config` 静默丢失用户配置 (C5)
**原状**: `mkdir -p` 和 `cp` 均不检查返回值,函数无条件 `return 0`,`write_sysctl` 以为
备份成功后直接覆写 `/etc/sysctl.d/99-bbr.conf` → 用户原配置不可逆丢失。

**修复**:
- `backup_config`: `mkdir`/`cp` 失败均 `return 1` + 明确报错
- `write_sysctl`: 调用 `backup_config` 失败时拒绝写入,先做 `algo`/`qdisc` 白名单校验,
  再原子写入(`.new` → `mv`)
- `restore_config`: 增加 backup 路径越界检查 (realpath 必须在 `BACKUP_DIR` 下),
  原子替换防止半写状态
- 三处 `write_sysctl` 调用方(`do_auto_tune`、`auto_tune` CLI、`--algo` CLI)都接住失败码
  并退出/中止后续 `apply_sysctl`

### 4. 三处 `[[ -f path/*.ko ]]` glob bug — qdisc 模块检测分支永远不命中 (SC2144)
**原状**: `detect_available_qdiscs` 第 6299/6307 行,`verify_grub_config` 第 7179 行使用
`[[ -f /lib/modules/.../sch_fq_pie.ko* ]]`。Bash 的 `-f` 不展开 glob,只匹配字面量
`*.ko` 文件名,故而 fq_pie/cake 检测、EFI grub 检测的 elif 分支从未触发。

**修复**: 改用 `compgen -G` (qdisc 检测) 和显式 `for f in glob; do [[ -f $f ]]` 循环 (EFI grub)。

---

## 供应链信任链 (CRITICAL)

### 5. XanMod 内核 .deb 走明文 HTTP 后 `dpkg -i` (C1)
**原状**: `download_xanmod_direct` 用 `http://deb.xanmod.org/...` 拉 Packages 文件再下载
.deb,**Packages 中明明有 SHA256 字段但被忽略**,然后直接 `dpkg -i`。MITM = root RCE。

**修复**:
- 全程 `https://`
- 解析 Packages 文件中的 `Filename:` + `SHA256:` 同一 stanza 内的字段
- 下载后 `sha256sum -c` 校验,**失败硬拒绝,绝不进入 dpkg**
- SHA256 必须是 64 位十六进制,格式异常拒绝
- 临时目录用 `mktemp -d` 替代固定 `/tmp/xanmod-install-$$`
- 单次下载 `--max-time 1800` 上限

### 6. 自更新 `update_script` 无任何完整性校验 (C2)
**原状**: `curl ... | -o /tmp/easybbr3_new.sh` → 仅 `head -1 | grep '#!/'` → `mv` 覆盖
当前脚本。GitHub raw 端点被投毒(账号被盗、PR 被恶意 merge、CDN 缓存污染、DNS 劫持) =
所有运行 `--update` 的机器立即 root RCE。还允许降级。

**修复**:
- **默认禁用**: 没有 `--allow-unverified-update` CLI 参数或 `ALLOW_UNVERIFIED_UPDATE=1`
  环境变量时,打印警告 banner 解释为何禁用 + 提供手动 wget+diff+install 的步骤
- 启用时仍做: 文件大小上限(10MB)、shebang 校验、`bash -n` 语法预检
- 拒绝降级: `version_gt $new_version $SCRIPT_VERSION` 必须为真
- 临时文件改用 `mktemp`
- 全程 cp/mv 检查返回值,失败硬终止
- 新增 CLI: `--update`、`--allow-unverified-update`,help 中说明

### 7. Liquorix 安装器 `curl | bash` (C3 + M7)
**原状**: Debian 路径下 `curl -s 'https://liquorix.net/install-liquorix.sh' | bash`,`-s`
还吞错。整个 `_install_kernel_liquorix_core` 函数无条件 `return 0`,`elrepo`/`hwe` 同病。

**修复**:
- Debian 路径: `curl` 下载到 `mktemp` → 校验 shebang → `bash -n` 语法预检 → `bash` 执行
- 三个核心函数(`_install_kernel_liquorix_core` / `_install_kernel_elrepo_core` /
  `_install_kernel_hwe_core`)所有 `apt-get install`/`yum install`/`dnf install` 失败均
  `return 1`,而非吞错
- HWE 增加 22.04 支持,以前漏掉了

### 8. nexttrace 二进制无校验 (C4)
**原状**: `curl -sL .../releases/latest/download/nexttrace_linux_${arch} -o /tmp/nexttrace`
→ `chmod +x` → `mv` → 后续以 root 执行。无 SHA256 校验,无 release tag pinning,
`/tmp/nexttrace` 可预测路径。

**修复**:
- 用 GitHub API 解析最新 release tag(可见可记录,而非隐式跟随重定向)
- 从同一 release 拉取 `checksums.txt`,parse 出对应二进制的 SHA256
- 下载后 `sha256sum` 校验,失败硬拒绝
- `mktemp -d` 替代固定路径
- `--max-time 60` + `--max-filesize 52428800`(50MB 上限)
- 缺 `sha256sum` 时拒绝安装(而非降级到无校验)

### 9. XanMod GPG key 不 pin fingerprint (H1 + H2)
**原状**: GPG key 每次重新下载,无 fingerprint 比对。备用 URL 来自
`raw.githubusercontent.com/xanmod/linux/main/gpg.key` —— 该仓库任何 committer 都能改它,
扩大攻击面。XanMod APT 源行还在用 `http://`。

**修复**:
- 嵌入 fingerprint 常量: `D38D7D1DA1349567ADED882D86F7D09EE734E623`
  (UID: `XanMod Kernel <kernel@xanmod.org>`,2026-04-14 时点从 `dl.xanmod.org/archive.key` 读取并固化)
- 支持 `XANMOD_GPG_FINGERPRINT` 环境变量临时覆盖
- 移除 GitHub raw 备用 key URL
- 主下载 URL 改为 `archive.key`(XanMod 官方文档推荐),`gpg.key` 作为兼容备用
- 下载后用 `gpg --show-keys --with-fingerprint --with-colons` 提取 fingerprint 并比对
- 不匹配时硬拒绝,提示用户去 https://xanmod.org/ 确认是否轮换密钥
- APT 源行从 `http://deb.xanmod.org` 改为 `https://deb.xanmod.org`

---

## 中等优先级修复

### 10. `verify_kernel_installation` pkg_count 拼接脏值 (M2)
**原**: `pkg_count=$(echo ... | grep -c . || echo 0)`,grep 输出 0 + `||` 兜底再输出 0,
拼成 `"0\n0"` 脏值。

**修复**: `printf '%s\n' "$new_kernels" | grep -c -v '^[[:space:]]*$' 2>/dev/null || true; pkg_count=${pkg_count:-0}`

### 11. `verify_kernel_bbr3` 子串误匹配 (M3)
**原**: `grep -q "bbr"` 同时命中 `bbr2/bbr3/foobar`,导致 BBR 可用性误报。

**修复**: `printf '%s\n' $available_algos | grep -qx 'bbr'` (词边界)。

### 12. `get_current_qdisc` 重复定义,第一处是 dead code (C6)
**原**: 6045 与 6278 两处定义,bash 取后者。第一处设置 `CURRENT_QDISC` 全局但永远不被调用,
任何依赖该全局的消费方静默错误。

**修复**: 删除第一处定义,保留第二处并让它同时更新 `CURRENT_QDISC` 全局作为防御性兼容。

### 13. `iptables-save` 写到非规范路径并清掉用户规则 (H6)
**原**: `iptables-save > /etc/iptables.rules` —— 既不是 Debian 规范路径
(`/etc/iptables/rules.v4`),也会盖掉同名文件。

**修复**: 检测 `/etc/iptables/` 目录是否存在,优先写规范路径;否则用脚本独占命名空间
`/etc/iptables.bbr3.rules`。临时文件 `+ mv` 原子替换。

### 14. log 文件符号链接攻击 (M1)
**原**: `>> $LOG_FILE` 跟随符号链接,本地非特权用户可在 `/var/log/bbr3-script.log`
处放符号链接到 `/etc/shadow`,等管理员以 root 运行脚本时,日志行被附加到目标文件。

**修复**:
- `log_init` 检测到 `[[ -L "$LOG_FILE" ]]` 时回退到 `mktemp /tmp/bbr3-script-XXXXXX.log`
- 用 `install -m 0640` 创建新文件,即使被竞争创建为符号链接也会拒绝
- `_log` 在写入前转义 `\n`/`\r`,防止 log injection

### 15. write_sysctl 输入白名单 (新增防御)
新增对 `algo` (`bbr/bbr2/bbr3/cubic/reno/...`) 和 `qdisc` (`fq/fq_codel/fq_pie/cake/...`)
的白名单校验,防止 CLI `--algo`/`--qdisc` 透传未知值进入 heredoc。

---

## CLI 变动

| 新增 | 说明 |
|---|---|
| `--update` | 显式入口,等价于交互菜单的"更新脚本" |
| `--allow-unverified-update` | 显式允许未签名自更新(风险自负) |

环境变量 `XANMOD_GPG_FINGERPRINT` 可临时覆盖默认指纹(用于 XanMod 项目轮换密钥的过渡期)。
环境变量 `ALLOW_UNVERIFIED_UPDATE=1` 等价于 `--allow-unverified-update`。

## 行为变更 (用户可见)

1. **`--update` 默认拒绝运行**: 必须显式 opt-in。这是有意为之——现状下自更新无法验证
   下载内容真实性,等同于把 root 权限交给 GitHub 端点。完整签名机制将在 v2.2.0 引入。
2. **Liquorix 安装在 Debian 上多了一步"下载验证"**: 用户体验等同,只是不再 `curl|bash`。
3. **XanMod GPG fingerprint 不匹配会硬拒绝安装**: 如果 XanMod 项目轮换了密钥,用户需要
   设置 `XANMOD_GPG_FINGERPRINT` 环境变量临时覆盖,并到本仓库提 issue 让我们更新常量。
4. **`--algo` 和 `--qdisc` 现在白名单校验**: 拼错的算法/qdisc 名会被拒绝,而非透传。

## 静态检查

修复前: `bash -n` PASS, shellcheck `-S error` **3 errors** (SC2144 × 3), `-S warning` 47 warnings
修复后: `bash -n` PASS, shellcheck `-S error` **0 errors**, `-S warning` 47 warnings

(警告数持平。新引入的 2 个 SC2128/SC2178 警告是 `regenerate_initramfs` 中故意做词分割的
字符串变量被 shellcheck 误判为数组,加 `# shellcheck disable=` 抑制。)

---

## 人工验证清单(merge 前请在测试 VPS 上跑)

作者无法在 macOS 上端到端验证内核安装/GRUB 路径,以下场景需要在真实 Linux VPS 上验证:

- [ ] **V1 全新机器**: Debian 12 跑 `./easybbr3.sh --install-kernel xanmod --non-interactive`,
      验证: GPG fingerprint 校验通过、SHA256 校验通过、reboot 后 `uname -r` 显示 xanmod
- [ ] **V2 故意失败 + 回滚**: 修改脚本让 `dpkg -i` 失败,确认 rollback 真的恢复了 /boot,
      `ls /boot/vmlinuz-*` 仍包含原内核,`update-grub` 后 grub.cfg 仍引用 known-good 内核
- [ ] **V3 Ctrl-C 测试**: 在 `update-initramfs` 跑到一半时按 Ctrl-C,确认进程 NOT 被中断
      (临界区屏蔽了 SIGINT)
- [ ] **V4 APT 源切换**: `switch_to_china_apt_sources` 后立即 `apt update` 成功;
      `switch_to_official_apt_sources` 后同样
- [ ] **V5 备份目录不可写**: `chmod 555 /etc/sysctl.d/bbr-backups`,运行脚本应明确
      报错"无法创建备份目录"而非静默继续覆写
- [ ] **V6 幂等性**: 完整跑一遍后再跑一遍,`/etc/sysctl.d/99-bbr.conf` 内容应一致
- [ ] **V7 自更新**: 默认运行 `--update` 应拒绝 + 打印 banner;加 `--allow-unverified-update` 后才执行
- [ ] **V8 XanMod fingerprint**: 故意改成错误 fingerprint,验证安装被拒绝且报错明确
- [ ] **V9 Debian Liquorix**: 验证下载-语法预检-执行流程能正常完成
- [ ] **V10 nexttrace**: `ensure_nexttrace` 路径下的 SHA256 校验通过

## 不在本次范围(推迟到 v2.2.0)

- 模块拆分(8 个 lib + build.sh 单文件分发)
- 性能优化(并行 precheck,缓存 main_iface/nproc)
- die() 全面替换 print_error+exit
- 错误信息加 next step
- 启动时间优化
- shellcheck CI gate
- 完整签名机制(minisign/cosign)接入

---

**致谢**: 修复方向与优先级源自一次完整的安全/正确性双视角审计(Claude Opus 4.6)。
原始审计报告与决策记录保存在 `openspec/changes/fix-v2.1.1-critical-safety/` 下。
