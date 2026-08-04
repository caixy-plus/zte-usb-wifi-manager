# 测试策略：离线模拟为主、实机只做最终验收

> 2026-07-29 与项目所有者确认的分层测试架构。原则：**主路由器不承担开发测试**；
> 探索性测试全部在离线环境或备用硬件台架完成，主路由器只做最终只读灰度与验收。

## 分层架构

| 层级 | 环境 | 测试内容 | 是否碰主路由器 |
|---|---|---|---|
| L1 | macOS / GitHub CI | 策略、校验、状态机、日志、安全扫描 | 否 |
| L2 | ZTE API 模拟器 | 登录、状态读取、超时、异常响应、会话过期 | 否 |
| L3 | OpenWrt SDK / x86_64 QEMU | SDK 构建；按版本留存 QEMU 安装与服务集成证据 | 否 |
| L4 | Linux network namespace | 真实内核路由、`eth2` 重建与默认路由切换门禁 | 否 |
| L5 | 备用硬件台架 | 真实 U25S、USB 断电、重新枚举、蜂窝恢复 | 使用备用设备 |
| L6 | 主路由器灰度 | 只读、影子模式、最终验收 | 最后才使用 |

## L1：POSIX Shell 单元测试（已实现）

`tests/` 下的现有套件：validation、policy 状态机、json、http、session、adapter、
snapshot、netifd、structure。TDD，macOS 与 CI 均可运行。

## L2：U25S API 模拟器（已实现）

`tests/u25s_simulator.py` 使用 Python 标准库在 loopback 随机端口实现已观察到的 goform
只读协议；`tests/test_u25s_simulator.sh` 通过真实 curl 调用生产 session/adapter 代码，
不连接真实 U25S。标准 `make test` 已覆盖：

- LD 挑战、双 SHA-256 登录摘要和 Cookie 会话。
- 正常状态读取与生产 adapter 规范化。
- Cookie 单次过期、自动重新登录。
- 已知字段缺失、错误 JSON 和请求超时。
- 错误摘要登录、未知读取命令和非 LOGIN 写请求拒绝。
- 非 loopback 监听地址拒绝，失败时不发布 ready file。
- 请求日志不记录 Cookie、登录材料或摘要。

模拟器只允许绑定字面量 `127.0.0.1`，写接口没有启用开关；未来增加故障场景时
继续通过显式只读 scenario 扩展，不能提供通用写放行参数。

真实设备响应只采集一次，删除 Cookie、IMEI、IMSI、ICCID、手机号后保存为 fixture，
之后解析代码改动都用 fixture 回归。

## L3：OpenWrt SDK 与 QEMU

当前 backend r14 已完成 OpenWrt 25.12.5 APK 与 24.10.7 IPK 的真实 SDK 构建，
并完成目标 TR3000 / U25S 的只读实机状态校准。仓库已有的双版本 QEMU 安装、
procd、rpcd/ubus、升级与卸载通过记录对应历史 backend r8 / LuCI r3；它不能作为
r14 QEMU 已通过的证据。后续每个需要声明 QEMU 兼容性的版本，都要用该版本制品重新
执行并单独留档。Docker 可作为更快的 Shell/依赖兼容测试，但不能替代 QEMU 中的
procd、ubus 和 LuCI 集成验证。

## L4：Linux 网络仿真（已实现自动门禁）

独立 Ubuntu CI job 以 root 运行 `make test-l4`，用真实系统 `ip`、network namespace
和 veth 模拟：

```text
manager namespace
├── eth2 → u25s namespace
└── wan  → wan namespace
```

当前自动门禁调用生产 `json.sh` 和 `netifd-adapter.sh`，只替代 OpenWrt 专属的
`ubus` / `jsonfilter`。它验证 `eth2` 为默认路由时门禁为 true、切换默认路由到
`wan` 后门禁为 false 且 U25S 管理地址仍可达，以及删除并重建 `eth2` 后状态恢复。
DHCP 超时、U25S 无公网和代理故障等更高层场景仍是后续覆盖项。该测试是 Linux-only，
不加入兼容 macOS 的普通 `make test`。

## L5：备用硬件台架

USB 真实断电、USB 控制器重新枚举、`zte-usb-recover` 协调以及 U30 Pro 原生
`power_supply_mode` 的电池行为和 USB 数据连续性无法靠虚拟机证明，必须用备用
TR3000（或其他测试路由器）+ 备用中兴设备做硬件在环测试。

包内提供两个只供备用台架使用的工具：

- `/usr/libexec/zte-usb-power-calibrate`：默认只读探测；只有显式确认备用硬件后才
  短暂切换板型对应的固定供电 profile，并验证控制入口、`usb-vbus`、`eth2`
  消失/恢复和 U25S 管理接口。
