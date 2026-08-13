# 首版能力矩阵冻结（charge_v1）

当前源码基线：backend r37 / LuCI r14（`access_profile=charge_v1`）。

产品面已收敛为 **U30 Pro 智能充电 + 设备基础信息只读 + 原生管理页跳转**。
历史完整控制台能力（移动网络/Wi‑Fi/短信/流量写操作等）从产品面删除；
实现状态变化必须同时提交代码、测试和本矩阵。

| 能力 | U30 Pro | 生产启用 |
|---|---|---|
| 设备状态只读（型号/版本/电池/供电模式/蜂窝摘要等） | implemented | 是 |
| 智能充电策略（阈值 + daemon `power_supply_mode`） | implemented | 是 |
| 原生管理页跳转 | implemented | 是（外链） |
| 智能充电事件日志 | implemented | 是 |
| SIM / APN / Wi‑Fi / 流量 / 短信写 | unsupported（产品删除） | 否 |
| 重启 / 关机 / 手动供电模式按钮 | unsupported（产品删除） | 否 |
| USB VBUS 断电 / 硬件 power adapter | unsupported（产品删除） | 否 |
| U25S 作为产品目标 | unsupported（产品删除） | 否 |
| 固件更新/恢复出厂/备份/设备密码 | native_console_only | 否 |

机器可读能力输出以 `zte_adapter_effective_capabilities_json` 为准；
U30 默认仅 `set_power_supply_mode` 为可写实现。
