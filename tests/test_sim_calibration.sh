#!/bin/sh
# shellcheck disable=SC2317,SC2329
set -eu

TEST_NAME=test_sim_calibration
. ./tests/testlib.sh

tool=./package/zte-usb-wifi-manager/files/usr/libexec/zte-u25s-sim-calibrate
if [ ! -f "$tool" ]; then
    fail 'SIM calibration tool must exist'
    finish
fi

work=$(mktemp -d /tmp/zte-test-sim-calibration.XXXXXX)
cleanup() {
    chmod -R u+rwx "$work" 2>/dev/null || :
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
lib=$work/lib
state=$work/state
mkdir -p "$lib" "$state"
credential_file=$state/credentials
cookie_file=$state/cookies
fetch_log=$state/fetches
login_log=$state/logins
cleanup_fail_marker=$state/cleanup-fail-marker

# Defined before all call sites for compatibility with older ShellCheck
# releases. Outside the cleanup-failure cases these wrappers pass through.
rm() {
    if [ "${ZTE_TEST_CLEANUP_FAIL_STAGE:-}" = state_file ] &&
        [ "${2-}" = "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json" ] &&
        [ ! -e "$cleanup_fail_marker" ]; then
        : >"$cleanup_fail_marker"
        return 1
    fi
    command rm "$@"
}
rmdir() {
    if [ ! -e "$cleanup_fail_marker" ]; then
        case ${ZTE_TEST_CLEANUP_FAIL_STAGE:-}:$1 in
            state_dir:"$ZTE_SIM_CALIBRATION_STATE_DIR"|lock_dir:"$ZTE_SIM_CALIBRATION_LOCK_DIR"|claim:"$ZTE_SIM_CALIBRATION_LOCK_DIR/recovery-active")
                : >"$cleanup_fail_marker"
                return 1
                ;;
        esac
    fi
    command rmdir "$@"
}

cp ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/credentials.sh "$lib/"
cp ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/json.sh "$lib/"
cp ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/validation.sh "$lib/"
cp ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh "$lib/"
cp ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh "$lib/"
cp ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/action-executor.sh "$lib/"
cat >"$lib/session.sh" <<'EOF'
zte_session_login() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$ZTE_TEST_LOGIN_LOG"
    [ "${ZTE_TEST_LOGIN_FAIL:-0}" = 0 ]
}
EOF
cat >"$lib/adapter-zte-u25s.sh" <<'EOF'
zte_adapter_fetch() {
    printf '%s\n' fetch >>"$ZTE_TEST_EVENT_LOG"
    printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$ZTE_TEST_FETCH_LOG"
    [ "${ZTE_TEST_FETCH_FAIL:-0}" = 0 ] || return 1
    printf '%s\n' "$ZTE_TEST_RAW"
}
EOF
manager_service=$state/manager-service
manager_state=$state/manager-state
manager_log=$state/manager-calls
manager_running_checks=$state/manager-running-checks
event_log=$state/events
provisional_audit=$state/provisional-audit
durability_log=$state/durability-events
sync_tool=$state/sync
cat >"$sync_tool" <<'EOF'
#!/bin/sh
state_json=$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")
case $state_json in
    *'"original_target":null'*) checkpoint=null ;;
    *) checkpoint=full ;;
esac
printf 'sync:%s\n' "$checkpoint" >>"$ZTE_TEST_DURABILITY_LOG"
[ "${ZTE_TEST_SYNC_FAIL_CHECKPOINT:-}" != "$checkpoint" ]
EOF
chmod +x "$sync_tool"
cat >"$manager_service" <<'EOF'
#!/bin/sh
case ${1-} in
    running)
        printf '%s\n' running-check >>"$ZTE_TEST_EVENT_LOG"
        case $(cat "$ZTE_TEST_MANAGER_STATE") in
            running) exit 0 ;;
            stopped) exit 1 ;;
            stopping)
                checks=$(cat "$ZTE_TEST_MANAGER_RUNNING_CHECKS")
                checks=$((checks + 1))
                printf '%s\n' "$checks" >"$ZTE_TEST_MANAGER_RUNNING_CHECKS"
                if [ "$checks" -ge "${ZTE_TEST_STOP_DELAY:-0}" ]; then
                    printf '%s\n' stopped >"$ZTE_TEST_MANAGER_STATE"
                    exit 1
                fi
                exit 0
                ;;
            *) exit 1 ;;
        esac
        ;;
    stop)
        printf '%s\n' stop >>"$ZTE_TEST_EVENT_LOG"
        printf '%s\n' stop >>"$ZTE_TEST_MANAGER_LOG"
        cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json" \
            >"$ZTE_TEST_PROVISIONAL_AUDIT"
        case ${ZTE_TEST_MANAGER_FAIL:-} in
            stop_running) exit 1 ;;
            stop_stopped|stop_stopped_start)
                printf '%s\n' stopped >"$ZTE_TEST_MANAGER_STATE"
                exit 1
                ;;
            stop_running_success) exit 0 ;;
        esac
        if [ "${ZTE_TEST_STOP_DELAY:-0}" -eq 0 ]; then
            printf '%s\n' stopped >"$ZTE_TEST_MANAGER_STATE"
        else
            printf '%s\n' stopping >"$ZTE_TEST_MANAGER_STATE"
            printf '%s\n' 0 >"$ZTE_TEST_MANAGER_RUNNING_CHECKS"
        fi
        if [ "${ZTE_TEST_BREAK_STATE_AFTER_STOP:-0}" = 1 ]; then
            chmod 500 "$ZTE_SIM_CALIBRATION_STATE_DIR"
        fi
        ;;
    start)
        printf '%s\n' manager:start >>"$ZTE_TEST_DURABILITY_LOG"
        printf '%s\n' start >>"$ZTE_TEST_EVENT_LOG"
        printf '%s\n' start >>"$ZTE_TEST_MANAGER_LOG"
        if [ "${ZTE_TEST_REQUIRE_CLEAN_START:-0}" = 1 ]; then
            [ ! -e "$ZTE_SIM_CALIBRATION_STATE_DIR" ] &&
                [ ! -L "$ZTE_SIM_CALIBRATION_STATE_DIR" ] &&
                [ ! -e "$ZTE_SIM_CALIBRATION_LOCK_DIR" ] &&
                [ ! -L "$ZTE_SIM_CALIBRATION_LOCK_DIR" ] || exit 1
        fi
        case ${ZTE_TEST_MANAGER_FAIL:-} in
            start|stop_stopped_start) exit 1 ;;
        esac
        chmod 700 "$ZTE_SIM_CALIBRATION_STATE_DIR" 2>/dev/null || :
        printf '%s\n' running >"$ZTE_TEST_MANAGER_STATE"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$manager_service"

printf '%s\n' 'password=test-password' >"$credential_file"
chmod 600 "$credential_file"

