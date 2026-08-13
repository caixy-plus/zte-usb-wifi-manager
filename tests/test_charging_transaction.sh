#!/bin/sh
set -eu

TEST_NAME=test_charging_transaction
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
transaction_lib=$lib/charging-transaction.sh
if [ ! -f "$transaction_lib" ]; then
    fail 'charging transaction library must exist'
    finish
fi
. "$lib/validation.sh"
# shellcheck disable=SC1090
. "$transaction_lib"

assert_file_contains "$transaction_lib" \
    "trap 'zte_charging_tx_end_locked' EXIT$"
assert_file_contains "$transaction_lib" \
    "trap 'exit 1' HUP INT TERM$"
assert_file_contains "$transaction_lib" 'CHARGING_TX_MARKER\.txid='
assert_file_contains "$transaction_lib" 'CHARGING_TX_MARKER\.new_enabled='
daemon_finalize_body=$(sed -n \
    '/^zte_charging_transaction_daemon_finalize() ($/,/^)/p' \
    "$transaction_lib")
case $daemon_finalize_body in
    *zte_charging_tx_begin_locked*)
        fail 'daemon ACK path must not acquire the rpcd transaction lock'
        ;;
    *) pass ;;
esac

work=$(mktemp -d /tmp/zte-test-charging-transaction.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
runtime=$work/runtime
savedirs=$work/savedirs
committed=$work/committed
mutation_log=$work/mutations
mutation_counter=$work/mutation-counter
mutation_fail_points=$work/mutation-fail-points
show_fail=$work/show-fail
service_log=$work/service-log
service_fail_points=$work/service-fail-points
flock_dir=$work/flock-held
flock_acquired=$work/flock-acquired
flock_release=$work/flock-release
service=./tests/helpers/mock_service_reload.sh

ZTE_CHARGING_UCI_BIN=./tests/helpers/mock_uci_stateful.sh
ZTE_CHARGING_FLOCK_BIN=./tests/helpers/mock_flock.sh
ZTE_CHARGING_TX_SAVEDIR_ROOT=$savedirs
ZTE_TEST_UCI_COMMITTED=$committed
ZTE_TEST_UCI_LOG=$mutation_log
ZTE_TEST_UCI_COUNTER=$mutation_counter
ZTE_TEST_UCI_FAIL_POINTS=$mutation_fail_points
ZTE_TEST_UCI_SHOW_FAIL_FILE=$show_fail
ZTE_TEST_SERVICE_LOG=$service_log
ZTE_TEST_SERVICE_FAIL_POINTS=$service_fail_points
ZTE_TEST_FLOCK_DIR=$flock_dir
ZTE_TEST_FLOCK_ACQUIRED=$flock_acquired
ZTE_TEST_FLOCK_RELEASE=$flock_release
ZTE_TEST_TX_LIB=$transaction_lib
ZTE_TEST_VALIDATION_LIB=$lib/validation.sh
ZTE_TEST_TX_STATE=$runtime
export ZTE_CHARGING_UCI_BIN ZTE_CHARGING_FLOCK_BIN
export ZTE_CHARGING_TX_SAVEDIR_ROOT ZTE_TEST_UCI_COMMITTED
export ZTE_TEST_UCI_LOG ZTE_TEST_UCI_COUNTER ZTE_TEST_UCI_FAIL_POINTS
export ZTE_TEST_UCI_SHOW_FAIL_FILE ZTE_TEST_SERVICE_LOG
export ZTE_TEST_SERVICE_FAIL_POINTS ZTE_TEST_FLOCK_DIR
export ZTE_TEST_FLOCK_ACQUIRED ZTE_TEST_FLOCK_RELEASE
export ZTE_TEST_TX_LIB ZTE_TEST_VALIDATION_LIB ZTE_TEST_TX_STATE
ZTE_CHARGING_TX_ACK_ATTEMPTS=1
ZTE_CHARGING_TX_TEST_NONCE=0123456789abcdef0123456789abcdef
export ZTE_CHARGING_TX_ACK_ATTEMPTS ZTE_CHARGING_TX_TEST_NONCE

# OpenWrt 25.12 ships hexdump but not od. Nonce generation must use the
# target-available utility instead of silently producing an empty value.
nonce_bin=$work/nonce-bin
mkdir -p "$nonce_bin"
cat >"$nonce_bin/hexdump" <<'EOF'
#!/bin/sh
[ "$#" -eq 5 ] && [ "$1" = -n ] && [ "$2" = 16 ] &&
    [ "$3" = -e ] && [ "$4" = '16/1 "%02x"' ] &&
    [ "$5" = /dev/urandom ] || exit 1
[ "${ZTE_TEST_HEXDUMP_FAIL:-0}" = 0 ] || exit 1
printf '%s' "${ZTE_TEST_HEXDUMP_OUTPUT:-0123456789abcdef0123456789abcdef}"
EOF
chmod 700 "$nonce_bin/hexdump"
unset ZTE_CHARGING_TX_TEST_NONCE
assert_eq 0123456789abcdef0123456789abcdef \
    "$(PATH="$nonce_bin" zte_charging_tx_nonce)"
ZTE_CHARGING_TX_HEXDUMP_BIN=$nonce_bin/hexdump
ZTE_TEST_HEXDUMP_FAIL=1
export ZTE_CHARGING_TX_HEXDUMP_BIN ZTE_TEST_HEXDUMP_FAIL
assert_failure zte_charging_tx_nonce
unset ZTE_TEST_HEXDUMP_FAIL
ZTE_TEST_HEXDUMP_OUTPUT=0123456789abcdef0123456789abcde
export ZTE_TEST_HEXDUMP_OUTPUT
assert_failure zte_charging_tx_nonce
ZTE_TEST_HEXDUMP_OUTPUT=0123456789ABCDEF0123456789ABCDEF
export ZTE_TEST_HEXDUMP_OUTPUT
assert_failure zte_charging_tx_nonce
unset ZTE_CHARGING_TX_HEXDUMP_BIN ZTE_TEST_HEXDUMP_OUTPUT
ZTE_CHARGING_TX_TEST_NONCE=0123456789abcdef0123456789abcdef
export ZTE_CHARGING_TX_TEST_NONCE

reset_state() {
    rm -rf "$runtime" "$savedirs" "$flock_dir"
    mkdir -p "$runtime" "$savedirs"
    chmod 700 "$runtime" "$savedirs"
    printf '%s\n' \
        'zte-usb-wifi-manager.charging=smart_charge' \
        'zte-usb-wifi-manager.charging.enabled=0' \
        'zte-usb-wifi-manager.charging.low_percent=30' \
        'zte-usb-wifi-manager.charging.high_percent=85' \
        >"$committed"
    : >"$mutation_log"
    printf '%s\n' 0 >"$mutation_counter"
    : >"$mutation_fail_points"
    : >"$service_log"
    : >"$service_fail_points"
    rm -f "$show_fail" "$show_fail.count" "$flock_acquired" "$flock_release"
    unset ZTE_TEST_FLOCK_BARRIER 2>/dev/null || :
}

committed_value() {
    _test_key=$1
    awk -v prefix="$_test_key=" '
        index($0, prefix) == 1 {
            print substr($0, length(prefix) + 1)
            found = 1
        }
        END { if (!found) exit 1 }
    ' "$committed"
}

assert_marker_absent() {
    assert_failure committed_value zte-usb-wifi-manager.charging_tx
}

add_marker() {
    _test_marker_state=$1
    _test_enabled_present=$2
    _test_low_present=$3
    _test_high_present=$4
    printf '%s\n' \
        'zte-usb-wifi-manager.charging_tx=transaction' \
        'zte-usb-wifi-manager.charging_tx.txid=tx-1722345678-99-0123456789abcdef0123456789abcdef' \
        "zte-usb-wifi-manager.charging_tx.state=$_test_marker_state" \
        'zte-usb-wifi-manager.charging_tx.new_enabled=1' \
        'zte-usb-wifi-manager.charging_tx.new_low=30' \
        'zte-usb-wifi-manager.charging_tx.new_high=80' \
        "zte-usb-wifi-manager.charging_tx.old_enabled_present=$_test_enabled_present" \
        "zte-usb-wifi-manager.charging_tx.old_low_present=$_test_low_present" \
        "zte-usb-wifi-manager.charging_tx.old_high_present=$_test_high_present" \
        >>"$committed"
    [ "$_test_enabled_present" = 0 ] || printf '%s\n' \
        'zte-usb-wifi-manager.charging_tx.old_enabled_value=0' \
        >>"$committed"
    [ "$_test_low_present" = 0 ] || printf '%s\n' \
        'zte-usb-wifi-manager.charging_tx.old_low_value=30' \
        >>"$committed"
    [ "$_test_high_present" = 0 ] || printf '%s\n' \
        'zte-usb-wifi-manager.charging_tx.old_high_value=85' \
        >>"$committed"
}

reset_state
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq ok "$result"
assert_eq 1 "$(committed_value zte-usb-wifi-manager.charging.enabled)"
assert_eq 30 "$(committed_value zte-usb-wifi-manager.charging.low_percent)"
assert_eq 80 "$(committed_value zte-usb-wifi-manager.charging.high_percent)"
assert_marker_absent
assert_eq 1 "$(wc -l <"$service_log" | tr -d ' ')"
assert_eq 0 "$(find "$savedirs" -mindepth 1 | wc -l | tr -d ' ')"

# Failed activation restores the exact committed snapshot and clears marker.
reset_state
printf '%s\n' 1 >"$service_fail_points"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq service_reload_failed "$result"
assert_eq 0 "$(committed_value zte-usb-wifi-manager.charging.enabled)"
assert_eq 30 "$(committed_value zte-usb-wifi-manager.charging.low_percent)"
assert_eq 85 "$(committed_value zte-usb-wifi-manager.charging.high_percent)"
assert_marker_absent
assert_eq 2 "$(wc -l <"$service_log" | tr -d ' ')"

# Snapshot readability is distinct from explicit option absence.
reset_state
: >"$show_fail"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq settings_snapshot_failed "$result"
assert_eq '' "$(cat "$mutation_log")"
assert_eq '' "$(cat "$service_log")"

reset_state
grep -v 'charging.low_percent=' "$committed" >"$committed.tmp"
mv "$committed.tmp" "$committed"
printf '%s\n' 1 >"$service_fail_points"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq service_reload_failed "$result"
assert_failure committed_value zte-usb-wifi-manager.charging.low_percent
assert_marker_absent

# A second rpcd process cannot cross the nonblocking transaction lock and
# performs zero UCI mutations while the first holder is paused.
reset_state
ZTE_TEST_FLOCK_BARRIER=1
export ZTE_TEST_FLOCK_BARRIER
(
    zte_charging_transaction_apply "$runtime" "$service" 1 30 80 \
        >"$work/first-result"
) &
first_pid=$!
wait_count=0
while [ ! -f "$flock_acquired" ] && [ "$wait_count" -lt 100 ]; do
    sleep 0.05
    wait_count=$((wait_count + 1))
done
assert_success test -f "$flock_acquired"
second_result=$(zte_charging_transaction_apply \
    "$runtime" "$service" 1 35 75)
assert_eq transaction_busy "$second_result"
assert_eq '' "$(cat "$mutation_log")"
: >"$flock_release"
wait "$first_pid"
assert_eq ok "$(cat "$work/first-result")"
unset ZTE_TEST_FLOCK_BARRIER

# reload_pending covers a crash after the initial commit and a crash after a
# successful new-config reload but before marker clear. Recovery finalizes it
# before accepting the next request.
reset_state
sed -e 's/charging.enabled=0/charging.enabled=1/' \
    -e 's/charging.low_percent=30/charging.low_percent=30/' \
    -e 's/charging.high_percent=85/charging.high_percent=80/' \
    "$committed" >"$committed.tmp"
mv "$committed.tmp" "$committed"
add_marker reload_pending 1 1 1
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 35 75)
assert_eq ok "$result"
assert_eq 35 "$(committed_value zte-usb-wifi-manager.charging.low_percent)"
assert_eq 75 "$(committed_value zte-usb-wifi-manager.charging.high_percent)"
assert_marker_absent
assert_eq 2 "$(wc -l <"$service_log" | tr -d ' ')"

