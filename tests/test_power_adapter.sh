#!/bin/sh
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
assert_failure zte_power_apply unconfigured OFF battery_high "$record"
assert_failure zte_power_apply dry-run RESET battery_high "$record"
assert_failure zte_power_apply dry-run OFF 'battery high' "$record"

finish
