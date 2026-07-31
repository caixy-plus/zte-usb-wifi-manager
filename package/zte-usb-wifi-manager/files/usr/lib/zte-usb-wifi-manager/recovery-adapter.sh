#!/bin/sh

zte_recovery_service_path_valid() {
	[ "${1-}" = '/etc/init.d/zte-usb-recover' ]
}

zte_recovery_service_available() {
	_zte_recovery_service_path=$1
	zte_recovery_service_path_valid "$_zte_recovery_service_path" &&
		[ -x "$_zte_recovery_service_path" ]
}

zte_recovery_service_control() {
	_zte_recovery_service_path=$1
	_zte_recovery_service_action=$2
	zte_recovery_service_available "$_zte_recovery_service_path" ||
		return 1
	case $_zte_recovery_service_action in
		start|stop) ;;
		*) return 1 ;;
	esac
	"$_zte_recovery_service_path" "$_zte_recovery_service_action"
}

zte_recovery_service_running() {
	_zte_recovery_service_path=$1
	zte_recovery_service_available "$_zte_recovery_service_path" ||
		return 1
	"$_zte_recovery_service_path" running >/dev/null 2>&1
}

zte_recovery_prepare_off() {
	_zte_recovery_inhibit_file=$1
	_zte_recovery_inhibit_reason=$2
	_zte_recovery_inhibit_expires=$3
	_zte_recovery_inhibit_now=$4
	_zte_recovery_service_path=$5

	zte_recovery_service_path_valid "$_zte_recovery_service_path" &&
		zte_recovery_service_available "$_zte_recovery_service_path" ||
		return 1
	if zte_recovery_service_running "$_zte_recovery_service_path"; then
		_zte_recovery_restart_service=true
	else
		_zte_recovery_restart_service=false
	fi
	zte_recovery_inhibit_write \
		"$_zte_recovery_inhibit_file" "$_zte_recovery_inhibit_reason" \
		"$_zte_recovery_inhibit_expires" "$_zte_recovery_inhibit_now" \
		"$_zte_recovery_restart_service" ||
		return 1
	if [ "$_zte_recovery_restart_service" = true ]; then
		if ! zte_recovery_service_control \
			"$_zte_recovery_service_path" stop; then
			if zte_recovery_service_running \
				"$_zte_recovery_service_path"; then
				zte_recovery_inhibit_clear \
					"$_zte_recovery_inhibit_file" || :
				return 1
			fi
		fi
	fi
}

zte_recovery_finish_on() {
	_zte_recovery_inhibit_file=$1
	_zte_recovery_service_path=$2

	zte_recovery_service_path_valid "$_zte_recovery_service_path" &&
		zte_recovery_service_available "$_zte_recovery_service_path" ||
		return 1
	_zte_recovery_restart_service=$(
		zte_recovery_inhibit_restart_value \
			"$_zte_recovery_inhibit_file"
	) || return 1
	if [ "$_zte_recovery_restart_service" = true ]; then
		zte_recovery_service_control "$_zte_recovery_service_path" start ||
			return 1
		zte_recovery_service_running "$_zte_recovery_service_path" ||
			return 1
	fi
	zte_recovery_inhibit_clear "$_zte_recovery_inhibit_file"
}

zte_recovery_reconcile() {
	_zte_recovery_inhibit_file=$1
	_zte_recovery_now=$2
	_zte_recovery_service_path=$3

	[ -e "$_zte_recovery_inhibit_file" ] || return 0
	if zte_recovery_inhibit_active \
		"$_zte_recovery_inhibit_file" "$_zte_recovery_now"; then
		return 0
	fi
	zte_recovery_service_path_valid "$_zte_recovery_service_path" &&
		zte_recovery_service_available "$_zte_recovery_service_path" ||
		return 1
	_zte_recovery_restart_service=$(
		zte_recovery_inhibit_restart_value \
			"$_zte_recovery_inhibit_file"
	) || _zte_recovery_restart_service=true
	if [ "$_zte_recovery_restart_service" = true ]; then
		zte_recovery_service_control "$_zte_recovery_service_path" start ||
			return 1
		zte_recovery_service_running "$_zte_recovery_service_path" ||
			return 1
	fi
	zte_recovery_inhibit_clear "$_zte_recovery_inhibit_file"
}
