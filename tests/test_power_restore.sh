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
: >"$state/hardware-calls"

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
    printf '%s\n' "$1" >>"$ZTE_TEST_HARDWARE_CALLS"
    [ "${ZTE_TEST_POWER_FAILURE:-0}" = 0 ] || return 1
    [ "$1" = ON ] || return 1
    printf '1\n' >"$2"
    printf '1\n' >"$ZTE_TEST_SUPPLY_FILE"
}
EOF
cat >"$lib/recovery-inhibit.sh" <<'EOF'
zte_recovery_inhibit_write() {
    [ "${ZTE_TEST_MARKER_WRITE_FAILURE:-0}" = 0 ] || return 1
    _zte_test_marker_tmp=$1.tmp.$$
    umask 077
    printf '{"reason":"%s","created":%s,"expires":%s,"restart_service":%s}\n' \
        "$2" "$4" "$3" "$5" >"$_zte_test_marker_tmp" || return 1
    chmod 600 "$_zte_test_marker_tmp" || return 1
    mv "$_zte_test_marker_tmp" "$1"
}
zte_recovery_inhibit_clear() {
    [ "${ZTE_TEST_CLEAR_FAILURE:-0}" = 0 ] || return 1
    rm -f "$1"
}
EOF
cat >"$lib/recovery-adapter.sh" <<'EOF'
zte_recovery_service_available() {
    return 0
}
zte_recovery_service_running() {
    [ "${ZTE_TEST_RUNNING_FAILURE:-0}" = 0 ] || return 1
    [ -e "$ZTE_TEST_RECOVERY_RUNNING" ]
}
zte_recovery_service_control() {
    printf '%s\n' "$2" >>"$ZTE_TEST_SERVICE_CALLS"
    [ "${ZTE_TEST_RECOVERY_FAILURE:-0}" = 0 ] || return 1
    : >"$ZTE_TEST_RECOVERY_RUNNING"
}
zte_recovery_finish_on() {
    [ "${ZTE_TEST_FINISH_FAILURE:-0}" = 0 ] || return 1
    [ ! -L "$1" ] || return 1
    [ "$(cat "$1")" != '{"invalid":true}' ] || return 1
    zte_recovery_service_control "$2" start || return 1
    zte_recovery_service_running "$2" || return 1
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
    ZTE_TEST_HARDWARE_CALLS=$state/hardware-calls \
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
    ZTE_TEST_HARDWARE_CALLS=$state/hardware-calls \
        sh "$tool"
}

restore_coordinator_claim_call() {
    ZTE_POWER_RESTORE_COORDINATOR_CLAIM=1 \
        restore_auto_call
}

mkdir "$state/actions/power-transition"
: >"$state/inhibit-recovery"
assert_success restore_auto_call
assert_eq 1 "$(cat "$state/power")"
assert_success test -e "$state/recovery-running"
assert_eq start "$(cat "$state/service-calls")"
assert_failure test -e "$state/inhibit-recovery"

# A coordinator-owned transition is only an atomic mutex. With power already
# confirmed ON and no marker, it must not cause a periodic hardware write or
# recovery-service start; the helper only releases the claim.
rm -f "$state/recovery-running"
: >"$state/service-calls"
: >"$state/hardware-calls"
mkdir "$state/actions/power-transition"
assert_success restore_coordinator_claim_call
assert_eq '' "$(cat "$state/hardware-calls")"
assert_eq '' "$(cat "$state/service-calls")"
assert_failure test -d "$state/actions/power-transition"

# If the coordinator mutex reveals a real OFF state, restoring power means a
# prior recovery stop cannot be disproved. Apply ON, restart and verify
# recovery, then release the mutex.
printf '0\n' >"$state/power"
printf '0\n' >"$state/supply"
rm -f "$state/recovery-running"
: >"$state/service-calls"
: >"$state/hardware-calls"
mkdir "$state/actions/power-transition"
assert_success restore_coordinator_claim_call
assert_eq ON "$(cat "$state/hardware-calls")"
assert_eq 1 "$(cat "$state/power")"
assert_eq 1 "$(cat "$state/supply")"
assert_eq start "$(cat "$state/service-calls")"
assert_success test -e "$state/recovery-running"
assert_failure test -d "$state/actions/power-transition"

# Every required step remains fail-closed, while the coordinator mutex itself
# is released so a later poll can retry atomically.
printf '0\n' >"$state/power"
printf '0\n' >"$state/supply"
rm -f "$state/recovery-running" "$state/inhibit-recovery"
: >"$state/hardware-calls"
mkdir "$state/actions/power-transition"
ZTE_TEST_MARKER_WRITE_FAILURE=1 assert_failure \
    restore_coordinator_claim_call
assert_eq 0 "$(cat "$state/power")"
assert_eq '' "$(cat "$state/hardware-calls")"
assert_failure test -e "$state/inhibit-recovery"
assert_failure test -d "$state/actions/power-transition"
unset ZTE_TEST_MARKER_WRITE_FAILURE

printf '0\n' >"$state/power"
printf '0\n' >"$state/supply"
rm -f "$state/recovery-running"
rm -f "$state/inhibit-recovery"
mkdir "$state/actions/power-transition"
ZTE_TEST_POWER_FAILURE=1 assert_failure restore_coordinator_claim_call
assert_eq 0 "$(cat "$state/power")"
assert_eq \
    '{"reason":"manual_power_off","created":0,"expires":1,"restart_service":true}' \
    "$(cat "$state/inhibit-recovery")"
