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

## 待补实机证据

r9 必须使用 GitHub 真实 SDK 制品重新安装到 OpenWrt 25.12.5，然后只执行一次
`zte-u25s-sim-calibrate probe`。只有认证成功并返回完整 readiness 字段，才能把
登录摘要校准标记为实机通过。真实 SIM 切换仍只能在备用 U25S 上执行。
