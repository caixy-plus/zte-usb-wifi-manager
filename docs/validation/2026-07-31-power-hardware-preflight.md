# TR3000 USB 供电与稳定性预检（2026-07-31）

## 结论

真实供电的生产代码、恢复互锁、备用台架校准工具和 72 小时采集/验证工具已完成
离线预检；**尚未取得备用 TR3000 v1 + U25S 的真实断电、重新枚举和 72 小时证据**。
因此默认配置继续保持：

```uci
option write_enabled '0'
option backend 'unconfigured'
option calibrated '0'
```

本文不把源码证据、单元测试或主路由器只读状态冒充为硬件校准。

## 板级入口证据

目标固件上游提交
[`86356f8`](https://github.com/padavanonly/immortalwrt-mt798x-6.6/commit/86356f8a2f796e5808fda25ce3e3bf6b3cc3278e)
在 TR3000 v1 DTS 中导出 `modem_power`，使用 GPIO 9、`GPIO_ACTIVE_LOW`，并修正
默认供电状态。候选操作为：

```text
OFF → /sys/class/gpio/modem_power/value 写 0
ON  → /sys/class/gpio/modem_power/value 写 1
```

生产适配器不接受其他板型、节点、数值或任意命令。

## 已完成的安全门控

- `hardware` 只允许 `cudy,tr3000-v1` 和固定 sysfs 节点。
- `write_enabled=1`、`usb.calibrated=1`、板型匹配和恢复服务可用必须同时成立。
- 每次 GPIO 写入后必须读回期望值，否则动作失败。
- 真实 OFF 前先写带期限的 inhibit，再停止 `/etc/init.d/zte-usb-recover`。
- ON 成功后先恢复 `zte-usb-recover`，再清除 inhibit。
- 设备动作排队或执行期间禁止真实 OFF。
- 守护进程正常退出、升级停止或收到 TERM/INT 时 best-effort 恢复 ON。
- 独立 procd recovery coordinator 每 30 秒处理过期/损坏 inhibit；即使主守护
  进程因配置错误无法运行，也会重启恢复服务并解除标记。
- OFF 写入可能成功但读回失败时保留有期限的 inhibit，避免立即触发竞争恢复。
- 默认包升级不会自动把已有设备切换到 `hardware` 或标记为已校准。

## 离线自动化

专项用例覆盖：

- Power Adapter：板型、固定路径、校准标志、ON/OFF 映射、写后读回和失败不改记录。
- recovery adapter：停止/启动、写 inhibit、失败回滚、过期/损坏标记协调。
- calibration：默认只读、错误确认词拒绝、断电/上电、网卡消失/恢复、异常清理。
  ON 读回失败会保留 inhibit/锁；`recover` 可在硬件恢复后安全重试。
- soak collector：两个守护进程的 PID/RSS/文件句柄、恢复服务状态、状态年龄、
  供电、inhibit、网卡和日志大小。
- soak verifier：72 小时时长、最大采样间隙、PID 变化、资源增长、陈旧状态、
  恢复服务与断电竞争、日志上限、无 inhibit 断电和未声明字段拒绝。

完整结果以当前提交的 `make check` 和 GitHub Actions 为准。

## 备用台架必须补齐的证据

1. `/usr/libexec/zte-usb-power-calibrate probe` 返回全部探测项成功。
2. 显式执行 `execute I_AM_ON_SPARE_HARDWARE` 后：
   - OFF 读回为 `0`；
   - 只有目标 USB 端口受影响；
   - `eth2` 消失；
   - ON 读回为 `1`；
   - `eth2` 在限时内恢复；
   - U25S 管理接口重新可读；
   - `zte-usb-recover` 没有在计划断电期间触发竞争复位。
3. 手动终止守护进程、写入失败和恢复服务失败时均回到安全供电状态。
4. 以 60 秒间隔连续采样至少 259200 秒，验证器通过且：
   - 最大采样间隙不超过 180 秒；
   - daemon PID 不变化；
   - RSS 波动不超过 2048 KiB；
   - 文件句柄波动不超过 4；
   - 所有状态（包括计划断电）的年龄不超过 180 秒；
   - 所有 OFF 样本均有有效 recovery inhibit，且 recovery 服务未运行；
   - 事件日志不超过 524288 字节。

只有上述证据全部归档后，才能把硬件 profile 标记为已校准并进入稳定版发布。
