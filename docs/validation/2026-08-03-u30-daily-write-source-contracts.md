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
| 连接模式 | `SET_CONNECTION_MODE` | `ConnectionMode` 与固定的漫游自动连接 `off` |
| APN | `APN_PROC` / `set_default` | 当前 APN、认证模式、用户名（不读回密码） |
| 2.4 GHz Wi-Fi | `setAccessPointInfo` | 开关、SSID、认证模式（不读回密码） |
| 流量套餐 | `DATA_LIMIT_SETTING` | 套餐开关、固定 `data` 单位、上限、提醒比例、固定自动清零、周期日、到量断网 |
| 流量清零 | `RESET_DATA_COUNTER` | 月度发送、接收、时长均为零 |
| 短信删除 | `DELETE_SMS` | 写前确认 ID 存在，关联 `sms_cmd=6` 的状态变化，再确认 ID 不再存在 |
| 短信已读 | `SET_MSG_READ` | 指定消息 tag 为 `0` |
| 短信发送 | `SEND_SMS` | 写前状态基线，关联 `sms_cmd_status_info` 的 `sms_cmd=4` 状态变化 |
| 设备重启 | `REBOOT_DEVICE` | 写前确认在线，观测达到最短窗口的离线，再观测状态接口恢复 |
| 设备关机 | `SHUTDOWN_DEVICE` | 写前确认在线并持续离线到验证窗口结束；必须另有恢复路径才允许校准 |

所有 POST 都是单次执行：传输失败属于结果不明确，不自动重复写入。读回可以按
有界次数重试。APN 写入会先读取当前 profile/index，再按页面的 `set_default` 契约
更新；该静态契约只证明 APN 和认证凭据修改，因此产品不提供虚假的 PDP 类型选择，
请求保留页面固定的 `apn_pdp_type=PPP` 传输字段。Wi-Fi 严格服从目标配置的
`WIFI_HAS_5G=false`，不从通用页面代码臆造 5 GHz
能力；短信正文使用严格 UTF-8 解码并复刻 WebUI 的十六进制编码和编码类型判断。
GSM7 与 Unicode 分别执行 WebUI 的 765/335 编码单位上限。这些实现均不读取
APN/Wi-Fi 密码作为读回依据。daemon 在动作出队后还会从记录中提取完整 payload，
再次执行重复键、未知字段、类型、范围和危险操作确认校验；队列文件即使被篡改也不会
直接进入执行器。

## 门控状态

静态源码只能证明请求构造，不能证明目标固件副作用和恢复行为。流量、短信、重启、
关机以及智能充电的生产 capability 和默认 UCI 写开关继续保持 `0`。最后阶段将在
备用/目标设备上逐项写入、读回、恢复原值，并只开放验证成功的能力。
