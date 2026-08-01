# U25S 流量与设备信息只读契约验证（2026-08-01）

## 验证范围

本次只读取目标 U25S 的静态 WebUI 脚本，并对明确列出的 goform 字段执行一次
无写入的 schema-only 请求。没有登录、提交表单、切换 SIM、修改网络设置或改变
USB 供电。

## 固件前端契约

目标 `service.js` 的状态批量请求及流量页面明确使用以下字段：

- 固件：`wa_inner_version`；
- 实时速率：`flux_realtime_tx_thrpt`、`flux_realtime_rx_thrpt`；
- 本次统计：`flux_realtime_tx_bytes`、`flux_realtime_rx_bytes`、
  `flux_realtime_time`；
- 本月统计：`flux_monthly_tx_bytes`、`flux_monthly_rx_bytes`、
  `flux_monthly_time`、`date_month`；
- 套餐：`flux_data_volume_limit_switch`、`flux_data_volume_limit_unit`、
  `flux_data_volume_limit_size`、`flux_data_volume_alert_percent`、
  `flux_auto_clear_flow_data_switch`、`flux_clear_date`、
  `flux_limited_disconnect`。

前端把空的速率、字节数和时长计数显示为零。套餐配置没有同等默认语义，因此
插件只把空计数规范化为零，空配置保持 `null`。

## 实机 schema-only 结果

目标设备对全部请求字段返回 JSON string 类型。探测时固件版本字段非空；流量和
套餐字段存在但为空，与原厂前端的零值处理一致。验证过程只输出字段名、类型、
存在性和是否为空，没有输出原始固件版本或任何设备值。

Wi-Fi 名称和客户端字段在当前未认证请求中为空或未请求，本次不据此开放相关
模块。后续必须取得经过脱敏的已认证 fixture 后单独实现。

## 隐私边界

本次未请求或记录密码、Cookie、认证摘要、SSID、Wi-Fi 密码、MAC、IP、主机名、
IMEI、IMSI、ICCID、手机号或短信内容。仓库 fixture 仅使用合成固件名和合成流量
数值。

## 结论

流量与固件信息满足只读开放条件：功能在目标固件可见，精确字段和类型已经确认，
空值语义与原厂前端一致。该结论不授权任何流量计划写操作。

