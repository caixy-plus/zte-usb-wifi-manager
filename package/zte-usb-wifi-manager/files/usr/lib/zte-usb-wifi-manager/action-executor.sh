#!/bin/sh

ZTE_SIM_READBACK_ATTEMPTS=${ZTE_SIM_READBACK_ATTEMPTS:-4}
ZTE_SIM_READBACK_INTERVAL=${ZTE_SIM_READBACK_INTERVAL:-2}

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

	# Selecting an already selected slot is idempotent. One relogin and retry
	# safely recovers the common expired-session failure without an unbounded
	# write loop.
	if ! zte_adapter_switch_sim \
		"$_zte_execute_host" "$_zte_execute_target" \
		"$_zte_execute_jar"; then
		if ! zte_session_login \
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

	_zte_execute_seen_slot=0
	_zte_execute_attempt=1
	while [ "$_zte_execute_attempt" -le "$_zte_execute_attempts" ]; do
		_zte_execute_raw=''
		if _zte_execute_raw=$(
			zte_adapter_fetch \
				"$_zte_execute_host" "$_zte_execute_password" \
				"$_zte_execute_jar"
		) &&
			zte_json_flat_has \
				"$_zte_execute_raw" simcard_active_slot_temp; then
			_zte_execute_seen_slot=1
			_zte_execute_active=$(
				zte_json_flat_get \
					"$_zte_execute_raw" simcard_active_slot_temp
			)
			if [ "$_zte_execute_active" = "$_zte_execute_index" ]; then
				printf 'ok\n'
				return 0
			fi
		fi
		if [ "$_zte_execute_attempt" -lt "$_zte_execute_attempts" ]; then
			sleep "$_zte_execute_interval"
		fi
		_zte_execute_attempt=$((_zte_execute_attempt + 1))
	done

	if [ "$_zte_execute_seen_slot" = 1 ]; then
		printf 'readback_mismatch\n'
	else
		printf 'readback_failed\n'
	fi
	return 1
}
