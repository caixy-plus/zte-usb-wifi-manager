#!/bin/sh
set -eu

TEST_NAME=test_schedule
. ./tests/testlib.sh

schedule=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/schedule.sh
if [ ! -f "$schedule" ]; then
    fail 'schedule library must exist'
    finish
fi
# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/schedule.sh
. "$schedule"

assert_eq 0 "$(zte_schedule_time_to_minutes 00:00)"
assert_eq 480 "$(zte_schedule_time_to_minutes 08:00)"
assert_eq 1439 "$(zte_schedule_time_to_minutes 23:59)"
for value in '' 8:00 08:0 24:00 12:60 aa:bb '08:00;id'; do
    assert_failure zte_schedule_time_to_minutes "$value"
done

assert_success zte_schedule_weekday_enabled '1 2 3 4 5' 1
assert_success zte_schedule_weekday_enabled '1 2 3 4 5' 5
assert_failure zte_schedule_weekday_enabled '1 2 3 4 5' 6
assert_failure zte_schedule_weekday_enabled '1 2 x' 2
assert_failure zte_schedule_weekday_enabled '1 2 3' 0

assert_eq 0 "$(zte_schedule_pre_departure 0 '1 2 3 4 5' 18:00 90 1 1000)"
assert_eq 1 "$(zte_schedule_pre_departure 1 '1 2 3 4 5' 18:00 90 1 990)"
assert_eq 1 "$(zte_schedule_pre_departure 1 '1 2 3 4 5' 18:00 90 5 1079)"
assert_eq 0 "$(zte_schedule_pre_departure 1 '1 2 3 4 5' 18:00 90 5 1080)"
assert_eq 0 "$(zte_schedule_pre_departure 1 '1 2 3 4 5' 18:00 90 6 1000)"
assert_failure zte_schedule_pre_departure 1 '1 2 3' 01:00 90 1 30
assert_failure zte_schedule_pre_departure 1 '1 2 3' 18:00 0 1 1000
assert_failure zte_schedule_pre_departure 2 '1 2 3' 18:00 90 1 1000
assert_failure zte_schedule_pre_departure 1 '1 2 3' 18:00 90 0 1000
assert_failure zte_schedule_pre_departure 1 '1 2 3' 18:00 90 1 1440

finish
