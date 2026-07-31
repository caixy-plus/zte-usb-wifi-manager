# 测试策略：离线模拟为主、实机只做最终验收

> 2026-07-29 与项目所有者确认的分层测试架构。原则：**主路由器不承担开发测试**；
> 探索性测试全部在离线环境或备用硬件台架完成，主路由器只做最终只读灰度与验收。

## 分层架构

| 层级 | 环境 | 测试内容 | 是否碰主路由器 |
|---|---|---|---|
| L1 | macOS / GitHub CI | 策略、校验、状态机、日志、安全扫描 | 否 |
| L2 | ZTE API 模拟器 | 登录、状态读取、超时、异常响应、会话过期 | 否 |
| L3 | OpenWrt x86_64 QEMU | APK 安装、procd、rpcd、ubus、UCI、LuCI | 否 |
| L4 | Linux 网络仿真 | 模拟 `usbwan`、`eth2`、DHCP、默认路由切换 | 否 |
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

## L3：QEMU OpenWrt

OpenWrt x86_64 虚拟机验证：APK 安装/升级/卸载、procd 拉起守护进程、rpcd/ubus 对象
与 ACL、UCI 配置与重启恢复、LuCI 菜单页面、守护进程崩溃/配置损坏/磁盘不足行为、
卸载后服务停止与运行状态清理。Docker 可作为更快的 Shell/依赖兼容测试，但 procd、
ubus、LuCI 验证必须用 QEMU。

## L4：Linux 网络仿真

CI 中用 network namespace + veth 模拟：

```text
OpenWrt namespace
├── usbwan / eth2 → 模拟 U25S
├── wan           → 模拟有线宽带
└── lan           → 模拟局域网客户端
```

覆盖：只有 usbwan；只有物理 WAN；WAN 为默认出口但 U25S 仍可管理；DHCP 超时；
eth2 消失后重现；默认路由切换；U25S 可管理但不能上网；代理不可用不影响插件状态机。

## L5：备用硬件台架

USB 真实断电、USB 控制器重新枚举、`zte-usb-recover` 协调这三项无法靠虚拟机证明，
必须用备用 TR3000（或其他测试路由器）+ 备用 U25S 做硬件在环测试。

包内提供两个只供备用台架使用的工具：

- `/usr/libexec/zte-usb-power-calibrate`：默认只读探测；只有显式确认备用硬件后才
  短暂切换板型对应的固定供电 profile，并验证控制入口、`usb-vbus`、`eth2`
  消失/恢复和 U25S 管理接口。
- `/usr/libexec/zte-usb-soak`：以有界 JSONL 采集 72 小时运行指标；电脑端用
  `scripts/verify-router-soak.js` 验证时长、状态新鲜度、RSS、文件句柄和恢复互锁。

官方 OpenWrt 的 TR3000 v1 DTS 把 GPIO 9 定义为 `usb-vbus` fixed regulator，
由 xHCI 控制器消费；官方 profile 使用固定 bind/unbind 入口并同时核对 regulator
状态。另有兼容固件导出 `modem_power`，两种 profile 均与板型严格绑定。源码和
主路由器只读证据只能确定候选控制路径，不能替代备用实机校准：
<https://github.com/openwrt/openwrt/blob/main/target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1.dtsi>。

## 电池策略：影子执行

Power Adapter 三种后端：

- `mock`：只记录动作，用于自动化测试。
- `dry-run`：读真实状态，绝不执行 USB 开关。
- `hardware`：最终验证通过后才允许控制硬件。

影子模式只记录决策不执行：

```text
decision=POWER_OFF
executed=false
reason=battery_reached_high
backend=dry-run
```

连续运行数天观察决策，无误判后才允许真实执行。

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

任何无法确认的状态都必须落到"保持现状"或 `FAIL_SAFE_ON`，不能主动断电。

## 主路由器最终上线流程（L6）

1. 只安装 LuCI 和只读后端。
2. `write_enabled=0`，运行至少 7 天。
3. 确认 CPU、内存、文件句柄和日志无持续增长。
4. 开启 `dry-run`，观察电池决策。
5. 单独开放一个经过验证的手动动作。
6. 最后才开放自动供电控制。
7. 每项能力都有独立 feature flag，可立即关闭。
8. 保留卸载包和恢复配置的离线命令。
