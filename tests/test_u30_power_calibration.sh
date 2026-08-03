#!/bin/sh
# shellcheck disable=SC2317,SC2329
set -eu

TEST_NAME=test_u30_power_calibration
. ./tests/testlib.sh

tool=./package/zte-usb-wifi-manager/files/usr/libexec/zte-u30-power-calibrate
if [ ! -f "$tool" ]; then
	fail 'U30 power-supply calibration tool must exist'
	finish
fi

work=$(mktemp -d /tmp/zte-test-u30-power-calibration.XXXXXX)
trap 'chmod -R u+rwx "$work" 2>/dev/null || :; rm -rf "$work"' EXIT HUP INT TERM
state=$work/state
mkdir -p "$state"
manager=$state/manager
manager_state=$state/manager-state
events=$state/events
sync_tool=$state/sync

cat >"$manager" <<'EOF'
#!/bin/sh
case ${1-} in
	running) [ "$(cat "$ZTE_TEST_MANAGER_STATE")" = running ] ;;
	stop)
		printf '%s\n' manager-stop >>"$ZTE_TEST_EVENTS"
		printf '%s\n' stopped >"$ZTE_TEST_MANAGER_STATE"
		;;
	start)
		printf '%s\n' manager-start >>"$ZTE_TEST_EVENTS"
		[ "${ZTE_TEST_MANAGER_START_FAIL:-0}" = 0 ] || exit 1
		printf '%s\n' running >"$ZTE_TEST_MANAGER_STATE"
		;;
	*) exit 1 ;;
esac
EOF
cat >"$sync_tool" <<'EOF'
#!/bin/sh
printf '%s\n' sync >>"$ZTE_TEST_EVENTS"
[ "${ZTE_TEST_SYNC_FAIL_WHILE_RUNNING:-0}" = 0 ] ||
	[ "$(cat "$ZTE_TEST_MANAGER_STATE")" != running ]
EOF
chmod +x "$manager" "$sync_tool"

ZTE_U30_CALIBRATION_LIB_DIR=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
ZTE_U30_CALIBRATION_HOST=192.168.0.1
ZTE_U30_CALIBRATION_NETDEV=eth2
ZTE_U30_CALIBRATION_ADAPTER=zte_u30
ZTE_U30_CALIBRATION_WRITE_ENABLED=0
ZTE_U30_CALIBRATION_POWER_WRITE_ENABLED=0
ZTE_U30_CALIBRATION_SMART_CHARGE_ENABLED=0
ZTE_U30_CALIBRATION_SIM_WRITE_ENABLED=0
ZTE_U30_CALIBRATION_CELLULAR_WRITE_ENABLED=0
ZTE_U30_CALIBRATION_WIFI_WRITE_ENABLED=0
ZTE_U30_CALIBRATION_TRAFFIC_WRITE_ENABLED=0
ZTE_U30_CALIBRATION_SMS_WRITE_ENABLED=0
ZTE_U30_CALIBRATION_REBOOT_ENABLED=0
ZTE_U30_CALIBRATION_SHUTDOWN_ENABLED=0
ZTE_U30_CALIBRATION_COOKIE_FILE=$state/cookies
ZTE_U30_CALIBRATION_STATE_DIR=$state/calibration
ZTE_U30_CALIBRATION_LOCK_DIR=$state/calibration.lock
ZTE_U30_CALIBRATION_MANAGER_SERVICE=$manager
ZTE_U30_CALIBRATION_SYNC=$sync_tool
ZTE_U30_CALIBRATION_STOP_ATTEMPTS=2
ZTE_U30_CALIBRATION_STOP_INTERVAL=0
ZTE_TEST_MANAGER_STATE=$manager_state
ZTE_TEST_EVENTS=$events
ZTE_TEST_MANAGER_START_FAIL=0
ZTE_TEST_SYNC_FAIL_WHILE_RUNNING=0
export ZTE_U30_CALIBRATION_LIB_DIR ZTE_U30_CALIBRATION_HOST
export ZTE_U30_CALIBRATION_NETDEV ZTE_U30_CALIBRATION_ADAPTER
export ZTE_U30_CALIBRATION_WRITE_ENABLED
export ZTE_U30_CALIBRATION_POWER_WRITE_ENABLED
export ZTE_U30_CALIBRATION_SMART_CHARGE_ENABLED
export ZTE_U30_CALIBRATION_SIM_WRITE_ENABLED
export ZTE_U30_CALIBRATION_CELLULAR_WRITE_ENABLED
export ZTE_U30_CALIBRATION_WIFI_WRITE_ENABLED
export ZTE_U30_CALIBRATION_TRAFFIC_WRITE_ENABLED
export ZTE_U30_CALIBRATION_SMS_WRITE_ENABLED
export ZTE_U30_CALIBRATION_REBOOT_ENABLED
export ZTE_U30_CALIBRATION_SHUTDOWN_ENABLED
export ZTE_U30_CALIBRATION_COOKIE_FILE ZTE_U30_CALIBRATION_STATE_DIR
export ZTE_U30_CALIBRATION_LOCK_DIR ZTE_U30_CALIBRATION_MANAGER_SERVICE
export ZTE_U30_CALIBRATION_SYNC ZTE_U30_CALIBRATION_STOP_ATTEMPTS
export ZTE_U30_CALIBRATION_STOP_INTERVAL ZTE_TEST_MANAGER_STATE ZTE_TEST_EVENTS
export ZTE_TEST_MANAGER_START_FAIL
export ZTE_TEST_SYNC_FAIL_WHILE_RUNNING

