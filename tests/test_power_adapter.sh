#!/bin/sh
# shellcheck disable=SC2317,SC2329
set -eu

TEST_NAME=test_power_adapter
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
power_adapter=$lib/power-adapter.sh
if [ ! -f "$power_adapter" ]; then
    fail 'power adapter library must exist'
    finish
fi
# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/power-adapter.sh
. "$power_adapter"

work=$(mktemp -d /tmp/zte-test-power-adapter.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
record=$work/power.json

for backend in unconfigured mock dry-run hardware; do
    assert_success zte_power_backend_valid "$backend"
done
for backend in '' gpio usb-authorize '../mock'; do
    assert_failure zte_power_backend_valid "$backend"
done
for action in ON OFF KEEP; do
    assert_success zte_power_action_valid "$action"
done
for action in '' on RESET '../OFF'; do
    assert_failure zte_power_action_valid "$action"
done
for reason in \
    battery_low battery_high manual_full pre_departure fail_safe disabled no_change
do
    assert_success zte_power_reason_valid "$reason"
done
assert_failure zte_power_reason_valid 'battery high'

assert_success zte_power_board_supported 'cudy,tr3000-v1'
for board in '' 'cudy,tr3000' 'cudy,tr3000-v1;reboot' '../tr3000'; do
    assert_failure zte_power_board_supported "$board"
done
assert_success zte_power_control_path_valid \
    '/sys/class/gpio/modem_power/value'
for path in \
    '' '/sys/class/gpio/modem_power/direction' \
    '/sys/class/gpio/modem_power/value/../direction' "$work/value"
do
    assert_failure zte_power_control_path_valid "$path"
done
assert_success zte_power_calibrated_flag_valid 0
assert_success zte_power_calibrated_flag_valid 1
assert_failure zte_power_calibrated_flag_valid ''
assert_failure zte_power_calibrated_flag_valid 2

mock_result=$(zte_power_apply mock ON battery_low "$record")
assert_eq \
    '{"backend":"mock","action":"ON","executed":true,"reason":"battery_low"}' \
    "$mock_result"
assert_eq "$mock_result" "$(cat "$record")"
assert_eq 600 "$(test_file_mode "$record")"

dry_run_result=$(zte_power_apply dry-run OFF battery_high "$record")
assert_eq \
    '{"backend":"dry-run","action":"OFF","executed":false,"reason":"battery_high"}' \
    "$dry_run_result"
assert_eq "$dry_run_result" "$(cat "$record")"

keep_result=$(zte_power_apply hardware KEEP no_change "$record")
assert_eq \
    '{"backend":"hardware","action":"KEEP","executed":false,"reason":"no_change"}' \
    "$keep_result"
assert_eq "$keep_result" "$(cat "$record")"

assert_failure zte_power_apply hardware ON battery_low "$record"
assert_eq "$keep_result" "$(cat "$record")"

# Hardware writes are accepted only for the exact calibrated TR3000 export.
# Override the I/O boundary so this behavior test never touches host sysfs.
hardware_state=$work/hardware-state
hardware_calls=$work/hardware-calls
printf '1\n' >"$hardware_state"
: >"$hardware_calls"
zte_power_sysfs_write() {
    printf '%s:%s\n' "$1" "$2" >>"$hardware_calls"
    printf '%s\n' "$2" >"$hardware_state"
}
zte_power_sysfs_read() {
    cat "$hardware_state"
}

hardware_off_result=$(zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1' 1)
assert_eq \
    '{"backend":"hardware","action":"OFF","executed":true,"reason":"battery_high"}' \
    "$hardware_off_result"
assert_eq \
    '/sys/class/gpio/modem_power/value:0' \
    "$(tail -n 1 "$hardware_calls")"
assert_eq 0 "$(cat "$hardware_state")"

hardware_on_result=$(zte_power_apply \
    hardware ON fail_safe "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1' 0)
assert_eq \
    '{"backend":"hardware","action":"ON","executed":true,"reason":"fail_safe"}' \
    "$hardware_on_result"
assert_eq \
    '/sys/class/gpio/modem_power/value:1' \
    "$(tail -n 1 "$hardware_calls")"
assert_eq 1 "$(cat "$hardware_state")"

assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 0 'cudy,tr3000-v1'
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1' 0
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v2' 1
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    "$work/value" 1 'cudy,tr3000-v1' 1
assert_eq "$hardware_on_result" "$(cat "$record")"

zte_power_sysfs_read() {
    printf '1\n'
}
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1' 1
assert_eq "$hardware_on_result" "$(cat "$record")"

zte_power_sysfs_write() {
    return 1
}
assert_failure zte_power_apply \
    hardware ON fail_safe "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1'
assert_eq "$hardware_on_result" "$(cat "$record")"

assert_failure zte_power_apply unconfigured OFF battery_high "$record"
assert_failure zte_power_apply dry-run RESET battery_high "$record"
assert_failure zte_power_apply dry-run OFF 'battery high' "$record"

finish
