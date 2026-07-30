# GitHub Actions 构建验证（2026-07-30）

## 结论

GitHub Actions 工作流运行
[`30532144723`](https://github.com/caixy-plus/zte-usb-wifi-manager/actions/runs/30532144723)
在源码提交 `2edfbbe8b1a7c6b0ce314c2f946ecf81304e73ed` 上完整通过。

| 构建目标 | 包格式 | 结果 |
|---|---|---|
| OpenWrt 25.12.5 | APK | PASS |
| OpenWrt 24.10.7 | IPK | PASS |
| 汇总安装包与校验文件 | Release artifact | PASS |

工作流同时通过仓库测试和 lint。该次运行由 `workflow_dispatch` 触发，因此只生成
Actions artifact，没有创建 GitHub Release。

## 产物

下载后的 artifact 恰好包含以下六个文件：

- `zte-usb-wifi-manager-0.1.0_rc1-r1.apk`
- `luci-app-zte-usb-wifi-manager-0.1.0_rc1-r1.apk`
- `zte-usb-wifi-manager_0.1.0_rc1-r1_all.ipk`
- `luci-app-zte-usb-wifi-manager_0.1.0_rc1-r1_all.ipk`
- `build-manifest.json`
- `SHA256SUMS`

`build-manifest.json` 记录的源码提交与工作流 `headSha` 一致。APK 的包架构为
`noarch`，IPK 的包架构为 `all`；两者都只包含脚本和静态资源。

## 完整性

在独立下载目录中执行 `sha256sum -c SHA256SUMS`：PASS。

| 文件 | SHA-256 |
|---|---|
| `build-manifest.json` | `731ae5766ef9fb48045cd99ce20f5ff6069b9be9193cb90749ae2488d3abb8e0` |
| `luci-app-zte-usb-wifi-manager-0.1.0_rc1-r1.apk` | `bf08a33a9fb19bfc7d93ba4a7e9a5eaba9962d8a88a5924e777e99ff570b950a` |
| `luci-app-zte-usb-wifi-manager_0.1.0_rc1-r1_all.ipk` | `f0de656242604bf88e9a1b24dea6ac8c76634c16672d918cb30fc35b28fd943c` |
| `zte-usb-wifi-manager-0.1.0_rc1-r1.apk` | `4b77881ed3cde76074defbbabedd472eff223cc57f627de719ef57a9b2f31949` |
| `zte-usb-wifi-manager_0.1.0_rc1-r1_all.ipk` | `bfe85a532454ff18871c6c959b1fb8a4946a14c99619392aa1cbe73fbbc2230b` |

这些校验值只对应运行 `30532144723` 的 Actions artifact。标签工作流创建的 Release
文件必须重新下载并按 Release 自带的 `SHA256SUMS` 独立校验。

## 构建边界

- 使用 OpenWrt 25.12.5 和 24.10.7 的官方 x86/64 SDK。
- 只安装构建 LuCI 所需的 `luci-base` feed 条目，没有用 `feeds install -a` 拉入
  无关源包。
- `coreutils-stat`、`curl`、`ip-tiny`、`jshn`、`rpcd`、`ubus`、`uci` 等运行时
  依赖由目标系统的官方签名软件源解析，不被伪装进项目包。
- 构建和校验没有访问主路由器或真实 U25S。
