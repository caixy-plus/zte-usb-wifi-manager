#!/bin/sh

zte_smart_charge_uint() {
	case ${1-} in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

# Map trusted battery state to a semantic device mode. In the hysteresis band
# the observed mode is preserved. Unknown observations never trigger a write.
zte_smart_charge_decide() {
	_zte_charge_enabled=${1-}
	_zte_charge_battery=${2-}
	_zte_charge_low=${3-}
	_zte_charge_high=${4-}
	_zte_charge_mode=${5-}

	case $_zte_charge_enabled in
		0) printf '%s\n' 'DISABLED:KEEP'; return 0 ;;
		1) ;;
		*) return 1 ;;
	esac
	zte_smart_charge_uint "$_zte_charge_low" &&
		zte_smart_charge_uint "$_zte_charge_high" || return 1
	[ "$_zte_charge_low" -lt "$_zte_charge_high" ] &&
		[ "$_zte_charge_high" -le 100 ] || return 1
	if ! zte_smart_charge_uint "$_zte_charge_battery"; then
		printf '%s\n' 'STATE_UNKNOWN:KEEP'
		return 0
	fi
	[ "$_zte_charge_battery" -le 100 ] || return 1
	case $_zte_charge_mode in
		charging|direct_supply) ;;
		*) printf '%s\n' 'STATE_UNKNOWN:KEEP'; return 0 ;;
	esac
	if [ "$_zte_charge_battery" -le "$_zte_charge_low" ]; then
		printf '%s\n' 'BATTERY_LOW:CHARGE'
	elif [ "$_zte_charge_battery" -ge "$_zte_charge_high" ]; then
		printf '%s\n' 'BATTERY_HIGH:DIRECT_SUPPLY'
	elif [ "$_zte_charge_mode" = charging ]; then
		printf '%s\n' 'HYSTERESIS:CHARGE'
	else
		printf '%s\n' 'HYSTERESIS:DIRECT_SUPPLY'
	fi
}
