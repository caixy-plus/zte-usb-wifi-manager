# r9 U25S 登录摘要校准（2026-07-31）

## 根因

目标 U25S 当前固件的 `js/util.js` 定义：

```js
function paswordAlgorithmsCookie(e){return SHA256(e)}
```

其中 `SHA256()` 使用 `0123456789ABCDEF` 编码返回值，因此每一轮摘要都是大写
十六进制。`js/service.js` 的真实登录表达式为：

```js
paswordAlgorithmsCookie(paswordAlgorithmsCookie(password) + LD)
```

backend r8 虽然把最终摘要转成了大写，但把第一轮的小写摘要直接与 `LD` 拼接，
因此提交值与目标固件不一致，真实登录稳定失败。

## 修复

backend r9 在拼接 `LD` 前先把第一轮 SHA-256 摘要转成大写，第二轮仍输出大写。
底层 `zte_sha256_hex()` 继续保持“输出小写”的通用契约，大小写转换只存在于 U25S
会话协议层。

测试使用两个固定、非生产凭据向量校验最终摘要和实际 POST body。U25S API 模拟器
也改为复刻固件的两轮大写行为。

## TDD 证据

更新测试和模拟器、尚未修改生产代码时：

- `test_session`：3/26 失败；
- `test_u25s_simulator`：登录请求收到 HTTP 403。

修改 `session.sh` 后：

- `test_session`：26 assertions PASS；
- `test_u25s_simulator`：56 assertions PASS；
- `make check`：PASS。

## 实机结果

r9 已使用 GitHub run `30617784653` 的真实 OpenWrt 25.12.5 SDK 制品正式升级
到 Cudy TR3000。升级后守护进程通过相同的 `session.sh` 持续读取设备成功，LuCI
显示设备在线且后端正常，说明摘要修复已进入真实运行路径。

严格只执行的一次独立 `zte-u25s-sim-calibrate probe` 仍返回
`authentication_failed`。结合守护进程同时读取成功，后续定位到 probe 与轮询
可能争用目标固件的全局 `LD` 挑战；该问题由 r10 会话锁继续验证。详见
[r10 会话锁验证](2026-07-31-r10-session-lock.md)。真实 SIM 切换仍只能在备用
U25S 上执行。
