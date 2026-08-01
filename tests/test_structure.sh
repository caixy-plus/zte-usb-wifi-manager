#!/bin/sh
# Production functions are intentionally extracted and defined through eval
# below, which ShellCheck 0.9 cannot model.
# shellcheck disable=SC2218,SC2317,SC2329
set -eu

TEST_NAME=test_structure
. ./tests/testlib.sh

backend=package/zte-usb-wifi-manager
luci='luci-app-zte-usb-wifi-manager'
config="$backend/files/etc/config/zte-usb-wifi-manager"
daemon="$backend/files/usr/sbin/zte-usb-wifi-managerd"

if grep -Eq "^config (battery 'policy'|schedule 'work')$" "$config"; then
    fail 'default config must not expose retired battery automation'
else
    pass
fi
poll_once_source=$(sed -n '/^poll_once() {$/,/^}$/p' "$daemon")
case $poll_once_source in
    *zte_policy_decide*|*apply_policy_action*)
        fail 'polling must not execute battery-driven USB power actions'
        ;;
    *) pass ;;
esac
case $poll_once_source in
    *'collect_private_clients '*) pass ;;
    *) fail 'polling must collect the bounded private client collection' ;;
esac
case $poll_once_source in
    *'"$raw_json" "$clients_json"'*) pass ;;
    *) fail 'polling must normalize the private client collection' ;;
esac

assert_file_contains "$backend/Makefile" '^PKG_NAME:=zte-usb-wifi-manager$'
assert_file_contains "$backend/Makefile" '^PKG_VERSION:=0\.1\.0_rc1$'
assert_file_contains "$backend/Makefile" '^PKG_RELEASE:=16$'
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
    '^define Package/zte-usb-wifi-manager/prerm$'
assert_file_contains "$backend/Makefile" \
    '/usr/libexec/zte-usb-power-restore \|\| exit 1'
assert_file_contains "$backend/Makefile" \
    '/etc/init.d/zte-usb-wifi-manager running'
assert_file_contains "$backend/Makefile" 'kill -0'
assert_file_contains "$backend/Makefile" \
    '^define Package/zte-usb-wifi-manager/postrm$'
assert_file_contains "$backend/Makefile" \
    'inhibit-recovery'
assert_file_contains "$backend/Makefile" \
    'actions/power-transition'
assert_file_contains "$backend/Makefile" \
    'rm -rf /var/run/zte-usb-wifi-manager'
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option write_enabled '0'"
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option sim_switch_enabled '0'"
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option cellular_write_enabled '0'"
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option wifi_write_enabled '0'"
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option traffic_write_enabled '0'"
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option sms_write_enabled '0'"
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" \
    "option off_probe_interval '900'"
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" \
    "option probe_settle_seconds '15'"
init_script="$backend/files/etc/init.d/zte-usb-wifi-manager"
assert_file_contains "$init_script" '^USE_PROCD=1$'
assert_file_contains "$init_script" \
    'procd_open_instance manager'
assert_file_contains "$init_script" \
    'procd_open_instance recovery-coordinator'
assert_file_contains "$init_script" \
    'zte-usb-recovery-coordinatord run'

# start_service must gate both procd instances on persistent SIM recovery
# artifacts. Exercise behavior rather than accepting matching source strings.
init_gate_root=$(mktemp -d /tmp/zte-test-init-gate.XXXXXX)
init_gate_log=$init_gate_root/procd-instances
init_gate_state=$init_gate_root/sim-calibration
init_gate_lock=$init_gate_root/sim-calibration.lock
init_power_state=$init_gate_root/power-calibration
init_power_lock=$init_gate_root/power-calibration.lock
run_gated_start() {
    (
        ZTE_SIM_CALIBRATION_STATE_DIR=$init_gate_state
        ZTE_SIM_CALIBRATION_LOCK_DIR=$init_gate_lock
        ZTE_POWER_CALIBRATION_STATE_DIR=$init_power_state
        ZTE_POWER_CALIBRATION_LOCK_DIR=$init_power_lock
        export ZTE_SIM_CALIBRATION_STATE_DIR
        export ZTE_SIM_CALIBRATION_LOCK_DIR
        export ZTE_POWER_CALIBRATION_STATE_DIR
        export ZTE_POWER_CALIBRATION_LOCK_DIR
        procd_open_instance() {
            printf '%s\n' "$1" >>"$init_gate_log"
        }
        procd_set_param() { :; }
        procd_close_instance() { :; }
        procd_add_reload_trigger() { :; }
        # shellcheck source=/dev/null
        . "$init_script"
        start_service
    )
}

: >"$init_gate_log"
assert_success run_gated_start
assert_eq 'manager
recovery-coordinator' "$(cat "$init_gate_log")"

mkdir "$init_gate_state"
: >"$init_gate_log"
assert_failure run_gated_start
assert_eq '' "$(cat "$init_gate_log")"
rmdir "$init_gate_state"

