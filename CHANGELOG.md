# ImmortalWRT AX6600 更新记录

## 2026-09-11 · 基于 ones20250 纯净版重建（ImmortalWRT v1）

本次为全量重写：上游编译机制原样保留，定制全部收敛到 ImmortalWRT 单 profile。

### 修复

- `QCA-ALL.yml`：还原上游骨架并改为单 matrix（`PROFILE: [ImmortalWRT]`）。
  此前 fork 的 `PROFILE: ImmortalWRT` 未同步 `WRT-CORE.yml` 白名单，触发 `exit 1`，一跑即失败。
- 移除 GPT 残留的格式错误配置（裸包名列表，不符合 `.config` 片段的 `CONFIG_*` 格式）。

### 工作流

- `WRT-CORE.yml`：profile 白名单加入 `ImmortalWRT`；固件命名改为
  `ImmortalWRT-时间-ipq60xx-jdcloud_re-cs-02-*.bin`；Release 文案更新为 ImmortalWRT 组件清单。
- `WRT-TEST.yml`：PROFILE 选项与默认值改为 ImmortalWRT，默认参数与正式编译一致。
- 默认值：主机名/SSID `ImmortalWRT`、管理地址 `192.168.100.1`、默认主题 aurora；WiFi 默认开放（无密码）。

### 组件（Scripts/Packages.sh ImmortalWRT 注入块）

- aurora 主题（eamonxg 版）+ 编译期默认主题替换（Settings.sh）
- Athena LED 点阵屏控制：回退上游树内官方版 `luci-app-athena-led`
  （ones20250 同款，预编译二进制零下载）；unraveloop 增强版 release 资产已 404 无法构建
- bandix-plus 流量统计（后端 + LuCI 前端，eBPF 旁路观察定位）
- daede 透明代理（dae + daed + luci-app-daede 一体包，pkg 模式提取三子包）

### 配置（Config/GENERAL_AX6600_ImmortalWRT.txt 新增）

- 显式开启：dae / luci-app-daede / bandix-plus 双包 / luci-theme-aurora / luci-app-athena-led
- Podman 容器环境（kmod-veth 覆盖基座 =n）、IPv6（odhcp6c / odhcpd-ipv6only）
- kmod-nft-fullcone（fullcone NAT）、vnstat（接口级总量统计，NSS 流量照数）
- 关闭：mosdns / smartdns（DNS 分流由 dae 内置模块承担）、树内旧版 LED 包

### 定位说明

- NSS 优先：直连流量满血硬件加速；dae 代理流量内核态接管，二者天然分工。
- bandix 纯观察：不影响转发性能；精确报表需临时停用 NSS ecm（README 有操作说明）。
- Config/GENERAL_AX6600_PLUS.txt 与 GPT 版 ImmortalWRT_AX6600.txt 已删除；Docs 三个半成品文档已删除，
  保留上游原文《刷机救砖教程.md》。

---

## 2026-09-12 · 运行时修复与增强批次

### 修复（编译层已验证通过后的运行时问题）

- `Settings.sh`：UDIR 变量未定义（删网口互换块时误删定义）→
  所有 uci-defaults 写根目录失败，菜单归拢/FullCone/podman 关闭/网络纠正全部未生效（模拟树验证修复）
- 无线 init.d 缺 rc.d 启用链接 → 三频固化未执行（补 S99ImmortalWRT-wifi 链接）
- 无线 init.d：jsonfilter -s 误用（应 -i）→ 5G 频段探测失败；
  加固：探测失败回落 149/HT80 非 DFS 安全值，不残留生成器的 DFS 默认信道
- NSS 页面 JS：重复定义 render + fs.exec 参数误用 → 重写（bun 语法校验）
- Config 漏 `CONFIG_PACKAGE_luci-app-ImmortalWRT-nss=y` → NSS 页面未进固件（已补）
- `podman-compose`：上游 immortalwrt/packages 无此包（死配置行）→
  自建 PyPI 打包（1.6.0 sdist + sha256 钉死，依赖 python3-yaml/dotenv）

### 新增

- DTS 端口 label 互换（wan↔lan1）：系统名 = 物理丝印 = 角色语义一致；
  弃 uci-defaults 网口互换方案（实测拔插确认丝印 WAN=dp5、丝印 LAN1=dp1）
