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
. "$lib/actions.sh"
# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/smart-charge-state.sh
. "$lib/smart-charge-state.sh"

assert_success zte_smart_charge_epoch_valid 2147483647
assert_failure zte_smart_charge_epoch_valid 2147483648
assert_failure zte_smart_charge_epoch_valid 9999999999

extract_daemon_function() {
    sed -n "/^$1() {$/,/^}$/p" "$daemon"
}
eval "$(extract_daemon_function apply_smart_charge_policy)"

host=192.168.0.1
work=$(mktemp -d /tmp/zte-smart-charge.XXXXXX)
STATE_DIR=$work/state
COOKIE_FILE=$work/cookies
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
smart_charge_persistence_failed=0
execute_log=$work/execute
: >"$execute_log"
trap 'rm -rf "$work"' EXIT HUP INT TERM
assert_success zte_action_init "$STATE_DIR"

load_cooldown() {
    cooldown_output=''
    if cooldown_output=$(zte_smart_charge_cooldown_load "$1" "$2"); then
        cooldown_status=0
    else
        cooldown_status=$?
    fi
}

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
assert_failure test -e "$STATE_DIR/actions/active"

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

# The automatic write and rpcd queue share one atomic exclusive slot in both
# directions. A busy slot is a stable defer state and never invokes POST.
assert_success zte_action_enqueue \
    "$STATE_DIR" op-1722345680-9000 set_power_supply_mode \
    '{"mode":"charging"}' 1722345680
assert_success apply_smart_charge_policy
assert_eq ACTION_BUSY "$policy_state"
assert_eq 'charging
direct_supply' "$(cat "$execute_log")"
zte_action_claim "$STATE_DIR" >/dev/null
assert_success zte_action_finish \
    "$STATE_DIR" op-1722345680-9000 failed unsupported 1722345681

enqueue_during_auto=$work/enqueue-during-auto
zte_execute_power_supply_mode() {
    if zte_action_enqueue \
        "$STATE_DIR" op-1722345682-9001 set_power_supply_mode \
        '{"mode":"charging"}' 1722345682; then
        printf '%s\n' allowed >"$enqueue_during_auto"
    else
        printf '%s\n' busy >"$enqueue_during_auto"
    fi
    printf '%s\n' "$4" >>"$execute_log"
    printf '%s\n' ok
}
assert_success apply_smart_charge_policy
assert_eq busy "$(cat "$enqueue_during_auto")"
assert_failure test -e "$STATE_DIR/actions/active"

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
direct_supply
direct_supply' "$(cat "$execute_log")"

# A failed/ambiguous POST enters a bounded cooldown, preventing a write storm.
zte_adapter_action_supported() { [ "$1" = set_power_supply_mode ]; }
zte_execute_power_supply_mode() {
    printf '%s\n' failed >>"$execute_log"
    printf '%s\n' write_ambiguous
    return 1
}
smart_charge_retry_after=0
assert_success apply_smart_charge_policy
assert_eq WRITE_FAILED "$policy_state"
assert_eq keep "$power_action"
assert_eq write_ambiguous "$smart_charge_last_error"
assert_eq 1722345980 "$smart_charge_retry_after"
assert_failure test -e "$STATE_DIR/actions/active"
cooldown_file=$STATE_DIR/smart-charge-cooldown
assert_eq 600 "$(test_file_mode "$cooldown_file")"
assert_eq '1722345980 write_ambiguous' "$(cat "$cooldown_file")"

# A daemon restart reloads an unexpired cooldown from tmpfs, and expiration,
# malformed data, unsafe modes, or symlinks are never trusted.
assert_eq '1722345980:write_ambiguous' \
    "$(zte_smart_charge_cooldown_load "$STATE_DIR" 1722345681)"
