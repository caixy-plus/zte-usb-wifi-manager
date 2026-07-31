#!/bin/sh
# HTTP stubs are invoked from production functions loaded with source, which
# ShellCheck 0.9 cannot trace across files.
# shellcheck disable=SC2317,SC2329
set -eu
TEST_NAME=test_adapter
. ./tests/testlib.sh
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/session.sh"
. "$lib/adapter-zte-u25s-metadata.sh"
. "$lib/adapter-zte-u25s.sh"
. "$lib/snapshot.sh"

# The inspected target firmware advertises HAS_LOGIN:false and its WebUI
# therefore treats the device as logged in without a LOGIN exchange.
assert_eq 0 "${ZTE_LOGIN_REQUIRED:-missing}"
assert_failure zte_adapter_login_required
assert_eq false "$(
    zte_adapter_capabilities_json |
        node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).login_required)))'
)"
ZTE_LOGIN_REQUIRED=1
assert_success zte_adapter_login_required
assert_eq true "$(
    zte_adapter_capabilities_json |
        node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).login_required)))'
)"
ZTE_LOGIN_REQUIRED=0

fixtures=./tests/fixtures/u25s
work=/tmp/zte-test-adapter.$$
mkdir -p "$work"
jar=$work/cookies.txt
printf x >"$jar"

# device flag mapping
assert_eq true "$(zte_adapter_bool 1)"
assert_eq false "$(zte_adapter_bool 0)"
assert_eq null "$(zte_adapter_bool '')"
assert_eq null "$(zte_adapter_bool maybe)"

# The target firmware reports modem_init_complete while fully registered and
# online; authenticated fixtures also use connected.
assert_success zte_adapter_modem_ready connected
assert_success zte_adapter_modem_ready modem_init_complete
assert_failure zte_adapter_modem_ready offline
assert_failure zte_adapter_modem_ready ''

# known-field gate
assert_success zte_adapter_has_any_field "$(cat "$fixtures/read_ok.json")"
assert_failure zte_adapter_has_any_field "$(cat "$fixtures/read_session_expired.json")"

# A firmware that exposes status without authentication must not be rejected
# merely because the cookie jar and credential are empty.
: >"$jar"
anonymous_logins=$work/anonymous-logins
: >"$anonymous_logins"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_session_login() {
    printf 'login\n' >>"$anonymous_logins"
    return 1
}
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { cat "$fixtures/read_ok.json"; }
anonymous_raw=$(zte_adapter_fetch 192.168.0.1 '' "$jar")
assert_eq "$(cat "$fixtures/read_ok.json")" "$anonymous_raw"
assert_eq 0 "$(wc -l <"$anonymous_logins" | tr -d ' ')"

# If the anonymous probe is valid JSON but has no known status fields, an
# absent password is a distinct "credentials required" outcome.
ZTE_LOGIN_REQUIRED=1
: >"$jar"
: >"$anonymous_logins"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { cat "$fixtures/read_session_expired.json"; }
set +e
zte_adapter_fetch 192.168.0.1 '' "$jar" >/dev/null
anonymous_status=$?
set -e
assert_eq 2 "$anonymous_status"
assert_eq 0 "$(wc -l <"$anonymous_logins" | tr -d ' ')"
ZTE_LOGIN_REQUIRED=0

# A stale optional credential must never make HAS_LOGIN:false firmware enter
# LOGIN after a malformed or unknown anonymous response.
: >"$anonymous_logins"
set +e
zte_adapter_fetch 192.168.0.1 stale-optional-password "$jar" >/dev/null
anonymous_status=$?
set -e
assert_eq 1 "$anonymous_status"
assert_eq 0 "$(wc -l <"$anonymous_logins" | tr -d ' ')"

# fetch with a warm cookie jar performs no login
: >"$jar"
printf x >"$jar"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { cat "$fixtures/read_ok.json"; }
raw=$(zte_adapter_fetch 192.168.0.1 secret "$jar")
assert_eq "$(cat "$fixtures/read_ok.json")" "$raw"

