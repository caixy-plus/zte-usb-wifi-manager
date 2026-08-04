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
    ZTE_USB_WIFI_SERVICE_INIT=${RPCD_TEST_SERVICE_INIT:-/etc/init.d/zte-usb-wifi-manager} \
    ZTE_TEST_RELOAD_LOG=${ZTE_TEST_RELOAD_LOG:-$work/reload-default} \
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
assert_eq '{"status":{},"sms_messages":{},"capabilities":{},"charging_settings":{},"set_charging_settings":{"enabled":"Boolean","low_percent":"Integer","high_percent":"Integer"},"credential_status":{},"set_credentials":{"password":"String"},"clear_credentials":{},"operation_status":{"operation_id":"String"},"logs":{"limit":"Integer"},"cellular_action":{"action":"String","target":"String","confirm":"Boolean","apn":"String","auth":"String","username":"String","password":"String","mode":"String"},"wifi_action":{"action":"String","enabled":"Boolean","band":"String","ssid":"String","security":"String","password":"String","channel":"String"},"traffic_action":{"action":"String","enabled":"Boolean","limit_bytes":"Integer","alert_percent":"Integer","cycle_day":"Integer","disconnect":"Boolean","confirm":"Boolean"},"sms_action":{"action":"String","message_id":"String","number":"String","content":"String","confirm":"Boolean"},"device_action":{"action":"String","confirm":"Boolean"},"power_action":{"action":"String","mode":"String"}}' \
    "$list_output" \
    'rpcd list must expose status, credentials, and operation status'

capabilities=$(rpcd_call call capabilities)
assert_success assert_json "$capabilities"
assert_eq false "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))')" \
    'rpcd must retain the legacy effective capability gate'
assert_eq unknown "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).adapter))')"
assert_eq Unavailable "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).model))')"
assert_eq unsupported "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).switch_sim?.implementation)))')" \
    'rpcd must not infer a device profile when no trusted status exists'
assert_eq not_applicable "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).switch_sim?.verification)))')"
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
chmod 600 "$state_dir/actions/pending/$operation_id.json"
operation_status=$(printf '{"operation_id":"%s"}\n' "$operation_id" | rpcd_call \
    call operation_status)
assert_success assert_json "$operation_status"
assert_eq \
    '{"operation_id":"op-1722345678-1234","type":"switch_sim","state":"queued","created":1722345678}' \
    "$operation_status"

# Public operation status is deliberately narrower than the private queue
# record. Predicting an operation ID must not disclose action parameters.
secret_index=0
for secret_case in \
    'set_apn|{"action":"set_apn","apn":"secret-apn","auth":"chap","username":"secret-user","password":"DUMMY_APN_PASSWORD"}' \
    'set_wifi|{"action":"set_wifi","enabled":true,"band":"2g","ssid":"secret-ssid","security":"wpa2_psk","password":"DUMMY_WIFI_PASSWORD","channel":"auto"}' \
    'send_sms|{"action":"send_sms","number":"+12025550999","content":"DUMMY_SMS_CONTENT"}' \
    'delete_sms|{"action":"delete_sms","message_id":"DUMMY_MESSAGE_ID","confirm":true}'
do
    secret_type=${secret_case%%|*}
    secret_payload=${secret_case#*|}
    secret_id=op-1722345678-$((2000 + secret_index))
    secret_index=$((secret_index + 1))
    printf '{"operation_id":"%s","type":"%s","state":"queued","payload":%s,"created":1722345678}\n' \
        "$secret_id" "$secret_type" "$secret_payload" \
        >"$state_dir/actions/pending/$secret_id.json"
    chmod 600 "$state_dir/actions/pending/$secret_id.json"
    secret_status=$(printf '{"operation_id":"%s"}\n' "$secret_id" |
        rpcd_call call operation_status)
    assert_eq \
        "{\"operation_id\":\"$secret_id\",\"type\":\"$secret_type\",\"state\":\"queued\",\"created\":1722345678}" \
        "$secret_status"
    case $secret_status in
        *payload*|*DUMMY*|*secret-apn*|*secret-user*|*secret-ssid*|*12025550999*)
            fail "operation_status leaked private $secret_type payload"
            ;;
        *) pass ;;
    esac
    rm -f "$state_dir/actions/pending/$secret_id.json"