ZTE_SIM_CALIBRATION_LIB_DIR=$lib
ZTE_SIM_CALIBRATION_CREDENTIAL_FILE=$credential_file
ZTE_SIM_CALIBRATION_HOST=192.168.0.1
ZTE_SIM_CALIBRATION_COOKIE_FILE=$cookie_file
ZTE_SIM_CALIBRATION_STATE_DIR=$state/calibration-state
ZTE_SIM_CALIBRATION_LOCK_DIR=$state/calibration-lock
ZTE_SIM_CALIBRATION_MANAGER_SERVICE=$manager_service
ZTE_SIM_CALIBRATION_SYNC=$sync_tool
ZTE_SIM_CALIBRATION_STOP_ATTEMPTS=3
ZTE_SIM_CALIBRATION_STOP_INTERVAL=0
ZTE_TEST_FETCH_LOG=$fetch_log
ZTE_TEST_FETCH_FAIL=0
ZTE_TEST_LOGIN_LOG=$login_log
ZTE_TEST_LOGIN_FAIL=0
ZTE_TEST_MANAGER_STATE=$manager_state
ZTE_TEST_MANAGER_LOG=$manager_log
ZTE_TEST_MANAGER_RUNNING_CHECKS=$manager_running_checks
ZTE_TEST_EVENT_LOG=$event_log
ZTE_TEST_PROVISIONAL_AUDIT=$provisional_audit
ZTE_TEST_MANAGER_FAIL=
ZTE_TEST_STOP_DELAY=0
ZTE_TEST_BREAK_STATE_AFTER_STOP=0
ZTE_TEST_DURABILITY_LOG=$durability_log
ZTE_TEST_SYNC_FAIL_CHECKPOINT=
ZTE_TEST_REQUIRE_CLEAN_START=0
ZTE_TEST_POWER_LOSS_TARGET=
export ZTE_SIM_CALIBRATION_LIB_DIR
export ZTE_SIM_CALIBRATION_CREDENTIAL_FILE
export ZTE_SIM_CALIBRATION_HOST
export ZTE_SIM_CALIBRATION_COOKIE_FILE
export ZTE_SIM_CALIBRATION_STATE_DIR
export ZTE_SIM_CALIBRATION_LOCK_DIR
export ZTE_SIM_CALIBRATION_MANAGER_SERVICE
export ZTE_SIM_CALIBRATION_SYNC
export ZTE_SIM_CALIBRATION_STOP_ATTEMPTS
export ZTE_SIM_CALIBRATION_STOP_INTERVAL
export ZTE_TEST_FETCH_LOG
export ZTE_TEST_FETCH_FAIL
export ZTE_TEST_LOGIN_LOG
export ZTE_TEST_LOGIN_FAIL
export ZTE_TEST_MANAGER_STATE
export ZTE_TEST_MANAGER_LOG
export ZTE_TEST_MANAGER_RUNNING_CHECKS
export ZTE_TEST_EVENT_LOG
export ZTE_TEST_PROVISIONAL_AUDIT
export ZTE_TEST_MANAGER_FAIL
export ZTE_TEST_STOP_DELAY
export ZTE_TEST_BREAK_STATE_AFTER_STOP
export ZTE_TEST_DURABILITY_LOG
export ZTE_TEST_SYNC_FAIL_CHECKPOINT
export ZTE_TEST_REQUIRE_CLEAN_START
export ZTE_TEST_POWER_LOSS_TARGET

if (
    # shellcheck source=/dev/null
    . "$tool"
); then
    pass
else
    fail 'SIM calibration tool must be safe to source for unit testing'
    finish
fi
# shellcheck source=/dev/null
. "$tool"

# Unit tests exercise the remaining probe contract without weakening the
# production root check.
zte_sim_calibration_require_root() {
    return 0
}

zte_sim_calibration_path_root_owned() {
    [ "${ZTE_TEST_NONROOT_PATH:-}" != "$1" ]
}

zte_sim_calibration_state_dir_root_owned() {
    zte_sim_calibration_path_root_owned "$ZTE_SIM_CALIBRATION_STATE_DIR"
}

sleep() {
    printf 'sleep:%s\n' "$1" >>"$event_log"
}

switch_log=$state/switches
state_audit=$state/state-audit
switch_once_marker=$state/switch-once-marker
zte_execute_switch_sim() {
    printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >>"$switch_log"
    printf 'switch:%s\n' "$4" >>"$durability_log"
    if [ "${ZTE_TEST_LOG_SWITCH_EVENTS:-0}" = 1 ]; then
        printf 'switch:%s\n' "$4" >>"$event_log"
    fi
    if [ ! -s "$state_audit" ]; then
        printf '%s|%s|%s|%s\n' \
            "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")" \
            "$(test_file_mode "$ZTE_SIM_CALIBRATION_STATE_DIR")" \
            "$(test_file_mode "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")" \
            "$(test_file_mode "$ZTE_SIM_CALIBRATION_LOCK_DIR")" \
            >"$state_audit"
    fi
    if [ "${ZTE_TEST_SWITCH_FAIL_ONCE:-}" = "$4" ] &&
        [ ! -e "$switch_once_marker" ]; then
        : >"$switch_once_marker"
        return 1
    fi
    case " ${ZTE_TEST_SWITCH_FAIL:-} " in
        *" $4 "*) return 1 ;;
    esac
    if [ "${ZTE_TEST_POWER_LOSS_TARGET:-}" = "$4" ]; then
        trap - 0 1 2 15
        exit 99
    fi
    return 0
}

sim_call() {
    ZTE_TEST_RAW=$1
    ZTE_TEST_FETCH_FAIL=${2:-0}
    export ZTE_TEST_RAW ZTE_TEST_FETCH_FAIL
    zte_sim_calibration_main probe
}

assert_probe_failure() {
    expected_code=$1
    shift
    probe_status=0
    probe_output=$(sim_call "$@") || probe_status=$?
    assert_eq 1 "$probe_status"
    assert_eq \
        "{\"ok\":false,\"mode\":\"probe\",\"code\":\"$expected_code\"}" \
        "$probe_output"
}

ready_raw() {
    case $1 in
        physical) slot=0 ;;
        sim1) slot=1 ;;
        sim2) slot=2 ;;
        sim3) slot=3 ;;
        *) return 1 ;;
    esac
    printf '%s\n' \
        "{\"simcard_active_slot_temp\":\"$slot\",\"mc_modem_main_state\":\"connected\",\"network_provider_fullname\":\"Carrier Secret\",\"ppp_status\":\"ipv4_ipv6_connected\"}"
}

