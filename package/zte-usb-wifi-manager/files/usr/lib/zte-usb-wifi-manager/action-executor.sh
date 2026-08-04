#!/bin/sh

ZTE_SIM_READBACK_ATTEMPTS=${ZTE_SIM_READBACK_ATTEMPTS:-4}
ZTE_SIM_READBACK_INTERVAL=${ZTE_SIM_READBACK_INTERVAL:-2}
ZTE_POWER_SUPPLY_READBACK_ATTEMPTS=${ZTE_POWER_SUPPLY_READBACK_ATTEMPTS:-3}
ZTE_POWER_SUPPLY_READBACK_INTERVAL=${ZTE_POWER_SUPPLY_READBACK_INTERVAL:-1}
ZTE_SETTING_READBACK_ATTEMPTS=${ZTE_SETTING_READBACK_ATTEMPTS:-3}
ZTE_SETTING_READBACK_INTERVAL=${ZTE_SETTING_READBACK_INTERVAL:-1}
ZTE_SMS_READBACK_ATTEMPTS=${ZTE_SMS_READBACK_ATTEMPTS:-3}
ZTE_SMS_READBACK_INTERVAL=${ZTE_SMS_READBACK_INTERVAL:-1}
ZTE_DEVICE_ACTION_ATTEMPTS=${ZTE_DEVICE_ACTION_ATTEMPTS:-30}
ZTE_DEVICE_ACTION_INTERVAL=${ZTE_DEVICE_ACTION_INTERVAL:-2}
ZTE_DEVICE_ACTION_MIN_OUTAGE_SECONDS=${ZTE_DEVICE_ACTION_MIN_OUTAGE_SECONDS:-6}

# Build the canonical state that the already-issued action must expose through
# an existing read-only adapter contract. This helper is shared by normal
# execution and restart verification so their comparisons cannot drift.
zte_action_expected_readback() (
	_zte_expected_action=$1
	_zte_expected_record=$2
	_zte_expected_payload=$(zte_json_top_object_get \
		"$_zte_expected_record" payload 2>/dev/null) || return 1
	zte_adapter_action_payload_valid \
		"$_zte_expected_action" "$_zte_expected_payload" || return 1
	case $_zte_expected_action in
		set_apn)
			_zte_expected_apn=$(zte_json_flat_get \
				"$_zte_expected_payload" apn)
			_zte_expected_auth=$(zte_json_flat_get \
				"$_zte_expected_payload" auth)
			_zte_expected_username=''
			if [ "$_zte_expected_auth" != none ]; then
				_zte_expected_username=$(zte_json_flat_get \
					"$_zte_expected_payload" username)
			fi
			printf '{"apn":"%s","auth":"%s","username":"%s"}\n' \
				"$(zte_json_escape "$_zte_expected_apn")" \
				"$_zte_expected_auth" \
				"$(zte_json_escape "$_zte_expected_username")"
			;;
		set_connection_mode)
			printf '%s|off\n' "$(zte_json_flat_get \
				"$_zte_expected_payload" mode)"
			;;
		set_wifi)
			_zte_expected_enabled=$(zte_json_flat_get \
				"$_zte_expected_payload" enabled)
			if [ "$_zte_expected_enabled" = false ]; then
				printf '%s\n' '{"enabled":false}'
			else
				printf '{"enabled":true,"band":"2g","ssid":"%s","security":"%s"}\n' \
					"$(zte_json_escape "$(zte_json_flat_get \
						"$_zte_expected_payload" ssid)")" \
					"$(zte_json_flat_get \
						"$_zte_expected_payload" security)"
			fi
			;;
		set_traffic_plan)
			_zte_expected_enabled=$(zte_json_flat_get \
				"$_zte_expected_payload" enabled)
			if [ "$_zte_expected_enabled" = false ]; then
				printf '%s\n' '0||||||'
			else
				_zte_expected_disconnect=$(zte_json_flat_get \
					"$_zte_expected_payload" disconnect)
				case $_zte_expected_disconnect in
					true) _zte_expected_disconnect=1 ;;
					false) _zte_expected_disconnect=0 ;;
				esac
				printf '1|data|%s|%s|1|%s|%s\n' \
					"$(zte_json_flat_get \
						"$_zte_expected_payload" limit_bytes)" \
					"$(zte_json_flat_get \
						"$_zte_expected_payload" alert_percent)" \
					"$(zte_json_flat_get \
						"$_zte_expected_payload" cycle_day)" \
					"$_zte_expected_disconnect"
			fi
			;;
		reset_traffic) printf '%s\n' '0|0|0' ;;
		set_power_supply_mode)
			zte_json_flat_get "$_zte_expected_payload" mode
			printf '\n'
			;;
		switch_sim)
			zte_json_flat_get "$_zte_expected_payload" target
			printf '\n'
			;;
		delete_sms) printf '%s\n' absent ;;
		mark_sms_read) printf '%s\n' 0 ;;
		*) return 1 ;;
	esac
)