mkdir "$init_gate_lock"
: >"$init_gate_log"
assert_failure run_gated_start
assert_eq '' "$(cat "$init_gate_log")"
rmdir "$init_gate_lock"

ln -s "$init_gate_root/missing-state-target" "$init_gate_state"
: >"$init_gate_log"
assert_failure run_gated_start
assert_eq '' "$(cat "$init_gate_log")"
rm "$init_gate_state"

ln -s "$init_gate_root/missing-lock-target" "$init_gate_lock"
: >"$init_gate_log"
assert_failure run_gated_start
assert_eq '' "$(cat "$init_gate_log")"
rm "$init_gate_lock"

mkdir "$init_power_lock"
: >"$init_gate_log"
assert_failure run_gated_start
assert_eq '' "$(cat "$init_gate_log")"
ZTE_POWER_CALIBRATION_BYPASS_LOCK=1
export ZTE_POWER_CALIBRATION_BYPASS_LOCK
: >"$init_gate_log"
assert_success run_gated_start
assert_eq 'manager
recovery-coordinator' "$(cat "$init_gate_log")"
unset ZTE_POWER_CALIBRATION_BYPASS_LOCK
rmdir "$init_power_lock"

mkdir "$init_power_state"
: >"$init_power_state/inhibit-recovery"
: >"$init_gate_log"
assert_failure run_gated_start
assert_eq '' "$(cat "$init_gate_log")"
rm -rf "$init_power_state"
rm -rf "$init_gate_root"
assert_file_contains "$backend/files/usr/libexec/rpcd/zte_usb_wifi" '"status"'
assert_file_contains "$backend/files/usr/libexec/rpcd/zte_usb_wifi" '"capabilities"'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh" '^ZTE_CAP_SIM_SWITCH=0$'
sim_calibration_tool="$backend/files/usr/libexec/zte-u25s-sim-calibrate"
assert_success test -x "$sim_calibration_tool"
assert_file_contains "$sim_calibration_tool" \
    'ZTE_SIM_CALIBRATION_STATE_DIR=.*:-/etc/zte-usb-wifi-manager/sim-calibration}'
assert_file_contains "$sim_calibration_tool" \
    'ZTE_SIM_CALIBRATION_LOCK_DIR=.*:-/etc/zte-usb-wifi-manager/sim-calibration\.lock}'
assert_file_contains "$sim_calibration_tool" \
    'ZTE_SIM_CALIBRATION_SYNC=.*:-/bin/sync}'

menu="$luci/root/usr/share/luci/menu.d/luci-app-zte-usb-wifi-manager.json"
assert_file_contains "$luci/Makefile" '^PKG_VERSION:=0\.1\.0_rc1$'
assert_file_contains "$luci/Makefile" '^PKG_RELEASE:=5$'
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
for tab in overview network wifi clients traffic sms device diagnostics logs; do
    assert_file_contains "$view" "id: '$tab'"
done
assert_file_contains "$view" '设备写接口尚未完成实机校准'
assert_file_contains "$view" 'status\.device'
assert_file_contains "$view" 'is_default_route'
assert_file_contains "$view" 'battery'
assert_file_contains "$view" 'USB 断电会中断数据连接，仅用于故障恢复'
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
assert_file_contains README.md 'OpenWrt 25\.12\.5.*backend r8 / LuCI r3 通过'
assert_file_contains README.md 'OpenWrt 24\.10\.7.*backend r8 / LuCI r3 通过'
assert_file_contains README.md '当前 backend r15 / LuCI r4 已完成本地检查'
assert_file_contains README.md '已发布的 r15 / LuCI r4 通过了双 SDK 与 QEMU 复验'
assert_file_contains README.md 'LuCI 已采用设备控制台导航'
assert_file_contains README.md 'SIM 类型与电池扩展状态'
assert_file_contains README.md '短信总数与脱敏事件日志'
assert_file_contains README.md '固件版本、实时/本次/本月流量和套餐状态已按目标固件契约接入只读展示'
assert_file_contains README.md 'hardware Power Adapter'
# Match literal Markdown backticks.
# shellcheck disable=SC2016
assert_file_contains README.md '默认仍以 `calibrated=0` 锁定'
assert_file_contains README.md 'zte-usb-power-calibrate'
assert_file_contains README.md '^### 备用 U25S SIM 写接口校准$'
assert_file_contains README.md \
    '/usr/libexec/zte-u25s-sim-calibrate probe'
assert_file_contains README.md \
    '/usr/libexec/zte-u25s-sim-calibrate execute I_AM_ON_SPARE_U25S <不同目标>'
assert_file_contains README.md \
    '/usr/libexec/zte-u25s-sim-calibrate recover'
assert_file_contains README.md '只能在备用 U25S'
assert_file_contains README.md \
    'r14 已修复实机满电状态枚举'
assert_file_contains README.md \
    'docs/validation/2026-07-31-r8-r3-qemu\.md'
assert_file_contains README.md \
    'docs/validation/2026-07-31-r15-r4-qemu\.md'
