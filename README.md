# ZTE USB WiFi Manager

[![CI](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

面向 OpenWrt 的中兴随身 WiFi 管理工具。项目目标是在一个 LuCI 入口内统一展示通过 USB 接入的中兴设备、蜂窝网络、流量、电池、供电和诊断信息。

## 当前状态

仓库目前处于**只读管理阶段**：

- 已接入 U25S goform 双重 SHA-256 登录和批量状态读取。
- daemon 聚合设备状态、netifd 网络状态和策略监控结果，并通过
  rpcd/ubus 提供给 LuCI。
- LuCI 十个标签已可切换；总览、移动网络、电池、设备和诊断页使用当前真实快照。
- 已补充读取 SIM 类型与电池扩展状态，不映射未经实机校准的卡槽语义。
- Wi-Fi、流量、短信和日志仍等待经过验证的 fixture，不展示推测数据。
- 已实现 mock/dry-run Power Adapter，可记录策略决策但不会控制真实 USB 供电；
  hardware 后端仍保持禁用，等待 TR3000 板级校准。
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

## 安装

> 项目目前是只读开发预览版，尚未发布稳定版本，也尚未完成主路由器实机验收。
> 建议先在备用 OpenWrt 设备上验证。不要强制安装与固件版本、target 或架构不匹配的包。

当前自动构建兼容矩阵：

| OpenWrt | 包格式 | 验证状态 |
|---|---|---|
| OpenWrt 25.12.5 | `.apk` | QEMU 安装验证通过 |
| OpenWrt 24.10.7 | `.ipk` | QEMU 安装验证通过 |

两个包均为纯脚本和静态资源，发布时标记为 `all` 架构。这里的 `all` 只表示不受
CPU 架构限制，不表示可以跨 OpenWrt 软件包格式或发行系列安装。未列出的 OpenWrt
版本目前不受支持，请勿强制安装。

### 1. 确认路由器信息

通过 SSH 登录路由器，记录固件版本、target 和架构：

```sh
ubus call system board
apk --print-arch 2>/dev/null || opkg print-architecture
```

Release 中的两个包是架构无关包，可用于兼容矩阵中同一 OpenWrt 版本的不同 CPU
架构；不能跨 OpenWrt 版本或包格式使用。自行构建时仍应使用与路由器相同 OpenWrt
版本的软件源。升级或安装前建议先备份路由器配置。

### 2. 获取安装包

正式发布后，普通用户应从
[GitHub Releases](https://github.com/caixy-plus/zte-usb-wifi-manager/releases)
下载两个与路由器匹配的包：

- `zte-usb-wifi-manager`：后端守护进程和 rpcd 接口。
- `luci-app-zte-usb-wifi-manager`：LuCI 页面、菜单和 ACL。

如果 Releases 页面没有适配当前固件的 `.apk` 或 `.ipk`，不要使用其他固件版本的包；
请按下方“从源码构建”使用匹配的 OpenWrt SDK。

下载后应按照 Release 附带的 `SHA256SUMS` 校验文件。`--allow-untrusted` 仅用于安装本项目
官方 Release 或用户自行构建的包，不应对来源不明的 OpenWrt 包使用。

将两个文件上传到路由器 `/tmp`：

```sh
ROUTER_HOST=192.168.1.1
scp zte-usb-wifi-manager*.apk luci-app-zte-usb-wifi-manager*.apk \
    "root@$ROUTER_HOST:/tmp/"
```

旧版 OpenWrt 使用 `.ipk` 时，将命令中的 `*.apk` 改成 `*.ipk`。

### 3. 安装软件包

OpenWrt 25.12.5 使用 APK：

```sh
apk update
apk add --allow-untrusted \
    /tmp/zte-usb-wifi-manager*.apk \
    /tmp/luci-app-zte-usb-wifi-manager*.apk
```

OpenWrt 24.10.7 使用 opkg：

```sh
opkg update
opkg install \
    /tmp/zte-usb-wifi-manager_*.ipk \
    /tmp/luci-app-zte-usb-wifi-manager_*.ipk
```

包管理器会从当前固件的软件源解析 `coreutils-stat`、`curl`、`ip-tiny`、`jshn`、
`rpcd`、`ubus` 和 `uci` 等依赖。不要使用 `--force-depends` 或
`--force-architecture`。

### 4. 配置 U25S 凭据

凭据文件必须由 root 拥有且权限为 `0600`。为避免密码进入 shell 历史，使用编辑器填写：

```sh
umask 077
mkdir -p /etc/zte-usb-wifi-manager
touch /etc/zte-usb-wifi-manager/credentials
chmod 600 /etc/zte-usb-wifi-manager/credentials
vi /etc/zte-usb-wifi-manager/credentials
```

文件只包含一行：

```text
password=<U25S_WEB_PASSWORD>
```

如实际连接参数与默认值不同，修改 UCI：

```sh
uci set zte-usb-wifi-manager.zte.host='192.168.0.1'
uci set zte-usb-wifi-manager.zte.interface='usbwan'
uci set zte-usb-wifi-manager.zte.netdev='eth2'
uci commit zte-usb-wifi-manager
```

当前版本必须保持只读：

```sh
uci set zte-usb-wifi-manager.main.write_enabled='0'
uci set zte-usb-wifi-manager.policy.enabled='0'
uci commit zte-usb-wifi-manager
```

### 5. 启动并验证

```sh
/etc/init.d/zte-usb-wifi-manager enable
/etc/init.d/zte-usb-wifi-manager restart
/etc/init.d/zte-usb-wifi-manager status

ubus list zte_usb_wifi
ubus call zte_usb_wifi capabilities
ubus call zte_usb_wifi status
```

然后在 LuCI 打开：**服务 → 中兴随身 WiFi**。

如果状态异常：

```sh
logread -e zte-usb-wifi-manager
ls -l /etc/zte-usb-wifi-manager/credentials
cat /var/run/zte-usb-wifi-manager/status.json
```

请勿在 Issue 中粘贴密码、Cookie、认证摘要、IMEI、IMSI、ICCID、手机号或短信内容。

### 从源码构建

在 Linux 上下载与目标路由器完全匹配的
[OpenWrt SDK](https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk)，解压后：

```sh
git clone https://github.com/caixy-plus/zte-usb-wifi-manager.git \
    ../zte-usb-wifi-manager

./scripts/feeds update -a
./scripts/feeds install -p luci luci-base

ln -s "$(realpath ../zte-usb-wifi-manager/package/zte-usb-wifi-manager)" \
    package/zte-usb-wifi-manager
ln -s "$(realpath ../zte-usb-wifi-manager/luci-app-zte-usb-wifi-manager)" \
    package/luci-app-zte-usb-wifi-manager

printf '%s\n' \
    'CONFIG_PACKAGE_zte-usb-wifi-manager=m' \
    'CONFIG_PACKAGE_luci-app-zte-usb-wifi-manager=m' >>.config
make defconfig

make package/zte-usb-wifi-manager/compile V=s
make package/luci-app-zte-usb-wifi-manager/compile V=s
```

构建结果位于 SDK 的 `bin/packages/` 目录。OpenWrt 25.12.5 生成 `.apk`，
OpenWrt 24.10.7 生成 `.ipk`。编译环境路径中不要包含空格，也不要使用与目标固件
不同版本的 SDK。这里只安装构建 LuCI 所需的 feed 元数据；运行时依赖由目标固件
的软件包管理器从对应版本的官方签名软件源解析。

### 卸载

```sh
/etc/init.d/zte-usb-wifi-manager stop
/etc/init.d/zte-usb-wifi-manager disable
```

OpenWrt 25.12.5：

```sh
apk del luci-app-zte-usb-wifi-manager zte-usb-wifi-manager
```

OpenWrt 24.10.7：

```sh
opkg remove luci-app-zte-usb-wifi-manager zte-usb-wifi-manager
```

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