# Verify an action that may already have reached the device before the daemon
# died. This function performs only bounded, read-only adapter calls. It never
# authenticates, invokes a setter, sends SMS, or issues a device command.
zte_action_restart_verification_supported() {
	_zte_verify_profile=${1-}
	_zte_verify_adapter=${2-}
	_zte_verify_action=${3-}
	[ "$_zte_verify_profile" = "$_zte_verify_adapter" ] || return 1
	case $_zte_verify_profile:$_zte_verify_action in
		zte_u25s:switch_sim) return 0 ;;
		zte_u30:set_apn|zte_u30:set_connection_mode|zte_u30:set_wifi|\
zte_u30:set_traffic_plan|zte_u30:reset_traffic|\
zte_u30:set_power_supply_mode|zte_u30:send_sms|zte_u30:delete_sms|\
zte_u30:mark_sms_read|zte_u30:reboot_device|zte_u30:shutdown_device)
			return 0
			;;
		*) return 1 ;;
	esac
}

# Return success only when the public readback contract covers every mutable
# value in the queued payload. Password-bearing APN/Wi-Fi changes cannot be
# reconstructed after a crash because firmware never returns those secrets.
zte_action_restart_readback_complete() (
	_zte_complete_action=$1
	_zte_complete_record=$2
	_zte_complete_payload=$(zte_json_top_object_get \
		"$_zte_complete_record" payload 2>/dev/null) || return 1
	zte_adapter_action_payload_valid \
		"$_zte_complete_action" "$_zte_complete_payload" || return 1
	case $_zte_complete_action in
		set_apn)
			[ "$(zte_json_flat_get \
				"$_zte_complete_payload" auth)" = none ]
			;;
		set_wifi)
			_zte_complete_enabled=$(zte_json_flat_get \
				"$_zte_complete_payload" enabled)
			[ "$_zte_complete_enabled" = false ] ||
				[ "$(zte_json_flat_get \
					"$_zte_complete_payload" security)" = open ]
			;;
		*) return 0 ;;
	esac
)