done

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
# Transaction mechanics have a dedicated stateful suite. This rpcd suite uses
# a narrow result stub to verify request validation and public error mapping.
# The generated stub expands this variable when it executes, not here.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'zte_charging_transaction_apply() {' \
    '  printf "%s\n" "${ZTE_TEST_CHARGING_TX_RESULT:-ok}"' \
    '}' >"$write_lib/charging-transaction.sh"
sed \
    -e 's/^ZTE_CAP_SWITCH_SIM=0$/ZTE_CAP_SWITCH_SIM=1/' \
    -e 's/^ZTE_CAP_SET_APN=0$/ZTE_CAP_SET_APN=1/' \
    -e 's/^ZTE_CAP_SET_CONNECTION_MODE=0$/ZTE_CAP_SET_CONNECTION_MODE=1/' \
    -e 's/^ZTE_CAP_SET_WIFI=0$/ZTE_CAP_SET_WIFI=1/' \
    -e 's/^ZTE_CAP_SET_TRAFFIC_PLAN=0$/ZTE_CAP_SET_TRAFFIC_PLAN=1/' \
    -e 's/^ZTE_CAP_RESET_TRAFFIC=0$/ZTE_CAP_RESET_TRAFFIC=1/' \
    -e 's/^ZTE_CAP_SEND_SMS=0$/ZTE_CAP_SEND_SMS=1/' \
    -e 's/^ZTE_CAP_DELETE_SMS=0$/ZTE_CAP_DELETE_SMS=1/' \
    -e 's/^ZTE_CAP_MARK_SMS_READ=0$/ZTE_CAP_MARK_SMS_READ=1/' \
    -e 's/^ZTE_CAP_REBOOT_DEVICE=0$/ZTE_CAP_REBOOT_DEVICE=1/' \
    -e 's/^ZTE_CAP_SHUTDOWN_DEVICE=0$/ZTE_CAP_SHUTDOWN_DEVICE=1/' \
    -e 's/^ZTE_CAP_SET_POWER_SUPPLY_MODE=0$/ZTE_CAP_SET_POWER_SUPPLY_MODE=1/' \
    -e 's/^ZTE_U30_CAP_SWITCH_SIM=0$/ZTE_U30_CAP_SWITCH_SIM=1/' \
    -e 's/^ZTE_U30_CAP_SET_WIFI=0$/ZTE_U30_CAP_SET_WIFI=1/' \
    "$metadata" >"$write_lib/adapter-zte-u25s-metadata.sh"
