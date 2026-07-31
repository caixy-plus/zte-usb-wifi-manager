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

## 尚未完成

r11 仍需正式升级到同一 OpenWrt 25.12.5 路由器，并在新的受控阶段只执行一次
只读 probe。只有 probe 返回 `ok:true`，才能继续在备用 U25S 上校准 SIM 写接口。
USB 真实供电和恢复协调仍必须在备用 TR3000 台架验证。
