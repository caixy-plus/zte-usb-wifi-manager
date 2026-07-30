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
        status_no_l3)
            printf '%s\n' '{"up":true}'
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
        '@.l3_device')
            [ "$_zte_test_ubus_mode" != status_no_l3 ] || return 1
            printf '%s\n' "$_zte_test_l3_device"
            ;;
        *) return 1 ;;
    esac
}

ip() {
    printf '%s\n' "$*" >>"$_zte_test_ip_calls"
    case $_zte_test_ip_mode:$* in
        ipv4:'route show default dev eth0.1')
            printf '%s\n' 'default via 192.0.2.1 dev eth0.1'
            ;;
        ipv6:'-6 route show default dev eth0.1')
            printf '%s\n' 'default via 2001:db8::1 dev eth0.1'
            ;;
        regex_neighbor:'route show default')
            printf '%s\n' 'default via 192.0.2.1 dev eth0x1 proto static'
            ;;
        *)
            return 1
            ;;
    esac
}

_zte_test_l3_device=eth2
_zte_test_ip_calls=$(mktemp /tmp/zte-test-netifd-ip.XXXXXX)
trap 'rm -f "$_zte_test_ip_calls"' EXIT HUP INT TERM
_zte_test_ip_mode=none
_zte_test_ubus_mode=status
actual=$(zte_netifd_collect wwan eth9)
assert_eq \
    '{"up":true,"l3_device":"eth2","ipv4":"","gateway":"","is_default_route":false}' \
    "$actual" \
    "missing optional netifd fields produce normalized JSON"

_zte_test_ubus_mode=fail
actual=$(zte_netifd_collect wwan eth9)
assert_eq \
    '{"up":false,"l3_device":"eth9","ipv4":"","gateway":"","is_default_route":false}' \
    "$actual" \
    "ubus failure produces a down fallback"

_zte_test_ubus_mode=empty
actual=$(zte_netifd_collect wwan eth9)
assert_eq \
    '{"up":false,"l3_device":"eth9","ipv4":"","gateway":"","is_default_route":false}' \
    "$actual" \
    "empty ubus status produces a down fallback"

_zte_test_ubus_mode=status_no_l3
actual=$(zte_netifd_collect wwan eth9)
assert_eq \
    '{"up":true,"l3_device":"eth9","ipv4":"","gateway":"","is_default_route":false}' \
    "$actual" \
    "missing l3_device uses the configured fallback"

_zte_test_ubus_mode=status
_zte_test_l3_device=eth0.1

_zte_test_ip_mode=regex_neighbor
: >"$_zte_test_ip_calls"
actual=$(zte_netifd_collect wwan eth9)
assert_eq \
    '{"up":true,"l3_device":"eth0.1","ipv4":"","gateway":"","is_default_route":false}' \
    "$actual" \
    'a regex-neighboring device name must not match the default route'

_zte_test_ip_mode=ipv4
: >"$_zte_test_ip_calls"
actual=$(zte_netifd_collect wwan eth9)
assert_eq \
    '{"up":true,"l3_device":"eth0.1","ipv4":"","gateway":"","is_default_route":true}' \
    "$actual" \
    'an exact IPv4 default route must be detected'
assert_eq 'route show default dev eth0.1' \
    "$(sed -n '1p' "$_zte_test_ip_calls")" \
    'the device must be passed as an exact ip argument'

_zte_test_ip_mode=ipv6
: >"$_zte_test_ip_calls"
actual=$(zte_netifd_collect wwan eth9)
assert_eq \
    '{"up":true,"l3_device":"eth0.1","ipv4":"","gateway":"","is_default_route":true}' \
    "$actual" \
    'an IPv6-only default route must be detected'

finish