assert_file_contains docs/validation/2026-07-31-r15-r4-qemu.md \
    '30639262368'
assert_file_contains docs/validation/2026-07-31-r15-r4-qemu.md \
    '30640806789'
assert_file_contains docs/validation/2026-07-31-r15-r4-qemu.md \
    'r14/r3→r15/r4'
assert_file_contains README.md \
    'releases/tag/v0\.1\.0-rc1-r15'
assert_file_contains README.md \
    'docs/validation/2026-08-01-r15-r4-formal-deployment\.md'
assert_file_contains docs/validation/2026-08-01-r15-r4-formal-deployment.md \
    '^# r15/r4 目标路由器正式部署验证（2026-08-01）$'
assert_file_contains docs/validation/2026-08-01-r15-r4-formal-deployment.md \
    'write_enabled=0'
assert_file_contains docs/validation/2026-08-01-r15-r4-formal-deployment.md \
    '重新连接返回认证失败'
assert_file_contains docs/validation/2026-07-31-r8-r3-qemu.md \
    'probe'
assert_file_contains docs/validation/2026-07-31-r8-r3-qemu.md \
    '失败码'
assert_file_contains README.md 'zte-usb-soak'
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

assert_file_contains "$daemon" '^set -e$'
for library in \
    json.sh credentials.sh session.sh snapshot.sh netifd-adapter.sh \
    power-adapter.sh event-log.sh \
    actions.sh recovery-inhibit.sh recovery-adapter.sh schedule.sh
do
    assert_file_contains "$daemon" "$library"
done
for function in \
    zte_adapter_fetch zte_failures_next zte_snapshot_compose zte_power_apply \
    zte_event_write zte_action_claim zte_action_finish \
    zte_action_prune_results zte_action_reconcile_active \
    zte_recovery_inhibit_write \
    zte_recovery_inhibit_clear zte_recovery_prepare_off \
    zte_recovery_finish_on zte_recovery_reconcile \
    zte_schedule_pre_departure
do
    assert_file_contains "$daemon" "$function"
done
assert_file_contains "$daemon" 'sleep.*zte_backoff_interval'
assert_file_contains "$daemon" 'zte_validate_interface.*interface'
assert_file_contains "$daemon" 'zte_validate_netdev.*netdev'
assert_file_contains "$daemon" 'init_state'
assert_file_contains "$daemon" '^[[:space:]]*state=credentials_missing$'
assert_file_contains "$daemon" '^[[:space:]]*reason=device_credentials_required$'
assert_file_contains "$daemon" '^[[:space:]]*state=authentication_failed$'
assert_file_contains "$daemon" '^[[:space:]]*reason=device_authentication_failed$'
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
assert_file_contains Makefile 'tests/test_recovery_adapter.sh'
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
assert_file_contains \
    "$backend/files/usr/lib/zte-usb-wifi-manager/recovery-adapter.sh" \
    '^zte_recovery_prepare_off\(\) \{$'
assert_file_contains \
    "$backend/files/etc/config/zte-usb-wifi-manager" \
    "option control_path 'auto'"
assert_file_contains "$backend/Makefile" \
    'cudy,tr3000-v1-ubootmod'
assert_file_contains "$backend/Makefile" \
    'zte-usb-wifi-manager\.usb\.control_path=auto'
# Match the literal shell variable expression in the production daemon.
# shellcheck disable=SC2016
assert_file_contains "$daemon" '^PID_FILE=\$STATE_DIR/manager\.pid$'
assert_file_contains \
    "$backend/files/usr/sbin/zte-usb-recovery-coordinatord" \
    'coordinator\.pid'
assert_file_contains docs/design/testing-strategy.md '^## L2：U25S API 模拟器（已实现）$'

# Execute the daemon orchestration functions with side-effect-free stubs.
lib="$backend/files/usr/lib/zte-usb-wifi-manager"
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/power-adapter.sh"
. "$lib/snapshot.sh"
extract_daemon_function() {
    sed -n "/^$1() {$/,/^}$/p" "$daemon"
}
eval "$(extract_daemon_function poll_once)"
eval "$(extract_daemon_function collect_private_clients)"
eval "$(extract_daemon_function calculate_policy)"
eval "$(extract_daemon_function read_current_power_state)"
eval "$(extract_daemon_function main)"
eval "$(extract_daemon_function write_power_outcome_record)"
eval "$(extract_daemon_function apply_policy_action)"
eval "$(extract_daemon_function power_inhibit_expiry)"
eval "$(extract_daemon_function restore_power_on)"
eval "$(extract_daemon_function shutdown_manager)"
eval "$(extract_daemon_function write_pid_file)"
eval "$(extract_daemon_function remove_pid_file)"
eval "$(extract_daemon_function record_event)"
eval "$(extract_daemon_function record_state_change)"
handle_planned_power_off() { return 1; }

