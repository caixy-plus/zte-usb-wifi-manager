#!/bin/sh
# Production functions are intentionally extracted and defined through eval
# below, which ShellCheck 0.9 cannot model.
# shellcheck disable=SC2218,SC2317,SC2329
set -eu

TEST_NAME=test_structure
. ./tests/testlib.sh

backend=package/zte-usb-wifi-manager
luci='luci-app-zte-usb-wifi-manager'

assert_file_contains "$backend/Makefile" '^PKG_NAME:=zte-usb-wifi-manager$'
assert_file_contains "$backend/Makefile" '^PKG_VERSION:=0\.1\.0_rc1$'
assert_file_contains "$backend/Makefile" '^PKG_RELEASE:=4$'
assert_file_contains "$backend/Makefile" '^  PKGARCH:=all$'
assert_file_contains "$backend/Makefile" \
    '^  DEPENDS:=.*\+coreutils-stat([[:space:]]|$)'
assert_file_contains "$backend/Makefile" '^  EXTRA_DEPENDS:=ip \(>=1\)$'
if grep -q '\+ip\(-tiny\|-full\)\{0,1\}\([[:space:]]\|$\)' \
    "$backend/Makefile"; then
    fail 'backend must express ip as a runtime virtual dependency'
else
    pass
fi
assert_file_contains "$backend/Makefile" \
    '^define Package/zte-usb-wifi-manager/postrm$'
assert_file_contains "$backend/Makefile" \
    'rm -rf /var/run/zte-usb-wifi-manager'
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option write_enabled '0'"
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "config schedule 'work'"
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option enabled '0'"
assert_file_contains "$backend/files/etc/init.d/zte-usb-wifi-manager" '^USE_PROCD=1$'
assert_file_contains "$backend/files/usr/libexec/rpcd/zte_usb_wifi" '"status"'
assert_file_contains "$backend/files/usr/libexec/rpcd/zte_usb_wifi" '"capabilities"'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh" '^ZTE_CAP_SIM_SWITCH=0$'

menu="$luci/root/usr/share/luci/menu.d/luci-app-zte-usb-wifi-manager.json"
assert_file_contains "$luci/Makefile" '^PKG_VERSION:=0\.1\.0_rc1$'
assert_file_contains "$luci/Makefile" '^PKG_RELEASE:=2$'
assert_file_contains "$luci/Makefile" '^LUCI_PKGARCH:=all$'
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
const write = acl["luci-app-zte-usb-wifi-manager"].write;
if (JSON.stringify(Object.keys(read)) !== JSON.stringify(["ubus"]))
    process.exit(1);
if (JSON.stringify(Object.keys(read.ubus)) !== JSON.stringify(["zte_usb_wifi"]))
    process.exit(1);
if (JSON.stringify(read.ubus.zte_usb_wifi) !==
    JSON.stringify(["status", "capabilities", "credential_status", "operation_status", "logs"]))
    process.exit(1);
if (JSON.stringify(write.ubus.zte_usb_wifi) !==
    JSON.stringify(["set_credentials", "cellular_action", "wifi_action", "traffic_action", "sms_action"]))
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
assert_file_contains README.md '^## 安装$'
assert_file_contains README.md 'apk add --allow-untrusted'
assert_file_contains README.md 'opkg install'
assert_file_contains README.md '/etc/zte-usb-wifi-manager/credentials'
assert_file_contains README.md 'OpenWrt 25\.12\.5'
assert_file_contains README.md 'OpenWrt 24\.10\.7'
assert_file_contains README.md 'OpenWrt 25\.12\.5.*QEMU 安装验证通过'
assert_file_contains README.md 'OpenWrt 24\.10\.7.*QEMU 安装验证通过'
assert_file_contains README.md 'LuCI 十个标签已可切换'
assert_file_contains README.md 'SIM 类型与电池扩展状态'
assert_file_contains README.md '短信总数与脱敏事件日志'
assert_file_contains README.md 'Wi-Fi 与流量仍等待经过验证的 fixture'
assert_file_contains README.md 'mock/dry-run Power Adapter'
assert_file_contains README.md 'hardware 后端仍保持禁用'
assert_file_contains README.md '原子动作队列'
assert_file_contains README.md '加速稳定性测试'
if grep -Fq 'USB Power Adapter 尚未实现' README.md; then
    fail 'README must not claim the implemented Power Adapter is missing'
