#!/bin/sh
set -eu

TEST_NAME=test_recovery_coordinator
. ./tests/testlib.sh

coordinator=./package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-recovery-coordinatord
if [ ! -f "$coordinator" ]; then
    fail 'recovery coordinator daemon must exist'
    finish
fi

work=$(mktemp -d /tmp/zte-test-recovery-coordinator.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
inhibit=$work/inhibit
calls=$work/service-calls
bin=$work/bin
state=$work/state
mkdir -p "$bin" "$state/actions"
: >"$calls"

cat >"$bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' "${ZTE_TEST_NOW:-1722345600}"
EOF
cat >"$bin/sleep" <<'EOF'
#!/bin/sh
cat "$ZTE_RECOVERY_COORDINATOR_PID_FILE" >"$ZTE_TEST_OBSERVED_PID"
if [ -n "${ZTE_TEST_SLEEP_LOG:-}" ]; then
    printf '%s\n' "$1" >>"$ZTE_TEST_SLEEP_LOG"
    calls=$(wc -l <"$ZTE_TEST_SLEEP_LOG" | tr -d ' ')
    [ "$calls" -lt "${ZTE_TEST_SLEEP_LIMIT:-1}" ] || exit 1
    exit 0
fi
exit 1
EOF
cat >"$bin/mkdir" <<'EOF'
#!/bin/sh
if [ "${ZTE_TEST_CLAIM_RACE:-0}" = 1 ] && [ "$#" -eq 1 ] &&
    [ "$1" = "$ZTE_RECOVERY_COORDINATOR_STATE_DIR/actions/power-transition" ]; then
    /bin/mkdir "$1"
    exit 1
fi
exec /bin/mkdir "$@"
EOF
cat >"$bin/logger" <<'EOF'
#!/bin/sh
[ -n "${ZTE_TEST_LOGGER_CALLS:-}" ] || exit 0
printf '%s\n' "$*" >>"$ZTE_TEST_LOGGER_CALLS"
EOF
chmod +x "$bin/date"
chmod +x "$bin/sleep"
chmod +x "$bin/mkdir"
chmod +x "$bin/logger"
cat >"$bin/power-restore" <<'EOF'
#!/bin/sh
[ -d "$ZTE_RECOVERY_COORDINATOR_STATE_DIR/actions/power-transition" ] || exit 1
printf '%s\n' restore >>"$ZTE_TEST_RESTORE_CALLS"
restore_count=$(wc -l <"$ZTE_TEST_RESTORE_CALLS" | tr -d ' ')
pattern_failure=0
case ${ZTE_TEST_RESTORE_PATTERN:-}:$restore_count in
    fail-success-fail:1|fail-success-fail:3) pattern_failure=1 ;;
esac
if [ "${ZTE_TEST_RESTORE_FAILURE:-0}" != 0 ] ||
    [ "$pattern_failure" = 1 ]; then
    [ "${ZTE_POWER_RESTORE_COORDINATOR_CLAIM:-0}" != 1 ] ||
        rmdir "$ZTE_RECOVERY_COORDINATOR_STATE_DIR/actions/power-transition"
    exit 1
fi
{ [ ! -e "$ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE" ] &&
    [ ! -L "$ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE" ]; } ||
    printf '%s\n' start >>"$ZTE_TEST_RESTORE_ACTIONS"
rm -f "$ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE"
rmdir "$ZTE_RECOVERY_COORDINATOR_STATE_DIR/actions/power-transition" \
    2>/dev/null || :
EOF
chmod +x "$bin/power-restore"
: >"$work/restore-calls"
: >"$work/restore-actions"

coordinator_call() {
    ZTE_RECOVERY_COORDINATOR_LIB_DIR=$lib \
    ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE=$inhibit \
    ZTE_RECOVERY_COORDINATOR_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_RECOVERY_COORDINATOR_STATE_DIR=$state \
    ZTE_RECOVERY_COORDINATOR_RESTORE_HELPER=$bin/power-restore \
    ZTE_RECOVERY_TEST_SERVICE_CALLS=$calls \
    ZTE_TEST_RESTORE_CALLS=$work/restore-calls \
    ZTE_TEST_RESTORE_ACTIONS=$work/restore-actions \
    ZTE_RECOVERY_TEST_SERVICE_AVAILABLE=1 \
    PATH="$bin:$PATH" \
        sh "$coordinator" once
}

# Inject only the external service boundary. Production validation, inhibit
# parsing, and reconciliation remain the real shipped implementations.
export ZTE_RECOVERY_TEST_MODE=1

