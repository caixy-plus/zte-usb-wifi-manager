#!/bin/sh
set -eu

TEST_NAME=test_packaging
. ./tests/testlib.sh

work=/tmp/zte-test-packaging.$$
trap 'rm -rf "$work"' EXIT HUP INT TERM

expected_2512='25.12.5|apk|openwrt-sdk-25.12.5-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst|0c8df0151a1e88feb7c03d694d61f6a18d51872815b7c811d76e2b77504d5e9c|openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz|23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461|e11279b01e7fea7f7d399e25e969d9382be6891071cbc1225804195224b27b52'
expected_2410='24.10.7|ipk|openwrt-sdk-24.10.7-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst|996d71f9eab7df2e8acb0bb2c9726426f05c10d419e5f9600d59b14d871f2acb|openwrt-24.10.7-x86-64-generic-ext4-combined.img.gz|3caea69f186b2bce80938d265e5e2a3dfd0f8713aed101df35d60b88d7270d1f|fa4ae9a869c3bc76c5d89dc6f6532194a4d1df8e7a99d6f441aeff085124c148'

assert_eq "$expected_2512" "$(./scripts/openwrt-release-matrix.sh 25.12.5)"
assert_eq "$expected_2410" "$(./scripts/openwrt-release-matrix.sh 24.10.7)"
assert_failure ./scripts/openwrt-release-matrix.sh 23.05.6 >/dev/null 2>&1
assert_failure ./scripts/openwrt-release-matrix.sh '25.12.5;id' >/dev/null 2>&1

builder=scripts/build-openwrt-packages.sh
assert_file_contains "$builder" 'openwrt-release-matrix\.sh'
assert_file_contains "$builder" 'downloads\.openwrt\.org/releases/'
assert_file_contains "$builder" 'sha256sums'
assert_file_contains "$builder" 'feeds\.buildinfo'
assert_file_contains "$builder" 'sha256sum.*-c'
assert_file_contains "$builder" 'package/zte-usb-wifi-manager/compile'
assert_file_contains "$builder" 'package/luci-app-zte-usb-wifi-manager/compile'
assert_file_contains "$builder" 'build-manifest\.json'
assert_failure ./scripts/build-openwrt-packages.sh 23.05.6 \
    /tmp/zte-invalid-output >/dev/null 2>&1
# Match the literal shell variable expression in the production script.
# shellcheck disable=SC2016
if grep -Eq 'sdk/\*|_all\.\$format' "$builder"; then
    fail 'builder must not rely on disabled globbing or IPK-style APK names'
else
    pass
fi
assert_file_contains "$builder" 'zte-usb-wifi-manager-\*\.apk'
assert_file_contains "$builder" 'zte-usb-wifi-manager_\*_all\.ipk'
# Internal architecture must be read from the built packages, not assumed.
assert_file_contains "$builder" 'adbdump'
assert_file_contains "$builder" 'Architecture: all'
# The curl dependency needs an explicit TLS backend: a fresh SDK defconfig
# does not reliably settle curl's SSL choice default, which breaks the curl
# compile with "TLS not detected".
assert_file_contains "$builder" 'CONFIG_PACKAGE_libmbedtls=m'
assert_file_contains "$builder" 'CONFIG_LIBCURL_MBEDTLS=y'

mkdir -p "$work/incoming/packages-25.12.5" \
    "$work/incoming/packages-24.10.7"
