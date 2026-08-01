# U25S 移动网络扩展只读验证

日期：2026-08-01

## 结论

当前 U25S 原厂 `service.js` 的主状态模型包含 LTE RSRP、RSCP、RSSI、漫游状态、
拨号模式、WAN 模式及 MCC/MNC。项目已将这些字段加入单次批量只读请求，并以
nullable string 规范化后展示在 LuCI 移动网络页。

## 证据边界

- 静态脚本确认字段名：`network_lte_rsrp`、`network_rscp`、`lte_rssi`、
  `network_simcard_roam`、`dial_mode`、`opms_wan_mode`、`network_rmcc`、
  `network_rmnc`。
- 匿名 schema-only 请求确认当前设备对八个字段均返回字符串类型，但在未认证会话
  中值为空。
- 本次探测只记录字段名、类型和是否为空，没有记录运营商值、设备标识、SIM 标识、
  Cookie 或凭据。

## 实现约束

- 空值和缺失值规范化为 `null`，LuCI 显示为不可用，不伪造默认值。
- 信号强度仅添加 `dBm` 单位，不根据未经验证的阈值推断“优秀/较差”。
- 漫游、拨号和 WAN 模式保留固件原始枚举；完整枚举集需在有效认证 fixture 到位后
  再映射为用户友好的状态。
- MCC/MNC 是运营商代码，不读取或保存 ICCID、IMSI、IMEI、手机号等唯一标识。
- 本批次仅增加只读展示，不开放蜂窝网络写能力。

## 自动化覆盖

- Adapter 测试覆盖八个字段的规范化值及缺失值为 `null`。
- LuCI 测试覆盖所有新增移动网络行与 MCC/MNC 组合显示。
- 模拟器 allowlist 与生产批量读取字段保持一致。
