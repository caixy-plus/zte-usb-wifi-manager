#!/bin/sh
set -eu

TEST_NAME=netifd
. ./tests/testlib.sh
. ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/json.sh
. ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/netifd-adapter.sh

actual=$(zte_netifd_json 1 eth2 192.168.0.2 192.168.0.1 1)
assert_eq \
    '{"up":true,"l3_device":"eth2","ipv4":"192.168.0.2","gateway":"192.168.0.1","is_default_route":true}' \
    "$actual" \
    "up interface is rendered as normalized JSON"

actual=$(zte_netifd_json 0 eth2 '' '' 0)
assert_eq \
    '{"up":false,"l3_device":"eth2","ipv4":"","gateway":"","is_default_route":false}' \
    "$actual" \
    "down interface is rendered with empty addresses"

ubus() {
    case $_zte_test_ubus_mode in
        status)
            printf '%s\n' '{"up":true,"l3_device":"eth2"}'
            ;;
        empty)
            return 0
            ;;
        fail)
            return 1
            ;;
    esac
}

jsonfilter() {
    case $4 in
        '@.up') printf '%s\n' true ;;
        '@.l3_device') printf '%s\n' eth2 ;;
        *) return 1 ;;
    esac
}

ip() {
    return 1
}

_zte_test_ubus_mode=status
actual=$(zte_netifd_collect wwan)
assert_eq \
    '{"up":true,"l3_device":"eth2","ipv4":"","gateway":"","is_default_route":false}' \
    "$actual" \
    "missing optional netifd fields produce normalized JSON"

_zte_test_ubus_mode=fail
actual=$(zte_netifd_collect wwan)
assert_eq \
    '{"up":false,"l3_device":"","ipv4":"","gateway":"","is_default_route":false}' \
    "$actual" \
    "ubus failure produces a down fallback"

_zte_test_ubus_mode=empty
actual=$(zte_netifd_collect wwan)
assert_eq \
    '{"up":false,"l3_device":"","ipv4":"","gateway":"","is_default_route":false}' \
    "$actual" \
    "empty ubus status produces a down fallback"

finish
