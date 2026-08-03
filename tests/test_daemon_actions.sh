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
. "$lib/http.sh"
. "$lib/device-profile.sh"
. "$lib/adapter-zte-u25s-metadata.sh"

extract_daemon_function() {
    sed -n "/^$1() {$/,/^}$/p" "$daemon"
}
eval "$(extract_daemon_function process_actions)"
eval "$(extract_daemon_function configured_action_enabled)"
eval "$(extract_daemon_function configure_device_profile)"
eval "$(extract_daemon_function collect_private_clients)"
eval "$(extract_daemon_function collect_private_sms)"

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

mkdir -p "$work/sys/1-1"
printf '%s\n' 19d2 >"$work/sys/1-1/idVendor"
printf '%s\n' 1354 >"$work/sys/1-1/idProduct"
printf '%s\n' 'U30 Pro' >"$work/sys/1-1/product"
adapter=auto
host=192.168.0.1
ZTE_USB_SYSFS_ROOT=$work/sys
profile_error=''
clients_json=''
sms_json=''
assert_success configure_device_profile
assert_eq zte_u30 "$ZTE_ADAPTER_ID"
assert_eq 'U30 Pro' "$ZTE_ADAPTER_MODEL"
assert_eq 'https://192.168.0.1' "$ZTE_DEVICE_ORIGIN"
assert_eq 1 "$ZTE_DEVICE_TLS_INSECURE"
assert_eq 0 "$ZTE_LOGIN_REQUIRED"
adapter=unknown
assert_failure configure_device_profile
assert_eq unsupported_device "$profile_error"
adapter=zte_u25s
assert_success configure_device_profile
assert_eq 'http://192.168.0.1' "$ZTE_DEVICE_ORIGIN"

private_auth_retry_after=0
next_sms_poll_at=0
PRIVATE_AUTH_BACKOFF_SECONDS=900
SMS_POLL_INTERVAL_SECONDS=300
COOKIE_FILE=$work/profile-cookies
zte_adapter_clients_unavailable_json() {
    printf '{"available":false,"reason":"%s","items":[]}\n' "$1"
}
zte_adapter_sms_unavailable_json() {
    printf '{"available":false,"reason":"%s","items":[]}\n' "$1"
}
zte_adapter_login_required() { return 1; }
zte_adapter_fetch_clients() {
    [ -z "$2" ] || return 1
    printf '%s\n' '{"available":true,"items":[]}'
}
zte_adapter_fetch_sms() {
    [ -z "$2" ] || return 1
    printf '%s\n' '{"available":true,"items":[]}'
}
assert_success collect_private_clients 100 ''
assert_eq '{"available":true,"items":[]}' "$clients_json"
assert_success collect_private_sms 100 ''
assert_eq '{"available":true,"items":[]}' "$sms_json"

zte_adapter_login_required() { return 0; }
assert_success collect_private_clients 101 ''
assert_eq '{"available":false,"reason":"credentials_missing","items":[]}' "$clients_json"

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
    '{"action":"switch_sim","target":"sim2","confirm":true}' 1722345678
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
    '{"action":"switch_sim","target":"sim2","confirm":true}' 1722345679
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
    '{"action":"switch_sim","target":"physical","confirm":true}' 1722345681
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
    '{"action":"switch_sim","target":"sim1","confirm":true}' 1722345682
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
    '{"action":"switch_sim","target":"sim1","confirm":true}' 1722345682
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
    '{"action":"switch_sim","target":"invalid","confirm":true}' 1722345683
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345683-1237","type":"switch_sim","state":"failed","code":"invalid_action","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345683-1237)"

# Source-reviewed U30 non-destructive settings share the same queue, feature
# gate and result-record discipline as the calibrated power action.
zte_adapter_action_supported() {
    case $1 in
        set_apn|set_connection_mode|set_wifi|set_traffic_plan|reset_traffic|send_sms|delete_sms|reboot_device)
            return 0
            ;;
    esac
    return 1
}
zte_adapter_action_effectively_enabled() {
    zte_adapter_action_supported "$1" && [ "$2" = 1 ] && [ "$3" = 1 ]
}
cellular_write_enabled=1
traffic_write_enabled=1
sms_write_enabled=1
device_reboot_enabled=1
zte_execute_u30_setting() {
    printf '%s|%s|%s|%s\n' "$1" "$3" "$4" "$5" >>"$execute_log"
    printf '%s\n' ok
}
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1241 set_connection_mode \
    '{"action":"set_connection_mode","mode":"automatic"}' 1722345684
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345684-1241","type":"set_connection_mode","state":"succeeded","code":"ok","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1241)"
case $(tail -n 1 "$execute_log") in
    192.168.0.1\|*\|set_connection_mode\|*'"mode":"automatic"'*) pass ;;
    *) fail 'daemon did not pass the validated queued setting to the executor' ;;
esac
# Revalidate the exact queued payload at execution time. A tampered record or
# a destructive action without its confirmation must never reach an executor.
execute_count=$(wc -l <"$execute_log" | tr -d ' ')
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1247 set_connection_mode \
    '{"action":"set_connection_mode","mode":"automatic","extra":"raw"}' 1722345684
assert_success process_actions
assert_eq invalid_action "$(zte_json_top_get \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1247)" code)"
assert_eq "$execute_count" "$(wc -l <"$execute_log" | tr -d ' ')"
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1248 reset_traffic \
    '{"action":"reset_traffic"}' 1722345684
assert_success process_actions
assert_eq invalid_action "$(zte_json_top_get \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1248)" code)"
assert_eq "$execute_count" "$(wc -l <"$execute_log" | tr -d ' ')"
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1246 set_apn \
    '{"action":"set_apn","apn":"fixture","auth":"none"}' 1722345684
assert_success process_actions
assert_eq succeeded "$(zte_json_top_get \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1246)" state)"
wifi_write_enabled=1
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1245 set_wifi \
    '{"action":"set_wifi","enabled":false}' 1722345684
assert_success process_actions
assert_eq succeeded "$(zte_json_top_get \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1245)" state)"
zte_execute_u30_sms_action() { printf '%s\n' ok; }
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1244 send_sms \
    '{"action":"send_sms","number":"+12025550123","content":"fixture"}' 1722345684
assert_success process_actions
assert_eq succeeded "$(zte_json_top_get \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1244)" state)"
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1242 delete_sms \
    '{"action":"delete_sms","message_id":"42","confirm":true}' 1722345684
assert_success process_actions
assert_eq succeeded "$(zte_json_top_get \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1242)" state)"
zte_execute_u30_device_action() { printf '%s\n' ok; }
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1243 reboot_device \
    '{"action":"reboot_device","confirm":true}' 1722345684
assert_success process_actions
assert_eq succeeded "$(zte_json_top_get \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1243)" state)"

# Anything outside the calibrated production capability remains unsupported.
zte_adapter_action_supported() { return 1; }
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345684-1238 shutdown_device \
    '{"action":"shutdown_device","confirm":true}' 1722345684
assert_success process_actions
assert_eq \
    '{"operation_id":"op-1722345684-1238","type":"shutdown_device","state":"failed","code":"unsupported","updated":1722345680}' \
    "$(zte_action_get "$STATE_DIR" op-1722345684-1238)"

assert_failure zte_action_has_active "$STATE_DIR"
finish
