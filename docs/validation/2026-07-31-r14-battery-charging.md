# r14 U25S 电池充电枚举校准（2026-07-31）

## 实机证据

r13 的唯一一次只读 probe 已通过，但守护进程快照持续进入
`device_read_threshold_reached`。对同一只读响应逐字段检查确认，目标 U25S 在
电量 100% 时返回 `battery_charging=2`，其余网络、SIM 和电池字段均有效。

目标固件公开的 `convertBatteryPers()` 明确按以下语义渲染：

- `0`：未充电；
- `2`：已充满；
- `1`：充电动画。

因此旧适配器仅允许通用布尔值 0/1，会错误拒绝一个合法的满电快照。

## r14 行为

新增设备专用充电枚举映射：`0` 和 `2` 规范化为 JSON `false`，`1` 规范化为
JSON `true`；既有 `false/no`、`true/yes` fixture 兼容不变，未知值继续失败关闭。
测试明确覆盖实机的满电值和充电值。

本地验证结果：

- `test_adapter`：73 assertions PASS；
- `make check`：全部测试、ShellCheck、JSON 检查和敏感数据扫描通过；
- `test_packaging`：151 assertions PASS，r14 的 APK/IPK 文件名、manifest 和 tag
  契约一致。

## 安全边界

r14 只修复只读状态规范化，不改变任何能力开关。正式升级后仍必须确认
`write_enabled=0`、`power_backend=unconfigured`、`power_calibrated=0` 和
`policy.enabled=0`。真实 SIM 写入与 USB 断电继续只允许在备用硬件台架执行。

## 构建与正式升级结果

r14 源码提交 `49b6c466cf2c684975266851cb857039c126e049` 的 GitHub Actions
运行 `30625146721` 全部通过：检查、OpenWrt 25.12.5 APK SDK、OpenWrt 24.10.7
IPK SDK 和聚合产物均成功。聚合产物经 `SHA256SUMS` 复核全部通过：

- APK：`c5d78c0174b1c3f94cf152f060a6dd6b24eb2800294d829ee08c745387eb0862`；
- IPK：`b20a23a1cb683ab52b94a9deb34cc7d3dddd92bfc143f665a9bc4fa56f4fe74c`。

目标 Cudy TR3000 已从 r13 正式升级到 r14，并正常重启服务加载新代码。首个新
快照恢复为 `online=true`、`state=ok`、`failures=0`，电量 100% 时
`battery.charging=false`；网络为 `NR5G-SA`，SIM 原始槽位仍为 `2`，PPP 保持
`ipv4_ipv6_connected`。

升级后复核：四个写入/硬件控制开关仍为 `0,unconfigured,0,0`，凭据文件保持
`0600 root`，crontab SHA-256 未变化，临时 APK 与临时 SSH 密钥均已删除，LuCI
页面显示“设备在线 / 后端状态正常”。本次没有再次执行 probe，也没有执行任何
SIM 写入或 USB 断电。
