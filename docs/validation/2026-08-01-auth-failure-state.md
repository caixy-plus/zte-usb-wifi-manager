# U25S 认证失败状态验证

日期：2026-08-01

## 问题

适配器此前把 LOGIN 被设备拒绝与 HTTP/JSON 读取失败都返回为状态 1。daemon 因此
只能生成 `degraded/device_read_failed`，管理页无法提示用户更新密码。

## 修复

- 缺少密码仍返回适配器状态 2，对应 `credentials_missing`。
- LOGIN 被拒绝返回状态 3，对应
  `authentication_failed/device_authentication_failed`。
- 认证失败仍计入连续失败次数并参与轮询退避，避免设备锁定期间高频重试。
- LuCI 将该状态显示为“设备认证失败”，保留最后可信设备数据时明确标为陈旧。
- 72 小时采样器接受该状态，不把可解释的认证故障误判为损坏快照。

当前设备的登录失败计数与锁定时间均为非零。本次仅记录零/非零状态，没有保存实际
计数、时间、密码、挑战值或 Cookie，也没有在锁定期再次发起登录。

## 自动化覆盖

- Adapter 验证登录拒绝返回精确状态 3。
- daemon 行为测试验证状态、原因、失败计数和快照内容。
- LuCI 验证中文状态及陈旧数据标识。
- soak collector/validator 验证新状态保持兼容。
