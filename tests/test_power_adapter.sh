#!/bin/sh
# shellcheck disable=SC2317,SC2329
set -eu

TEST_NAME=test_power_adapter
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
power_adapter=$lib/power-adapter.sh
if [ ! -f "$power_adapter" ]; then
    fail 'power adapter library must exist'
    finish
fi
. "$lib/validation.sh"
. "$lib/json.sh"
# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/power-adapter.sh
. "$power_adapter"

work=$(mktemp -d /tmp/zte-test-power-adapter.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
record=$work/power.json

for backend in unconfigured mock dry-run hardware; do
    assert_success zte_power_backend_valid "$backend"
done
for backend in '' gpio usb-authorize '../mock'; do
    assert_failure zte_power_backend_valid "$backend"
done
for action in ON OFF KEEP; do
    assert_success zte_power_action_valid "$action"
done
for action in '' on RESET '../OFF'; do
    assert_failure zte_power_action_valid "$action"
done
for reason in \
    battery_low battery_high manual_full pre_departure fail_safe disabled no_change
do
    assert_success zte_power_reason_valid "$reason"
done
assert_failure zte_power_reason_valid 'battery high'

assert_success zte_power_board_supported 'cudy,tr3000-v1'
assert_success zte_power_board_supported 'cudy,tr3000-v1-ubootmod'
for board in '' 'cudy,tr3000' 'cudy,tr3000-v1;reboot' '../tr3000'; do
    assert_failure zte_power_board_supported "$board"
done
assert_success zte_power_control_path_valid \
    '/sys/class/gpio/modem_power/value'
assert_success zte_power_control_path_valid \
    '/sys/bus/platform/drivers/xhci-mtk/11200000.usb'
assert_success zte_power_control_config_valid auto
assert_success zte_power_control_config_valid \
    '/sys/class/gpio/modem_power/value'
assert_success zte_power_control_config_valid \
    '/sys/bus/platform/drivers/xhci-mtk/11200000.usb'
assert_failure zte_power_control_config_valid ''
assert_eq '/sys/class/gpio/modem_power/value' \
    "$(zte_power_resolve_control_path 'cudy,tr3000-v1' auto)"
assert_eq '/sys/bus/platform/drivers/xhci-mtk/11200000.usb' \
    "$(zte_power_resolve_control_path 'cudy,tr3000-v1-ubootmod' auto)"
assert_eq '/sys/bus/platform/drivers/xhci-mtk/11200000.usb' \
    "$(zte_power_resolve_control_path \
        'cudy,tr3000-v1-ubootmod' \
        '/sys/bus/platform/drivers/xhci-mtk/11200000.usb')"
assert_failure zte_power_resolve_control_path \
    'cudy,tr3000-v1-ubootmod' '/sys/class/gpio/modem_power/value'
for path in \
    '' '/sys/class/gpio/modem_power/direction' \
    '/sys/bus/platform/drivers/xhci-mtk/11200000.usb/driver' \
    '/sys/class/gpio/modem_power/value/../direction' "$work/value"
do
    assert_failure zte_power_control_path_valid "$path"
done
assert_success zte_power_board_control_supported \
    'cudy,tr3000-v1' '/sys/class/gpio/modem_power/value'
assert_success zte_power_board_control_supported \
    'cudy,tr3000-v1-ubootmod' \
    '/sys/bus/platform/drivers/xhci-mtk/11200000.usb'
assert_failure zte_power_board_control_supported \
    'cudy,tr3000-v1' '/sys/bus/platform/drivers/xhci-mtk/11200000.usb'
assert_failure zte_power_board_control_supported \
    'cudy,tr3000-v1-ubootmod' '/sys/class/gpio/modem_power/value'
assert_eq '/sys/class/gpio/modem_power/value' \
    "$(zte_power_default_control_path 'cudy,tr3000-v1')"
assert_eq '/sys/bus/platform/drivers/xhci-mtk/11200000.usb' \
    "$(zte_power_default_control_path 'cudy,tr3000-v1-ubootmod')"
assert_failure zte_power_default_control_path 'cudy,tr3000-v2'
assert_success zte_power_calibrated_flag_valid 0
assert_success zte_power_calibrated_flag_valid 1
assert_failure zte_power_calibrated_flag_valid ''
assert_failure zte_power_calibrated_flag_valid 2
assert_eq \
    'hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value' \
    "$(zte_power_profile_id hardware 1 1 cudy,tr3000-v1 \
        /sys/class/gpio/modem_power/value)"
assert_eq 'mock|0|0||' \
    "$(zte_power_profile_id mock 0 0 ignored-board ignored-path)"

mock_result=$(zte_power_apply mock ON battery_low "$record")
assert_eq \
    '{"backend":"mock","action":"ON","executed":true,"reason":"battery_low"}' \
    "$mock_result"
assert_eq "$mock_result" "$(cat "$record")"
timestamped_mock=$(zte_power_apply \
    mock ON battery_low "$record" ignored-path 0 ignored-board 0 1722345678)
assert_eq \
    '{"backend":"mock","action":"ON","executed":true,"reason":"battery_low","outcome":"succeeded","updated":1722345678,"profile":"mock|0|0||"}' \
    "$timestamped_mock"
assert_eq 600 "$(test_file_mode "$record")"

dry_run_result=$(zte_power_apply dry-run OFF battery_high "$record")
assert_eq \
    '{"backend":"dry-run","action":"OFF","executed":false,"reason":"battery_high"}' \
    "$dry_run_result"
assert_eq "$dry_run_result" "$(cat "$record")"

keep_result=$(zte_power_apply hardware KEEP no_change "$record")
assert_eq \
    '{"backend":"hardware","action":"KEEP","executed":false,"reason":"no_change"}' \
    "$keep_result"
assert_eq "$keep_result" "$(cat "$record")"

assert_failure zte_power_apply hardware ON battery_low "$record"
assert_eq "$keep_result" "$(cat "$record")"

# Hardware writes are accepted only for the exact calibrated TR3000 export.
# Override the I/O boundary so this behavior test never touches host sysfs.
hardware_state=$work/hardware-state
hardware_calls=$work/hardware-calls
printf '1\n' >"$hardware_state"
: >"$hardware_calls"
zte_power_sysfs_write() {
    printf '%s:%s\n' "$1" "$2" >>"$hardware_calls"
    printf '%s\n' "$2" >"$hardware_state"
}
zte_power_sysfs_read() {
    cat "$hardware_state"
}

run_hardware_audit_failure() (
    zte_power_write_record() { return 1; }
    set +e
    _audit_output=$(zte_power_apply \
        hardware "$1" "$2" "$record" \
        '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1' 1 \
        1722345678)
    _audit_status=$?
    set -e
    printf '%s\n%s\n' "$_audit_status" "$_audit_output"
)

assert_eq \
    '2
{"backend":"hardware","action":"OFF","executed":true,"reason":"battery_high","outcome":"succeeded","updated":1722345678,"profile":"hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value"}' \
    "$(run_hardware_audit_failure OFF battery_high)"
assert_eq 0 "$(cat "$hardware_state")"
assert_eq \
    '2
{"backend":"hardware","action":"ON","executed":true,"reason":"battery_low","outcome":"succeeded","updated":1722345678,"profile":"hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value"}' \
    "$(run_hardware_audit_failure ON battery_low)"
assert_eq 1 "$(cat "$hardware_state")"

assert_eq ON "$(zte_power_observed_state \
    '/sys/class/gpio/modem_power/value')"
printf '0\n' >"$hardware_state"
assert_eq OFF "$(zte_power_observed_state \
    '/sys/class/gpio/modem_power/value')"
printf '1\n' >"$hardware_state"

hardware_off_result=$(zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1' 1)
assert_eq \
    '{"backend":"hardware","action":"OFF","executed":true,"reason":"battery_high"}' \
    "$hardware_off_result"
assert_eq \
    '/sys/class/gpio/modem_power/value:0' \
    "$(tail -n 1 "$hardware_calls")"
assert_eq 0 "$(cat "$hardware_state")"

hardware_on_result=$(zte_power_apply \
    hardware ON fail_safe "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1' 0)
assert_eq \
    '{"backend":"hardware","action":"ON","executed":true,"reason":"fail_safe"}' \
    "$hardware_on_result"
assert_eq \
    '/sys/class/gpio/modem_power/value:1' \
    "$(tail -n 1 "$hardware_calls")"
assert_eq 1 "$(cat "$hardware_state")"

# Official OpenWrt uses the xHCI driver's bind state as the fixed regulator
# control boundary. Override that boundary so the test cannot affect host USB.
xhci_path=/sys/bus/platform/drivers/xhci-mtk/11200000.usb
xhci_state=$work/xhci-state
xhci_supply_state=$work/xhci-supply-state
xhci_calls=$work/xhci-calls
topology=$work/topology
controller=$topology/11200000.usb
target_usb=$controller/usb1/1-1
target_interface=$target_usb/1-1:1.0
topology_netdev=$topology/netdev
mkdir -p "$target_interface" "$topology_netdev"
ln -s "$target_interface" "$topology_netdev/device"
ZTE_POWER_CONTROLLER_DEVICE_PATH=$controller
ZTE_POWER_NETDEV_PATH=$topology_netdev
export ZTE_POWER_CONTROLLER_DEVICE_PATH ZTE_POWER_NETDEV_PATH
assert_success zte_power_controller_topology_safe \
    "$xhci_path" "$ZTE_POWER_NETDEV_PATH"
printf '1\n' >"$xhci_state"
printf '1\n' >"$xhci_supply_state"
: >"$xhci_calls"
zte_power_driver_state() {
    cat "$xhci_state"
}
zte_power_supply_read() {
    cat "$xhci_supply_state"
}
zte_power_driver_write() {
    printf '%s:%s\n' "$1" "$2" >>"$xhci_calls"
    case $1 in
        */unbind)
            printf '0\n' >"$xhci_state"
            printf '0\n' >"$xhci_supply_state"
            ;;
        */bind)
            printf '1\n' >"$xhci_state"
            printf '1\n' >"$xhci_supply_state"
            ;;
        *) return 1 ;;
    esac
}

