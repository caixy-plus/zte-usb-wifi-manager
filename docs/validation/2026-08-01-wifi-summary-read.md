# U25S Wi-Fi 总览只读验证

日期：2026-08-01

## 结论

当前 U25S 原厂页面明确提供 Wi-Fi 管理模块，`service.js` 同时确认主状态和设备
信息会使用 Wi-Fi 开关、2.4/5GHz SSID、认证模式及客户端计数。项目已将这些
非密码字段加入单次只读快照，并在 LuCI 的 U25S Wi-Fi 页展示。

## 字段白名单

- `wifi_onoff_state`
- `guest_switch`
- `wifi_chip1_ssid1_ssid`
- `wifi_chip1_ssid1_auth_mode`
- `wifi_chip1_ssid1_access_sta_num`
- `wifi_chip2_ssid1_ssid`
- `wifi_chip2_ssid1_auth_mode`
- `wifi_chip2_ssid1_access_sta_num`

原厂 `getWifiBasic()` 还会读取 `WPAPSK1_encode`、`m_WPAPSK1_encode` 等密码字段；
项目没有请求、规范化、缓存或渲染这些字段。

## 实机证据边界

匿名 schema-only 请求确认八个白名单字段在当前设备响应中均为字符串，但未认证
会话下为空。本次仅记录字段名、类型和空值状态，没有采集真实 SSID、密码、MAC、
Cookie 或设备标识。字段语义同时由当前固件 `service.js` 的实际页面映射确认。

因此本批次可以证明读取契约和缺失值行为，但不能声称当前旧凭据已经通过认证，也
不能证明真实 Wi-Fi 写操作。所有 Wi-Fi 写能力继续关闭。

## 自动化覆盖

- Adapter 使用合成 SSID 验证布尔值、认证模式和客户端计数规范化。
- 测试明确拒绝任何 password、passphrase 或 WPAPSK 字段进入规范化对象。
- LuCI 测试覆盖完整 Wi-Fi 总览，并确认 Wi-Fi 面板不显示密码。
- 模拟器 allowlist 与生产批量读取字段一致。
