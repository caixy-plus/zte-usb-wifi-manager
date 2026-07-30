#!/bin/sh
set -eu

TEST_NAME=test_rpcd
. ./tests/testlib.sh

rpcd=./package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi
metadata=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh
work=$(mktemp -d /tmp/zte-test-rpcd.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
status_file=$work/status.json

if grep -Fq ':-/usr/lib/zte-usb-wifi-manager}' "$rpcd"; then
    pass
else
    fail 'rpcd must retain the production metadata directory default'
fi
if grep -Fq ':-/var/run/zte-usb-wifi-manager/status.json}' "$rpcd"; then
    pass
else
    fail 'rpcd must retain the production snapshot path default'
fi
assert_file_contains "$rpcd" 'adapter-zte-u25s-metadata\.sh'
if grep -q '/adapter-zte-u25s\.sh' "$rpcd"; then
    fail 'rpcd must not load the HTTP/session adapter stack'
else
    pass
fi

rpcd_call() {
    ZTE_USB_WIFI_LIB_DIR=$(dirname "$metadata") \
    ZTE_USB_WIFI_STATUS_FILE=$status_file \
        sh "$rpcd" "$@"
}

assert_json() {
    printf '%s\n' "$1" | node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => JSON.parse(input));
'
}

list_output=$(rpcd_call list)
assert_success assert_json "$list_output"
assert_eq '{"status":{},"capabilities":{}}' "$list_output" \
    'rpcd list must expose exactly the two read-only methods'

capabilities=$(rpcd_call call capabilities)
assert_success assert_json "$capabilities"
assert_eq \
    '{"adapter":"zte_u25s","model":"U25S","read_status":true,"sim_switch":false,"cellular_write":false,"wifi_write":false,"sms_write":false}' \
    "$capabilities" \
    'rpcd capabilities must come from static adapter metadata'

fallback=$(rpcd_call call status)
assert_success assert_json "$fallback"
assert_eq \
    '{"online":false,"model":"U25S","state":"framework_ready","reason":"device_polling_not_configured"}' \
    "$fallback" \
    'a missing snapshot must return framework status'

printf '%s\n' '{"online":true,"state":"ok","updated":1722345678}' >"$status_file"
status=$(rpcd_call call status)
assert_success assert_json "$status"
assert_eq '{"online":true,"state":"ok","updated":1722345678}' "$status" \
    'rpcd status must return the cached snapshot byte-for-byte'

assert_failure rpcd_call call unknown
assert_failure rpcd_call unknown

finish
