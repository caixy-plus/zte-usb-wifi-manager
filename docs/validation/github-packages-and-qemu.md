# GitHub 安装包与 QEMU 验证

本文档供维护者验证 GitHub Actions 生成的安装包。验证环境必须是一次性的本地
OpenWrt 虚拟机，不得连接主路由器或真实 U25S。

## 1. 运行 GitHub 构建

从已经包含 `.github/workflows/packages.yml` 的 `main` 分支触发：

```sh
commit_sha=$(git rev-parse origin/main)
started_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
gh workflow run packages.yml --ref main
run_id=
attempt=0
while [ -z "$run_id" ] && [ "$attempt" -lt 24 ]; do
    run_id=$(gh run list --workflow packages.yml --event workflow_dispatch \
        --branch main --commit "$commit_sha" --limit 10 \
        --json databaseId,createdAt,headSha \
        --jq ".[] | select(.headSha == \"$commit_sha\" and .createdAt >= \"$started_at\") | .databaseId" \
        | head -n 1)
    [ -n "$run_id" ] || sleep 5
    attempt=$((attempt + 1))
done
[ -n "$run_id" ]
gh run watch "$run_id" --exit-status
```

下载 GitHub 生成的完整产物并验证。macOS 主机没有 GNU `sha256sum`，先安装
coreutils 并选择可用命令：

```sh
brew install coreutils   # 提供 gsha256sum；仅需一次
sha256sum_cmd=sha256sum
command -v sha256sum >/dev/null 2>&1 || sha256sum_cmd=gsha256sum

artifact_dir=$(mktemp -d)
gh run download "$run_id" --name openwrt-packages --dir "$artifact_dir"
(cd "$artifact_dir" && "$sha256sum_cmd" -c SHA256SUMS)
```

目录中必须恰好包含两份 APK、两份 IPK、`SHA256SUMS` 和
`build-manifest.json`。安装验证必须使用这里下载的文件，不能用本地重新构建的文件
替代。

## 2. 准备官方 OpenWrt 镜像

macOS 缺少 QEMU 时安装：

```sh
brew install qemu coreutils
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
    printf '%s\n' "$image_sha256 *$image_file" | "$sha256sum_cmd" -c -
)
gzip_status=0
gzip -dc "$vm_dir/$image_file" >"$vm_dir/base.img" || gzip_status=$?
# macOS gzip 会把 24.10.7 官方镜像的尾随填充报告为状态 2；压缩文件
# 已由官方 SHA-256 校验，且下一步还会让 qemu-img 验证解压后的磁盘。
case "$release:$gzip_status" in
    25.12.5:0|24.10.7:0|24.10.7:2) ;;
    *) exit "$gzip_status" ;;
esac
qemu-img info "$vm_dir/base.img" >/dev/null
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

# 保留虚拟网段到 QEMU 网关的直连路由，禁止访问其他私有地址。
for private_net in \
    10.0.0.0/8 \
    100.64.0.0/10 \
    169.254.0.0/16 \
    172.16.0.0/12 \
    192.168.0.0/16; do
    ip route replace prohibit "$private_net" metric 5
done
sysctl -w net.ipv6.conf.all.disable_ipv6=1
if ip route get 192.168.0.1 >/dev/null 2>&1; then exit 1; fi
if ip route get 10.0.0.1 >/dev/null 2>&1; then exit 1; fi
```

这组拒绝路由必须在执行 `apk update` 或 `opkg update` 前生效。虚拟网段自身的
`192.168.1.0/24` 直连路由比拒绝路由更具体，因此仍可访问 QEMU 网关，但其他私网
目标（包括 U25S 默认地址）无法经用户网络转发。不要桥接物理 LAN。

另开终端断言固件版本：

```sh
actual_release=$(ssh \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p "$ssh_port" root@127.0.0.1 \
    '. /etc/openwrt_release; printf "%s\n" "$DISTRIB_RELEASE"')
[ "$actual_release" = "$release" ]
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
test -x /etc/init.d/zte-usb-wifi-manager
test -x /usr/sbin/zte-usb-wifi-managerd
test -x /usr/libexec/rpcd/zte_usb_wifi
[ "$(stat -c '%a' /etc/init.d/zte-usb-wifi-manager)" = 755 ]
[ "$(stat -c '%a' /usr/sbin/zte-usb-wifi-managerd)" = 755 ]
[ "$(stat -c '%a' /usr/libexec/rpcd/zte_usb_wifi)" = 755 ]

test -f /etc/config/zte-usb-wifi-manager
test -f /usr/share/luci/menu.d/luci-app-zte-usb-wifi-manager.json
test -f /usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json
test -f /www/luci-static/resources/view/zte-usb-wifi-manager/index.js
grep -Fq "option write_enabled '0'" /etc/config/zte-usb-wifi-manager

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
sleep 2

ubus list zte_usb_wifi
ubus call service list '{"name":"zte-usb-wifi-manager"}' \
    >/tmp/zte-service.json
ubus call zte_usb_wifi capabilities >/tmp/zte-capabilities.json
ubus call zte_usb_wifi status >/tmp/zte-status.json
jsonfilter -i /tmp/zte-service.json -e '@["zte-usb-wifi-manager"]' >/dev/null
jsonfilter -i /tmp/zte-capabilities.json -e '@' >/dev/null
jsonfilter -i /tmp/zte-status.json -e '@' >/dev/null
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
! opkg list-installed | grep -q '^zte-usb-wifi-manager '
! opkg list-installed | grep -q '^luci-app-zte-usb-wifi-manager '
test ! -e /usr/libexec/rpcd/zte_usb_wifi
test ! -e /www/luci-static/resources/view/zte-usb-wifi-manager/index.js
```

最后在虚拟机中执行 `poweroff`，QEMU 退出后删除 `$vm_dir`。

## 7. 验证预发布文件

标签工作流完成后下载 Release 中的原始文件：

```sh
release_dir=$(mktemp -d)
gh release download v0.1.0-rc1-r10 --dir "$release_dir"
(cd "$release_dir" && "$sha256sum_cmd" -c SHA256SUMS)
```

使用新的 QEMU overlay，按第 3 至第 6 节重新安装 Release 文件。只有这一步成功后，
README 才能把对应版本标记为“QEMU 安装验证通过”。