work=/tmp/zte-test-daemon.$$
mkdir -p "$work"
fetch_count=$work/fetch-count
status_log=$work/status
policy_power_log=$work/policy-power
printf 0 >"$fetch_count"
: >"$status_log"
: >"$policy_power_log"

# Exercise the production atomic writer against an isolated status path.
eval "$(extract_daemon_function write_status)"
STATE_DIR=$work/real-state
PID_FILE=$STATE_DIR/manager.pid
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

power_backend=unconfigured
power_calibrated=0
power_control_path=auto
assert_eq UNKNOWN "$(read_current_power_state)"
power_backend=hardware
assert_eq UNKNOWN "$(read_current_power_state)"
power_calibrated=1
zte_power_detect_board() { printf '%s\n' cudy,tr3000-v1; }
zte_power_resolve_control_path() {
    printf '%s\n' /sys/class/gpio/modem_power/value
}
zte_power_observed_state() { printf '%s\n' ON; }
assert_eq ON "$(read_current_power_state)"
power_backend=dry-run
power_calibrated=0
assert_eq ON "$(read_current_power_state)"
zte_power_observed_state() { printf '%s\n' UNKNOWN; }
assert_eq UNKNOWN "$(read_current_power_state)"

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

# Private collections must distinguish missing credentials, rejected
# credentials, cooldown, transient read failures, and success. In particular,
# an invalid saved password must not be retried on every poll because the U25S
# firmware applies a login lockout.
PRIVATE_AUTH_BACKOFF_SECONDS=900
private_auth_retry_after=0
client_fetch_count=$work/client-fetch-count
printf 0 >"$client_fetch_count"
zte_adapter_clients_unavailable_json() {
    printf '{"available":false,"reason":"%s","items":[]}\n' "$1"
}
zte_adapter_fetch_clients() {
    n=$(cat "$client_fetch_count")
    printf '%s' "$((n + 1))" >"$client_fetch_count"
    case $2 in
        accepted) printf '%s\n' '{"available":true,"items":[]}' ;;
        rejected) return 3 ;;
        *) return 1 ;;
    esac
}
collect_private_clients 1722345678 ''
assert_eq '{"available":false,"reason":"credentials_missing","items":[]}' \
    "$clients_json"
assert_eq 0 "$(cat "$client_fetch_count")"
collect_private_clients 1722345678 accepted
assert_eq '{"available":true,"items":[]}' "$clients_json"
assert_eq 1 "$(cat "$client_fetch_count")"
collect_private_clients 1722345678 rejected
assert_eq '{"available":false,"reason":"authentication_failed","items":[]}' \
    "$clients_json"
assert_eq 1722346578 "$private_auth_retry_after"
assert_eq 2 "$(cat "$client_fetch_count")"
collect_private_clients 1722345679 rejected
assert_eq '{"available":false,"reason":"authentication_backoff","items":[]}' \
    "$clients_json"
assert_eq 2 "$(cat "$client_fetch_count")"
private_auth_retry_after=0
collect_private_clients 1722345678 transient
assert_eq '{"available":false,"reason":"read_failed","items":[]}' \
    "$clients_json"
assert_eq 3 "$(cat "$client_fetch_count")"

zte_read_password() { printf '%s\n' secret; }
zte_adapter_fetch_clients() { return 1; }
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
collect_power_snapshot() { power_json=''; }
zte_is_uint() {
    case ${1-} in ''|*[!0-9]*) return 1 ;; esac
}
zte_policy_decide() {
    printf '%s\n' "$8" >"$policy_power_log"
    printf '%s\n' 'DISABLED:KEEP'
}
schedule_pre_departure_now() { printf '0\n'; }
read_current_power_state() { printf 'ON\n'; }
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
    "$(zte_snapshot_compose ok '' "$dev1" "$net" retired none 0 1722345678)" \
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
        "$net" retired none 0 1722345678)" \
    "$(sed -n '1p' "$status_log")"

# Adapter status 3 means LOGIN was attempted and rejected. It must remain a
# distinct, backoff-counted state instead of looking like a generic outage.
: >"$status_log"
last_device_json=''
last_logged_state=''
failures=0
zte_read_password() { printf '%s\n' secret; }
zte_adapter_fetch() { return 3; }
poll_once
assert_eq \
    "$(zte_snapshot_compose authentication_failed device_authentication_failed '' \
        "$net" retired none 1 1722345678)" \
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
assert_eq '' "$(cat "$policy_power_log")" \
    'daemon polling must not evaluate battery-driven USB power actions'
poll_once
poll_once
poll_once
assert_eq \
    "$(zte_snapshot_compose ok '' "$dev1" "$net" retired none 0 1722345678)" \
    "$(sed -n '1p' "$status_log")"
assert_eq \
    "$(zte_snapshot_compose degraded device_read_failed "$dev1" "$net" retired none 1 1722345678)" \
    "$(sed -n '2p' "$status_log")"
assert_eq \
    "$(zte_snapshot_compose degraded device_read_failed "$dev1" "$net" retired none 2 1722345678)" \
    "$(sed -n '3p' "$status_log")"
