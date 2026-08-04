# 首版能力矩阵冻结

当前源码基线：backend r31 / LuCI r12（2026-08-04）。历史 r30
包的 SDK/QEMU/只读真机证据不能替代当前源码的最终构建和真机验收。

机器可读 U25S 基线位于 `tests/fixtures/u25s/capabilities-first-release.json`；动态
U30 契约由 `tests/test_adapter.sh`、`tests/test_u30_*_e2e.sh` 和静态 metadata 共同
约束。实现状态变化必须同时提交代码、测试、证据和 capability 变更，不能只改前端。

| 能力 | U25S | U30 Pro 当前实现 | 当前最高验证层级 | 生产启用 |
|---|---|---|---|---|
| 移动网络/Wi-Fi/流量/设备读取 | implemented | implemented | 历史 r30 Cudy 只读 + 当前本地回归 | 是 |
| 接入设备明细 | implemented | 端点不可用时独立降级 | 历史 r30 Cudy 只读 | 是 |
| 短信收件箱 | implemented | implemented | 状态化模拟器；真机待验收 | 是，私有缓存 |
| SIM 切换 | implemented，待 U25S 实机 | not_implemented | U25S 模拟器 | 否 |
| APN/连接模式 | not_implemented | implemented | 状态化 HTTP 模拟器 | 否 |
| 2.4 GHz Wi-Fi 设置 | not_implemented | implemented | 状态化 HTTP 模拟器 | 否 |
| 流量套餐/清零 | not_implemented | implemented | 状态化 HTTP 模拟器 | 否 |
| 短信发送/删除/已读 | not_implemented | implemented | 状态化 HTTP 模拟器 | 否 |
| 设备重启/关机 | not_implemented | implemented | 状态化 HTTP 模拟器 | 否 |
| 原生供电模式/智能充电 | unsupported | implemented | 状态化 HTTP 模拟器 | 否 |
| 固件更新/恢复出厂/备份恢复/设备密码 | native_console_only | native_console_only | 原生控制台 | 否 |

所有 U30 写 capability 继续为 `0`。离线测试证明请求、故障分类、单次 POST、读回、
崩溃恢复和敏感数据边界符合契约，但不能证明目标固件会接受写入。生产启用还必须同时
满足静态 capability、全局 UCI 写门和独立功能门；描述性 `feature_status` 不能绕过。