# shellcheck source=/dev/null
if (. "$tool"); then
	pass
else
	fail 'U30 calibration tool must be safe to source'
	finish
fi
# shellcheck source=/dev/null
. "$tool"

rmdir() {
	if [ "${ZTE_TEST_FINALIZE_RMDIR_FAIL:-0}" = 1 ] &&
		[ "${1-}" = "$ZTE_U30_CALIBRATION_STATE_DIR" ] &&
		[ "$(cat "$ZTE_TEST_MANAGER_STATE")" = running ]; then
		return 1
	fi
	command rmdir "$@"
}

zte_u30_power_calibration_require_root() { return 0; }
zte_u30_power_calibration_path_root_owned() { return 0; }
zte_netifd_route_uses_device() {
	[ "${ZTE_TEST_ROUTE_OK:-1}" = 1 ] &&
		[ "$1" = 192.168.0.1 ] && [ "$2" = eth2 ]
}
zte_adapter_fetch_power_supply_mode() {
	printf '%s\n' "${ZTE_TEST_CURRENT_MODE:-charging}"
}
zte_execute_power_supply_mode() {
	printf 'write:%s\n' "$4" >>"$ZTE_TEST_EVENTS"
	if [ "${ZTE_TEST_REENTER_RECOVER:-0}" = 1 ] &&
		[ "$4" = direct_supply ]; then
		reenter_status=0
		reenter_output=$(zte_u30_power_calibration_recover) ||
			reenter_status=$?
		printf 'reenter:%s:%s\n' "$reenter_status" "$reenter_output" \
			>>"$ZTE_TEST_EVENTS"
	fi
	case ${ZTE_TEST_FAIL_WRITE:-}:$4 in
		target:direct_supply) printf '%s\n' write_ambiguous; return 1 ;;
		restore:charging) printf '%s\n' readback_mismatch; return 1 ;;
	esac
	ZTE_TEST_CURRENT_MODE=$4
	export ZTE_TEST_CURRENT_MODE
	return 0
}

reset_case() {
	rm -rf "$ZTE_U30_CALIBRATION_STATE_DIR" \
		"$ZTE_U30_CALIBRATION_LOCK_DIR"
	rm -f "$ZTE_U30_CALIBRATION_COOKIE_FILE"
	: >"$events"
	printf '%s\n' running >"$manager_state"
	ZTE_TEST_CURRENT_MODE=charging
	ZTE_TEST_ROUTE_OK=1
	ZTE_TEST_FAIL_WRITE=
	ZTE_TEST_MANAGER_START_FAIL=0
	ZTE_TEST_REENTER_RECOVER=0
	ZTE_TEST_SYNC_FAIL_WHILE_RUNNING=0
	ZTE_TEST_FINALIZE_RMDIR_FAIL=0
	export ZTE_TEST_CURRENT_MODE ZTE_TEST_ROUTE_OK ZTE_TEST_FAIL_WRITE
	export ZTE_TEST_MANAGER_START_FAIL
	export ZTE_TEST_REENTER_RECOVER
	export ZTE_TEST_SYNC_FAIL_WHILE_RUNNING ZTE_TEST_FINALIZE_RMDIR_FAIL
}