default_calibration_state_dir=$ZTE_SIM_CALIBRATION_STATE_DIR
default_calibration_lock_dir=$ZTE_SIM_CALIBRATION_LOCK_DIR
reset_execute_fixture() {
    if command -v zte_sim_calibration_disarm_traps >/dev/null 2>&1; then
        zte_sim_calibration_disarm_traps
    fi
    trap cleanup EXIT HUP INT TERM
    ZTE_SIM_CALIBRATION_STATE_DIR=$default_calibration_state_dir
    ZTE_SIM_CALIBRATION_LOCK_DIR=$default_calibration_lock_dir
    ZTE_TEST_FETCH_FAIL=0
    ZTE_TEST_LOGIN_FAIL=0
    ZTE_TEST_SWITCH_FAIL=
    ZTE_TEST_SWITCH_FAIL_ONCE=
    ZTE_TEST_MANAGER_FAIL=
    ZTE_TEST_STOP_DELAY=0
    ZTE_TEST_BREAK_STATE_AFTER_STOP=0
    ZTE_TEST_NONROOT_PATH=
    ZTE_TEST_LOG_SWITCH_EVENTS=0
    ZTE_TEST_SYNC_FAIL_CHECKPOINT=
    ZTE_TEST_REQUIRE_CLEAN_START=0
    ZTE_TEST_POWER_LOSS_TARGET=
    _zte_sim_calibration_active_state_tmp=
    _zte_sim_calibration_owned_state_dir=0
    ZTE_SIM_CALIBRATION_STOP_ATTEMPTS=3
    ZTE_SIM_CALIBRATION_STOP_INTERVAL=0
    export ZTE_SIM_CALIBRATION_STATE_DIR
    export ZTE_SIM_CALIBRATION_LOCK_DIR
    export ZTE_TEST_FETCH_FAIL
    export ZTE_TEST_LOGIN_FAIL
    export ZTE_TEST_SWITCH_FAIL
    export ZTE_TEST_SWITCH_FAIL_ONCE
    export ZTE_TEST_MANAGER_FAIL
    export ZTE_TEST_STOP_DELAY
    export ZTE_TEST_BREAK_STATE_AFTER_STOP
    export ZTE_TEST_NONROOT_PATH
    export ZTE_TEST_LOG_SWITCH_EVENTS
    export ZTE_TEST_SYNC_FAIL_CHECKPOINT
    export ZTE_TEST_REQUIRE_CLEAN_START
    export ZTE_TEST_POWER_LOSS_TARGET
    export ZTE_SIM_CALIBRATION_STOP_ATTEMPTS
    export ZTE_SIM_CALIBRATION_STOP_INTERVAL
    chmod 700 "$ZTE_SIM_CALIBRATION_STATE_DIR" 2>/dev/null || :
    rm -rf "$ZTE_SIM_CALIBRATION_STATE_DIR" \
        "$ZTE_SIM_CALIBRATION_LOCK_DIR"
    : >"$fetch_log"
    : >"$login_log"
    : >"$switch_log"
    : >"$state_audit"
    : >"$manager_log"
    : >"$manager_running_checks"
    : >"$event_log"
    : >"$provisional_audit"
    : >"$durability_log"
    rm -f "$switch_once_marker"
}

execute_call() {
    ZTE_TEST_RAW=$(ready_raw "$1")
    export ZTE_TEST_RAW
    zte_sim_calibration_main execute I_AM_ON_SPARE_U25S "$2"
}

prepare_recovery_state() {
    reset_execute_fixture
    recovery_original=$1
    recovery_manager=$2
    mkdir "$ZTE_SIM_CALIBRATION_LOCK_DIR"
    chmod 700 "$ZTE_SIM_CALIBRATION_LOCK_DIR"
    mkdir "$ZTE_SIM_CALIBRATION_STATE_DIR"
    chmod 700 "$ZTE_SIM_CALIBRATION_STATE_DIR"
    case $recovery_original in
        null) recovery_original_json=null ;;
        *) recovery_original_json="\"$recovery_original\"" ;;
    esac
    printf \
        '{"original_target":%s,"manager_was_running":%s}\n' \
        "$recovery_original_json" "$recovery_manager" \
        >"$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
    chmod 600 "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
    printf '%s\n' stopped >"$manager_state"
}

for slot_target in \
    '0:physical' \
    '1:sim1' \
    '2:sim2' \
    '3:sim3'; do
    slot=${slot_target%%:*}
    target=${slot_target#*:}
    : >"$fetch_log"
    : >"$login_log"
    result=$(sim_call "{\"simcard_active_slot_temp\":\"$slot\",\"mc_modem_main_state\":\"connected\",\"network_provider_fullname\":\"Carrier Secret\",\"ppp_status\":\"ipv4_ipv6_connected\"}")
    assert_eq \
        "{\"ok\":true,\"mode\":\"probe\",\"active_target\":\"$target\",\"modem_ready\":true,\"network_registered\":true,\"ppp_ready\":true}" \
        "$result"
    assert_eq "192.168.0.1|test-password|$cookie_file" \
        "$(cat "$login_log")"
    assert_eq "192.168.0.1|test-password|$cookie_file" "$(cat "$fetch_log")"
done

# Missing or non-0600 credentials are rejected before the adapter is called.
rm "$credential_file"
: >"$fetch_log"
assert_probe_failure credentials_unavailable \
    '{"simcard_active_slot_temp":"0","mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}'
assert_eq '' "$(cat "$fetch_log")"
printf '%s\n' 'password=test-password' >"$credential_file"
chmod 644 "$credential_file"
assert_probe_failure credentials_unavailable \
    '{"simcard_active_slot_temp":"0","mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}'
chmod 600 "$credential_file"

# A calibration probe authenticates before accepting readiness fields.
: >"$fetch_log"
: >"$login_log"
ZTE_TEST_LOGIN_FAIL=1
export ZTE_TEST_LOGIN_FAIL
assert_probe_failure authentication_failed \
    '{"simcard_active_slot_temp":"0","mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}'
assert_eq '' "$(cat "$fetch_log")"
ZTE_TEST_LOGIN_FAIL=0

# Each readiness failure has a stable, non-secret diagnostic code.
assert_probe_failure modem_not_connected \
    '{"simcard_active_slot_temp":"0","mc_modem_main_state":"offline","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}'
assert_probe_failure network_unregistered \
    '{"simcard_active_slot_temp":"1","mc_modem_main_state":"connected","network_provider_fullname":"   ","ppp_status":"ipv4_ipv6_connected"}'
assert_probe_failure ppp_not_ready \
    '{"simcard_active_slot_temp":"2","mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret","ppp_status":"disconnected"}'
assert_probe_failure invalid_active_slot \
    '{"simcard_active_slot_temp":"9","mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}'
assert_probe_failure device_fetch_failed \
    '{"simcard_active_slot_temp":"0","mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}' \
    1

for raw in \
    '{"mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}' \
    '{"simcard_active_slot_temp":"0","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}' \
    '{"simcard_active_slot_temp":"0","mc_modem_main_state":"connected","ppp_status":"ipv4_ipv6_connected"}' \
    '{"simcard_active_slot_temp":"0","mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret"}'; do
    assert_probe_failure missing_field "$raw"
done

assert_probe_failure invalid_device_response \
    '{"simcard_active_slot_temp":"0"'

# Probe takes no extra arguments and never leaks credential, cookie, or provider.
assert_failure zte_sim_calibration_main probe extra >/dev/null 2>&1
result=$(sim_call '{"simcard_active_slot_temp":"0","mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}')
case $result in
    *test-password*|*Carrier\ Secret*|*"$cookie_file"*)
        fail 'probe output must not expose secrets or provider details'
        ;;
    *) pass ;;
