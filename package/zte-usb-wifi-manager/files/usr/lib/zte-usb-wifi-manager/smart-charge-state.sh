#!/bin/sh

zte_smart_charge_error_valid() {
	case ${1-} in
		write_ambiguous|readback_failed|readback_mismatch|\
authentication_failed|credentials_missing|executor_failed|attempt_in_progress)
			return 0
			;;
		*) return 1 ;;
	esac
}

zte_smart_charge_epoch_valid() {
	zte_is_uint "${1-}" || return 1
	_zte_smart_epoch_candidate=$1
	_zte_smart_epoch_max=2147483647
	[ "${#_zte_smart_epoch_candidate}" -lt 10 ] && return 0
	[ "${#_zte_smart_epoch_candidate}" -eq 10 ] || return 1
	while [ -n "$_zte_smart_epoch_candidate" ]; do
		_zte_smart_epoch_digit=${_zte_smart_epoch_candidate%\
"${_zte_smart_epoch_candidate#?}"}
		_zte_smart_epoch_max_digit=${_zte_smart_epoch_max%\
"${_zte_smart_epoch_max#?}"}
		[ "$_zte_smart_epoch_digit" -lt \
			"$_zte_smart_epoch_max_digit" ] && return 0
		[ "$_zte_smart_epoch_digit" -gt \
			"$_zte_smart_epoch_max_digit" ] && return 1
		_zte_smart_epoch_candidate=${_zte_smart_epoch_candidate#?}
		_zte_smart_epoch_max=${_zte_smart_epoch_max#?}
	done
	return 0
}

zte_smart_charge_state_dir_valid() {
	[ -n "${1-}" ] && [ "$1" != / ] && [ -d "$1" ] && [ ! -L "$1" ]
}

zte_smart_charge_file_mode() {
	if _zte_smart_state_mode=$(stat -c '%a' "$1" 2>/dev/null); then
		printf '%s\n' "$_zte_smart_state_mode"
	else
		stat -f '%Lp' "$1" 2>/dev/null
	fi
}

zte_smart_charge_state_remove() {
	rm -f "$1"
}

zte_smart_charge_cooldown_clear() {
	_zte_smart_state_root=$1
	zte_smart_charge_state_dir_valid "$_zte_smart_state_root" || return 1
	_zte_smart_state_file=$_zte_smart_state_root/smart-charge-cooldown
	if [ ! -e "$_zte_smart_state_file" ] &&
		[ ! -L "$_zte_smart_state_file" ]; then
		return 0
	fi
	[ -f "$_zte_smart_state_file" ] &&
		[ ! -L "$_zte_smart_state_file" ] || return 1
	[ "$(zte_smart_charge_file_mode "$_zte_smart_state_file")" = 600 ] ||
		return 1
	zte_smart_charge_state_remove "$_zte_smart_state_file" || return 1
	[ ! -e "$_zte_smart_state_file" ] && [ ! -L "$_zte_smart_state_file" ]
}

zte_smart_charge_cooldown_write() {
	_zte_smart_state_root=$1
	_zte_smart_state_retry_after=$2
	_zte_smart_state_error=$3
	zte_smart_charge_state_dir_valid "$_zte_smart_state_root" || return 1
	zte_smart_charge_epoch_valid "$_zte_smart_state_retry_after" || return 1
	zte_smart_charge_error_valid "$_zte_smart_state_error" || return 1

	_zte_smart_state_file=$_zte_smart_state_root/smart-charge-cooldown
	if [ -L "$_zte_smart_state_file" ]; then
		return 1
	elif [ -e "$_zte_smart_state_file" ] &&
		[ ! -f "$_zte_smart_state_file" ]; then
		return 1
	fi
	_zte_smart_state_tmp=$_zte_smart_state_file.tmp.$$
	umask 077
	rm -f "$_zte_smart_state_tmp" || return 1
	printf '%s %s\n' "$_zte_smart_state_retry_after" \
		"$_zte_smart_state_error" >"$_zte_smart_state_tmp" || return 1
	chmod 600 "$_zte_smart_state_tmp" || {
		rm -f "$_zte_smart_state_tmp"
		return 1
	}
	mv "$_zte_smart_state_tmp" "$_zte_smart_state_file" || {
		rm -f "$_zte_smart_state_tmp"
		return 1
	}
}

zte_smart_charge_cooldown_load() {
	_zte_smart_state_root=$1
	_zte_smart_state_now=$2
	zte_smart_charge_state_dir_valid "$_zte_smart_state_root" || return 2
	zte_smart_charge_epoch_valid "$_zte_smart_state_now" || return 2
	_zte_smart_state_file=$_zte_smart_state_root/smart-charge-cooldown
	if [ ! -e "$_zte_smart_state_file" ] &&
		[ ! -L "$_zte_smart_state_file" ]; then
		return 1
	fi
	if [ -L "$_zte_smart_state_file" ] ||
		[ ! -f "$_zte_smart_state_file" ] ||
		[ "$(zte_smart_charge_file_mode "$_zte_smart_state_file")" != 600 ]; then
		return 2
	fi
	_zte_smart_state_record=$(cat "$_zte_smart_state_file" 2>/dev/null) ||
		return 2
	_zte_smart_state_retry_after=${_zte_smart_state_record%% *}
	_zte_smart_state_error=${_zte_smart_state_record#* }
	if [ "$_zte_smart_state_error" = "$_zte_smart_state_record" ] ||
		[ "$_zte_smart_state_record" != \
		"$_zte_smart_state_retry_after $_zte_smart_state_error" ] ||
		! zte_smart_charge_epoch_valid "$_zte_smart_state_retry_after" ||
		! zte_smart_charge_error_valid "$_zte_smart_state_error"; then
		return 2
	fi
	if [ "$_zte_smart_state_retry_after" -le "$_zte_smart_state_now" ]; then
		zte_smart_charge_state_remove "$_zte_smart_state_file" || return 2
		if [ -e "$_zte_smart_state_file" ] ||
			[ -L "$_zte_smart_state_file" ]; then
			return 2
		fi
		return 1
	fi
	printf '%s:%s\n' "$_zte_smart_state_retry_after" \
		"$_zte_smart_state_error"
	return 0
}