assert_eq 600 "$(test_file_mode "$state/inhibit-recovery")"
assert_failure test -d "$state/actions/power-transition"
unset ZTE_TEST_POWER_FAILURE

# First poll restores power but cannot start recovery. The durable marker must
# survive so a second poll retries recovery even though power is already ON.
printf '0\n' >"$state/power"
printf '0\n' >"$state/supply"
rm -f "$state/recovery-running"
rm -f "$state/inhibit-recovery"
mkdir "$state/actions/power-transition"
ZTE_TEST_RECOVERY_FAILURE=1 assert_failure restore_coordinator_claim_call
assert_eq 1 "$(cat "$state/power")"
assert_failure test -e "$state/recovery-running"
assert_success test -e "$state/inhibit-recovery"
assert_failure test -d "$state/actions/power-transition"
unset ZTE_TEST_RECOVERY_FAILURE
: >"$state/service-calls"
: >"$state/hardware-calls"
mkdir "$state/actions/power-transition"
assert_success restore_coordinator_claim_call
assert_eq '' "$(cat "$state/hardware-calls")"
assert_eq start "$(cat "$state/service-calls")"
assert_success test -e "$state/recovery-running"
assert_failure test -e "$state/inhibit-recovery"
assert_failure test -d "$state/actions/power-transition"

# A failed running readback follows the same two-poll retry protocol.
printf '0\n' >"$state/power"
printf '0\n' >"$state/supply"
rm -f "$state/recovery-running"
rm -f "$state/inhibit-recovery"
mkdir "$state/actions/power-transition"
ZTE_TEST_RUNNING_FAILURE=1 assert_failure restore_coordinator_claim_call
assert_success test -e "$state/recovery-running"
assert_success test -e "$state/inhibit-recovery"
assert_failure test -d "$state/actions/power-transition"
unset ZTE_TEST_RUNNING_FAILURE
: >"$state/service-calls"
: >"$state/hardware-calls"
mkdir "$state/actions/power-transition"
assert_success restore_coordinator_claim_call
assert_eq '' "$(cat "$state/hardware-calls")"
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
    ZTE_TEST_HARDWARE_CALLS="$state/hardware-calls" \
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
    ZTE_TEST_HARDWARE_CALLS="$state/hardware-calls" \
    sh "$tool"
assert_eq 1 "$(cat "$state/power")"
assert_success test -e "$state/recovery-running"
assert_failure test -e "$state/inhibit-recovery"

# Dangling symlinks are invalid markers and must be handled by the same
# fail-safe path, including safe removal of the link itself.
rm -f "$state/recovery-running"
: >"$state/service-calls"
ln -s "$work/missing-marker-target" "$state/inhibit-recovery"
assert_success restore_auto_call
assert_success test -e "$state/recovery-running"
assert_eq start "$(cat "$state/service-calls")"
assert_failure test -L "$state/inhibit-recovery"
assert_failure test -d "$state/actions/power-transition"

# A bound controller with a disabled regulator is reconciled through the
# verified ON path instead of being accepted as healthy.
printf '%s\n' 1 >"$state/power"
printf '%s\n' 0 >"$state/supply"
printf '%s\n' 'cudy,tr3000-v1' >"$state/board"
assert_success restore_auto_call
assert_eq 1 "$(cat "$state/supply")"

# A corrupt marker cannot prove the previous recovery-service state. Once the
# helper has confirmed that both controller and supply are ON, fail safe by
# starting recovery and clearing the unusable ownership record.
rm -f "$state/recovery-running"
: >"$state/service-calls"
printf '%s\n' '{"invalid":true}' >"$state/inhibit-recovery"
assert_success restore_auto_call
assert_success test -e "$state/recovery-running"
assert_eq start "$(cat "$state/service-calls")"
assert_failure test -e "$state/inhibit-recovery"

# The corrupt-marker fallback must not report success until start succeeds,
# the service is observed running, and the marker is actually cleared.
rm -f "$state/recovery-running"
: >"$state/service-calls"
printf '%s\n' '{"invalid":true}' >"$state/inhibit-recovery"
ZTE_TEST_RECOVERY_FAILURE=1 assert_failure restore_auto_call
assert_failure test -e "$state/recovery-running"
assert_success test -e "$state/inhibit-recovery"
unset ZTE_TEST_RECOVERY_FAILURE

rm -f "$state/recovery-running"
: >"$state/service-calls"
printf '%s\n' '{"invalid":true}' >"$state/inhibit-recovery"
ZTE_TEST_RUNNING_FAILURE=1 assert_failure restore_auto_call
assert_success test -e "$state/recovery-running"
assert_success test -e "$state/inhibit-recovery"
unset ZTE_TEST_RUNNING_FAILURE

rm -f "$state/recovery-running"
: >"$state/service-calls"
printf '%s\n' '{"invalid":true}' >"$state/inhibit-recovery"
ZTE_TEST_CLEAR_FAILURE=1 assert_failure restore_auto_call
assert_success test -e "$state/recovery-running"
assert_success test -e "$state/inhibit-recovery"
unset ZTE_TEST_CLEAR_FAILURE

# A read-only install on an unsupported or temporarily unreadable board has
# no owned transition to restore; the helper must not block service shutdown
# or package removal in that case.
rm -f "$state/recovery-running" "$state/inhibit-recovery"
printf '%s\n' 'unsupported,board' >"$state/board"
assert_success restore_auto_call

finish
