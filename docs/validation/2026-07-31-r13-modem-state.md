# r13 U25S modem 就绪枚举校准（2026-07-31）

## 实机证据

r12 在目标 Cudy TR3000 + U25S 上成功跳过不必要的 LOGIN，唯一一次 probe 从
`authentication_failed` 前进到 `modem_not_connected`。同一设备的匿名只读响应
显示：

- `simcard_active_slot_temp` 有效；
- `mc_modem_main_state=modem_init_complete`；
- 运营商字段非空；
- `ppp_status=ipv4_ipv6_connected`。

目标固件公开的 `js/status/statusBar.js` 同样把 `modem_init_complete` 作为有服务时
显示正常信号的 modem 状态，因此这是已由实机与固件双重证实的就绪枚举。

## r13 行为与 TDD

适配器新增统一 `zte_adapter_modem_ready()`，只接受：

- `connected`：保留认证模拟器和既有 fixture 兼容；
- `modem_init_complete`：目标 U25S 实机状态。

probe、执行前读取和操作后回读统一使用该函数；空值、offline 和其他未知枚举继续
失败关闭。红灯时实际枚举分别导致 adapter、动作执行器和校准 probe 测试失败；
最小实现后：

- `test_adapter`：71 assertions PASS；
- `test_action_executor`：27 assertions PASS；
- `test_sim_calibration`：419 assertions PASS；
- ShellCheck：PASS。

## 尚未完成

r13 仍需全量检查、双 SDK 构建、正式升级和一次新的匿名只读 probe。只有 probe
返回 `ok:true`，才转移到备用 U25S 执行 SIM 切换与回读校准。主路由器不执行 SIM
写或 USB 断电测试。
