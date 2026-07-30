#!/bin/sh
set -eu
TEST_NAME=test_snapshot
. ./tests/testlib.sh
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/json.sh"
. "$lib/snapshot.sh"

assert_eq '0:ok' "$(zte_failures_next 2 1 3)"
assert_eq '1:degraded' "$(zte_failures_next 0 0 3)"
assert_eq '2:degraded' "$(zte_failures_next 1 0 3)"
assert_eq '3:fail_safe' "$(zte_failures_next 2 0 3)"

assert_eq 30 "$(zte_backoff_interval 30 0)"
assert_eq 60 "$(zte_backoff_interval 30 1)"
assert_eq 120 "$(zte_backoff_interval 30 2)"
assert_eq 240 "$(zte_backoff_interval 30 3)"
assert_eq 300 "$(zte_backoff_interval 30 4)"
assert_eq 300 "$(zte_backoff_interval 30 999999999999999999999999)"
assert_eq 300 "$(zte_backoff_interval 999999999999999999999999 0)"
assert_failure zte_backoff_interval invalid 1

dev='{"online":true,"model":"U25S","battery":{"present":true,"percent":82,"charging":false}}'
net='{"up":true,"l3_device":"eth2","ipv4":"192.168.0.2","gateway":"192.168.0.1","is_default_route":true}'
assert_eq "$dev" "$(zte_device_retain '' "$dev" 1)"
assert_eq "$dev" "$(zte_device_retain "$dev" '' 0)"
assert_eq "$dev" "$(zte_device_retain "$dev" '{"partial":true}' 0)"
assert_eq '' "$(zte_device_retain '' '' 0)"
assert_eq '{"online":true,"model":"U25S","state":"ok","reason":"","device":'"$dev"',"network":'"$net"',"policy":{"state":"DISABLED","power_action":"KEEP"},"failures":0,"updated":1722345678}' \
    "$(zte_snapshot_compose ok '' "$dev" "$net" DISABLED KEEP 0 1722345678)"
assert_eq '{"online":false,"model":"U25S","state":"degraded","reason":"device_read_failed","device":'"$dev"',"network":'"$net"',"policy":{"state":"unavailable","power_action":"none"},"failures":1,"updated":1722345679}' \
    "$(zte_snapshot_compose degraded device_read_failed "$dev" "$net" unavailable none 1 1722345679)"
assert_eq '{"online":false,"model":"U25S","state":"fail_safe","reason":"device_read_threshold_reached","device":null,"network":null,"policy":{"state":"unavailable","power_action":"none"},"failures":3,"updated":1722345679}' \
    "$(zte_snapshot_compose fail_safe device_read_threshold_reached '' '' unavailable none 3 1722345679)"
finish