- 网络配置纠正 uci-defaults（98-ImmortalWRT-net-fix）：兼容旧命名配置升级
- ksmbd 替换 Samba4（省 ~34MB 常驻；上游无打印/域控需求，纯收益）
- `CONFIG_VERSION_DIST="ImmortalWRT"`：banner/openwrt_release/系统 ID 品牌化
- `CONFIG_DEBUG_INFO_BTF=y`：内核原生 BTF（vmlinux-btf 包仍作 dae 依赖兜底）
- podman API 服务默认关闭（省 ~45MB；podman 包 init 无条件常驻 system service）
- banner：figlet 字样 + 项目格言 "Flow downstream, not upstream."
- FullCone NAT 固化开启（96-ImmortalWRT-fullcone）
- 分区适配：KERNEL_SIZE=12288k（实测 A 槽 0:HLOS=12288KB，GPT 对齐）

### 文档

- README 全量重构（组件表/网口表/无线表/使用指南折叠块/构建系统说明）
- CHANGELOG 补运行时修复批次（本段）

---

## 2026-09-14 · NSS 页面完善与无线首启修复

### 无线（首次刷机后 5G 起不来）

- **根因**：ath11k 的 phy 级 regd 更新走 workqueue，三个 radio 并发启动时相互竞争，
  部分 phy 更新失败（日志实证 `hostapd: Frequency 5180/5745 is not allowed`），
  导致两个 5G 起不来；重启一次即恢复。
- **改法**：`ImmortalWRT-wifi` 改为「参数比对 → 对未就绪的 radio 逐个串行重启 → 仍不行则兜底重启一次」，并用
  `/etc/.ImmortalWRT-wifi-rebooted` 守卫防止无限重启循环。
  ★ 不可用 `wifi reload` 重试——读 `/sbin/wifi` 源码可知它忽略设备参数、执行全量
  `ubus call network reload`，会把三个 radio 一起重启，反而加剧竞争。
- SSID：2.4G 改为 `ImmortalWRT-2.4G`（三频分名一致）

### NSS 加速页

修复（均为实测复现）：

| 问题 | 影响 |
|---|---|
| 负载图取**行内首个百分比**（= Min 列） | 曲线长期显示为低谷；应取 Avg 列 |
| `rrdtool fetch` 输出 `ts: value` 的冒号未剥离 → 拼出 `ts::v` | 前端 split 得 3 段全丢弃，**历史图永远空白** |
| `draw()` 清空 svg 后未补挂悬停层 | 页面停留 5 秒后悬停十字线永久消失，且不报错 |
| 样本数 <2 时 `monotone()` 返回空串、`xOf()` 以 `n-1` 为分母 | 单点历史产出 `d=" LNaN,… LNaN,… Z"`，整条曲线画不出 |
| `readStatus()` 无条件吞掉错误 | ACL 失效/脚本缺失只表现为"图表一直空着"，提示却说"等待约 30 秒" |
| 自启状态取 `rc.list` 的 `enabled` 字段 | **恒报未启用**：`rc.c` 只读 init 脚本前 11 行，而 `qca-nss-ecm` 有 16 行版权头、`START=26` 在第 18 行；改为直接判定 `/etc/rc.d/S??qca-nss-ecm` 链接 |
| 引擎状态用 `lsmod` 检测 | busybox 未编译该 applet 时恒判"已停用"；改用 `/proc/modules` |
| 连接数按"纯数字"解析 | ECM 实际给的是 `tcp X udp Y other Z total W` 文本 → 页面永远显示 `—` |

新增：

- **频率档位**按钮（748.8 / 1497.6 MHz），走上游 `/usr/bin/nss_freq`，写 proc 并存入 UCI
- **加速连接数** KPI（判断"加速是否在工作"最直接的指标）
- 负载历史图支持 2 小时 / 12 小时 / 1 天 / 1 周切换，含悬浮读数
- 开关改用 LuCI 标准组件（`ui.Checkbox`）与官方 `ubus rc.init` 接口，外观交给主题

> 页面不提供 Auto/Fixed 调频切换：上游 `qca-nss-pbuf` 开机即把 NSS 时钟锁频
> （`auto_scale=0`），这是其 pbuf/N2H offload 配置的前提，不该反着改。

### 测试

- 新增 `Scripts/nss-page-test.js`（前端，46 项）与 `Scripts/nss-status-test.sh`（后端解析，10 项），
  直接从 `Settings.sh` 取代码运行，无需编译固件。已用缺陷注入验证其有效性
  （移除修复即失败）。
- README 补「目录结构」章节（修掉 TOC 里的死链）与 NSS 读数含义说明。

