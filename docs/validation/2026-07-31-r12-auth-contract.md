# r12 U25S 认证契约校准（2026-07-31）

## 实机证据

r11 已在 OpenWrt 25.12.5 Cudy TR3000 上正式升级。唯一一次只读校准 probe 仍返回
`authentication_failed`，而匿名批量状态读取持续成功。

不发起新登录请求的情况下，被动读取目标 U25S 发布的静态 WebUI 文件得到：

- `js/config/config.js`：`DEVICE_MODEL:"U25S"`、`HAS_LOGIN:false`、
  `WEB_ATTR_IF_SUPPORT_SHA256:2`；
- `js/service.js`：`getLoginStatus()` 在 `HAS_LOGIN:false` 时直接返回 logged in，
  不调用登录接口；
- `js/login.js`：只有实际提交登录表单时才调用 `service.login()`；
- 匿名状态接口继续返回设备、蜂窝和 SIM 就绪字段。

因此 r9-r11 的登录兼容代码对需要认证的固件变体仍然有效，但目标固件的正确路径是
不执行 LOGIN。原校准器与动作执行器无条件要求密码并登录，违反了已核实的目标固件
契约。

## r12 行为

- 适配器元数据新增 `ZTE_LOGIN_REQUIRED=0` 和 `login_required:false`；
- SIM probe、执行和恢复统一通过适配器认证契约取得可选密码；
- 目标固件路径跳过 LOGIN，直接使用匿名状态读取和仍受校准门控的写请求；
- 即使保留了旧密码且匿名响应异常，读取层也不会回退到 LOGIN；
- 认证必需模式继续要求 mode-600 凭据并保留 r9-r11 登录实现；
- 匿名写第一次失败时不盲目重试，避免无会话恢复依据的重复写；
- `ZTE_CAP_SIM_SWITCH` 仍为 `0`，生产写入口没有提前开放。

TDD 红灯证据：

- 适配器缺少认证契约及能力字段；
- 匿名动作被错误返回 `credentials_missing`；
- 无凭据 probe 被错误返回 `credentials_unavailable`。

最小实现后：

- `test_adapter`：67 assertions PASS；
- `test_action_executor`：27 assertions PASS；
- `test_sim_calibration`：417 assertions PASS；
- `test_rpcd`：59 assertions PASS。

## 构建、正式升级与实机结论

- 全量 `make check`：PASS；
- GitHub Actions run：`30623348907`；
- source commit：`fac31a63e978914f7b6a28290fb32f2b6796a6dd`；
- OpenWrt 25.12.5 APK 与 24.10.7 IPK 的真实 SDK 构建均通过；
- r12 APK SHA-256：
  `7af6450f36b4107227ebc4b207257bccf31c660ff3241f1c5fb560ed368f21fc`；
- Cudy TR3000 正式升级：`0.1.0_rc1-r11 -> 0.1.0_rc1-r12`。

安装后守护进程正常，写、电池策略和硬件供电全部保持关闭，凭据权限保持
`0600/root`，计划任务 SHA-256 未变。唯一一次匿名只读 probe 返回：

```json
{"ok":false,"mode":"probe","code":"modem_not_connected"}
```

这证明认证门槛已经消失，失败点前进到后续就绪校验。随后带与插件一致请求头的
匿名只读接口返回：SIM 槽位有效、`mc_modem_main_state=modem_init_complete`、运营商
非空、`ppp_status=ipv4_ipv6_connected`。目标固件 `status/statusBar.js` 也明确把
`modem_init_complete` 用作正常信号状态。原测试只接受人工 fixture 中的
`connected`，转入 r13 校准真实枚举。没有执行 SIM 写操作。
