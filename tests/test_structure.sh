#!/bin/sh
set -eu

TEST_NAME=test_structure
. ./tests/testlib.sh

backend=package/zte-usb-wifi-manager
luci='luci-app-zte-usb-wifi-manager'

assert_file_contains "$backend/Makefile" '^PKG_NAME:=zte-usb-wifi-manager$'
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option write_enabled '0'"
assert_file_contains "$backend/files/etc/init.d/zte-usb-wifi-manager" '^USE_PROCD=1$'
assert_file_contains "$backend/files/usr/libexec/rpcd/zte_usb_wifi" '"status"'
assert_file_contains "$backend/files/usr/libexec/rpcd/zte_usb_wifi" '"capabilities"'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh" '^ZTE_CAP_SIM_SWITCH=0$'

menu="$luci/root/usr/share/luci/menu.d/luci-app-zte-usb-wifi-manager.json"
assert_file_contains "$menu" '"path": "zte-usb-wifi-manager/index"'
assert_file_contains "$menu" '"title": "中兴随身 WiFi"'

acl="$luci/root/usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json"
if grep -q '"uci"' "$acl"; then
    fail 'LuCI ACL must not grant UCI access'
else
    pass
fi
assert_success node -e '
const fs = require("fs");
const acl = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const read = acl["luci-app-zte-usb-wifi-manager"].read;
if (JSON.stringify(Object.keys(read)) !== JSON.stringify(["ubus"]))
    process.exit(1);
if (JSON.stringify(Object.keys(read.ubus)) !== JSON.stringify(["zte_usb_wifi"]))
    process.exit(1);
if (JSON.stringify(read.ubus.zte_usb_wifi) !== JSON.stringify(["status", "capabilities"]))
    process.exit(1);
' "$acl"

view="$luci/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js"
for tab in overview network wifi traffic sms battery schedule device diagnostics logs; do
    assert_file_contains "$view" "id: '$tab'"
done
assert_file_contains "$view" '设备写接口尚未完成实机校准'
assert_file_contains "$view" 'status\.device'
assert_file_contains "$view" 'is_default_route'
assert_file_contains "$view" 'battery'
assert_file_contains "$view" '仅监控'
assert_file_contains "$view" 'status\.online === true'
assert_file_contains "$view" 'status\.online === false'
assert_file_contains "$view" 'network\.up === true'
assert_file_contains "$view" 'network\.up === false'

if grep -R -q '双卡智能切换\\|SET_DUAL_SIM_SMART_SWITCH' \
    "$backend" "$luci" 2>/dev/null; then
    fail 'unsupported smart SIM switching must not be shipped'
else
    pass
fi

assert_file_contains docs/design/zte-usb-wifi-manager-ui.html '<title>中兴随身 WiFi 管理</title>'
assert_file_contains docs/design/zte-usb-wifi-manager-design.md '^# 中兴随身 WiFi 管理工具详细设计文档$'

daemon="$backend/files/usr/sbin/zte-usb-wifi-managerd"
for library in json.sh session.sh snapshot.sh netifd-adapter.sh; do
    assert_file_contains "$daemon" "$library"
done
for function in zte_adapter_fetch zte_failures_next zte_snapshot_compose; do
    assert_file_contains "$daemon" "$function"
done
assert_file_contains "$daemon" 'sleep.*zte_backoff_interval'
assert_file_contains "$daemon" 'zte_validate_interface.*interface'
assert_file_contains "$daemon" 'zte_validate_netdev.*netdev'
assert_file_contains "$daemon" 'init_state'
assert_file_contains "$daemon" '^[[:space:]]*state=credentials_missing$'
assert_file_contains "$daemon" '^[[:space:]]*reason=credential_file_unreadable$'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/session.sh" 'goformId=LOGIN'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh" 'multi_data=1'
assert_file_contains tests/fixtures/u25s/read_ok.json 'NR5G-SA'
assert_file_contains Makefile 'tests/test_session.sh'
assert_file_contains Makefile 'tests/test_adapter.sh'

# Execute the daemon orchestration functions with side-effect-free stubs.
lib="$backend/files/usr/lib/zte-usb-wifi-manager"
. "$lib/json.sh"
. "$lib/snapshot.sh"
extract_daemon_function() {
    sed -n "/^$1() {$/,/^}$/p" "$daemon"
}
eval "$(extract_daemon_function poll_once)"
eval "$(extract_daemon_function main)"

work=/tmp/zte-test-daemon.$$
mkdir -p "$work"
fetch_count=$work/fetch-count
status_log=$work/status
printf 0 >"$fetch_count"
: >"$status_log"