---

## 2026-09-14 · 双 WAN（mwan3）与网口重命名

### 网口

丝印 **LAN2**（dp2）改为第二条上行 `wan2`；丝印 LAN1 的上行由 `wan` 更名为 `wan1`
（与 wan2 成对，语义更清楚）。最终形态：

| 丝印 | 系统名 | 角色 |
|---|---|---|
| WAN (2.5G) | `lan1` | 内网 |
| LAN1 (千兆) | `wan1` | 上行 1 |
| LAN2 (千兆) | `wan2` | 上行 2 |
| LAN3 / LAN4 | `lan3` / `lan4` | 内网 |

- DTS：`Settings.sh` 用一条多 `-e` 的 sed 同时改 dp1/dp2/dp5 的 label。
  DTS 里的 `switch_lan_bmp`/`switch_wan_bmp` **不动** —— 全树检索确认它们只出现在
  各设备 DTS 中、没有任何驱动读取，是 QSDK 遗留的装饰属性。
- `02_network`：LAN 列表去掉 lan2；`wan2` 单独声明为独立接口。
  ★ 不能用 `ucidef_set_interfaces_lan_wan` 的 wan 参数塞两个设备 ——
  该函数见空格即走 `json_select_array "ports"`，会把两个口桥成一个 WAN。
- 防火墙：zone **名保持 `wan`**（`firewall.config` 里有 11 处 `option src/dest 'wan'`
  引用它），只把 `list network` 由 `'wan'` 换成 `'wan1' 'wan2'`。
- `98-ImmortalWRT-net-fix` 重写为幂等的网口规范化脚本：剔除 br-lan 里的 lan2、
  把旧 `network.wan` 迁移为 `network.wan1`、补建 `wan2`。
  迁移是为了**保留配置升级**：不迁移则 mwan3 找不到 wan1，静默失效。

### 组件

- **mwan3 3.6.12**（dl12345/mwan3，`openwrt-25.12` 分支）+ 同作者 LuCI 界面。
  ★ 与 feeds 里的 **2.12.2** 是两回事：旧版依赖 iptables+ipset，与本固件的
  fw4/nftables 不合；`Packages.sh` 会先删 feeds 同名包再克隆新版。
  依赖 15 项中 12 项已有，缺的 `libnetfilter-conntrack` / `libmnl` /
  `ucode-mod-socket` 均在树内、由 `+DEPENDS` 自动拉入。
- Config 增 `CONFIG_PACKAGE_mwan3=y` 与 `CONFIG_PACKAGE_luci-app-mwan3=y`。

### mwan3 初始配置

`Settings.sh` 覆盖包自带的 `/etc/config/mwan3`：

- **默认不接管流量**（所有 rule `enabled 0`）——单线时接管无收益，只增加
  fwmark 交互面。接线并配好协议后启用 `default_rule_v4` 即可。
- `track_ip` 改为国内可达的 `223.5.5.5 / 119.29.29.29 / 180.76.76.76`
  （上游默认 1.0.0.1、208.67.x.x 等，国内会误判线路故障而错误切走流量）。
- 预置 `balanced`（等权）/ `wan1_only` / `wan2_only` 三个策略。
- `wan2` 的接口项默认 `enabled 0`（未接线不做探测）。

### 测试

- 新增 `Scripts/ImmortalWRT-netfix-test.sh`（14 项）：覆盖新刷机、保留配置升级、
  幂等、wan6 处理四种场景。已用缺陷注入验证有效性（去掉迁移或去掉 br-lan
  剔除即失败）。
- 过程中修掉自己的 mock 两处错误，值得记录：① 函数末尾 `return 0` 会覆盖
  `uci -q get` 的退出码，使"键不存在"被判成存在、迁移分支全被跳过（测试假通过）；
  ② 删旧键用 `grep -v "^$key="` 时，键中的 uci 匿名段语法 `[0]` 被 grep 当字符类，
  旧行删不掉、读回旧值。两处都已改为语义正确的实现并写入注释。

---

## 2026-09-14 · 源码基座切换到 PurpleRed-River/immortalwrt

编译拉取的源码仓库由 `ones20250/immortalwrt_ipq` 换成 `PurpleRed-River/immortalwrt`
（同为 `main` 分支）。**源码内容零差异** —— 三方 HEAD 是同一个 commit：

