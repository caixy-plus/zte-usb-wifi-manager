#!/bin/sh
set -eu

TEST_NAME=test_rpcd
. ./tests/testlib.sh

rpcd=./package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi
metadata=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh
. "$(dirname "$metadata")/validation.sh"
. "$(dirname "$metadata")/json.sh"
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
assert_file_contains "$rpcd" 'event-log\.sh'
assert_file_contains "$rpcd" 'json\.sh'
assert_file_contains "$rpcd" 'charging-transaction\.sh'
if grep -q '/adapter-zte-u25s\.sh' "$rpcd"; then
    fail 'rpcd must not load the HTTP/session adapter stack'
else
    pass
fi
if grep -E 'cellular_action|wifi_action|sms_action|device_action|power_action|operation_status|sms_messages' "$rpcd" >/dev/null; then
    fail 'rpcd product surface must not expose removed console actions'
else
    pass
fi

rpcd_call() {
    ZTE_USB_WIFI_LIB_DIR=${RPCD_TEST_LIB_DIR:-$(dirname "$metadata")} \
    ZTE_USB_WIFI_STATUS_FILE=$status_file \
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
assert_eq '{"status":{},"capabilities":{},"charging_settings":{},"set_charging_settings":{"enabled":"Boolean","low_percent":"Integer","high_percent":"Integer"},"credential_status":{},"set_credentials":{"password":"String"},"clear_credentials":{},"logs":{"limit":"Integer"}}' \
    "$list_output" \
    'rpcd list must expose charge-only product methods'

# Capabilities fail closed until the daemon has cached an exact U30 identity.
capabilities=$(rpcd_call call capabilities)
assert_success assert_json "$capabilities"
assert_eq false "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))')"
assert_eq unknown "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).adapter))')"
assert_eq Unavailable "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).model))')"
assert_eq unsupported "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).switch_sim?.implementation)))')"
assert_eq unsupported "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).set_power_supply_mode?.implementation)))')"
assert_eq native_console_only "$(printf '%s' "$capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).factory_reset?.implementation)))')"

printf '%s\n' '{"online":false,"state":"unsupported_device","device":null}' >"$status_file"
unsupported_capabilities=$(rpcd_call call capabilities)
assert_eq unknown "$(printf '%s' "$unsupported_capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).adapter))')"
assert_eq false "$(printf '%s' "$unsupported_capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).set_power_supply_mode)))')"

printf '%s\n' '{"online":true,"model":"U30 Pro","device":{"adapter":"zte_u30","model":"U30 Pro"}}' >"$status_file"
u30_capabilities=$(rpcd_call call capabilities)
assert_eq zte_u30 "$(printf '%s' "$u30_capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).adapter))')"
assert_eq https "$(printf '%s' "$u30_capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).transport))')"
assert_eq device_certificate_unverified "$(printf '%s' "$u30_capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).tls_verification))')"
rm -f "$status_file"

fallback=$(rpcd_call call status)
assert_success assert_json "$fallback"
case $fallback in
    *framework_ready*) pass ;;
    *) fail 'a missing snapshot must return framework status' ;;
esac

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

# Mock UCI + charging transaction for settings path.
mkdir -p "$write_lib" "$test_bin"
for library in validation.sh json.sh credentials.sh event-log.sh adapter-zte-u25s-metadata.sh; do
    ln -s "$(cd "$(dirname "$metadata")" && pwd)/$library" "$write_lib/$library"
done
printf '%s\n' \
    '#!/bin/sh' \
    'zte_charging_transaction_apply() {' \
    '  printf "%s\n" ok' \
    '}' >"$write_lib/charging-transaction.sh"
