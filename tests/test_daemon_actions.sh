#!/bin/sh
# Production orchestration is extracted from the daemon and invokes test
# doubles defined below.
# shellcheck disable=SC2034,SC2218,SC2317,SC2329
set -eu

TEST_NAME=test_daemon_actions
. ./tests/testlib.sh

backend=./package/zte-usb-wifi-manager
daemon=$backend/files/usr/sbin/zte-usb-wifi-managerd
lib=$backend/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/actions.sh"

extract_daemon_function() {
    sed -n "/^$1() {$/,/^}$/p" "$daemon"
}
eval "$(extract_daemon_function process_actions)"
eval "$(extract_daemon_function configured_action_enabled)"

work=$(mktemp -d /tmp/zte-test-daemon-actions.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
STATE_DIR=$work/state
ACTION_RESULT_MAX_COUNT=50
host=192.168.0.1
credential_file=$work/credentials
COOKIE_FILE=$work/cookies
event_log=$work/events
execute_log=$work/execute
: >"$event_log"
: >"$execute_log"

date() { printf '%s\n' 1722345680; }
logger() { :; }
record_event() {
    printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >>"$event_log"
}
zte_read_password() { printf '%s\n' secret; }
zte_adapter_login_required() { return 0; }
zte_adapter_action_supported() { [ "$1" = switch_sim ]; }
zte_adapter_action_effectively_enabled() {
    [ "$1" = switch_sim ] && [ "$2" = 1 ] && [ "$3" = 1 ]
}
write_enabled=1
sim_switch_enabled=1
cellular_write_enabled=0
wifi_write_enabled=0
traffic_write_enabled=0
sms_write_enabled=0
zte_execute_switch_sim() {
    printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >>"$execute_log"
    printf '%s\n' ok
}

assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345678-1234 switch_sim \
    '{"action":"switch_sim","target":"sim2"}' 1722345678
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345678-1234","type":"switch_sim","state":"succeeded","code":"ok","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345678-1234)"
assert_eq \
    "192.168.0.1|secret|$COOKIE_FILE|sim2" \
    "$(cat "$execute_log")"
assert_eq 'info|action|action_succeeded|1722345680' \
    "$(cat "$event_log")"

# A queued action cannot bypass a feature flag disabled before execution.
sim_switch_enabled=0
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345679-1240 switch_sim \
    '{"action":"switch_sim","target":"sim2"}' 1722345679
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345679-1240","type":"switch_sim","state":"failed","code":"write_not_enabled","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345679-1240)"
sim_switch_enabled=1

# A valid write response without matching readback is a failed operation.
: >"$event_log"
: >"$execute_log"
zte_execute_switch_sim() {
    printf '%s\n' readback_mismatch
    return 1
}
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345681-1235 switch_sim \
    '{"action":"switch_sim","target":"physical"}' 1722345681
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345681-1235","type":"switch_sim","state":"failed","code":"readback_mismatch","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345681-1235)"
assert_eq 'error|action|action_failed|1722345680' \
    "$(cat "$event_log")"

# Missing credentials and invalid targets are terminal, non-secret failures.
zte_read_password() { return 1; }
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345682-1236 switch_sim \
    '{"action":"switch_sim","target":"sim1"}' 1722345682
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345682-1236","type":"switch_sim","state":"failed","code":"credentials_missing","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345682-1236)"

# Firmware that explicitly declares anonymous access must not require a saved
# password before invoking the calibrated executor.
: >"$execute_log"
zte_adapter_login_required() { return 1; }
zte_read_password() { printf '%s\n' stale-secret; }
zte_execute_switch_sim() {
    printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >>"$execute_log"
    printf '%s\n' ok
}
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345682-1239 switch_sim \
    '{"action":"switch_sim","target":"sim1"}' 1722345682
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345682-1239","type":"switch_sim","state":"succeeded","code":"ok","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345682-1239)"
assert_eq \
    "192.168.0.1||$COOKIE_FILE|sim1" \
    "$(cat "$execute_log")"

zte_read_password() { printf '%s\n' secret; }
zte_adapter_login_required() { return 0; }
zte_execute_switch_sim() {
    printf '%s\n' invalid_target
    return 1
}
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345683-1237 switch_sim \
    '{"action":"switch_sim","target":"invalid"}' 1722345683
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345683-1237","type":"switch_sim","state":"failed","code":"invalid_target","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345683-1237)"

# Anything outside the calibrated production capability remains unsupported.
zte_adapter_action_supported() { return 1; }
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1238 set_wifi \
    '{"action":"set_wifi","enabled":true}' 1722345684
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345684-1238","type":"set_wifi","state":"failed","code":"unsupported","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1238)"

assert_failure zte_action_has_active "$STATE_DIR"
finish
