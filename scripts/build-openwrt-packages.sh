#!/bin/sh
set -eu
set -f

die() {
    printf 'build-openwrt-packages: %s\n' "$*" >&2
    exit 1
}

read_ipk_metadata() {
    package_file=$1
    control_archive=$work_dir/ipk-control.tar.gz

    # OpenWrt 24.10 emits gzip-compressed tar IPKs, while older tools and
    # third-party builders may still emit the traditional ar container.
    if tar -xOf "$package_file" ./control.tar.gz \
        >"$control_archive" 2>/dev/null &&
        tar -xzOf - ./control <"$control_archive" 2>/dev/null; then
        rm -f "$control_archive"
        return 0
    fi
    if ar p "$package_file" control.tar.gz \
        >"$control_archive" 2>/dev/null &&
        tar -xzOf - ./control <"$control_archive" 2>/dev/null; then
        rm -f "$control_archive"
        return 0
    fi

    rm -f "$control_archive"
    return 1
}

[ "$#" -eq 2 ] ||
    die 'usage: build-openwrt-packages.sh RELEASE OUTPUT_DIRECTORY'

requested_release=$1
output_dir=$2
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

build_inputs_status=$(git -C "$repo_root" status --porcelain \
    --untracked-files=all -- \
    scripts/build-openwrt-packages.sh \
    scripts/openwrt-release-matrix.sh \
    package/zte-usb-wifi-manager \
    luci-app-zte-usb-wifi-manager)
[ -z "$build_inputs_status" ] ||
    die 'build inputs differ from HEAD; commit or restore them first'

matrix=$("$script_dir/openwrt-release-matrix.sh" "$requested_release")
IFS='|' read -r release format sdk_file sdk_sha256 image_file image_sha256 \
    feeds_sha256 <<EOF
$matrix
EOF
if [ -z "$release" ] || [ -z "$format" ] || [ -z "$sdk_file" ] ||
    [ -z "$sdk_sha256" ] || [ -z "$image_file" ] ||
    [ -z "$image_sha256" ] || [ -z "$feeds_sha256" ]; then
    die 'invalid release matrix entry'
fi