esac

# Execute switches away and back only while holding durable recovery state.
reset_execute_fixture
printf '%s\n' running >"$manager_state"
execute_status=0
execute_result=$(execute_call physical sim2) || execute_status=$?
assert_eq 0 "$execute_status"
assert_eq \
    '{"ok":true,"mode":"execute","target":"sim2","target_verified":true,"original_restored":true}' \
    "$execute_result"
assert_eq \
    "192.168.0.1|test-password|$cookie_file|sim2
192.168.0.1|test-password|$cookie_file|physical" \
    "$(cat "$switch_log")"
assert_eq 'stop
start' "$(cat "$manager_log")"
assert_eq running "$(cat "$manager_state")"
assert_eq \
    '{"original_target":"physical","manager_was_running":true}|700|600|700' \
    "$(cat "$state_audit")"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$provisional_audit")"
assert_eq \
    'running-check
stop
running-check
fetch
running-check
start' \
    "$(cat "$event_log")"
assert_failure test -e "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
assert_failure test -d "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
assert_eq 'sync:full
switch:sim2
switch:physical
sync:null
manager:start' "$(cat "$durability_log")"

# A full checkpoint must reach persistent storage before the first device
# write. Failed sync leaves the full recovery record and manager stopped.
reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_SYNC_FAIL_CHECKPOINT=full
export ZTE_TEST_SYNC_FAIL_CHECKPOINT
execute_status=0
execute_result=$(execute_call physical sim2) || execute_status=$?
assert_failure test "$execute_status" -eq 0
assert_eq state_sync_failed "$execute_result"
assert_eq '' "$(cat "$switch_log")"
assert_eq stopped "$(cat "$manager_state")"
assert_eq \
    '{"original_target":"physical","manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# Simulated untrappable power loss leaves the full persistent checkpoint.
# The init gate rejects restart, then recover restores exactly once, durably
# checkpoints null, removes the gate artifacts, and only then starts manager.
reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_POWER_LOSS_TARGET=sim2
export ZTE_TEST_POWER_LOSS_TARGET
execute_status=0
(
    execute_call physical sim2
) >/dev/null 2>&1 || execute_status=$?
assert_eq 99 "$execute_status"
assert_eq \
    '{"original_target":"physical","manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
assert_eq stopped "$(cat "$manager_state")"

init_restart_log=$state/init-restart-instances
: >"$init_restart_log"
init_service=./package/zte-usb-wifi-manager/files/etc/init.d/zte-usb-wifi-manager
restart_status=0
(
    procd_open_instance() {
        printf '%s\n' "$1" >>"$init_restart_log"
    }
    procd_set_param() { :; }
    procd_close_instance() { :; }
    procd_add_reload_trigger() { :; }
    # shellcheck source=/dev/null
    . "$init_service"
    start_service
) || restart_status=$?
assert_failure test "$restart_status" -eq 0
assert_eq '' "$(cat "$init_restart_log")"

ZTE_TEST_POWER_LOSS_TARGET=
ZTE_TEST_REQUIRE_CLEAN_START=1
export ZTE_TEST_POWER_LOSS_TARGET ZTE_TEST_REQUIRE_CLEAN_START
: >"$switch_log"
: >"$durability_log"
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_eq 0 "$recover_status"
assert_eq \
    '{"ok":true,"mode":"recover","original_restored":true,"manager_restored":true}' \
    "$recover_result"
assert_eq \
    "192.168.0.1|test-password|$cookie_file|physical" \
    "$(cat "$switch_log")"
assert_eq 'switch:physical
sync:null
manager:start' "$(cat "$durability_log")"
assert_eq running "$(cat "$manager_state")"
assert_failure test -e "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -e "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# A manager which started stopped remains stopped after a successful loop.
reset_execute_fixture
printf '%s\n' stopped >"$manager_state"
execute_status=0
execute_result=$(execute_call sim1 sim3) || execute_status=$?
assert_eq 0 "$execute_status"
assert_eq \
    '{"ok":true,"mode":"execute","target":"sim3","target_verified":true,"original_restored":true}' \
    "$execute_result"
assert_eq "192.168.0.1|test-password|$cookie_file" \
    "$(cat "$login_log")"
assert_eq '' "$(cat "$manager_log")"
assert_eq stopped "$(cat "$manager_state")"
assert_eq \
    '{"original_target":"sim1","manager_was_running":false}|700|600|700' \
    "$(cat "$state_audit")"
assert_eq 'running-check
fetch
running-check' "$(cat "$event_log")"
assert_failure test -d "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# Static arguments, stop bounds, and credentials are rejected before locking.
reset_execute_fixture
printf '%s\n' running >"$manager_state"
assert_failure zte_sim_calibration_main execute WRONG_ACK sim2 \
    >/dev/null 2>&1
assert_failure zte_sim_calibration_main execute I_AM_ON_SPARE_U25S sim2 extra \
    >/dev/null 2>&1
assert_failure zte_sim_calibration_main execute I_AM_ON_SPARE_U25S invalid \
    >/dev/null 2>&1
ZTE_SIM_CALIBRATION_STOP_ATTEMPTS=0
export ZTE_SIM_CALIBRATION_STOP_ATTEMPTS
assert_failure execute_call physical sim2 >/dev/null 2>&1
ZTE_SIM_CALIBRATION_STOP_ATTEMPTS=3
ZTE_SIM_CALIBRATION_STOP_INTERVAL=-1
export ZTE_SIM_CALIBRATION_STOP_ATTEMPTS
export ZTE_SIM_CALIBRATION_STOP_INTERVAL
assert_failure execute_call physical sim2 >/dev/null 2>&1
ZTE_SIM_CALIBRATION_STOP_INTERVAL=0
export ZTE_SIM_CALIBRATION_STOP_INTERVAL
assert_eq '' "$(cat "$fetch_log")"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

rm "$credential_file"
assert_failure execute_call physical sim2 >/dev/null 2>&1
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
printf '%s\n' 'password=test-password' >"$credential_file"
chmod 600 "$credential_file"