else
    pass
fi
if grep -Fq '等待 QEMU 安装验证' README.md; then
    fail 'README must not retain a pending QEMU validation status'
else
    pass
fi
assert_file_contains README.md 'coreutils-stat'
assert_file_contains README.md '\./scripts/feeds install -p luci luci-base'
if grep -Fq './scripts/feeds install -a' README.md; then
    fail 'README source build must not install every feed package'
else
    pass
fi
if grep -Eq '25\.12 及以上|24\.10 及以下|相同 OpenWrt 版本、target/subtarget' \
    README.md; then
    fail 'README must describe only the exact tested release compatibility'
else
    pass
fi

package_validation=docs/validation/github-packages-and-qemu.md
assert_file_contains "$package_validation" '^# GitHub 安装包与 QEMU 验证$'
assert_file_contains "$package_validation" 'gh workflow run packages\.yml'
assert_file_contains "$package_validation" 'sha256sum_cmd'
assert_file_contains "$package_validation" 'gsha256sum'
assert_file_contains "$package_validation" 'apk add --allow-untrusted'
assert_file_contains "$package_validation" 'opkg install'
assert_file_contains "$package_validation" 'ubus call zte_usb_wifi capabilities'
assert_file_contains "$package_validation" 'gh release download'
assert_file_contains "$package_validation" 'ip route replace prohibit'
assert_file_contains "$package_validation" 'headSha'
assert_file_contains "$package_validation" 'test -f /usr/share/rpcd/acl\.d/luci-app-zte-usb-wifi-manager\.json'
assert_file_contains "$package_validation" 'jsonfilter'
assert_file_contains "$package_validation" 'opkg list-installed'
assert_file_contains "$package_validation" '^sleep 2$'

build_evidence=docs/validation/2026-07-30-github-actions-build.md
assert_file_contains "$build_evidence" '^# GitHub Actions 构建验证（2026-07-30）$'
assert_file_contains "$build_evidence" '30532144723'
assert_file_contains "$build_evidence" '2edfbbe8b1a7c6b0ce314c2f946ecf81304e73ed'
assert_file_contains "$build_evidence" 'OpenWrt 25\.12\.5.*PASS'
assert_file_contains "$build_evidence" 'OpenWrt 24\.10\.7.*PASS'
assert_file_contains "$build_evidence" 'sha256sum -c SHA256SUMS.*PASS'

qemu_evidence=docs/validation/2026-07-30-qemu-installation.md
assert_file_contains "$qemu_evidence" '^# QEMU 安装验证（2026-07-30）$'
assert_file_contains "$qemu_evidence" 'OpenWrt 25\.12\.5.*PASS'
assert_file_contains "$qemu_evidence" 'OpenWrt 24\.10\.7.*PASS'
assert_file_contains "$qemu_evidence" 'coreutils-stat'
assert_file_contains "$qemu_evidence" 'validation=PASS'
assert_file_contains "$qemu_evidence" 'uninstall=PASS'
assert_file_contains "$qemu_evidence" '30532866289'
assert_file_contains "$qemu_evidence" 'v0\.1\.0-rc1'
assert_file_contains "$qemu_evidence" 'Release 文件完整性.*PASS'
assert_file_contains "$qemu_evidence" 'Release 安装与依赖.*PASS'
assert_file_contains "$qemu_evidence" 'Release 服务与 ubus.*PASS'
assert_file_contains "$qemu_evidence" 'Release 卸载.*PASS'

daemon="$backend/files/usr/sbin/zte-usb-wifi-managerd"
assert_file_contains "$daemon" '^set -e$'
for library in \
    json.sh credentials.sh session.sh snapshot.sh netifd-adapter.sh \
    power-adapter.sh event-log.sh \
    actions.sh recovery-inhibit.sh schedule.sh
do
    assert_file_contains "$daemon" "$library"
done
for function in \
    zte_adapter_fetch zte_failures_next zte_snapshot_compose zte_power_apply \
    zte_event_write zte_action_claim zte_action_finish \
    zte_action_prune_results zte_action_reconcile_active \
    zte_recovery_inhibit_write \
    zte_recovery_inhibit_clear zte_schedule_pre_departure