# The single-quoted lines below are the literal body of the generated UCI
# test double; their parameter expansions must happen when that script runs.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'case " $* " in' \
    '  *" -q get zte-usb-wifi-manager.main.write_enabled "*)' \
    '    printf "%s\n" "${ZTE_TEST_WRITE_ENABLED:-1}" ;;' \
    '  *" -q get zte-usb-wifi-manager.writes.set_power_supply_mode_enabled "*)' \
    '    printf "%s\n" "${ZTE_TEST_POWER_ENABLED:-1}" ;;' \
    '  *" -q get zte-usb-wifi-manager.charging.enabled "*)' \
    '    printf "%s\n" "${ZTE_TEST_CHARGING_ENABLED:-0}" ;;' \
    '  *" -q get zte-usb-wifi-manager.charging.low_percent "*)' \
    '    printf "%s\n" "${ZTE_TEST_CHARGING_LOW:-30}" ;;' \
    '  *" -q get zte-usb-wifi-manager.charging.high_percent "*)' \
    '    printf "%s\n" "${ZTE_TEST_CHARGING_HIGH:-80}" ;;' \
    '  *) exit 1 ;;' \
    'esac' >"$test_bin/uci"
chmod +x "$test_bin/uci"

RPCD_TEST_LIB_DIR=$write_lib
export RPCD_TEST_LIB_DIR

printf '%s\n' '{"online":true,"model":"U30 Pro","device":{"adapter":"zte_u30","model":"U30 Pro"}}' >"$status_file"
u30_write_capabilities=$(rpcd_call call capabilities)
assert_eq true "$(printf '%s' "$u30_write_capabilities" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).set_power_supply_mode)))')"
u30_global_gate_closed=$(ZTE_TEST_WRITE_ENABLED=0 rpcd_call call capabilities)
assert_eq false "$(printf '%s' "$u30_global_gate_closed" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).set_power_supply_mode)))')"
u30_feature_gate_closed=$(ZTE_TEST_POWER_ENABLED=0 rpcd_call call capabilities)
assert_eq false "$(printf '%s' "$u30_feature_gate_closed" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).set_power_supply_mode)))')"
rm -f "$status_file"

charging_settings=$(ZTE_TEST_CHARGING_ENABLED=1 ZTE_TEST_CHARGING_LOW=35 \
    ZTE_TEST_CHARGING_HIGH=75 rpcd_call call charging_settings)
assert_eq '{"enabled":true,"low_percent":35,"high_percent":75}' \
    "$charging_settings"

charging_saved=$(printf '%s\n' \
    '{"enabled":true,"low_percent":40,"high_percent":85}' |
    rpcd_call call set_charging_settings)
assert_eq '{"ok":true,"enabled":true,"low_percent":40,"high_percent":85}' \
    "$charging_saved"
assert_eq '{"ok":false,"error":"invalid_settings"}' \
    "$(printf '%s\n' '{"enabled":true,"low_percent":90,"high_percent":80}' |
        rpcd_call call set_charging_settings)"

# Logs: only smart_charge events are returned.
assert_eq '{"events":[]}' "$(printf '%s\n' '{"limit":20}' | rpcd_call call logs)"
mkdir -p "$state_dir/logs"
printf '%s\n' \
    '{"time":1722345678,"level":"info","type":"service","code":"service_started"}' \
    '{"time":1722345679,"level":"info","type":"smart_charge","code":"smart_charge_applied"}' \
    '{"time":1722345680,"level":"warn","type":"smart_charge","code":"write_failed_cooldown"}' \
    >"$state_dir/logs/events.jsonl"
logs=$(printf '%s\n' '{"limit":10}' | rpcd_call call logs)
assert_success node -e '
const events = JSON.parse(process.argv[1]).events;
if (events.length !== 2) process.exit(1);
if (events[0].code !== "smart_charge_applied") process.exit(1);
if (events[1].code !== "write_failed_cooldown") process.exit(1);
' "$logs"
assert_eq '{"ok":false,"error":"invalid_limit"}' \
    "$(printf '%s\n' '{"limit":0}' | rpcd_call call logs)"
assert_eq '{"ok":false,"error":"invalid_limit"}' \
    "$(printf '%s\n' '{"limit":201}' | rpcd_call call logs)"

assert_failure rpcd_call call unknown
assert_failure rpcd_call call cellular_action
assert_failure rpcd_call call sms_messages
assert_failure rpcd_call call operation_status
assert_failure rpcd_call unknown

finish
