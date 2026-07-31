#!/bin/sh

zte_power_backend_valid() {
	case ${1-} in
		unconfigured|mock|dry-run|hardware) return 0 ;;
		*) return 1 ;;
	esac
}

zte_power_action_valid() {
	case ${1-} in
		ON|OFF|KEEP) return 0 ;;
		*) return 1 ;;
	esac
}

zte_power_reason_valid() {
	case ${1-} in
		battery_low|battery_high|manual_full|pre_departure|fail_safe|\
disabled|no_change)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

zte_power_board_supported() {
	case ${1-} in
		cudy,tr3000-v1|cudy,tr3000-v1-ubootmod) return 0 ;;
		*) return 1 ;;
	esac
}

zte_power_control_path_valid() {
	case ${1-} in
		/sys/class/gpio/modem_power/value|\
/sys/bus/platform/drivers/xhci-mtk/11200000.usb)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

zte_power_control_config_valid() {
	[ "${1-}" = auto ] || zte_power_control_path_valid "${1-}"
}

zte_power_board_control_supported() {
	case ${1-}:${2-} in
		cudy,tr3000-v1:/sys/class/gpio/modem_power/value|\
cudy,tr3000-v1-ubootmod:/sys/bus/platform/drivers/xhci-mtk/11200000.usb)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

zte_power_default_control_path() {
	case ${1-} in
		cudy,tr3000-v1)
			printf '%s\n' /sys/class/gpio/modem_power/value
			;;
		cudy,tr3000-v1-ubootmod)
			printf '%s\n' \
				/sys/bus/platform/drivers/xhci-mtk/11200000.usb
			;;
		*)
			return 1
			;;
	esac
}

zte_power_resolve_control_path() {
	_zte_power_resolve_board=$1
	_zte_power_resolve_config=$2
	if [ "$_zte_power_resolve_config" = auto ]; then
		zte_power_default_control_path "$_zte_power_resolve_board"
		return
	fi
	zte_power_board_control_supported \
		"$_zte_power_resolve_board" "$_zte_power_resolve_config" ||
		return 1
	printf '%s\n' "$_zte_power_resolve_config"
}

zte_power_calibrated_flag_valid() {
	case ${1-} in
		0|1) return 0 ;;
		*) return 1 ;;
	esac
}

zte_power_profile_id() {
	_zte_power_profile_backend=${1-}
	_zte_power_profile_calibrated=${2-0}
	_zte_power_profile_write=${3-0}
	_zte_power_profile_board=${4-}
	_zte_power_profile_path=${5-}
	zte_power_backend_valid "$_zte_power_profile_backend" || return 1
	zte_power_calibrated_flag_valid \
		"$_zte_power_profile_calibrated" || return 1
	zte_power_calibrated_flag_valid "$_zte_power_profile_write" || return 1
	case $_zte_power_profile_backend in
		unconfigured|mock)
			_zte_power_profile_board=''
			_zte_power_profile_path=''
			;;
	esac
	printf '%s|%s|%s|%s|%s\n' \
		"$_zte_power_profile_backend" "$_zte_power_profile_calibrated" \
		"$_zte_power_profile_write" "$_zte_power_profile_board" \
		"$_zte_power_profile_path"
}

zte_power_sysfs_write() {
	_zte_power_sysfs_path=$1
	_zte_power_sysfs_value=$2
	[ -e "$_zte_power_sysfs_path" ] &&
		[ -w "$_zte_power_sysfs_path" ] || return 1
	printf '%s\n' "$_zte_power_sysfs_value" >"$_zte_power_sysfs_path"
}

zte_power_sysfs_read() {
	_zte_power_sysfs_path=$1
	[ -r "$_zte_power_sysfs_path" ] || return 1
	cat "$_zte_power_sysfs_path"
}