# restore_pending covers crashes after restoration commit or after the old
# reload but before marker clear.
reset_state
add_marker restore_pending 1 1 1
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 35 75)
assert_eq ok "$result"
assert_eq 35 "$(committed_value zte-usb-wifi-manager.charging.low_percent)"
assert_marker_absent
assert_eq 2 "$(wc -l <"$service_log" | tr -d ' ')"

# Corrupt durable state is never guessed away and the new request performs no
# mutation.
reset_state
printf '%s\n' \
    'zte-usb-wifi-manager.charging_tx=transaction' \
    'zte-usb-wifi-manager.charging_tx.state=reload_pending' \
    'zte-usb-wifi-manager.charging_tx.old_enabled_present=1' \
    >>"$committed"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq transaction_recovery_failed "$result"
assert_eq '' "$(cat "$mutation_log")"

# A marker-clear commit failure remains durable and cannot report success.
reset_state
printf '%s\n' 18 >"$mutation_fail_points"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq settings_rollback_failed "$result"
assert_eq reload_pending "$(committed_value \
    zte-usb-wifi-manager.charging_tx.state)"

# A failed initial write whose private revert also fails is a rollback failure.
reset_state
printf '%s\n' 2,3 >"$mutation_fail_points"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq settings_rollback_failed "$result"
assert_marker_absent