zte_verify_action_after_restart() (
	_zte_verify_host=$1
	_zte_verify_jar=$2
	_zte_verify_action=$3
	_zte_verify_record=$4
	if ! zte_action_restart_verification_supported \
		"${ZTE_DEVICE_PROFILE_ID:-}" "${ZTE_ADAPTER_ID:-}" \
		"$_zte_verify_action"; then
		printf '%s\n' verification_inconclusive
		return 1
	fi
	case $_zte_verify_action in
		send_sms|delete_sms|reboot_device|shutdown_device)
			printf '%s\n' verification_inconclusive
			return 1
			;;
	esac
	_zte_verify_expected=$(zte_action_expected_readback \
		"$_zte_verify_action" "$_zte_verify_record") || {
		printf '%s\n' readback_failed
		return 1
	}
	if ! zte_action_restart_readback_complete \
		"$_zte_verify_action" "$_zte_verify_record"; then
		printf '%s\n' verification_inconclusive
		return 1
	fi
	_zte_verify_message_id=''
	if [ "$_zte_verify_action" = mark_sms_read ]; then
		_zte_verify_message_id=$(zte_json_path_get \
			"$_zte_verify_record" payload message_id 2>/dev/null) || {
			printf '%s\n' readback_failed
			return 1
		}
	fi
	_zte_verify_record=''
	_zte_verify_observed=''
	_zte_verify_read_ok=0
	case $_zte_verify_action in
		set_apn)
			if _zte_verify_observed=$(zte_adapter_fetch_apn_setting \
				"$_zte_verify_host" "$_zte_verify_jar" 2>/dev/null); then
				_zte_verify_read_ok=1
			fi
			;;
		set_connection_mode)
			if _zte_verify_observed=$(zte_adapter_fetch_connection_mode \
				"$_zte_verify_host" "$_zte_verify_jar" 2>/dev/null); then
				_zte_verify_read_ok=1
			fi
			;;
		set_wifi)
			if _zte_verify_observed=$(zte_adapter_fetch_wifi_setting \
				"$_zte_verify_host" "$_zte_verify_jar" 2>/dev/null); then
				_zte_verify_read_ok=1
			fi
			;;
		set_traffic_plan)
			if _zte_verify_observed=$(zte_adapter_fetch_traffic_plan \
				"$_zte_verify_host" "$_zte_verify_jar" 2>/dev/null); then
				_zte_verify_read_ok=1
			fi
			;;
		reset_traffic)
			if _zte_verify_observed=$(zte_adapter_fetch_traffic_counters \
				"$_zte_verify_host" "$_zte_verify_jar" 2>/dev/null); then
				_zte_verify_read_ok=1
			fi
			;;
		set_power_supply_mode)
			if _zte_verify_observed=$(zte_adapter_fetch_power_supply_mode \
				"$_zte_verify_host" "$_zte_verify_jar" 2>/dev/null); then
				_zte_verify_read_ok=1
			fi
			;;
		switch_sim)
			if _zte_verify_observed=$(zte_adapter_fetch_sim_recovery_state \
				"$_zte_verify_host" "$_zte_verify_jar" 2>/dev/null); then
				_zte_verify_read_ok=1
			fi
			;;
		mark_sms_read)
			if _zte_verify_observed=$(zte_adapter_fetch_sms_message_state \
				"$_zte_verify_host" "$_zte_verify_message_id" \
				"$_zte_verify_jar" 2>/dev/null); then
				_zte_verify_read_ok=1
			fi
			;;
		*) ;;
	esac
	if [ "$_zte_verify_read_ok" != 1 ] ||
		[ -z "$_zte_verify_observed" ]; then
		printf '%s\n' readback_failed
		return 1
	fi
	if [ "$_zte_verify_action" = switch_sim ]; then
		zte_json_is_flat_object "$_zte_verify_observed" || {
			printf '%s\n' readback_failed
			return 1
		}
		_zte_verify_sim_target=$(zte_json_flat_get \
			"$_zte_verify_observed" target)
		_zte_verify_sim_modem=$(zte_json_flat_get \
			"$_zte_verify_observed" modem)
		_zte_verify_sim_provider=$(zte_json_flat_get \
			"$_zte_verify_observed" provider)
		_zte_verify_sim_ppp=$(zte_json_flat_get \
			"$_zte_verify_observed" ppp)
		if [ "$_zte_verify_sim_target" = "$_zte_verify_expected" ] &&
			case $_zte_verify_sim_modem in
				connected|modem_init_complete) true ;;
				*) false ;;
			esac &&
			case $_zte_verify_sim_provider in *[![:space:]]*) true ;; *) false ;; esac &&
			[ "$_zte_verify_sim_ppp" = ipv4_ipv6_connected ]; then
			printf '%s\n' verified_after_restart
			return 0
		fi
		printf '%s\n' readback_mismatch
		return 1
	fi
	if [ "$_zte_verify_action" = mark_sms_read ] &&
		[ "$_zte_verify_observed" = absent ]; then
		printf '%s\n' verification_inconclusive
		return 1
	fi
	if [ "$_zte_verify_observed" = "$_zte_verify_expected" ]; then
		printf '%s\n' verified_after_restart
		return 0
	fi
	printf '%s\n' readback_mismatch
	return 1
)

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
	_zte_power_execute_password=''
	_zte_power_execute_post_status=0
	if zte_adapter_set_power_supply_mode "$_zte_power_execute_host" \
		"$_zte_power_execute_target" "$_zte_power_execute_jar"; then
		:
	else
		_zte_power_execute_post_status=$?
	fi
	case $_zte_power_execute_post_status in
		0|10) ;;
		11) printf '%s\n' device_rejected; return 1 ;;
		*) printf '%s\n' preflight_failed; return 1 ;;
	esac
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
	if [ "$_zte_power_execute_post_status" = 10 ]; then
		printf '%s\n' write_ambiguous
		return 1
	fi
	printf '%s\n' "$_zte_power_execute_failure"
	return 1
}

