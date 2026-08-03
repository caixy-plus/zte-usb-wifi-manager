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
sms_file=$work/sms.json
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
    ZTE_USB_WIFI_SMS_FILE=$sms_file \
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
assert_eq '{"status":{},"sms_messages":{},"capabilities":{},"credential_status":{},"set_credentials":{"password":"String"},"clear_credentials":{},"operation_status":{"operation_id":"String"},"logs":{"limit":"Integer"},"cellular_action":{"action":"String","target":"String","apn":"String","pdp_type":"String","auth":"String","username":"String","password":"String","mode":"String"},"wifi_action":{"action":"String","enabled":"Boolean","band":"String","ssid":"String","security":"String","password":"String","channel":"String"},"traffic_action":{"action":"String","enabled":"Boolean","limit_bytes":"Integer","alert_percent":"Integer","cycle_day":"Integer","disconnect":"Boolean","confirm":"Boolean"},"sms_action":{"action":"String","message_id":"String","number":"String","content":"String","confirm":"Boolean"},"device_action":{"action":"String","confirm":"Boolean"},"power_action":{"action":"String","mode":"String"}}' \
    "$list_output" \
    'rpcd list must expose status, credentials, and operation status'

capabilities=$(rpcd_call call capabilities)
assert_success assert_json "$capabilities"
assert_eq false "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))')" \
    'rpcd must retain the legacy effective capability gate'
assert_eq spare_device_required "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).sim_switch?.verification)))')" \
    'rpcd must expose the static SIM calibration state'
assert_eq native_console_only "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).factory_reset?.implementation)))')" \
    'rpcd must expose native-console-only operations'

printf '%s\n' '{"online":true,"model":"U30 Pro","device":{"adapter":"zte_u30","model":"U30 Pro"}}' >"$status_file"
u30_capabilities=$(rpcd_call call capabilities)
assert_eq zte_u30 "$(printf '%s' "$u30_capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).adapter))')"
assert_eq https "$(printf '%s' "$u30_capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).transport))')"
assert_eq device_certificate_unverified "$(printf '%s' "$u30_capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).tls_verification))')"
rm -f "$status_file"

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

assert_eq '{"available":false,"reason":"not_loaded","items":[]}' \
    "$(rpcd_call call sms_messages)"
sms_cache='{"available":true,"items":[{"id":"7","number_raw":"+8600000000000","content_encoded":"0054004500530054"}]}'
printf '%s\n' "$sms_cache" >"$sms_file"
chmod 600 "$sms_file"
assert_eq "$sms_cache" "$(rpcd_call call sms_messages)" \
    'rpcd SMS method must return only the private cache'

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
chmod 644 "$credential_file"
assert_eq '{"ok":false,"error":"credential_clear_failed"}' \
    "$(rpcd_call call clear_credentials)"
assert_success test -f "$credential_file"
chmod 600 "$credential_file"
assert_eq '{"ok":true,"configured":false}' \
    "$(rpcd_call call clear_credentials)"
assert_failure test -e "$credential_file"
assert_eq '{"ok":true,"configured":false}' \
    "$(rpcd_call call clear_credentials)" \
    'clearing absent credentials must be idempotent'

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
    device_action:reboot_device \
    device_action:shutdown_device \
    power_action:set_power_supply_mode \
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
sed \
    -e 's/^ZTE_CAP_SIM_SWITCH=0$/ZTE_CAP_SIM_SWITCH=1/' \
    -e 's/^ZTE_CAP_CELLULAR_WRITE=0$/ZTE_CAP_CELLULAR_WRITE=1/' \
    -e 's/^ZTE_CAP_WIFI_WRITE=0$/ZTE_CAP_WIFI_WRITE=1/' \
    -e 's/^ZTE_CAP_TRAFFIC_WRITE=0$/ZTE_CAP_TRAFFIC_WRITE=1/' \
    -e 's/^ZTE_CAP_SMS_WRITE=0$/ZTE_CAP_SMS_WRITE=1/' \
    -e 's/^ZTE_CAP_DEVICE_REBOOT=0$/ZTE_CAP_DEVICE_REBOOT=1/' \
    -e 's/^ZTE_CAP_DEVICE_SHUTDOWN=0$/ZTE_CAP_DEVICE_SHUTDOWN=1/' \
    -e 's/^ZTE_CAP_POWER_SUPPLY_WRITE=0$/ZTE_CAP_POWER_SUPPLY_WRITE=1/' \
    "$metadata" >"$write_lib/adapter-zte-u25s-metadata.sh"
