# QEMU 安装验证（2026-07-30）

## 结论

对 GitHub Actions 运行 `30532144723` 的下载产物完成离线 QEMU 安装、服务、
rpcd/ubus、只读默认值和卸载验证：

| 虚拟系统 | 安装与依赖 | 服务与 ubus | 卸载 | 结果 |
|---|---|---|---|---|
| OpenWrt 25.12.5 x86/64 | PASS | PASS | PASS | PASS |
| OpenWrt 24.10.7 x86/64 | PASS | PASS | PASS | PASS |

这是发布前 Actions artifact 的验证。标签创建后的 GitHub Release 原始文件仍需在
新的 QEMU overlay 中复验；完成前 README 保持“等待 QEMU 安装验证”。

## 环境隔离

- 使用 OpenWrt 官方 x86/64 generic-ext4-combined-efi 镜像并核对下载校验值。
- QEMU 只使用用户态 NAT，没有桥接到宿主机物理网络。
- 客体配置了针对 `10.0.0.0/8`、`100.64.0.0/10`、`169.254.0.0/16`、
  `172.16.0.0/12`、`192.168.0.0/16` 的禁止路由，只保留访问 QEMU 网关所需的
  更具体虚拟网段路由；IPv6 已关闭。
- 没有连接、探测或修改主路由器和真实 U25S。
- 测试凭据文件为空且权限为 `0600`，未写入密码、Cookie 或设备标识。

## 安装验证

安装前移除插件和已有的 `coreutils-stat`，随后先更新官方签名软件源，再使用正常的
本地包安装命令。没有使用 `--force-depends` 或 `--force-architecture`。

两个系统都由包管理器自动安装 `coreutils-stat` 及其他运行时依赖；安装完成后
`stat -c '%a'` 可用。后端包的依赖元数据明确包含 `coreutils-stat`。

验证项目包括：

- daemon、init、rpcd 文件存在且可执行文件模式为 `0755`；
- UCI 配置存在，`write_enabled=0`、策略 `enabled=0`；
- procd 服务处于 `running`；
- rpcd 重启并等待后，`ubus list zte_usb_wifi` 返回对象；
- `capabilities` 和 `status` 均返回可解析 JSON；
- 能力响应保持只读，所有写能力均为 `false`；
- 无设备场景返回 `online=false` 和 `credentials_missing`，没有触发设备写操作。

两套环境的验证脚本最终都输出 `validation=PASS`。

## 卸载验证

停止并禁用服务后，分别通过 `apk del` 和 `opkg remove` 卸载前后端包。包数据库中
不再存在两个项目包，rpcd 脚本和 LuCI 页面文件均已删除。两套环境最终都输出
`uninstall=PASS`。

卸载过程中 init 脚本在服务已经停止时打印一次无害的 “service delete: Not found”
提示；包管理器返回成功，且上述卸载后检查全部通过。
