#!/bin/sh

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

finish
