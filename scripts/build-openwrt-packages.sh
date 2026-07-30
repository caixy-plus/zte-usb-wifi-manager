#!/bin/sh
set -eu
set -f

die() {
    printf 'build-openwrt-packages: %s\n' "$*" >&2
    exit 1
}

[ "$#" -eq 2 ] ||
    die 'usage: build-openwrt-packages.sh RELEASE OUTPUT_DIRECTORY'

requested_release=$1
output_dir=$2
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

matrix=$("$script_dir/openwrt-release-matrix.sh" "$requested_release")
IFS='|' read -r release format sdk_file sdk_sha256 image_file image_sha256 \
    feeds_sha256 <<EOF
$matrix
EOF
[ -n "$release" ] && [ -n "$format" ] && [ -n "$sdk_file" ] &&
    [ -n "$sdk_sha256" ] && [ -n "$image_file" ] &&
    [ -n "$image_sha256" ] && [ -n "$feeds_sha256" ] ||
    die 'invalid release matrix entry'

case $output_dir in
    /*) ;;
    *) output_dir=$PWD/$output_dir ;;
esac

[ ! -e "$output_dir" ] ||
    die "output directory already exists: $output_dir"
mkdir -p "$output_dir"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/zte-openwrt-build.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

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
    ./scripts/feeds install -a
    ln -s "$repo_root/package/zte-usb-wifi-manager" \
        package/zte-usb-wifi-manager
    ln -s "$repo_root/luci-app-zte-usb-wifi-manager" \
        package/luci-app-zte-usb-wifi-manager
    printf '%s\n' \
        'CONFIG_PACKAGE_zte-usb-wifi-manager=m' \
        'CONFIG_PACKAGE_luci-app-zte-usb-wifi-manager=m' \
        'CONFIG_PACKAGE_libmbedtls=m' \
        'CONFIG_LIBCURL_MBEDTLS=y' >>.config
    # A fresh SDK does not reliably settle curl's SSL choice default in one
    # defconfig pass; the pinned symbols above make the TLS backend explicit
    # and the second pass settles any remaining dependent defaults.
    make defconfig
    make defconfig
    make package/zte-usb-wifi-manager/compile V=s
    make package/luci-app-zte-usb-wifi-manager/compile V=s
)

case $format in
    apk)
        backend_pattern='zte-usb-wifi-manager-*.apk'
        luci_pattern='luci-app-zte-usb-wifi-manager-*.apk'
        package_architecture=noarch
        ;;
    ipk)
        backend_pattern='zte-usb-wifi-manager_*_all.ipk'
        luci_pattern='luci-app-zte-usb-wifi-manager_*_all.ipk'
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

[ ! -L "$backend_package" ] && [ ! -L "$luci_package" ] ||
    die 'package outputs must be regular files, not symlinks'

# Read the architecture from inside the built packages; never trust the
# filename or the matrix value. APK v3 metadata is dumped with the SDK's own
# apk tool; IPK control data comes from the ar member control.tar.gz.
case $format in
    apk)
        apk_tool=$sdk_dir/staging_dir/host/bin/apk
        [ -x "$apk_tool" ] || die 'SDK apk host tool is missing'
        for package_file in "$backend_package" "$luci_package"; do
            "$apk_tool" adbdump "$package_file" 2>/dev/null |
                grep -Fqx '  arch: noarch' ||
                die "$package_file is not an arch:noarch APK"
        done
        ;;
    ipk)
        for package_file in "$backend_package" "$luci_package"; do
            ar p "$package_file" control.tar.gz 2>/dev/null |
                tar -xzOf - ./control 2>/dev/null |
                grep -Fqx 'Architecture: all' ||
                die "$package_file is not an Architecture: all IPK"
        done
        ;;
esac

backend_name=$(basename "$backend_package")
luci_name=$(basename "$luci_package")
cp "$backend_package" "$output_dir/$backend_name"
cp "$luci_package" "$output_dir/$luci_name"

backend_sha256=$(sha256sum "$output_dir/$backend_name" | awk '{print $1}')
luci_sha256=$(sha256sum "$output_dir/$luci_name" | awk '{print $1}')
commit_sha=$(git -C "$repo_root" rev-parse HEAD)

node - "$output_dir/build-manifest.json" \
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

printf 'built OpenWrt %s packages in %s\n' "$release" "$output_dir"