# A conflicting lock or any pre-existing state is rejected without reading the
# device or modifying the old recovery record.
reset_execute_fixture
printf '%s\n' running >"$manager_state"
mkdir "$ZTE_SIM_CALIBRATION_LOCK_DIR"
chmod 700 "$ZTE_SIM_CALIBRATION_LOCK_DIR"
assert_failure execute_call physical sim2 >/dev/null 2>&1
assert_eq '' "$(cat "$switch_log")"
assert_eq '' "$(cat "$manager_log")"
assert_eq '' "$(cat "$fetch_log")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# An interruption after this execute creates and arms its lock, but before it
# rejects a pre-existing state directory, must never adopt that old state.
for pre_state_interrupt in HUP:129 INT:130 EXIT:7; do
    reset_execute_fixture
    printf '%s\n' stopped >"$manager_state"
    mkdir "$ZTE_SIM_CALIBRATION_STATE_DIR"
    chmod 700 "$ZTE_SIM_CALIBRATION_STATE_DIR"
    old_state='{"original_target":"physical","manager_was_running":true}'
    printf '%s\n' "$old_state" \
        >"$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
    chmod 600 "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
    cp "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json" "$state/old-state-copy"
    interrupt_name=${pre_state_interrupt%%:*}
    interrupt_status=${pre_state_interrupt#*:}
    execute_status=0
    (
        zte_sim_calibration_arm_traps() {
            _zte_sim_calibration_recovery_attempted=0
            _zte_sim_calibration_traps_armed=1
            trap zte_sim_calibration_on_exit 0
            trap 'zte_sim_calibration_on_signal 129' 1
            trap 'zte_sim_calibration_on_signal 130' 2
            trap 'zte_sim_calibration_on_signal 143' 15
            case $interrupt_name in
                HUP) zte_sim_calibration_on_signal 129 ;;
                INT) zte_sim_calibration_on_signal 130 ;;
                EXIT) exit 7 ;;
            esac
        }
        execute_call physical sim2
    ) >/dev/null 2>&1 || execute_status=$?
    assert_eq "$interrupt_status" "$execute_status" \
        "$interrupt_name pre-state interruption status"
    assert_eq '' "$(cat "$fetch_log")"
    assert_eq '' "$(cat "$switch_log")"
    assert_eq '' "$(cat "$manager_log")"
    assert_success cmp -s \
        "$state/old-state-copy" \
        "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
    assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
done

reset_execute_fixture
printf '%s\n' running >"$manager_state"
mkdir "$ZTE_SIM_CALIBRATION_STATE_DIR"
chmod 700 "$ZTE_SIM_CALIBRATION_STATE_DIR"
old_state='{"original_target":"sim3","manager_was_running":true}'
printf '%s\n' "$old_state" \
    >"$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
chmod 600 "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
assert_failure execute_call physical sim2 >/dev/null 2>&1
assert_eq "$old_state" \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_eq '' "$(cat "$fetch_log")"
assert_eq '' "$(cat "$manager_log")"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

reset_execute_fixture
printf '%s\n' running >"$manager_state"
old_state_target=$state/old-state-target
mkdir "$old_state_target"
printf '%s\n' keep >"$old_state_target/marker"
ln -s "$old_state_target" "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure execute_call physical sim2 >/dev/null 2>&1
assert_success test -L "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_eq keep "$(cat "$old_state_target/marker")"
assert_eq '' "$(cat "$fetch_log")"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# Asynchronous stop is bounded and fetch cannot run until running becomes false.
reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_STOP_DELAY=2
export ZTE_TEST_STOP_DELAY
execute_status=0
execute_result=$(execute_call physical sim2) || execute_status=$?
assert_eq 0 "$execute_status"
assert_eq \
    'running-check
stop
running-check
sleep:0
running-check
fetch
running-check
start' \
    "$(cat "$event_log")"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$provisional_audit")"

# If stop returns failure but the manager is still running, or if a successful
# stop never quiesces, no fetch occurs and the canonical null checkpoint is
# retained when the common finalizer cannot safely stop the manager.
reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_MANAGER_FAIL=stop_running
export ZTE_TEST_MANAGER_FAIL
assert_failure execute_call physical sim2 >/dev/null 2>&1
assert_eq 'stop
stop' "$(cat "$manager_log")"
assert_eq running "$(cat "$manager_state")"
assert_eq '' "$(cat "$fetch_log")"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_MANAGER_FAIL=stop_running_success
ZTE_SIM_CALIBRATION_STOP_ATTEMPTS=3
ZTE_SIM_CALIBRATION_STOP_INTERVAL=1
export ZTE_TEST_MANAGER_FAIL
export ZTE_SIM_CALIBRATION_STOP_ATTEMPTS
export ZTE_SIM_CALIBRATION_STOP_INTERVAL
assert_failure execute_call physical sim2 >/dev/null 2>&1
assert_eq '' "$(cat "$fetch_log")"
assert_eq 'sleep:1
sleep:1
sleep:1
sleep:1' "$(grep '^sleep:' "$event_log")"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# If the manager did stop, every later failure first tries to restore it.
# Failed restore keeps the provisional or full state and lock for Task B2.
reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_BREAK_STATE_AFTER_STOP=1
ZTE_TEST_MANAGER_FAIL=start
export ZTE_TEST_BREAK_STATE_AFTER_STOP
export ZTE_TEST_MANAGER_FAIL
execute_status=0
execute_result=$(execute_call physical sim2) || execute_status=$?
assert_failure test "$execute_status" -eq 0
assert_eq state_write_failed "$execute_result"
assert_eq '' "$(cat "$switch_log")"
assert_eq 'stop
start' "$(cat "$manager_log")"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_FETCH_FAIL=1
ZTE_TEST_MANAGER_FAIL=start
export ZTE_TEST_FETCH_FAIL
export ZTE_TEST_MANAGER_FAIL
execute_status=0
execute_result=$(execute_call physical sim2) || execute_status=$?
assert_failure test "$execute_status" -eq 0
assert_eq read_failed "$execute_result"
assert_eq '' "$(cat "$switch_log")"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_MANAGER_FAIL=start
export ZTE_TEST_MANAGER_FAIL
execute_status=0
execute_result=$(execute_call physical physical) || execute_status=$?
assert_failure test "$execute_status" -eq 0
assert_eq same_target "$execute_result"
assert_eq '' "$(cat "$switch_log")"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_MANAGER_FAIL=stop_stopped_start
export ZTE_TEST_MANAGER_FAIL
execute_status=0
execute_result=$(execute_call physical sim2) || execute_status=$?
assert_failure test "$execute_status" -eq 0
assert_eq '' "$(cat "$fetch_log")"
assert_eq '' "$(cat "$switch_log")"
assert_eq 'stop
start' "$(cat "$manager_log")"
assert_eq stopped "$(cat "$manager_state")"
assert_eq manager_stop_failed "$execute_result"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# Once a write starts, executor failure triggers exactly one best-effort restore
# while the original command still returns its fixed failure code.
reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_SWITCH_FAIL=sim2
export ZTE_TEST_SWITCH_FAIL
execute_status=0
execute_result=$(execute_call physical sim2) || execute_status=$?
assert_failure test "$execute_status" -eq 0
assert_eq switch_target_failed "$execute_result"
assert_eq running "$(cat "$manager_state")"
assert_eq 'stop
start' "$(cat "$manager_log")"
assert_eq \
    "192.168.0.1|test-password|$cookie_file|sim2