# The generated stub must expand this variable when it executes, not here.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'log_mutation() {' \
    '  printf "%s\n" "$*" >>"${ZTE_TEST_UCI_LOG:?}"' \
    '  mutation_count=$(wc -l <"${ZTE_TEST_UCI_LOG}" | tr -d " ")' \
    '  [ "$mutation_count" != "${ZTE_TEST_UCI_FAIL_AT:-0}" ]' \
    '}' \
    'case "$*" in' \
    '  "-q get zte-usb-wifi-manager.main.write_enabled") value=${ZTE_TEST_WRITE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.switch_sim_enabled") value=${ZTE_TEST_SWITCH_SIM_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.cellular_write_enabled") value=${ZTE_TEST_CELLULAR_WRITE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.set_wifi_enabled") value=${ZTE_TEST_SET_WIFI_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.set_traffic_plan_enabled") value=${ZTE_TEST_SET_TRAFFIC_PLAN_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.reset_traffic_enabled") value=${ZTE_TEST_RESET_TRAFFIC_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.send_sms_enabled") value=${ZTE_TEST_SEND_SMS_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.delete_sms_enabled") value=${ZTE_TEST_DELETE_SMS_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.mark_sms_read_enabled") value=${ZTE_TEST_MARK_SMS_READ_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.reboot_device_enabled") value=${ZTE_TEST_REBOOT_DEVICE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.shutdown_device_enabled") value=${ZTE_TEST_SHUTDOWN_DEVICE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.set_power_supply_mode_enabled") value=${ZTE_TEST_SET_POWER_SUPPLY_MODE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.set_apn_enabled") value=${ZTE_TEST_SET_APN_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.writes.set_connection_mode_enabled") value=${ZTE_TEST_SET_CONNECTION_MODE_ENABLED:-0} ;;' \
    '  "-q get zte-usb-wifi-manager.charging.enabled")' \
    '    [ "${ZTE_TEST_OLD_ENABLED_PRESENT:-1}" = 1 ] || exit 1' \
    '    value=${ZTE_TEST_OLD_ENABLED:-${ZTE_TEST_CHARGING_ENABLED:-0}} ;;' \
    '  "-q get zte-usb-wifi-manager.charging.low_percent")' \
    '    [ "${ZTE_TEST_OLD_LOW_PRESENT:-1}" = 1 ] || exit 1' \
    '    value=${ZTE_TEST_OLD_LOW:-${ZTE_TEST_CHARGING_LOW:-30}} ;;' \
    '  "-q get zte-usb-wifi-manager.charging.high_percent")' \
    '    [ "${ZTE_TEST_OLD_HIGH_PRESENT:-1}" = 1 ] || exit 1' \
    '    value=${ZTE_TEST_OLD_HIGH:-${ZTE_TEST_CHARGING_HIGH:-80}} ;;' \
    '  -q\ set\ zte-usb-wifi-manager.charging.*|-q\ delete\ zte-usb-wifi-manager.charging.*|-q\ commit\ zte-usb-wifi-manager|-q\ revert\ zte-usb-wifi-manager)' \
    '    log_mutation "$@" || exit 1; exit 0 ;;' \
    '  *) exit 1 ;;' \
    'esac' \
    'printf "%s\n" "$value"' >"$test_bin/uci"
chmod +x "$test_bin/uci"
service_init=$test_bin/zte-usb-wifi-manager-init
# The generated service stub expands these variables when it executes.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'printf "%s\n" "$*" >>"${ZTE_TEST_RELOAD_LOG:?}"' \
    'reload_count=$(wc -l <"${ZTE_TEST_RELOAD_LOG}" | tr -d " ")' \
    'case ,${ZTE_TEST_RELOAD_FAIL_CALLS:-}, in' \
    '  *,"$reload_count",*) exit 1 ;;' \
    'esac' \
    'exit 0' >"$service_init"
chmod +x "$service_init"
RPCD_TEST_SERVICE_INIT=$service_init
export RPCD_TEST_SERVICE_INIT
RPCD_TEST_LIB_DIR=$write_lib
export RPCD_TEST_LIB_DIR

rpcd_all_write_gates_capabilities() {
    ZTE_TEST_WRITE_ENABLED=1 \
    ZTE_TEST_SWITCH_SIM_ENABLED=1 \
    ZTE_TEST_SET_APN_ENABLED=1 \
    ZTE_TEST_SET_CONNECTION_MODE_ENABLED=1 \
    ZTE_TEST_SET_WIFI_ENABLED=1 \
    ZTE_TEST_SET_TRAFFIC_PLAN_ENABLED=1 \
    ZTE_TEST_RESET_TRAFFIC_ENABLED=1 \
    ZTE_TEST_SEND_SMS_ENABLED=1 \
    ZTE_TEST_DELETE_SMS_ENABLED=1 \
    ZTE_TEST_MARK_SMS_READ_ENABLED=1 \
    ZTE_TEST_REBOOT_DEVICE_ENABLED=1 \
    ZTE_TEST_SHUTDOWN_DEVICE_ENABLED=1 \
    ZTE_TEST_SET_POWER_SUPPLY_MODE_ENABLED=1 \
        rpcd_call call capabilities
}