zte_power_driver_state() {
	_zte_power_driver_path=$1
	_zte_power_driver_dir=${_zte_power_driver_path%/*}
	[ -d "$_zte_power_driver_dir" ] || return 1
	if [ -L "$_zte_power_driver_path" ]; then
		printf '%s\n' 1
	else
		printf '%s\n' 0
	fi
}

zte_power_canonical_dir() {
	[ -d "$1" ] || return 1
	(
		cd "$1" 2>/dev/null || exit 1
		pwd -P
	)
}

zte_power_usb_tree_safe() (
	_zte_power_tree_root=$1
	_zte_power_tree_target=$2
	for _zte_power_tree_entry in "$_zte_power_tree_root"/*; do
		[ -d "$_zte_power_tree_entry" ] || continue
		[ ! -L "$_zte_power_tree_entry" ] || continue
		_zte_power_tree_name=${_zte_power_tree_entry##*/}
		case $_zte_power_tree_name in
			*:*) ;;
			[0-9]*-[0-9]*)
				case $_zte_power_tree_target/ in
					"$_zte_power_tree_entry"/*) ;;
					*) return 1 ;;
				esac
				;;
		esac
		zte_power_usb_tree_safe \
			"$_zte_power_tree_entry" "$_zte_power_tree_target" || return 1
	done
)

zte_power_usb_tree_empty() (
	_zte_power_tree_root=$1
	for _zte_power_tree_entry in "$_zte_power_tree_root"/*; do
		[ -d "$_zte_power_tree_entry" ] || continue
		[ ! -L "$_zte_power_tree_entry" ] || continue
		_zte_power_tree_name=${_zte_power_tree_entry##*/}
		case $_zte_power_tree_name in
			*:*) ;;
			[0-9]*-[0-9]*) return 1 ;;
		esac
		zte_power_usb_tree_empty "$_zte_power_tree_entry" || return 1
	done
)

