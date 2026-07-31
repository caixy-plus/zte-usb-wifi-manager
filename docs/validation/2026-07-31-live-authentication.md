# U25S 实时认证与正式部署验证（2026-07-31）

## 结论

提交 `66ebc435016eeff4e475fa3910aafec421151e7f` 对应的 OpenWrt 25.12.5
APK 已正式升级到 Cudy TR3000 v1：

- `zte-usb-wifi-manager`：`0.1.0_rc1-r3`
- `luci-app-zte-usb-wifi-manager`：`0.1.0_rc1-r2`

升级保留了现有配置。安装时使用一次性计划任务调用
`apk add --allow-untrusted`；任务执行后自动删除自身，原有计划任务内容逐字保持不变。
没有新增 SSH 密钥或其他持久管理入口。

## 构建与校验

GitHub Actions 运行
[`30595239364`](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/runs/30595239364)
完成：

- `check`：PASS
- OpenWrt 25.12.5 APK：PASS
- OpenWrt 24.10.7 IPK：PASS
- 汇总产物和 `SHA256SUMS`：PASS

安装前已确认下载产物的 SHA-256 与 `SHA256SUMS` 一致，构建清单中的源码提交与
目标提交一致。本地 `make check` 同样全部通过。

## 实机只读证据

真实 U25S 的状态接口允许匿名只读探测。生产 adapter 对真实响应的脱敏规范化结果
确认了以下字段：

- 型号：U25S
- 在线：是
- 网络制式：NR5G-SA
- 信号格：5
- 电量：100
- 充电：否
- 活动卡槽原始值：2

验证记录没有保存密码、Cookie、认证摘要、IMEI、IMSI、ICCID、手机号、短信正文、
MAC 地址或 LuCI 会话标识。

## 管理页登录入口

路由器上的 LuCI 静态资源已确认包含：

- `credential_status` 和 `set_credentials` RPC
- `type="password"` 的 U25S 管理密码输入框
- “设备登录”与“保存密码”入口
- 保存后清空输入框的处理
- 不使用浏览器持久化保存密码

密码由 rpcd 原子写入 root 所有、权限 `0600` 的凭据文件，页面不能读取或回显密码。
保存成功只表示安全落盘，不冒充设备认证成功。

升级后重启 rpcd 会按 OpenWrt 设计使现有 LuCI 会话失效。当前没有路由器管理密码，
因此新版页面的最终点击复核需要设备所有者重新登录 LuCI 后完成。

## 仍保持门控的项目

- 用户提供的 U25S 管理密码通过目标固件的已验证登录算法返回“密码错误”；没有继续
  猜测、变换编码或重试，以避免触发设备锁定。
- 目标固件静态资源确认 SIM 切换写接口为 `SIM_SWITCH_SIMCARD`，参数
  `card_index` 的可见映射为 `1`、`2`、`3`、`0`。
- 上述静态证据不替代真实切卡、超时、回读和恢复验证，因此生产 SIM 写能力仍为
  `false`。
- 真实 USB 供电、恢复协调和 72 小时稳定性验收仍必须在备用 TR3000 + 备用 U25S
  台架完成，不能在主路由器上做探索性测试。
