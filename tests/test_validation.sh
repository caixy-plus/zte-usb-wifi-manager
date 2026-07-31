#!/bin/sh
set -eu

TEST_NAME=test_validation
. ./tests/testlib.sh
. ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/validation.sh

assert_success zte_validate_thresholds 70 100
assert_success zte_validate_thresholds 30 31
assert_failure zte_validate_thresholds 100 70
assert_failure zte_validate_thresholds 70 70
assert_failure zte_validate_thresholds 29 100
assert_failure zte_validate_thresholds 70 101
assert_failure zte_validate_thresholds text 100

assert_success zte_validate_host 192.168.0.1
assert_success zte_validate_host 192.168.0.1:8080
assert_failure zte_validate_host zte.local
assert_failure zte_validate_host 256.168.0.1
assert_failure zte_validate_host 192.168.0
assert_failure zte_validate_host 192.168.0.1:
assert_failure zte_validate_host 192.168.0.1:65536
assert_failure zte_validate_host ''
assert_failure zte_validate_host '192.168.0.1;reboot'
assert_failure zte_validate_host 'http://192.168.0.1/'

for name in usbwan eth2 br-lan wwan_2.1 eth0:1 radio0@wlan0; do
    assert_success zte_validate_interface "$name"
    assert_success zte_validate_netdev "$name"
done
# The dollar sign is intentionally literal unsafe input.
# shellcheck disable=SC2016
for name in '' 'usb wan' '../eth0' 'eth0;reboot' 'eth0$bad'; do
    assert_failure zte_validate_interface "$name"
    assert_failure zte_validate_netdev "$name"
done
control_name=$(printf 'eth0\nbad')
assert_failure zte_validate_interface "$control_name"
assert_failure zte_validate_netdev "$control_name"

finish
