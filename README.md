# ZTE USB WiFi Manager

[![CI](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

面向 OpenWrt 的中兴 U25S 设备控制台整合工具。项目目标是在一个 LuCI
入口内管理通过 USB 接入的 U25S 专属能力，包括蜂窝网络、SIM、U25S Wi-Fi、
客户端、流量、短信、设备状态和诊断；OpenWrt 已有的 DHCP、防火墙、端口转发
等功能不重复实现。

> 本项目不再承诺智能充放电。TR3000 关闭 USB VBUS 时，U25S 的 USB 数据连接
> 也会中断，无法实现“停止充电但保持 USB 上联”。电池信息仅作为设备状态展示；
> USB 断电只可能作为明确会掉线的人工故障恢复动作。

## 当前状态

仓库目前处于**设备控制台整合开发预览阶段**。源码 backend r16 / LuCI r5
已经完成产品边界重置，最近完成真实 SDK/QEMU/路由器验证的发布包仍是
backend r15 / LuCI r4：

- 已接入 U25S goform 双重 SHA-256 登录和批量状态读取。
- daemon 聚合设备状态和 netifd 网络状态，并通过
  rpcd/ubus 提供给 LuCI。
- LuCI 已采用设备控制台导航；总览、移动网络、短信、设备、诊断和日志页使用缓存快照。
- 已补充读取 SIM 类型与电池扩展状态，不映射未经实机校准的卡槽语义。
- 已展示经过验证的短信总数与脱敏事件日志；不缓存号码或短信正文。
- 固件版本、实时/本次/本月流量和套餐状态已按目标固件契约接入只读展示；
  Wi-Fi 与客户端仍等待经过验证的已认证 fixture，不展示推测数据。
- 已实现 mode-600 原子动作队列、单动作串行化、结果限额、重启恢复和操作状态查询。
- 已从目标固件原生登录页核实 `SIM_SWITCH_SIMCARD` 及 `1/2/3/0` 卡槽映射，
  并接入 daemon 的登录、单次会话恢复重试、写入和操作后状态回读。
- 模拟器覆盖九类语义写动作的成功、拒绝、超时、会话过期和读回；这些 fixture
  动作不等同于真实 U25S 写接口。
- 已保留严格限定为 Cudy TR3000 v1 的 hardware Power Adapter 代码，仅用于
  旧版本遗留 OFF 状态的安全恢复和后续显式故障恢复研究：
  官方 OpenWrt `ubootmod` 固件使用 xHCI bind/unbind 和 `usb-vbus` regulator
  双重读回；导出 `modem_power` 的兼容固件继续使用固定 GPIO 节点。
  两种 profile 都必须与板型精确匹配，默认仍以 `calibrated=0` 锁定。
- daemon 正常轮询不会计算或执行任何电池驱动的 USB 供电动作。启动和退出时
  仍会尝试恢复旧版本可能遗留的 OFF 状态，避免升级后设备被困在断电状态。
- 连续读取失败会触发轮询退避，快照会保留最后可信的设备状态。
- 已加入加速稳定性测试和脱敏 72 小时采样/验证工具，覆盖日志轮转、动作结果限额、
  权限、临时文件、RSS、文件句柄、状态新鲜度与恢复互锁；
  真实 72 小时与硬件在环运行仍待备用设备完成。
- 独立 Ubuntu CI 已加入真实 Linux network namespace + veth 的 L4 门禁，验证
  `eth2` / `wan` 默认路由切换、U25S 管理地址连通性及 `eth2` 重建恢复。
- 所有生产设备写能力保持关闭，默认 `write_enabled=0`。
- SIM 切换仍需在备用 U25S 上完成真实切卡与恢复验收后才会开放。

当前状态不代表已经完成人工上机验收。

项目不会根据固件通用代码中的残留符号自行增加功能。产品能力以当前设备原生管理页面、实机验证结果和明确需求为准。

## 目标环境

- 路由器：Cudy TR3000 v1
- SoC：MediaTek MT7981
- OpenWrt：25.12.5
- 中兴设备：U25S / MU5650
- 当前 USB 网络：`usbwan` / `eth2`

## 安装

> 项目目前是安全门控开发预览版，尚未发布稳定版本，也尚未完成全部真实 U25S
> 写接口和 72 小时稳定性验收。建议先在备用 OpenWrt 设备上验证。
> 不要强制安装与固件版本、target 或架构不匹配的包。

当前构建与验证证据：

| OpenWrt | 包格式 | 当前 r15 / LuCI r4 | 历史 QEMU 记录 |
|---|---|---|---|
| OpenWrt 25.12.5 | `.apk` | GitHub SDK、安装、r14→r15 升级、服务与卸载均通过 | backend r8 / LuCI r3 通过 |
| OpenWrt 24.10.7 | `.ipk` | GitHub SDK、安装、r14→r15 升级、服务与卸载均通过 | backend r8 / LuCI r3 通过 |

当前 backend r15 / LuCI r4 已完成本地检查、GitHub 双版本真实 SDK 构建，以及
官方 OpenWrt 双版本 QEMU 安装、从 r14/r3 原位升级、配置保留、procd/rpcd/ubus
和卸载验证。过程未连接主路由器或真实 U25S。记录见
[r15/r4 验证记录](docs/validation/2026-07-31-r15-r4-qemu.md)。历史 r8/r3 的
QEMU 与当时的 OpenWrt 25.12.5 Cudy TR3000 实机只读 probe 见
[r8/r3 验证记录](docs/validation/2026-07-31-r8-r3-qemu.md)。

目标固件登录脚本后续复核发现第一轮 SHA-256 也必须使用大写十六进制；backend
r9 已完成双 SDK 构建并正式升级。backend r10 随后加入跨进程登录串行化并在
同一设备正式升级，但单次校准 probe 仍返回 `authentication_failed`，因此并发
不是该认证失败的根因。backend r11 对齐了登录 POST 和成功码并在同一设备正式
升级，但唯一一次 probe 仍返回 `authentication_failed`。随后当时对目标固件
`config.js` 和 `service.js` 的被动复核曾判断 `HAS_LOGIN:false`。backend r12
按该契约改为匿名读取后，实机 probe 已越过认证并
准确停在 modem 状态检查；只读响应确认目标枚举为 `modem_init_complete`。backend
r13 已纳入实机 modem 状态并通过主路由器唯一一次只读 probe。随后守护进程
暴露出目标固件在满电时返回 `battery_charging=2`；backend r14 已修复实机满电状态枚举，
按原生 WebUI 语义将该值规范化为“已充满、未主动充电”，同时保留密码入口给需要
认证的固件变体。记录见
[r9 登录摘要校准](docs/validation/2026-07-31-r9-login-digest.md)。
实机部署与会话锁记录见
[r10 会话锁验证](docs/validation/2026-07-31-r10-session-lock.md)。
目标固件免登录契约与 r12 实机结果见
[r12 认证契约校准](docs/validation/2026-07-31-r12-auth-contract.md)。
实机 modem 状态枚举校准见
[r13 modem 状态校准](docs/validation/2026-07-31-r13-modem-state.md)。
满电枚举修复与实机状态恢复见
[r14 电池充电枚举校准](docs/validation/2026-07-31-r14-battery-charging.md)。

2026-08-01 对当前设备静态资源再次核验后，`config.js` 明确为
`HAS_LOGIN:true`、`PASSWORD_ENCODE:true`，登录页也会执行双 SHA-256 认证；项目
因此恢复“写操作必须登录”的安全契约，但仍允许状态读取先尝试匿名探测。当前保存
的凭据被设备以登录结果码 `3` 拒绝，认证模块与全部写操作在有效凭据完成校准前
继续保持关闭。详见
[认证契约复核](docs/validation/2026-08-01-auth-contract-recheck.md)。

当前源码对应的下一预发布标签为 `v0.1.0-rc1-r16`，尚未发布；只有维护者显式创建并推送与包元数据
匹配的 tag 才会发布。带 `-rc` 的 tag 自动创建 prerelease，稳定版 tag 创建普通
Release。已发布的 r15 / LuCI r4 通过了双 SDK 与 QEMU 复验，但不包含本次
产品边界重置，也不代表真实设备写接口或 72 小时稳定性验收已经完成。

当前候选安装包已发布到
[v0.1.0-rc1-r15 prerelease](https://github.com/caixy-plus/zte-usb-wifi-manager/releases/tag/v0.1.0-rc1-r15)，
Release 原文件已在两套全新 QEMU overlay 中再次完成安装、服务和卸载验证。
同一份 APK 已在目标 Cudy TR3000 v1 / OpenWrt 25.12.5 上从 backend r14、
LuCI r3 正式升级到 r15/r4；服务、rpcd/ubus、在线快照、文件权限和只读供电探测
均通过，所有真实写入门控保持关闭。实机记录见
[r15/r4 正式部署验证](docs/validation/2026-08-01-r15-r4-formal-deployment.md)。

两个包均为纯脚本和静态资源，发布时标记为 `all` 架构。这里的 `all` 只表示不受
CPU 架构限制，不表示可以跨 OpenWrt 软件包格式或发行系列安装。未列出的 OpenWrt
版本目前不受支持，请勿强制安装。

### 1. 确认路由器信息

通过 SSH 登录路由器，记录固件版本、target 和架构：

```sh
ubus call system board
apk --print-arch 2>/dev/null || opkg print-architecture
```

Release 中的两个包是架构无关包，可用于兼容矩阵中同一 OpenWrt 版本的不同 CPU
架构；不能跨 OpenWrt 版本或包格式使用。自行构建时仍应使用与路由器相同 OpenWrt
版本的软件源。升级或安装前建议先备份路由器配置。

### 2. 获取安装包

正式发布后，普通用户应从
[GitHub Releases](https://github.com/caixy-plus/zte-usb-wifi-manager/releases)
下载两个与路由器匹配的包：

- `zte-usb-wifi-manager`：后端守护进程和 rpcd 接口。
- `luci-app-zte-usb-wifi-manager`：LuCI 页面、菜单和 ACL。

如果 Releases 页面没有适配当前固件的 `.apk` 或 `.ipk`，不要使用其他固件版本的包；
请按下方“从源码构建”使用匹配的 OpenWrt SDK。

下载后应按照 Release 附带的 `SHA256SUMS` 校验文件。`--allow-untrusted` 仅用于安装本项目
官方 Release 或用户自行构建的包，不应对来源不明的 OpenWrt 包使用。

将两个文件上传到路由器 `/tmp`：

```sh
ROUTER_HOST=192.168.1.1
scp zte-usb-wifi-manager*.apk luci-app-zte-usb-wifi-manager*.apk \
    "root@$ROUTER_HOST:/tmp/"
```

旧版 OpenWrt 使用 `.ipk` 时，将命令中的 `*.apk` 改成 `*.ipk`。

### 3. 安装软件包

OpenWrt 25.12.5 使用 APK：

```sh
apk update
apk add --allow-untrusted \
    /tmp/zte-usb-wifi-manager*.apk \
    /tmp/luci-app-zte-usb-wifi-manager*.apk
```

OpenWrt 24.10.7 使用 opkg：

```sh
opkg update
opkg install \
    /tmp/zte-usb-wifi-manager_*.ipk \
    /tmp/luci-app-zte-usb-wifi-manager_*.ipk
```

包管理器会从当前固件的软件源解析 `coreutils-stat`、`curl`、`ip-tiny`、`jshn`、
`rpcd`、`ubus` 和 `uci` 等依赖。不要使用 `--force-depends` 或
`--force-architecture`。

### 4. 配置 U25S 凭据

安装后先打开 LuCI：**服务 → 中兴随身 WiFi → 设备登录**。需要认证的
U25S 可以在这里输入管理密码并点击“保存登录凭据”。页面只提供写入入口，不会读取、回显或保存在
浏览器中；后端以 root 身份原子写入权限为 `0600` 的凭据文件。

部分 U25S 固件允许免登录读取状态。插件会先执行只读探测，成功时不强制要求
密码；保存的密码仅在设备明确要求认证时使用。保存成功仅表示凭据安全落盘，
不等同于密码已经通过设备验证。

无 LuCI 时可用编辑器配置。为避免密码进入 shell 历史：

```sh
umask 077
mkdir -p /etc/zte-usb-wifi-manager
touch /etc/zte-usb-wifi-manager/credentials
chmod 600 /etc/zte-usb-wifi-manager/credentials
vi /etc/zte-usb-wifi-manager/credentials
```

文件只包含一行：

```text
password=<U25S_WEB_PASSWORD>
```

如实际连接参数与默认值不同，修改 UCI：

```sh
uci set zte-usb-wifi-manager.zte.host='192.168.0.1'
uci set zte-usb-wifi-manager.zte.interface='usbwan'
uci set zte-usb-wifi-manager.zte.netdev='eth2'
uci commit zte-usb-wifi-manager
```

当前生产能力矩阵仍保持设备写操作关闭：

```sh
uci set zte-usb-wifi-manager.main.write_enabled='0'
uci commit zte-usb-wifi-manager
```

### 5. 启动并验证

```sh
/etc/init.d/zte-usb-wifi-manager enable
/etc/init.d/zte-usb-wifi-manager restart
/etc/init.d/zte-usb-wifi-manager status

ubus list zte_usb_wifi
ubus call zte_usb_wifi capabilities
ubus call zte_usb_wifi status
```

然后在 LuCI 打开：**服务 → 中兴随身 WiFi**。

如果状态异常：

```sh
logread -e zte-usb-wifi-manager
ls -l /etc/zte-usb-wifi-manager/credentials
cat /var/run/zte-usb-wifi-manager/status.json
```

请勿在 Issue 中粘贴密码、Cookie、认证摘要、IMEI、IMSI、ICCID、手机号或短信内容。

### USB 故障恢复研究工具

仓库保留的 `zte-usb-power-calibrate` 会真实关闭整个 USB 端口，数据连接必然
中断。它不是充电管理功能，不应在日常使用或承担上网任务的路由器上运行。
开发者只能在备用 TR3000 v1 与备用 U25S 台架上使用其 `probe`、`execute` 和
`recover` 子命令研究显式故障恢复。正式 LuCI 页面目前不提供 USB 断电按钮。

### 备用 U25S SIM 写接口校准

以下命令只能在备用 U25S 上执行，不能用于主路由器或任何正在承担上网任务的设备。
`execute` 会真实切换 SIM 卡槽，完成验证后自动切回原槽。

先确认设备状态可读并记录当前活动目标：

```sh
/usr/libexec/zte-u25s-sim-calibrate probe
```

确认连接的是备用 U25S 后，选择一个不同于当前活动目标的
`physical`、`sim1`、`sim2` 或 `sim3`：

```sh
/usr/libexec/zte-u25s-sim-calibrate execute I_AM_ON_SPARE_U25S <不同目标>
```

如果执行、恢复或清理失败，工具会保持 manager stopped，并保留 canonical state
和 calibration lock，避免在恢复状态不明确时继续访问设备。修复外部条件后使用
有界重试恢复原槽和 manager 状态：

```sh
/usr/libexec/zte-u25s-sim-calibrate recover
```

恢复记录与锁分别持久保存在
`/etc/zte-usb-wifi-manager/sim-calibration` 和
`/etc/zte-usb-wifi-manager/sim-calibration.lock`，目录权限为 `0700`、状态文件
权限为 `0600`，并在真实切卡前和清理前使用 `/bin/sync` 落盘。路由器重启后只要
任一恢复路径仍存在（包括符号链接），init 就会拒绝启动 manager 和 recovery
coordinator；必须人工运行上述 `recover`，不会自动触发真实切卡。

校准工具不改变生产 capability；`ZTE_CAP_SIM_SWITCH=0` 仍保持关闭。只有备用
U25S 实机验收全部通过后，才会在后续独立变更中开放生产 SIM 切换能力。

### 72 小时稳定性验收

备用硬件校准通过后，在路由器运行：

```sh
ZTE_SOAK_OUTPUT=/var/run/zte-usb-wifi-manager/soak/72h.jsonl \
    nohup /usr/libexec/zte-usb-soak run 259200 60 \
    >/tmp/zte-usb-soak.out 2>&1 &
```

完成后把 `72h.jsonl` 复制回电脑，在仓库根目录验证：

```sh
node scripts/verify-router-soak.js 72h.jsonl \
    --duration 259200 \
    --max-rss-growth-kb 2048 \
    --max-fd-growth 4 \
    --max-status-age 180 \
    --max-event-log-bytes 524288 \
    --max-sample-gap 180 \
    --max-pid-changes 0
```

采样只包含两个守护进程的存活/PID/RSS/文件句柄、恢复服务状态、状态、供电、恢复互锁、网卡存在性和日志大小；
不读取凭据、Cookie 或设备标识。验证器会拒绝时长不足、资源持续增长、状态陈旧、
无 inhibit 的断电记录及任何未声明字段。

### 从源码构建

在 Linux 上下载与目标路由器完全匹配的
[OpenWrt SDK](https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk)，解压后：

```sh
git clone https://github.com/caixy-plus/zte-usb-wifi-manager.git \
    ../zte-usb-wifi-manager

./scripts/feeds update -a
./scripts/feeds install -p luci luci-base

ln -s "$(realpath ../zte-usb-wifi-manager/package/zte-usb-wifi-manager)" \
    package/zte-usb-wifi-manager
ln -s "$(realpath ../zte-usb-wifi-manager/luci-app-zte-usb-wifi-manager)" \
    package/luci-app-zte-usb-wifi-manager

printf '%s\n' \
    'CONFIG_PACKAGE_zte-usb-wifi-manager=m' \
    'CONFIG_PACKAGE_luci-app-zte-usb-wifi-manager=m' >>.config
make defconfig

make package/zte-usb-wifi-manager/compile V=s
make package/luci-app-zte-usb-wifi-manager/compile V=s
```

构建结果位于 SDK 的 `bin/packages/` 目录。OpenWrt 25.12.5 生成 `.apk`，
OpenWrt 24.10.7 生成 `.ipk`。编译环境路径中不要包含空格，也不要使用与目标固件
不同版本的 SDK。这里只安装构建 LuCI 所需的 feed 元数据；运行时依赖由目标固件
的软件包管理器从对应版本的官方签名软件源解析。

### 卸载

包管理器会先检查 SIM 校准恢复状态；如果
`/etc/zte-usb-wifi-manager/sim-calibration` 或
`/etc/zte-usb-wifi-manager/sim-calibration.lock` 仍存在，升级或卸载会 fail-closed，
且不会自动调用真实 SIM `recover`。请先按“备用 U25S SIM 写接口校准”完成有界
恢复。没有 SIM 恢复状态时，包管理器才会停止管理器并运行
`/usr/libexec/zte-usb-power-restore`。如果无法确认 USB 已恢复上电或恢复服务
状态已处理，卸载仍会失败并保留运行时安全标记，避免把设备留在无协调状态。

```sh
/etc/init.d/zte-usb-wifi-manager stop
/etc/init.d/zte-usb-wifi-manager disable
```

OpenWrt 25.12.5：

```sh
apk del luci-app-zte-usb-wifi-manager zte-usb-wifi-manager
```

OpenWrt 24.10.7：

```sh
opkg remove luci-app-zte-usb-wifi-manager zte-usb-wifi-manager
```

## 仓库结构

```text
.
├── package/zte-usb-wifi-manager/        # 后端包、守护进程、策略与适配器
├── luci-app-zte-usb-wifi-manager/       # LuCI 菜单、ACL 和只读状态总览
├── tests/                               # POSIX Shell 测试
├── docs/design/                         # UI 成品稿与详细设计文档
├── docs/plans/                          # 可执行实施计划
└── .github/workflows/ci.yml             # GitHub Actions
```

## 设计资料

- [UI 成品设计稿](docs/design/zte-usb-wifi-manager-ui.html)
- [详细设计文档](docs/design/zte-usb-wifi-manager-design.md)
- [四阶段交付与 QEMU 验证](docs/validation/2026-07-30-four-stage-delivery.md)
- [TR3000 USB 供电与稳定性预检](docs/validation/2026-07-31-power-hardware-preflight.md)
- [框架层实施计划](docs/plans/2026-07-29-framework-foundation.md)
- [Phase 1 只读实施计划](docs/plans/2026-07-29-phase1-read-only.md)

## 本地验证

依赖：POSIX Shell、GNU Make 或 BSD Make、Node.js。完整静态检查还需要 ShellCheck。

```sh
make test
make lint
```

`make test` 会运行配置校验、状态机、U25S 模拟器、动作队列、Power Adapter、
供电校准与恢复互锁、72 小时采样验证、加速稳定性、双版本打包、LuCI、
Shell/JSON 语法和敏感信息模式检查。

## 安全边界

- 后端默认不允许设备写操作。
- 密码、Cookie、号卡身份和短信正文不得进入仓库或日志。
- LuCI 不直接执行 shell。
- 未校准的设备能力必须返回 unsupported，不得仅通过隐藏按钮控制。
- USB 供电不得由电量或日程触发；未来若开放人工恢复，必须明确提示数据会中断。

## 路线

1. ✅ 已接入 U25S 只读登录和批量状态读取。
2. 补齐经过脱敏和审核的 Wi-Fi、流量及短信元数据 fixture。
3. 在备用 TR3000 + U25S 上逐项校准设备写接口和操作后验证。
4. 实现设备设置、短信、SIM 和系统动作的逐项回读验证。
5. 完成备用硬件 72 小时稳定性测试，再进行主路由器安全验收。

## 贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。

## License

[MIT](LICENSE)
