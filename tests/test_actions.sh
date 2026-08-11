#!/bin/sh
# Test doubles intentionally replace commands/functions after earlier test cases.
# shellcheck disable=SC2218,SC2317,SC2329
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

for action in set_power_supply_mode
do
    assert_success zte_action_type_valid "$action"
done
for action in '' factory_reset switch_sim set_apn set_wifi send_sms reboot_device \
    'switch sim' '../switch_sim' SWITCH_SIM; do
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
    "$state/actions/verifying" \
    "$state/actions/results"
do
    assert_eq 700 "$(test_file_mode "$directory")"
done

operation_id=op-1722345678-1234
payload='{"mode":"charging"}'
assert_success zte_action_enqueue \
    "$state" "$operation_id" set_power_supply_mode "$payload" 1722345678
record=$state/actions/pending/$operation_id.json
assert_eq 600 "$(test_file_mode "$record")"
expected='{"operation_id":"op-1722345678-1234","type":"set_power_supply_mode","state":"queued","payload":{"mode":"charging"},"created":1722345678}'
assert_eq "$expected" "$(cat "$record")"
assert_success zte_action_has_active "$state"
assert_eq "$expected" "$(zte_action_get "$state" "$operation_id")"
assert_eq \
    '{"operation_id":"op-1722345678-1234","type":"set_power_supply_mode","state":"queued","created":1722345678}' \
    "$(zte_action_public_status "$state" "$operation_id")"

assert_failure zte_action_enqueue \
    "$state" op-1722345679-1235 set_power_supply_mode '{"mode":"charging"}' 1722345679
assert_failure zte_action_enqueue \
    "$work/other" op-1722345680-1236 unknown '{}' 1722345680
assert_failure zte_action_enqueue \
    "$work/other" op-1722345680-1236 set_power_supply_mode '{"nested":{"value":1}}' 1722345680
assert_failure zte_action_get "$state" op-1722345681-1237

running=$(zte_action_claim "$state")
expected_running='{"operation_id":"op-1722345678-1234","type":"set_power_supply_mode","state":"running","payload":{"mode":"charging"},"created":1722345678}'
assert_eq "$expected_running" "$running"
assert_failure test -e "$record"
assert_eq "$expected_running" \
    "$(cat "$state/actions/running/$operation_id.json")"
assert_eq \
    '{"operation_id":"op-1722345678-1234","type":"set_power_supply_mode","state":"running","created":1722345678}' \
    "$(zte_action_public_status "$state" "$operation_id")"

assert_success zte_action_finish \
    "$state" "$operation_id" failed unsupported 1722345682
expected_result='{"operation_id":"op-1722345678-1234","type":"set_power_supply_mode","state":"failed","code":"unsupported","updated":1722345682}'
assert_eq "$expected_result" "$(zte_action_get "$state" "$operation_id")"
assert_eq "$expected_result" \
    "$(zte_action_public_status "$state" "$operation_id")"
assert_failure zte_action_has_active "$state"
assert_failure zte_action_finish \
    "$state" "$operation_id" succeeded ok 1722345683

second_id=op-1722345684-1238
assert_success zte_action_enqueue \
    "$state" "$second_id" set_power_supply_mode '{"mode":"direct_supply"}' 1722345684
zte_action_claim "$state" >/dev/null
assert_success zte_action_recover_running "$state" 1722345685
assert_eq \
    '{"operation_id":"op-1722345684-1238","type":"set_power_supply_mode","state":"verifying","payload":{"mode":"direct_supply"},"created":1722345684}' \
    "$(zte_action_get "$state" "$second_id")"
assert_failure test -e "$state/actions/running/$second_id.json"
assert_success test -f "$state/actions/verifying/$second_id.json"
assert_success zte_action_has_active "$state"
# A second startup sees an already durable verifying record and does not
# execute or rewrite it.
verifying_before=$(cat "$state/actions/verifying/$second_id.json")
assert_success zte_action_recover_running "$state" 1722345686
assert_eq "$verifying_before" \
    "$(cat "$state/actions/verifying/$second_id.json")"
assert_success zte_action_finish \
    "$state" "$second_id" succeeded verified_after_restart 1722345687
assert_eq \
    '{"operation_id":"op-1722345684-1238","type":"set_power_supply_mode","state":"succeeded","code":"verified_after_restart","updated":1722345687}' \
    "$(zte_action_get "$state" "$second_id")"