assert_eq \
    "$(zte_snapshot_compose ok '' "$dev2" "$net" retired none 0 1722345678)" \
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

# Production power collection publishes controller/supply readback, the last
# execution record, and recovery coordination state in the cached snapshot.
eval "$(extract_daemon_function collect_power_snapshot)"
previous_state_dir=$STATE_DIR
power_snapshot_state=$work/power-snapshot-state
mkdir -p "$power_snapshot_state"
printf '%s\n' \
    '{"backend":"hardware","action":"ON","executed":true,"reason":"battery_low","outcome":"succeeded","updated":1722345678,"profile":"hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value"}' \
    >"$power_snapshot_state/power-decision.json"
STATE_DIR=$power_snapshot_state
RECOVERY_INHIBIT_FILE=$STATE_DIR/inhibit-recovery
RECOVERY_SERVICE=/etc/init.d/zte-usb-recover
power_backend=hardware
power_calibrated=1
write_enabled=1
power_control_path=auto
zte_power_detect_board() { printf '%s\n' cudy,tr3000-v1; }
zte_power_resolve_control_path() {
    printf '%s\n' /sys/class/gpio/modem_power/value
}
zte_power_hardware_read() { printf '%s\n' 1; }
zte_power_supply_read() { printf '%s\n' 1; }
zte_recovery_inhibit_active() { return 0; }
zte_recovery_service_available() { return 0; }
zte_recovery_service_running() { return 0; }
collect_power_snapshot
assert_eq \
    '{"backend":"hardware","calibrated":true,"write_enabled":true,"control_path":"/sys/class/gpio/modem_power/value","control_state":1,"supply_state":1,"observed":"ON","execution":{"available":true,"reason":"ready"},"decision":{"backend":"hardware","action":"ON","executed":true,"reason":"battery_low","outcome":"succeeded","updated":1722345678,"profile":"hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value"},"recovery":{"inhibited":true,"service_available":true,"service_running":true}}' \
    "$power_json"
power_backend=unconfigured
power_calibrated=0
write_enabled=0
collect_power_snapshot
assert_eq \
    '{"backend":"unconfigured","calibrated":false,"write_enabled":false,"control_path":null,"control_state":null,"supply_state":null,"observed":"UNKNOWN","execution":{"available":false,"reason":"backend_unconfigured"},"decision":null,"recovery":{"inhibited":true,"service_available":true,"service_running":true}}' \
    "$power_json"
STATE_DIR=$previous_state_dir

# Production load_config rejects unsafe names without terminating the shell.
. "$lib/validation.sh"
. "$lib/power-adapter.sh"
. "$lib/recovery-inhibit.sh"
. "$lib/recovery-adapter.sh"
. "$lib/schedule.sh"
eval "$(extract_daemon_function load_config)"
config_load() { :; }
# Assignments are read by the eval-defined production load_config function.
# shellcheck disable=SC2034
config_get() {
    case $1 in
        enabled) enabled=1 ;;
        write_enabled) write_enabled=$_zte_test_write_enabled ;;
        sim_switch_enabled) sim_switch_enabled=$_zte_test_action_flag ;;
        cellular_write_enabled) cellular_write_enabled=0 ;;
        wifi_write_enabled) wifi_write_enabled=0 ;;
        traffic_write_enabled) traffic_write_enabled=0 ;;
        sms_write_enabled) sms_write_enabled=0 ;;
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
        power_control_path) power_control_path=$_zte_test_power_control_path ;;
        power_calibrated) power_calibrated=$_zte_test_power_calibrated ;;
        power_off_probe_interval)
            power_off_probe_interval=$_zte_test_power_off_probe_interval
            ;;
        power_probe_settle_seconds)
            power_probe_settle_seconds=$_zte_test_power_probe_settle_seconds
            ;;
    esac
}
logger() { :; }
_zte_test_interface='bad/name'
_zte_test_netdev=eth2
_zte_test_power_backend=unconfigured
_zte_test_write_enabled=0
_zte_test_action_flag=0
_zte_test_power_control_path=/sys/class/gpio/modem_power/value
_zte_test_power_calibrated=0
_zte_test_power_off_probe_interval=900
_zte_test_power_probe_settle_seconds=15
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
_zte_test_action_flag=2
assert_failure load_config
_zte_test_action_flag=0
_zte_test_write_enabled=2
assert_failure load_config
_zte_test_write_enabled=0
_zte_test_power_calibrated=2
assert_failure load_config
_zte_test_power_calibrated=0
_zte_test_power_control_path=/tmp/modem_power
assert_failure load_config
_zte_test_power_control_path=/sys/class/gpio/modem_power/value
assert_success load_config
_zte_test_power_off_probe_interval=59
assert_failure load_config
_zte_test_power_off_probe_interval=900
_zte_test_power_probe_settle_seconds=121
assert_failure load_config
_zte_test_power_probe_settle_seconds=15
assert_success load_config