assert_unavailable_capabilities() {
    _zte_test_unavailable=$1
    assert_eq unknown "$(printf '%s' "$_zte_test_unavailable" |
        node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).adapter))')"
    assert_eq Unavailable "$(printf '%s' "$_zte_test_unavailable" |
        node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).model))')"
    assert_eq true "$(printf '%s' "$_zte_test_unavailable" | node -e '
let s="";
process.stdin.on("data", d => s += d);
process.stdin.on("end", () => {
    const c = JSON.parse(s);
    const actions = [
        "switch_sim", "set_apn", "set_connection_mode", "set_wifi",
        "set_traffic_plan", "reset_traffic", "send_sms", "delete_sms",
        "mark_sms_read", "reboot_device", "shutdown_device",
        "set_power_supply_mode"
    ];
    const grouped = [
        "sim_switch", "cellular_write", "wifi_write", "traffic_write",
        "sms_write", "device_reboot", "device_shutdown", "power_supply_write"
    ];
    process.stdout.write(String(actions.concat(grouped).every(key => c[key] === false) &&
        actions.every(key => c.feature_status[key].enabled === false &&
            c.feature_status[key].implementation === "unsupported" &&
            c.feature_status[key].verification === "not_applicable")));
});
')"
}

base_state_dir=$state_dir
for profile_case in missing malformed device_null unknown mismatch; do
    state_dir=$work/profile-$profile_case
    case $profile_case in
        missing) rm -f "$status_file" ;;
        malformed) printf '%s\n' 'not-json' >"$status_file" ;;
        device_null) printf '%s\n' '{"device":null}' >"$status_file" ;;
        unknown)
            printf '%s\n' \
                '{"device":{"adapter":"zte_unknown","model":"Unknown"}}' \
                >"$status_file"
            ;;
        mismatch)
            printf '%s\n' \
                '{"device":{"adapter":"zte_u25s","model":"U30 Pro"}}' \
                >"$status_file"
            ;;
    esac
    unavailable_capabilities=$(rpcd_all_write_gates_capabilities)
    assert_success assert_json "$unavailable_capabilities"
    assert_unavailable_capabilities "$unavailable_capabilities"
    profile_reply=$(printf '%s\n' \
        '{"action":"set_wifi","enabled":false}' |
        ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SET_WIFI_ENABLED=1 \
            rpcd_call call wifi_action)
    assert_eq '{"ok":false,"error":"unsupported"}' "$profile_reply" \
        "untrusted profile must reject write: $profile_case"
    if find "$state_dir/actions/pending" -type f -name '*.json' 2>/dev/null |
        grep -q .; then
        fail "untrusted profile created queue file: $profile_case"
    else
        pass
    fi
done
state_dir=$base_state_dir
printf '%s\n' \
    '{"online":true,"device":{"adapter":"zte_u25s","model":"U25S"}}' \
    >"$status_file"

charging_settings=$(ZTE_TEST_CHARGING_ENABLED=1 ZTE_TEST_CHARGING_LOW=35 \
    ZTE_TEST_CHARGING_HIGH=75 rpcd_call call charging_settings)
assert_eq '{"enabled":true,"low_percent":35,"high_percent":75}' \
    "$charging_settings"
uci_write_log=$work/uci-writes
: >"$uci_write_log"
charging_saved=$(printf '%s\n' \
    '{"enabled":true,"low_percent":30,"high_percent":80}' |
    rpcd_call call set_charging_settings)
