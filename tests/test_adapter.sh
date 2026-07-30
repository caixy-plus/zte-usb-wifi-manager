#!/bin/sh
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

# known-field gate
assert_success zte_adapter_has_any_field "$(cat "$fixtures/read_ok.json")"
assert_failure zte_adapter_has_any_field "$(cat "$fixtures/read_session_expired.json")"

# fetch with a warm cookie jar performs no login
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { cat "$fixtures/read_ok.json"; }
raw=$(zte_adapter_fetch 192.168.0.1 secret "$jar")
assert_eq "$(cat "$fixtures/read_ok.json")" "$raw"

# normalize maps every field
expected='{"online":true,"model":"U25S","modem_state":"connected","cellular":{"type":"NR5G-SA","provider":"中国移动","signalbar":"4","rsrp":"-68","ppp_status":"ipv4_ipv6_connected"},"sim":{"active_slot_raw":"1"},"battery":{"present":true,"percent":82,"charging":false},"missing":""}'
assert_eq "$expected" "$(zte_adapter_normalize "$raw")"
assert_success node -e 'JSON.parse(process.argv[1])' "$expected"

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
    *'"battery":{"present":false,"percent":null,"charging":null}'*) pass ;;
    *) fail "missing fields not nulled: $out" ;;
esac
case $out in
    *'"missing":"mc_modem_main_state,network_signalbar,network_provider_fullname,Z5g_rsrp,ppp_status,simcard_active_slot_temp,battery_vol_percent,battery_charging"'*) pass ;;
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

rm -rf "$work"
finish