xhci_off_result=$(zte_power_apply \
    hardware OFF battery_high "$record" \
    "$xhci_path" 1 'cudy,tr3000-v1-ubootmod' 1)
assert_eq \
    '{"backend":"hardware","action":"OFF","executed":true,"reason":"battery_high"}' \
    "$xhci_off_result"
assert_eq \
    '/sys/bus/platform/drivers/xhci-mtk/unbind:11200000.usb' \
    "$(tail -n 1 "$xhci_calls")"
assert_eq 0 "$(cat "$xhci_state")"

# An already detached and unpowered controller is idempotently OFF even
# though its controller and netdev sysfs nodes no longer exist.
mv "$topology" "$work/topology-off"
: >"$xhci_calls"
assert_success zte_power_hardware_apply OFF "$xhci_path"
assert_eq '' "$(cat "$xhci_calls")"
mv "$work/topology-off" "$topology"

xhci_on_result=$(zte_power_apply \
    hardware ON fail_safe "$record" \
    "$xhci_path" 1 'cudy,tr3000-v1-ubootmod' 0)
assert_eq \
    '{"backend":"hardware","action":"ON","executed":true,"reason":"fail_safe"}' \
    "$xhci_on_result"
assert_eq \
    '/sys/bus/platform/drivers/xhci-mtk/bind:11200000.usb' \
    "$(tail -n 1 "$xhci_calls")"