reset_case
probe=$(zte_u30_power_calibration_probe)
assert_eq \
	'{"ok":true,"mode":"probe","adapter":"zte_u30","current_mode":"charging","write_gates_disabled":true,"device_route":true}' \
	"$probe"
assert_eq '' "$(cat "$events")"

ZTE_U30_CALIBRATION_ADAPTER=auto
export ZTE_U30_CALIBRATION_ADAPTER
probe_status=0
probe=$(zte_u30_power_calibration_probe) || probe_status=$?
assert_eq 1 "$probe_status"
assert_eq '{"ok":false,"mode":"probe","code":"wrong_profile"}' "$probe"
ZTE_U30_CALIBRATION_ADAPTER=zte_u30
export ZTE_U30_CALIBRATION_ADAPTER

ZTE_U30_CALIBRATION_WRITE_ENABLED=1
export ZTE_U30_CALIBRATION_WRITE_ENABLED
probe_status=0
probe=$(zte_u30_power_calibration_probe) || probe_status=$?
assert_eq 1 "$probe_status"
assert_eq '{"ok":false,"mode":"probe","code":"write_gates_enabled"}' "$probe"
ZTE_U30_CALIBRATION_WRITE_ENABLED=0
export ZTE_U30_CALIBRATION_WRITE_ENABLED

for gate in \
	ZTE_U30_CALIBRATION_SIM_WRITE_ENABLED \
	ZTE_U30_CALIBRATION_CELLULAR_WRITE_ENABLED \
	ZTE_U30_CALIBRATION_WIFI_WRITE_ENABLED \
	ZTE_U30_CALIBRATION_TRAFFIC_WRITE_ENABLED \
	ZTE_U30_CALIBRATION_SMS_WRITE_ENABLED \
	ZTE_U30_CALIBRATION_REBOOT_ENABLED \
	ZTE_U30_CALIBRATION_SHUTDOWN_ENABLED; do
	eval "$gate=1; export $gate"
	probe_status=0
	probe=$(zte_u30_power_calibration_probe) || probe_status=$?
	assert_eq 1 "$probe_status"
	assert_eq \
		'{"ok":false,"mode":"probe","code":"write_gates_enabled"}' \
		"$probe"
	eval "$gate=0; export $gate"
done

reset_case
execute_status=0
zte_u30_power_calibration_execute WRONG >/dev/null || execute_status=$?
assert_eq 2 "$execute_status"
assert_eq '' "$(cat "$events")"

: >"$ZTE_U30_CALIBRATION_COOKIE_FILE"
result=$(zte_u30_power_calibration_execute I_AM_ON_SPARE_U30)
assert_eq \
	'{"ok":true,"mode":"execute","tested":"direct_supply","target_verified":true,"original":"charging","original_restored":true,"management_route_preserved":true}' \
	"$result"
assert_eq 'manager-stop
sync
write:direct_supply
write:charging
manager-start
sync
sync' "$(cat "$events")"
assert_eq running "$(cat "$manager_state")"
assert_failure test -e "$ZTE_U30_CALIBRATION_STATE_DIR"
assert_failure test -e "$ZTE_U30_CALIBRATION_LOCK_DIR"
assert_failure test -e "$ZTE_U30_CALIBRATION_COOKIE_FILE"

reset_case
ZTE_TEST_REENTER_RECOVER=1
export ZTE_TEST_REENTER_RECOVER
result=$(zte_u30_power_calibration_execute I_AM_ON_SPARE_U30)
assert_eq \
	'{"ok":true,"mode":"execute","tested":"direct_supply","target_verified":true,"original":"charging","original_restored":true,"management_route_preserved":true}' \
	"$result"
assert_eq 'manager-stop
sync
write:direct_supply
reenter:1:recovery_busy
write:charging
manager-start
sync
sync' "$(cat "$events")"

reset_case
ZTE_TEST_MANAGER_START_FAIL=1
export ZTE_TEST_MANAGER_START_FAIL
execute_status=0
execute_output=$(zte_u30_power_calibration_execute I_AM_ON_SPARE_U30) ||
	execute_status=$?
