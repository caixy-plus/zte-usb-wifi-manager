#!/bin/sh
# shellcheck disable=SC2329
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
    reset_traffic send_sms delete_sms mark_sms_read reboot_device shutdown_device \
    set_power_supply_mode
do
    assert_success zte_action_type_valid "$action"
done
for action in '' factory_reset 'switch sim' '../switch_sim' SWITCH_SIM; do
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

prune_state=$work/prune
assert_success zte_action_init "$prune_state"
index=0
while [ "$index" -lt 8 ]; do
    operation_id=op-17223457$((10 + index))-20$index
    assert_success zte_action_enqueue \
        "$prune_state" "$operation_id" set_wifi '{"enabled":true}' \
        "17223457$((10 + index))"
    zte_action_claim "$prune_state" >/dev/null
    assert_success zte_action_finish \
        "$prune_state" "$operation_id" failed unsupported \
        "17223457$((10 + index))"
    index=$((index + 1))
done
assert_success zte_action_prune_results "$prune_state" 5
assert_eq 5 \
    "$(find "$prune_state/actions/results" -type f -name '*.json' |
        wc -l | tr -d ' ')"
assert_failure test -e \
    "$prune_state/actions/results/op-1722345710-200.json"
assert_success test -e \
    "$prune_state/actions/results/op-1722345717-207.json"
assert_failure zte_action_prune_results "$prune_state" 0

concurrent_state=$work/concurrent
success_dir=$work/concurrent-success
mkdir -p "$success_dir"
index=0
while [ "$index" -lt 20 ]; do
    (
        concurrent_id=op-$((1722349000 + index))-$((5000 + index))
        if zte_action_enqueue \
            "$concurrent_state" "$concurrent_id" set_wifi \
            '{"enabled":true}' "$((1722349000 + index))"; then
            : >"$success_dir/$index"
        fi
    ) &
    index=$((index + 1))
done
wait
assert_eq 1 "$(find "$success_dir" -type f | wc -l | tr -d ' ')"
assert_eq 1 "$(
    find "$concurrent_state/actions/pending" -type f -name '*.json' |
        wc -l | tr -d ' '
)"
assert_success test -e "$concurrent_state/actions/active"
concurrent_record=$(zte_action_claim "$concurrent_state")
concurrent_id=$(zte_json_top_get "$concurrent_record" operation_id)
assert_success zte_action_finish \
    "$concurrent_state" "$concurrent_id" failed unsupported 1722349999
assert_failure test -e "$concurrent_state/actions/active"

reconcile_state=$work/reconcile
assert_success zte_action_init "$reconcile_state"
assert_success mkdir "$reconcile_state/actions/active"
assert_success zte_action_reconcile_active "$reconcile_state"
assert_failure test -e "$reconcile_state/actions/active"
assert_success zte_action_enqueue \
    "$reconcile_state" op-1722350000-6000 set_wifi \
    '{"enabled":true}' 1722350000
if [ -d "$reconcile_state/actions/active" ]; then
    assert_success rmdir "$reconcile_state/actions/active"
else
    assert_success rm -f "$reconcile_state/actions/active"
fi
assert_success zte_action_reconcile_active "$reconcile_state"
assert_success test -e "$reconcile_state/actions/active"

transition_state=$work/power-transition
assert_success zte_power_transition_claim "$transition_state"
assert_success zte_power_transition_active "$transition_state"
assert_failure zte_action_enqueue \
    "$transition_state" op-1722351000-7000 switch_sim \
    '{"target":"sim1"}' 1722351000
assert_success zte_power_transition_release "$transition_state"
assert_failure zte_power_transition_active "$transition_state"
assert_success zte_action_enqueue \
    "$transition_state" op-1722351000-7000 switch_sim \
    '{"target":"sim1"}' 1722351000
assert_failure zte_power_transition_claim "$transition_state"
zte_action_claim "$transition_state" >/dev/null
assert_success zte_action_finish \
    "$transition_state" op-1722351000-7000 failed unsupported 1722351001
assert_success zte_power_transition_claim "$transition_state"
assert_success zte_power_transition_release "$transition_state"

# Automatic device writes share the same atomic slot as queued rpcd actions,
# without borrowing the legacy USB power-transition marker.
exclusive_state=$work/device-action-exclusive
assert_success zte_device_action_claim "$exclusive_state"
assert_eq 600 "$(test_file_mode "$exclusive_state/actions/active")"
exclusive_owner=$(cat "$exclusive_state/actions/active")
assert_eq automatic "${exclusive_owner%% *}"
# Reconciliation can run while an owner has atomically claimed the slot but
# has not yet published its pending record. A live owner must never be cleared.
assert_success zte_action_reconcile_active "$exclusive_state"
assert_success test -e "$exclusive_state/actions/active"
assert_failure zte_action_enqueue \
    "$exclusive_state" op-1722352000-7100 set_power_supply_mode \
    '{"mode":"charging"}' 1722352000
assert_failure zte_power_transition_claim "$exclusive_state"
assert_success zte_device_action_release "$exclusive_state"
assert_failure test -e "$exclusive_state/actions/active"
assert_success zte_action_enqueue \
    "$exclusive_state" op-1722352000-7100 set_power_supply_mode \
    '{"mode":"charging"}' 1722352000
assert_failure zte_device_action_claim "$exclusive_state"
assert_success test -f \
    "$exclusive_state/actions/pending/op-1722352000-7100.json"

# Startup reconciliation clears an abandoned recordless automatic slot, but
# it must retain the slot while a queued/running manual record still exists.
assert_success zte_action_reconcile_active "$exclusive_state"
assert_success test -e "$exclusive_state/actions/active"
zte_action_claim "$exclusive_state" >/dev/null
assert_success zte_action_reconcile_active "$exclusive_state"
assert_success test -e "$exclusive_state/actions/active"
assert_success zte_action_finish \
    "$exclusive_state" op-1722352000-7100 failed unsupported 1722352001
assert_success mkdir "$exclusive_state/actions/active"
assert_success zte_action_reconcile_active "$exclusive_state"
assert_failure test -e "$exclusive_state/actions/active"

# A daemon-owned slot whose PID no longer exists is abandoned and may be
# removed, unlike the live claim-before-record window above.
printf '%s\n' 'automatic 999999' >"$exclusive_state/actions/active"
chmod 600 "$exclusive_state/actions/active"
assert_success zte_action_reconcile_active "$exclusive_state"
assert_failure test -e "$exclusive_state/actions/active"

# PID liveness alone is insufficient after reuse. Reconciliation also compares
# the process start identity, while an unreadable identity stays fail-closed.
reuse_state=$work/pid-reuse
test_start_id=111
zte_action_process_start_id() { printf '%s\n' "$test_start_id"; }
assert_success zte_device_action_claim "$reuse_state"
test_start_id=222
assert_success zte_action_reconcile_active "$reuse_state"
assert_failure test -e "$reuse_state/actions/active"
test_start_id=333
assert_success zte_device_action_claim "$reuse_state"
zte_action_process_start_id() { return 1; }
assert_success zte_action_reconcile_active "$reuse_state"
assert_success test -e "$reuse_state/actions/active"
assert_success zte_device_action_release "$reuse_state"

assert_success zte_power_transition_claim "$exclusive_state"
assert_failure zte_device_action_claim "$exclusive_state"
assert_success zte_power_transition_release "$exclusive_state"

finish
