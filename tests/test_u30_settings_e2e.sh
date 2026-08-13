#!/bin/sh
# Exercise non-destructive U30 settings through the complete production chain
# against a loopback-only stateful simulator. TLS remains a separate final
# device/QEMU concern; this suite freezes HTTP request and readback semantics.
set -eu

TEST_NAME=test_u30_settings_e2e
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/session.sh"
. "$lib/device-profile.sh"
. "$lib/adapter-zte-u25s-metadata.sh"
. "$lib/adapter-zte-u25s.sh"
. "$lib/action-executor.sh"

work=$(mktemp -d /tmp/zte-test-u30-settings-e2e.XXXXXX)
ZTE_SESSION_LOCK_FILE=$work/session.lock
ZTE_SESSION_LOCK_ATTEMPTS=1
ZTE_SESSION_LOCK_INTERVAL=0
export ZTE_SESSION_LOCK_FILE ZTE_SESSION_LOCK_ATTEMPTS
export ZTE_SESSION_LOCK_INTERVAL
simulator_pid=
trap 'stop_simulator; rm -rf "$work"' EXIT HUP INT TERM

stop_simulator() {
	if [ -n "$simulator_pid" ]; then
		kill "$simulator_pid" 2>/dev/null || true
		wait "$simulator_pid" 2>/dev/null || true
		simulator_pid=
	fi
}

start_simulator() {
	stop_simulator
	scenario=$1
	ready_file=$work/ready
	request_log=$work/requests
	rm -f "$ready_file" "$request_log"
	python3 tests/u25s_simulator.py \
		--host 127.0.0.1 --port 0 --profile u30 \
		--scenario "$scenario" --ready-file "$ready_file" \
		--request-log "$request_log" --login-secret unused \
		--allow-u30-setting-writes \
		>"$work/server.out" 2>"$work/server.err" &
	simulator_pid=$!
	attempts=0
	while [ ! -s "$ready_file" ]; do
		if ! kill -0 "$simulator_pid" 2>/dev/null; then
			fail "U30 settings simulator exited: $(cat "$work/server.err")"
			return 1
		fi
		attempts=$((attempts + 1))
		[ "$attempts" -lt 100 ] || {
			fail 'U30 settings simulator did not become ready'
			return 1
		}
		sleep 0.02
	done
	simulator_host=127.0.0.1:$(cat "$ready_file")
}

run_setting() {
	action=$1
	record=$2
	setting_status=0
	setting_output=$(zte_execute_u30_setting "$simulator_host" unused \
		"$work/cookies" "$action" "$record" 2>>"$work/action.err") ||
		setting_status=$?
}

assert_setting_success() {
	expected_goform=$1
	assert_eq ok "$setting_output"
	assert_eq 0 "$setting_status"
	assert_eq 1 "$(grep -c "^POST U30_SETTING $expected_goform " \
		"$request_log")" 'each setting must POST exactly once'
	if grep -Ei 'cookie|password|unused|sensitive' "$request_log" \
		"$work/action.err" "$work/server.err" "$work/server.out" \
		>/dev/null 2>&1; then
		fail 'U30 settings logs exposed request secrets'
	else
		pass
	fi
}

assert_success zte_device_profile_select_named zte_u30
ZTE_DEVICE_PROFILE_SCHEME=http
ZTE_DEVICE_PROFILE_TLS_INSECURE=0
export ZTE_DEVICE_PROFILE_SCHEME ZTE_DEVICE_PROFILE_TLS_INSECURE
assert_success zte_adapter_apply_profile
assert_eq zte_u30 "$ZTE_ADAPTER_ID"
assert_success zte_adapter_login_required

ZTE_HTTP_TIMEOUT=0.2
ZTE_SETTING_READBACK_ATTEMPTS=3
ZTE_SETTING_READBACK_INTERVAL=0
export ZTE_HTTP_TIMEOUT ZTE_SETTING_READBACK_ATTEMPTS
export ZTE_SETTING_READBACK_INTERVAL