dev1='{"online":true,"model":"U25S","battery":{"present":true,"percent":82,"charging":false}}'
dev2='{"online":true,"model":"U25S","battery":{"present":true,"percent":83,"charging":false}}'
net='{"up":true,"l3_device":"eth2","ipv4":"","gateway":"","is_default_route":false}'
credential_file=unused
host=192.168.0.1
# Read by the eval-defined production poll_once function.
# shellcheck disable=SC2034
COOKIE_FILE=$work/cookies
failure_threshold=3
battery_enabled=0
battery_low=70
battery_high=100
failures=0
# Read by the eval-defined production poll_once function.
# shellcheck disable=SC2034
last_device_json=''

zte_read_password() { printf '%s\n' secret; }
zte_adapter_fetch() {
    n=$(cat "$fetch_count")
    n=$((n + 1))
    printf '%s' "$n" >"$fetch_count"
    case $n in
        1) printf '%s\n' "$dev1" ;;
        2) printf '%s\n' partial ;;
        3) return 1 ;;
        4) printf '%s\n' "$dev2" ;;
    esac
}
zte_adapter_normalize() {
    if [ "$1" = partial ]; then
        printf '%s\n' '{"partial":true}'
        return 1
    fi
    printf '%s\n' "$1"
}
collect_network() { network_json=$net; }
zte_is_uint() {
    case ${1-} in ''|*[!0-9]*) return 1 ;; esac
}
zte_policy_decide() { printf '%s\n' 'DISABLED:KEEP'; }
date() { printf '%s\n' 1722345678; }
write_status() { printf '%s\n' "$1" >>"$status_log"; }

poll_once
poll_once
poll_once
poll_once
assert_eq \
    "$(zte_snapshot_compose ok '' "$dev1" "$net" DISABLED KEEP 0 1722345678)" \
    "$(sed -n '1p' "$status_log")"
assert_eq \
    "$(zte_snapshot_compose degraded device_read_failed "$dev1" "$net" unavailable none 1 1722345678)" \
    "$(sed -n '2p' "$status_log")"
assert_eq \
    "$(zte_snapshot_compose degraded device_read_failed "$dev1" "$net" unavailable none 2 1722345678)" \
    "$(sed -n '3p' "$status_log")"
assert_eq \
    "$(zte_snapshot_compose ok '' "$dev2" "$net" DISABLED KEEP 0 1722345678)" \
    "$(sed -n '4p' "$status_log")"

# Production collect_network passes both configured names to the adapter.
eval "$(extract_daemon_function collect_network)"
collect_args=$work/collect-args
ubus() { :; }
jsonfilter() { :; }
zte_netifd_collect() {
    printf '%s|%s\n' "$1" "$2" >"$collect_args"
    printf '%s\n' "$net"
}
interface=usbwan
netdev=eth2
collect_network
assert_eq 'usbwan|eth2' "$(cat "$collect_args")"
assert_eq "$net" "$network_json"

# Production load_config rejects unsafe names without terminating the shell.
. "$lib/validation.sh"
eval "$(extract_daemon_function load_config)"
config_load() { :; }
# Assignments are read by the eval-defined production load_config function.
# shellcheck disable=SC2034
config_get() {
    case $1 in
        enabled) enabled=1 ;;
        poll_interval) poll_interval=30 ;;
        failure_threshold) failure_threshold=3 ;;
        host) host=192.168.0.1 ;;
        interface) interface=$_zte_test_interface ;;
        netdev) netdev=$_zte_test_netdev ;;
        credential_file) credential_file=unused ;;
        battery_enabled) battery_enabled=0 ;;
        battery_low) battery_low=70 ;;
        battery_high) battery_high=100 ;;
    esac
}
logger() { :; }
_zte_test_interface='bad/name'
_zte_test_netdev=eth2
assert_failure load_config
_zte_test_interface=usbwan
_zte_test_netdev='bad netdev'
assert_failure load_config
_zte_test_interface=usbwan
_zte_test_netdev=eth2
assert_success load_config

sleep_log=$work/sleep
: >"$sleep_log"
# Assignments are read by the eval-defined production main function.
# shellcheck disable=SC2034
load_config() {
    enabled=1
    poll_interval=30
}
init_state() { :; }
main_poll_count=0
# Assignments are read by the eval-defined production main function.
# shellcheck disable=SC2034
poll_once() {
    main_poll_count=$((main_poll_count + 1))
    case $main_poll_count in
        1) failures=1 ;;
        2) failures=2 ;;
        3)
            failures=0
            enabled=0
            ;;
    esac
}
sleep() { printf '%s\n' "$1" >>"$sleep_log"; }
main
assert_eq '60
120
30' "$(cat "$sleep_log")"

rm -rf "$work"
finish