- `/usr/libexec/zte-usb-soak`：以有界 JSONL 采集 72 小时运行指标；电脑端用
  `scripts/verify-router-soak.js --adapter zte_u30 --max-failures 3
  --max-action-results 50` 验证时长、适配器身份、设备原生供电模式、USB 数据连续性、
  状态新鲜度、RSS、文件句柄、失败计数、动作结果上限和恢复互锁。采集器默认每
  5 秒监测一次并跨 60 秒证据间隔锁存 USB 断链、最大失败计数和最大动作结果数；
  4 MiB 默认上限覆盖标准 72 小时证据量。
- `/usr/libexec/zte-u30-power-calibrate`：默认只读探测；只有精确 U30 配置档、所有生产
  写门关闭并输入备用机确认词后，才切到相反的设备原生供电模式并自动恢复原模式；
  每次写入都强制读回和检查管理路由，失败时持久保留可恢复状态并阻止 manager 启动。

官方 OpenWrt 的 TR3000 v1 DTS 把 GPIO 9 定义为 `usb-vbus` fixed regulator，
由 xHCI 控制器消费；官方 profile 使用固定 bind/unbind 入口并同时核对 regulator
状态。另有兼容固件导出 `modem_power`，两种 profile 均与板型严格绑定。源码和
主路由器只读证据只能确定候选控制路径，不能替代备用实机校准：
<https://github.com/openwrt/openwrt/blob/main/target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1.dtsi>。

## 电池策略：设备原生供电模式

U30 Pro 使用设备原生 `power_supply_mode`，不会关闭 USB VBUS：

- `charging`：允许电池充电。
- `direct_supply`：停止给电池充电，但预期保持 USB 数据连接。
- 未经备用设备双向校准时，生产静态 capability 和全部 UCI 写门保持关闭。

离线测试和未解锁阶段只记录策略决策不执行：

```text
decision=SET_DIRECT_SUPPLY
executed=false
reason=battery_reached_high
backend=device_power_supply
```

连续运行数天观察决策，无误判后才允许真实执行。

LuCI 保存智能充电阈值时采用可恢复 UCI 事务：rpcd 以非阻塞 `flock` 串行化
“旧值快照、私有 UCI savedir 提交、服务 reload、失败补偿”全过程，并把事务 ID、
新值、旧值和 `reload_pending`/`restore_pending` 状态与配置一次提交。daemon 不获取
事务锁也不清除标记；它只验证刚加载的配置与标记状态，原子写入 mode-0600 的运行时
ACK。rpcd 在仍持锁时验证 ACK 的事务 ID、状态和值，并在 reload 前、接受 ACK 时和
清除标记前重新核对 committed 配置的 raw 值及 option presence；匹配后才清除标记。
下一次写请求会先清理安全的孤立 ACK、消费当前 ACK 或恢复未完成事务。锁、标记、
ACK、配置漂移或清理状态有任何歧义时拒绝新写入，
daemon 则继续只读运行并关闭该进程的自动充电写入。`tests/test_charging_transaction.sh`
使用有 committed/staged 状态的 UCI 模拟器覆盖并发锁争用、信号中断、SIGKILL 遗留
savedir 回收、ACK 缺失/延迟/畸形、配置漂移，以及通过预置 durable marker 模拟的
initial commit 后和 restore commit 后恢复入口；它不宣称用真实 SIGKILL 命中每条
commit/reload/marker-clear 指令之间的微小时间窗。

U30 Pro 的正式 72 小时验收必须指定 `--adapter zte_u30`。验证器允许设备在
`charging` 和 `direct_supply` 之间切换，但任何板级 VBUS 关闭、`eth2` 消失、适配器
变化、连续失败计数超过 3 或动作结果文件超过守护进程上限 50，只要被内部监测捕获
就会持久锁存并判定为失败。五秒以下瞬态仍属于最终备用硬件事件日志和链路专项测试
的覆盖范围，不把轮询采样表述为无损硬件事件捕获。

## 故障注入清单

- U25S API 超时、拒绝连接、错误 JSON
- Cookie 过期
- 电池字段缺失或超过 100%
- SIM 被拔出
- PPP 长时间无法恢复
- 守护进程被强制终止
- 系统时间未同步或跳变
- USB 设备重复枚举
- `zte-usb-recover` 与计划断电并发
- 日志达到上限
- OpenClash、LED 服务重启
- 有线 WAN 与 usbwan 同时在线

任何无法确认的状态都必须保持现状，不能主动切换供电模式或断电。

## 主路由器最终上线流程（L6）

1. 只安装 LuCI 和只读后端。
2. `write_enabled=0`，运行至少 7 天。
3. 确认 CPU、内存、文件句柄和日志无持续增长。
4. 开启 `dry-run`，观察电池决策。
5. 单独开放一个经过验证的手动动作。
6. 最后才开放自动供电控制。
7. 每项能力都有独立 feature flag，可立即关闭。
8. 保留卸载包和恢复配置的离线命令。
