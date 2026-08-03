#!/bin/sh

ZTE_SIM_READBACK_ATTEMPTS=${ZTE_SIM_READBACK_ATTEMPTS:-4}
ZTE_SIM_READBACK_INTERVAL=${ZTE_SIM_READBACK_INTERVAL:-2}
ZTE_POWER_SUPPLY_READBACK_ATTEMPTS=${ZTE_POWER_SUPPLY_READBACK_ATTEMPTS:-3}
ZTE_POWER_SUPPLY_READBACK_INTERVAL=${ZTE_POWER_SUPPLY_READBACK_INTERVAL:-1}

# Execute one non-retriable U30 power mode write and verify it with safe reads.
# A failed POST is deliberately reported as ambiguous and is never repeated.
zte_execute_power_supply_mode() {
	_zte_power_execute_host=$1
	_zte_power_execute_password=$2
	_zte_power_execute_jar=$3
	_zte_power_execute_target=$4
	case $_zte_power_execute_target in
		charging|direct_supply) ;;
		*) printf '%s\n' invalid_target; return 1 ;;
	esac
	if zte_adapter_login_required; then
		[ -n "$_zte_power_execute_password" ] || {
			printf '%s\n' credentials_missing
			return 1
		}
		zte_session_login "$_zte_power_execute_host" \
			"$_zte_power_execute_password" "$_zte_power_execute_jar" || {
			printf '%s\n' authentication_failed
			return 1
		}
	fi
	if ! zte_adapter_set_power_supply_mode "$_zte_power_execute_host" \
		"$_zte_power_execute_target" "$_zte_power_execute_jar"; then
		printf '%s\n' write_ambiguous
		return 1
	fi
	_zte_power_execute_attempts=$ZTE_POWER_SUPPLY_READBACK_ATTEMPTS
	_zte_power_execute_interval=$ZTE_POWER_SUPPLY_READBACK_INTERVAL
	zte_is_uint "$_zte_power_execute_attempts" &&
		[ "$_zte_power_execute_attempts" -ge 1 ] ||
		_zte_power_execute_attempts=3
	zte_is_uint "$_zte_power_execute_interval" ||
		_zte_power_execute_interval=1
	_zte_power_execute_failure=readback_failed
	_zte_power_execute_attempt=1
	while [ "$_zte_power_execute_attempt" -le \
		"$_zte_power_execute_attempts" ]; do
		if _zte_power_execute_observed=$(
			zte_adapter_fetch_power_supply_mode \
				"$_zte_power_execute_host" "$_zte_power_execute_jar"
		); then
			if [ "$_zte_power_execute_observed" = \
				"$_zte_power_execute_target" ]; then
				printf '%s\n' ok
				return 0
			fi
			_zte_power_execute_failure=readback_mismatch
		fi
		if [ "$_zte_power_execute_attempt" -lt \
			"$_zte_power_execute_attempts" ]; then
			sleep "$_zte_power_execute_interval"
		fi
		_zte_power_execute_attempt=$((_zte_power_execute_attempt + 1))
	done
	printf '%s\n' "$_zte_power_execute_failure"
	return 1
}

# Execute the one target-firmware write whose request shape is currently
# verified. The result is a stable, non-secret code printed on stdout.
#
# $1 host, $2 password, $3 cookie jar, $4 semantic SIM target.
zte_execute_switch_sim() {
	_zte_execute_host=$1
	_zte_execute_password=$2
	_zte_execute_jar=$3
	_zte_execute_target=$4

	_zte_execute_index=$(
		zte_adapter_sim_card_index "$_zte_execute_target"
	) || {
		printf 'invalid_target\n'
		return 1
	}
	if zte_adapter_login_required; then
		if [ -z "$_zte_execute_password" ]; then
			printf 'credentials_missing\n'
			return 1
		fi
		if ! zte_session_login \
			"$_zte_execute_host" "$_zte_execute_password" \
			"$_zte_execute_jar"; then
			printf 'authentication_failed\n'
			return 1
		fi
	fi

	# Selecting an already selected slot is idempotent. One relogin and retry
	# safely recovers the common expired-session failure without an unbounded
	# write loop.
	if ! zte_adapter_switch_sim \
		"$_zte_execute_host" "$_zte_execute_target" \
		"$_zte_execute_jar"; then
		if ! zte_adapter_login_required ||
			! zte_session_login \
			"$_zte_execute_host" "$_zte_execute_password" \
			"$_zte_execute_jar" ||
			! zte_adapter_switch_sim \
				"$_zte_execute_host" "$_zte_execute_target" \
				"$_zte_execute_jar"; then
			printf 'write_failed\n'
			return 1
		fi
	fi

	_zte_execute_attempts=$ZTE_SIM_READBACK_ATTEMPTS
	_zte_execute_interval=$ZTE_SIM_READBACK_INTERVAL
	if ! zte_is_uint "$_zte_execute_attempts" ||
		[ "$_zte_execute_attempts" -lt 1 ]; then
		_zte_execute_attempts=4
	fi
	if ! zte_is_uint "$_zte_execute_interval"; then
		_zte_execute_interval=2
	fi

	_zte_execute_failure=readback_failed
	_zte_execute_attempt=1
	while [ "$_zte_execute_attempt" -le "$_zte_execute_attempts" ]; do
		_zte_execute_raw=''
		_zte_execute_failure=readback_failed
		if _zte_execute_raw=$(
			zte_adapter_fetch \
				"$_zte_execute_host" "$_zte_execute_password" \
				"$_zte_execute_jar"
		) &&
			zte_json_is_flat_object "$_zte_execute_raw" &&
			zte_json_flat_has \
				"$_zte_execute_raw" simcard_active_slot_temp &&
			zte_json_flat_has \
				"$_zte_execute_raw" mc_modem_main_state &&
			zte_json_flat_has \
				"$_zte_execute_raw" network_provider_fullname &&
			zte_json_flat_has \
				"$_zte_execute_raw" ppp_status; then
			_zte_execute_active=$(
				zte_json_flat_get \
					"$_zte_execute_raw" simcard_active_slot_temp
			)
			_zte_execute_modem=$(
				zte_json_flat_get \
					"$_zte_execute_raw" mc_modem_main_state
			)
			_zte_execute_provider=$(
				zte_json_flat_get \
					"$_zte_execute_raw" network_provider_fullname
			)
			_zte_execute_ppp=$(
				zte_json_flat_get "$_zte_execute_raw" ppp_status
			)

			if [ -z "$_zte_execute_active" ]; then
				_zte_execute_failure=readback_failed
			elif [ "$_zte_execute_active" != "$_zte_execute_index" ]; then
				_zte_execute_failure=readback_mismatch
			elif ! zte_adapter_modem_ready "$_zte_execute_modem"; then
				_zte_execute_failure=modem_not_ready
			else
				case $_zte_execute_provider in
					*[![:space:]]*)
						if [ "$_zte_execute_ppp" = \
							ipv4_ipv6_connected ]; then
							printf 'ok\n'
							return 0
						fi
						_zte_execute_failure=ppp_not_restored
						;;
					*)
						_zte_execute_failure=network_not_registered
						;;
				esac
			fi
		fi
		if [ "$_zte_execute_attempt" -lt "$_zte_execute_attempts" ]; then
			sleep "$_zte_execute_interval"
		fi
		_zte_execute_attempt=$((_zte_execute_attempt + 1))
	done

	printf '%s\n' "$_zte_execute_failure"
	return 1
}