do
    assert_file_contains "$daemon" "$function"
done
assert_file_contains "$daemon" 'sleep.*zte_backoff_interval'
assert_file_contains "$daemon" 'zte_validate_interface.*interface'
assert_file_contains "$daemon" 'zte_validate_netdev.*netdev'
assert_file_contains "$daemon" 'init_state'
assert_file_contains "$daemon" '^[[:space:]]*state=credentials_missing$'
assert_file_contains "$daemon" '^[[:space:]]*reason=device_credentials_required$'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/session.sh" 'goformId=LOGIN'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh" 'multi_data=1'
assert_file_contains tests/fixtures/u25s/read_ok.json 'NR5G-SA'
assert_file_contains Makefile 'tests/test_session.sh'
assert_file_contains Makefile 'tests/test_credentials.sh'
assert_file_contains Makefile 'tests/test_schedule.sh'
assert_file_contains Makefile 'tests/test_adapter.sh'
assert_file_contains Makefile 'tests/test_u25s_simulator.sh'
assert_file_contains Makefile 'tests/test_actions.sh'
assert_file_contains Makefile 'tests/test_action_executor.sh'
assert_file_contains Makefile 'tests/test_daemon_actions.sh'
assert_file_contains Makefile 'tests/test_power_adapter.sh'
assert_file_contains Makefile 'tests/test_event_log.sh'
assert_file_contains Makefile 'tests/test_recovery_inhibit.sh'
assert_file_contains Makefile 'tests/test_recovery_guard.sh'
assert_file_contains Makefile 'tests/test_runtime_stability.sh'
assert_file_contains \
    "$backend/files/usr/lib/zte-usb-wifi-manager/actions.sh" \
    '^zte_action_enqueue\(\) \{$'
assert_file_contains "$daemon" 'action-executor\.sh'
assert_file_contains "$daemon" 'zte_execute_switch_sim'
assert_file_contains \
    "$backend/files/usr/lib/zte-usb-wifi-manager/action-executor.sh" \
    '^zte_execute_switch_sim\(\) \{$'
assert_file_contains \
    "$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh" \
    '^zte_adapter_action_payload_valid\(\) \{$'
assert_file_contains \
    "$backend/files/usr/lib/zte-usb-wifi-manager/power-adapter.sh" \
    '^zte_power_apply\(\) \{$'
assert_file_contains \
    "$backend/files/usr/lib/zte-usb-wifi-manager/event-log.sh" \
    '^zte_event_write\(\) \{$'
assert_file_contains \
    "$backend/files/usr/lib/zte-usb-wifi-manager/recovery-inhibit.sh" \
    '^zte_recovery_inhibit_write\(\) \{$'
assert_file_contains docs/design/testing-strategy.md '^## L2：U25S API 模拟器（已实现）$'

# Execute the daemon orchestration functions with side-effect-free stubs.
lib="$backend/files/usr/lib/zte-usb-wifi-manager"
. "$lib/json.sh"
. "$lib/snapshot.sh"
extract_daemon_function() {
    sed -n "/^$1() {$/,/^}$/p" "$daemon"
}
eval "$(extract_daemon_function poll_once)"
eval "$(extract_daemon_function calculate_policy)"
eval "$(extract_daemon_function main)"
eval "$(extract_daemon_function apply_policy_action)"
eval "$(extract_daemon_function record_event)"
eval "$(extract_daemon_function record_state_change)"

work=/tmp/zte-test-daemon.$$
mkdir -p "$work"
fetch_count=$work/fetch-count
status_log=$work/status
policy_power_log=$work/policy-power
printf 0 >"$fetch_count"
: >"$status_log"

# Exercise the production atomic writer against an isolated status path.
eval "$(extract_daemon_function write_status)"
STATE_DIR=$work/real-state
STATUS_FILE=$STATE_DIR/status.json
atomic_move_log=$work/atomic-moves
: >"$atomic_move_log"
# Injected into the eval-defined production write_status function.
# shellcheck disable=SC2329
mv() {
    if [ "$#" -ne 2 ] || [ ! -f "$1" ]; then
        return 1
    fi
    printf '%s|%s|%s\n' "$1" "$2" "$(cat "$1")" >>"$atomic_move_log"
    command mv "$1" "$2"
}
write_status '{"generation":1}'
write_status '{"generation":2}'
unset -f mv
assert_eq \
    "$STATUS_FILE.tmp.$$|$STATUS_FILE|{\"generation\":1}
