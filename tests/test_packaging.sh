#!/bin/sh
set -eu

TEST_NAME=test_packaging
. ./tests/testlib.sh

work=/tmp/zte-test-packaging.$$
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work"

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
assert_file_contains "$builder" \
    "zte-usb-wifi-manager-0\\.1\\.0_rc1-r5\\.apk"
assert_file_contains "$builder" \
    "zte-usb-wifi-manager_0\\.1\\.0_rc1-r5_all\\.ipk"
backend_package_definition="$work/backend-package-definition"
sed -n '/^define Package\/zte-usb-wifi-manager$/,/^endef$/p' \
    package/zte-usb-wifi-manager/Makefile >"$backend_package_definition"
assert_file_contains "$backend_package_definition" '  PKGARCH:=all'
# Internal architecture must be read from the built packages, not assumed.
assert_file_contains "$builder" 'adbdump'
assert_file_contains "$builder" 'Architecture: all'
# Runtime dependencies come from the target router's signed package feeds.
# Installing every source feed makes the SDK rebuild curl and other unrelated
# packages that the trimmed SDK cannot satisfy.
if grep -Fq './scripts/feeds install -a' "$builder"; then
    fail 'builder must not install every feed package into the source graph'
else
    pass
fi
assert_file_contains "$builder" \
    './scripts/feeds install -p luci luci-base'
assert_file_contains "$builder" \
    'package/feeds/packages/curl'
assert_file_contains luci-app-zte-usb-wifi-manager/Makefile \
    'call BuildPackage'

builder_repo="$work/builder-repo"
fake_bin="$work/fake-bin"
mkdir -p "$builder_repo/scripts" "$builder_repo/package" \
    "$builder_repo/luci-app-zte-usb-wifi-manager" "$fake_bin"
cp scripts/openwrt-release-matrix.sh scripts/build-openwrt-packages.sh \
    "$builder_repo/scripts/"
cp -R package/zte-usb-wifi-manager "$builder_repo/package/"
cp luci-app-zte-usb-wifi-manager/Makefile \
    "$builder_repo/luci-app-zte-usb-wifi-manager/"

cat >"$fake_bin/curl" <<'EOF'
#!/bin/sh
set -eu
destination=
while [ "$#" -gt 0 ]; do
    case $1 in
        -o)
            destination=$2
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
case $(basename "$destination") in
    sha256sums)
        printf '%s\n' \
            '0c8df0151a1e88feb7c03d694d61f6a18d51872815b7c811d76e2b77504d5e9c *openwrt-sdk-25.12.5-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst' \
            'e11279b01e7fea7f7d399e25e969d9382be6891071cbc1225804195224b27b52 *feeds.buildinfo' \
            '996d71f9eab7df2e8acb0bb2c9726426f05c10d419e5f9600d59b14d871f2acb *openwrt-sdk-24.10.7-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst' \
            'fa4ae9a869c3bc76c5d89dc6f6532194a4d1df8e7a99d6f441aeff085124c148 *feeds.buildinfo' \
            >"$destination"
        ;;
    *)
        printf 'fixture\n' >"$destination"
        ;;
esac
EOF

cat >"$fake_bin/sha256sum" <<'EOF'
#!/bin/sh
set -eu
if [ "${1-}" = -c ]; then
    cat >/dev/null
    exit 0
fi
printf '%064d  %s\n' 0 "$1"
EOF

cat >"$fake_bin/tar" <<'EOF'
#!/bin/sh
set -eu
case " $* " in
    *' --zstd -xf '*)
        destination=
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -C ]; then
                destination=$2
                break
            fi
            shift
        done
        root=$destination/sdk-root
        mkdir -p "$root/scripts" "$root/package" "$root/feeds/luci" \
            "$root/bin/packages/fixture" "$root/staging_dir/host/bin"
        : >"$root/feeds/luci/luci.mk"
        cat >"$root/scripts/feeds" <<'SCRIPT'
#!/bin/sh
case " $* " in
    ' install -a ')
        exit 65
        ;;
    ' install -p luci luci-base ')
        mkdir -p package/feeds/luci/luci-base
        ;;
esac
exit 0
SCRIPT
        cat >"$root/staging_dir/host/bin/apk" <<'SCRIPT'
#!/bin/sh
set -eu
package_file=$2
case $(basename "$package_file") in
    luci-app-*)
        package_name=luci-app-zte-usb-wifi-manager
        package_version=0.1.0_rc1-r3
        ;;
    *)
        package_name=zte-usb-wifi-manager
        package_version=0.1.0_rc1-r5
        ;;
esac
[ "${FAKE_WRONG_METADATA:-0}" -eq 0 ] || package_name=wrong-package
printf '%s\n' \
    "  name: $package_name" \
    "  version: $package_version" \
    '  arch: noarch'
SCRIPT
        chmod +x "$root/scripts/feeds" "$root/staging_dir/host/bin/apk"
        ;;
    *' -xOf '*' ./control.tar.gz '*)
        printf '%s\n' "$2"
        ;;
    *' -xzOf - ./control '*)
        IFS= read -r package_file
        case $(basename "$package_file") in
            luci-app-*)
                package_name=luci-app-zte-usb-wifi-manager
                package_version=0.1.0_rc1-r3
                ;;
            *)
                package_name=zte-usb-wifi-manager
                package_version=0.1.0_rc1-r5
                ;;
        esac
        [ "${FAKE_WRONG_METADATA:-0}" -eq 0 ] ||
            package_name=wrong-package
        printf '%s\n' \
            "Package: $package_name" \
            "Version: $package_version" \
            'Architecture: all'
        ;;
    *)
        exit 64
        ;;