# Execute a source-reviewed, non-destructive U30 setting and confirm it using
# safe GETs. POST transport failures are ambiguous and are never retried.
zte_execute_u30_setting() (
	_zte_setting_host=$1
	_zte_setting_device_password=$2
	_zte_setting_jar=$3
	_zte_setting_action=$4
	_zte_setting_record=$5
	if zte_adapter_login_required; then
		[ -n "$_zte_setting_device_password" ] || {
			printf '%s\n' credentials_missing
			return 1
		}
		zte_session_login "$_zte_setting_host" \
			"$_zte_setting_device_password" \
			"$_zte_setting_jar" || {
			printf '%s\n' authentication_failed
			return 1
		}
	fi
	_zte_setting_device_password=''
	_zte_setting_expected=$(zte_action_expected_readback \
		"$_zte_setting_action" "$_zte_setting_record") || {
		printf '%s\n' invalid_action
		return 1
	}
	_zte_setting_secret_unverifiable=0
	case $_zte_setting_action in
		set_apn)
			[ "$(zte_json_path_get "$_zte_setting_record" payload auth)" = \
				none ] || _zte_setting_secret_unverifiable=1
			;;
		set_wifi)
			if [ "$(zte_json_path_get \
				"$_zte_setting_record" payload enabled)" = true ] &&
				[ "$(zte_json_path_get \
					"$_zte_setting_record" payload security)" != open ]; then
				_zte_setting_secret_unverifiable=1
			fi
			;;
	esac
	_zte_setting_post_status=0
	case $_zte_setting_action in
		set_apn)
			_zte_setting_apn=$(zte_json_path_get \
				"$_zte_setting_record" payload apn 2>/dev/null) || {
				printf '%s\n' invalid_action; return 1;
			}
			_zte_setting_auth=$(zte_json_path_get \
				"$_zte_setting_record" payload auth 2>/dev/null) || {
				printf '%s\n' invalid_action; return 1;
			}
			_zte_setting_username=$(zte_json_path_get \
				"$_zte_setting_record" payload username 2>/dev/null) ||
				_zte_setting_username=''
			_zte_setting_password=$(zte_json_path_get \
				"$_zte_setting_record" payload password 2>/dev/null) ||
				_zte_setting_password=''
			case $_zte_setting_apn in
				''|*[!A-Za-z0-9._-]*) printf '%s\n' invalid_action; return 1 ;;
			esac
			[ "${#_zte_setting_apn}" -le 100 ] || {
				printf '%s\n' invalid_action; return 1;
			}
			case $_zte_setting_auth in
				none) _zte_setting_username=''; _zte_setting_password='' ;;
				pap|chap|pap_or_chap)
					if ! zte_adapter_payload_text \
						"$_zte_setting_username" 1 128 ||
						! zte_adapter_payload_text \
						"$_zte_setting_password" 1 128; then
						printf '%s\n' invalid_action; return 1
					fi
					;;
				*) printf '%s\n' invalid_action; return 1 ;;
			esac
			_zte_setting_record=''
			zte_adapter_set_apn "$_zte_setting_host" "$_zte_setting_apn" \
				"$_zte_setting_auth" "$_zte_setting_username" \
				"$_zte_setting_password" \
				"$_zte_setting_jar" || _zte_setting_post_status=$?
			_zte_setting_password=''
			;;
		set_connection_mode)
			_zte_setting_mode=$(zte_json_path_get \
				"$_zte_setting_record" payload mode 2>/dev/null) || {
				printf '%s\n' invalid_action; return 1;
			}
			case $_zte_setting_mode in automatic|manual|on_demand) ;; *)
				printf '%s\n' invalid_action; return 1 ;; esac
			_zte_setting_record=''
			zte_adapter_set_connection_mode "$_zte_setting_host" \
				"$_zte_setting_mode" "$_zte_setting_jar" ||
				_zte_setting_post_status=$?
			;;
		set_wifi)
			_zte_setting_enabled=$(zte_json_path_get \
				"$_zte_setting_record" payload enabled 2>/dev/null) || {
				printf '%s\n' invalid_action; return 1;
			}
			case $_zte_setting_enabled in
				false)
					_zte_setting_enabled_raw=0
					_zte_setting_band=''
					_zte_setting_ssid=''
					_zte_setting_security=''
					_zte_setting_password=''
					_zte_setting_channel=''
					;;
				true)
					_zte_setting_enabled_raw=1
					_zte_setting_band=$(zte_json_path_get \
						"$_zte_setting_record" payload band 2>/dev/null) || {
						printf '%s\n' invalid_action; return 1;
					}
					_zte_setting_ssid=$(zte_json_path_get \
						"$_zte_setting_record" payload ssid 2>/dev/null) || {
						printf '%s\n' invalid_action; return 1;
					}
					_zte_setting_security=$(zte_json_path_get \
						"$_zte_setting_record" payload security 2>/dev/null) || {
						printf '%s\n' invalid_action; return 1;
					}
					_zte_setting_channel=$(zte_json_path_get \
						"$_zte_setting_record" payload channel 2>/dev/null) || {
						printf '%s\n' invalid_action; return 1;
					}
					_zte_setting_password=$(zte_json_path_get \
						"$_zte_setting_record" payload password 2>/dev/null) ||
						_zte_setting_password=''
					if [ "$_zte_setting_band" != 2g ] ||
						[ "$_zte_setting_channel" != auto ] ||
						! zte_adapter_payload_text "$_zte_setting_ssid" 1 32; then
						printf '%s\n' invalid_action; return 1;
					fi
					case $_zte_setting_security in
						open) ;;
						wpa2_psk|wpa3_sae|wpa2_wpa3)
							zte_adapter_payload_text \
								"$_zte_setting_password" 8 63 || {
								printf '%s\n' invalid_action; return 1;
							}
							;;
						*) printf '%s\n' invalid_action; return 1 ;;
					esac
					;;
				*) printf '%s\n' invalid_action; return 1 ;;
			esac
			_zte_setting_record=''
			zte_adapter_set_wifi "$_zte_setting_host" \
				"$_zte_setting_enabled_raw" "$_zte_setting_band" \
				"$_zte_setting_ssid" "$_zte_setting_security" \
				"$_zte_setting_password" "$_zte_setting_channel" \
				"$_zte_setting_jar" || _zte_setting_post_status=$?
			_zte_setting_password=''
			;;
		set_traffic_plan)
			_zte_setting_enabled=$(zte_json_path_get \
				"$_zte_setting_record" payload enabled 2>/dev/null) || {
				printf '%s\n' invalid_action; return 1;
			}
			case $_zte_setting_enabled in
				true)
					_zte_setting_enabled_raw=1
					_zte_setting_limit=$(zte_json_path_get \
						"$_zte_setting_record" payload limit_bytes 2>/dev/null) || {
						printf '%s\n' invalid_action; return 1;
					}
					_zte_setting_alert=$(zte_json_path_get \
						"$_zte_setting_record" payload alert_percent 2>/dev/null) || {
						printf '%s\n' invalid_action; return 1;
					}
					_zte_setting_day=$(zte_json_path_get \
						"$_zte_setting_record" payload cycle_day 2>/dev/null) || {
						printf '%s\n' invalid_action; return 1;
					}
					_zte_setting_disconnect=$(zte_json_path_get \
						"$_zte_setting_record" payload disconnect 2>/dev/null) || {
						printf '%s\n' invalid_action; return 1;
					}
					case $_zte_setting_disconnect in
						true) _zte_setting_disconnect_raw=1 ;;
						false) _zte_setting_disconnect_raw=0 ;;
						*) printf '%s\n' invalid_action; return 1 ;;
					esac
					;;
				false)
					_zte_setting_enabled_raw=0
					_zte_setting_limit=''
					_zte_setting_alert=''
					_zte_setting_day=''
					_zte_setting_disconnect_raw=''
					;;
				*) printf '%s\n' invalid_action; return 1 ;;
			esac
			_zte_setting_record=''
			zte_adapter_set_traffic_plan "$_zte_setting_host" \
				"$_zte_setting_enabled_raw" "$_zte_setting_limit" \
				"$_zte_setting_alert" "$_zte_setting_day" \
				"$_zte_setting_disconnect_raw" "$_zte_setting_jar" ||
				_zte_setting_post_status=$?
			;;
		reset_traffic)
			_zte_setting_record=''
			zte_adapter_reset_traffic "$_zte_setting_host" \
				"$_zte_setting_jar" || _zte_setting_post_status=$?
			;;
		*) printf '%s\n' invalid_action; return 1 ;;
	esac
	case $_zte_setting_post_status in
		0|10) ;;
		11) printf '%s\n' device_rejected; return 1 ;;
		*) printf '%s\n' preflight_failed; return 1 ;;
	esac
	_zte_setting_attempts=$ZTE_SETTING_READBACK_ATTEMPTS
	_zte_setting_interval=$ZTE_SETTING_READBACK_INTERVAL
	zte_is_uint "$_zte_setting_attempts" &&
		[ "$_zte_setting_attempts" -ge 1 ] || _zte_setting_attempts=3
	zte_is_uint "$_zte_setting_interval" || _zte_setting_interval=1
	_zte_setting_failure=readback_failed
	_zte_setting_attempt=1
	while [ "$_zte_setting_attempt" -le "$_zte_setting_attempts" ]; do
		_zte_setting_observed=''
		_zte_setting_read_ok=0
		case $_zte_setting_action in
			set_apn)
				if _zte_setting_observed=$(zte_adapter_fetch_apn_setting \
					"$_zte_setting_host" "$_zte_setting_jar" 2>/dev/null); then
					_zte_setting_read_ok=1
				fi
				;;
			set_connection_mode)
				if _zte_setting_observed=$(zte_adapter_fetch_connection_mode \
					"$_zte_setting_host" "$_zte_setting_jar" 2>/dev/null); then
					_zte_setting_read_ok=1
				fi
				;;
			set_wifi)
				if _zte_setting_observed=$(zte_adapter_fetch_wifi_setting \
					"$_zte_setting_host" "$_zte_setting_jar" 2>/dev/null); then
					_zte_setting_read_ok=1
				fi
				;;
			set_traffic_plan)
				if _zte_setting_observed=$(zte_adapter_fetch_traffic_plan \
					"$_zte_setting_host" "$_zte_setting_jar" 2>/dev/null); then
					_zte_setting_read_ok=1
				fi
				;;
			reset_traffic)
				if _zte_setting_observed=$(zte_adapter_fetch_traffic_counters \
					"$_zte_setting_host" "$_zte_setting_jar" 2>/dev/null); then
					_zte_setting_read_ok=1
				fi
				;;
		esac
		if [ "$_zte_setting_read_ok" = 1 ] &&
			[ -n "$_zte_setting_observed" ]; then
			if [ "$_zte_setting_observed" = "$_zte_setting_expected" ]; then
				if [ "$_zte_setting_post_status" = 10 ] &&
					[ "$_zte_setting_secret_unverifiable" = 1 ]; then
					printf '%s\n' write_ambiguous
					return 1
				fi
				printf '%s\n' ok
				return 0
			fi
			_zte_setting_failure=readback_mismatch
		fi
		if [ "$_zte_setting_attempt" -lt "$_zte_setting_attempts" ]; then
			sleep "$_zte_setting_interval"
		fi
		_zte_setting_attempt=$((_zte_setting_attempt + 1))
	done
	if [ "$_zte_setting_post_status" = 10 ]; then
		printf '%s\n' write_ambiguous
	else
		printf '%s\n' "$_zte_setting_failure"
	fi
	return 1
)

