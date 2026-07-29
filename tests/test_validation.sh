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
assert_success zte_validate_host zte.local
assert_failure zte_validate_host ''
assert_failure zte_validate_host '192.168.0.1;reboot'
assert_failure zte_validate_host 'http://192.168.0.1/'

finish
