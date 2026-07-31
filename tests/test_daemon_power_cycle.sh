#!/bin/sh
# shellcheck disable=SC2034,SC2218,SC2317,SC2329
set -eu

TEST_NAME=test_daemon_power_cycle
. ./tests/testlib.sh

backend=./package/zte-usb-wifi-manager
daemon=$backend/files/usr/sbin/zte-usb-wifi-managerd
lib=$backend/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/snapshot.sh"

extract_daemon_function() {
    sed -n "/^$1() {$/,/^}$/p" "$daemon"
}
eval "$(extract_daemon_function write_power_status)"
eval "$(extract_daemon_function handle_planned_power_off)"
eval "$(extract_daemon_function power_inhibit_expiry)"

work=$(mktemp -d /tmp/zte-test-daemon-power-cycle.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
status_log=$work/status
sleep_log=$work/sleep
state_log=$work/state
: >"$status_log"
: >"$sleep_log"
: >"$state_log"

last_device_json='{"online":true,"model":"U25S","battery":{"percent":100,"charging":false}}'
network_json='{"up":false,"l3_device":"eth2","ipv4":"","gateway":"","is_default_route":false}'
failures=0
test_now=1722345600
power_probe_settle_seconds=15
power_off_probe_interval=900
poll_interval=30
RECOVERY_INHIBIT_FILE=$work/inhibit-recovery
planned_power_off=1
next_power_probe_at=1722346500
restore_result=0

date() { printf '%s\n' "$test_now"; }
renew_log=$work/renew
: >"$renew_log"
zte_recovery_inhibit_renew() {
    printf '%s:%s\n' "$2" "$3" >"$renew_log"
}
collect_network() { :; }
write_status() { printf '%s\n' "$1" >>"$status_log"; }
record_state_change() {
    printf '%s:%s\n' "$1" "$2" >>"$state_log"
}
sleep() { printf '%s\n' "$1" >>"$sleep_log"; }
restore_power_on() {
    [ "$restore_result" = 0 ] || return 1
    planned_power_off=0
    next_power_probe_at=0
}

# Before the next scheduled probe, expected device unreachability is explicit
# state and never increments the transport failure counter.
assert_success handle_planned_power_off
assert_eq \
    "$(zte_snapshot_compose planned_off battery_high "$last_device_json" \
        "$network_json" MAINTAIN_BATTERY OFF 0 "$test_now")" \
    "$(cat "$status_log")"
assert_eq 'planned_off:1722345600' "$(cat "$state_log")"
assert_eq 0 "$failures"
assert_eq '' "$(cat "$sleep_log")"
assert_eq '1722346575:1722345600' "$(cat "$renew_log")"

# A long valid poll interval must not let the recovery lease expire before
# the next planned-off renewal.
poll_interval=300
power_off_probe_interval=60
power_probe_settle_seconds=1
next_power_probe_at=1722346500
assert_success handle_planned_power_off
assert_eq '1722345990:1722345600' "$(cat "$renew_log")"

# At the probe deadline, restore power, allow enumeration to settle, then
# return "not handled" so poll_once performs a real status read.
: >"$status_log"
: >"$state_log"
test_now=1722346500
poll_interval=30
power_off_probe_interval=900
power_probe_settle_seconds=15
assert_failure handle_planned_power_off
assert_eq 0 "$planned_power_off"
assert_eq 0 "$next_power_probe_at"
assert_eq 15 "$(cat "$sleep_log")"
assert_eq '' "$(cat "$status_log")"

# A failed power restore remains fail-safe and does not attempt a device read.
: >"$sleep_log"
planned_power_off=1
next_power_probe_at=1722346500
restore_result=1
assert_success handle_planned_power_off
assert_eq \
    "$(zte_snapshot_compose fail_safe power_restore_failed \
        "$last_device_json" "$network_json" FAIL_SAFE_ON ON 0 "$test_now")" \
    "$(cat "$status_log")"
assert_eq '' "$(cat "$sleep_log")"
assert_eq 1 "$planned_power_off"

finish
