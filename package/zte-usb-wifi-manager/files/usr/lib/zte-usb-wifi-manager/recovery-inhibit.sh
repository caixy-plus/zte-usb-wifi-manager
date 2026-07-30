#!/bin/sh

zte_recovery_reason_valid() {
	case ${1-} in
		scheduled_power_off|manual_power_off|battery_high) return 0 ;;
		*) return 1 ;;
	esac
}

zte_recovery_inhibit_write() {
	_zte_inhibit_file=$1
	_zte_inhibit_reason=$2
	_zte_inhibit_expires=$3
	_zte_inhibit_created=$4

	[ -n "$_zte_inhibit_file" ] && [ "$_zte_inhibit_file" != / ] ||
		return 1
	zte_recovery_reason_valid "$_zte_inhibit_reason" || return 1
	zte_is_uint "$_zte_inhibit_expires" || return 1
	zte_is_uint "$_zte_inhibit_created" || return 1
	[ "$_zte_inhibit_expires" -gt "$_zte_inhibit_created" ] || return 1

	_zte_inhibit_tmp=$_zte_inhibit_file.tmp.$$
	umask 077
	printf '{"reason":"%s","created":%s,"expires":%s}\n' \
		"$_zte_inhibit_reason" "$_zte_inhibit_created" \
		"$_zte_inhibit_expires" >"$_zte_inhibit_tmp" || return 1
	chmod 600 "$_zte_inhibit_tmp" || return 1
	mv "$_zte_inhibit_tmp" "$_zte_inhibit_file"
}

zte_recovery_inhibit_active() {
	_zte_inhibit_file=$1
	_zte_inhibit_now=$2
	zte_is_uint "$_zte_inhibit_now" || return 1
	[ -s "$_zte_inhibit_file" ] || return 1
	_zte_inhibit_json=$(cat "$_zte_inhibit_file")
	zte_json_is_flat_object "$_zte_inhibit_json" || return 1
	_zte_inhibit_reason=$(zte_json_flat_get "$_zte_inhibit_json" reason)
	_zte_inhibit_expires=$(zte_json_flat_get "$_zte_inhibit_json" expires)
	zte_recovery_reason_valid "$_zte_inhibit_reason" || return 1
	zte_is_uint "$_zte_inhibit_expires" || return 1
	[ "$_zte_inhibit_expires" -gt "$_zte_inhibit_now" ]
}

zte_recovery_inhibit_clear() {
	_zte_inhibit_file=$1
	[ -n "$_zte_inhibit_file" ] && [ "$_zte_inhibit_file" != / ] ||
		return 1
	rm -f "$_zte_inhibit_file"
}