assert_eq '{"ok":true,"enabled":true,"low_percent":30,"high_percent":80}' \
    "$charging_saved"
assert_eq '{"ok":false,"error":"invalid_settings"}' "$(printf '%s\n' \
    '{"enabled":true,"low_percent":80,"high_percent":30}' |
    ZTE_TEST_UCI_LOG=$uci_write_log rpcd_call call set_charging_settings)"

charging_request='{"enabled":true,"low_percent":30,"high_percent":80}'
for transaction_result in \
    transaction_busy transaction_recovery_failed settings_snapshot_failed \
    settings_write_failed settings_rollback_failed service_reload_failed \
    service_restore_failed; do
    transaction_reply=$(printf '%s\n' "$charging_request" |
        ZTE_TEST_CHARGING_TX_RESULT=$transaction_result \
            rpcd_call call set_charging_settings)
    assert_eq \
        "{\"ok\":false,\"error\":\"$transaction_result\"}" \
        "$transaction_reply"
done
unknown_transaction_reply=$(printf '%s\n' "$charging_request" |
    ZTE_TEST_CHARGING_TX_RESULT=unexpected_internal_result \
        rpcd_call call set_charging_settings)
assert_eq '{"ok":false,"error":"transaction_recovery_failed"}' \
    "$unknown_transaction_reply" \
    'rpcd must fail closed for an unknown transaction result'

effective_capabilities=$(
    ZTE_TEST_WRITE_ENABLED=1 \
    ZTE_TEST_SWITCH_SIM_ENABLED=1 \
    ZTE_TEST_SET_WIFI_ENABLED=0 \
        rpcd_call call capabilities
)
assert_eq true "$(printf '%s' "$effective_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))')"
assert_eq false "$(printf '%s' "$effective_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).wifi_write)))')"
per_action_capabilities=$(
    ZTE_TEST_WRITE_ENABLED=1 \
    ZTE_TEST_CELLULAR_WRITE_ENABLED=1 \
    ZTE_TEST_SET_APN_ENABLED=1 \
    ZTE_TEST_SET_CONNECTION_MODE_ENABLED=0 \
        rpcd_call call capabilities
)
assert_eq true "$(printf '%s' "$per_action_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).set_apn)))')"
assert_eq false "$(printf '%s' "$per_action_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).set_connection_mode)))')"
assert_eq false "$(printf '%s' "$per_action_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).cellular_write)))')" \
    'legacy cellular_write must be a safe all-actions aggregate'
cross_action_denied=$(printf '%s\n' \
    '{"action":"set_connection_mode","mode":"automatic"}' |
    ZTE_TEST_WRITE_ENABLED=1 \
    ZTE_TEST_CELLULAR_WRITE_ENABLED=1 \
    ZTE_TEST_SET_APN_ENABLED=1 \
    ZTE_TEST_SET_CONNECTION_MODE_ENABLED=0 \
        rpcd_call call cellular_action)
assert_eq '{"ok":false,"error":"write_not_enabled"}' "$cross_action_denied"
if find "$state_dir/actions/pending" -type f -name '*.json' 2>/dev/null |
    grep -q .; then
    fail 'enabling APN or a legacy cellular gate must not enqueue connection mode'
else
    pass
fi
independent_device_capabilities=$(
    ZTE_TEST_WRITE_ENABLED=1 \
    ZTE_TEST_REBOOT_DEVICE_ENABLED=1 \
    ZTE_TEST_SHUTDOWN_DEVICE_ENABLED=0 \
        rpcd_call call capabilities
)
assert_eq true "$(printf '%s' "$independent_device_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).device_reboot)))')"
assert_eq false "$(printf '%s' "$independent_device_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).device_shutdown)))')"
globally_disabled_capabilities=$(
    ZTE_TEST_WRITE_ENABLED=0 \
    ZTE_TEST_SWITCH_SIM_ENABLED=1 \
        rpcd_call call capabilities
)
assert_eq false "$(printf '%s' "$globally_disabled_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))')"

