#!/bin/sh
# shellcheck disable=SC2317,SC2329
set -eu

TEST_NAME=test_power_calibration
. ./tests/testlib.sh

tool=./package/zte-usb-wifi-manager/files/usr/libexec/zte-usb-power-calibrate
if [ ! -f "$tool" ]; then
    fail 'power calibration tool must exist'
    finish
fi

work=$(mktemp -d /tmp/zte-test-power-calibration.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
lib=$work/lib
bin=$work/bin
state=$work/state
mkdir -p "$lib" "$bin" "$state/netdev"
printf '%s\n' 'cudy,tr3000-v1' >"$state/board"
printf '1\n' >"$state/power"
printf '%s\n' running >"$state/manager-state"
: >"$state/service-calls"
ZTE_TEST_MANAGER_STATE=$state/manager-state
ZTE_TEST_MANAGER_STUCK=0
export ZTE_TEST_MANAGER_STATE ZTE_TEST_MANAGER_STUCK

cat >"$lib/validation.sh" <<'EOF'
zte_validate_netdev() {
    [ "$1" = eth2 ]
}
zte_validate_host() {
    [ "$1" = 192.168.0.1 ]
}
EOF
cat >"$lib/power-adapter.sh" <<'EOF'
zte_power_board_supported() {
    case $1 in
        cudy,tr3000-v1|cudy,tr3000-v1-ubootmod) return 0 ;;
        *) return 1 ;;
    esac
}
zte_power_control_path_valid() {
    [ "$1" = "$ZTE_CALIBRATION_CONTROL_PATH" ]
}
zte_power_board_control_supported() {
    zte_power_board_supported "$1" &&
        [ "$2" = "$ZTE_CALIBRATION_CONTROL_PATH" ]
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
    [ "${ZTE_TEST_SUPPLY_READ_FAIL:-0}" = 0 ] || return 1
    if [ -n "${ZTE_TEST_SUPPLY_STATE:-}" ]; then
        printf '%s\n' "$ZTE_TEST_SUPPLY_STATE"
    else
        cat "$1"
    fi
}
zte_power_hardware_apply() {
    if [ "$1" = OFF ] &&
        [ -n "${ZTE_POWER_CONTROLLER_DEVICE_PATH:-}" ]; then
        zte_power_controller_topology_safe \
            "$2" "${ZTE_POWER_NETDEV_PATH:-}" || return 1
    fi
    case $1 in
        OFF)
            printf '0\n' >"$2"
            rmdir "$ZTE_CALIBRATION_NETDEV_PATH"
            [ "${ZTE_TEST_FAIL_POWER_ACTION:-}" != OFF ]
            ;;
        ON)
            [ "${ZTE_TEST_FAIL_POWER_ACTION:-}" != ON ] || return 1
            printf '1\n' >"$2"
            mkdir -p "$ZTE_CALIBRATION_NETDEV_PATH"
            ;;
        *) return 1 ;;
    esac
}
zte_power_controller_topology_safe() {
    [ -n "${ZTE_POWER_CONTROLLER_DEVICE_PATH:-}" ] || return 0
    controller=$(cd "$ZTE_POWER_CONTROLLER_DEVICE_PATH" 2>/dev/null && pwd -P) ||
        return 1
    target=$(cd "$2/device" 2>/dev/null && pwd -P) || return 1
    case $target/ in
        "$controller"/*) ;;
        *) return 1 ;;
    esac
    [ ! -d "$controller/usb2/2-1" ]
}
EOF
cat >"$lib/recovery-inhibit.sh" <<'EOF'
:
EOF
cat >"$lib/recovery-adapter.sh" <<'EOF'
zte_recovery_service_available() {
    [ "${ZTE_TEST_RECOVERY_UNAVAILABLE:-0}" = 0 ]
}
zte_recovery_prepare_off() {
    printf '%s\n' stop >>"$ZTE_TEST_SERVICE_CALLS"
    : >"$1"
    [ "${ZTE_TEST_FAIL_RECOVERY_PREPARE:-0}" = 0 ]
}
zte_recovery_finish_on() {
    printf '%s\n' start >>"$ZTE_TEST_SERVICE_CALLS"
    rm -f "$1"
    [ "${ZTE_TEST_FAIL_RECOVERY_FINISH:-0}" = 0 ]
}
EOF
cat >"$lib/netifd-adapter.sh" <<'EOF'
zte_netifd_route_uses_device() {
    [ "${ZTE_TEST_ROUTE_MATCH:-1}" = 1 ] &&
        [ "$1" = 192.168.0.1 ] && [ "$2" = eth2 ]
}
EOF
cat >"$bin/sleep" <<'EOF'
#!/bin/sh
if [ "${ZTE_TEST_SIGNAL_ON_SLEEP:-0}" = 1 ]; then
    kill -HUP "$PPID"
fi
:
EOF
cat >"$bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' 1722345600
EOF
cat >"$bin/uci" <<'EOF'
#!/bin/sh
case $* in
    *zte-usb-wifi-manager.zte.netdev*) printf '%s\n' eth2 ;;
    *zte-usb-wifi-manager.zte.host*) printf '%s\n' 192.168.0.1 ;;
    *) exit 1 ;;
esac
EOF
cat >"$bin/curl" <<'EOF'
#!/bin/sh
[ "${ZTE_TEST_CURL_FAIL:-0}" = 0 ] || exit 1
case " $* " in
    *' --interface eth2 '*) ;;
    *) exit 1 ;;
esac
printf '%s\n' '{"modem_main_state":"modem_init_complete"}'
EOF
cat >"$bin/manager-service" <<'EOF'
#!/bin/sh
case $1 in
    running)
        [ "$(cat "$ZTE_TEST_MANAGER_STATE")" = running ]
        ;;
    stop)
        printf '%s\n' manager-stop >>"$ZTE_TEST_SERVICE_CALLS"
        [ "${ZTE_TEST_FAIL_MANAGER_ACTION:-}" != stop ] || exit 1
        [ "${ZTE_TEST_MANAGER_STUCK:-0}" = 1 ] ||
            printf '%s\n' stopped >"$ZTE_TEST_MANAGER_STATE"
        if [ -n "${ZTE_TEST_ADD_USB_SIBLING_ON_STOP:-}" ]; then
            mkdir -p "$ZTE_TEST_ADD_USB_SIBLING_ON_STOP"
        fi
        ;;
    start)
        printf '%s\n' manager-start >>"$ZTE_TEST_SERVICE_CALLS"
        [ "${ZTE_TEST_FAIL_MANAGER_ACTION:-}" != start ] || exit 1
        printf '%s\n' running >"$ZTE_TEST_MANAGER_STATE"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$bin/"*

calibration_call() {
    ZTE_CALIBRATION_LIB_DIR=$lib \
    ZTE_CALIBRATION_BOARD_FILE=$state/board \
    ZTE_CALIBRATION_CONTROL_PATH=$state/power \
    ZTE_CALIBRATION_NETDEV_PATH=${ZTE_TEST_CALIBRATION_NETDEV_PATH:-$state/netdev} \
    ZTE_CALIBRATION_STATE_DIR=$state/runtime \
    ZTE_CALIBRATION_LOCK_DIR=$state/lock \
    ZTE_CALIBRATION_MANAGER_SERVICE=$bin/manager-service \
    ZTE_CALIBRATION_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_CALIBRATION_OUTAGE_SECONDS=0 \
    ZTE_CALIBRATION_WAIT_ATTEMPTS=2 \
    ZTE_TEST_SERVICE_CALLS=$state/service-calls \
    PATH="$bin:$PATH" \
        sh "$tool" "$@"
}

calibration_auto_call() {
    ZTE_CALIBRATION_LIB_DIR=$lib \
    ZTE_CALIBRATION_BOARD_FILE=$state/board \
    ZTE_CALIBRATION_NETDEV_PATH=$state/netdev \
    ZTE_CALIBRATION_STATE_DIR=$state/runtime \
    ZTE_CALIBRATION_LOCK_DIR=$state/lock \
    ZTE_CALIBRATION_MANAGER_SERVICE=$bin/manager-service \
    ZTE_CALIBRATION_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_CALIBRATION_OUTAGE_SECONDS=0 \
    ZTE_CALIBRATION_WAIT_ATTEMPTS=2 \
    ZTE_TEST_DEFAULT_POWER_PATH=$state/power \
    ZTE_TEST_SERVICE_CALLS=$state/service-calls \
    PATH="$bin:$PATH" \
        sh "$tool" "$@"
}

assert_power_probe_failure() {
    expected_code=$1
    probe_status=0
    probe_output=$(calibration_call probe) || probe_status=$?
    assert_eq 1 "$probe_status"
    assert_eq \
        "{\"ok\":false,\"mode\":\"probe\",\"code\":\"$expected_code\"}" \
        "$probe_output"
}

probe_result=$(calibration_call probe)
assert_eq \
    '{"ok":true,"mode":"probe","board":"cudy,tr3000-v1","power":1,"recovery_service":true,"netdev_present":true,"device_reachable":true}' \
    "$probe_result"
assert_eq '' "$(cat "$state/service-calls")"
assert_eq "$probe_result" "$(calibration_auto_call probe)"

# The ubootmod profile unbinds the whole xHCI controller. It is safe only
# when every attached USB device on that controller is an ancestor of the
# configured U25S network interface.
topology=$state/topology
controller=$topology/11200000.usb
target_usb=$controller/usb1/1-1
target_interface=$target_usb/1-1:1.0
topology_netdev=$topology/netdev
mkdir -p "$target_interface" "$topology_netdev"
ln -s "$target_interface" "$topology_netdev/device"
printf '%s\n' 'cudy,tr3000-v1-ubootmod' >"$state/board"
topology_probe=$(ZTE_CALIBRATION_CONTROLLER_DEVICE_PATH="$controller" \
    ZTE_TEST_CALIBRATION_NETDEV_PATH="$topology_netdev" calibration_call probe)
assert_eq \
    '{"ok":true,"mode":"probe","board":"cudy,tr3000-v1-ubootmod","power":1,"recovery_service":true,"netdev_present":true,"device_reachable":true}' \
    "$topology_probe"

: >"$state/service-calls"
printf '%s\n' running >"$state/manager-state"
topology_execute_status=0
ZTE_CALIBRATION_CONTROLLER_DEVICE_PATH="$controller" \
    ZTE_TEST_CALIBRATION_NETDEV_PATH="$topology_netdev" \
    ZTE_TEST_ADD_USB_SIBLING_ON_STOP="$controller/usb2/2-1" \
    calibration_call execute I_AM_ON_SPARE_HARDWARE >/dev/null ||
    topology_execute_status=$?
assert_failure test "$topology_execute_status" -eq 0
assert_eq 1 "$(cat "$state/power")"
assert_eq \
    "manager-stop
stop
start
manager-start" \
    "$(cat "$state/service-calls")"
assert_failure test -d "$state/lock"

probe_status=0
probe_output=$(ZTE_CALIBRATION_CONTROLLER_DEVICE_PATH="$controller" \
    ZTE_TEST_CALIBRATION_NETDEV_PATH="$topology_netdev" \
    calibration_call probe) || probe_status=$?
assert_eq 1 "$probe_status"
assert_eq \
    '{"ok":false,"mode":"probe","code":"shared_usb_controller"}' \
    "$probe_output"
rm -rf "$topology"
printf '%s\n' 'cudy,tr3000-v1' >"$state/board"
unset ZTE_CALIBRATION_CONTROLLER_DEVICE_PATH
unset ZTE_TEST_CALIBRATION_NETDEV_PATH
unset ZTE_TEST_ADD_USB_SIBLING_ON_STOP
: >"$state/service-calls"

mv "$state/board" "$state/board.saved"
assert_power_probe_failure board_file_unreadable
mv "$state/board.saved" "$state/board"

printf '%s\n' unsupported,board >"$state/board"
assert_power_probe_failure unsupported_board
printf '%s\n' 'cudy,tr3000-v1' >"$state/board"

mv "$state/power" "$state/power.saved"
assert_power_probe_failure power_read_failed
mv "$state/power.saved" "$state/power"

ZTE_TEST_SUPPLY_READ_FAIL=1
export ZTE_TEST_SUPPLY_READ_FAIL
assert_power_probe_failure supply_read_failed
ZTE_TEST_SUPPLY_READ_FAIL=0
ZTE_TEST_SUPPLY_STATE=0
export ZTE_TEST_SUPPLY_STATE
assert_power_probe_failure supply_state_mismatch
ZTE_TEST_SUPPLY_STATE=

ZTE_TEST_RECOVERY_UNAVAILABLE=1
export ZTE_TEST_RECOVERY_UNAVAILABLE
assert_power_probe_failure recovery_service_unavailable
ZTE_TEST_RECOVERY_UNAVAILABLE=0

ZTE_TEST_CURL_FAIL=1
export ZTE_TEST_CURL_FAIL
assert_power_probe_failure device_unreachable
ZTE_TEST_CURL_FAIL=0

ZTE_TEST_ROUTE_MATCH=0
export ZTE_TEST_ROUTE_MATCH
assert_power_probe_failure device_route_mismatch
ZTE_TEST_ROUTE_MATCH=1
export ZTE_TEST_ROUTE_MATCH

assert_failure calibration_call execute WRONG_ACK >/dev/null 2>&1
assert_eq 1 "$(cat "$state/power")"
assert_success test -d "$state/netdev"
assert_eq '' "$(cat "$state/service-calls")"

execute_result=$(calibration_call execute I_AM_ON_SPARE_HARDWARE)
assert_eq \
    '{"ok":true,"mode":"execute","board":"cudy,tr3000-v1","off_readback":true,"netdev_disappeared":true,"on_readback":true,"netdev_restored":true,"device_reachable":true}' \
    "$execute_result"
assert_eq 1 "$(cat "$state/power")"
assert_success test -d "$state/netdev"
assert_eq \
    "manager-stop
stop
start
manager-start" \
    "$(cat "$state/service-calls")"
assert_failure test -e "$state/runtime/inhibit-recovery"
assert_failure test -d "$state/lock"

# Calibration preserves an intentionally stopped manager across success.
printf '%s\n' stopped >"$state/manager-state"
: >"$state/service-calls"
execute_result=$(calibration_call execute I_AM_ON_SPARE_HARDWARE)
assert_eq \
    '{"ok":true,"mode":"execute","board":"cudy,tr3000-v1","off_readback":true,"netdev_disappeared":true,"on_readback":true,"netdev_restored":true,"device_reachable":true}' \
    "$execute_result"
assert_eq stopped "$(cat "$state/manager-state")"
assert_eq "stop
start" "$(cat "$state/service-calls")"
assert_failure test -e "$state/runtime/manager-was-running"
printf '%s\n' running >"$state/manager-state"

# Any failure after claiming the calibration lock must restore power, restart
# the manager, clear recovery ownership, and release the lock.
: >"$state/service-calls"
assert_failure env ZTE_TEST_FAIL_MANAGER_ACTION=stop \
    ZTE_CALIBRATION_LIB_DIR="$lib" \
    ZTE_CALIBRATION_BOARD_FILE="$state/board" \
    ZTE_CALIBRATION_CONTROL_PATH="$state/power" \
    ZTE_CALIBRATION_NETDEV_PATH="$state/netdev" \
    ZTE_CALIBRATION_STATE_DIR="$state/runtime" \
    ZTE_CALIBRATION_LOCK_DIR="$state/lock" \
    ZTE_CALIBRATION_MANAGER_SERVICE="$bin/manager-service" \
    ZTE_CALIBRATION_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_CALIBRATION_OUTAGE_SECONDS=0 \
    ZTE_CALIBRATION_WAIT_ATTEMPTS=2 \
    ZTE_TEST_SERVICE_CALLS="$state/service-calls" \
    PATH="$bin:$PATH" \
    sh "$tool" execute I_AM_ON_SPARE_HARDWARE
assert_eq 1 "$(cat "$state/power")"
assert_success test -d "$state/netdev"
assert_eq \
    "manager-stop
manager-start" \
    "$(cat "$state/service-calls")"
assert_failure test -d "$state/lock"

# A successful stop command is not enough: if procd still reports the manager
# running, abort before stopping recovery or touching USB power.
: >"$state/service-calls"
ZTE_TEST_MANAGER_STUCK=1
export ZTE_TEST_MANAGER_STUCK
assert_failure calibration_call execute I_AM_ON_SPARE_HARDWARE
assert_eq 1 "$(cat "$state/power")"
assert_success test -d "$state/netdev"
assert_eq "manager-stop
manager-start" "$(cat "$state/service-calls")"
assert_failure test -e "$state/runtime/inhibit-recovery"
assert_failure test -d "$state/lock"
ZTE_TEST_MANAGER_STUCK=0
export ZTE_TEST_MANAGER_STUCK

: >"$state/service-calls"
assert_failure env ZTE_TEST_FAIL_POWER_ACTION=OFF \
    ZTE_CALIBRATION_LIB_DIR="$lib" \
    ZTE_CALIBRATION_BOARD_FILE="$state/board" \
    ZTE_CALIBRATION_CONTROL_PATH="$state/power" \
    ZTE_CALIBRATION_NETDEV_PATH="$state/netdev" \
    ZTE_CALIBRATION_STATE_DIR="$state/runtime" \
    ZTE_CALIBRATION_LOCK_DIR="$state/lock" \
    ZTE_CALIBRATION_MANAGER_SERVICE="$bin/manager-service" \
    ZTE_CALIBRATION_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_CALIBRATION_OUTAGE_SECONDS=0 \
    ZTE_CALIBRATION_WAIT_ATTEMPTS=2 \
    ZTE_TEST_SERVICE_CALLS="$state/service-calls" \
    PATH="$bin:$PATH" \
    sh "$tool" execute I_AM_ON_SPARE_HARDWARE
assert_eq 1 "$(cat "$state/power")"
assert_success test -d "$state/netdev"
assert_eq \
    "manager-stop
stop
start
manager-start" \
    "$(cat "$state/service-calls")"
assert_failure test -e "$state/runtime/inhibit-recovery"
assert_failure test -d "$state/lock"

# If ON cannot be read back, keep the manager/recovery stopped and retain the
# inhibit and lock so a later safety restore can retry without competition.
: >"$state/service-calls"
assert_failure env ZTE_TEST_FAIL_POWER_ACTION=ON \
    ZTE_CALIBRATION_LIB_DIR="$lib" \
    ZTE_CALIBRATION_BOARD_FILE="$state/board" \
    ZTE_CALIBRATION_CONTROL_PATH="$state/power" \
    ZTE_CALIBRATION_NETDEV_PATH="$state/netdev" \
    ZTE_CALIBRATION_STATE_DIR="$state/runtime" \
    ZTE_CALIBRATION_LOCK_DIR="$state/lock" \
    ZTE_CALIBRATION_MANAGER_SERVICE="$bin/manager-service" \
    ZTE_CALIBRATION_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_CALIBRATION_OUTAGE_SECONDS=0 \
    ZTE_CALIBRATION_WAIT_ATTEMPTS=2 \
    ZTE_TEST_SERVICE_CALLS="$state/service-calls" \
    PATH="$bin:$PATH" \
    sh "$tool" execute I_AM_ON_SPARE_HARDWARE
assert_eq 0 "$(cat "$state/power")"
assert_failure test -d "$state/netdev"
assert_eq \
    "manager-stop
stop" \
    "$(cat "$state/service-calls")"
assert_success test -e "$state/runtime/inhibit-recovery"
assert_success test -d "$state/lock"

recover_result=$(calibration_call recover)
assert_eq \
    '{"ok":true,"mode":"recover","power":1,"services_restored":true}' \
    "$recover_result"
assert_eq 1 "$(cat "$state/power")"
assert_success test -d "$state/netdev"
assert_eq \
    "manager-stop
stop
start
manager-start" \
    "$(cat "$state/service-calls")"
assert_failure test -e "$state/runtime/inhibit-recovery"
assert_failure test -d "$state/lock"

# Cross-process recover also preserves an originally stopped manager.
printf '%s\n' stopped >"$state/manager-state"
: >"$state/service-calls"
assert_failure env ZTE_TEST_FAIL_POWER_ACTION=ON \
    ZTE_CALIBRATION_LIB_DIR="$lib" \
    ZTE_CALIBRATION_BOARD_FILE="$state/board" \
    ZTE_CALIBRATION_CONTROL_PATH="$state/power" \
    ZTE_CALIBRATION_NETDEV_PATH="$state/netdev" \
    ZTE_CALIBRATION_STATE_DIR="$state/runtime" \
    ZTE_CALIBRATION_LOCK_DIR="$state/lock" \
    ZTE_CALIBRATION_MANAGER_SERVICE="$bin/manager-service" \
    ZTE_CALIBRATION_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_CALIBRATION_OUTAGE_SECONDS=0 \
    ZTE_CALIBRATION_WAIT_ATTEMPTS=2 \
    ZTE_TEST_SERVICE_CALLS="$state/service-calls" \
    PATH="$bin:$PATH" \
    sh "$tool" execute I_AM_ON_SPARE_HARDWARE
assert_eq 0 "$(cat "$state/runtime/manager-was-running")"
assert_eq 600 "$(test_file_mode "$state/runtime/manager-was-running")"
recover_result=$(calibration_call recover)
assert_eq \
    '{"ok":true,"mode":"recover","power":1,"services_restored":true}' \
    "$recover_result"
assert_eq stopped "$(cat "$state/manager-state")"
assert_eq "stop
start" "$(cat "$state/service-calls")"
assert_failure test -e "$state/runtime/manager-was-running"
assert_failure test -d "$state/lock"
printf '%s\n' running >"$state/manager-state"

# Legacy missing state and corrupt state both fail safe to the old behavior:
# restore power/recovery and start the manager rather than strand a lock.
for legacy_state in missing corrupt; do
    printf '%s\n' stopped >"$state/manager-state"
    printf '0\n' >"$state/power"
    rmdir "$state/netdev" 2>/dev/null || :
    mkdir -p "$state/runtime" "$state/lock"
    : >"$state/runtime/inhibit-recovery"
    if [ "$legacy_state" = corrupt ]; then
        printf '%s\n' invalid >"$state/runtime/manager-was-running"
    else
        rm -f "$state/runtime/manager-was-running"
    fi
    : >"$state/service-calls"
    legacy_result=$(calibration_call recover)
    assert_eq \
        '{"ok":true,"mode":"recover","power":1,"services_restored":true}' \
        "$legacy_result"
    assert_eq running "$(cat "$state/manager-state")"
    assert_eq "start
manager-start" "$(cat "$state/service-calls")"
    assert_failure test -d "$state/lock"
    assert_failure test -e "$state/runtime/manager-was-running"
done

: >"$state/service-calls"
assert_failure env ZTE_TEST_SIGNAL_ON_SLEEP=1 \
    ZTE_CALIBRATION_LIB_DIR="$lib" \
    ZTE_CALIBRATION_BOARD_FILE="$state/board" \
    ZTE_CALIBRATION_CONTROL_PATH="$state/power" \
    ZTE_CALIBRATION_NETDEV_PATH="$state/netdev" \
    ZTE_CALIBRATION_STATE_DIR="$state/runtime" \
    ZTE_CALIBRATION_LOCK_DIR="$state/lock" \
    ZTE_CALIBRATION_MANAGER_SERVICE="$bin/manager-service" \
    ZTE_CALIBRATION_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_CALIBRATION_OUTAGE_SECONDS=1 \
    ZTE_CALIBRATION_WAIT_ATTEMPTS=2 \
    ZTE_TEST_SERVICE_CALLS="$state/service-calls" \
    PATH="$bin:$PATH" \
    sh "$tool" execute I_AM_ON_SPARE_HARDWARE
assert_eq 1 "$(cat "$state/power")"
assert_success test -d "$state/netdev"
assert_eq \
    "manager-stop
stop
start
manager-start" \
    "$(cat "$state/service-calls")"
assert_failure test -e "$state/runtime/inhibit-recovery"
assert_failure test -d "$state/lock"

: >"$state/service-calls"
assert_failure env ZTE_TEST_FAIL_RECOVERY_PREPARE=1 \
    ZTE_CALIBRATION_LIB_DIR="$lib" \
    ZTE_CALIBRATION_BOARD_FILE="$state/board" \
    ZTE_CALIBRATION_CONTROL_PATH="$state/power" \
    ZTE_CALIBRATION_NETDEV_PATH="$state/netdev" \
    ZTE_CALIBRATION_STATE_DIR="$state/runtime" \
    ZTE_CALIBRATION_LOCK_DIR="$state/lock" \
    ZTE_CALIBRATION_MANAGER_SERVICE="$bin/manager-service" \
    ZTE_CALIBRATION_RECOVERY_SERVICE=/etc/init.d/zte-usb-recover \
    ZTE_CALIBRATION_OUTAGE_SECONDS=0 \
    ZTE_CALIBRATION_WAIT_ATTEMPTS=2 \
    ZTE_TEST_SERVICE_CALLS="$state/service-calls" \
    PATH="$bin:$PATH" \
    sh "$tool" execute I_AM_ON_SPARE_HARDWARE
assert_eq 1 "$(cat "$state/power")"
assert_success test -d "$state/netdev"
assert_eq \
    "manager-stop
stop
start
manager-start" \
    "$(cat "$state/service-calls")"
assert_failure test -e "$state/runtime/inhibit-recovery"
assert_failure test -d "$state/lock"

finish