zte_execute_u30_sms_action() (
	_zte_sms_execute_host=$1
	_zte_sms_execute_password=$2
	_zte_sms_execute_jar=$3
	_zte_sms_execute_action=$4
	_zte_sms_execute_record=$5
	if zte_adapter_login_required; then
		[ -n "$_zte_sms_execute_password" ] || {
			printf '%s\n' credentials_missing; return 1;
		}
		zte_session_login "$_zte_sms_execute_host" \
			"$_zte_sms_execute_password" "$_zte_sms_execute_jar" || {
				printf '%s\n' authentication_failed; return 1;
			}
	fi
	_zte_sms_execute_password=''
	_zte_sms_execute_post_status=0
	case $_zte_sms_execute_action in
		send_sms)
			_zte_sms_execute_number=$(zte_json_path_get \
				"$_zte_sms_execute_record" payload number 2>/dev/null) || {
				printf '%s\n' invalid_action; return 1;
			}
			_zte_sms_execute_content=$(zte_json_path_get \
				"$_zte_sms_execute_record" payload content 2>/dev/null) || {
				printf '%s\n' invalid_action; return 1;
			}
			if ! zte_adapter_payload_phone "$_zte_sms_execute_number" ||
				! zte_adapter_sms_payload_valid "$_zte_sms_execute_content"; then
				printf '%s\n' invalid_action; return 1;
			fi
			_zte_sms_execute_baseline=$(zte_adapter_fetch_sms_command_status \
				"$_zte_sms_execute_host" 4 "$_zte_sms_execute_jar" \
				2>/dev/null) || {
				printf '%s\n' preflight_failed; return 1;
			}
			zte_adapter_send_sms "$_zte_sms_execute_host" \
				"$_zte_sms_execute_number" "$_zte_sms_execute_content" \
				"$_zte_sms_execute_jar" || _zte_sms_execute_post_status=$?
			_zte_sms_execute_expected=succeeded
			;;
		delete_sms)
			_zte_sms_execute_id=$(zte_json_path_get \
				"$_zte_sms_execute_record" payload message_id 2>/dev/null) || {
				printf '%s\n' invalid_action; return 1;
			}
			zte_adapter_payload_message_id "$_zte_sms_execute_id" || {
				printf '%s\n' invalid_action; return 1;
			}
			_zte_sms_execute_pre_state=$(zte_adapter_fetch_sms_message_state \
				"$_zte_sms_execute_host" "$_zte_sms_execute_id" \
				"$_zte_sms_execute_jar" 2>/dev/null) || {
				printf '%s\n' preflight_failed; return 1;
			}
			[ "$_zte_sms_execute_pre_state" != absent ] || {
				printf '%s\n' invalid_action; return 1;
			}
			_zte_sms_execute_baseline=$(zte_adapter_fetch_sms_command_status \
				"$_zte_sms_execute_host" 6 "$_zte_sms_execute_jar" \
				2>/dev/null) || {
				printf '%s\n' preflight_failed; return 1;
			}
			zte_adapter_delete_sms "$_zte_sms_execute_host" \
				"$_zte_sms_execute_id" "$_zte_sms_execute_jar" ||
				_zte_sms_execute_post_status=$?
			_zte_sms_execute_expected=absent
			;;
		mark_sms_read)
			_zte_sms_execute_id=$(zte_json_path_get \
				"$_zte_sms_execute_record" payload message_id 2>/dev/null) || {
				printf '%s\n' invalid_action; return 1;
			}
			zte_adapter_payload_message_id "$_zte_sms_execute_id" || {
				printf '%s\n' invalid_action; return 1;
			}
			_zte_sms_execute_pre_state=$(zte_adapter_fetch_sms_message_state \
				"$_zte_sms_execute_host" "$_zte_sms_execute_id" \
				"$_zte_sms_execute_jar" 2>/dev/null) || {
				printf '%s\n' preflight_failed; return 1;
			}
			[ "$_zte_sms_execute_pre_state" != absent ] || {
				printf '%s\n' invalid_action; return 1;
			}
			zte_adapter_mark_sms_read "$_zte_sms_execute_host" \
				"$_zte_sms_execute_id" "$_zte_sms_execute_jar" ||
				_zte_sms_execute_post_status=$?
			_zte_sms_execute_expected=$(zte_action_expected_readback \
				"$_zte_sms_execute_action" "$_zte_sms_execute_record") || {
				printf '%s\n' invalid_action; return 1;
			}
			;;
		*) printf '%s\n' invalid_action; return 1 ;;
	esac
	_zte_sms_execute_record=''
	_zte_sms_execute_number=''
	_zte_sms_execute_content=''
	case $_zte_sms_execute_post_status in
		0|10) ;;
		11) printf '%s\n' device_rejected; return 1 ;;
		12) printf '%s\n' preflight_failed; return 1 ;;
		*) _zte_sms_execute_post_status=10 ;;
	esac
	if [ "$_zte_sms_execute_action" = send_sms ] &&
		[ "$_zte_sms_execute_post_status" = 10 ]; then
		printf '%s\n' write_ambiguous
		return 1
	fi
	_zte_sms_execute_attempts=$ZTE_SMS_READBACK_ATTEMPTS
	_zte_sms_execute_interval=$ZTE_SMS_READBACK_INTERVAL
	zte_is_uint "$_zte_sms_execute_attempts" &&
		[ "$_zte_sms_execute_attempts" -ge 1 ] || _zte_sms_execute_attempts=3
	zte_is_uint "$_zte_sms_execute_interval" || _zte_sms_execute_interval=1
	_zte_sms_execute_failure=readback_failed
	_zte_sms_execute_transition=0
	_zte_sms_execute_attempt=1
	while [ "$_zte_sms_execute_attempt" -le "$_zte_sms_execute_attempts" ]; do
		case $_zte_sms_execute_action in
			send_sms|delete_sms)
				case $_zte_sms_execute_action in
					send_sms) _zte_sms_execute_command=4 ;;
					delete_sms) _zte_sms_execute_command=6 ;;
				esac
				_zte_sms_execute_observed=$(zte_adapter_fetch_sms_command_status \
					"$_zte_sms_execute_host" "$_zte_sms_execute_command" \
					"$_zte_sms_execute_jar" \
					2>/dev/null) || _zte_sms_execute_observed=''
				;;
			*)
				_zte_sms_execute_observed=$(zte_adapter_fetch_sms_message_state \
					"$_zte_sms_execute_host" "$_zte_sms_execute_id" \
					"$_zte_sms_execute_jar" 2>/dev/null) || _zte_sms_execute_observed=''
				;;
		esac
		if [ -n "$_zte_sms_execute_observed" ]; then
			if [ "$_zte_sms_execute_observed" != \
				"${_zte_sms_execute_baseline:-}" ]; then
				_zte_sms_execute_transition=1
			fi
			if [ "$_zte_sms_execute_observed" = failed ]; then
				printf '%s\n' device_rejected
				return 1
			fi
			case $_zte_sms_execute_action in
				send_sms)
					if [ "$_zte_sms_execute_observed" = succeeded ] &&
						{ [ "$_zte_sms_execute_baseline" != succeeded ] ||
							[ "$_zte_sms_execute_transition" = 1 ]; }; then
						printf '%s\n' ok; return 0
					fi
					;;
				delete_sms)
					if [ "$_zte_sms_execute_observed" = succeeded ] &&
						{ [ "$_zte_sms_execute_baseline" != succeeded ] ||
							[ "$_zte_sms_execute_transition" = 1 ]; }; then
						_zte_sms_execute_message_state=''
						if _zte_sms_execute_message_state=$( \
							zte_adapter_fetch_sms_message_state \
								"$_zte_sms_execute_host" \
								"$_zte_sms_execute_id" \
								"$_zte_sms_execute_jar" 2>/dev/null
						) && [ "$_zte_sms_execute_message_state" = absent ]; then
							printf '%s\n' ok
							return 0
						fi
					fi
					;;
				*)
					if [ "$_zte_sms_execute_observed" = \
						"$_zte_sms_execute_expected" ]; then
						printf '%s\n' ok; return 0
					fi
					;;
			esac
			_zte_sms_execute_failure=readback_mismatch
		fi
		if [ "$_zte_sms_execute_attempt" -lt "$_zte_sms_execute_attempts" ]; then
			sleep "$_zte_sms_execute_interval"
		fi
		_zte_sms_execute_attempt=$((_zte_sms_execute_attempt + 1))
	done
	if [ "$_zte_sms_execute_post_status" = 10 ]; then
		printf '%s\n' write_ambiguous
	else
		printf '%s\n' "$_zte_sms_execute_failure"
	fi
	return 1
)

