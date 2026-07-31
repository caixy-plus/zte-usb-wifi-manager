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
exit 1
EOF
chmod +x "$bin/date"
chmod +x "$bin/sleep"
cat >"$bin/power-restore" <<'EOF'
#!/bin/sh
printf '%s\n' restore >>"$ZTE_TEST_RESTORE_CALLS"
rm -f "$ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE"
rmdir "$ZTE_RECOVERY_COORDINATOR_STATE_DIR/actions/power-transition"
EOF
chmod +x "$bin/power-restore"
: >"$work/restore-calls"

coordinator_call() {
    ZTE_RECOVERY_COORDINATOR_LIB_DIR=$lib \
    ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE=$inhibit \
    ZTE_RECOVERY_COORDINATOR_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_RECOVERY_COORDINATOR_STATE_DIR=$state \
    ZTE_RECOVERY_COORDINATOR_RESTORE_HELPER=$bin/power-restore \
    ZTE_RECOVERY_TEST_SERVICE_CALLS=$calls \
    ZTE_TEST_RESTORE_CALLS=$work/restore-calls \
    ZTE_RECOVERY_TEST_SERVICE_AVAILABLE=1 \
    PATH="$bin:$PATH" \
        sh "$coordinator" once
}

# Inject only the external service boundary. Production validation, inhibit
# parsing, and reconciliation remain the real shipped implementations.
export ZTE_RECOVERY_TEST_MODE=1

assert_success coordinator_call
assert_eq '' "$(cat "$calls")"

. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/recovery-inhibit.sh"
assert_success zte_recovery_inhibit_write \
    "$inhibit" battery_high 1722346000 1722345500 true
assert_success coordinator_call
assert_eq '' "$(cat "$calls")"
assert_success test -e "$inhibit"

assert_success env ZTE_TEST_NOW=1722346000 \
    ZTE_RECOVERY_COORDINATOR_LIB_DIR="$lib" \
    ZTE_RECOVERY_COORDINATOR_INHIBIT_FILE="$inhibit" \
    ZTE_RECOVERY_COORDINATOR_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_RECOVERY_TEST_MODE=1 \
    ZTE_RECOVERY_TEST_SERVICE_CALLS="$calls" \
    ZTE_RECOVERY_TEST_SERVICE_AVAILABLE=1 \
    PATH="$bin:$PATH" \
    sh "$coordinator" once
assert_eq '/etc/init.d/zte-usb-recover:start' "$(cat "$calls")"
assert_failure test -e "$inhibit"

assert_success zte_recovery_inhibit_write \
    "$inhibit" battery_high 1722346000 1722345500 true
mkdir "$state/actions/power-transition"
: >"$calls"
: >"$work/restore-calls"
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
    PATH="$bin:$PATH" \
    sh "$coordinator" once
assert_eq restore "$(cat "$work/restore-calls")"
assert_eq '' "$(cat "$calls")"
assert_failure test -e "$inhibit"
assert_failure test -d "$state/actions/power-transition"

printf '%s\n' '{"invalid":true}' >"$inhibit"
: >"$calls"
assert_success coordinator_call
assert_eq '/etc/init.d/zte-usb-recover:start' "$(cat "$calls")"
assert_failure test -e "$inhibit"

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

finish