assert_eq 1 "$execute_status"
assert_eq cleanup_failed "$execute_output"
assert_eq stopped "$(cat "$manager_state")"
assert_success test -e "$ZTE_U30_CALIBRATION_STATE_DIR/state.json"
assert_success test -e "$ZTE_U30_CALIBRATION_LOCK_DIR"
assert_eq \
	'{"original_mode":"charging","manager_was_running":true}' \
	"$(cat "$ZTE_U30_CALIBRATION_STATE_DIR/state.json")"
ZTE_TEST_MANAGER_START_FAIL=0
export ZTE_TEST_MANAGER_START_FAIL
recover=$(zte_u30_power_calibration_recover)
assert_eq \
	'{"ok":true,"mode":"recover","original_restored":true,"manager_restored":true}' \
	"$recover"
assert_eq running "$(cat "$manager_state")"

for finalize_fault in sync rmdir; do
	reset_case
	case $finalize_fault in
		sync) ZTE_TEST_SYNC_FAIL_WHILE_RUNNING=1 ;;
		rmdir) ZTE_TEST_FINALIZE_RMDIR_FAIL=1 ;;
	esac
	export ZTE_TEST_SYNC_FAIL_WHILE_RUNNING ZTE_TEST_FINALIZE_RMDIR_FAIL
	execute_status=0
	execute_output=$(zte_u30_power_calibration_execute I_AM_ON_SPARE_U30) ||
		execute_status=$?
	assert_eq 1 "$execute_status"
	assert_eq cleanup_failed "$execute_output"
	assert_eq stopped "$(cat "$manager_state")"
	assert_eq \
		'{"original_mode":"charging","manager_was_running":true}' \
		"$(cat "$ZTE_U30_CALIBRATION_STATE_DIR/state.json")"
	assert_success test -d "$ZTE_U30_CALIBRATION_LOCK_DIR"
	assert_eq 0 "$(find "$ZTE_U30_CALIBRATION_LOCK_DIR" \
		-mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
	ZTE_TEST_SYNC_FAIL_WHILE_RUNNING=0
	ZTE_TEST_FINALIZE_RMDIR_FAIL=0
	export ZTE_TEST_SYNC_FAIL_WHILE_RUNNING ZTE_TEST_FINALIZE_RMDIR_FAIL
	recover=$(zte_u30_power_calibration_recover)
	assert_eq \
		'{"ok":true,"mode":"recover","original_restored":true,"manager_restored":true}' \
		"$recover"
done

reset_case
ZTE_TEST_FAIL_WRITE=target
export ZTE_TEST_FAIL_WRITE
execute_status=0
execute_output=$(zte_u30_power_calibration_execute I_AM_ON_SPARE_U30) ||
	execute_status=$?
assert_eq 1 "$execute_status"
assert_eq target_uncertain "$execute_output"
assert_eq 'manager-stop
sync
write:direct_supply' "$(cat "$events")"
assert_eq stopped "$(cat "$manager_state")"
assert_success test -e "$ZTE_U30_CALIBRATION_STATE_DIR/state.json"
assert_success test -e "$ZTE_U30_CALIBRATION_LOCK_DIR"
printf '%s\n' 2147483647 \
	>"$ZTE_U30_CALIBRATION_LOCK_DIR/recovery-active"
chmod 600 "$ZTE_U30_CALIBRATION_LOCK_DIR/recovery-active"
ZTE_TEST_FAIL_WRITE=
export ZTE_TEST_FAIL_WRITE
recover=$(zte_u30_power_calibration_recover)
assert_eq \
	'{"ok":true,"mode":"recover","original_restored":true,"manager_restored":true}' \
	"$recover"

reset_case
ZTE_TEST_FAIL_WRITE=restore
export ZTE_TEST_FAIL_WRITE
execute_status=0
execute_output=$(zte_u30_power_calibration_execute I_AM_ON_SPARE_U30) ||
	execute_status=$?
assert_eq 1 "$execute_status"
assert_eq restore_failed "$execute_output"
assert_eq stopped "$(cat "$manager_state")"
assert_success test -e "$ZTE_U30_CALIBRATION_STATE_DIR/state.json"
assert_success test -e "$ZTE_U30_CALIBRATION_LOCK_DIR"
assert_eq \
	'{"original_mode":"charging","manager_was_running":true}' \
	"$(cat "$ZTE_U30_CALIBRATION_STATE_DIR/state.json")"