case $output_dir in
    /*) ;;
    *) output_dir=$PWD/$output_dir ;;
esac

[ ! -e "$output_dir" ] ||
    die "output directory already exists: $output_dir"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/zte-openwrt-build.XXXXXX")
staged_output=
cleanup() {
    rm -rf "$work_dir"
    [ -z "$staged_output" ] || rm -rf "$staged_output"
}
trap cleanup EXIT HUP INT TERM

output_parent=$(dirname "$output_dir")
output_name=$(basename "$output_dir")
mkdir -p "$output_parent"
staged_output=$(mktemp -d "$output_parent/.${output_name}.tmp.XXXXXX")

base_url="https://downloads.openwrt.org/releases/$release/targets/x86/64"
curl -fL --retry 3 --proto '=https' \
    "$base_url/sha256sums" -o "$work_dir/sha256sums"
curl -fL --retry 3 --proto '=https' \
    "$base_url/feeds.buildinfo" -o "$work_dir/feeds.buildinfo"
curl -fL --retry 3 --proto '=https' \
    "$base_url/$sdk_file" -o "$work_dir/$sdk_file"

official_entry="$sdk_sha256 *$sdk_file"
grep -Fqx "$official_entry" "$work_dir/sha256sums" ||
    die 'pinned SDK checksum does not match the official checksum list'
official_feeds_entry="$feeds_sha256 *feeds.buildinfo"
grep -Fqx "$official_feeds_entry" "$work_dir/sha256sums" ||
    die 'pinned feeds checksum does not match the official checksum list'
(
    cd "$work_dir"
    printf '%s\n' "$official_entry" | sha256sum -c -
    printf '%s\n' "$official_feeds_entry" | sha256sum -c -
)

mkdir "$work_dir/sdk"
tar --zstd -xf "$work_dir/$sdk_file" -C "$work_dir/sdk"
sdk_list=$work_dir/sdk-directories
find "$work_dir/sdk" -mindepth 1 -maxdepth 1 -type d -print >"$sdk_list"
sdk_count=$(wc -l <"$sdk_list" | tr -d ' ')
[ "$sdk_count" -eq 1 ] ||
    die "SDK archive must contain one top-level directory, found $sdk_count"
IFS= read -r sdk_dir <"$sdk_list"

(
    cd "$sdk_dir"
    cp "$work_dir/feeds.buildinfo" feeds.conf
    ./scripts/feeds update -a
    [ -f feeds/luci/luci.mk ] ||
        die 'pinned LuCI feed does not contain luci.mk'
    # Install only LuCI's build helper. Runtime dependencies such as curl are
    # supplied by the target router's signed package repositories; adding all
    # feed sources here would make the trimmed SDK try to rebuild them.
    ./scripts/feeds install -p luci luci-base
    [ ! -e package/feeds/packages/curl ] ||
        die 'selective feed setup unexpectedly installed curl source'
    ln -s "$repo_root/package/zte-usb-wifi-manager" \
        package/zte-usb-wifi-manager
    ln -s "$repo_root/luci-app-zte-usb-wifi-manager" \
        package/luci-app-zte-usb-wifi-manager
    printf '%s\n' \
        'CONFIG_PACKAGE_zte-usb-wifi-manager=m' \
        'CONFIG_PACKAGE_luci-app-zte-usb-wifi-manager=m' >>.config
    make defconfig
    grep -Fqx 'CONFIG_PACKAGE_zte-usb-wifi-manager=m' .config ||
        die 'SDK configuration did not select the backend package'
    grep -Fqx 'CONFIG_PACKAGE_luci-app-zte-usb-wifi-manager=m' .config ||
        die 'SDK configuration did not select the LuCI package'
    make package/zte-usb-wifi-manager/compile V=s
    make package/luci-app-zte-usb-wifi-manager/compile V=s
)

case $format in
    apk)
        backend_pattern='zte-usb-wifi-manager-0.1.0_rc1-r14.apk'
        luci_pattern='luci-app-zte-usb-wifi-manager-0.1.0_rc1-r3.apk'
        package_architecture=noarch
        ;;
    ipk)
        backend_pattern='zte-usb-wifi-manager_0.1.0_rc1-r14_all.ipk'
        luci_pattern='luci-app-zte-usb-wifi-manager_0.1.0_rc1-r3_all.ipk'
        package_architecture=all
        ;;
    *)
        die "unsupported package format in matrix: $format"
        ;;
esac

backend_list=$work_dir/backend-packages
find "$sdk_dir/bin" -type f \
    -name "$backend_pattern" -print >"$backend_list"
backend_count=$(wc -l <"$backend_list" | tr -d ' ')
[ "$backend_count" -eq 1 ] ||
    die "expected one backend .$format package, found $backend_count"
IFS= read -r backend_package <"$backend_list"

luci_list=$work_dir/luci-packages
find "$sdk_dir/bin" -type f \
    -name "$luci_pattern" -print >"$luci_list"
luci_count=$(wc -l <"$luci_list" | tr -d ' ')
[ "$luci_count" -eq 1 ] ||
    die "expected one LuCI .$format package, found $luci_count"
IFS= read -r luci_package <"$luci_list"

if [ -L "$backend_package" ] || [ -L "$luci_package" ]; then
    die 'package outputs must be regular files, not symlinks'
fi

# Read the architecture from inside the built packages; never trust the
# filename or the matrix value. APK v3 metadata is dumped with the SDK's own
# apk tool; IPK control data supports both OpenWrt's tar wrapper and the
# traditional ar wrapper.
case $format in
    apk)
        apk_tool=$sdk_dir/staging_dir/host/bin/apk
        [ -x "$apk_tool" ] || die 'SDK apk host tool is missing'
        backend_metadata=$("$apk_tool" adbdump "$backend_package" 2>/dev/null) ||
            die "cannot read APK metadata: $backend_package"
        luci_metadata=$("$apk_tool" adbdump "$luci_package" 2>/dev/null) ||
            die "cannot read APK metadata: $luci_package"
        printf '%s\n' "$backend_metadata" |
            grep -Fqx '  name: zte-usb-wifi-manager' ||
            die "$backend_package has unexpected APK metadata"
        printf '%s\n' "$backend_metadata" |
            grep -Fqx '  version: 0.1.0_rc1-r14' ||
            die "$backend_package has unexpected APK metadata"
        printf '%s\n' "$backend_metadata" |
            grep -Fqx '  arch: noarch' ||
            die "$backend_package has unexpected APK metadata"
        printf '%s\n' "$luci_metadata" |
            grep -Fqx '  name: luci-app-zte-usb-wifi-manager' ||
            die "$luci_package has unexpected APK metadata"
        printf '%s\n' "$luci_metadata" |
            grep -Fqx '  version: 0.1.0_rc1-r3' ||
            die "$luci_package has unexpected APK metadata"
        printf '%s\n' "$luci_metadata" |
            grep -Fqx '  arch: noarch' ||
            die "$luci_package has unexpected APK metadata"
        ;;
    ipk)
        backend_metadata=$(read_ipk_metadata "$backend_package") ||
            die "cannot read IPK metadata: $backend_package"
        luci_metadata=$(read_ipk_metadata "$luci_package") ||
            die "cannot read IPK metadata: $luci_package"
        printf '%s\n' "$backend_metadata" |
            grep -Fqx 'Package: zte-usb-wifi-manager' ||
            die "$backend_package has unexpected IPK metadata"
        printf '%s\n' "$backend_metadata" |
            grep -Fqx 'Version: 0.1.0_rc1-r14' ||
            die "$backend_package has unexpected IPK metadata"
        printf '%s\n' "$backend_metadata" |
            grep -Fqx 'Architecture: all' ||
            die "$backend_package has unexpected IPK metadata"
        printf '%s\n' "$luci_metadata" |
            grep -Fqx 'Package: luci-app-zte-usb-wifi-manager' ||
            die "$luci_package has unexpected IPK metadata"
        printf '%s\n' "$luci_metadata" |
            grep -Fqx 'Version: 0.1.0_rc1-r3' ||
            die "$luci_package has unexpected IPK metadata"
        printf '%s\n' "$luci_metadata" |
            grep -Fqx 'Architecture: all' ||
            die "$luci_package has unexpected IPK metadata"
        ;;
esac

backend_name=$(basename "$backend_package")
luci_name=$(basename "$luci_package")
cp "$backend_package" "$staged_output/$backend_name"
cp "$luci_package" "$staged_output/$luci_name"

backend_sha256=$(sha256sum "$staged_output/$backend_name" | awk '{print $1}')
luci_sha256=$(sha256sum "$staged_output/$luci_name" | awk '{print $1}')
commit_sha=$(git -C "$repo_root" rev-parse HEAD)

node - "$staged_output/build-manifest.json" \
    "$release" "$format" "$package_architecture" \
    "$sdk_file" "$sdk_sha256" "$feeds_sha256" "$commit_sha" \
    "$backend_name" "$backend_sha256" "$luci_name" "$luci_sha256" <<'NODE'
const fs = require('fs');
const [
    manifestPath,
    release,
    format,
    architecture,
    sdkFile,
    sdkSha256,
    feedsSha256,
    commitSha,
    backendName,
    backendSha256,
    luciName,
    luciSha256
] = process.argv.slice(2);

fs.writeFileSync(manifestPath, JSON.stringify({
    openwrt_release: release,
    package_format: format,
    package_architecture: architecture,
    sdk: {
        filename: sdkFile,
        sha256: sdkSha256
    },
    feeds_sha256: feedsSha256,
    source_commit: commitSha,
    packages: [
        { filename: backendName, sha256: backendSha256 },
        { filename: luciName, sha256: luciSha256 }
    ]
}, null, 2) + '\n');
NODE

mv "$staged_output" "$output_dir"
staged_output=
printf 'built OpenWrt %s packages in %s\n' "$release" "$output_dir"