assert_failure zte_action_has_active "$state"

# Recovery validates every running record before moving anything. Corruption
# and a duplicate verifying destination stay fail-closed.
corrupt_state=$work/corrupt-recovery
assert_success zte_action_init "$corrupt_state"
printf '%s\n' '{"operation_id":"wrong","type":"set_power_supply_mode","state":"running","payload":{"mode":"direct_supply"},"created":1722345684}' \
    >"$corrupt_state/actions/running/op-1722345688-1240.json"
chmod 600 "$corrupt_state/actions/running/op-1722345688-1240.json"
assert_failure zte_action_recover_running "$corrupt_state" 1722345689
assert_success test -f \
    "$corrupt_state/actions/running/op-1722345688-1240.json"

duplicate_state=$work/duplicate-recovery
duplicate_id=op-1722345690-1241
assert_success zte_action_enqueue \
    "$duplicate_state" "$duplicate_id" set_power_supply_mode '{"mode":"charging"}' 1722345690
zte_action_claim "$duplicate_state" >/dev/null
cp "$duplicate_state/actions/running/$duplicate_id.json" \
    "$duplicate_state/actions/verifying/$duplicate_id.json"
sed 's/"state":"running"/"state":"verifying"/' \
    "$duplicate_state/actions/verifying/$duplicate_id.json" \
    >"$duplicate_state/actions/verifying/$duplicate_id.json.tmp"
mv "$duplicate_state/actions/verifying/$duplicate_id.json.tmp" \
    "$duplicate_state/actions/verifying/$duplicate_id.json"
chmod 600 "$duplicate_state/actions/verifying/$duplicate_id.json"
assert_success zte_action_recover_running "$duplicate_state" 1722345691
assert_failure test -e "$duplicate_state/actions/running/$duplicate_id.json"
assert_success test -f "$duplicate_state/actions/verifying/$duplicate_id.json"

# A crash after pending->running rename but before the state rewrite proves no
# POST was issued. Startup recovery restores the queued record.
queued_window_state=$work/queued-window
queued_window_id=op-1722345692-1242
assert_success zte_action_enqueue \
    "$queued_window_state" "$queued_window_id" set_power_supply_mode \
    '{"mode":"charging"}' 1722345692
real_mv=$(command -v mv)
mv_calls=$work/queued-window-mv-calls
: >"$mv_calls"
mv() {
    printf '%s\n' call >>"$mv_calls"
    if [ "$(wc -l <"$mv_calls" | tr -d ' ')" -eq 2 ]; then
        return 1
    fi
    "$real_mv" "$@"
}
assert_failure zte_action_claim "$queued_window_state"
unset -f mv 2>/dev/null || unset mv
assert_success test -f \
    "$queued_window_state/actions/running/$queued_window_id.json"
assert_eq queued "$(zte_json_top_get \
    "$(cat "$queued_window_state/actions/running/$queued_window_id.json")" \
    state)"
assert_success zte_action_recover_running "$queued_window_state" 1722345693
assert_failure test -e \
    "$queued_window_state/actions/running/$queued_window_id.json"
assert_success test -f \
    "$queued_window_state/actions/pending/$queued_window_id.json"
assert_failure test -e \
    "$queued_window_state/actions/verifying/$queued_window_id.json"

# A crash after running->verifying rename leaves a recoverable record whose
# stale state is repaired idempotently on the next startup.
rename_window_state=$work/rename-window
rename_window_id=op-1722345694-1244
assert_success zte_action_enqueue \
    "$rename_window_state" "$rename_window_id" set_power_supply_mode \
    '{"mode":"direct_supply"}' 1722345694
zte_action_claim "$rename_window_state" >/dev/null
: >"$mv_calls"
mv() {
    printf '%s\n' call >>"$mv_calls"
    if [ "$(wc -l <"$mv_calls" | tr -d ' ')" -eq 2 ]; then
        return 1
    fi
    "$real_mv" "$@"
}
assert_failure zte_action_recover_running "$rename_window_state" 1722345695
unset -f mv 2>/dev/null || unset mv
assert_failure test -e \
    "$rename_window_state/actions/running/$rename_window_id.json"
assert_success test -f \
    "$rename_window_state/actions/verifying/$rename_window_id.json"
assert_eq running "$(zte_json_top_get \
    "$(cat "$rename_window_state/actions/verifying/$rename_window_id.json")" \
    state)"