192.168.0.1|test-password|$cookie_file|physical" \
    "$(cat "$switch_log")"
assert_failure test -d "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_SWITCH_FAIL_ONCE=physical
export ZTE_TEST_SWITCH_FAIL_ONCE
execute_status=0
execute_result=$(execute_call physical sim2) || execute_status=$?
assert_failure test "$execute_status" -eq 0
assert_eq restore_failed "$execute_result"
assert_eq running "$(cat "$manager_state")"
assert_eq 'stop
start' "$(cat "$manager_log")"
assert_eq \
    "192.168.0.1|test-password|$cookie_file|sim2
192.168.0.1|test-password|$cookie_file|physical
192.168.0.1|test-password|$cookie_file|physical" \
    "$(cat "$switch_log")"
assert_failure test -d "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

reset_execute_fixture
printf '%s\n' running >"$manager_state"
ZTE_TEST_SWITCH_FAIL='sim2 physical'
export ZTE_TEST_SWITCH_FAIL
execute_status=0
execute_result=$(execute_call physical sim2) || execute_status=$?
assert_failure test "$execute_status" -eq 0
assert_eq automatic_recovery_failed "$execute_result"
assert_eq stopped "$(cat "$manager_state")"
assert_eq stop "$(cat "$manager_log")"
assert_eq \
    '{"original_target":"physical","manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# Manual recovery accepts only canonical, root-owned state protected by the
# existing calibration lock.
prepare_recovery_state physical true
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_eq 0 "$recover_status"
assert_eq \
    '{"ok":true,"mode":"recover","original_restored":true,"manager_restored":true}' \
    "$recover_result"
assert_eq \
    "192.168.0.1|test-password|$cookie_file|physical" \
    "$(cat "$switch_log")"
assert_eq start "$(cat "$manager_log")"
assert_failure test -d "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

prepare_recovery_state null true
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_eq 0 "$recover_status"
assert_eq \
    '{"ok":true,"mode":"recover","original_restored":false,"manager_restored":true}' \
    "$recover_result"
assert_eq '' "$(cat "$switch_log")"
assert_eq start "$(cat "$manager_log")"

prepare_recovery_state sim3 false
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_eq 0 "$recover_status"
assert_eq \
    '{"ok":true,"mode":"recover","original_restored":true,"manager_restored":true}' \
    "$recover_result"
assert_eq '' "$(cat "$manager_log")"
assert_eq stopped "$(cat "$manager_state")"

# Recovery always quiesces a currently running manager before any device write,
# regardless of the recorded manager state.
prepare_recovery_state physical true
printf '%s\n' running >"$manager_state"
ZTE_TEST_LOG_SWITCH_EVENTS=1
export ZTE_TEST_LOG_SWITCH_EVENTS
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_eq 0 "$recover_status"
assert_eq \
    'running-check
stop
running-check
switch:physical
start' \
    "$(cat "$event_log")"

prepare_recovery_state sim2 false
printf '%s\n' running >"$manager_state"
ZTE_TEST_LOG_SWITCH_EVENTS=1
export ZTE_TEST_LOG_SWITCH_EVENTS
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_eq 0 "$recover_status"
assert_eq stopped "$(cat "$manager_state")"
assert_eq 'stop' "$(cat "$manager_log")"
assert_eq \
    'running-check
stop
running-check
switch:sim2' \
    "$(cat "$event_log")"

prepare_recovery_state physical true
printf '%s\n' running >"$manager_state"
ZTE_TEST_MANAGER_FAIL=stop_running_success
export ZTE_TEST_MANAGER_FAIL
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_failure test "$recover_status" -eq 0
assert_eq recovery_stop_failed "$recover_result"
assert_eq '' "$(cat "$switch_log")"
assert_success test -f "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

prepare_recovery_state physical true
ZTE_TEST_SWITCH_FAIL=physical
export ZTE_TEST_SWITCH_FAIL
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_failure test "$recover_status" -eq 0
assert_eq recovery_switch_failed "$recover_result"
assert_eq '' "$(cat "$manager_log")"
assert_success test -f "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# A restored original target is not followed by cleanup or manager start until
# the null checkpoint is durably synced. Retrying that null state never writes
# the device again.
prepare_recovery_state physical true
ZTE_TEST_SYNC_FAIL_CHECKPOINT=null
ZTE_TEST_REQUIRE_CLEAN_START=1
export ZTE_TEST_SYNC_FAIL_CHECKPOINT ZTE_TEST_REQUIRE_CLEAN_START
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_failure test "$recover_status" -eq 0
assert_eq state_sync_failed "$recover_result"
assert_eq 1 "$(wc -l <"$switch_log" | tr -d ' ')"
assert_eq stopped "$(cat "$manager_state")"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

ZTE_TEST_SYNC_FAIL_CHECKPOINT=
export ZTE_TEST_SYNC_FAIL_CHECKPOINT
: >"$switch_log"
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_eq 0 "$recover_status"
assert_eq '' "$(cat "$switch_log")"
assert_eq running "$(cat "$manager_state")"
assert_failure test -e "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -e "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# Manager start happens only after cleanup. A failed start rebuilds a durable
# canonical null checkpoint so the next recover starts without another switch.
prepare_recovery_state physical true
ZTE_TEST_MANAGER_FAIL=start
ZTE_TEST_REQUIRE_CLEAN_START=1
export ZTE_TEST_MANAGER_FAIL ZTE_TEST_REQUIRE_CLEAN_START
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_failure test "$recover_status" -eq 0
assert_eq manager_restore_failed "$recover_result"
assert_eq \
    '{"original_target":null,"manager_was_running":true}' \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_success test -f "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
assert_eq stopped "$(cat "$manager_state")"
assert_eq 1 "$(wc -l <"$switch_log" | tr -d ' ')"

ZTE_TEST_MANAGER_FAIL=
export ZTE_TEST_MANAGER_FAIL
: >"$switch_log"
recover_status=0
recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
assert_eq 0 "$recover_status"
assert_eq '' "$(cat "$switch_log")"
assert_eq running "$(cat "$manager_state")"
assert_failure test -e "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -e "$ZTE_SIM_CALIBRATION_LOCK_DIR"

assert_failure zte_sim_calibration_main recover extra >/dev/null 2>&1
reset_execute_fixture
assert_failure zte_sim_calibration_main recover >/dev/null 2>&1

