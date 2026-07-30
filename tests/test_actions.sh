#!/bin/sh
set -eu

TEST_NAME=test_actions
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
actions=$lib/actions.sh
if [ ! -f "$actions" ]; then
    fail 'actions library must exist'
    finish
fi
. "$lib/validation.sh"
. "$lib/json.sh"
# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/actions.sh
. "$actions"

work=$(mktemp -d /tmp/zte-test-actions.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
state=$work/state

for action in \
    switch_sim set_apn set_connection_mode set_wifi set_traffic_plan \
    reset_traffic send_sms delete_sms mark_sms_read
do
    assert_success zte_action_type_valid "$action"
done
for action in '' reboot_device 'switch sim' '../switch_sim' SWITCH_SIM; do
    assert_failure zte_action_type_valid "$action"
done

assert_success zte_operation_id_valid op-1722345678-1234
for operation_id in '' op-1-2 op-1722345678 op-1722345678-x '../op-1722345678-1'; do
    assert_failure zte_operation_id_valid "$operation_id"
done

assert_success zte_action_init "$state"
for directory in \
    "$state/actions" \
    "$state/actions/pending" \
    "$state/actions/running" \
    "$state/actions/results"
do
    assert_eq 700 "$(test_file_mode "$directory")"
done

operation_id=op-1722345678-1234
payload='{"target":"sim1"}'
assert_success zte_action_enqueue \
    "$state" "$operation_id" switch_sim "$payload" 1722345678
record=$state/actions/pending/$operation_id.json
assert_eq 600 "$(test_file_mode "$record")"
expected='{"operation_id":"op-1722345678-1234","type":"switch_sim","state":"queued","payload":{"target":"sim1"},"created":1722345678}'
assert_eq "$expected" "$(cat "$record")"
assert_success zte_action_has_active "$state"
assert_eq "$expected" "$(zte_action_get "$state" "$operation_id")"

assert_failure zte_action_enqueue \
    "$state" op-1722345679-1235 set_wifi '{"enabled":true}' 1722345679
assert_failure zte_action_enqueue \
    "$work/other" op-1722345680-1236 unknown '{}' 1722345680
assert_failure zte_action_enqueue \
    "$work/other" op-1722345680-1236 set_wifi '{"nested":{"value":1}}' 1722345680
assert_failure zte_action_get "$state" op-1722345681-1237

running=$(zte_action_claim "$state")
expected_running='{"operation_id":"op-1722345678-1234","type":"switch_sim","state":"running","payload":{"target":"sim1"},"created":1722345678}'
assert_eq "$expected_running" "$running"
assert_failure test -e "$record"
assert_eq "$expected_running" \
    "$(cat "$state/actions/running/$operation_id.json")"

assert_success zte_action_finish \
    "$state" "$operation_id" failed unsupported 1722345682
expected_result='{"operation_id":"op-1722345678-1234","type":"switch_sim","state":"failed","code":"unsupported","updated":1722345682}'
assert_eq "$expected_result" "$(zte_action_get "$state" "$operation_id")"
assert_failure zte_action_has_active "$state"
assert_failure zte_action_finish \
    "$state" "$operation_id" succeeded ok 1722345683

second_id=op-1722345684-1238
assert_success zte_action_enqueue \
    "$state" "$second_id" set_wifi '{"enabled":true}' 1722345684
zte_action_claim "$state" >/dev/null
assert_success zte_action_recover_running "$state" 1722345685
assert_eq \
    '{"operation_id":"op-1722345684-1238","type":"set_wifi","state":"failed","code":"daemon_restarted","updated":1722345685}' \
    "$(zte_action_get "$state" "$second_id")"

finish
