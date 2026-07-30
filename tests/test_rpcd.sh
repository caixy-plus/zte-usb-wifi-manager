#!/bin/sh
set -eu

TEST_NAME=test_rpcd
. ./tests/testlib.sh

rpcd=./package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi
metadata=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh
work=$(mktemp -d /tmp/zte-test-rpcd.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
status_file=$work/status.json
state_dir=$work/state

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
assert_file_contains "$rpcd" 'actions\.sh'
assert_file_contains "$rpcd" 'json\.sh'
if grep -q '/adapter-zte-u25s\.sh' "$rpcd"; then
    fail 'rpcd must not load the HTTP/session adapter stack'
else
    pass
fi

rpcd_call() {
    ZTE_USB_WIFI_LIB_DIR=$(dirname "$metadata") \
    ZTE_USB_WIFI_STATUS_FILE=$status_file \
    ZTE_USB_WIFI_STATE_DIR=$state_dir \
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
assert_eq '{"status":{},"capabilities":{},"operation_status":{"operation_id":"String"},"cellular_action":{"action":"String"},"wifi_action":{"action":"String"},"traffic_action":{"action":"String"},"sms_action":{"action":"String"}}' \
    "$list_output" \
    'rpcd list must expose status, capabilities, and operation status'

capabilities=$(rpcd_call call capabilities)
assert_success assert_json "$capabilities"
assert_eq \
    '{"adapter":"zte_u25s","model":"U25S","read_status":true,"sim_switch":false,"cellular_write":false,"wifi_write":false,"traffic_write":false,"sms_write":false}' \
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

mkdir -p "$state_dir/actions/pending"
operation_id=op-1722345678-1234
operation_record='{"operation_id":"op-1722345678-1234","type":"switch_sim","state":"queued","payload":{"target":"sim1"},"created":1722345678}'
printf '%s\n' "$operation_record" \
    >"$state_dir/actions/pending/$operation_id.json"
operation_status=$(printf '{"operation_id":"%s"}\n' "$operation_id" | rpcd_call \
    call operation_status)
assert_success assert_json "$operation_status"
assert_eq "$operation_record" "$operation_status"

invalid_status=$(printf '%s\n' '{"operation_id":"../bad"}' | rpcd_call \
    call operation_status)
assert_eq '{"ok":false,"error":"invalid_operation_id"}' "$invalid_status"
missing_status=$(printf '%s\n' '{"operation_id":"op-1722345679-1235"}' | rpcd_call \
    call operation_status)
assert_eq '{"ok":false,"error":"operation_not_found"}' "$missing_status"
mkdir -p "$state_dir/actions/results"
mv "$state_dir/actions/pending/$operation_id.json" \
    "$state_dir/actions/results/$operation_id.json"

for method_action in \
    cellular_action:switch_sim \
    cellular_action:set_apn \
    cellular_action:set_connection_mode \
    wifi_action:set_wifi \
    traffic_action:set_traffic_plan \
    traffic_action:reset_traffic \
    sms_action:send_sms \
    sms_action:delete_sms \
    sms_action:mark_sms_read
do
    method=${method_action%%:*}
    action=${method_action#*:}
    reply=$(printf '{"action":"%s"}\n' "$action" | rpcd_call call "$method")
    assert_eq '{"ok":false,"error":"unsupported"}' "$reply"
done
invalid_action=$(printf '%s\n' '{"action":"reboot_device"}' | rpcd_call \
    call cellular_action)
assert_eq '{"ok":false,"error":"invalid_action"}' "$invalid_action"
wrong_method=$(printf '%s\n' '{"action":"send_sms"}' | rpcd_call \
    call wifi_action)
assert_eq '{"ok":false,"error":"invalid_action"}' "$wrong_method"
if find "$state_dir/actions/pending" -type f -name '*.json' 2>/dev/null |
    grep -q .; then
    fail 'unsupported actions must not create queue files'
else
    pass
fi

assert_failure rpcd_call call unknown
assert_failure rpcd_call unknown

finish