assert_success coordinator_call
assert_eq '' "$(cat "$calls")"
assert_eq restore "$(cat "$work/restore-calls")"
assert_eq '' "$(cat "$work/restore-actions")"

# Losing the atomic transition claim to a concurrent manager must defer the
# restore without invoking the helper.
: >"$work/restore-calls"
ZTE_TEST_CLAIM_RACE=1 assert_failure coordinator_call
assert_eq '' "$(cat "$work/restore-calls")"
assert_success test -d "$state/actions/power-transition"
unset ZTE_TEST_CLAIM_RACE
rmdir "$state/actions/power-transition" 2>/dev/null || :

. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/recovery-inhibit.sh"
: >"$work/restore-calls"
: >"$work/restore-actions"
assert_success zte_recovery_inhibit_write \
    "$inhibit" battery_high 1722346000 1722345500 true
assert_success coordinator_call
assert_eq '' "$(cat "$calls")"
assert_eq '' "$(cat "$work/restore-calls")"
assert_eq '' "$(cat "$work/restore-actions")"
assert_success test -e "$inhibit"

ZTE_TEST_NOW=1722346000 ZTE_TEST_RESTORE_FAILURE=1 \
    assert_failure coordinator_call
assert_eq restore "$(cat "$work/restore-calls")"
assert_eq '' "$(cat "$calls")"
assert_eq '' "$(cat "$work/restore-actions")"
assert_success test -e "$inhibit"
unset ZTE_TEST_RESTORE_FAILURE

: >"$work/restore-calls"
: >"$work/restore-actions"
ZTE_TEST_NOW=1722346000 assert_success coordinator_call
assert_eq restore "$(cat "$work/restore-calls")"
assert_eq '' "$(cat "$calls")"
assert_eq start "$(cat "$work/restore-actions")"
assert_failure test -e "$inhibit"

assert_success zte_recovery_inhibit_write \
    "$inhibit" battery_high 1722346000 1722345500 true
mkdir "$state/actions/power-transition"
: >"$calls"
: >"$work/restore-calls"
: >"$work/restore-actions"
assert_success env ZTE_TEST_NOW=1722346000 \
    ZTE_RECOVERY_COORDINATOR_LIB_DIR="$lib" \
    ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE="$inhibit" \
    ZTE_RECOVERY_COORDINATOR_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_RECOVERY_COORDINATOR_STATE_DIR="$state" \
    ZTE_RECOVERY_COORDINATOR_RESTORE_HELPER="$bin/power-restore" \
    ZTE_RECOVERY_TEST_MODE=1 \
    ZTE_RECOVERY_TEST_SERVICE_CALLS="$calls" \
    ZTE_RECOVERY_TEST_SERVICE_AVAILABLE=1 \
    ZTE_TEST_RESTORE_CALLS="$work/restore-calls" \
    ZTE_TEST_RESTORE_ACTIONS="$work/restore-actions" \
    PATH="$bin:$PATH" \
    sh "$coordinator" once
assert_eq restore "$(cat "$work/restore-calls")"
assert_eq '' "$(cat "$calls")"
assert_eq start "$(cat "$work/restore-actions")"
assert_failure test -e "$inhibit"
assert_failure test -d "$state/actions/power-transition"

printf '%s\n' '{"invalid":true}' >"$inhibit"
: >"$calls"
: >"$work/restore-calls"
: >"$work/restore-actions"
assert_success coordinator_call
assert_eq restore "$(cat "$work/restore-calls")"
assert_eq '' "$(cat "$calls")"
assert_eq start "$(cat "$work/restore-actions")"
assert_failure test -e "$inhibit"

# A dangling symlink is an invalid marker, not the claim-before-marker window.
ln -s "$work/missing-inhibit-target" "$inhibit"
mkdir "$state/actions/power-transition"
: >"$work/restore-calls"
: >"$work/restore-actions"
assert_success coordinator_call
assert_eq restore "$(cat "$work/restore-calls")"
assert_eq start "$(cat "$work/restore-actions")"
assert_failure test -L "$inhibit"
assert_failure test -d "$state/actions/power-transition"

# An active transition with no marker is the brief claim-before-marker window.
# The coordinator must not race its owner by invoking the restore helper.
mkdir "$state/actions/power-transition"
: >"$work/restore-calls"
: >"$work/restore-actions"
assert_success coordinator_call
assert_eq '' "$(cat "$work/restore-calls")"
assert_eq '' "$(cat "$work/restore-actions")"
assert_success test -d "$state/actions/power-transition"
rmdir "$state/actions/power-transition"