assert_eq 1 "$(cat "$xhci_state")"

# Runtime topology changes invalidate the old calibration. Every later xHCI
# OFF must fail before unbind when another USB device shares the controller.
mkdir -p "$controller/usb2/2-1"
: >"$xhci_calls"
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    "$xhci_path" 1 'cudy,tr3000-v1-ubootmod' 1
assert_eq '' "$(cat "$xhci_calls")"
assert_eq 1 "$(cat "$xhci_state")"
rm -rf "$controller/usb2"

: >"$xhci_calls"
assert_success zte_power_hardware_apply ON "$xhci_path"
assert_eq '' "$(cat "$xhci_calls")"
printf '0\n' >"$xhci_state"
printf '0\n' >"$xhci_supply_state"
assert_success zte_power_hardware_apply OFF "$xhci_path"
assert_eq '' "$(cat "$xhci_calls")"
printf '1\n' >"$xhci_state"
printf '1\n' >"$xhci_supply_state"

# A controller/regulator split-brain is repaired by cycling the fixed xHCI
# profile in the requested direction.
: >"$xhci_calls"
printf '0\n' >"$xhci_supply_state"
rm -rf "$target_usb" "$topology_netdev"
unset ZTE_POWER_NETDEV_PATH
assert_success zte_power_hardware_apply ON "$xhci_path"
assert_eq \
    "/sys/bus/platform/drivers/xhci-mtk/unbind:11200000.usb