# The generated stub must expand this variable when it executes, not here.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'case "$*" in' \
    '  "-q get zte-usb-wifi-manager.main.write_enabled") value=${ZTE_TEST_WRITE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.sim_switch_enabled") value=${ZTE_TEST_SIM_SWITCH_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.cellular_write_enabled") value=${ZTE_TEST_CELLULAR_WRITE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.wifi_write_enabled") value=${ZTE_TEST_WIFI_WRITE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.traffic_write_enabled") value=${ZTE_TEST_TRAFFIC_WRITE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.sms_write_enabled") value=${ZTE_TEST_SMS_WRITE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.device_reboot_enabled") value=${ZTE_TEST_DEVICE_REBOOT_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.device_shutdown_enabled") value=${ZTE_TEST_DEVICE_SHUTDOWN_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.power_supply_write_enabled") value=${ZTE_TEST_POWER_SUPPLY_WRITE_ENABLED:-0} ;;' \
    '  *) exit 1 ;;' \
    'esac' \
    'printf "%s\n" "$value"' >"$test_bin/uci"
chmod +x "$test_bin/uci"
RPCD_TEST_LIB_DIR=$write_lib
export RPCD_TEST_LIB_DIR

effective_capabilities=$(
    ZTE_TEST_WRITE_ENABLED=1 \
    ZTE_TEST_SIM_SWITCH_ENABLED=1 \
    ZTE_TEST_WIFI_WRITE_ENABLED=0 \
        rpcd_call call capabilities
)
assert_eq true "$(printf '%s' "$effective_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))')"
assert_eq false "$(printf '%s' "$effective_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).wifi_write)))')"
independent_device_capabilities=$(
    ZTE_TEST_WRITE_ENABLED=1 \
    ZTE_TEST_DEVICE_REBOOT_ENABLED=1 \
    ZTE_TEST_DEVICE_SHUTDOWN_ENABLED=0 \
        rpcd_call call capabilities
)
assert_eq true "$(printf '%s' "$independent_device_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).device_reboot)))')"
assert_eq false "$(printf '%s' "$independent_device_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).device_shutdown)))')"
globally_disabled_capabilities=$(
    ZTE_TEST_WRITE_ENABLED=0 \
    ZTE_TEST_SIM_SWITCH_ENABLED=1 \
        rpcd_call call capabilities
)
assert_eq false "$(printf '%s' "$globally_disabled_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))')"

sim_write_disabled=$(printf '%s\n' \
    '{"action":"switch_sim","target":"sim2"}' |
    ZTE_TEST_WRITE_ENABLED=0 rpcd_call call cellular_action)
assert_eq '{"ok":false,"error":"write_not_enabled"}' "$sim_write_disabled"
sim_feature_disabled=$(printf '%s\n' \
    '{"action":"switch_sim","target":"sim2"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SIM_SWITCH_ENABLED=0 \
        rpcd_call call cellular_action)
assert_eq '{"ok":false,"error":"write_not_enabled"}' \
    "$sim_feature_disabled"
assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"switch_sim"}' |
        ZTE_TEST_WRITE_ENABLED=1 rpcd_call call cellular_action
)"
assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"switch_sim","target":"invalid"}' |
        ZTE_TEST_WRITE_ENABLED=1 rpcd_call call cellular_action
)"
sim_queued=$(printf '%s\n' \
    '{"action":"switch_sim","target":"physical"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SIM_SWITCH_ENABLED=1 \
        rpcd_call call cellular_action)
assert_success assert_json "$sim_queued"
sim_queued_id=$(zte_json_flat_get "$sim_queued" operation_id)
assert_success zte_operation_id_valid "$sim_queued_id"
assert_eq physical "$(
    zte_json_path_get \
        "$(cat "$state_dir/actions/pending/$sim_queued_id.json")" \
        payload target
)"
zte_action_claim "$state_dir" >/dev/null
assert_success zte_action_finish \
    "$state_dir" "$sim_queued_id" failed test_complete 1722345680