power_call_log=$work/power-calls
: >"$power_call_log"
power_record_log=$work/power-records
: >"$power_record_log"
hardware_io_log=$work/hardware-io
: >"$hardware_io_log"
_zte_test_power_apply_failure=0
zte_power_apply() {
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" \
        >>"$power_call_log"
    case $_zte_test_power_apply_failure in
        0) return 0 ;;
        2)
            _zte_test_profile=$(zte_power_profile_id \
                "$1" "$6" "$8" "$7" "$5") || return 1
            printf \
                '{"backend":"%s","action":"%s","executed":true,"reason":"%s","outcome":"succeeded","updated":%s,"profile":"%s"}\n' \
                "$1" "$2" "$3" "$9" "$_zte_test_profile"
            return 2
            ;;
        *) return 1 ;;
    esac
}
zte_power_hardware_apply() {
    printf '%s|%s\n' "$1" "$2" >>"$hardware_io_log"
    [ "$_zte_test_power_apply_failure" = 0 ]
}
_zte_test_power_record_failure=0
zte_power_write_record() {
    printf '%s|%s\n' "$1" "$2" >>"$power_record_log"
    [ "$_zte_test_power_record_failure" = 0 ]
}
_zte_test_board='cudy,tr3000-v1'
zte_power_detect_board() { printf '%s\n' "$_zte_test_board"; }
_zte_test_action_active=0
zte_action_has_active() { [ "$_zte_test_action_active" = 1 ]; }
_zte_test_power_transition=0
zte_power_transition_claim() {
    [ "$_zte_test_power_transition" = 0 ] || return 1
    [ "$_zte_test_action_active" = 0 ] || return 1
    _zte_test_power_transition=1
}
zte_power_transition_active() {
    [ "$_zte_test_power_transition" = 1 ]
}
zte_power_transition_release() {
    _zte_test_power_transition=0
}
_zte_test_recovery_available=1
_zte_test_recovery_running=1
_zte_test_recovery_control_failure=0
zte_recovery_service_available() {
    [ "$_zte_test_recovery_available" = 1 ]
}
zte_recovery_service_running() {
    [ "$_zte_test_recovery_running" = 1 ]
}
recovery_service_calls=$work/recovery-service-calls
: >"$recovery_service_calls"
zte_recovery_service_control() {
    printf '%s:%s\n' "$1" "$2" >>"$recovery_service_calls"
    [ "$_zte_test_recovery_control_failure" = 0 ] || return 1
    case $2 in
        start) _zte_test_recovery_running=1 ;;
        stop) _zte_test_recovery_running=0 ;;
    esac
}
STATE_DIR=$work/power-state
mkdir -p "$STATE_DIR"
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
power_backend=unconfigured
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
write_enabled=0
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
power_control_path=/sys/class/gpio/modem_power/value
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
power_calibrated=0
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
power_off_probe_interval=900
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
power_probe_settle_seconds=15
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
planned_power_off=0
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
next_power_probe_at=0
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
network_json='{"up":true,"l3_device":"eth2","ipv4":"","gateway":"","is_default_route":false}'
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
    "dry-run|ON|battery_low|$STATE_DIR/power-decision.json|/sys/class/gpio/modem_power/value|0|cudy,tr3000-v1|0|1722345678
dry-run|OFF|battery_high|$STATE_DIR/power-decision.json|/sys/class/gpio/modem_power/value|0|cudy,tr3000-v1|0|1722345678" \
    "$(cat "$power_call_log")"
RECOVERY_INHIBIT_FILE=$STATE_DIR/inhibit-recovery
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
RECOVERY_SERVICE=/etc/init.d/zte-usb-recover
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

# Hardware never runs unless both global writes and the board profile are
# explicitly enabled. A successful OFF keeps the recovery service inhibited
# until a verified ON clears it.
: >"$power_call_log"
power_backend=hardware
last_power_action=''
write_enabled=0
power_calibrated=1
apply_policy_action MAINTAIN_BATTERY OFF
assert_eq '' "$(cat "$power_call_log")"
write_enabled=1
power_calibrated=0
apply_policy_action MAINTAIN_BATTERY OFF
assert_eq '' "$(cat "$power_call_log")"
power_calibrated=1
network_json='{"up":true,"l3_device":"eth2","ipv4":"","gateway":"","is_default_route":true}'
apply_policy_action MAINTAIN_BATTERY OFF
assert_eq '' "$(cat "$power_call_log")"
assert_eq 0 "$planned_power_off"
network_json='{"up":true,"l3_device":"eth2","ipv4":"","gateway":"","is_default_route":false}'
_zte_test_action_active=1
apply_policy_action MAINTAIN_BATTERY OFF
assert_eq '' "$(cat "$power_call_log")"
assert_failure test -e "$RECOVERY_INHIBIT_FILE"
_zte_test_action_active=0
apply_policy_action MAINTAIN_BATTERY OFF
assert_eq \
    "hardware|OFF|battery_high|$STATE_DIR/power-decision.json|/sys/class/gpio/modem_power/value|1|cudy,tr3000-v1|1|1722345678" \
    "$(cat "$power_call_log")"