sim_write_disabled=$(printf '%s\n' \
    '{"action":"switch_sim","target":"sim2","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=0 rpcd_call call cellular_action)
assert_eq '{"ok":false,"error":"write_not_enabled"}' "$sim_write_disabled"
sim_feature_disabled=$(printf '%s\n' \
    '{"action":"switch_sim","target":"sim2","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SWITCH_SIM_ENABLED=0 \
        rpcd_call call cellular_action)
assert_eq '{"ok":false,"error":"write_not_enabled"}' \
    "$sim_feature_disabled"
assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"switch_sim","target":"sim2"}' |
        ZTE_TEST_WRITE_ENABLED=1 rpcd_call call cellular_action
)"
assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"switch_sim","target":"sim2","confirm":false}' |
        ZTE_TEST_WRITE_ENABLED=1 rpcd_call call cellular_action
)"
assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"switch_sim","target":"sim2","confirm":"true"}' |
        ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SWITCH_SIM_ENABLED=1 \
            rpcd_call call cellular_action
)"
assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"switch_sim","target":"invalid","confirm":true}' |
        ZTE_TEST_WRITE_ENABLED=1 rpcd_call call cellular_action
)"
if find "$state_dir/actions/pending" -type f -name '*.json' 2>/dev/null |
    grep -q .; then
    fail 'unconfirmed SIM switches must not create queue files'
else
    pass
fi
sim_queued=$(printf '%s\n' \
    '{"action":"switch_sim","target":"physical","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SWITCH_SIM_ENABLED=1 \
        rpcd_call call cellular_action)
assert_success assert_json "$sim_queued"
sim_queued_id=$(zte_json_flat_get "$sim_queued" operation_id)
assert_success zte_operation_id_valid "$sim_queued_id"
assert_eq physical "$(
    zte_json_path_get \
        "$(cat "$state_dir/actions/pending/$sim_queued_id.json")" \
        payload target
)"
assert_eq true "$(
    zte_json_path_get \
        "$(cat "$state_dir/actions/pending/$sim_queued_id.json")" \
        payload confirm
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
    '{"action":"set_apn","apn":"internet","auth":"chap","username":"fixture-user","password":"DUMMY_QUEUE_VALUE"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SET_APN_ENABLED=1 \
        rpcd_call call cellular_action)
case $apn_queued in *DUMMY_QUEUE_VALUE*) fail 'APN password leaked in RPC reply' ;; *) pass ;; esac
assert_queued_action "$apn_queued" apn internet

mode_queued=$(printf '%s\n' \
    '{"action":"set_connection_mode","mode":"automatic"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SET_CONNECTION_MODE_ENABLED=1 \
        rpcd_call call cellular_action)
assert_queued_action "$mode_queued" mode automatic

wifi_queued=$(printf '%s\n' \
    '{"action":"set_wifi","enabled":true,"band":"5g","ssid":"Fixture WiFi","security":"wpa2_psk","password":"DUMMY_WIFI_VALUE","channel":"36"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SET_WIFI_ENABLED=1 \
        rpcd_call call wifi_action)
case $wifi_queued in *DUMMY_WIFI_VALUE*) fail 'Wi-Fi password leaked in RPC reply' ;; *) pass ;; esac
assert_queued_action "$wifi_queued" ssid 'Fixture WiFi'