zte_execute_u30_device_action() (
	_zte_device_execute_host=$1
	_zte_device_execute_password=$2
	_zte_device_execute_jar=$3
	_zte_device_execute_action=$4
	case $_zte_device_execute_action in
		reboot_device) _zte_device_execute_command=reboot ;;
		shutdown_device) _zte_device_execute_command=shutdown ;;
		*) printf '%s\n' invalid_action; return 1 ;;
	esac
	if zte_adapter_login_required; then
		[ -n "$_zte_device_execute_password" ] || {
			printf '%s\n' credentials_missing; return 1;
		}
		zte_session_login "$_zte_device_execute_host" \
			"$_zte_device_execute_password" "$_zte_device_execute_jar" || {
				printf '%s\n' authentication_failed; return 1;
			}
	fi
	_zte_device_execute_password=''
	if ! zte_adapter_probe_status "$_zte_device_execute_host" \
		"$_zte_device_execute_jar"; then
		printf '%s\n' preflight_failed
		return 1
	fi
	_zte_device_execute_post_status=0
	zte_adapter_device_command "$_zte_device_execute_host" \
		"$_zte_device_execute_command" "$_zte_device_execute_jar" ||
		_zte_device_execute_post_status=$?
	case $_zte_device_execute_post_status in
		0|10) ;;
		11) printf '%s\n' device_rejected; return 1 ;;
		12) printf '%s\n' preflight_failed; return 1 ;;
		*) _zte_device_execute_post_status=10 ;;
	esac
	_zte_device_execute_attempts=$ZTE_DEVICE_ACTION_ATTEMPTS
	_zte_device_execute_interval=$ZTE_DEVICE_ACTION_INTERVAL
	_zte_device_execute_min_outage=$ZTE_DEVICE_ACTION_MIN_OUTAGE_SECONDS
	zte_is_uint "$_zte_device_execute_attempts" &&
		[ "$_zte_device_execute_attempts" -ge 2 ] || _zte_device_execute_attempts=30
	zte_is_uint "$_zte_device_execute_interval" || _zte_device_execute_interval=2
	zte_is_uint "$_zte_device_execute_min_outage" || _zte_device_execute_min_outage=6
	_zte_device_execute_outage_qualified=0
	_zte_device_execute_failures=0
	_zte_device_execute_online=1
	_zte_device_execute_attempt=1
	while [ "$_zte_device_execute_attempt" -le "$_zte_device_execute_attempts" ]; do
		if zte_adapter_probe_status "$_zte_device_execute_host" \
			"$_zte_device_execute_jar"; then
			_zte_device_execute_online=1
			if [ "$_zte_device_execute_action" = reboot_device ] &&
				[ "$_zte_device_execute_outage_qualified" = 1 ]; then
				printf '%s\n' ok
				return 0
			fi
			_zte_device_execute_failures=0
		else
			_zte_device_execute_online=0
			_zte_device_execute_failures=$((_zte_device_execute_failures + 1))
			if [ $(((_zte_device_execute_failures - 1) * \
				_zte_device_execute_interval)) -ge \
				"$_zte_device_execute_min_outage" ]; then
				_zte_device_execute_outage_qualified=1
			fi
		fi
		if [ "$_zte_device_execute_attempt" -lt "$_zte_device_execute_attempts" ]; then
			sleep "$_zte_device_execute_interval"
		fi
		_zte_device_execute_attempt=$((_zte_device_execute_attempt + 1))
	done
	if [ "$_zte_device_execute_action" = shutdown_device ] &&
		[ "$_zte_device_execute_outage_qualified" = 1 ] &&
		[ "$_zte_device_execute_online" = 0 ]; then
		printf '%s\n' ok
		return 0
	fi
	if [ "$_zte_device_execute_post_status" = 10 ]; then
		printf '%s\n' write_ambiguous
		return 1
	fi
	if [ "$_zte_device_execute_outage_qualified" = 1 ]; then
		printf '%s\n' recovery_timeout
	else
		printf '%s\n' readback_mismatch
	fi
	return 1
)

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
