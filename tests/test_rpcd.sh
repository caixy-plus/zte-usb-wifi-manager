#!/bin/sh
set -eu

TEST_NAME=test_rpcd
. ./tests/testlib.sh

rpcd=./package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi
metadata=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh
. "$(dirname "$metadata")/validation.sh"
. "$(dirname "$metadata")/json.sh"
. "$(dirname "$metadata")/actions.sh"
work=$(mktemp -d /tmp/zte-test-rpcd.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
status_file=$work/status.json
state_dir=$work/state
credential_file=$work/credentials
write_lib=$work/write-lib
test_bin=$work/bin

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
assert_file_contains "$rpcd" 'event-log\.sh'
assert_file_contains "$rpcd" 'json\.sh'
if grep -q '/adapter-zte-u25s\.sh' "$rpcd"; then
    fail 'rpcd must not load the HTTP/session adapter stack'
else
    pass
fi

rpcd_call() {
    ZTE_USB_WIFI_LIB_DIR=${RPCD_TEST_LIB_DIR:-$(dirname "$metadata")} \
    ZTE_USB_WIFI_STATUS_FILE=$status_file \
    ZTE_USB_WIFI_STATE_DIR=$state_dir \
    ZTE_USB_WIFI_CREDENTIAL_FILE=$credential_file \
    PATH="$test_bin:$PATH" \
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
assert_eq '{"status":{},"capabilities":{},"credential_status":{},"set_credentials":{"password":"String"},"operation_status":{"operation_id":"String"},"logs":{"limit":"Integer"},"cellular_action":{"action":"String"},"wifi_action":{"action":"String"},"traffic_action":{"action":"String"},"sms_action":{"action":"String"}}' \
    "$list_output" \
    'rpcd list must expose status, credentials, and operation status'

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

assert_eq '{"configured":false}' "$(rpcd_call call credential_status)"
credential_reply=$(printf '%s\n' '{"password":"PLACEHOLDER"}' |
    rpcd_call call set_credentials)
assert_eq '{"ok":true,"configured":true}' "$credential_reply"
case $credential_reply in
    *PLACEHOLDER*) fail 'credential RPC echoed the submitted password' ;;
    *) pass ;;
esac
assert_eq 600 "$(test_file_mode "$credential_file")"
assert_eq 'password=PLACEHOLDER' "$(cat "$credential_file")"
assert_eq '{"configured":true}' "$(rpcd_call call credential_status)"
assert_eq '{"ok":false,"error":"invalid_password"}' \
    "$(printf '%s\n' '{"password":""}' | rpcd_call call set_credentials)"
assert_eq '{"ok":false,"error":"invalid_password"}' \
    "$(printf '%s\n' 'not-json' | rpcd_call call set_credentials)"

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

mkdir -p "$write_lib" "$test_bin"
for library in validation.sh json.sh credentials.sh actions.sh event-log.sh; do
    ln -s "$(pwd)/package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/$library" \
        "$write_lib/$library"
done
sed 's/^ZTE_CAP_WIFI_WRITE=0$/ZTE_CAP_WIFI_WRITE=1/' \
    "$metadata" >"$write_lib/adapter-zte-u25s-metadata.sh"
# The generated stub must expand this variable when it executes, not here.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'if [ "$*" = "-q get zte-usb-wifi-manager.main.write_enabled" ]; then' \
    '    printf "%s\n" "${ZTE_TEST_WRITE_ENABLED:-0}"' \
    '    exit 0' \
    'fi' \
    'exit 1' >"$test_bin/uci"
chmod +x "$test_bin/uci"
RPCD_TEST_LIB_DIR=$write_lib
export RPCD_TEST_LIB_DIR

write_disabled=$(printf '%s\n' '{"action":"set_wifi"}' |
    ZTE_TEST_WRITE_ENABLED=0 rpcd_call call wifi_action)
assert_eq '{"ok":false,"error":"write_not_enabled"}' "$write_disabled"
queued=$(printf '%s\n' '{"action":"set_wifi"}' |
    ZTE_TEST_WRITE_ENABLED=1 rpcd_call call wifi_action)
assert_success assert_json "$queued"
case $queued in
    '{"ok":true,"operation_id":"op-'*',"state":"queued"}') pass ;;
    *) fail "supported write did not return a queued operation: $queued" ;;
esac
queued_id=$(zte_json_flat_get "$queued" operation_id)
assert_success zte_operation_id_valid "$queued_id"
assert_success test -f "$state_dir/actions/pending/$queued_id.json"
assert_eq 600 \
    "$(test_file_mode "$state_dir/actions/pending/$queued_id.json")"
busy=$(printf '%s\n' '{"action":"set_wifi"}' |
    ZTE_TEST_WRITE_ENABLED=1 rpcd_call call wifi_action)
assert_eq '{"ok":false,"error":"operation_busy"}' "$busy"
RPCD_TEST_LIB_DIR=$(dirname "$metadata")
export RPCD_TEST_LIB_DIR

assert_eq '{"events":[]}' "$(printf '%s\n' '{"limit":20}' | rpcd_call call logs)"
mkdir -p "$state_dir/logs"
printf '%s\n' \
    '{"time":1722345678,"level":"info","type":"service","code":"service_started"}' \
    >"$state_dir/logs/events.jsonl"
logs=$(printf '%s\n' '{"limit":1}' | rpcd_call call logs)
assert_eq \
    '{"events":[{"time":1722345678,"level":"info","type":"service","code":"service_started"}]}' \
    "$logs"
assert_eq '{"ok":false,"error":"invalid_limit"}' \
    "$(printf '%s\n' '{"limit":0}' | rpcd_call call logs)"
assert_eq '{"ok":false,"error":"invalid_limit"}' \
    "$(printf '%s\n' '{"limit":201}' | rpcd_call call logs)"

assert_failure rpcd_call call unknown
assert_failure rpcd_call unknown

finish
