#!/bin/sh
set -eu
TEST_NAME=test_json
. ./tests/testlib.sh
. ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/json.sh

assert_eq 'NR5G-SA' "$(zte_json_flat_get '{"network_type":"NR5G-SA"}' network_type)"
assert_eq '-68' "$(zte_json_flat_get '{"Z5g_rsrp":"-68"}' Z5g_rsrp)"
assert_eq '82' "$(zte_json_flat_get '{"battery_vol_percent":"82"}' battery_vol_percent)"
assert_eq '82' "$(zte_json_flat_get '{"percent":82}' percent)"
assert_eq '-3' "$(zte_json_flat_get '{"v":-3}' v)"
assert_eq 'true' "$(zte_json_flat_get '{"online":true}' online)"
assert_eq 'false' "$(zte_json_flat_get '{"online":false}' online)"
assert_eq boolean "$(zte_json_flat_type '{"online":true}' online)"
assert_eq string "$(zte_json_flat_type '{"online":"true"}' online)"
assert_eq '' "$(zte_json_flat_get '{"a":"1"}' missing_key)"
assert_eq '' "$(zte_json_flat_type '{"a":"1"}' missing_key)"
# a longer key containing the requested name must not match
assert_eq '' "$(zte_json_flat_get '{"xnetwork_type":"X"}' network_type)"
assert_failure zte_json_flat_has '{"xnetwork_type":"X"}' network_type
# values with spaces and CJK survive
assert_eq '中国移动 4G' "$(zte_json_flat_get '{"p":"中国移动 4G"}' p)"
escaped='{"network_provider_fullname":"ACME \"5G\" C:\\modem\/ui\nline"}'
escaped_expected=$(printf 'ACME "5G" C:\\modem/ui\nline')
assert_eq "$escaped_expected" \
    "$(zte_json_flat_get "$escaped" network_provider_fullname)"

multiline=$(printf '{\n  "network_type"\n  :\n  "NR5G-SA"\n}')
assert_success zte_json_is_flat_object "$multiline"
assert_success zte_json_flat_has "$multiline" network_type
assert_eq NR5G-SA "$(zte_json_flat_get "$multiline" network_type)"

# has distinguishes absent fields from present empty and null values, while get
# preserves its existing empty-output behavior for all three.
assert_failure zte_json_flat_has '{"other":"value"}' value
assert_success zte_json_flat_has '{"value":""}' value
assert_success zte_json_flat_has '{"value":null}' value
assert_eq '' "$(zte_json_flat_get '{"other":"value"}' value)"
assert_eq '' "$(zte_json_flat_get '{"value":""}' value)"
assert_eq '' "$(zte_json_flat_get '{"value":null}' value)"
# Nested normalized objects use a separate exact top-level scalar query.
normalized='{"online":true,"model":"U25S","battery":{"percent":82}}'
assert_eq true "$(zte_json_top_get "$normalized" online)"
assert_eq U25S "$(zte_json_top_get "$normalized" model)"
assert_eq '' "$(zte_json_top_get "$normalized" percent)"
assert_eq 82 "$(zte_json_path_get "$normalized" battery percent)"
assert_eq '{"percent":82}' \
    "$(zte_json_top_object_get "$normalized" battery)"
assert_failure zte_json_top_object_get "$normalized" model
assert_failure zte_json_top_object_get \
    '{"payload":{"action":"safe"},"payload":{"action":"tampered"}}' payload
assert_success zte_json_is_flat_object '{"a":"b"}'
assert_success zte_json_is_flat_object '{}'
assert_eq 'action
target' "$(zte_json_flat_keys '{"action":"switch_sim","target":"sim2"}')"
assert_failure zte_json_is_flat_object '{"action":"first","action":"second"}'
assert_failure zte_json_flat_keys '{"action":"first","action":"second"}'
assert_success zte_json_is_flat_object ' { "provider" : "中国移动 4G", "escaped" : "a\"b\\c", "number" : -12.5e+2, "enabled" : true, "disabled" : false, "empty" : null } '
assert_failure zte_json_is_flat_object 'not json'
assert_failure zte_json_is_flat_object ''
assert_failure zte_json_is_flat_object '{"battery_vol_percent":}'
assert_failure zte_json_is_flat_object '{"a":"b",}'
assert_failure zte_json_is_flat_object '{"a" "b"}'
assert_failure zte_json_is_flat_object '{"a":"b"} trailing'
assert_failure zte_json_is_flat_object '{"nested":{"a":"b"}}'
assert_failure zte_json_is_flat_object '{"nested":["a"]}'
assert_eq 'a\"b\\c' "$(zte_json_escape 'a"b\c')"
# keys with sed-special characters are rejected, not interpolated
assert_failure zte_json_flat_get '{"a":"1"}' 'bad/key'

