#!/bin/sh
set -eu

TEST_NAME=test_power_restore
. ./tests/testlib.sh

tool=./package/zte-usb-wifi-manager/files/usr/libexec/zte-usb-power-restore
if [ ! -f "$tool" ]; then
    fail 'power restore helper must exist'
    finish
fi

work=$(mktemp -d /tmp/zte-test-power-restore.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
lib=$work/lib
state=$work/state
mkdir -p "$lib" "$state/actions"
printf '%s\n' 'cudy,tr3000-v1' >"$state/board"
printf '0\n' >"$state/power"
printf '0\n' >"$state/supply"
: >"$state/service-calls"

cat >"$lib/validation.sh" <<'EOF'
:
EOF
cat >"$lib/json.sh" <<'EOF'
:
EOF
cat >"$lib/actions.sh" <<'EOF'
zte_power_transition_active() {
    [ -d "$1/actions/power-transition" ]
}
zte_power_transition_release() {
    rmdir "$1/actions/power-transition"
}
EOF
cat >"$lib/power-adapter.sh" <<'EOF'
zte_power_board_supported() {
    [ "$1" = 'cudy,tr3000-v1' ]
}
zte_power_control_path_valid() {
    [ "$1" = "$ZTE_POWER_RESTORE_CONTROL_PATH" ]
}
zte_power_board_control_supported() {
    [ "$1" = 'cudy,tr3000-v1' ] &&
        [ "$2" = "$ZTE_POWER_RESTORE_CONTROL_PATH" ]
}
zte_power_default_control_path() {
    [ "$1" = 'cudy,tr3000-v1' ] || return 1
    printf '%s\n' "$ZTE_TEST_DEFAULT_POWER_PATH"
}
zte_power_sysfs_read() {
    return 1
}
zte_power_hardware_read() {
    cat "$1"
}
zte_power_supply_read() {
    cat "$ZTE_TEST_SUPPLY_FILE"
}
zte_power_hardware_apply() {
    [ "${ZTE_TEST_POWER_FAILURE:-0}" = 0 ] || return 1
    [ "$1" = ON ] || return 1
    printf '1\n' >"$2"
    printf '1\n' >"$ZTE_TEST_SUPPLY_FILE"
}
EOF
cat >"$lib/recovery-inhibit.sh" <<'EOF'
zte_recovery_inhibit_clear() {
    rm -f "$1"
}
EOF
cat >"$lib/recovery-adapter.sh" <<'EOF'
zte_recovery_service_available() {
    return 0
}
zte_recovery_service_running() {
    [ -e "$ZTE_TEST_RECOVERY_RUNNING" ]
}
zte_recovery_service_control() {
    printf '%s\n' "$2" >>"$ZTE_TEST_SERVICE_CALLS"
    [ "${ZTE_TEST_RECOVERY_FAILURE:-0}" = 0 ] || return 1
    : >"$ZTE_TEST_RECOVERY_RUNNING"
}
zte_recovery_finish_on() {
    [ "${ZTE_TEST_FINISH_FAILURE:-0}" = 0 ] || return 1
    zte_recovery_service_control "$2" start || return 1
    zte_recovery_inhibit_clear "$1"
}
EOF

restore_call() {
    ZTE_POWER_RESTORE_LIB_DIR=$lib \
    ZTE_POWER_RESTORE_BOARD_FILE=$state/board \
    ZTE_POWER_RESTORE_CONTROL_PATH=$state/power \
    ZTE_POWER_RESTORE_STATE_DIR=$state \
    ZTE_POWER_RESTORE_INHIBIT_FILE=$state/inhibit-recovery \
    ZTE_POWER_RESTORE_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_TEST_SUPPLY_FILE=$state/supply \
    ZTE_TEST_RECOVERY_RUNNING=$state/recovery-running \
    ZTE_TEST_SERVICE_CALLS=$state/service-calls \
        sh "$tool"
}

restore_auto_call() {
    ZTE_POWER_RESTORE_LIB_DIR=$lib \
    ZTE_POWER_RESTORE_BOARD_FILE=$state/board \
    ZTE_POWER_RESTORE_STATE_DIR=$state \
    ZTE_POWER_RESTORE_INHIBIT_FILE=$state/inhibit-recovery \
    ZTE_POWER_RESTORE_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_TEST_DEFAULT_POWER_PATH=$state/power \
    ZTE_TEST_SUPPLY_FILE=$state/supply \
    ZTE_TEST_RECOVERY_RUNNING=$state/recovery-running \
    ZTE_TEST_SERVICE_CALLS=$state/service-calls \
        sh "$tool"
}

mkdir "$state/actions/power-transition"
: >"$state/inhibit-recovery"
assert_success restore_auto_call
assert_eq 1 "$(cat "$state/power")"
assert_success test -e "$state/recovery-running"
assert_eq start "$(cat "$state/service-calls")"
assert_failure test -e "$state/inhibit-recovery"
assert_failure test -d "$state/actions/power-transition"

# A failed hardware restore must retain ownership state so package removal can
# abort and a later retry can still recover safely.
printf '0\n' >"$state/power"
rm -f "$state/recovery-running"
: >"$state/service-calls"
mkdir "$state/actions/power-transition"
: >"$state/inhibit-recovery"
assert_failure env ZTE_TEST_POWER_FAILURE=1 \
    ZTE_POWER_RESTORE_LIB_DIR="$lib" \
    ZTE_POWER_RESTORE_BOARD_FILE="$state/board" \
    ZTE_POWER_RESTORE_CONTROL_PATH="$state/power" \
    ZTE_POWER_RESTORE_STATE_DIR="$state" \
    ZTE_POWER_RESTORE_INHIBIT_FILE="$state/inhibit-recovery" \
    ZTE_POWER_RESTORE_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_TEST_SUPPLY_FILE="$state/supply" \
    ZTE_TEST_RECOVERY_RUNNING="$state/recovery-running" \
    ZTE_TEST_SERVICE_CALLS="$state/service-calls" \
    sh "$tool"
assert_eq 0 "$(cat "$state/power")"
assert_success test -e "$state/inhibit-recovery"
assert_success test -d "$state/actions/power-transition"

# A malformed ownership record is handled conservatively: with a claimed
# transition, restore the recovery service before releasing the lock.
assert_success env ZTE_TEST_FINISH_FAILURE=1 \
    ZTE_POWER_RESTORE_LIB_DIR="$lib" \
    ZTE_POWER_RESTORE_BOARD_FILE="$state/board" \
    ZTE_POWER_RESTORE_CONTROL_PATH="$state/power" \
    ZTE_POWER_RESTORE_STATE_DIR="$state" \
    ZTE_POWER_RESTORE_INHIBIT_FILE="$state/inhibit-recovery" \
    ZTE_POWER_RESTORE_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_TEST_SUPPLY_FILE="$state/supply" \
    ZTE_TEST_RECOVERY_RUNNING="$state/recovery-running" \
    ZTE_TEST_SERVICE_CALLS="$state/service-calls" \
    sh "$tool"
assert_eq 1 "$(cat "$state/power")"
assert_success test -e "$state/recovery-running"
assert_failure test -e "$state/inhibit-recovery"
assert_failure test -d "$state/actions/power-transition"

# A bound controller with a disabled regulator is reconciled through the
# verified ON path instead of being accepted as healthy.
printf '%s\n' 1 >"$state/power"
printf '%s\n' 0 >"$state/supply"
printf '%s\n' 'cudy,tr3000-v1' >"$state/board"
assert_success restore_auto_call
assert_eq 1 "$(cat "$state/supply")"

# A read-only install on an unsupported or temporarily unreadable board has
# no owned transition to restore; the helper must not block service shutdown
# or package removal in that case.
printf '%s\n' 'unsupported,board' >"$state/board"
assert_success restore_auto_call

finish
