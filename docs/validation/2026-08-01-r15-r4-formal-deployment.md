# r15/r4 目标路由器正式部署验证（2026-08-01）

## 部署目标与来源

- 路由器：Cudy TR3000 v1（OpenWrt U-Boot layout）
- 板型：`cudy,tr3000-v1-ubootmod`
- 固件：OpenWrt 25.12.5 `r33051-f5dae5ece4`，`mediatek/filogic`
- 安装包：GitHub prerelease `v0.1.0-rc1-r15` 的原始 APK
- 升级：backend `0.1.0_rc1-r14` → `0.1.0_rc1-r15`；LuCI
  `0.1.0_rc1-r3` → `0.1.0_rc1-r4`

上传到路由器后先重新计算 SHA-256，再以一次性的
`apk add --allow-untrusted --upgrade` 安装已校验的本地开发包；没有修改 APK 的
全局仓库或签名配置。
backend APK 回读 SHA-256 为
`3780121fe2080e769a0fe3fde0a95262657c43b2a318f6b52e1cee7b71cceb25`，
LuCI APK 为
`6ce69e345c0b4df722c8324ac77a8c74452068873f39c0437339c5124db87769`，
与 Release 的 `SHA256SUMS` 一致。

## 升级后验证

- 两个包均回读到目标版本；
- `zte-usb-wifi-manager` procd 服务为 `running`；
- `zte_usb_wifi` ubus 对象存在，`status` 和 `capabilities` 均为有效 JSON；
- 状态快照为 `state=ok`、`online=true`、`network.up=true`；
- credentials 权限为 `0600`，init、daemon、rpcd 脚本权限均为 `0755`；
- LuCI 菜单、页面和 rpcd ACL 文件均存在；
- `write_enabled=0`、`usb.backend=unconfigured`、`usb.calibrated=0`、
  `policy.enabled=0` 在升级前后保持不变；
- `power.backend=unconfigured`、`power.calibrated=false`、
  `power.write_enabled=false`，没有执行任何供电或设备写操作。

只读 `/usr/libexec/zte-usb-power-calibrate probe` 返回 `ok=true`、`mode=probe`、
`power=1`、`device_reachable=true`。这只证明 r15 在目标板型上能读取当前供电为 ON
且 U25S 可达，不构成 OFF/ON、重新枚举或恢复协调的实机校准证据。

## 凭据与清理

部署使用单个带固定注释的临时 Ed25519 公钥。完成验证后，路由器
`authorized_keys` 中该行被精确删除，本机临时公钥和私钥文件也被删除；随后使用
该私钥重新连接返回认证失败。上传的 APK、临时 JSON、UCI 备份和 LuCI 缓存也已
清理。U25S 管理密码、Cookie、设备标识和用户数据均未写入仓库或验证记录。

## 剩余门禁

当前正式部署是完整 r15/r4 软件包，但真实写能力仍按证据门控。稳定版仍需在备用
TR3000 + 备用 U25S 台架完成 SIM 切换与回切、真实 USB OFF/ON、`eth2` 消失和恢复、
`zte-usb-recover` 协调，以及连续 72 小时稳定性验收；这些破坏性项目不得在本次
主路由器上补测。
