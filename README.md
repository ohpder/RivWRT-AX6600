<div align="center">

# $\color{red}{\rule{0.314em}{0.75em}}\$ ImmortalWRT

**AX6600 雅典娜 · 个人定制固件**

*编译机制基于 [ones20250/Openwrt-AX6600](https://github.com/ones20250/Openwrt-AX6600) · 源码基座 [PurpleRed-River/immortalwrt](https://github.com/PurpleRed-River/immortalwrt)*

`IPQ6010` `12M+2G` `1G RAM` `128G eMMC` `NSS 加速` `dae eBPF` `kernel 6.18`

*" Flow downstream, not upstream. "*

</div>

---

## 目录

- [目录结构](#-目录结构)
- [定制组件](#-定制组件)
- [固件特性](#-固件特性)
- [网口定义](#-网口定义)
- [默认参数](#-默认参数)
- [云编译与刷机](#-云编译与刷机)
- [使用指南](#-使用指南)

---

## 📂 目录结构

```
Config/         编译配置片段（按 profile 拼接，非完整 .config）
  GENERAL_AX6600.txt          上游通用配置
  GENERAL_AX6600_ImmortalWRT.txt   ImmortalWRT 增量（组件开关）
  IPQ60XX-WIFI-YES.txt        目标平台与设备
Scripts/
  Settings.sh                 构建期注入总入口（CI 唯一调用点）
  Packages.sh                 第三方组件拉取
  nss-page-test.js            NSS 加速页面回归测试（前端）
  nss-status-test.sh          NSS 状态采集回归测试（后端解析）
  ImmortalWRT-netfix-test.sh       wan6 首启修复回归测试
Docs/           刷机救砖教程等
.github/workflows/           云编译工作流
```

### 开发期测试

`Scripts/` 下三个测试脚本不参与固件构建，只在改 `Settings.sh` 时用来快速验证：

```sh
bun Scripts/nss-page-test.js      # 页面前端：轮询重绘、边界输入、状态渲染
sh  Scripts/nss-status-test.sh    # 状态采集：debugfs 数据格式解析
sh  Scripts/ImmortalWRT-netfix-test.sh # wan6 首启修复：默认值、旧接口名迁移、幂等
```

它们直接从 `Settings.sh` 的 heredoc 里取出代码来跑（前端用 `bun`，后端用系统 `sh`），
**不需要先编译固件**。存在的理由：这几处的 bug 几乎都在动态行为与格式假设上 ——
轮询若干次后悬停层被清掉、单点历史算出 `NaN` 坐标、ECM 连接数数据源是文本而非数字 ——
这些静态审阅看不出来，
构建与语法检查也发现不了。每个测试都用缺陷注入验证过（改回缺陷版本即失败）。

---

## ✨ 定制组件

| 组件 | 来源 | 说明 |
|------|------|------|
| **aurora 主题** | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora) | 现代界面，编译期设为默认 |
| **aurora 设置界面** | [eamonxg/luci-app-aurora-config](https://github.com/eamonxg/luci-app-aurora-config) | 预设/浅深色/布局/主题商店 |
| **Athena LED 点阵屏** | 上游树内官方版 | 网速/天气/农历，预编译二进制零下载 |
| **bandix-plus 流量统计** | [timsaya/openwrt-bandix-plus](https://github.com/timsaya/openwrt-bandix-plus) + [前端](https://github.com/timsaya/luci-app-bandix-plus) | eBPF 旁路观察（见[使用注意](#使用注意)） |
| **daede 透明代理** | [kenzok8/openwrt-daede](https://github.com/kenzok8/openwrt-daede) | dae eBPF 内核 + daed + 统一管理页 |
| **partexp 分区管理** | [sirpdboy/luci-app-partexp](https://github.com/sirpdboy/luci-app-partexp) | Web 一键格式化/扩容/挂载 |
| **wolultra 网络唤醒** | [ones20250/packages](https://github.com/ones20250/packages) | 上游 wolplus 继任包 |
| **ksmbd 文件共享** | 上游 feeds | 内核态 SMB，替换基座 Samba4（省 34MB） |
| **NSS 加速管理页** | 本项目自建 `luci-app-ImmortalWRT-nss` | 引擎开关 + 频率档位 + 负载历史（2h/12h/1d/1w）+ 加速连接数 |
| **podman-compose** | 本项目自建包（PyPI 1.6.0） | CLI 容器编排 |
| **statistics / vnstat** | 上游 feeds | 历史图表 / 接口流量总量 |

基座沿用上游：**NSS 硬件加速全套**、**firewall4/nftables**、ath11k 三频、内存水位调优、自动挂载。

---

## 🔧 固件特性

- **NSS 满血加速**：直连流量硬件转发（CPU 近零）；代理流量由 dae 内核态接管，互不抢道
- **内核原生 BTF**：`CONFIG_DEBUG_INFO_BTF=y`，eBPF 程序开箱即用
- **单 WAN 默认布局**：沿用上游端口角色，2.5G 口为 WAN，LAN1-LAN4 为 LAN；双 WAN 定制已注释停用（见下表）
- **FullCone NAT**：游戏机/P2P 友好，默认开启（防火墙页可关）
- **eMMC 寿命关怀**：数据盘独立分区 + 每周 fstrim + 高频写服务默认关闭
- **无默认密码**：登录与 WiFi 均默认开放，首刷请立即加固

---

## 🔌 网口定义

| 物理丝印 | 系统设备名 | 角色 |
|---|---|---|
| **WAN**（2.5G） | `wan` | **上行** |
| LAN1-LAN4（千兆） | `lan1`-`lan4` | 内网 |

> 双 WAN 端口改名、网络注入和 mwan3 配置目前均已在构建脚本中注释停用。

---

## 📡 默认参数

| 项 | 值 |
|----|----|
| 管理地址 | `192.168.100.1` |
| 主机名 | `ImmortalWRT` |
| 登录密码 | 默认无（**首刷请立即设置**） |
| WiFi | 三 SSID 分频，**默认开放**（见下） |

| SSID | 频段 | 信道 | 带宽 |
|---|---|---|---|
| `ImmortalWRT-2.4G` | 2.4G | 11 | 20MHz |
| `ImmortalWRT-5.2G` | 5G 游戏段（4×4） | 44 | 160MHz |
| `ImmortalWRT-5.8G` | 5G 影音段 | 149 | 80MHz |

通用：地区 US · 功率 24dBm（ones20250 官方推荐）。首次启动由 `ImmortalWRT-wifi` 服务自动固化（按总线自动区分 5G 频段，探测失败回落非 DFS 安全值）。

---

## 🖥 云编译与刷机

| Workflow | 用途 |
|---|---|
| `QCA-ALL` | 正式编译（源码：PurpleRed-River/immortalwrt main） |
| `WRT-TEST` | 仅生成 `.config`（几分钟，验证配置） |
| `WRT-PKG-TEST` | 单包链编译验证（快速定位组件问题） |

> **源码基座说明**：`PurpleRed-River/immortalwrt` 是 [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt)
> 的 fork（VIKINGYFY 又是 [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) 的 fork），
> 提供 qualcommax/ipq60xx 高通平台支持与无线 regdb 调整（删 CN/US 的 DFS、提功率）。
> 换源时确认三者中任意一个的 HEAD 即可 —— 本固件依赖的树内内容（设备 DTS、NSS 驱动、
> regdb patch、`nss_freq`/`nss_diag`）都在这条 fork 链上，且 `Settings.sh` 的每处 sed
> 目标都有对应断言，若不匹配会直接报错而非静默失效。

- 固件命名：`ImmortalWRT-时间-ipq60xx-jdcloud_re-cs-02-squashfs-factory/sysupgrade.bin`
- 适配分区：**12MiB 内核 + 2GiB rootfs**（chenxin527 GPT，A 槽）
- 首刷走 U-Boot Web 上传 `factory`；系统内升级用 `sysupgrade`（独立数据分区不受影响）
- 详细流程：[Docs/刷机救砖教程.md](Docs/刷机救砖教程.md)

---

## 📖 使用指南

<details>
<summary><b>多 WAN（已停用）</b></summary>

<!-- 历史配置说明保留，当前构建不包含以下双 WAN 配置。

固件已装 **mwan3 3.6.12**（nftables 版）+ 其 LuCI 界面。界面有**两个入口**：

| 菜单位置 | 用途 |
|---|---|
| **网络 → MultiWAN 管理器** | 配置：接口 / 成员 / 策略 / 规则 / IP 集 |
| **状态 → MultiWAN 管理器** | 查看：概览 / 状态 / 路由 / 诊断 / 排障 |

**接线**：第一条线接丝印 **LAN1**（`wan1`），第二条接丝印 **LAN2**（`wan2`）。

**启用步骤**（固件默认**不接管流量**，因为单线时接管没有收益）：

1. **网络 → 接口**：分别把 `wan1` / `wan2` 的协议按实际线路设为 `DHCP` 或 `PPPoE`
   （PPPoE 需填账号密码）。出厂默认两条都是 `none`。
2. **网络 → MultiWAN 管理器 → 接口**：确认 `wan1`、`wan2` 都启用
   （`wan2` 默认未启用，接线后打开）。
3. **网络 → MultiWAN 管理器 → 规则**：启用 `default_rule_v4`（或新建一条），
   策略选 `balanced`。
4. 保存应用后，mwan3 才开始在两条线上分流。

**预置的策略**（在 mwan3 配置里已生成，直接用）：

| 策略 | 含义 |
|---|---|
| `balanced` | 两条等权分流（weight 1:1）。想按带宽比分配就改 member 的 weight，如 1000M+500M → 2:1 |
| `wan1_only` | 全部走第一条 |
| `wan2_only` | 全部走第二条 |

**按运营商分流**：mwan3 的规则支持 `ipset` 选项，可把「目的 IP 属于某运营商」
的流量固定走对应线路。做法是先用 `config ipset` 声明一个集合（`loadfile` 指向
纯文本 CIDR 列表），再在规则里引用它 —— 规则**按配置文件顺序 first-match**，
所以运营商规则必须排在默认规则之前。IP 段数据可用社区整理的
[ispip.clang.cn](https://ispip.clang.cn)（按运营商分文件，v4/v6 分开）。
> 更新集合后必须 `restart` 而非 `reload`：mwan3 渲染集合时只 `add element`
> 不做 flush，仅 reload 会让已删除的旧网段永久残留。

**线路健康探测**：`track_ip` 已改为国内可达的 `223.5.5.5 / 119.29.29.29 / 180.76.76.76`
（上游默认是 1.0.0.1、208.67.x.x 等，国内探测容易误判成"线路故障"而错误切走流量）。
三个 IP + `reliability 2` = 至少两个可达才算健康。

**与代理/NSS 的关系**：

- **NSS**：直连流量由硬件转发，ECM 在连接建立时只需一次确定的路由决策，与 mwan3 不冲突。
- **dae**：其配置里 `wan_interface` 默认是 `auto`，**双 WAN 下建议显式写成
  `wan_interface: wan1, wan2`**，否则 dae 可能只认一条出口。
  dae 的 eBPF 分流与 mwan3 的 fwmark 标记理论上是两个维度（前者"走不走代理"、
  后者"走哪条宽带"），若实测有冲突，调整 mwan3 的 `mmx_mask`（默认 `0x3F00`）。
-->

双 WAN 端口映射、mwan3 与对应的首启配置目前均已在构建脚本中注释停用，固件按上游默认单 WAN 布局生成。

</details>

<details>
<summary><b>NSS 加速与代理的分工</b></summary>

- 直连流量：NSS 硬件转发，CPU 近零
- 代理流量：dae 在内核态接管（eBPF），与 NSS 天然分工
- 页面：**服务 → NSS 加速**（5 秒轮询）；**服务 → daede**（节点/规则配置）
- 防火墙页"路由/NAT 卸载"保持**无**——NSS 独立工作，软件卸载会干扰

页面上的四个读数，含义各不相同：

| 项 | 说明 |
|---|---|
| **硬件加速** 开关 | 开=ECM 内核模块加载中（直连走硬件转发）；关=回退内核软转发。默认开，开机自启 |
| **频率档位** | `748.8 MHz`（上游默认）／`1497.6 MHz`。写 proc 并存入 UCI，重启保持 |
| **NSS 频率** | 当前实际时钟（只读） |
| **加速连接数** | 当前经 NSS 加速的连接条数；判断"加速到底有没有在工作"看它最直接 |

> **「NSS 核心负载」图不是流量速率**，而是引擎核心的占用率：空闲时贴近 0 属正常，
> 只有大流量经过加速路径时才会抬升。想确认加速是否生效，看**加速连接数**。
> 图的时间范围可切 2 小时 / 12 小时 / 1 天 / 1 周，鼠标移到曲线上可读数。

> 上游 `qca-nss-pbuf` 开机即把 NSS 时钟锁频（`auto_scale=0`），这是其 pbuf/N2H
> offload 配置的前提，因此页面不提供 Auto/Fixed 切换，只给两个锁频档。

</details>

<details>
<summary><b>bandix 流量统计的定位</b></summary>

- eBPF 旁路观察，不影响转发性能；**管控/限速功能勿开**（NSS 下不生效）
- NSS 加速的流量不计入其统计（数字偏低属正常），需要精确报表时在 NSS 页面临时停用加速
- 长周期总量看 vnstat（接口计数器，NSS 流量照数）

</details>

<details>
<summary><b>文件共享（ksmbd）与存储规划</b></summary>

- 先用 partexp 把剩余空间格式化为 ext4 并挂载 `/opt`
- ksmbd 共享目录指向 `/opt/share`（LuCI 服务 → 网络共享）
- 容器数据 → `/opt/containers`，compose 文件 → `/opt/compose`
- 系统日志写内存（tmpfs）不伤 eMMC；每周 fstrim 已内置
- ksmbd 无打印共享与域控；macOS Time Machine 支持有限

</details>

<details>
<summary><b>容器（podman CLI）</b></summary>

```sh
mkdir -p /opt/compose && cd /opt/compose
vim docker-compose.yml        # 定义服务栈
podman-compose up -d
```

- podman 常驻 API 服务默认关闭（省 45MB）；需要远程 API 时 `/etc/init.d/podman start`
- 容器数据建议 `/opt/containers`（storage.conf 可改 graphroot）

</details>

<details>
<summary><b>登录横幅</b></summary>

SSH 登录显示点阵 ImmortalWRT 标志 + 项目格言 + 组件清单，由 `Settings.sh` 构建期生成（`/etc/banner`）。

</details>

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

## 免责声明

本项目固件仅供个人学习与研究使用。刷机有风险，操作前请备份分区并确认设备型号匹配，
因刷机造成的设备损坏或数据丢失由使用者自行承担。
