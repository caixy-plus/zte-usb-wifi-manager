#!/bin/sh
# shellcheck disable=SC2034,SC2218,SC2317,SC2329
set -eu

TEST_NAME=test_daemon_smart_charge
. ./tests/testlib.sh

backend=./package/zte-usb-wifi-manager
daemon=$backend/files/usr/sbin/zte-usb-wifi-managerd
lib=$backend/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/smart-charge-policy.sh"

extract_daemon_function() {
    sed -n "/^$1() {$/,/^}$/p" "$daemon"
}
eval "$(extract_daemon_function apply_smart_charge_policy)"

host=192.168.0.1
COOKIE_FILE=/tmp/zte-smart-charge-cookie
battery_enabled=1
battery_low=30
battery_high=80
write_enabled=1
power_supply_write_enabled=1
smart_charge_retry_after=0
SMART_CHARGE_RETRY_SECONDS=300
ZTE_ADAPTER_ID=zte_u30
policy_state=''
power_action=''
smart_charge_last_error=''
execute_log=$(mktemp /tmp/zte-smart-charge-execute.XXXXXX)
trap 'rm -f "$execute_log"' EXIT HUP INT TERM

date() { printf '%s\n' 1722345680; }
logger() { :; }
record_event() { :; }
zte_adapter_action_supported() { [ "$1" = set_power_supply_mode ]; }
configured_action_enabled() { [ "$1" = set_power_supply_mode ]; }
zte_execute_power_supply_mode() {
    printf '%s\n' "$4" >>"$execute_log"
    printf '%s\n' ok
}

device_json='{"battery":{"percent":25},"power_supply":{"mode_raw":"1","direct_supply":true}}'
assert_success apply_smart_charge_policy
assert_eq BATTERY_LOW "$policy_state"
assert_eq charging "$power_action"
assert_eq charging "$(cat "$execute_log")"

# A mode already matching the policy is a read-only no-op.
device_json='{"battery":{"percent":25},"power_supply":{"mode_raw":"0","direct_supply":false}}'
assert_success apply_smart_charge_policy
assert_eq BATTERY_LOW "$policy_state"
assert_eq keep "$power_action"
assert_eq charging "$(cat "$execute_log")"

# High battery selects direct supply and never touches USB VBUS control.
device_json='{"battery":{"percent":85},"power_supply":{"mode_raw":"0","direct_supply":false}}'
assert_success apply_smart_charge_policy
assert_eq BATTERY_HIGH "$policy_state"
assert_eq direct_supply "$power_action"
assert_eq 'charging
direct_supply' "$(cat "$execute_log")"

# Disabled automation, missing state, unsupported profiles and closed gates
# must preserve the current device mode without invoking the executor.
battery_enabled=0
assert_success apply_smart_charge_policy
assert_eq DISABLED "$policy_state"
assert_eq keep "$power_action"
battery_enabled=1
device_json='{"battery":{"percent":null},"power_supply":{"mode_raw":null,"direct_supply":null}}'
assert_success apply_smart_charge_policy
assert_eq STATE_UNKNOWN "$policy_state"
assert_eq keep "$power_action"
ZTE_ADAPTER_ID=zte_u25s
assert_success apply_smart_charge_policy
assert_eq UNSUPPORTED_DEVICE "$policy_state"
assert_eq keep "$power_action"
ZTE_ADAPTER_ID=zte_u30
zte_adapter_action_supported() { return 1; }
device_json='{"battery":{"percent":85},"power_supply":{"mode_raw":"0","direct_supply":false}}'
assert_success apply_smart_charge_policy
assert_eq AWAITING_CALIBRATION "$policy_state"
assert_eq keep "$power_action"
assert_eq 'charging
direct_supply' "$(cat "$execute_log")"

# A failed/ambiguous POST enters a bounded cooldown, preventing a write storm.
zte_adapter_action_supported() { [ "$1" = set_power_supply_mode ]; }
zte_execute_power_supply_mode() { printf '%s\n' write_ambiguous; return 1; }
smart_charge_retry_after=0
assert_success apply_smart_charge_policy
assert_eq WRITE_FAILED "$policy_state"
assert_eq keep "$power_action"
assert_eq write_ambiguous "$smart_charge_last_error"
assert_eq 1722345980 "$smart_charge_retry_after"
zte_execute_power_supply_mode() {
    printf '%s\n' "$4" >>"$execute_log"
    printf '%s\n' ok
}
assert_success apply_smart_charge_policy
assert_eq COOLDOWN "$policy_state"
assert_eq keep "$power_action"
assert_eq 'charging
direct_supply' "$(cat "$execute_log")"

finish
