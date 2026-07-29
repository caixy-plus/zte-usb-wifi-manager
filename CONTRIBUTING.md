# Contributing

感谢参与 ZTE USB WiFi Manager。

## 开发原则

- 不把其他型号或通用固件中的接口当作 U25S 已支持能力。
- 新设备能力必须附带当前固件的脱敏响应 fixture 和测试。
- 写操作必须说明失败行为、恢复方式和是否导致网络中断。
- 不提交密码、Cookie、IMEI、IMSI、ICCID、手机号或短信正文。
- LuCI 只调用 rpcd/ubus，不直接执行 shell。

## 提交流程

1. Fork 仓库并创建功能分支。
2. 先写能复现需求的失败测试。
3. 编写最小实现并运行：

   ```sh
   make test
   make lint
   ```

4. 提交 Pull Request，描述目标设备、固件版本、验证步骤和风险。

## Commit 建议

使用简洁的 Conventional Commit 风格：

```text
feat: add read-only battery status adapter
fix: preserve power state inside hysteresis range
docs: document U25S login challenge
```