assert_success zte_action_recover_running "$rename_window_state" 1722345696
assert_eq verifying "$(zte_json_top_get \
    "$(cat "$rename_window_state/actions/verifying/$rename_window_id.json")" \
    state)"

# Failure while preparing the replacement state file also retains the renamed
# authoritative record and is repairable on the next pass.
temp_window_state=$work/temp-window
temp_window_id=op-1722345697-1245
assert_success zte_action_enqueue \
    "$temp_window_state" "$temp_window_id" set_power_supply_mode \
    '{"mode":"direct_supply"}' 1722345697
zte_action_claim "$temp_window_state" >/dev/null
real_chmod=$(command -v chmod)
chmod() {
    case $1 in
        600)
            case $2 in *.tmp.*) return 1 ;; esac
            ;;
    esac
    "$real_chmod" "$@"
}
assert_failure zte_action_recover_running "$temp_window_state" 1722345698
unset -f chmod 2>/dev/null || unset chmod
assert_failure test -e \
    "$temp_window_state/actions/running/$temp_window_id.json"
assert_eq running "$(zte_json_top_get \
    "$(cat "$temp_window_state/actions/verifying/$temp_window_id.json")" \
    state)"
assert_success zte_action_recover_running "$temp_window_state" 1722345699
assert_eq verifying "$(zte_json_top_get \
    "$(cat "$temp_window_state/actions/verifying/$temp_window_id.json")" \
    state)"

# Divergent natural duplicates are never guessed away.
divergent_dual_state=$work/divergent-dual
divergent_dual_id=op-1722345699-1249
assert_success zte_action_enqueue \
    "$divergent_dual_state" "$divergent_dual_id" set_power_supply_mode \
    '{"enabled":false}' 1722345699
zte_action_claim "$divergent_dual_state" >/dev/null
sed -e 's/"state":"running"/"state":"verifying"/' \
    -e 's/"enabled":false/"enabled":true/' \
    "$divergent_dual_state/actions/running/$divergent_dual_id.json" \
    >"$divergent_dual_state/actions/verifying/$divergent_dual_id.json"
chmod 600 \
    "$divergent_dual_state/actions/verifying/$divergent_dual_id.json"
assert_failure zte_action_recover_running "$divergent_dual_state" 1722345700
assert_success test -f \
    "$divergent_dual_state/actions/running/$divergent_dual_id.json"
assert_success test -f \
    "$divergent_dual_state/actions/verifying/$divergent_dual_id.json"

# Unsafe recovery entries are distinguishable from an empty queue (status 2),
# including dangling symlinks and oversized regular files.
unsafe_recovery_state=$work/unsafe-recovery
assert_success zte_action_init "$unsafe_recovery_state"
unsafe_recovery_id=op-1722345701-1251
ln -s "$work/missing-record" \
    "$unsafe_recovery_state/actions/verifying/$unsafe_recovery_id.json"
if zte_action_verifying_next "$unsafe_recovery_state" >/dev/null 2>&1; then
    unsafe_recovery_status=0
else
    unsafe_recovery_status=$?
fi
assert_eq 2 "$unsafe_recovery_status"
rm "$unsafe_recovery_state/actions/verifying/$unsafe_recovery_id.json"
dd if=/dev/zero \
    of="$unsafe_recovery_state/actions/verifying/$unsafe_recovery_id.json" \
    bs=1024 count=65 2>/dev/null
chmod 600 \
    "$unsafe_recovery_state/actions/verifying/$unsafe_recovery_id.json"