```
ones20250/immortalwrt_ipq      90448eeb2b8f5d172caedfe6d96ab3bacb058c09
PurpleRed-River/immortalwrt    90448eeb2b8f5d172caedfe6d96ab3bacb058c09
VIKINGYFY/immortalwrt          90448eeb2b8f5d172caedfe6d96ab3bacb058c09
```

三者是 `immortalwrt/immortalwrt → VIKINGYFY/immortalwrt → {ones20250, PurpleRed-River}`
的关系，且最近提交的作者全是 VIKING / VIKINGYFY / Tianling Shen —— ones20250 没有
自己的提交，是 VIKINGYFY 的精确同步。逐文件比对 15 个关键路径（设备 DTS、02_network、
ipq60xx.mk、NSS 驱动与 patch、regdb 功率/DFS patch、nss_freq/nss_diag、firewall.config、
kernel-version.mk、feeds.conf.default 等）**全部 md5 相同**。

- 改动点：`QCA-ALL.yml`（matrix SOURCE）· `WRT-TEST.yml`（下拉选项与默认值）
  · `WRT-PKG-TEST.yml`（克隆地址）
- 文案改为引用 `$WRT_SOURCE` 变量（`WRT_PROFILE_DESC` 与 Release 说明），
  以后再换源不必改这些文字
- 顺带修正 Release 说明一处措辞错误：`设备型号` 原先填的是源码仓库名，
  现改为 `jdcloud_re-cs-02（京东云雅典娜 AX6600）`，源码仓库另列为 `源码基座`

### 换源暴露的风险 → 补齐断言

换源使"sed 目标漂移 → 静默失效"成为现实风险，故给 `Settings.sh` 里三处
原本无校验的 sed 补上断言（另有防火墙那条本就有）：

| 目标 | 静默失效的后果 |
|---|---|
| `ipq60xx.mk` 的 `KERNEL_SIZE` | 编出按 6MiB 分区布局的固件，与设备 12MiB 内核分区不匹配 |
| DTS 三处端口 label | 网口角色错位，用户按 README 接线会接错口 |
| `02_network` 设备分支 | 首次刷机默认配置里 br-lan 挂不存在的 lan2、WAN 指向不存在的 wan1 → 直接没网 |
| `firewall.config` 的 wan zone | 两条上行都进不了 wan zone（无 NAT、入站策略失效）|

断言判的是**最终状态**而非"sed 是否命中" —— 上游若某天自己改成目标值，同样通过。

验证（注入漂移，用临时副本，未提交）：四个场景全部被正确拦截，退出码 1，
错误信息指出具体文件与期望值；正常场景退出码 0。

### 修复编译阻塞：第三方 LuCI 包的 luci.mk 路径

推送前核查发现 `dl12345/luci-app-mwan3` 的 Makefile 用 `include ../../luci.mk`
—— 这是给 `feeds/luci/applications/<pkg>/` 层级写的相对路径。本固件把这类包克隆到
`package/`，`../../luci.mk` 会解析成 `wrt/luci.mk`（不存在）→ **构建直接失败**。
（仓库其它第三方 LuCI 包如 aurora 用的是 `$(TOPDIR)/feeds/luci/luci.mk` 绝对路径，
所以此前没踩过。）

`Settings.sh` 增加统一的扫描修正：找出 `package/*/Makefile` 里任何含
`../../luci.mk` 的引用改成绝对路径，模式不锚定行首尾（容错缩进/多空格），
修正后断言"不应再有残留"。做成通用而非只针对 mwan3 —— 将来加新包不会再踩。

验证三种场景：正常相对路径（修正）· 带缩进变体（仍能修正）· 已是绝对路径
（不动、不报错）。

### 修正 README 的菜单路径

原来写的「网络 → 多WAN管理器」不准确。读 `menu.d` 后改正：mwan3 有**两个入口**，
`admin/network/mwan3/*`（配置：接口/成员/策略/规则/IP 集）与
`admin/status/mwan3/*`（查看：概览/状态/路由/诊断/排障）；中文标题是
**「MultiWAN 管理器」**（zh_Hans 翻译）。另补上按运营商分流（`ipset` + `loadfile`）
的说明与"更新后须 restart 而非 reload"的提醒。

---

## 上游历史（fork 自 ones20250/Openwrt-AX6600）

上游按 PURE（纯净）/ PLUS（预装 OpenClash、PassWall2、Docker 等）双版本发布，机制详见上游仓库。
本仓库不再构建 PURE/PLUS，仅维护 ImmortalWRT 定制版。