# The simulator rejects header drift and duplicate keys before applying a
# setting, so the E2E cannot pass with a looser request contract.
start_simulator u30-setting-success
invalid_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 1 \
	-H "Referer: http://$simulator_host/" \
	-H 'Content-Type: application/x-www-form-urlencoded' \
	--data-binary 'isTest=false&goformId=SET_CONNECTION_MODE&ConnectionMode=manual_dial&dial_roam_setting_option=off' \
	"http://$simulator_host/goform/goform_set_cmd_process")
assert_eq 400 "$invalid_code" 'missing XHR header must be rejected'

start_simulator u30-setting-success
invalid_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 1 \
	-H "Referer: http://$simulator_host/" \
	-H 'X-Requested-With: XMLHttpRequest' \
	-H 'Content-Type: application/x-www-form-urlencoded' \
	--data-binary 'isTest=false&goformId=SET_CONNECTION_MODE&ConnectionMode=manual_dial&ConnectionMode=auto_dial&dial_roam_setting_option=off' \
	"http://$simulator_host/goform/goform_set_cmd_process")
assert_eq 400 "$invalid_code" 'duplicate form keys must be rejected'

start_simulator u30-setting-success
run_setting set_connection_mode \
	'{"payload":{"action":"set_connection_mode","mode":"manual"}}'
assert_setting_success SET_CONNECTION_MODE

start_simulator u30-setting-success
run_setting set_apn \
	'{"payload":{"action":"set_apn","apn":"internet","auth":"none"}}'
assert_setting_success APN_PROC

start_simulator u30-setting-success
run_setting set_wifi \
	'{"payload":{"action":"set_wifi","enabled":true,"band":"2g","ssid":"Fixture WiFi","security":"open","channel":"auto"}}'
assert_setting_success setAccessPointInfo

start_simulator u30-setting-success
run_setting set_wifi \
	'{"payload":{"action":"set_wifi","enabled":false}}'
assert_setting_success switchWiFiModule

start_simulator u30-setting-success
run_setting set_traffic_plan \
	'{"payload":{"action":"set_traffic_plan","enabled":true,"limit_bytes":10737418240,"alert_percent":90,"cycle_day":1,"disconnect":false}}'
assert_setting_success DATA_LIMIT_SETTING

start_simulator u30-setting-success
run_setting reset_traffic \
	'{"payload":{"action":"reset_traffic","confirm":true}}'
assert_setting_success RESET_DATA_COUNTER

# A definite rejection never runs readback. Ambiguous responses never retry
# the POST and are resolved only when the requested state was actually applied.
start_simulator u30-setting-reject
run_setting set_connection_mode \
	'{"payload":{"action":"set_connection_mode","mode":"manual"}}'
assert_eq device_rejected "$setting_output"
assert_eq 1 "$setting_status"
assert_eq 1 "$(grep -c '^POST U30_SETTING SET_CONNECTION_MODE ' "$request_log")"
assert_eq 0 "$(grep -c '^GET U30_SETTING ' "$request_log" || true)"

start_simulator u30-setting-timeout-before-apply
run_setting set_connection_mode \
	'{"payload":{"action":"set_connection_mode","mode":"manual"}}'
assert_eq write_ambiguous "$setting_output"
assert_eq 1 "$setting_status"
assert_eq 1 "$(grep -c '^POST U30_SETTING SET_CONNECTION_MODE ' "$request_log")"
assert_eq 3 "$(grep -c '^GET U30_SETTING ' "$request_log")"

for scenario in u30-setting-apply-then-timeout \
	u30-setting-malformed-applied u30-setting-empty-applied; do
	start_simulator "$scenario"
	run_setting set_connection_mode \
		'{"payload":{"action":"set_connection_mode","mode":"manual"}}'
	assert_setting_success SET_CONNECTION_MODE
done

for scenario in u30-setting-malformed-unapplied \
	u30-setting-empty-unapplied; do
	start_simulator "$scenario"
	run_setting set_connection_mode \
		'{"payload":{"action":"set_connection_mode","mode":"manual"}}'
	assert_eq write_ambiguous "$setting_output"
	assert_eq 1 "$setting_status"
	assert_eq 1 "$(grep -c '^POST U30_SETTING SET_CONNECTION_MODE ' "$request_log")"
done

finish