esac
EOF

cat >"$fake_bin/ar" <<'EOF'
#!/bin/sh
set -eu
exit 66
EOF

cat >"$fake_bin/make" <<'EOF'
#!/bin/sh
set -eu
case " $* " in
    ' defconfig ')
        ;;
    *' package/zte-usb-wifi-manager/compile '*)
        [ "${FAKE_BUILD_FAIL:-0}" -eq 0 ] || exit 1
        [ ! -e package/feeds/packages/curl ] || exit 1
        printf 'apk-backend\n' \
            >bin/packages/fixture/zte-usb-wifi-manager-0.1.0_rc1-r5.apk
        printf 'ipk-backend\n' \
            >bin/packages/fixture/zte-usb-wifi-manager_0.1.0_rc1-r5_all.ipk
        ;;
    *' package/luci-app-zte-usb-wifi-manager/compile '*)
        printf 'apk-luci\n' \
            >bin/packages/fixture/luci-app-zte-usb-wifi-manager-0.1.0_rc1-r3.apk
        printf 'ipk-luci\n' \
            >bin/packages/fixture/luci-app-zte-usb-wifi-manager_0.1.0_rc1-r3_all.ipk
        ;;
esac
EOF
chmod +x "$fake_bin"/*

git -C "$builder_repo" init -q
git -C "$builder_repo" config user.name 'Packaging Test'
git -C "$builder_repo" config user.email 'packaging-test@example.invalid'
git -C "$builder_repo" add .
git -C "$builder_repo" commit -qm 'fixture'

assert_success env PATH="$fake_bin:$PATH" \
    "$builder_repo/scripts/build-openwrt-packages.sh" 25.12.5 \
    "$work/hermetic-success"
assert_file_contains "$work/hermetic-success/build-manifest.json" \
    '"source_commit": "[0-9a-f]{40}"'
assert_success env PATH="$fake_bin:$PATH" \
    "$builder_repo/scripts/build-openwrt-packages.sh" 24.10.7 \
    "$work/hermetic-ipk-success"
assert_file_contains "$work/hermetic-ipk-success/build-manifest.json" \
    '"package_format": "ipk"'

assert_failure env PATH="$fake_bin:$PATH" FAKE_BUILD_FAIL=1 \
    "$builder_repo/scripts/build-openwrt-packages.sh" 25.12.5 \
    "$work/hermetic-failure" >/dev/null 2>&1
if [ -e "$work/hermetic-failure" ]; then
    fail 'failed build must not leave the final output directory'
else
    pass
fi

assert_failure env PATH="$fake_bin:$PATH" FAKE_WRONG_METADATA=1 \
    "$builder_repo/scripts/build-openwrt-packages.sh" 25.12.5 \
    "$work/hermetic-wrong-metadata" >/dev/null 2>&1
assert_failure env PATH="$fake_bin:$PATH" FAKE_WRONG_METADATA=1 \
    "$builder_repo/scripts/build-openwrt-packages.sh" 24.10.7 \
    "$work/hermetic-wrong-ipk-metadata" >/dev/null 2>&1

printf '\n# dirty fixture\n' \
    >>"$builder_repo/package/zte-usb-wifi-manager/Makefile"
assert_failure env PATH="$fake_bin:$PATH" \
    "$builder_repo/scripts/build-openwrt-packages.sh" 25.12.5 \
    "$work/hermetic-dirty" >/dev/null 2>&1

mkdir -p "$work/incoming/packages-25.12.5" \
    "$work/incoming/packages-24.10.7"
printf apk-backend >"$work/incoming/packages-25.12.5/zte-usb-wifi-manager-0.1.0_rc1-r5.apk"
printf apk-luci >"$work/incoming/packages-25.12.5/luci-app-zte-usb-wifi-manager-0.1.0_rc1-r3.apk"
printf ipk-backend >"$work/incoming/packages-24.10.7/zte-usb-wifi-manager_0.1.0_rc1-r5_all.ipk"
printf ipk-luci >"$work/incoming/packages-24.10.7/luci-app-zte-usb-wifi-manager_0.1.0_rc1-r3_all.ipk"
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

rm "$work/incoming/packages-25.12.5/unexpected.txt"
cp -R "$work/incoming" "$work/wrong-version-incoming"
mv "$work/wrong-version-incoming/packages-25.12.5/zte-usb-wifi-manager-0.1.0_rc1-r5.apk" \
    "$work/wrong-version-incoming/packages-25.12.5/zte-usb-wifi-manager-9.9.9-r1.apk"
node - "$work/wrong-version-incoming/packages-25.12.5/build-manifest.json" <<'NODE'
const fs = require('fs');
const manifestPath = process.argv[2];
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const backend = manifest.packages.find(item =>
    item.filename.startsWith('zte-usb-wifi-manager-')
);
backend.filename = 'zte-usb-wifi-manager-9.9.9-r1.apk';
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest)}\n`);
NODE
assert_failure node scripts/assemble-openwrt-packages.js \
    "$work/wrong-version-incoming" "$work/dist-wrong-version" \
    "$source_sha" v0.1.0-rc1 >/dev/null 2>&1

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