assert_success zte_recovery_inhibit_active \
    "$RECOVERY_INHIBIT_FILE" 1722346000
assert_eq 1 "$planned_power_off"
assert_eq 1722346578 "$next_power_probe_at"
assert_eq 1 "$_zte_test_power_transition"
assert_eq '/etc/init.d/zte-usb-recover:stop' \
    "$(tail -n 1 "$recovery_service_calls")"
apply_policy_action FAIL_SAFE_ON ON
assert_failure test -e "$RECOVERY_INHIBIT_FILE"
assert_eq 0 "$planned_power_off"
assert_eq 0 "$next_power_probe_at"
assert_eq 0 "$_zte_test_power_transition"
assert_eq '/etc/init.d/zte-usb-recover:start' \
    "$(tail -n 1 "$recovery_service_calls")"

# The auto profile resolves the official ubootmod board to its fixed xHCI
# control boundary before any hardware write is attempted.
: >"$power_call_log"
last_power_action=''
_zte_test_board='cudy,tr3000-v1-ubootmod'
power_control_path=auto
apply_policy_action MAINTAIN_BATTERY OFF
assert_eq \
    "hardware|OFF|battery_high|$STATE_DIR/power-decision.json|/sys/bus/platform/drivers/xhci-mtk/11200000.usb|1|cudy,tr3000-v1-ubootmod|1|1722345678" \
    "$(cat "$power_call_log")"
apply_policy_action FAIL_SAFE_ON ON
_zte_test_board='cudy,tr3000-v1'
# Read by the eval-defined production apply_policy_action function.
# shellcheck disable=SC2034
power_control_path=/sys/class/gpio/modem_power/value

# Missing recovery coordination is a hard gate for real hardware writes.
: >"$power_call_log"
last_power_action=''
_zte_test_recovery_available=0
apply_policy_action MAINTAIN_BATTERY OFF
assert_eq '' "$(cat "$power_call_log")"
assert_failure test -e "$RECOVERY_INHIBIT_FILE"
_zte_test_recovery_available=1

# Recovery preparation failure happens before the hardware write and must
# replace any matching old success record with an explicit failed outcome.
: >"$power_record_log"
last_power_action=''
_zte_test_recovery_running=1
_zte_test_recovery_control_failure=1
assert_failure apply_policy_action MAINTAIN_BATTERY OFF
assert_eq 0 "$_zte_test_power_transition"
assert_eq \
    "$STATE_DIR/power-decision.json|{\"backend\":\"hardware\",\"action\":\"OFF\",\"executed\":false,\"reason\":\"battery_high\",\"outcome\":\"failed\",\"updated\":1722345678,\"profile\":\"hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value\"}" \
    "$(tail -n 1 "$power_record_log")"
_zte_test_recovery_control_failure=0

# If OFF might have reached hardware but verification fails, retain the timed
# inhibit instead of immediately starting a competing USB recovery cycle.
: >"$power_call_log"
last_power_action=''
_zte_test_power_apply_failure=1
assert_failure apply_policy_action MAINTAIN_BATTERY OFF
assert_success zte_recovery_inhibit_active \
    "$RECOVERY_INHIBIT_FILE" 1722346000
assert_eq \
    "hardware|OFF|battery_high|$STATE_DIR/power-decision.json|/sys/class/gpio/modem_power/value|1|cudy,tr3000-v1|1|1722345678" \
    "$(cat "$power_call_log")"
assert_eq \
    "$STATE_DIR/power-decision.json|{\"backend\":\"hardware\",\"action\":\"OFF\",\"executed\":false,\"reason\":\"battery_high\",\"outcome\":\"failed\",\"updated\":1722345678,\"profile\":\"hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value\"}" \
    "$(tail -n 1 "$power_record_log")"
assert_eq 1 "$planned_power_off"
assert_eq 1 "$_zte_test_power_transition"
_zte_test_power_apply_failure=0

# If even the fallback failure record cannot be written, clear the matching
# stale success record instead of continuing to publish it.
printf '%s\n' stale-success >"$STATE_DIR/power-decision.json"
_zte_test_power_record_failure=1
_zte_test_power_apply_failure=1
last_power_action=''
assert_failure apply_policy_action FAIL_SAFE_ON ON
assert_failure test -e "$STATE_DIR/power-decision.json"
_zte_test_power_record_failure=0
_zte_test_power_apply_failure=0

# A confirmed hardware transition remains truthful when only the first audit
# write fails. The daemon retries the same successful record and still performs
# OFF/ON recovery coordination.
apply_policy_action FAIL_SAFE_ON ON
: >"$power_call_log"
: >"$power_record_log"
last_power_action=''
_zte_test_power_apply_failure=2
assert_success apply_policy_action MAINTAIN_BATTERY OFF
assert_eq 1 "$planned_power_off"
assert_eq \
    "$STATE_DIR/power-decision.json|{\"backend\":\"hardware\",\"action\":\"OFF\",\"executed\":true,\"reason\":\"battery_high\",\"outcome\":\"succeeded\",\"updated\":1722345678,\"profile\":\"hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value\"}" \
    "$(tail -n 1 "$power_record_log")"
