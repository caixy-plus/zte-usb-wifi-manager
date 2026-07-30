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

	zte_power_backend_valid "$_zte_power_backend" || return 1
	zte_power_action_valid "$_zte_power_action" || return 1
	zte_power_reason_valid "$_zte_power_reason" || return 1

	if [ "$_zte_power_action" != KEEP ]; then
		case $_zte_power_backend in
			mock) _zte_power_executed=true ;;
			dry-run) _zte_power_executed=false ;;
			unconfigured|hardware) return 1 ;;
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
