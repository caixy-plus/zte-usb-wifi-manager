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
	[ "${1-}" = 'cudy,tr3000-v1' ]
}

zte_power_control_path_valid() {
	[ "${1-}" = '/sys/class/gpio/modem_power/value' ]
}

zte_power_calibrated_flag_valid() {
	case ${1-} in
		0|1) return 0 ;;
		*) return 1 ;;
	esac
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

zte_power_hardware_apply() {
	_zte_power_hardware_action=$1
	_zte_power_hardware_path=$2

	case $_zte_power_hardware_action in
		ON) _zte_power_expected_value=1 ;;
		OFF) _zte_power_expected_value=0 ;;
		*) return 1 ;;
	esac

	zte_power_sysfs_write \
		"$_zte_power_hardware_path" "$_zte_power_expected_value" ||
		return 1
	_zte_power_actual_value=$(
		zte_power_sysfs_read "$_zte_power_hardware_path"
	) || return 1
	[ "$_zte_power_actual_value" = "$_zte_power_expected_value" ]
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
				zte_power_control_path_valid \
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

	_zte_power_result=$(printf \
		'{"backend":"%s","action":"%s","executed":%s,"reason":"%s"}' \
		"$_zte_power_backend" "$_zte_power_action" \
		"$_zte_power_executed" "$_zte_power_reason")
	zte_power_write_record "$_zte_power_record_file" "$_zte_power_result" ||
		return 1
	printf '%s\n' "$_zte_power_result"
}