observed_pid=$work/observed-pid
coordinator_pid=$work/coordinator.pid
assert_failure env \
    ZTE_RECOVERY_COORDINATOR_LIB_DIR="$lib" \
    ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE="$inhibit" \
    ZTE_RECOVERY_COORDINATOR_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_RECOVERY_COORDINATOR_INTERVAL=10 \
    ZTE_RECOVERY_COORDINATOR_PID_FILE="$coordinator_pid" \
    ZTE_RECOVERY_TEST_MODE=1 \
    ZTE_RECOVERY_TEST_SERVICE_CALLS="$calls" \
    ZTE_RECOVERY_TEST_SERVICE_AVAILABLE=1 \
    ZTE_TEST_OBSERVED_PID="$observed_pid" \
    PATH="$bin:$PATH" \
    sh "$coordinator" run
assert_success test -s "$observed_pid"
assert_failure test -e "$coordinator_pid"

sleep_log=$work/sleep-log
logger_calls=$work/logger-calls
: >"$sleep_log"
: >"$logger_calls"
assert_failure env \
    ZTE_RECOVERY_COORDINATOR_LIB_DIR="$lib" \
    ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE="$inhibit" \
    ZTE_RECOVERY_COORDINATOR_INTERVAL=10 \
    ZTE_RECOVERY_COORDINATOR_LOG_MAX_INTERVAL=40 \
    ZTE_RECOVERY_COORDINATOR_PID_FILE="$coordinator_pid" \
    ZTE_RECOVERY_COORDINATOR_RESTORE_HELPER="$work/missing-helper" \
    ZTE_RECOVERY_COORDINATOR_STATE_DIR="$state" \
    ZTE_RECOVERY_TEST_MODE=1 \
    ZTE_RECOVERY_TEST_SERVICE_CALLS="$calls" \
    ZTE_RECOVERY_TEST_SERVICE_AVAILABLE=1 \
    ZTE_TEST_OBSERVED_PID="$observed_pid" \
    ZTE_TEST_SLEEP_LOG="$sleep_log" \
    ZTE_TEST_SLEEP_LIMIT=4 \
    ZTE_TEST_LOGGER_CALLS="$logger_calls" \
    PATH="$bin:$PATH" \
    sh "$coordinator" run
assert_eq "10
10
10
10" "$(cat "$sleep_log")"
assert_eq 3 "$(wc -l <"$logger_calls" | tr -d ' ')"
assert_failure test -e "$coordinator_pid"

# A successful recovery resets log throttling immediately; a new failure is
# logged at once while recovery attempts remain at the base interval.
: >"$sleep_log"
: >"$logger_calls"
: >"$work/restore-calls"
assert_failure env \
    ZTE_RECOVERY_COORDINATOR_LIB_DIR="$lib" \
    ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE="$inhibit" \
    ZTE_RECOVERY_COORDINATOR_INTERVAL=10 \
    ZTE_RECOVERY_COORDINATOR_LOG_MAX_INTERVAL=40 \
    ZTE_RECOVERY_COORDINATOR_PID_FILE="$coordinator_pid" \
    ZTE_RECOVERY_COORDINATOR_RESTORE_HELPER="$bin/power-restore" \
    ZTE_RECOVERY_COORDINATOR_STATE_DIR="$state" \
    ZTE_RECOVERY_TEST_MODE=1 \
    ZTE_RECOVERY_TEST_SERVICE_CALLS="$calls" \
    ZTE_RECOVERY_TEST_SERVICE_AVAILABLE=1 \
    ZTE_TEST_OBSERVED_PID="$observed_pid" \
    ZTE_TEST_SLEEP_LOG="$sleep_log" \
    ZTE_TEST_SLEEP_LIMIT=4 \
    ZTE_TEST_LOGGER_CALLS="$logger_calls" \
    ZTE_TEST_RESTORE_CALLS="$work/restore-calls" \
    ZTE_TEST_RESTORE_ACTIONS="$work/restore-actions" \
    ZTE_TEST_RESTORE_PATTERN=fail-success-fail \
    PATH="$bin:$PATH" \
    sh "$coordinator" run
assert_eq "10
10
10
10" "$(cat "$sleep_log")"
assert_eq 2 "$(wc -l <"$logger_calls" | tr -d ' ')"
assert_failure test -e "$coordinator_pid"

finish