assert_queued_action() {
    _zte_test_reply=$1
    _zte_test_key=$2
    _zte_test_expected=$3
    assert_success assert_json "$_zte_test_reply"
    _zte_test_id=$(zte_json_flat_get "$_zte_test_reply" operation_id)
    assert_success zte_operation_id_valid "$_zte_test_id"
    _zte_test_file=$state_dir/actions/pending/$_zte_test_id.json
    assert_eq 600 "$(test_file_mode "$_zte_test_file")"
    assert_eq "$_zte_test_expected" "$(
        zte_json_path_get "$(cat "$_zte_test_file")" payload "$_zte_test_key"
    )"
    zte_action_claim "$state_dir" >/dev/null
    assert_success zte_action_finish \
        "$state_dir" "$_zte_test_id" failed test_complete 1722345680
}

apn_queued=$(printf '%s\n' \
    '{"action":"set_apn","apn":"internet","pdp_type":"ipv4v6","auth":"chap","username":"fixture-user","password":"DUMMY_QUEUE_VALUE"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_CELLULAR_WRITE_ENABLED=1 \
        rpcd_call call cellular_action)
case $apn_queued in *DUMMY_QUEUE_VALUE*) fail 'APN password leaked in RPC reply' ;; *) pass ;; esac
assert_queued_action "$apn_queued" apn internet

mode_queued=$(printf '%s\n' \
    '{"action":"set_connection_mode","mode":"automatic"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_CELLULAR_WRITE_ENABLED=1 \
        rpcd_call call cellular_action)
assert_queued_action "$mode_queued" mode automatic

wifi_queued=$(printf '%s\n' \
    '{"action":"set_wifi","enabled":true,"band":"2g","ssid":"Fixture WiFi","security":"wpa2_psk","password":"DUMMY_WIFI_VALUE","channel":"auto"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_WIFI_WRITE_ENABLED=1 \
        rpcd_call call wifi_action)
case $wifi_queued in *DUMMY_WIFI_VALUE*) fail 'Wi-Fi password leaked in RPC reply' ;; *) pass ;; esac
assert_queued_action "$wifi_queued" ssid 'Fixture WiFi'

traffic_queued=$(printf '%s\n' \
    '{"action":"set_traffic_plan","enabled":true,"limit_bytes":10737418240,"alert_percent":90,"cycle_day":1,"disconnect":false}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_TRAFFIC_WRITE_ENABLED=1 \
        rpcd_call call traffic_action)
assert_queued_action "$traffic_queued" limit_bytes 10737418240

reset_queued=$(printf '%s\n' \
    '{"action":"reset_traffic","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_TRAFFIC_WRITE_ENABLED=1 \
        rpcd_call call traffic_action)
assert_queued_action "$reset_queued" confirm true

sms_queued=$(printf '%s\n' \
    '{"action":"send_sms","number":"+12025550123","content":"runtime fixture message"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SMS_WRITE_ENABLED=1 \
        rpcd_call call sms_action)
case $sms_queued in *runtime*|*12025550123*) fail 'SMS private data leaked in RPC reply' ;; *) pass ;; esac
assert_queued_action "$sms_queued" action send_sms

delete_queued=$(printf '%s\n' \
    '{"action":"delete_sms","message_id":"42","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SMS_WRITE_ENABLED=1 \
        rpcd_call call sms_action)
assert_queued_action "$delete_queued" message_id 42

read_queued=$(printf '%s\n' \
    '{"action":"mark_sms_read","message_id":"42"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SMS_WRITE_ENABLED=1 \
        rpcd_call call sms_action)
assert_queued_action "$read_queued" message_id 42

reboot_queued=$(printf '%s\n' \
    '{"action":"reboot_device","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_DEVICE_REBOOT_ENABLED=1 \
        rpcd_call call device_action)
assert_queued_action "$reboot_queued" confirm true

shutdown_queued=$(printf '%s\n' \
    '{"action":"shutdown_device","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_DEVICE_SHUTDOWN_ENABLED=1 \
        rpcd_call call device_action)
assert_queued_action "$shutdown_queued" confirm true

unknown_field=$(printf '%s\n' \
    '{"action":"set_wifi","enabled":false,"goformId":"UNREVIEWED"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_WIFI_WRITE_ENABLED=1 \
        rpcd_call call wifi_action)
assert_eq '{"ok":false,"error":"invalid_action"}' "$unknown_field"

assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"set_wifi"}' |
        ZTE_TEST_WRITE_ENABLED=0 rpcd_call call wifi_action
)"
assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"set_wifi"}' |
        ZTE_TEST_WRITE_ENABLED=1 rpcd_call call wifi_action
)"
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
