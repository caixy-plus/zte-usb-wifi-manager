# r20/r9 到 r21/r10 隔离 QEMU 升级验证

验证日期：2026-08-01

| 环境 | 升级路径 | 结果 |
|---|---|---|
| OpenWrt 25.12.5 APK | backend r20 / LuCI r9 → backend r21 / LuCI r10 | PASS |
| OpenWrt 24.10.7 IPK | backend r20 / LuCI r9 → backend r21 / LuCI r10 | PASS |

两台虚拟机均使用未安装插件的基础镜像、QEMU user-mode NAT、禁止访问
`192.168.0.0/16` 的路由和禁用 IPv6；未连接 Cudy 路由器或 U25S。

验证步骤与结果：

- 安装真实 GitHub SDK 产物 r20/r9：PASS。
- 把 `main.poll_interval` 改为 `77` 并提交 UCI，随后安装 r21/r10：PASS。
- 升级后包版本、rpcd/ubus 对象和自定义 UCI 值 `77`：PASS。
- cellular、Wi-Fi、traffic、SMS、device reboot、device shutdown 六类生产写能力
  升级后仍全部为 `false`：PASS。
- 重启请求仍由服务端返回 `unsupported`，没有因旧配置残留而开放：PASS。
- LuCI 已更新为包含 `device_action` 和独立关机确认控件的 r10：PASS。
- 升级后卸载两个包，LuCI/rpcd/运行状态清理：PASS。

两个系统的串口日志均得到 `NETWORK`、`OLDGET`、`NEWGET`、`OLDINSTALL`、
`UPGRADE`、`VERSION`、`RESTART`、`CONFIG`、`GATES`、`DEVICELOCK`、`LUCI`、
`REMOVE`、`CLEANUP` 全部 `OK`。

该验证覆盖软件升级安全性，不代替备用 U25S 上的厂商写接口校准和真实 72 小时运行。
