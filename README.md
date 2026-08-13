# ZTE USB WiFi Manager

[![CI](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

面向 OpenWrt 的中兴 **U30 Pro 智能充电管理器**。它不是完整的随身
Wi-Fi 控制台，产品范围固定为：

1. 按电量阈值自动切换 U30 Pro 原生 `power_supply_mode`；
2. 只读显示设备、电池、蜂窝网络和 USB 上联摘要；
3. 提供 U30 Pro 原生管理页入口；
4. 保存或清除仅供后端登录设备使用的本地管理密码。

移动网络、Wi-Fi、短信、流量、客户端、SIM 切换、设备重启/关机和 USB
VBUS 断电等控制均不属于当前产品面。

> 智能充电只改变 U30 Pro 内部供电模式。它不会关闭 USB VBUS，也不会主动
> 断开 USB 数据连接。

## 当前版本与验证状态

当前源码基线为 **backend r40 / LuCI r15**，访问配置为
`access_profile=charge_v1`。

- 目标设备：**U30 Pro only**；U25S 不在产品支持范围内。
- 默认 `adapter=auto`，但只有 USB 身份被精确识别为 U30 Pro 后才会加载
  `zte_u30` 能力。
- OpenWrt 25.12.5 构建 `.apk`，OpenWrt 24.10.7 构建 `.ipk`。
- 后端和 LuCI 包均为架构无关包；Shell 不会被编译成 ELF 机器码。
- 25.12.5 真机已验证 LuCI r15、backend r40、U30 Pro 固件
  `U30ProV1.0.0B23`。
- 真机已完成 `电池充电 → 电源直供 → 电池充电` 双向切换；两次切换中
  `eth2` 和默认路由保持可用。
- GitHub Packages 产物包含 `build-manifest.json` 和 `SHA256SUMS`，可将安装包
  追溯到精确源码提交。

## 智能充电行为

设低阈值为 `low`、高阈值为 `high`：

| 电量 | 策略 |
|---|---|
| `battery <= low` | 关闭直供，切换为电池充电 |
| `low < battery < high` | 保持设备当前供电模式，不写设备 |
| `battery >= high` | 打开直供，停止给电池充电 |

中间区间是滞回区，用于避免设备在阈值附近频繁切换。仓库默认阈值为
`30 / 80`；长期插电时可按备用电量需求在 LuCI 中调整，例如 `60 / 80`。

策略默认每 30 秒读取一次状态。设备状态或当前供电模式不可信时，策略保持
当前状态而不盲目写入；写入失败后按默认 300 秒冷却时间重试。

## 写入与认证边界

当前唯一允许写入 U30 Pro 的设备接口是
`POWER_SUPPLY_SETTING` / `power_supply_mode`。LuCI 没有手动“充电”或“直供”
按钮，设备写入只能由启用后的智能充电策略触发。

U30 Pro 当前固件虽然在静态页面配置中声明
`ACCESSIBLE_ID_SUPPORT=false`，但真机写入要求动态 `AD`。后端会在每次写入前
读取新的 `wa_inner_version`、`cr_version` 和 `RD`，按设备网页算法派生 AD：

```text
SHA256(SHA256(wa_inner_version + cr_version) + RD)
```

两轮摘要均使用大写十六进制。AD、Cookie 和设备密码均不会写入状态快照或事件
日志，也不会由 LuCI 回显。设备密码保存在 root 所有、权限 `0600` 的
`/etc/zte-usb-wifi-manager/credentials`。

设备使用 HTTPS 和设备自有证书；当前适配器将其标记为
`device_certificate_unverified`，并通过固定设备地址、USB 身份识别、请求白名单、
登录认证和精确读回共同限制写入范围。

## LuCI 页面

安装后进入：

```text
服务 → 中兴智能充电
```

页面包含三个 Tab：

- **设备**：基础信息、原生管理页入口以及本地设备凭据；
- **智能充电**：当前电量/模式、策略状态、开关和低/高阈值；
- **日志**：仅显示 `smart_charge` 事件。

LuCI 只调用 rpcd/ubus，不直接执行 Shell 命令，也不直接请求 U30 Pro。

## 安装包

GitHub `Packages` 工作流输出：

```text
zte-usb-wifi-manager-0.1.0_rc1-r40.apk
luci-app-zte-usb-wifi-manager-0.1.0_rc1-r15.apk
zte-usb-wifi-manager_0.1.0_rc1-r40_all.ipk
luci-app-zte-usb-wifi-manager_0.1.0_rc1-r15_all.ipk
build-manifest.json
SHA256SUMS
```

安装前应先在下载目录验证 `SHA256SUMS`，并确认 `build-manifest.json` 中的
`source_commit` 是预期提交。

OpenWrt 25.12.5：

```sh
apk add --allow-untrusted \
    /tmp/zte-usb-wifi-manager-0.1.0_rc1-r40.apk \
    /tmp/luci-app-zte-usb-wifi-manager-0.1.0_rc1-r15.apk
```

OpenWrt 24.10.7：

```sh
opkg install \
    /tmp/zte-usb-wifi-manager_0.1.0_rc1-r40_all.ipk \
    /tmp/luci-app-zte-usb-wifi-manager_0.1.0_rc1-r15_all.ipk
```

安装后启用服务并重新加载 rpcd：

```sh
/etc/init.d/zte-usb-wifi-manager enable
/etc/init.d/zte-usb-wifi-manager restart
/etc/init.d/rpcd restart
```

然后在 LuCI 的“设备”页保存 U30 Pro 网页管理密码。密码只写入路由器本地，
不会返回浏览器。

## 默认配置

配置文件为 `/etc/config/zte-usb-wifi-manager`：

| UCI 项 | 默认值 | 说明 |
|---|---:|---|
| `main.enabled` | `1` | 启动后端轮询 |
| `main.write_enabled` | `1` | 全局设备写入总开关 |
| `main.access_profile` | `charge_v1` | 固定产品访问配置 |
| `main.poll_interval` | `30` | 轮询周期，单位秒 |
| `writes.set_power_supply_mode_enabled` | `1` | 智能充电设备写入门控 |
| `zte.host` | `192.168.0.1` | U30 Pro 管理地址 |
| `zte.interface` | `usbwan` | netifd 接口 |
| `zte.netdev` | `eth2` | USB 数据网卡 |
| `zte.adapter` | `auto` | 仍须通过 USB 身份识别 |
| `charging.enabled` | `1` | 启用智能充电 |
| `charging.low_percent` | `30` | 低电量阈值 |
| `charging.high_percent` | `80` | 高电量阈值 |
| `charging.retry_seconds` | `300` | 写入失败冷却时间 |

修改配置后使用服务 reload/restart 使其生效。日常设置建议通过 LuCI 保存；后端会
校验阈值，并以事务方式提交 UCI 配置和重载服务。

## 架构与运行方式

数据流保持单向：

1. `zte-usb-wifi-managerd` 由 procd 管理，登录并读取 U30 Pro，执行智能充电，
   将快照原子写入 `/var/run/zte-usb-wifi-manager/status.json`；
2. `/usr/libexec/rpcd/zte_usb_wifi` 只读取缓存状态，并提供 capabilities、凭据、
   充电设置和事件日志 RPC；它不直接访问设备；
3. LuCI JavaScript 只调用 rpcd/ubus。

后端使用 OpenWrt 默认的 POSIX Shell / BusyBox `ash`，配合 UCI、ubus、procd、
`curl` 和 `jsonfilter`。构建过程会将这些脚本打包进 APK/IPK；只有 LuCI
JavaScript 会在打包时压缩。

当前单设备、30 秒轮询的负载很低。一次 25.12.5 真机观测中，daemon 常驻 RSS
约 2.3 MB，运行约 45 分钟累计 CPU 时间约 0.83 秒；该数据是参考值，不是硬件
性能保证。

## 开发与验证

```sh
make test                       # 全部回归、语法、JSON 和敏感信息扫描
make lint                       # shellcheck（需安装）
make check                      # test + lint
```

主要目录：

- `package/zte-usb-wifi-manager/`：后端包；
- `luci-app-zte-usb-wifi-manager/`：LuCI 包；
- `tests/`：POSIX Shell、Node.js 和 Python 测试/模拟器；
- `docs/design/`：设计文档；
- `docs/validation/`：硬件校准、写入契约和发布验证记录。

更完整的 GitHub 产物验证流程见
[`docs/validation/github-packages-and-qemu.md`](docs/validation/github-packages-and-qemu.md)。

## 许可

MIT — 见 [LICENSE](LICENSE)。
