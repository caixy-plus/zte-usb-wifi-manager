# GitHub 安装包与 QEMU 验证

本文档供维护者验证 GitHub Actions 生成的安装包。验证环境必须是一次性的本地
OpenWrt 虚拟机，不得连接主路由器或真实 U25S。

## 1. 运行 GitHub 构建

从已经包含 `.github/workflows/packages.yml` 的 `main` 分支触发：

```sh
gh workflow run packages.yml --ref main
run_id=$(gh run list --workflow packages.yml --limit 1 \
    --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --exit-status
```

下载 GitHub 生成的完整产物并验证：

```sh
artifact_dir=$(mktemp -d)
gh run download "$run_id" --name openwrt-packages --dir "$artifact_dir"
(cd "$artifact_dir" && sha256sum -c SHA256SUMS)
```

目录中必须恰好包含两份 APK、两份 IPK、`SHA256SUMS` 和
`build-manifest.json`。安装验证必须使用这里下载的文件，不能用本地重新构建的文件
替代。

## 2. 准备官方 OpenWrt 镜像

macOS 缺少 QEMU 时安装：

```sh
brew install qemu
```

为每个版本分别执行以下过程：

```sh
release=25.12.5
matrix=$(./scripts/openwrt-release-matrix.sh "$release")
old_ifs=$IFS
IFS='|'
set -- $matrix
IFS=$old_ifs
image_file=$5
image_sha256=$6
base_url="https://downloads.openwrt.org/releases/$release/targets/x86/64"

vm_dir=$(mktemp -d)
curl -fL --retry 3 --proto '=https' \
    "$base_url/sha256sums" -o "$vm_dir/sha256sums"
curl -fL --retry 3 --proto '=https' \
    "$base_url/$image_file" -o "$vm_dir/$image_file"
grep -Fqx "$image_sha256 *$image_file" "$vm_dir/sha256sums"
(
    cd "$vm_dir"
    printf '%s\n' "$image_sha256 *$image_file" | sha256sum -c -
)
gzip -dc "$vm_dir/$image_file" >"$vm_dir/base.img"
qemu-img create -f qcow2 -F raw -b "$vm_dir/base.img" "$vm_dir/overlay.qcow2"
```

对于 24.10.7，将第一行改为：

```sh
release=24.10.7
```

## 3. 启动隔离虚拟机

25.12.5 使用本机端口 `22512`，24.10.7 使用 `22410`。以下示例是 25.12.5：

```sh
ssh_port=22512
qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu max \
    -m 512 \
    -nographic \
    -drive "file=$vm_dir/overlay.qcow2,if=virtio,format=qcow2" \
    -nic "user,model=virtio-net-pci,net=192.168.1.0/24,hostfwd=tcp:127.0.0.1:$ssh_port-192.168.1.1:22"
```

在串口控制台按 Enter 后配置 QEMU 用户网络的网关和 DNS：

```sh
uci set network.lan.gateway='192.168.1.2'
uci -q delete network.lan.dns
uci add_list network.lan.dns='192.168.1.3'
uci commit network
/etc/init.d/network restart
```

不要桥接物理 LAN。另开终端确认 SSH：

```sh
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p "$ssh_port" root@127.0.0.1 cat /etc/openwrt_release
```

## 4. 上传并安装 GitHub 产物

上传对应格式的两个包：

```sh
scp -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -P "$ssh_port" "$artifact_dir"/*.apk root@127.0.0.1:/tmp/
```

24.10.7 将 `*.apk` 改为 `*.ipk`。

OpenWrt 25.12.5：

```sh
apk update
apk add --allow-untrusted \
    /tmp/zte-usb-wifi-manager*.apk \
    /tmp/luci-app-zte-usb-wifi-manager*.apk
apk info -e zte-usb-wifi-manager
apk info -e luci-app-zte-usb-wifi-manager
```

OpenWrt 24.10.7：

```sh
opkg update
opkg install \
    /tmp/zte-usb-wifi-manager_*.ipk \
    /tmp/luci-app-zte-usb-wifi-manager_*.ipk
opkg status zte-usb-wifi-manager
opkg status luci-app-zte-usb-wifi-manager
```

不得加入 `--force-depends`、`--force-architecture`，也不得手工复制文件到根文件系统。

## 5. 验证服务和 ubus

在虚拟机中执行：

```sh
stat -c '%a %n' \
    /etc/init.d/zte-usb-wifi-manager \
    /usr/libexec/rpcd/zte_usb_wifi

umask 077
mkdir -p /etc/zte-usb-wifi-manager
touch /etc/zte-usb-wifi-manager/credentials
chmod 600 /etc/zte-usb-wifi-manager/credentials

uci set zte-usb-wifi-manager.main.write_enabled='0'
uci set zte-usb-wifi-manager.policy.enabled='0'
uci commit zte-usb-wifi-manager

/etc/init.d/zte-usb-wifi-manager enable
/etc/init.d/zte-usb-wifi-manager restart
/etc/init.d/zte-usb-wifi-manager status
/etc/init.d/rpcd restart

ubus list zte_usb_wifi
ubus call zte_usb_wifi capabilities
ubus call zte_usb_wifi status
```

两个 ubus 调用必须返回可解析 JSON。由于没有连接 U25S，`status` 可以报告凭据或设备
不可用，但 rpcd 对象不能消失或返回无效 JSON。

## 6. 验证卸载

OpenWrt 25.12.5：

```sh
/etc/init.d/zte-usb-wifi-manager stop
/etc/init.d/zte-usb-wifi-manager disable
apk del luci-app-zte-usb-wifi-manager zte-usb-wifi-manager
! apk info -e zte-usb-wifi-manager
! apk info -e luci-app-zte-usb-wifi-manager
```

OpenWrt 24.10.7：

```sh
/etc/init.d/zte-usb-wifi-manager stop
/etc/init.d/zte-usb-wifi-manager disable
opkg remove luci-app-zte-usb-wifi-manager zte-usb-wifi-manager
! opkg status zte-usb-wifi-manager
! opkg status luci-app-zte-usb-wifi-manager
```

最后在虚拟机中执行 `poweroff`，QEMU 退出后删除 `$vm_dir`。

## 7. 验证预发布文件

标签工作流完成后下载 Release 中的原始文件：

```sh
release_dir=$(mktemp -d)
gh release download v0.1.0-rc1 --dir "$release_dir"
(cd "$release_dir" && sha256sum -c SHA256SUMS)
```

使用新的 QEMU overlay，按第 3 至第 6 节重新安装 Release 文件。只有这一步成功后，
README 才能把对应版本标记为“QEMU 安装验证通过”。
