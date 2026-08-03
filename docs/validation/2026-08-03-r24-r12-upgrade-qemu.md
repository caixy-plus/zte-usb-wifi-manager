# r15/r4 到 r24/r12 隔离 QEMU 升级验证

日期：2026-08-03

## 结论

| 环境 | 升级路径 | 结果 |
|---|---|---|
| OpenWrt 25.12.5 APK | backend r15 / LuCI r4 → backend r24 / LuCI r12 | PASS |
| OpenWrt 24.10.7 IPK | backend r15 / LuCI r4 → backend r24 / LuCI r12 | PASS |

两台虚拟机均从官方 x86/64 基础镜像创建一次性 overlay，使用 QEMU user-mode NAT，
未桥接物理网络。安装前加入禁止访问 `10/8`、`100.64/10`、`169.254/16`、
`172.16/12` 和 `192.168/16` 的路由并禁用 IPv6；对 U25S/U30 Pro 默认管理地址的
路由检查按预期失败，因此测试没有接触 Cudy 或真实随身 WiFi。

## 验证项目

- 安装历史正式包 backend r15 / LuCI r4，并确认包数据库状态：PASS。
- 将 `main.poll_interval` 自定义为 `77` 后原位升级 r24/r12：PASS。
- APK/IPK 包版本分别为 backend r24、LuCI r12：PASS。
- 自定义轮询值 `77` 在升级后保留：PASS。
- 历史 U25S 配置继续保留 `zte_u25s`，不使用未经校准的 U25S 自动识别：PASS。
- 新增的重启、关机和电源直供写开关均补为 fail-closed 的 `0`：PASS。
- 新增 `charging` 配置节及 `0/30/80/300` 默认值均存在：PASS。
- procd 服务可重启，rpcd 注册 `zte_usb_wifi`：PASS。
- `status` 和 `capabilities` 返回可解析 JSON：PASS。
- 设备重启和 `power_supply_mode` 请求均返回 `unsupported`，未创建真实写入：PASS。
- 卸载 backend 与 LuCI 后，rpcd、LuCI 文件和运行目录清理：PASS。
- 两台虚拟机正常关机，QEMU 退出码均为 0：PASS。

OpenWrt 的 conffile 机制会在修改过旧配置时保留 `.apk-new` 或 `-opkg` 副本；r24
post-install 迁移负责把必需的新安全键以关闭状态加入活动 UCI 配置，而不覆盖用户
已有值。

由于隔离 QEMU 没有真实 USB 设备，本验证只证明升级不会改写已选适配器。更换为
U30 Pro 的旧安装必须在最后的真机调试中显式选择 `zte_u30`；不能把 QEMU 结果当作
U25S/U30 USB 自动识别的硬件证据。

## 边界

该验证覆盖真实包管理器中的升级、配置保留、服务、ubus、安全门控和卸载行为。
它不证明真实 U30 Pro 厂商写接口、供电模式读回、故障恢复或 72 小时稳定性；这些
仍属于最后的备用硬件与真机调试验收。