zte_power_controller_topology_safe() {
	_zte_power_topology_control=$1
	_zte_power_topology_netdev=${2-}
	[ "$_zte_power_topology_control" = \
		/sys/bus/platform/drivers/xhci-mtk/11200000.usb ] || return 0
	[ -n "$_zte_power_topology_netdev" ] || return 1
	_zte_power_topology_controller=${ZTE_POWER_CONTROLLER_DEVICE_PATH:-}
	if [ -z "$_zte_power_topology_controller" ]; then
		_zte_power_topology_controller=$(zte_power_canonical_dir \
			"$_zte_power_topology_control") || return 1
	else
		_zte_power_topology_controller=$(zte_power_canonical_dir \
			"$_zte_power_topology_controller") || return 1
	fi
	_zte_power_topology_target=$(zte_power_canonical_dir \
		"$_zte_power_topology_netdev/device") || return 1
	case $_zte_power_topology_target/ in
		"$_zte_power_topology_controller"/*) ;;
		*) return 1 ;;
	esac
	zte_power_usb_tree_safe \
		"$_zte_power_topology_controller" "$_zte_power_topology_target"
}

zte_power_controller_rebind_safe() {
	_zte_power_rebind_control=$1
	_zte_power_rebind_netdev=${2-}
	[ "$_zte_power_rebind_control" = \
		/sys/bus/platform/drivers/xhci-mtk/11200000.usb ] || return 0
	if [ -n "$_zte_power_rebind_netdev" ] &&
		[ -d "$_zte_power_rebind_netdev/device" ]; then
		zte_power_controller_topology_safe \
			"$_zte_power_rebind_control" "$_zte_power_rebind_netdev"
		return
	fi
	_zte_power_rebind_controller=${ZTE_POWER_CONTROLLER_DEVICE_PATH:-}
	if [ -z "$_zte_power_rebind_controller" ]; then
		_zte_power_rebind_controller=$(zte_power_canonical_dir \
			"$_zte_power_rebind_control") || return 1
	else
		_zte_power_rebind_controller=$(zte_power_canonical_dir \
			"$_zte_power_rebind_controller") || return 1
	fi
	zte_power_usb_tree_empty "$_zte_power_rebind_controller"
}

zte_power_driver_write() {
	_zte_power_driver_control=$1
	_zte_power_driver_device=$2
	[ "$_zte_power_driver_device" = 11200000.usb ] || return 1
	case $_zte_power_driver_control in
		/sys/bus/platform/drivers/xhci-mtk/bind|\
/sys/bus/platform/drivers/xhci-mtk/unbind) ;;
		*) return 1 ;;
	esac
	[ -w "$_zte_power_driver_control" ] || return 1
	printf '%s' "$_zte_power_driver_device" >"$_zte_power_driver_control"
}

zte_power_hardware_read() {
	_zte_power_hardware_path=$1
	case $_zte_power_hardware_path in
		/sys/class/gpio/modem_power/value)
			zte_power_sysfs_read "$_zte_power_hardware_path"
			;;
		/sys/bus/platform/drivers/xhci-mtk/11200000.usb)
			zte_power_driver_state "$_zte_power_hardware_path"
			;;
		*)
			return 1
			;;
	esac
}

zte_power_supply_read() {
	_zte_power_supply_path=$1
	case $_zte_power_supply_path in
		/sys/class/gpio/modem_power/value)
			zte_power_hardware_read "$_zte_power_supply_path"
			;;
		/sys/bus/platform/drivers/xhci-mtk/11200000.usb)
			_zte_power_regulator_root=\
${ZTE_POWER_REGULATOR_ROOT:-/sys/class/regulator}
			for _zte_power_regulator in \
				"$_zte_power_regulator_root"/*; do
				[ -r "$_zte_power_regulator/name" ] || continue
				[ "$(cat "$_zte_power_regulator/name")" = usb-vbus ] ||
					continue
				[ -r "$_zte_power_regulator/state" ] || return 1
				case $(cat "$_zte_power_regulator/state") in
					enabled) printf '%s\n' 1 ;;
					disabled) printf '%s\n' 0 ;;
					*) return 1 ;;
				esac
				return
			done
			return 1
			;;
		*)
			return 1
			;;
	esac
}

zte_power_observed_state() {
	_zte_power_observed_path=$1
	_zte_power_observed_control=$(
		zte_power_hardware_read "$_zte_power_observed_path" 2>/dev/null
	) || _zte_power_observed_control=''
	_zte_power_observed_supply=$(
		zte_power_supply_read "$_zte_power_observed_path" 2>/dev/null
	) || _zte_power_observed_supply=''
	case $_zte_power_observed_control:$_zte_power_observed_supply in
		1:1) printf '%s\n' ON ;;
		0:0) printf '%s\n' OFF ;;
		*) printf '%s\n' UNKNOWN ;;
	esac
}

zte_power_hardware_apply() {
	_zte_power_hardware_action=$1
	_zte_power_hardware_path=$2

	case $_zte_power_hardware_action in
		ON) _zte_power_expected_value=1 ;;
		OFF) _zte_power_expected_value=0 ;;
		*) return 1 ;;
	esac
	_zte_power_current_value=$(
		zte_power_hardware_read "$_zte_power_hardware_path" 2>/dev/null
	) || _zte_power_current_value=''
	if [ "$_zte_power_current_value" = "$_zte_power_expected_value" ]; then
		_zte_power_current_supply=$(
			zte_power_supply_read "$_zte_power_hardware_path" 2>/dev/null
		) || return 1
		if [ "$_zte_power_current_supply" = \
			"$_zte_power_expected_value" ]; then
			return 0
		fi
		[ "$_zte_power_hardware_path" = \
			/sys/bus/platform/drivers/xhci-mtk/11200000.usb ] ||
			return 1
		if [ "$_zte_power_hardware_action" = ON ]; then
			zte_power_controller_rebind_safe \
				"$_zte_power_hardware_path" \
				"${ZTE_POWER_NETDEV_PATH:-}" || return 1
			zte_power_driver_write \
				/sys/bus/platform/drivers/xhci-mtk/unbind \
				11200000.usb || return 1
			zte_power_driver_write \
				/sys/bus/platform/drivers/xhci-mtk/bind \
				11200000.usb || return 1
		else
			return 1
		fi
	fi

	if [ "$_zte_power_current_value" != "$_zte_power_expected_value" ]; then
		case $_zte_power_hardware_path in
		/sys/class/gpio/modem_power/value)
			zte_power_sysfs_write \
				"$_zte_power_hardware_path" \
				"$_zte_power_expected_value" ||
				return 1
			;;
		/sys/bus/platform/drivers/xhci-mtk/11200000.usb)
			if [ "$_zte_power_hardware_action" = ON ]; then
				_zte_power_driver_control=\
/sys/bus/platform/drivers/xhci-mtk/bind
			else
				_zte_power_driver_control=\
/sys/bus/platform/drivers/xhci-mtk/unbind
				zte_power_controller_topology_safe \
					"$_zte_power_hardware_path" \
					"${ZTE_POWER_NETDEV_PATH:-}" || return 1
			fi
			zte_power_driver_write \
				"$_zte_power_driver_control" 11200000.usb ||
				return 1
			;;
		*)
			return 1
			;;
		esac
	fi
	_zte_power_actual_value=$(
		zte_power_hardware_read "$_zte_power_hardware_path"
	) || return 1
	[ "$_zte_power_actual_value" = "$_zte_power_expected_value" ] ||
		return 1
	_zte_power_actual_supply=$(
		zte_power_supply_read "$_zte_power_hardware_path"
	) || return 1
	[ "$_zte_power_actual_supply" = "$_zte_power_expected_value" ]
}

zte_power_write_record() {
	_zte_power_record_file=$1
	_zte_power_record_json=$2
	[ -n "$_zte_power_record_file" ] && [ "$_zte_power_record_file" != / ] ||
		return 1

	_zte_power_record_tmp=$_zte_power_record_file.tmp.$$
	umask 077
	printf '%s\n' "$_zte_power_record_json" >"$_zte_power_record_tmp" ||
		return 1
	chmod 600 "$_zte_power_record_tmp" || return 1
	mv "$_zte_power_record_tmp" "$_zte_power_record_file"
}

zte_power_apply() {
	_zte_power_backend=$1
	_zte_power_action=$2
	_zte_power_reason=$3
	_zte_power_record_file=$4
	_zte_power_control_path=${5-}
	_zte_power_calibrated=${6-0}
	_zte_power_board=${7-}
	_zte_power_write_authorized=${8-0}
	_zte_power_updated=${9-}

	zte_power_backend_valid "$_zte_power_backend" || return 1
	zte_power_action_valid "$_zte_power_action" || return 1
	zte_power_reason_valid "$_zte_power_reason" || return 1

	if [ "$_zte_power_action" != KEEP ]; then
		case $_zte_power_backend in
			mock) _zte_power_executed=true ;;
			dry-run) _zte_power_executed=false ;;
			hardware)
				zte_power_calibrated_flag_valid \
					"$_zte_power_write_authorized" ||
					return 1
				if [ "$_zte_power_action" = OFF ] &&
					[ "$_zte_power_write_authorized" != 1 ]; then
					return 1
				fi
				zte_power_calibrated_flag_valid \
					"$_zte_power_calibrated" ||
					return 1
				[ "$_zte_power_calibrated" = 1 ] || return 1
				zte_power_board_supported "$_zte_power_board" ||
					return 1
				zte_power_board_control_supported \
					"$_zte_power_board" \
					"$_zte_power_control_path" ||
					return 1
				zte_power_hardware_apply \
					"$_zte_power_action" \
					"$_zte_power_control_path" ||
					return 1
				_zte_power_executed=true
				;;
			unconfigured) return 1 ;;
		esac
	else
		_zte_power_executed=false
	fi

	if [ -n "$_zte_power_updated" ]; then
		zte_is_uint "$_zte_power_updated" &&
			[ "$_zte_power_updated" -gt 0 ] || return 1
		_zte_power_profile=$(zte_power_profile_id \
			"$_zte_power_backend" "$_zte_power_calibrated" \
			"$_zte_power_write_authorized" "$_zte_power_board" \
			"$_zte_power_control_path") || return 1
		_zte_power_result=$(printf \
			'{"backend":"%s","action":"%s","executed":%s,"reason":"%s","outcome":"succeeded","updated":%s,"profile":"%s"}' \
			"$_zte_power_backend" "$_zte_power_action" \
			"$_zte_power_executed" "$_zte_power_reason" \
			"$_zte_power_updated" "$(zte_json_escape "$_zte_power_profile")")
	else
		_zte_power_result=$(printf \
			'{"backend":"%s","action":"%s","executed":%s,"reason":"%s"}' \
			"$_zte_power_backend" "$_zte_power_action" \
			"$_zte_power_executed" "$_zte_power_reason")
	fi
	if ! zte_power_write_record \
		"$_zte_power_record_file" "$_zte_power_result"; then
		printf '%s\n' "$_zte_power_result"
		return 2
	fi
	printf '%s\n' "$_zte_power_result"
}