traffic_queued=$(printf '%s\n' \
    '{"action":"set_traffic_plan","enabled":true,"limit_bytes":10737418240,"alert_percent":90,"cycle_day":1,"disconnect":false}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SET_TRAFFIC_PLAN_ENABLED=1 \
        rpcd_call call traffic_action)
assert_queued_action "$traffic_queued" limit_bytes 10737418240

reset_queued=$(printf '%s\n' \
    '{"action":"reset_traffic","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_RESET_TRAFFIC_ENABLED=1 \
        rpcd_call call traffic_action)
assert_queued_action "$reset_queued" confirm true

sms_queued=$(printf '%s\n' \
    '{"action":"send_sms","number":"+12025550123","content":"runtime fixture message"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SEND_SMS_ENABLED=1 \
        rpcd_call call sms_action)
case $sms_queued in *runtime*|*12025550123*) fail 'SMS private data leaked in RPC reply' ;; *) pass ;; esac
assert_queued_action "$sms_queued" action send_sms

delete_queued=$(printf '%s\n' \
    '{"action":"delete_sms","message_id":"42","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_DELETE_SMS_ENABLED=1 \
        rpcd_call call sms_action)
assert_queued_action "$delete_queued" message_id 42

read_queued=$(printf '%s\n' \
    '{"action":"mark_sms_read","message_id":"42"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_MARK_SMS_READ_ENABLED=1 \
        rpcd_call call sms_action)
assert_queued_action "$read_queued" message_id 42

reboot_queued=$(printf '%s\n' \
    '{"action":"reboot_device","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_REBOOT_DEVICE_ENABLED=1 \
        rpcd_call call device_action)
assert_queued_action "$reboot_queued" confirm true

shutdown_queued=$(printf '%s\n' \
    '{"action":"shutdown_device","confirm":true}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SHUTDOWN_DEVICE_ENABLED=1 \
        rpcd_call call device_action)
assert_queued_action "$shutdown_queued" confirm true

unknown_field=$(printf '%s\n' \
    '{"action":"set_wifi","enabled":false,"goformId":"UNREVIEWED"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SET_WIFI_ENABLED=1 \
        rpcd_call call wifi_action)
assert_eq '{"ok":false,"error":"invalid_action"}' "$unknown_field"

printf '%s\n' '{"online":true,"model":"U30 Pro","device":{"adapter":"zte_u30","model":"U30 Pro"}}' >"$status_file"
u30_write_capabilities=$(
    ZTE_TEST_WRITE_ENABLED=1 \
    ZTE_TEST_SWITCH_SIM_ENABLED=1 \
    ZTE_TEST_SET_WIFI_ENABLED=1 \
        rpcd_call call capabilities
)
assert_eq false "$(printf '%s' "$u30_write_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))')"
assert_eq not_implemented "$(printf '%s' "$u30_write_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).feature_status.sim_switch.implementation))')"
assert_eq false "$(printf '%s' "$u30_write_capabilities" |
    node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).feature_status.sim_switch.enabled)))')"
assert_eq '{"ok":false,"error":"unsupported"}' "$(
    printf '%s\n' '{"action":"switch_sim","target":"sim2","confirm":true}' |
        ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SWITCH_SIM_ENABLED=1 \
            rpcd_call call cellular_action
)"
assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"set_wifi","enabled":true,"band":"5g","ssid":"U30","security":"open","channel":"auto"}' |
        ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SET_WIFI_ENABLED=1 \
            rpcd_call call wifi_action
)"
assert_eq '{"ok":false,"error":"invalid_action"}' "$(
    printf '%s\n' '{"action":"set_wifi","enabled":true,"band":"2g","ssid":"U30","security":"open","channel":"6"}' |
        ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SET_WIFI_ENABLED=1 \
            rpcd_call call wifi_action
)"
u30_wifi_queued=$(printf '%s\n' \
    '{"action":"set_wifi","enabled":true,"band":"2g","ssid":"U30","security":"open","channel":"auto"}' |
    ZTE_TEST_WRITE_ENABLED=1 ZTE_TEST_SET_WIFI_ENABLED=1 \
        rpcd_call call wifi_action)
assert_queued_action "$u30_wifi_queued" band 2g
printf '%s\n' \
    '{"online":true,"device":{"adapter":"zte_u25s","model":"U25S"}}' \
    >"$status_file"

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
