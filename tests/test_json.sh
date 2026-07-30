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
assert_eq '' "$(zte_json_flat_get '{"a":"1"}' missing_key)"
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
assert_success zte_json_is_flat_object '{"a":"b"}'
assert_success zte_json_is_flat_object '{}'
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
finish
