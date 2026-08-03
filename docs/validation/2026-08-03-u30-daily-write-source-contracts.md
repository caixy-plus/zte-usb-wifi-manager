# U30 Pro 日常写操作静态契约复核

## 范围

本轮只读取 U30 Pro 自身通过 HTTPS 提供的静态 WebUI 文件，没有安装软件包，
没有提交任何设备写请求，也没有读取或保存 Cookie、设备唯一标识和短信正文。

复核来源为 `js/service.js`、`js/config/config.js` 和
`js/config/ufi/mu3351/config.js`。机器可读摘要保存在
`tests/fixtures/u30/write-contracts.json`，不保存厂商完整源文件。

## 已冻结的请求

| 语义操作 | goformId | 安全读回 |
|---|---|---|
| 连接模式 | `SET_CONNECTION_MODE` | `ConnectionMode` |
| 流量套餐 | `DATA_LIMIT_SETTING` | 套餐开关、上限、提醒比例、周期日、到量断网 |
| 流量清零 | `RESET_DATA_COUNTER` | 月度发送、接收、时长均为零 |
| 短信删除 | `DELETE_SMS` | 指定消息 ID 不再存在 |
| 短信已读 | `SET_MSG_READ` | 指定消息 tag 为 `0` |
| 设备重启 | `REBOOT_DEVICE` | 先观测离线，再观测状态接口恢复 |
| 设备关机 | `SHUTDOWN_DEVICE` | 连续离线；必须另有恢复路径才允许校准 |

所有 POST 都是单次执行：传输失败属于结果不明确，不自动重复写入。读回可以按
有界次数重试。APN、Wi-Fi 设置和短信发送仍需要补齐当前页面上下文或字符编码契约，
因此本轮不把这三项标记为已实现，也不开放对应 capability。

## 门控状态

静态源码只能证明请求构造，不能证明目标固件副作用和恢复行为。流量、短信、重启、
关机以及智能充电的生产 capability 和默认 UCI 写开关继续保持 `0`。最后阶段将在
备用/目标设备上逐项写入、读回、恢复原值，并只开放验证成功的能力。