# Each state safety violation is rejected without switch, manager action, or
# mutation of the supplied recovery artifacts.
prepare_recovery_state physical true
printf '%s\n' \
    '{"original_target":"physical","manager_was_running":true,"extra":1}' \
    >"$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
chmod 600 "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
invalid_state_before=$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")
assert_failure zte_sim_calibration_main recover >/dev/null 2>&1
assert_eq "$invalid_state_before" \
    "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
assert_eq '' "$(cat "$switch_log")"
assert_eq '' "$(cat "$manager_log")"

for invalid_part in lock_mode state_mode file_mode lock_owner state_owner file_owner; do
    prepare_recovery_state physical true
    case $invalid_part in
        lock_mode) chmod 755 "$ZTE_SIM_CALIBRATION_LOCK_DIR" ;;
        state_mode) chmod 755 "$ZTE_SIM_CALIBRATION_STATE_DIR" ;;
        file_mode) chmod 644 "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json" ;;
        lock_owner) ZTE_TEST_NONROOT_PATH=$ZTE_SIM_CALIBRATION_LOCK_DIR ;;
        state_owner) ZTE_TEST_NONROOT_PATH=$ZTE_SIM_CALIBRATION_STATE_DIR ;;
        file_owner)
            ZTE_TEST_NONROOT_PATH=$ZTE_SIM_CALIBRATION_STATE_DIR/state.json
            ;;
    esac
    export ZTE_TEST_NONROOT_PATH
    assert_failure zte_sim_calibration_main recover >/dev/null 2>&1
    assert_eq '' "$(cat "$switch_log")"
    assert_eq '' "$(cat "$manager_log")"
    assert_success test -e "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
done

prepare_recovery_state physical true
state_file_target=$state/state-file-target
mv "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json" "$state_file_target"
ln -s "$state_file_target" "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
assert_failure zte_sim_calibration_main recover >/dev/null 2>&1
assert_success test -L "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
assert_eq '' "$(cat "$switch_log")"

prepare_recovery_state physical true
state_dir_target=$state/state-dir-target
mv "$ZTE_SIM_CALIBRATION_STATE_DIR" "$state_dir_target"
ln -s "$state_dir_target" "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure zte_sim_calibration_main recover >/dev/null 2>&1
assert_success test -L "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_eq '' "$(cat "$switch_log")"

prepare_recovery_state physical true
lock_dir_target=$state/lock-dir-target
mv "$ZTE_SIM_CALIBRATION_LOCK_DIR" "$lock_dir_target"
ln -s "$lock_dir_target" "$ZTE_SIM_CALIBRATION_LOCK_DIR"
assert_failure zte_sim_calibration_main recover >/dev/null 2>&1
assert_success test -L "$ZTE_SIM_CALIBRATION_LOCK_DIR"
assert_eq '' "$(cat "$switch_log")"

prepare_recovery_state physical true
: >"$ZTE_SIM_CALIBRATION_STATE_DIR/unexpected"
assert_failure zte_sim_calibration_main recover >/dev/null 2>&1
assert_success test -e "$ZTE_SIM_CALIBRATION_STATE_DIR/unexpected"
assert_eq '' "$(cat "$switch_log")"

prepare_recovery_state physical true
: >"$ZTE_SIM_CALIBRATION_LOCK_DIR/unexpected"
assert_failure zte_sim_calibration_main recover >/dev/null 2>&1
assert_success test -e "$ZTE_SIM_CALIBRATION_LOCK_DIR/unexpected"
assert_eq '' "$(cat "$switch_log")"

prepare_recovery_state physical true
mkdir "$ZTE_SIM_CALIBRATION_LOCK_DIR/recovery-active"
assert_failure zte_sim_calibration_main recover >/dev/null 2>&1
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR/recovery-active"
assert_eq '' "$(cat "$switch_log")"

for invalid_stop_settings in attempts_zero attempts_huge interval_huge; do
    prepare_recovery_state physical true
    case $invalid_stop_settings in
        attempts_zero) ZTE_SIM_CALIBRATION_STOP_ATTEMPTS=0 ;;
        attempts_huge) ZTE_SIM_CALIBRATION_STOP_ATTEMPTS=121 ;;
        interval_huge) ZTE_SIM_CALIBRATION_STOP_INTERVAL=61 ;;
    esac
    export ZTE_SIM_CALIBRATION_STOP_ATTEMPTS
    export ZTE_SIM_CALIBRATION_STOP_INTERVAL
    assert_failure zte_sim_calibration_main recover >/dev/null 2>&1
    assert_eq '' "$(cat "$switch_log")"
    assert_success test -f "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
    assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
done

# EXIT and signal guards perform at most one recovery attempt. Successful
# recovery preserves the original exit/signal status; failed recovery is
# reported and leaves durable state.
reset_execute_fixture
mkdir "$ZTE_SIM_CALIBRATION_LOCK_DIR"
chmod 700 "$ZTE_SIM_CALIBRATION_LOCK_DIR"
trap_status=0
(
    zte_sim_calibration_arm_traps
    zte_sim_calibration_on_signal 129
) >/dev/null 2>&1 || trap_status=$?
assert_eq 129 "$trap_status"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

reset_execute_fixture
mkdir "$ZTE_SIM_CALIBRATION_LOCK_DIR"
chmod 700 "$ZTE_SIM_CALIBRATION_LOCK_DIR"
: >"$ZTE_SIM_CALIBRATION_LOCK_DIR/foreign"
trap_status=0
trap_result=$(
    (
        zte_sim_calibration_arm_traps
        zte_sim_calibration_on_signal 129
    )
) || trap_status=$?
assert_failure test "$trap_status" -eq 0
assert_eq automatic_recovery_failed "$trap_result"
assert_success test -e "$ZTE_SIM_CALIBRATION_LOCK_DIR/foreign"

reset_execute_fixture
mkdir "$ZTE_SIM_CALIBRATION_LOCK_DIR"
chmod 700 "$ZTE_SIM_CALIBRATION_LOCK_DIR"
mkdir "$ZTE_SIM_CALIBRATION_STATE_DIR"
chmod 700 "$ZTE_SIM_CALIBRATION_STATE_DIR"
_zte_sim_calibration_owned_state_dir=1
trap_status=0
(
    zte_sim_calibration_arm_traps
    zte_sim_calibration_on_signal 129
) >/dev/null 2>&1 || trap_status=$?
assert_eq 129 "$trap_status"
assert_failure test -d "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
assert_eq '' "$(cat "$switch_log")"

prepare_recovery_state null true
active_tmp=$ZTE_SIM_CALIBRATION_STATE_DIR/state.json.tmp.$$
printf '%s\n' \
    '{"original_target":"physical","manager_was_running":true}' \
    >"$active_tmp"
