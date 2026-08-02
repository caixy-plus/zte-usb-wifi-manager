#!/bin/sh
set -eu

TEST_NAME=test_device_profile
. ./tests/testlib.sh

profile=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/device-profile.sh
# shellcheck source=/dev/null
[ -f "$profile" ] && . "$profile"

assert_success command -v zte_device_profile_select

assert_success zte_device_profile_select 19d2 1354 'U30 Pro'
assert_eq zte_u30 "$(zte_device_profile_id)"
assert_eq 'U30 Pro' "$(zte_device_profile_model)"
assert_eq https "$(zte_device_profile_scheme)"
assert_eq 1 "$(zte_device_profile_tls_insecure)"
assert_eq 0 "$(zte_device_profile_login_required)"
assert_eq kmod-usb-net-cdc-ncm "$(zte_device_profile_driver)"

assert_success zte_device_profile_select_named zte_u25s
assert_eq zte_u25s "$(zte_device_profile_id)"
assert_eq U25S "$(zte_device_profile_model)"
assert_eq http "$(zte_device_profile_scheme)"
assert_eq 0 "$(zte_device_profile_tls_insecure)"
assert_eq 1 "$(zte_device_profile_login_required)"
assert_eq kmod-usb-net-cdc-ether "$(zte_device_profile_driver)"
assert_failure zte_device_profile_select_named unknown

assert_failure zte_device_profile_select 19d2 ffff 'U30 Pro'
assert_failure zte_device_profile_select 1234 1354 'U30 Pro'
assert_failure zte_device_profile_select 19d2 1354 'Unknown Product'
assert_failure zte_device_profile_select '19d2;touch /tmp/x' 1354 'U30 Pro'

finish