# normalize maps every field
expected='{"online":true,"model":"U25S","modem_state":"connected","cellular":{"type":"NR5G-SA","provider":"中国移动","signalbar":"4","rsrp":"-68","ppp_status":"ipv4_ipv6_connected"},"sim":{"active_slot_raw":"1","type":"physical"},"battery":{"present":true,"percent":82,"charging":false,"value":"4050","pers":"82","temperature_level":"normal"},"sms":{"total":3},"missing":""}'
assert_eq "$expected" "$(zte_adapter_normalize "$raw")"
assert_success node -e 'JSON.parse(process.argv[1])' "$expected"

# The target U25S WebUI treats battery_charging=2 as fully charged, not an
# invalid state. It must normalize to false so a full battery cannot make the
# daemon enter fail-safe or be reported as actively charging.
full_battery_out=$(zte_adapter_normalize \
    '{"battery_exist":"1","battery_vol_percent":"100","battery_charging":"2"}')
assert_eq false \
    "$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).battery.charging))' \
        "$full_battery_out")"
charging_battery_out=$(zte_adapter_normalize \
    '{"battery_exist":"1","battery_vol_percent":"99","battery_charging":"1"}')
assert_eq true \
    "$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).battery.charging))' \
        "$charging_battery_out")"

# Escaped strings and JSON whitespace survive extraction and normalization.
escaped_raw=$(printf '{\n"network_provider_fullname"\n:\n"ACME \\"5G\\""\n}')
escaped_out=$(zte_adapter_normalize "$escaped_raw")
assert_success node -e 'JSON.parse(process.argv[1])' "$escaped_out"
assert_eq 'ACME "5G"' \
    "$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).cellular.provider)' "$escaped_out")"

# Present battery fields must be semantically valid. A syntactically valid but
# damaged device response must fail the same fetch -> normalize path as polling.
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { printf '%s\n' "$invalid_response"; }
fetch_and_normalize() {
    _raw=$(zte_adapter_fetch 192.168.0.1 secret "$jar") &&
        zte_adapter_normalize "$_raw" >/dev/null
}
for invalid_response in \
    '{"battery_vol_percent":"150"}' \
    '{"battery_vol_percent":"-1"}' \
    '{"battery_vol_percent":"unknown"}' \
    '{"battery_vol_percent":"01"}' \
    '{"battery_vol_percent":"099"}' \
    '{"battery_exist":"maybe"}' \
    '{"battery_charging":"maybe"}'
do
    assert_failure zte_adapter_normalize "$invalid_response"
    assert_failure fetch_and_normalize
done
for invalid_response in \
    '{"sms_data_total":"-1"}' \
    '{"sms_data_total":"01"}' \
    '{"sms_data_total":"unknown"}'
do
    assert_failure zte_adapter_normalize "$invalid_response"
done
empty_sms_out=$(zte_adapter_normalize '{"sms_data_total":""}')
assert_eq null \
    "$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).sms.total))' \
        "$empty_sms_out")"

# A rejected candidate cannot replace the last trusted device snapshot.
invalid_response='{"battery_vol_percent":"01"}'
candidate=''
ok=0
if _raw=$(zte_adapter_fetch 192.168.0.1 secret "$jar") &&
    candidate=$(zte_adapter_normalize "$_raw"); then
    ok=1
fi
assert_eq 0 "$ok"
assert_eq "$expected" "$(zte_device_retain "$expected" "$candidate" "$ok")"

# Accepted boundary values always produce strict JSON.
for valid_percent in 0 1 99 100; do
    valid_out=$(zte_adapter_normalize \
        "{\"battery_vol_percent\":\"$valid_percent\"}")
    assert_success node -e 'JSON.parse(process.argv[1])' "$valid_out"
done