chmod 600 "$active_tmp"
_zte_sim_calibration_active_state_tmp=$active_tmp
_zte_sim_calibration_owned_state_dir=1
trap_status=0
(
    zte_sim_calibration_arm_traps
    zte_sim_calibration_on_signal 130
) >/dev/null 2>&1 || trap_status=$?
assert_eq 130 "$trap_status"
assert_eq '' "$(cat "$switch_log")"
assert_eq start "$(cat "$manager_log")"
assert_failure test -e "$active_tmp"
assert_failure test -d "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

for trap_case in HUP:129 INT:130 TERM:143; do
    trap_name=${trap_case%%:*}
    trap_code=${trap_case#*:}
    prepare_recovery_state physical true
    _zte_sim_calibration_owned_state_dir=1
    trap_status=0
    (
        zte_sim_calibration_arm_traps
        zte_sim_calibration_on_signal "$trap_code"
    ) >/dev/null 2>&1 || trap_status=$?
    assert_eq "$trap_code" "$trap_status" "$trap_name recovery status"
    assert_eq 1 "$(wc -l <"$switch_log" | tr -d ' ')"
    assert_eq start "$(cat "$manager_log")"
    assert_failure test -d "$ZTE_SIM_CALIBRATION_STATE_DIR"
    assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
done

prepare_recovery_state null true
_zte_sim_calibration_owned_state_dir=1
trap_status=0
(
    zte_sim_calibration_arm_traps
    exit 7
) >/dev/null 2>&1 || trap_status=$?
assert_eq 7 "$trap_status"
assert_eq '' "$(cat "$switch_log")"
assert_eq start "$(cat "$manager_log")"
assert_failure test -d "$ZTE_SIM_CALIBRATION_STATE_DIR"
assert_failure test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

prepare_recovery_state physical true
_zte_sim_calibration_owned_state_dir=1
ZTE_TEST_SWITCH_FAIL=physical
export ZTE_TEST_SWITCH_FAIL
trap_status=0
trap_result=$(
    (
        zte_sim_calibration_arm_traps
        exit 7
    )
) || trap_status=$?
assert_failure test "$trap_status" -eq 0
assert_eq automatic_recovery_failed "$trap_result"
assert_eq 1 "$(wc -l <"$switch_log" | tr -d ' ')"
assert_success test -f "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json"
assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

# Cleanup is transactional: failure at any destructive stage re-establishes a
# canonical null state under the lock with the manager stopped.
for cleanup_stage in state_file state_dir lock_dir claim; do
    prepare_recovery_state physical true
    command rm -f "$cleanup_fail_marker"
    ZTE_TEST_CLEANUP_FAIL_STAGE=$cleanup_stage
    export ZTE_TEST_CLEANUP_FAIL_STAGE
    recover_status=0
    recover_result=$(zte_sim_calibration_main recover) || recover_status=$?
    assert_failure test "$recover_status" -eq 0
    assert_eq cleanup_failed "$recover_result"
    assert_eq stopped "$(cat "$manager_state")"
    assert_eq \
        '{"original_target":null,"manager_was_running":true}' \
        "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
    assert_eq 700 "$(test_file_mode "$ZTE_SIM_CALIBRATION_STATE_DIR")"
    assert_eq 600 \
        "$(test_file_mode "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
    assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
    assert_eq 1 "$(wc -l <"$switch_log" | tr -d ' ')"
    assert_eq '' "$(cat "$manager_log")"
done

for cleanup_stage in state_file state_dir lock_dir; do
    reset_execute_fixture
    printf '%s\n' running >"$manager_state"
    command rm -f "$cleanup_fail_marker"
    ZTE_TEST_CLEANUP_FAIL_STAGE=$cleanup_stage
    export ZTE_TEST_CLEANUP_FAIL_STAGE
    execute_status=0
    execute_result=$(execute_call physical sim2) || execute_status=$?
    assert_failure test "$execute_status" -eq 0
    assert_eq cleanup_failed "$execute_result"
    assert_eq 2 "$(wc -l <"$switch_log" | tr -d ' ')"
    assert_eq stopped "$(cat "$manager_state")"
    assert_eq \
        '{"original_target":null,"manager_was_running":true}' \
        "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
    assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"

    reset_execute_fixture
    printf '%s\n' running >"$manager_state"
    command rm -f "$cleanup_fail_marker"
    ZTE_TEST_CLEANUP_FAIL_STAGE=$cleanup_stage
    export ZTE_TEST_CLEANUP_FAIL_STAGE
    execute_status=0
    execute_result=$(execute_call physical physical) || execute_status=$?
    assert_failure test "$execute_status" -eq 0
    assert_eq same_target "$execute_result"
    assert_eq 0 "$(wc -l <"$switch_log" | tr -d ' ')"
    assert_eq stopped "$(cat "$manager_state")"
    assert_eq \
        '{"original_target":null,"manager_was_running":true}' \
        "$(cat "$ZTE_SIM_CALIBRATION_STATE_DIR/state.json")"
    assert_success test -d "$ZTE_SIM_CALIBRATION_LOCK_DIR"
done
ZTE_TEST_CLEANUP_FAIL_STAGE=
export ZTE_TEST_CLEANUP_FAIL_STAGE

# The installed CLI always enforces the real effective UID through /usr/bin/id.
: >"$fetch_log"
direct_raw=$(printf '%s\n' \
    '{"simcard_active_slot_temp":"0","mc_modem_main_state":"connected","network_provider_fullname":"Carrier Secret","ppp_status":"ipv4_ipv6_connected"}')
direct_status=0
direct_result=$(
    ZTE_TEST_RAW="$direct_raw" ZTE_TEST_FETCH_FAIL=0 sh "$tool" probe
) || direct_status=$?
if [ "$(/usr/bin/id -u)" -eq 0 ]; then
    assert_eq 0 "$direct_status"
    assert_eq \
        '{"ok":true,"mode":"probe","active_target":"physical","modem_ready":true,"network_registered":true,"ppp_ready":true}' \
        "$direct_result"
else
    assert_failure test "$direct_status" -eq 0
    assert_eq '' "$direct_result"
    assert_eq '' "$(cat "$fetch_log")"

    # A caller-controlled library must not run before the direct CLI's
    # unoverrideable root gate.
    evil_lib=$work/evil-lib
    sentinel=$state/pre-root-library-ran
    mkdir "$evil_lib"
    printf '%s\n' \
        ": >\"\$ZTE_TEST_PRE_ROOT_SENTINEL\"" \
        'exit 0' >"$evil_lib/validation.sh"
    evil_status=0
    ZTE_SIM_CALIBRATION_LIB_DIR="$evil_lib" \
    ZTE_TEST_PRE_ROOT_SENTINEL="$sentinel" \
        sh "$tool" probe >/dev/null 2>&1 || evil_status=$?
    assert_failure test "$evil_status" -eq 0
    assert_failure test -e "$sentinel"
fi

cleanup
trap - EXIT HUP INT TERM
finish
