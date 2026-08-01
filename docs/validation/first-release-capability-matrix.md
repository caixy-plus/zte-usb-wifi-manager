# 首版能力矩阵冻结

冻结基线：backend r21 / LuCI r10（2026-08-01）

机器可读契约位于 `tests/fixtures/u25s/capabilities-first-release.json`，
`tests/test_adapter.sh` 会对完整 JSON 结构做回归比较。后续能力状态发生变化时，必须
同时提交实现证据、更新该 fixture，并经过对应层级验证，不能只修改前端标签。

| 能力 | 实现状态 | 验证状态 | 生产启用 |
|---|---|---|---|
| 移动网络状态 | implemented | local_and_qemu | 是 |
| U25S Wi-Fi 状态 | implemented | local_and_qemu | 是 |
| 接入设备明细 | implemented | simulator_only | 是，待实机认证 |
| 流量状态 | implemented | local_and_qemu | 是 |
| 短信收件箱 | implemented | simulator_only | 是，待实机认证 |
| 设备状态 | implemented | local_and_qemu | 是 |
| SIM 切换 | implemented | spare_device_required | 否 |
| 移动网络设置 | not_implemented | spare_device_required | 否 |
| Wi-Fi 设置 | not_implemented | spare_device_required | 否 |
| 流量设置 | not_implemented | spare_device_required | 否 |
| 短信操作 | not_implemented | spare_device_required | 否 |
| 设备重启 | not_implemented | spare_device_required | 否 |
| 设备关机 | not_implemented | spare_device_required | 否 |
| 固件更新 | native_console_only | native_console | 否 |
| 恢复出厂 | native_console_only | native_console | 否 |
| 备份与恢复 | native_console_only | native_console | 否 |
| 设备密码 | native_console_only | native_console | 否 |

这里的“生产启用”由后端静态 capability、全局 UCI 写门和每项独立 UCI 功能门共同
决定。描述性 `feature_status` 与 LuCI 显示均不能绕过这些门控。
