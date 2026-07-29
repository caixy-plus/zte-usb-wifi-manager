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

## L2：U25S API 模拟器

当前形态：fixture + 函数级 stub（`zte_http_get`/`zte_http_post` 在测试中被重定义，
覆盖正常、缺字段、异常 JSON、会话过期）。后续如需更真实的 L2，在电脑上实现假的
`192.168.0.1` goform 服务：LD 挑战、SHA-256 登录、Cookie 过期、各类异常响应；
写接口默认拒绝，仅具体用例临时开启。设备适配器测试时只连模拟器，不连真实 U25S。

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
