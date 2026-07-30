# ZTE USB WiFi Manager

[![CI](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

面向 OpenWrt 的中兴随身 WiFi 管理工具。项目目标是在一个 LuCI 入口内统一展示通过 USB 接入的中兴设备、蜂窝网络、流量、电池、供电和诊断信息。

## 当前状态

仓库目前处于**只读管理阶段**：

- 已接入 U25S goform 双重 SHA-256 登录和批量状态读取。
- daemon 聚合设备状态、netifd 网络状态和策略监控结果，并通过
  rpcd/ubus 提供给 LuCI。
- 连续读取失败会触发轮询退避，快照会保留最后可信的设备状态。
- 电池策略目前仅用于监控；USB Power Adapter 尚未实现。
- 所有设备写操作保持关闭，`write_enabled=0`。
- SIM 切换仍需完成 `card_index` 实机校准后才会开放。

当前状态不代表已经完成人工上机验收。

项目不会根据固件通用代码中的残留符号自行增加功能。产品能力以当前设备原生管理页面、实机验证结果和明确需求为准。

## 目标环境

- 路由器：Cudy TR3000 v1
- SoC：MediaTek MT7981
- OpenWrt：25.12.5
- 中兴设备：U25S / MU5650
- 当前 USB 网络：`usbwan` / `eth2`

## 仓库结构

```text
.
├── package/zte-usb-wifi-manager/        # 后端包、守护进程、策略与适配器
├── luci-app-zte-usb-wifi-manager/       # LuCI 菜单、ACL 和只读状态总览
├── tests/                               # POSIX Shell 测试
├── docs/design/                         # UI 成品稿与详细设计文档
├── docs/plans/                          # 可执行实施计划
└── .github/workflows/ci.yml             # GitHub Actions
```

## 设计资料

- [UI 成品设计稿](docs/design/zte-usb-wifi-manager-ui.html)
- [详细设计文档](docs/design/zte-usb-wifi-manager-design.md)
- [框架层实施计划](docs/plans/2026-07-29-framework-foundation.md)
- [Phase 1 只读实施计划](docs/plans/2026-07-29-phase1-read-only.md)

## 本地验证

依赖：POSIX Shell、GNU Make 或 BSD Make、Node.js。完整静态检查还需要 ShellCheck。

```sh
make test
make lint
```

`make test` 会运行配置校验、状态机、包结构、Shell 语法、JSON 语法和敏感信息模式检查。

## 安全边界

- 后端默认不允许设备写操作。
- 密码、Cookie、号卡身份和短信正文不得进入仓库或日志。
- LuCI 不直接执行 shell。
- 未校准的设备能力必须返回 unsupported，不得仅通过隐藏按钮控制。
- 计划中的 USB 供电动作必须先完成板级入口和恢复机制验证。

## 路线

1. ✅ 已接入 U25S 只读登录和批量状态读取。
2. 用脱敏实机 fixture 替换当前合成 fixture。
3. 在 TR3000 + U25S 上完成 rpcd 缓存状态与 LuCI 总览的只读实机验收。
4. 逐项校准并开放明确要求的设备写操作。
5. 完成 USB 供电后端、故障保护和 72 小时稳定性测试。

## 贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。

## License

[MIT](LICENSE)