$STATUS_FILE.tmp.$$|$STATUS_FILE|{\"generation\":2}" \
    "$(cat "$atomic_move_log")" \
    'write_status must publish complete temporary files through mv'
assert_eq '{"generation":2}' "$(cat "$STATUS_FILE")" \
    'write_status must atomically replace the previous snapshot'
assert_eq 600 "$(test_file_mode "$STATUS_FILE")" \
    'write_status must publish a mode-600 snapshot'
if find "$STATE_DIR" -name 'status.json.tmp.*' -print | grep -q .; then
    fail 'write_status left a temporary snapshot behind'
else
    pass
fi

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
manual_full=0
schedule_enabled=0
schedule_weekdays='1 2 3 4 5'
schedule_departure=18:00
schedule_lead=90
power_backend=unconfigured
last_power_action=''
failures=0
# Read by the eval-defined production poll_once function.
# shellcheck disable=SC2034
last_device_json=''
# Read by the eval-defined production record_state_change function.
# shellcheck disable=SC2034
last_logged_state=''
# Read by the eval-defined production record_event function.
# shellcheck disable=SC2034
EVENT_LOG_MAX_BYTES=524288
event_call_log=$work/event-calls
: >"$event_call_log"
zte_event_write() {
    printf '%s|%s|%s|%s|%s|%s\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" >>"$event_call_log"
}

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
zte_policy_decide() {
    printf '%s\n' "$8" >"$policy_power_log"
    printf '%s\n' 'DISABLED:KEEP'
}
schedule_pre_departure_now() { printf '0\n'; }
date() { printf '%s\n' 1722345678; }
write_status() { printf '%s\n' "$1" >>"$status_log"; }

# Anonymous status firmware must be polled even when no credential file exists.
anonymous_password_log=$work/anonymous-password
zte_read_password() { return 1; }
zte_adapter_fetch() {
    printf '%s' "$2" >"$anonymous_password_log"
    printf '%s\n' "$dev1"
}
zte_adapter_normalize() { printf '%s\n' "$1"; }
poll_once
assert_eq '' "$(cat "$anonymous_password_log")"
assert_eq \
    "$(zte_snapshot_compose ok '' "$dev1" "$net" DISABLED KEEP 0 1722345678)" \
    "$(sed -n '1p' "$status_log")"

# Adapter status 2 means the endpoint is reachable but needs a password.
: >"$status_log"
last_device_json=''
last_logged_state=''
failures=0
zte_adapter_fetch() { return 2; }
poll_once
assert_eq \
    "$(zte_snapshot_compose credentials_missing device_credentials_required '' \
        "$net" DISABLED KEEP 0 1722345678)" \
    "$(sed -n '1p' "$status_log")"

# Restore the configured-credential sequence used by the degradation tests.
: >"$status_log"
: >"$event_call_log"
printf 0 >"$fetch_count"
# Read by the eval-defined production poll_once function.
# shellcheck disable=SC2034
last_device_json=''
# Read by the eval-defined production record_state_change function.
# shellcheck disable=SC2034
last_logged_state=''
failures=0
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

poll_once
assert_eq OFF "$(cat "$policy_power_log")" \
    'daemon must map the observed charging flag to current power state'
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
assert_eq \
    "$work/real-state|info|state|state_ok|1722345678|524288
$work/real-state|warn|state|state_degraded|1722345678|524288
$work/real-state|info|state|state_ok|1722345678|524288" \
    "$(cat "$event_call_log")" \
    'daemon must log state transitions without logging every poll'

fail_safe_policy_log=$work/fail-safe-policy
# Invoked by the eval-defined production calculate_policy function.
# shellcheck disable=SC2329
zte_policy_decide() {
    printf '%s|%s|%s|%s\n' "$1" "$2" "$5" "$8" \
        >"$fail_safe_policy_log"
    printf '%s\n' 'FAIL_SAFE_ON:ON'
}
battery_enabled=1
# Read by the eval-defined production calculate_policy function.
# shellcheck disable=SC2034
health=fail_safe
# Read by the eval-defined production calculate_policy function.
# shellcheck disable=SC2034
ok=0
# Read by the eval-defined production calculate_policy function.
# shellcheck disable=SC2034
device_json=''
calculate_policy
assert_eq '1|1|0|UNKNOWN' "$(cat "$fail_safe_policy_log")"
# Assigned by the eval-defined production calculate_policy function.
# shellcheck disable=SC2154
assert_eq FAIL_SAFE_ON "$policy_state"
# Assigned by the eval-defined production calculate_policy function.
# shellcheck disable=SC2154
assert_eq ON "$power_action"
# Read by the eval-defined production calculate_policy function.
# shellcheck disable=SC2034
health=credentials_missing
calculate_policy
assert_eq '1|1|0|UNKNOWN' "$(cat "$fail_safe_policy_log")"
assert_eq FAIL_SAFE_ON "$policy_state"
assert_eq ON "$power_action"

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
. "$lib/power-adapter.sh"
. "$lib/recovery-inhibit.sh"
. "$lib/schedule.sh"
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
        manual_full) manual_full=0 ;;
        schedule_enabled) schedule_enabled=0 ;;
        schedule_weekdays) schedule_weekdays='1 2 3 4 5' ;;
        schedule_departure) schedule_departure=18:00 ;;
        schedule_lead) schedule_lead=90 ;;
        power_backend) power_backend=$_zte_test_power_backend ;;
    esac
}
logger() { :; }
_zte_test_interface='bad/name'
_zte_test_netdev=eth2
_zte_test_power_backend=unconfigured
assert_failure load_config
_zte_test_interface=usbwan
_zte_test_netdev='bad netdev'
assert_failure load_config
_zte_test_interface=usbwan
_zte_test_netdev=eth2
_zte_test_power_backend=invalid
assert_failure load_config
_zte_test_power_backend=unconfigured
assert_success load_config

