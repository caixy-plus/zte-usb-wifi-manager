#!/bin/sh

zte_schedule_is_uint() {
	case ${1-} in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

zte_schedule_time_to_minutes() {
	_zte_schedule_time=${1-}
	case $_zte_schedule_time in
		[01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;;
		*) return 1 ;;
	esac
	_zte_schedule_hour=${_zte_schedule_time%:*}
	_zte_schedule_minute=${_zte_schedule_time#*:}
	_zte_schedule_hour=${_zte_schedule_hour#0}
	_zte_schedule_minute=${_zte_schedule_minute#0}
	printf '%s\n' "$(( ${_zte_schedule_hour:-0} * 60 + ${_zte_schedule_minute:-0} ))"
}

zte_schedule_weekdays_valid() {
	_zte_schedule_days=${1-}
	[ -n "$_zte_schedule_days" ] || return 1

	_zte_schedule_valid=0
	_zte_schedule_old_ifs=$IFS
	IFS=' '
	for _zte_schedule_day in $_zte_schedule_days; do
		IFS=$_zte_schedule_old_ifs
		case $_zte_schedule_day in
			[1-7]) ;;
			*)
				_zte_schedule_valid=1
				break
				;;
		esac
		IFS=' '
	done
	IFS=$_zte_schedule_old_ifs
	return "$_zte_schedule_valid"
}

zte_schedule_weekday_enabled() {
	_zte_schedule_days=${1-}
	_zte_schedule_wanted=${2-}
	case $_zte_schedule_wanted in
		[1-7]) ;;
		*) return 1 ;;
	esac
	zte_schedule_weekdays_valid "$_zte_schedule_days" || return 1

	_zte_schedule_found=1
	for _zte_schedule_day in $_zte_schedule_days; do
		if [ "$_zte_schedule_day" = "$_zte_schedule_wanted" ]; then
			_zte_schedule_found=0
		fi
	done
	return "$_zte_schedule_found"
}

zte_schedule_pre_departure() {
	_zte_schedule_enabled=${1-}
	_zte_schedule_days=${2-}
	_zte_schedule_departure=${3-}
	_zte_schedule_lead=${4-}
	_zte_schedule_weekday=${5-}
	_zte_schedule_now=${6-}

	case $_zte_schedule_enabled in
		0|1) ;;
		*) return 1 ;;
	esac
	_zte_schedule_departure_minutes=$(
		zte_schedule_time_to_minutes "$_zte_schedule_departure"
	) || return 1
	zte_schedule_weekdays_valid "$_zte_schedule_days" || return 1
	case $_zte_schedule_weekday in
		[1-7]) ;;
		*) return 1 ;;
	esac
	zte_schedule_is_uint "$_zte_schedule_lead" &&
		[ "$_zte_schedule_lead" -ge 1 ] &&
		[ "$_zte_schedule_lead" -le "$_zte_schedule_departure_minutes" ] ||
		return 1
	zte_schedule_is_uint "$_zte_schedule_now" &&
		[ "$_zte_schedule_now" -le 1439 ] || return 1

	_zte_schedule_day_active=0
	if zte_schedule_weekday_enabled \
		"$_zte_schedule_days" "$_zte_schedule_weekday"; then
		_zte_schedule_day_active=1
	else
		_zte_schedule_weekday_status=$?
		[ "$_zte_schedule_weekday_status" -eq 1 ] || return 1
	fi

	if [ "$_zte_schedule_enabled" = 1 ] &&
		[ "$_zte_schedule_day_active" = 1 ] &&
		[ "$_zte_schedule_now" -ge \
			$((_zte_schedule_departure_minutes - _zte_schedule_lead)) ] &&
		[ "$_zte_schedule_now" -lt "$_zte_schedule_departure_minutes" ]; then
		printf '1\n'
	else
		printf '0\n'
	fi
}