assert_success apply_policy_action FAIL_SAFE_ON ON
assert_eq 0 "$planned_power_off"
assert_eq 0 "$_zte_test_power_transition"
assert_eq \
    "$STATE_DIR/power-decision.json|{\"backend\":\"hardware\",\"action\":\"ON\",\"executed\":true,\"reason\":\"fail_safe\",\"outcome\":\"succeeded\",\"updated\":1722345678,\"profile\":\"hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value\"}" \
    "$(tail -n 1 "$power_record_log")"
_zte_test_power_apply_failure=0

# Stopping or uninstalling the manager must restore VBUS even when normal
# writes were disabled after an earlier hardware OFF.
: >"$power_call_log"
: >"$hardware_io_log"
: >"$recovery_service_calls"
last_power_action=OFF
# Read by the eval-defined production restore_power_on function.
# shellcheck disable=SC2034
write_enabled=0
power_backend=hardware
power_calibrated=1
_zte_test_power_record_failure=1
assert_success zte_recovery_inhibit_write \
    "$RECOVERY_INHIBIT_FILE" battery_high 1722346000 1722345600 true
assert_success restore_power_on
assert_eq \
    'ON|/sys/class/gpio/modem_power/value' \
    "$(cat "$hardware_io_log")"
assert_eq '/etc/init.d/zte-usb-recover:start' \
    "$(cat "$recovery_service_calls")"
assert_failure test -e "$RECOVERY_INHIBIT_FILE"
assert_eq ON "$last_power_action"
_zte_test_power_record_failure=0
assert_eq \
    "$STATE_DIR/power-decision.json|{\"backend\":\"hardware\",\"action\":\"ON\",\"executed\":true,\"reason\":\"disabled\",\"outcome\":\"succeeded\",\"updated\":1722345678,\"profile\":\"hardware|1|0|cudy,tr3000-v1|/sys/class/gpio/modem_power/value\"}" \
    "$(tail -n 1 "$power_record_log")"

# A successful ON followed by recovery restart failure is an executed action
# with a failed overall outcome, never a stale success.
assert_success zte_recovery_inhibit_write \
    "$RECOVERY_INHIBIT_FILE" battery_high 1722346000 1722345600 true
_zte_test_recovery_running=0
_zte_test_recovery_control_failure=1
assert_failure restore_power_on
assert_eq \
    "$STATE_DIR/power-decision.json|{\"backend\":\"hardware\",\"action\":\"ON\",\"executed\":true,\"reason\":\"disabled\",\"outcome\":\"failed\",\"updated\":1722345678,\"profile\":\"hardware|1|0|cudy,tr3000-v1|/sys/class/gpio/modem_power/value\"}" \
    "$(tail -n 1 "$power_record_log")"
_zte_test_recovery_control_failure=0
zte_recovery_inhibit_clear "$RECOVERY_INHIBIT_FILE"

# A normal startup with no owned transition must not enable a recovery service
# that the administrator had intentionally disabled.
: >"$hardware_io_log"
: >"$recovery_service_calls"
_zte_test_recovery_running=0
assert_success restore_power_on
assert_eq \
    'ON|/sys/class/gpio/modem_power/value' \
    "$(cat "$hardware_io_log")"
assert_eq '' "$(cat "$recovery_service_calls")"
assert_eq 0 "$_zte_test_recovery_running"

: >"$power_call_log"
power_calibrated=0
assert_success restore_power_on
assert_eq '' "$(cat "$power_call_log")"
# Read by later eval-defined production functions.
# shellcheck disable=SC2034
power_calibrated=1

sleep_log=$work/sleep
: >"$sleep_log"
startup_order=$work/startup-order
: >"$startup_order"
# Assignments are read by the eval-defined production main function.
# shellcheck disable=SC2034
load_config() {
    printf '%s\n' config >>"$startup_order"
    enabled=1
    poll_interval=30
}
early_safety_restore() {
    printf '%s\n' safety >>"$startup_order"
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
zte_recovery_reconcile() { :; }
# Read by the eval-defined production main function.
# shellcheck disable=SC2034
power_backend=unconfigured
main
assert_eq \
    "safety
config" \
    "$(cat "$startup_order")"
assert_eq "$$" "$(cat "$PID_FILE")"
assert_eq \
    "$work/real-state|info|service|service_started|1722345678|524288" \
    "$(sed -n '1p' "$event_call_log")"
assert_eq "$work/real-state|50" "$(cat "$prune_call_log")"
assert_eq '60
120
30' "$(cat "$sleep_log")"
shutdown_manager
assert_failure test -e "$PID_FILE"

rm -rf "$work"
finish