/sys/bus/platform/drivers/xhci-mtk/bind:11200000.usb" \
    "$(cat "$xhci_calls")"
mkdir -p "$target_interface" "$topology_netdev"
ln -s "$target_interface" "$topology_netdev/device"
ZTE_POWER_NETDEV_PATH=$topology_netdev
export ZTE_POWER_NETDEV_PATH
: >"$xhci_calls"
printf '0\n' >"$xhci_state"
printf '1\n' >"$xhci_supply_state"
mv "$topology" "$work/topology-off"
assert_failure zte_power_hardware_apply OFF "$xhci_path"
assert_eq '' "$(cat "$xhci_calls")"
mv "$work/topology-off" "$topology"
printf '1\n' >"$xhci_state"
printf '1\n' >"$xhci_supply_state"

# A detached controller is not accepted as power-off unless the fixed
# usb-vbus regulator also reports disabled.
zte_power_driver_write() {
    printf '%s:%s\n' "$1" "$2" >>"$xhci_calls"
    case $1 in
        */unbind) printf '0\n' >"$xhci_state" ;;
        */bind) printf '1\n' >"$xhci_state" ;;
        *) return 1 ;;
    esac
}
assert_failure zte_power_hardware_apply OFF "$xhci_path"
printf '1\n' >"$xhci_state"
: >"$xhci_calls"

assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    "$xhci_path" 1 'cudy,tr3000-v1' 1
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' \
    1 'cudy,tr3000-v1-ubootmod' 1
assert_eq "$xhci_on_result" "$(cat "$record")"

assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 0 'cudy,tr3000-v1'
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1' 0
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v2' 1
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    "$work/value" 1 'cudy,tr3000-v1' 1
assert_eq "$hardware_on_result" "$(cat "$record")"

zte_power_sysfs_read() {
    printf '1\n'
}
assert_failure zte_power_apply \
    hardware OFF battery_high "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1' 1
assert_eq "$hardware_on_result" "$(cat "$record")"

zte_power_sysfs_write() {
    return 1
}
zte_power_sysfs_read() {
    printf '0\n'
}
assert_failure zte_power_apply \
    hardware ON fail_safe "$record" \
    '/sys/class/gpio/modem_power/value' 1 'cudy,tr3000-v1'
assert_eq "$hardware_on_result" "$(cat "$record")"

assert_failure zte_power_apply unconfigured OFF battery_high "$record"
assert_failure zte_power_apply dry-run RESET battery_high "$record"
assert_failure zte_power_apply dry-run OFF 'battery high' "$record"

zte_power_hardware_read() { printf '%s\n' 1; }
zte_power_supply_read() { printf '%s\n' 0; }
assert_eq UNKNOWN "$(zte_power_observed_state \
    '/sys/bus/platform/drivers/xhci-mtk/11200000.usb')"
zte_power_hardware_read() { return 1; }
zte_power_supply_read() { return 1; }
assert_eq UNKNOWN "$(zte_power_observed_state \
    '/sys/bus/platform/drivers/xhci-mtk/11200000.usb')"

finish
