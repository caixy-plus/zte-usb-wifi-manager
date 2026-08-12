#!/bin/sh
# Production profile orchestration is extracted with eval and consumes these
# test globals indirectly.
# shellcheck disable=SC2034,SC2154,SC2329
set -eu

TEST_NAME=test_daemon_profile
. ./tests/testlib.sh

backend=./package/zte-usb-wifi-manager
daemon=$backend/files/usr/sbin/zte-usb-wifi-managerd
lib=$backend/files/usr/lib/zte-usb-wifi-manager

. "$lib/validation.sh"
. "$lib/http.sh"
. "$lib/device-profile.sh"
. "$lib/adapter-zte-u25s-metadata.sh"

extract_daemon_function() {
    sed -n "/^$1() {$/,/^}$/p" "$daemon"
}

eval "$(extract_daemon_function device_profile_still_valid)"
eval "$(extract_daemon_function configure_device_profile)"

logger() { :; }

work=$(mktemp -d /tmp/zte-test-daemon-profile.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
sysfs=$work/sys/bus/usb/devices
netfs=$work/sys/class/net
mkdir -p "$sysfs/1-1/1-1:1.0" "$netfs/eth2"
ln -s ../../../bus/usb/devices/1-1/1-1:1.0 "$netfs/eth2/device"

write_identity() {
    printf '%s\n' "$1" >"$sysfs/1-1/idVendor"
    printf '%s\n' "$2" >"$sysfs/1-1/idProduct"
    printf '%s\n' "$3" >"$sysfs/1-1/product"
}

host=192.168.0.1
netdev=eth2
ZTE_SYS_CLASS_NET_ROOT=$netfs
adapter=auto
write_identity 19d2 1354 'U30 Pro'
assert_success configure_device_profile
assert_eq zte_u30 "$ZTE_ADAPTER_ID"
assert_eq 'U30 Pro' "$ZTE_ADAPTER_MODEL"
assert_eq 'https://192.168.0.1' "$ZTE_DEVICE_ORIGIN"

write_identity 19d2 1354 'Unknown Product'
adapter=auto
assert_failure configure_device_profile

adapter=zte_u30
assert_failure configure_device_profile \
    'an explicit profile must not bypass exact USB identity verification'

# An unrelated U30 elsewhere on the USB bus must not authorize eth2.
mkdir -p "$sysfs/2-1"
printf '%s\n' 19d2 >"$sysfs/2-1/idVendor"
printf '%s\n' 1354 >"$sysfs/2-1/idProduct"
printf '%s\n' 'U30 Pro' >"$sysfs/2-1/product"
adapter=auto
assert_failure configure_device_profile

rm -rf "$sysfs/1-1"
adapter=auto
assert_failure configure_device_profile
adapter=zte_u30
assert_failure configure_device_profile \
    'an explicit profile must also fail when the bound identity disappears'

finish
