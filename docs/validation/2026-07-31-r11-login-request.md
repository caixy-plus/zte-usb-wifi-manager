# r11 U25S 登录请求对齐（2026-07-31）

## 实机前提

r10 已在 OpenWrt 25.12.5 Cudy TR3000 上完成正式升级，唯一一次只读校准 probe
仍返回 `authentication_failed`。这证伪了“只由全局 LD 并发导致失败”的假设。
本轮不再次发起登录，而是只读取目标 U25S 对外提供的静态 WebUI JavaScript。

## 目标固件证据

目标固件 `service.js` 的 `login()` 构造以下表单字段：

```text
isTest=false
goformId=LOGIN
password=<uppercase double-SHA-256 digest>
```

同一函数把响应 `result` 为字符串 `0` 或 `4` 都判定为登录成功。公共请求封装使用
POST `/goform/goform_set_cmd_process`，由 jQuery 以表单格式编码参数。目标固件
`util.js` 再次确认 SHA-256 输出为大写十六进制。

r10 的插件请求只提交 `goformId` 和 `password`，并且只接受结果 `0`，与目标
固件存在两个确定差异。

## r11 修复与测试

- 登录表单按固件顺序提交
  `isTest=false&goformId=LOGIN&password=<digest>`；
- `result=0` 和 `result=4` 均作为成功；
- 其他结果、缺失结果和 HTTP/JSON 错误仍失败关闭；
- 保留 r10 的全局 `LD -> LOGIN` 串行化。

TDD 红灯时 `test_session` 明确失败 2 项：表单缺少 `isTest=false`，以及
`result=4` 被误拒。实现后：

- `test_session`：49 assertions PASS；
- `test_u25s_simulator`：56 assertions PASS；
- `test_sim_calibration`：413 assertions PASS。

## 全量检查与双 SDK 构建

- `make check`：PASS；
- GitHub Actions run：`30621709431`；
- source commit：`f409f99a73481664372d54cc6455c7f2adeef769`；
- OpenWrt 25.12.5 APK 与 24.10.7 IPK 的真实 SDK 构建均通过；
- 汇总制品 `SHA256SUMS` 全部通过；
- r11 APK SHA-256：
  `d8243e4a7d9fa5d2fbe247df137a38b2f0f0eb78492f498c7a3a8ace8110cfe1`；
- r11 IPK SHA-256：
  `7435b819b9a7c420137be27a736248c94550ecc8e75068aea3808e142b7e6e39`。

## 正式升级与实机结论

Cudy TR3000 上正式升级结果：
`0.1.0_rc1-r10 -> 0.1.0_rc1-r11`。安装后守护进程运行，凭据文件保持 root 所有和
`0600`，计划任务 SHA-256 未变，会话锁无残留，设备写、电池策略和硬件供电仍
保持关闭。唯一一次只读 probe 仍返回：

```json
{"ok":false,"mode":"probe","code":"authentication_failed"}
```

因此请求参数和结果码兼容修复仍不是完整根因。部署所用一次性 SSH 公钥已从路由器
删除，本地私钥已移入废纸篓。

随后被动读取目标固件 `config.js` 发现其明确声明 `HAS_LOGIN:false`，原生 WebUI
因此根本不执行 LOGIN。插件校准器无条件认证才是与该固件契约直接冲突的路径，转入
r12 修复。SIM 写接口和 USB 供电仍未在主路由器执行。