power_call_log=$work/power-calls
: >"$power_call_log"
zte_power_apply() {
    printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >>"$power_call_log"
}
STATE_DIR=$work/power-state
mkdir -p "$STATE_DIR"
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
power_backend=unconfigured
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
last_power_action=''
apply_policy_action MAINTAIN_CHARGING ON
assert_eq '' "$(cat "$power_call_log")"
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
power_backend=dry-run
apply_policy_action MAINTAIN_CHARGING ON
apply_policy_action MAINTAIN_CHARGING ON
apply_policy_action MAINTAIN_BATTERY OFF
assert_eq \
    "dry-run|ON|battery_low|$STATE_DIR/power-decision.json
dry-run|OFF|battery_high|$STATE_DIR/power-decision.json" \
    "$(cat "$power_call_log")"
RECOVERY_INHIBIT_FILE=$STATE_DIR/inhibit-recovery
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
RECOVERY_INHIBIT_SECONDS=600
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
power_backend=mock
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
last_power_action=''
apply_policy_action MAINTAIN_BATTERY OFF
assert_success zte_recovery_inhibit_active \
    "$RECOVERY_INHIBIT_FILE" 1722346000
apply_policy_action MAINTAIN_CHARGING ON
assert_failure test -e "$RECOVERY_INHIBIT_FILE"

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
: >"$event_call_log"
STATE_DIR=$work/real-state
# Read by the eval-defined production main function.
# shellcheck disable=SC2034
ACTION_RESULT_MAX_COUNT=50
process_actions() { :; }
zte_action_reconcile_active() { :; }
zte_action_recover_running() { :; }
prune_call_log=$work/prune-calls
: >"$prune_call_log"
zte_action_prune_results() {
    printf '%s|%s\n' "$1" "$2" >>"$prune_call_log"
}
main
assert_eq \
    "$work/real-state|info|service|service_started|1722345678|524288" \
    "$(sed -n '1p' "$event_call_log")"
assert_eq "$work/real-state|50" "$(cat "$prune_call_log")"
assert_eq '60
120
30' "$(cat "$sleep_log")"

rm -rf "$work"
finish