# missing fields become null and are reported in ZTE_READ_FIELDS order
out=$(zte_adapter_normalize "$(cat "$fixtures/read_missing_fields.json")")
case $out in
    *'"sim":{"active_slot_raw":null,"type":null}'*) pass ;;
    *) fail "missing SIM fields not nulled: $out" ;;
esac
case $out in
    *'"battery":{"present":false,"percent":null,"charging":null,"value":null,"pers":null,"temperature_level":null}'*) pass ;;
    *) fail "missing battery fields not nulled: $out" ;;
esac
case $out in
    *'"sms":{"total":null}'*) pass ;;
    *) fail "missing SMS fields not nulled: $out" ;;
esac
case $out in
    *'"missing":"mc_modem_main_state,network_signalbar,network_provider_fullname,Z5g_rsrp,ppp_status,simcard_active_slot_temp,usim_esim_type,battery_vol_percent,battery_charging,battery_value,battery_pers,battery_temperature_level,sms_data_total"'*) pass ;;
    *) fail "missing list wrong: $out" ;;
esac

# malformed response fails without any retry
get_calls=$work/get-calls
printf 0 >"$get_calls"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() {
    n=$(cat "$get_calls"); n=$((n + 1)); printf '%s' "$n" >"$get_calls"
    cat "$fixtures/read_malformed.json"
}
assert_failure zte_adapter_fetch 192.168.0.1 secret "$jar"
assert_eq 1 "$(cat "$get_calls")"

# stale session triggers exactly one relogin and one retry
ZTE_LOGIN_REQUIRED=1
printf 0 >"$get_calls"
logins=$work/logins
: >"$logins"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_session_login() { printf 'x\n' >>"$logins"; return 0; }
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() {
    n=$(cat "$get_calls"); n=$((n + 1)); printf '%s' "$n" >"$get_calls"
    if [ "$n" -eq 1 ]; then
        cat "$fixtures/read_session_expired.json"
    else
        cat "$fixtures/read_ok.json"
    fi
}
raw2=$(zte_adapter_fetch 192.168.0.1 secret "$jar")
assert_eq "$(cat "$fixtures/read_ok.json")" "$raw2"
assert_eq 2 "$(cat "$get_calls")"
assert_eq 1 "$(wc -l <"$logins" | tr -d ' ')"
ZTE_LOGIN_REQUIRED=0

# Target firmware login page exposes four SIM choices. Keep the semantic
# action payload independent of the firmware's non-sequential physical slot.
assert_eq 1 "$(zte_adapter_sim_card_index sim1)"
assert_eq 2 "$(zte_adapter_sim_card_index sim2)"
assert_eq 3 "$(zte_adapter_sim_card_index sim3)"
assert_eq 0 "$(zte_adapter_sim_card_index physical)"
assert_failure zte_adapter_sim_card_index ''
assert_failure zte_adapter_sim_card_index sim4
assert_failure zte_adapter_sim_card_index 0

# The calibrated request shape must contain only the verified goform id and
# card_index mapping. A response other than the observed success token fails.
switch_post_log=$work/switch-post
zte_http_post() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >"$switch_post_log"
    printf '%s\n' '{"result":"success"}'
}
assert_success zte_adapter_switch_sim 192.168.0.1 sim2 "$jar"
assert_eq \
    "http://192.168.0.1/goform/goform_set_cmd_process|isTest=false&goformId=SIM_SWITCH_SIMCARD&card_index=2|$jar" \
    "$(cat "$switch_post_log")"
zte_http_post() { printf '%s\n' '{"result":"failure"}'; }
assert_failure zte_adapter_switch_sim 192.168.0.1 physical "$jar"
zte_http_post() { printf '%s\n' 'not-json'; }
assert_failure zte_adapter_switch_sim 192.168.0.1 sim1 "$jar"
assert_failure zte_adapter_switch_sim 192.168.0.1 invalid "$jar"

rm -rf "$work"
finish
