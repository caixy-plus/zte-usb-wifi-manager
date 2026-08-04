# U30 离线代码门禁 — 2026-08-04

## 结论

当前分支已完成最终 SDK/QEMU/真机调试之前能够离线证明的 U30 写入安全链。候选
包元数据为 backend r32 / LuCI r13，本记录不生成新安装包，也不复用历史 r30
二进制证据。

完整 `make test` 与 `make lint` 通过。r32 已把 U30 已实现 capability、所有独立
UCI 写门和智能充电改为默认启用，并为历史只读配置加入一次性 `full_v1` 迁移。
Cudy 上的历史 r31/r12 已完整卸载；尚未部署本候选包或执行真实 U30 写入。

## 已覆盖的生产链

测试直接调用生产实现，不用伪造适配器返回值：

```text
action executor -> U30 adapter -> classified HTTP POST
                -> stateful loopback simulator -> production GET readback
```

覆盖动作：

- `power_supply_mode` 充电/电源直供；
- APN、连接模式、2.4 GHz Wi-Fi；
- 流量套餐和流量清零；
- 短信发送、删除和已读；
- 设备重启和关机。

覆盖故障：成功、HTTP 4xx 明确拒绝、发送前失败、发送后超时、应用后丢失响应、空响应、
错误 JSON、读回缺失/错误/超时和延迟收敛。非幂等 POST 始终只发送一次；只有完整、
成功且与目标精确一致的安全 GET 才能消除结果不确定。短信发送的全局状态不绑定请求，
因此响应丢失后保持 `write_ambiguous`；短信删除/已读使用具体消息 ID 读回。

重启成功必须观察到持续掉线后恢复，关机成功必须观察到持续离线。写入中断后的动作队列
进入只读恢复，不重复执行；APN/Wi-Fi 密码无法从设备读回时返回
`verification_inconclusive`。动作记录、密码、短信号码和正文会在持久化记账前清除。

## 本地门禁

- `make check`：PASS；
- U30 供电 E2E：115 assertions；
- U30 设置 E2E：56 assertions；
- U30 短信/设备动作 E2E：46 assertions；
- U25S 模拟器：66 assertions；
- 运行稳定性：1313 assertions；
- 打包契约：281 assertions；
- 敏感数据扫描、ShellCheck、LuCI 测试：PASS。

## 明确未证明

- 真实 U30 的 HTTPS、自签名证书、固件版本和具体写响应；
- `0=charging`、`1=direct_supply` 在目标设备上的双向实测及 USB 数据链连续性；
- SDK 依赖解析、APK/IPK 安装、升级、卸装和 procd/rpcd 生命周期；
- Cudy 上的驱动、USB 重插、设备重启、默认出口保护和 72 小时稳定性。

这些项目按计划集中到最后调试阶段。真机成功与失败路径需要留下脱敏证据，但本地
状态化 E2E 已作为开放 U30 capability 的代码门禁；最终安装包必须保持完整访问默认值。
