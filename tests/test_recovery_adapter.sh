#!/bin/sh
# shellcheck disable=SC2317,SC2329
set -eu

TEST_NAME=test_recovery_adapter
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
adapter=$lib/recovery-adapter.sh
if [ ! -f "$adapter" ]; then
    fail 'recovery adapter library must exist'
    finish
fi
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/recovery-inhibit.sh"
# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/recovery-adapter.sh
. "$adapter"

work=$(mktemp -d /tmp/zte-test-recovery-adapter.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
inhibit=$work/inhibit-recovery
service=/etc/init.d/zte-usb-recover
calls=$work/calls
: >"$calls"

assert_success zte_recovery_service_path_valid "$service"
for path in \
    '' /etc/init.d/usb-recover /tmp/zte-usb-recover \
    '/etc/init.d/zte-usb-recover;reboot'
do
    assert_failure zte_recovery_service_path_valid "$path"
done

_zte_test_service_failure=0
_zte_test_service_running=1
_zte_test_stop_takes_effect=1
zte_recovery_service_available() { return 0; }
zte_recovery_service_running() {
    [ "$_zte_test_service_running" = 1 ]
}
zte_recovery_service_control() {
    printf '%s:%s\n' "$1" "$2" >>"$calls"
    case $2 in
        stop)
            if [ "$_zte_test_stop_takes_effect" = 1 ]; then
                _zte_test_service_running=0
            fi
            ;;
        start)
            [ "$_zte_test_service_failure" = 0 ] &&
                _zte_test_service_running=1
            ;;
    esac
    [ "$_zte_test_service_failure" = 0 ]
}

assert_success zte_recovery_prepare_off \
    "$inhibit" battery_high 1722346000 1722345600 "$service"
assert_success zte_recovery_inhibit_active "$inhibit" 1722345999
assert_success zte_recovery_inhibit_restart_required "$inhibit"
assert_eq "$service:stop" "$(cat "$calls")"

: >"$calls"
assert_success zte_recovery_finish_on "$inhibit" "$service"
assert_eq "$service:start" "$(cat "$calls")"
assert_failure test -e "$inhibit"

# A service the administrator had already stopped remains stopped.
: >"$calls"
_zte_test_service_running=0
assert_success zte_recovery_prepare_off \
    "$inhibit" battery_high 1722346000 1722345600 "$service"
assert_failure zte_recovery_inhibit_restart_required "$inhibit"
assert_eq '' "$(cat "$calls")"
assert_success zte_recovery_finish_on "$inhibit" "$service"
assert_eq '' "$(cat "$calls")"
assert_failure test -e "$inhibit"

# If stop fails and the service is still running, do not proceed.
: >"$calls"
_zte_test_service_running=1
_zte_test_service_failure=1
_zte_test_stop_takes_effect=0
assert_failure zte_recovery_prepare_off \
    "$inhibit" battery_high 1722346000 1722345600 "$service"
assert_failure test -e "$inhibit"
assert_eq "$service:stop" "$(cat "$calls")"

# A non-zero stop that nevertheless stopped the service is treated as owned
# and retains its restart marker.
: >"$calls"
_zte_test_service_running=1
_zte_test_stop_takes_effect=1
assert_success zte_recovery_prepare_off \
    "$inhibit" battery_high 1722346000 1722345600 "$service"
assert_success zte_recovery_inhibit_restart_required "$inhibit"
assert_eq "$service:stop" "$(cat "$calls")"

# If restart fails after an ON, retain the timed marker so startup
# reconciliation can retry instead of silently losing coordination state.
: >"$calls"
_zte_test_service_failure=1
assert_failure zte_recovery_finish_on "$inhibit" "$service"
assert_success test -e "$inhibit"
assert_eq "$service:start" "$(cat "$calls")"

# Expired or invalid markers restart the recovery service and are removed.
: >"$calls"
_zte_test_service_failure=0
assert_success zte_recovery_reconcile "$inhibit" 1722346000 "$service"
assert_eq "$service:start" "$(cat "$calls")"
assert_failure test -e "$inhibit"

: >"$calls"
printf '%s\n' '{"invalid":true}' >"$inhibit"
_zte_test_service_running=0
assert_success zte_recovery_reconcile "$inhibit" 1722345600 "$service"
assert_eq "$service:start" "$(cat "$calls")"
assert_failure test -e "$inhibit"

# An active inhibit means a planned outage is still in force: do nothing.
: >"$calls"
assert_success zte_recovery_inhibit_write \
    "$inhibit" battery_high 1722346000 1722345600 true
assert_success zte_recovery_reconcile "$inhibit" 1722345999 "$service"
assert_eq '' "$(cat "$calls")"
assert_success test -e "$inhibit"

# No marker also means no ownership: do not start a service the user may have
# intentionally disabled.
rm -f "$inhibit"
: >"$calls"
assert_success zte_recovery_reconcile "$inhibit" 1722346000 "$service"
assert_eq '' "$(cat "$calls")"

finish