# Daemon startup never reloads itself. Matching loaded/committed values prove
# startup applied the config, allowing marker finalization under the same lock.
reset_state
sed -e 's/charging.enabled=0/charging.enabled=1/' \
    -e 's/charging.low_percent=30/charging.low_percent=30/' \
    -e 's/charging.high_percent=85/charging.high_percent=80/' \
    "$committed" >"$committed.tmp"
mv "$committed.tmp" "$committed"
add_marker reload_pending 1 1 1
result=$(zte_charging_transaction_daemon_finalize \
    "$runtime" 1 30 80)
assert_eq ok "$result"
assert_eq reload_pending "$(committed_value \
    zte-usb-wifi-manager.charging_tx.state)"
assert_success test -s "$runtime/charging-transaction.ack"
assert_eq '' "$(cat "$service_log")"

reset_state
add_marker restore_pending 1 1 1
result=$(zte_charging_transaction_daemon_finalize \
    "$runtime" 1 30 80)
assert_eq transaction_recovery_failed "$result"
assert_eq restore_pending "$(committed_value \
    zte-usb-wifi-manager.charging_tx.state)"

# A reload may return before procd's replacement daemon publishes its ACK.
reset_state
ZTE_CHARGING_TX_ACK_ATTEMPTS=20
ZTE_CHARGING_TX_ACK_SLEEP=0.02
ZTE_TEST_SERVICE_ACK_DELAY=0.05
export ZTE_CHARGING_TX_ACK_ATTEMPTS ZTE_CHARGING_TX_ACK_SLEEP
export ZTE_TEST_SERVICE_ACK_DELAY
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
unset ZTE_TEST_SERVICE_ACK_DELAY ZTE_CHARGING_TX_ACK_SLEEP
ZTE_CHARGING_TX_ACK_ATTEMPTS=1
export ZTE_CHARGING_TX_ACK_ATTEMPTS
assert_eq ok "$result"
assert_marker_absent

