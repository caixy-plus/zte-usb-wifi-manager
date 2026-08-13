#!/bin/sh
# Exercise U30 SMS and device commands through the production executor,
# adapter and HTTP layers against a loopback-only stateful simulator.
set -eu

TEST_NAME=test_u30_actions_e2e
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

# Minimal test replacement for OpenWrt jsonfilter's one expression used by
# the production SMS readback. It emits each object from messages[] as JSONL.
jsonfilter() {
	[ "$1" = -s ] && [ "$3" = -e ] && [ "$4" = '@.messages[*]' ] || return 1
	printf '%s' "$2" | node -e '
		let s="";
		process.stdin.on("data", d => s += d);
		process.stdin.on("end", () => {
			const value = JSON.parse(s);
			if (!Array.isArray(value.messages)) process.exit(1);
			for (const item of value.messages) console.log(JSON.stringify(item));
		});'
}

work=$(mktemp -d /tmp/zte-test-u30-actions-e2e.XXXXXX)
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
		--allow-u30-action-writes \
		>"$work/server.out" 2>"$work/server.err" &
	simulator_pid=$!
	attempts=0
	while [ ! -s "$ready_file" ]; do
		if ! kill -0 "$simulator_pid" 2>/dev/null; then
			fail "U30 action simulator exited: $(cat "$work/server.err")"
			return 1
		fi
		attempts=$((attempts + 1))
		[ "$attempts" -lt 100 ] || {
			fail 'U30 action simulator did not become ready'
			return 1
		}
		sleep 0.02
	done
	simulator_host=127.0.0.1:$(cat "$ready_file")
}

run_sms() {
	action=$1
	record=$2
	action_status=0
	action_output=$(zte_execute_u30_sms_action "$simulator_host" unused \
		"$work/cookies" "$action" "$record" 2>>"$work/action.err") ||
		action_status=$?
}

run_device() {
	action=$1
	action_status=0
	action_output=$(zte_execute_u30_device_action "$simulator_host" unused \
		"$work/cookies" "$action" 2>>"$work/action.err") ||
		action_status=$?
}

assert_single_post() {
	goform=$1
	assert_eq 1 "$(grep -c "^POST U30_ACTION $goform " "$request_log")" \
		'non-idempotent device POST must be issued exactly once'
	if grep -Ei 'cookie|password|unused|sensitive|2025550123|0046006900780074007500720065' \
		"$request_log" "$work/action.err" "$work/server.err" \
		"$work/server.out" >/dev/null 2>&1; then
		fail 'U30 action logs exposed private request content'
	else
		pass
	fi
}

assert_success zte_device_profile_select_named zte_u30
ZTE_DEVICE_PROFILE_SCHEME=http
ZTE_DEVICE_PROFILE_TLS_INSECURE=0
export ZTE_DEVICE_PROFILE_SCHEME ZTE_DEVICE_PROFILE_TLS_INSECURE
assert_success zte_adapter_apply_profile
assert_success zte_adapter_login_required

ZTE_HTTP_TIMEOUT=0.2
ZTE_SMS_READBACK_ATTEMPTS=3
ZTE_SMS_READBACK_INTERVAL=0
ZTE_DEVICE_ACTION_ATTEMPTS=4
ZTE_DEVICE_ACTION_INTERVAL=1
ZTE_DEVICE_ACTION_MIN_OUTAGE_SECONDS=1
export ZTE_HTTP_TIMEOUT ZTE_SMS_READBACK_ATTEMPTS ZTE_SMS_READBACK_INTERVAL
export ZTE_DEVICE_ACTION_ATTEMPTS ZTE_DEVICE_ACTION_INTERVAL
export ZTE_DEVICE_ACTION_MIN_OUTAGE_SECONDS

start_simulator u30-action-success
run_sms send_sms \
	'{"payload":{"action":"send_sms","number":"+12025550123","content":"Fixture"}}'
assert_eq ok "$action_output"
assert_eq 0 "$action_status"
assert_single_post SEND_SMS

start_simulator u30-action-success
run_sms mark_sms_read \
	'{"payload":{"action":"mark_sms_read","message_id":"42"}}'
assert_eq ok "$action_output"
assert_eq 0 "$action_status"
assert_single_post SET_MSG_READ

start_simulator u30-action-success
run_sms delete_sms \
	'{"payload":{"action":"delete_sms","message_id":"42","confirm":true}}'
assert_eq ok "$action_output"
assert_eq 0 "$action_status"
assert_single_post DELETE_SMS

start_simulator u30-action-reject
run_sms send_sms \
	'{"payload":{"action":"send_sms","number":"+12025550123","content":"Fixture"}}'
assert_eq device_rejected "$action_output"
assert_eq 1 "$action_status"
assert_single_post SEND_SMS

# A lost SEND_SMS response can never be proven by the global command status.
start_simulator u30-action-apply-then-timeout
run_sms send_sms \
	'{"payload":{"action":"send_sms","number":"+12025550123","content":"Fixture"}}'
assert_eq write_ambiguous "$action_output"
assert_eq 1 "$action_status"
assert_single_post SEND_SMS

# Delete/read operations are tied to an exact message ID, so safe readback may
# resolve an applied timeout but not a timeout before application.
start_simulator u30-action-apply-then-timeout
run_sms delete_sms \
	'{"payload":{"action":"delete_sms","message_id":"42","confirm":true}}'
assert_eq ok "$action_output"
assert_eq 0 "$action_status"
assert_single_post DELETE_SMS

start_simulator u30-action-timeout-before-apply
run_sms delete_sms \
	'{"payload":{"action":"delete_sms","message_id":"42","confirm":true}}'
assert_eq write_ambiguous "$action_output"
assert_eq 1 "$action_status"
assert_single_post DELETE_SMS

start_simulator u30-action-success
run_device reboot_device
assert_eq ok "$action_output"
assert_eq 0 "$action_status"
assert_single_post REBOOT_DEVICE
assert_eq 1 "$(grep -c '^GET U30_DEVICE outage-qualified ' "$request_log")"
assert_eq 1 "$(grep -c '^GET U30_DEVICE recovered ' "$request_log")"

start_simulator u30-action-success
run_device shutdown_device
assert_eq ok "$action_output"
assert_eq 0 "$action_status"
assert_single_post SHUTDOWN_DEVICE
assert_eq 1 "$(grep -c '^GET U30_DEVICE shutdown-offline ' "$request_log")"

start_simulator u30-action-reject
run_device reboot_device
assert_eq device_rejected "$action_output"
assert_eq 1 "$action_status"
assert_single_post REBOOT_DEVICE

finish