smart_charge_retry_after=0
loaded_cooldown=$(zte_smart_charge_cooldown_load "$STATE_DIR" 1722345681)
smart_charge_retry_after=${loaded_cooldown%%:*}
smart_charge_last_error=${loaded_cooldown#*:}
zte_execute_power_supply_mode() {
    printf '%s\n' "$4" >>"$execute_log"
    printf '%s\n' ok
}
assert_success apply_smart_charge_policy
assert_eq COOLDOWN "$policy_state"
assert_eq keep "$power_action"
assert_eq 'charging
direct_supply
direct_supply
failed' "$(cat "$execute_log")"

printf '%s\n' malformed >"$cooldown_file"
chmod 600 "$cooldown_file"
load_cooldown "$STATE_DIR" 1722345681
assert_eq 2 "$cooldown_status"
assert_success test -f "$cooldown_file"
rm -f "$cooldown_file"
printf '%s\n' '1722345980 write_ambiguous' >"$cooldown_file"
chmod 644 "$cooldown_file"
load_cooldown "$STATE_DIR" 1722345681
assert_eq 2 "$cooldown_status"
assert_success test -f "$cooldown_file"
rm -f "$cooldown_file"
printf '%s\n' '1722345980 write_ambiguous' >"$cooldown_file"
chmod 000 "$cooldown_file"
load_cooldown "$STATE_DIR" 1722345681
assert_eq 2 "$cooldown_status"
assert_success test -f "$cooldown_file"
rm -f "$cooldown_file"
printf '%s\n' '999999999999999999999 write_ambiguous' >"$cooldown_file"
chmod 600 "$cooldown_file"
load_cooldown "$STATE_DIR" 1722345681
assert_eq 2 "$cooldown_status"
assert_success test -f "$cooldown_file"
rm -f "$cooldown_file"
printf '%s\n' '1722345680 write_ambiguous' >"$cooldown_file"
chmod 600 "$cooldown_file"
load_cooldown "$STATE_DIR" 1722345681
assert_eq 1 "$cooldown_status"
assert_failure test -e "$cooldown_file"
load_cooldown "$STATE_DIR" 1722345681
assert_eq 1 "$cooldown_status"
assert_eq '' "$cooldown_output"
victim=$work/victim
printf '%s\n' untouched >"$victim"
ln -s "$victim" "$cooldown_file"
load_cooldown "$STATE_DIR" 1722345681
assert_eq 2 "$cooldown_status"
assert_eq untouched "$(cat "$victim")"
assert_success test -L "$cooldown_file"
assert_failure zte_smart_charge_cooldown_write \
    "$STATE_DIR" 1722345980 write_ambiguous
assert_eq untouched "$(cat "$victim")"
assert_success test -L "$cooldown_file"
rm -f "$cooldown_file"

# A successful action must not silently remove an unsafe cooldown object.
# Clear fails closed, latches persistence failure, and retains the evidence.
ln -s "$victim" "$cooldown_file"
smart_charge_retry_after=0
smart_charge_persistence_failed=0
assert_success apply_smart_charge_policy
assert_eq 1 "$smart_charge_persistence_failed"
assert_success test -L "$cooldown_file"
rm -f "$cooldown_file"
smart_charge_persistence_failed=0

mkdir "$cooldown_file"
assert_failure zte_smart_charge_cooldown_clear "$STATE_DIR"
assert_success test -d "$cooldown_file"
rmdir "$cooldown_file"
mkfifo "$cooldown_file"
assert_failure zte_smart_charge_cooldown_clear "$STATE_DIR"
assert_success test -p "$cooldown_file"
rm -f "$cooldown_file"

mkdir "$cooldown_file"
assert_failure zte_smart_charge_cooldown_write \
    "$STATE_DIR" 1722345980 write_ambiguous
assert_success test -d "$cooldown_file"
rmdir "$cooldown_file"

# An expired record is cleanly absent only after successful removal. If the
# unlink cannot be confirmed, load reports unsafe and leaves evidence so every
# restart continues to fail closed.
printf '%s\n' '1722345680 write_ambiguous' >"$cooldown_file"
chmod 600 "$cooldown_file"
zte_smart_charge_state_remove() { return 1; }
load_cooldown "$STATE_DIR" 1722345681
assert_eq 2 "$cooldown_status"
assert_success test -f "$cooldown_file"
rm -f "$cooldown_file"

# Persistence failure leaves an independent fail-safe latch, preventing a
# write storm even if the ordinary in-process retry timestamp is reset.
zte_smart_charge_cooldown_write() { return 1; }
zte_execute_power_supply_mode() {
    printf '%s\n' persist-failed >>"$execute_log"
    printf '%s\n' write_ambiguous
    return 1
}
smart_charge_retry_after=0
smart_charge_persistence_failed=0
assert_success apply_smart_charge_policy
assert_eq COOLDOWN_PERSIST_FAILED "$policy_state"
smart_charge_retry_after=0
assert_success apply_smart_charge_policy
assert_eq COOLDOWN_PERSIST_FAILED "$policy_state"
assert_eq 1 "$(grep -c '^persist-failed$' "$execute_log")"

finish