printf apk-backend >"$work/incoming/packages-25.12.5/zte-usb-wifi-manager-0.1.0_rc1-r1.apk"
printf apk-luci >"$work/incoming/packages-25.12.5/luci-app-zte-usb-wifi-manager-0.1.0_rc1-r1.apk"
printf ipk-backend >"$work/incoming/packages-24.10.7/zte-usb-wifi-manager_0.1.0_rc1-r1_all.ipk"
printf ipk-luci >"$work/incoming/packages-24.10.7/luci-app-zte-usb-wifi-manager_0.1.0_rc1-r1_all.ipk"
node - "$work/incoming" <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const root = process.argv[2];
const source = '0123456789abcdef0123456789abcdef01234567';
const entries = [
    {
        release: '25.12.5',
        format: 'apk',
        architecture: 'noarch',
        sdk: 'openwrt-sdk-25.12.5-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst',
        sdkSha256: '0c8df0151a1e88feb7c03d694d61f6a18d51872815b7c811d76e2b77504d5e9c',
        feedsSha256: 'e11279b01e7fea7f7d399e25e969d9382be6891071cbc1225804195224b27b52'
    },
    {
        release: '24.10.7',
        format: 'ipk',
        architecture: 'all',
        sdk: 'openwrt-sdk-24.10.7-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst',
        sdkSha256: '996d71f9eab7df2e8acb0bb2c9726426f05c10d419e5f9600d59b14d871f2acb',
        feedsSha256: 'fa4ae9a869c3bc76c5d89dc6f6532194a4d1df8e7a99d6f441aeff085124c148'
    }
];
for (const {
    release,
    format,
    architecture,
    sdk,
    sdkSha256,
    feedsSha256
} of entries) {
    const dir = path.join(root, `packages-${release}`);
    const filenames = fs.readdirSync(dir).sort();
    const packages = filenames.map(filename => ({
        filename,
        sha256: crypto.createHash('sha256')
            .update(fs.readFileSync(path.join(dir, filename))).digest('hex')
    }));
    fs.writeFileSync(path.join(dir, 'build-manifest.json'), JSON.stringify({
        openwrt_release: release,
        package_format: format,
        package_architecture: architecture,
        sdk: { filename: sdk, sha256: sdkSha256 },
        feeds_sha256: feedsSha256,
        source_commit: source,
        packages
    }));
}
NODE

source_sha=0123456789abcdef0123456789abcdef01234567
assert_success node scripts/assemble-openwrt-packages.js \
    "$work/incoming" "$work/dist" "$source_sha" main
# JavaScript template literals and process arguments are intentionally quoted
# from the shell.
# shellcheck disable=SC2016
assert_success node -e '
const fs = require("fs");
const path = process.argv[1];
const files = fs.readdirSync(path).sort();
if (files.length !== 6 ||
    !files.includes("SHA256SUMS") ||
    !files.includes("build-manifest.json"))
    process.exit(1);
const manifest = JSON.parse(fs.readFileSync(`${path}/build-manifest.json`));
if (manifest.project_ref !== "main" || manifest.project_tag !== null ||
    manifest.source_commit !== process.argv[2] || manifest.builds.length !== 2)
    process.exit(1);
' "$work/dist" "$source_sha"

: >"$work/incoming/packages-25.12.5/unexpected.txt"
assert_failure node scripts/assemble-openwrt-packages.js \
    "$work/incoming" "$work/dist-unexpected" "$source_sha" main \
    >/dev/null 2>&1

workflow=.github/workflows/packages.yml
assert_file_contains "$workflow" 'workflow_dispatch:'
assert_file_contains "$workflow" 'tags:'
assert_file_contains "$workflow" '25\.12\.5'
assert_file_contains "$workflow" '24\.10\.7'
assert_file_contains "$workflow" 'contents: read'
assert_file_contains "$workflow" 'contents: write'
assert_file_contains "$workflow" 'scripts/build-openwrt-packages\.sh'
assert_file_contains "$workflow" 'SHA256SUMS'
assert_file_contains "$workflow" 'gh release create'
assert_file_contains "$workflow" '\-\-prerelease'
assert_file_contains "$workflow" "v0\\.1\\.0-rc1"
assert_file_contains "$workflow" 'scripts/assemble-openwrt-packages\.js'
assert_file_contains "$workflow" '11d5960a326750d5838078e36cf38b85af677262'
assert_file_contains "$workflow" 'ea165f8d65b6e75b540449e92b4886f43607fa02'
assert_file_contains "$workflow" 'd3f86a106a0bac45b974a628896c90dbdf5c8093'

if grep -Eq 'pull_request:|--force-depends|--force-architecture' \
    "$workflow" 2>/dev/null; then
    fail 'packaging workflow must not run on pull requests or force installs'
else
    pass
fi

finish