jsonfilter() {
    node ./tests/jsonfilter_stub.js "$@"
}

station_raw='{"station_list":[{"mac_addr":"AA:BB:CC:DD:EE:FF","hostname":"Lab client","ip_addr":"192.0.2.10","ssid_index":"1","interfacetype":"WIFI1","ULSpeed":"12","DLSpeed":"34","ignored_field":"SHOULD_NOT_APPEAR"},{"mac_addr":"11:22:33:44:55:66","hostname":"","ip_addr":"","ssid_index":"2","interfacetype":"WIFI2","ULSpeed":"","DLSpeed":""}]}'
station_expected='{"available":true,"items":[{"mac":"AA:BB:CC:DD:EE:FF","hostname":"Lab client","ip":"192.0.2.10","ssid_index":"1","interface":"WIFI1","upload_rate_raw":"12","download_rate_raw":"34"},{"mac":"11:22:33:44:55:66","hostname":null,"ip":null,"ssid_index":"2","interface":"WIFI2","upload_rate_raw":null,"download_rate_raw":null}]}'
assert_eq "$station_expected" "$(zte_json_normalize_station_list "$station_raw")"
assert_eq '{"available":true,"items":[]}' \
    "$(zte_json_normalize_station_list '{"station_list":[]}')"
assert_failure zte_json_normalize_station_list '{}'
assert_failure zte_json_normalize_station_list '{"station_list":"bad"}'
assert_failure zte_json_normalize_station_list \
    '{"station_list":[{"hostname":"missing mac"}]}'
assert_failure zte_json_normalize_station_list \
    '{"station_list":[{"mac_addr":"not-a-mac"}]}'
assert_failure zte_json_normalize_station_list \
    '{"station_list":["not-an-object"]}'
# shellcheck disable=SC2016
station_many=$(node -e 'process.stdout.write(JSON.stringify({station_list:Array.from({length:65},(_,i)=>({mac_addr:`02:00:00:00:00:${i.toString(16).padStart(2,"0")}`}))}))')
assert_failure zte_json_normalize_station_list "$station_many"

sms_raw='{"messages":[{"id":"7","number":"+8600000000000","content":"4F60597D","date":"26,08,01,09,30,00,+32","tag":"1","draft_group_id":"0","received_all_concat_sms":"1","private_extension":"MUST_NOT_LEAK"}]}'
sms_expected='{"available":true,"items":[{"id":"7","number_raw":"+8600000000000","content_encoded":"4F60597D","date_raw":"26,08,01,09,30,00,+32","tag":"1","draft_group_id":"0","received_all_concat_sms":"1"}]}'
assert_eq "$sms_expected" "$(zte_json_normalize_sms_messages "$sms_raw")"
assert_eq '{"available":true,"items":[]}' \
    "$(zte_json_normalize_sms_messages '{"messages":[]}')"
assert_failure zte_json_normalize_sms_messages '{}'
assert_failure zte_json_normalize_sms_messages '{"messages":"bad"}'
assert_failure zte_json_normalize_sms_messages \
    '{"messages":[{"number":"missing id"}]}'
assert_failure zte_json_normalize_sms_messages \
    '{"messages":[{"id":"bad id","content":"0041"}]}'
assert_failure zte_json_normalize_sms_messages \
    '{"messages":["not-an-object"]}'
# shellcheck disable=SC2016
sms_many=$(node -e 'process.stdout.write(JSON.stringify({messages:Array.from({length:51},(_,i)=>({id:String(i),content:"0041"}))}))')
assert_failure zte_json_normalize_sms_messages "$sms_many"
finish