# File size/mode/type checks happen before record content is read. Neither
# public status nor recovery may cat/wc an oversized record into memory.
unsafe_read_log=$work/unsafe-read-log
: >"$unsafe_read_log"
real_cat=$(command -v cat)
real_wc=$(command -v wc)
cat() {
    case ${1-} in
        "$unsafe_recovery_state"/actions/*)
            printf '%s\n' cat >>"$unsafe_read_log"
            ;;
    esac
    "$real_cat" "$@"
}
wc() {
    printf '%s\n' wc >>"$unsafe_read_log"
    "$real_wc" "$@"
}
assert_failure zte_action_public_status \
    "$unsafe_recovery_state" "$unsafe_recovery_id"
assert_eq '' "$("$real_cat" "$unsafe_read_log")"
assert_failure zte_action_recover_running \
    "$unsafe_recovery_state" 1722345702
assert_eq '' "$("$real_cat" "$unsafe_read_log")"
unset -f cat 2>/dev/null || unset cat
unset -f wc 2>/dev/null || unset wc

# Publishing the terminal result is the commit point. If source cleanup
# fails, restart recovery preserves that result byte-for-byte and only removes
# the matching residual source/slot.
terminal_commit_state=$work/terminal-commit
terminal_commit_id=op-1722345703-1253
assert_success zte_action_enqueue \
    "$terminal_commit_state" "$terminal_commit_id" set_power_supply_mode \
    '{"enabled":false}' 1722345703
zte_action_claim "$terminal_commit_state" >/dev/null
assert_success zte_action_recover_running \
    "$terminal_commit_state" 1722345704
terminal_commit_source=$terminal_commit_state/actions/verifying/$terminal_commit_id.json
real_rm=$(command -v rm)
rm() {
    if [ "${1-}" = "$terminal_commit_source" ]; then
        return 1
    fi
    "$real_rm" "$@"
}
assert_failure zte_action_finish \
    "$terminal_commit_state" "$terminal_commit_id" succeeded \
    verified_after_restart 1722345705
unset -f rm 2>/dev/null || unset rm
terminal_commit_result=$terminal_commit_state/actions/results/$terminal_commit_id.json
assert_success test -f "$terminal_commit_source"
assert_success test -f "$terminal_commit_result"
terminal_commit_before=$(cat "$terminal_commit_result")
assert_success zte_action_recover_running \
    "$terminal_commit_state" 1722345706
assert_failure test -e "$terminal_commit_source"
assert_eq "$terminal_commit_before" "$(cat "$terminal_commit_result")"
assert_eq "$terminal_commit_before" \
    "$(zte_action_public_status "$terminal_commit_state" "$terminal_commit_id")"
assert_failure zte_action_has_active "$terminal_commit_state"

# A conflicting terminal result is never allowed to erase or supersede the
# nonterminal source.
terminal_conflict_state=$work/terminal-conflict
terminal_conflict_id=op-1722345707-1257
assert_success zte_action_enqueue \
    "$terminal_conflict_state" "$terminal_conflict_id" set_power_supply_mode \
    '{"enabled":true}' 1722345707
zte_action_claim "$terminal_conflict_state" >/dev/null
assert_success zte_action_recover_running \
    "$terminal_conflict_state" 1722345708
printf '%s\n' \
    '{"operation_id":"op-1722345707-1257","type":"set_apn","state":"succeeded","code":"ok","updated":1722345708}' \
    >"$terminal_conflict_state/actions/results/$terminal_conflict_id.json"
chmod 600 \
    "$terminal_conflict_state/actions/results/$terminal_conflict_id.json"
assert_failure zte_action_recover_running \
    "$terminal_conflict_state" 1722345709
assert_success test -f \
    "$terminal_conflict_state/actions/verifying/$terminal_conflict_id.json"
assert_success test -f \
    "$terminal_conflict_state/actions/results/$terminal_conflict_id.json"

prune_state=$work/prune
assert_success zte_action_init "$prune_state"
index=0
while [ "$index" -lt 8 ]; do
    operation_id=op-17223457$((10 + index))-20$index
    assert_success zte_action_enqueue \
        "$prune_state" "$operation_id" set_power_supply_mode '{"mode":"charging"}' \
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
            "$concurrent_state" "$concurrent_id" set_power_supply_mode \
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
    "$reconcile_state" op-1722350000-6000 set_power_supply_mode \
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
    "$transition_state" op-1722351000-7000 set_power_supply_mode \
    '{"mode":"charging"}' 1722351000
assert_success zte_power_transition_release "$transition_state"
assert_failure zte_power_transition_active "$transition_state"
assert_success zte_action_enqueue \
    "$transition_state" op-1722351000-7000 set_power_supply_mode \
    '{"mode":"charging"}' 1722351000
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
printf '%s\n' 'automatic 999999 123' >"$exclusive_state/actions/active"
chmod 600 "$exclusive_state/actions/active"
assert_success zte_action_reconcile_active "$exclusive_state"
assert_failure test -e "$exclusive_state/actions/active"

# Unverifiable owners and unsafe slot types are not proof of staleness. Keep
# them fail-closed; only the recognized empty legacy directory above is clear.
unknown_state=$work/unknown-owner
assert_success zte_action_init "$unknown_state"
printf '%s\n' malformed >"$unknown_state/actions/active"
chmod 600 "$unknown_state/actions/active"
assert_success zte_action_reconcile_active "$unknown_state"
assert_success test -f "$unknown_state/actions/active"
rm -f "$unknown_state/actions/active"
printf '%s\n' 'automatic 999999 123' >"$unknown_state/actions/active"
chmod 644 "$unknown_state/actions/active"
assert_success zte_action_reconcile_active "$unknown_state"
assert_success test -f "$unknown_state/actions/active"
rm -f "$unknown_state/actions/active"
ln -s "$work/missing-owner-target" "$unknown_state/actions/active"
assert_success zte_action_reconcile_active "$unknown_state"
assert_success test -L "$unknown_state/actions/active"
rm -f "$unknown_state/actions/active"
mkfifo "$unknown_state/actions/active"
assert_success zte_action_reconcile_active "$unknown_state"
assert_success test -p "$unknown_state/actions/active"
rm -f "$unknown_state/actions/active"

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

permission_state=$work/owner-permission
test_start_id=444
zte_action_process_start_id() { printf '%s\n' "$test_start_id"; }
assert_success zte_device_action_claim "$permission_state"
zte_action_process_liveness() { return 2; }
if zte_action_slot_owner_live "$permission_state"; then
    owner_status=0
else
    owner_status=$?
fi
assert_eq 2 "$owner_status"
assert_success zte_action_reconcile_active "$permission_state"
assert_success test -e "$permission_state/actions/active"
assert_success zte_device_action_release "$permission_state"

# Every mutation of actions/active shares one short atomic guard. While held,
# claim, reconcile, and release all fail closed without changing the slot.
guard_state=$work/active-guard
assert_success zte_device_action_claim "$guard_state"
guard_owner_before=$(cat "$guard_state/actions/active")
assert_success zte_action_guard_claim "$guard_state"
assert_failure zte_device_action_claim "$guard_state"
assert_failure zte_action_reconcile_active "$guard_state"
assert_failure zte_device_action_release "$guard_state"
assert_eq "$guard_owner_before" "$(cat "$guard_state/actions/active")"
assert_success zte_action_guard_release "$guard_state"
assert_success zte_device_action_release "$guard_state"

untrusted_guard_state=$work/untrusted-active-guard
assert_success zte_device_action_claim "$untrusted_guard_state"
untrusted_owner=$(cat "$untrusted_guard_state/actions/active")
ln -s "$work/untrusted-guard-target" \
    "$untrusted_guard_state/actions/active.guard"
assert_failure zte_device_action_claim "$untrusted_guard_state"
assert_failure zte_action_reconcile_active "$untrusted_guard_state"
assert_failure zte_device_action_release "$untrusted_guard_state"
assert_eq "$untrusted_owner" \
    "$(cat "$untrusted_guard_state/actions/active")"
rm -f "$untrusted_guard_state/actions/active.guard"
assert_success zte_device_action_release "$untrusted_guard_state"

# A first reconciler may clear a proven stale owner. A successor can then
# claim, and a later reconciler must observe and retain that successor.
successor_state=$work/reconcile-successor
zte_action_process_liveness() {
    [ "$1" != 999999 ]
}
assert_success zte_action_init "$successor_state"
printf '%s\n' 'automatic 999999 123' >"$successor_state/actions/active"
chmod 600 "$successor_state/actions/active"
assert_success zte_action_reconcile_active "$successor_state"
assert_failure test -e "$successor_state/actions/active"
assert_success zte_device_action_claim "$successor_state"
successor_owner=$(cat "$successor_state/actions/active")
assert_success zte_action_reconcile_active "$successor_state"
assert_eq "$successor_owner" "$(cat "$successor_state/actions/active")"
assert_success zte_device_action_release "$successor_state"

assert_success zte_power_transition_claim "$exclusive_state"
assert_failure zte_device_action_claim "$exclusive_state"
assert_success zte_power_transition_release "$exclusive_state"

# If the slot was absent at the initial observation, reconciliation returns
# without a stale removal. Inject a new claim immediately after that observed
# absence to make the former check/remove race deterministic.
race_state=$work/reconcile-race
assert_success zte_action_init "$race_state"
zte_action_slot_observe() {
    printf '%s\n' "automatic $$ portable" >"$race_state/actions/active"
    chmod 600 "$race_state/actions/active"
    printf '%s\n' absent
}
assert_success zte_action_reconcile_active "$race_state"
assert_success test -f "$race_state/actions/active"

# Once the hard-link publication succeeds, failure to remove the private temp
# name is cleanup debt, not a failed claim with a live active slot.
cleanup_state=$work/post-publish-cleanup
cleanup_log=$work/post-publish-cleanup-called
zte_action_slot_tmp_cleanup() {
    printf '%s\n' called >"$cleanup_log"
    return 1
}
assert_success zte_device_action_claim "$cleanup_state"
assert_success test -f "$cleanup_state/actions/active"
assert_eq called "$(cat "$cleanup_log")"
assert_success zte_device_action_release "$cleanup_state"

# Recovery shares the active guard. A competing recovery attempt cannot move
# the running record, and a later pass moves it exactly once to verifying.
dual_state=$work/dual-recoverer
dual_id=op-1722353000-7200
assert_success zte_action_enqueue \
    "$dual_state" "$dual_id" set_power_supply_mode '{"mode":"charging"}' 1722353000
zte_action_claim "$dual_state" >/dev/null
assert_success zte_action_guard_claim "$dual_state"
assert_failure zte_action_recover_running "$dual_state" 1722353001
assert_success test -f "$dual_state/actions/running/$dual_id.json"
assert_failure test -e "$dual_state/actions/verifying/$dual_id.json"
assert_success zte_action_guard_release "$dual_state"
assert_success zte_action_recover_running "$dual_state" 1722353002
assert_failure test -e "$dual_state/actions/running/$dual_id.json"
assert_success test -f "$dual_state/actions/verifying/$dual_id.json"
assert_success zte_action_finish \
    "$dual_state" "$dual_id" timed_out verification_inconclusive 1722353003

# If active ownership is externally replaced by a later automatic writer,
# finishing the durable verification record must never unlink that successor.
finish_successor_state=$work/finish-successor
finish_successor_id=op-1722353010-7210
assert_success zte_action_enqueue \
    "$finish_successor_state" "$finish_successor_id" set_power_supply_mode \
    '{"enabled":false}' 1722353010
zte_action_claim "$finish_successor_state" >/dev/null
assert_success zte_action_recover_running "$finish_successor_state" 1722353011
finish_successor_start=$(zte_action_process_start_id "$$")
printf 'automatic %s %s\n' "$$" "$finish_successor_start" \
    >"$finish_successor_state/actions/active"
chmod 600 "$finish_successor_state/actions/active"
finish_successor_owner=$(cat "$finish_successor_state/actions/active")
assert_success zte_action_finish \
    "$finish_successor_state" "$finish_successor_id" succeeded \
    verified_after_restart 1722353012
assert_eq "$finish_successor_owner" \
    "$(cat "$finish_successor_state/actions/active")"
assert_success zte_device_action_release "$finish_successor_state"

# A repaired/manual successor uses the same queue owner format. Its remaining
# durable record, not just the slot owner label, prevents the older verifying
# operation from deleting the successor's slot.
manual_successor_state=$work/finish-manual-successor
old_id=op-1722353020-7220
new_id=op-1722353021-7221
assert_success zte_action_enqueue \
    "$manual_successor_state" "$old_id" set_power_supply_mode \
    '{"enabled":true}' 1722353020
zte_action_claim "$manual_successor_state" >/dev/null
assert_success zte_action_recover_running "$manual_successor_state" 1722353021
printf '%s\n' \
    '{"operation_id":"op-1722353021-7221","type":"set_power_supply_mode","state":"queued","payload":{"mode":"charging"},"created":1722353021}' \
    >"$manual_successor_state/actions/pending/$new_id.json"
chmod 600 "$manual_successor_state/actions/pending/$new_id.json"
manual_successor_owner=$(cat "$manual_successor_state/actions/active")
assert_success zte_action_finish \
    "$manual_successor_state" "$old_id" succeeded \
    verified_after_restart 1722353022
assert_eq "$manual_successor_owner" \
    "$(cat "$manual_successor_state/actions/active")"
zte_action_claim "$manual_successor_state" >/dev/null
assert_success zte_action_finish \
    "$manual_successor_state" "$new_id" failed unsupported 1722353023

finish