printf '%s\n' partial >"$ZTE_U30_CALIBRATION_STATE_DIR/state.json.tmp.2147483647"
chmod 600 "$ZTE_U30_CALIBRATION_STATE_DIR/state.json.tmp.2147483647"
printf '%s\n' pid=2147483647 >"$ZTE_U30_CALIBRATION_LOCK_DIR/owner"
chmod 600 "$ZTE_U30_CALIBRATION_LOCK_DIR/owner"

ZTE_TEST_FAIL_WRITE=
export ZTE_TEST_FAIL_WRITE
recover=$(zte_u30_power_calibration_recover)
assert_eq \
	'{"ok":true,"mode":"recover","original_restored":true,"manager_restored":true}' \
	"$recover"
assert_eq running "$(cat "$manager_state")"
assert_failure test -e "$ZTE_U30_CALIBRATION_STATE_DIR"
assert_failure test -e "$ZTE_U30_CALIBRATION_LOCK_DIR"

reset_case
mkdir "$ZTE_U30_CALIBRATION_LOCK_DIR"
chmod 700 "$ZTE_U30_CALIBRATION_LOCK_DIR"
printf '%s\n' "$$" >"$ZTE_U30_CALIBRATION_LOCK_DIR/recovery-active"
chmod 600 "$ZTE_U30_CALIBRATION_LOCK_DIR/recovery-active"
assert_failure zte_u30_power_calibration_create_claim
assert_eq "$$" "$(cat "$ZTE_U30_CALIBRATION_LOCK_DIR/recovery-active")"
assert_eq 1 "$(zte_u30_power_calibration_dir_entry_count \
	"$ZTE_U30_CALIBRATION_LOCK_DIR")"

reset_case
printf '%s\n' stopped >"$manager_state"
mkdir "$ZTE_U30_CALIBRATION_LOCK_DIR"
chmod 700 "$ZTE_U30_CALIBRATION_LOCK_DIR"
printf '%s\n' manager_was_running=true \
	>"$ZTE_U30_CALIBRATION_LOCK_DIR/committed"
chmod 600 "$ZTE_U30_CALIBRATION_LOCK_DIR/committed"
recover=$(zte_u30_power_calibration_recover)
assert_eq \
	'{"ok":true,"mode":"recover","original_restored":false,"manager_restored":true}' \
	"$recover"
assert_eq running "$(cat "$manager_state")"
assert_failure test -e "$ZTE_U30_CALIBRATION_LOCK_DIR"

reset_case
mkdir "$ZTE_U30_CALIBRATION_LOCK_DIR"
chmod 700 "$ZTE_U30_CALIBRATION_LOCK_DIR"
execute_status=0
zte_u30_power_calibration_execute I_AM_ON_SPARE_U30 >/dev/null ||
	execute_status=$?
assert_eq 1 "$execute_status"
assert_eq '' "$(cat "$events")"
recover=$(zte_u30_power_calibration_recover)
assert_eq \
	'{"ok":true,"mode":"recover","original_restored":false,"manager_restored":true}' \
	"$recover"
assert_failure test -e "$ZTE_U30_CALIBRATION_LOCK_DIR"

reset_case
printf '%s\n' stopped >"$manager_state"
mkdir "$ZTE_U30_CALIBRATION_LOCK_DIR"
chmod 700 "$ZTE_U30_CALIBRATION_LOCK_DIR"
: >"$ZTE_U30_CALIBRATION_LOCK_DIR/committed.tmp.2147483647"
chmod 600 "$ZTE_U30_CALIBRATION_LOCK_DIR/committed.tmp.2147483647"
: >"$ZTE_U30_CALIBRATION_LOCK_DIR/recovery-active.tmp.2147483646"
chmod 600 "$ZTE_U30_CALIBRATION_LOCK_DIR/recovery-active.tmp.2147483646"
recover=$(zte_u30_power_calibration_recover)
assert_eq \
	'{"ok":true,"mode":"recover","original_restored":false,"manager_restored":false}' \
	"$recover"
assert_failure test -e "$ZTE_U30_CALIBRATION_LOCK_DIR"

finish
