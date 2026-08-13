# ZTE USB WiFi Manager

[![CI](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

面向 OpenWrt 的中兴 **U30 Pro 智能充电** 管理工具。产品面刻意收敛为：

1. **智能充电策略**（低/高电量阈值滞回，切换设备原生 `power_supply_mode`）
2. **设备基础信息只读**（型号、版本、电池/供电模式、蜂窝摘要、USB 上联等）
3. **设备原生管理页跳转**（校验后的网关 URL 外链）

不再提供完整设备控制台（移动网络/Wi‑Fi/短信/流量/客户端写操作等）。未整合功能请走设备原生页面。

> U30 Pro 智能充电只修改设备内部供电模式：低电量切电池充电，高电量切电源直供。
> **不会**用关闭 USB VBUS 的方式控制充电，也不会断开 USB 数据连接。

## 当前状态

仓库当前候选版本为 **backend r34 / LuCI r14**（`access_profile=charge_v1`）：

- 目标设备：**U30 Pro only**（默认 `adapter=auto`）。只有 USB 身份被精确识别为 U30 Pro 后，才会启用设备能力和智能充电写入。
- LuCI 三 Tab：**设备 / 智能充电 / 日志**。
- 唯一产品写入口：保存智能充电策略（开关 + 低/高阈值）。
- 日志页仅展示 `smart_charge` 事件。
- daemon 轮询读取设备状态，执行自动智能充电；rpcd 不再暴露动作队列/短信/控制台写方法。
- 旧版 USB 硬件断电 / 恢复协调路径已从产品面移除。

```sh
make test                       # 本地回归
make lint                       # shellcheck（需安装）
make check                      # test + lint
```

## 架构

单向数据流：

1. `zte-usb-wifi-managerd` 登录并批量读取 U30 状态，执行智能充电策略，原子写入 `/var/run/zte-usb-wifi-manager/status.json`。
2. `rpcd/zte_usb_wifi` 提供 status / capabilities / credentials / charging_settings / logs。
3. LuCI 只调用 rpcd/ubus；密码写后不回显。

## 布局

- `package/zte-usb-wifi-manager/`：后端包
- `luci-app-zte-usb-wifi-manager/`：LuCI 包
- `tests/`：POSIX Shell / Node 回归
- `docs/`：设计与验证记录（含历史完整控制台阶段）

## 许可

MIT — 见 [LICENSE](LICENSE)。
