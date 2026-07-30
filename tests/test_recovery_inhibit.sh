#!/bin/sh
set -eu

TEST_NAME=test_recovery_inhibit
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
inhibit_lib=$lib/recovery-inhibit.sh
if [ ! -f "$inhibit_lib" ]; then
    fail 'recovery inhibit library must exist'
    finish
fi
. "$lib/validation.sh"
. "$lib/json.sh"
# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/recovery-inhibit.sh
. "$inhibit_lib"

work=$(mktemp -d /tmp/zte-test-recovery-inhibit.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
inhibit=$work/recovery-inhibit.json

for reason in scheduled_power_off manual_power_off battery_high; do
    assert_success zte_recovery_reason_valid "$reason"
done
assert_failure zte_recovery_reason_valid ''
assert_failure zte_recovery_reason_valid '../power_off'

assert_success zte_recovery_inhibit_write \
    "$inhibit" battery_high 1722346000 1722345678
assert_eq 600 "$(test_file_mode "$inhibit")"
assert_eq \
    '{"reason":"battery_high","created":1722345678,"expires":1722346000}' \
    "$(cat "$inhibit")"
assert_success zte_recovery_inhibit_active "$inhibit" 1722345999
assert_failure zte_recovery_inhibit_active "$inhibit" 1722346000
assert_failure zte_recovery_inhibit_active "$inhibit" 1722346001
assert_failure zte_recovery_inhibit_write \
    "$inhibit" battery_high 1722345678 1722345678
assert_failure zte_recovery_inhibit_write \
    "$inhibit" 'bad reason' 1722346000 1722345678

assert_success zte_recovery_inhibit_clear "$inhibit"
assert_failure test -e "$inhibit"
assert_success zte_recovery_inhibit_clear "$inhibit"

finish