# The target BusyBox sleep accepts integer seconds only. A delayed daemon ACK
# must still be observed when fractional sleeps are unavailable.
reset_state
strict_sleep_bin=$work/strict-sleep-bin
mkdir -p "$strict_sleep_bin"
cat >"$strict_sleep_bin/sleep" <<'EOF'
#!/bin/sh
case ${1-} in
    ''|*[!0-9]*|0) exit 1 ;;
    *) exec /bin/sleep "$@" ;;
esac
EOF
chmod 700 "$strict_sleep_bin/sleep"
ZTE_CHARGING_TX_ACK_ATTEMPTS=2
ZTE_TEST_SERVICE_ACK_DELAY=0.05
ZTE_TEST_SERVICE_SLEEP_BIN=/bin/sleep
export ZTE_CHARGING_TX_ACK_ATTEMPTS ZTE_TEST_SERVICE_ACK_DELAY
export ZTE_TEST_SERVICE_SLEEP_BIN
result=$(PATH="$strict_sleep_bin:$PATH" \
    zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
unset ZTE_TEST_SERVICE_ACK_DELAY ZTE_TEST_SERVICE_SLEEP_BIN
ZTE_CHARGING_TX_ACK_ATTEMPTS=1
export ZTE_CHARGING_TX_ACK_ATTEMPTS
assert_eq ok "$result"
assert_marker_absent

# TERM exits through the EXIT cleanup trap. No code after the barrier runs and
# the next process can acquire the lock.
reset_state
term_barrier=$work/term-barrier
ZTE_CHARGING_TX_AFTER_LOCK_BARRIER=$term_barrier
export ZTE_CHARGING_TX_AFTER_LOCK_BARRIER
zte_charging_transaction_apply "$runtime" "$service" 1 30 80 \
    >"$work/term-result" &
term_pid=$!
wait_count=0
while [ ! -f "$term_barrier.ready" ] && [ "$wait_count" -lt 100 ]; do
    sleep 0.05
    wait_count=$((wait_count + 1))
done
assert_success test -f "$term_barrier.ready"
term_holder_pid=$(cat "$term_barrier.pid")
kill -TERM "$term_holder_pid"
assert_failure wait "$term_pid"
assert_eq '' "$(cat "$mutation_log")"
assert_eq '' "$(cat "$service_log")"
unset ZTE_CHARGING_TX_AFTER_LOCK_BARRIER
assert_eq ok "$(zte_charging_transaction_apply \
    "$runtime" "$service" 1 30 80)"

# SIGKILL can leave only the private savedir behind. Kernel flock release is
# represented by releasing the mock lock; the next holder safely removes the
# ordinary orphan before creating its own savedir.
reset_state
kill_barrier=$work/kill-barrier
ZTE_CHARGING_TX_AFTER_LOCK_BARRIER=$kill_barrier
export ZTE_CHARGING_TX_AFTER_LOCK_BARRIER
zte_charging_transaction_apply "$runtime" "$service" 1 30 80 \
    >"$work/kill-result" &
kill_pid=$!
wait_count=0
while [ ! -f "$kill_barrier.ready" ] && [ "$wait_count" -lt 100 ]; do
    sleep 0.05
    wait_count=$((wait_count + 1))
done
assert_success test -f "$kill_barrier.ready"
kill_holder_pid=$(cat "$kill_barrier.pid")
kill -KILL "$kill_holder_pid"
if wait "$kill_pid" 2>/dev/null; then
    fail 'SIGKILL transaction unexpectedly succeeded'
else
    pass
fi
assert_success find "$savedirs" -mindepth 1 -maxdepth 1 -type d \
    -name 'charging-uci.*' | grep -q .
rmdir "$flock_dir"
unset ZTE_CHARGING_TX_AFTER_LOCK_BARRIER
assert_eq ok "$(zte_charging_transaction_apply \
    "$runtime" "$service" 1 30 80)"
assert_eq 0 "$(find "$savedirs" -mindepth 1 | wc -l | tr -d ' ')"

# An anomalous orphan is never removed or crossed.
reset_state
ln -s "$work" "$savedirs/charging-uci.bad"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq transaction_busy "$result"
assert_success test -L "$savedirs/charging-uci.bad"
assert_eq '' "$(cat "$mutation_log")"

# Structurally complete but semantically illegal old values are corrupt and
# must never be restored.
reset_state
add_marker restore_pending 1 1 1
sed 's/old_low_value=30/old_low_value=5/' "$committed" >"$committed.tmp"
mv "$committed.tmp" "$committed"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq transaction_recovery_failed "$result"
assert_eq '' "$(cat "$mutation_log")"

# Duplicate marker sections and ambiguous/malformed values are corrupt. Only
# an unambiguous field status of "absent" may represent a missing old value.
reset_state
add_marker restore_pending 1 1 1
printf '%s\n' 'zte-usb-wifi-manager.charging_tx=transaction' >>"$committed"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq transaction_recovery_failed "$result"
assert_eq '' "$(cat "$mutation_log")"

reset_state
grep -v 'charging.enabled=' "$committed" >"$committed.tmp"
mv "$committed.tmp" "$committed"
add_marker restore_pending 0 1 1
printf '%s\n' \
    'zte-usb-wifi-manager.charging_tx.old_enabled_value=0' \
    'zte-usb-wifi-manager.charging_tx.old_enabled_value=0' \
    >>"$committed"
result=$(zte_charging_transaction_daemon_finalize "$runtime" 0 30 85)
assert_eq transaction_recovery_failed "$result"
assert_failure test -e "$runtime/charging-transaction.ack"

reset_state
grep -v 'charging.enabled=' "$committed" >"$committed.tmp"
mv "$committed.tmp" "$committed"
add_marker restore_pending 0 1 1
printf '%s\n' \
    "zte-usb-wifi-manager.charging_tx.old_enabled_value='broken" \
    >>"$committed"
result=$(zte_charging_transaction_daemon_finalize "$runtime" 0 30 85)
assert_eq transaction_recovery_failed "$result"
assert_failure test -e "$runtime/charging-transaction.ack"

# No marker means normal daemon startup and no ACK write.
reset_state
result=$(zte_charging_transaction_daemon_finalize "$runtime" 0 30 85)
assert_eq ok "$result"
assert_failure test -e "$runtime/charging-transaction.ack"
assert_success test -d "$runtime/charging-ack-read"
assert_eq 700 "$(test_file_mode "$runtime/charging-ack-read")"
assert_eq 0 "$(find "$runtime" -mindepth 1 -maxdepth 1 \
    -name 'charging-ack-read.*' | wc -l | tr -d ' ')"

reset_state
ln -s "$work" "$runtime/charging-ack-read"
result=$(zte_charging_transaction_daemon_finalize "$runtime" 0 30 85)
assert_eq transaction_recovery_failed "$result"
assert_success test -L "$runtime/charging-ack-read"

# The marker and current committed charging values are one proof. A daemon
# cannot ACK a marker whose committed values drifted after it loaded.
reset_state
add_marker reload_pending 1 1 1
result=$(zte_charging_transaction_daemon_finalize "$runtime" 1 30 80)
assert_eq transaction_recovery_failed "$result"
assert_failure test -e "$runtime/charging-transaction.ack"

# Drift after daemon ACK but before rpcd clear is detected and leaves the
# durable marker untouched.
reset_state
ZTE_TEST_SERVICE_POST_ACK_DRIFT=1
export ZTE_TEST_SERVICE_POST_ACK_DRIFT
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
unset ZTE_TEST_SERVICE_POST_ACK_DRIFT
assert_eq transaction_recovery_failed "$result"
assert_eq reload_pending "$(committed_value \
    zte-usb-wifi-manager.charging_tx.state)"

# restore_pending compares raw presence as well as effective defaults. Missing
# old options can still be ACKed when the loaded defaults match.
reset_state
grep -v 'charging.low_percent=' "$committed" >"$committed.tmp"
mv "$committed.tmp" "$committed"
add_marker restore_pending 1 0 1
result=$(zte_charging_transaction_daemon_finalize "$runtime" 0 30 85)
assert_eq ok "$result"
assert_success test -s "$runtime/charging-transaction.ack"

# A safe orphan ACK is removed under lock before any new transaction. An
# anomalous orphan ACK is fail-closed.
reset_state
printf '%s\n' \
    'tx-1722345678-99-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|reload_pending|1|30|80' \
    >"$runtime/charging-transaction.ack"
chmod 600 "$runtime/charging-transaction.ack"
: >"$show_fail"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq settings_snapshot_failed "$result"
assert_failure test -e "$runtime/charging-transaction.ack"

reset_state
printf '%s\n' bad >"$runtime/charging-transaction.ack"
chmod 644 "$runtime/charging-transaction.ack"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq transaction_recovery_failed "$result"
assert_eq '' "$(cat "$mutation_log")"

# ACK parser accepts exactly one newline-terminated five-field record.
reset_state
ack_file=$runtime/charging-transaction.ack
valid_txid=tx-1722345678-99-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
printf '%s\n' "$valid_txid|reload_pending|1|30|80" >"$ack_file"
chmod 600 "$ack_file"
assert_success zte_charging_tx_ack_matches "$ack_file" \
    "$valid_txid" reload_pending 1 30 80
printf '%s\n%s\n' "$valid_txid|reload_pending|1|30|80" extra >"$ack_file"
assert_failure zte_charging_tx_ack_matches "$ack_file" \
    "$valid_txid" reload_pending 1 30 80
printf '%s' "$valid_txid|reload_pending|1|30|80" >"$ack_file"
assert_failure zte_charging_tx_ack_matches "$ack_file" \
    "$valid_txid" reload_pending 1 30 80

# Duplicate UCI fields are ambiguous, never equivalent to an absent option.
reset_state
printf '%s\n' 'zte-usb-wifi-manager.charging.low_percent=31' >>"$committed"
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
assert_eq settings_snapshot_failed "$result"
assert_eq '' "$(cat "$mutation_log")"

# A post-flock mktemp failure explicitly unlocks; a later request can enter.
reset_state
ZTE_CHARGING_TX_MKTEMP_BIN=false
export ZTE_CHARGING_TX_MKTEMP_BIN
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
unset ZTE_CHARGING_TX_MKTEMP_BIN
assert_eq transaction_busy "$result"
assert_failure test -d "$flock_dir"
assert_eq ok "$(zte_charging_transaction_apply \
    "$runtime" "$service" 1 30 80)"

# Successful reload without any ACK cannot clear the marker or report success.
reset_state
ZTE_TEST_SERVICE_AUTO_ACK=0
export ZTE_TEST_SERVICE_AUTO_ACK
result=$(zte_charging_transaction_apply "$runtime" "$service" 1 30 80)
unset ZTE_TEST_SERVICE_AUTO_ACK
assert_eq service_restore_failed "$result"
assert_eq restore_pending "$(committed_value \
    zte-usb-wifi-manager.charging_tx.state)"

# The production daemon wrapper continues startup but disables automatic
# charging writes and emits an explicit event when finalization is ambiguous.
daemon=./package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd
eval "$(sed -n '/^recover_charging_transaction() {$/,/^}$/p' "$daemon")"
daemon_event_log=$work/daemon-event-log
daemon_logger_log=$work/daemon-logger-log
: >"$daemon_event_log"
: >"$daemon_logger_log"
logger() { printf '%s\n' "$*" >>"$daemon_logger_log"; }
record_event() { printf '%s\n' "$*" >>"$daemon_event_log"; }
zte_charging_transaction_daemon_finalize() {
    printf '%s\n' "$daemon_finalize_result"
}
# These globals are read by the eval-defined production daemon function.
# shellcheck disable=SC2034
STATE_DIR=$runtime
battery_enabled=1
# shellcheck disable=SC2034
battery_low=30
# shellcheck disable=SC2034
battery_high=80
daemon_finalize_result=ok
assert_success recover_charging_transaction
assert_eq 1 "$battery_enabled"
assert_eq '' "$(cat "$daemon_event_log")"

daemon_finalize_result=transaction_recovery_failed
assert_success recover_charging_transaction
assert_eq 0 "$battery_enabled"
assert_file_contains "$daemon_event_log" \
    'error smart_charge charging_transaction_recovery_failed'
assert_file_contains "$daemon_logger_log" \
    'charging_transaction_recovery_failed'

finish
