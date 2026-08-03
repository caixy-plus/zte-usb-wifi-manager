#!/bin/sh

# Map a device flag string to JSON true/false/null.
zte_adapter_origin() {
	_zte_adapter_origin_input=$1
	_zte_adapter_scheme=${ZTE_DEVICE_PROFILE_SCHEME:-http}
	case $_zte_adapter_scheme in
		http|https) ;;
		*) return 1 ;;
	esac
	case $_zte_adapter_origin_input in
		http://*|https://*) _zte_adapter_origin=$_zte_adapter_origin_input ;;
		*)
			zte_validate_host "$_zte_adapter_origin_input" || return 1
			_zte_adapter_origin=$_zte_adapter_scheme://$_zte_adapter_origin_input
			;;
	esac
	zte_http_origin_valid "$_zte_adapter_origin" || return 1
	case $_zte_adapter_origin in
		"$_zte_adapter_scheme"://*) ;;
		*) return 1 ;;
	esac
	printf '%s\n' "$_zte_adapter_origin"
}

zte_adapter_bool() {
	case ${1-} in
		1|true|yes) printf 'true' ;;
		0|false|no) printf 'false' ;;
		*) printf 'null' ;;
	esac
}

# The target firmware uses 2 for a present, fully charged battery. Its WebUI
# renders 0 as discharging, 2 as full, and the remaining known value 1 as
# charging. Keep this device-specific enum out of the generic boolean mapper.
zte_adapter_charging_bool() {
	case ${1-} in
		1|true|yes) printf 'true' ;;
		0|2|false|no) printf 'false' ;;
		*) return 1 ;;
	esac
}

zte_adapter_modem_ready() {
	case ${1-} in
		connected|modem_init_complete) return 0 ;;
		*) return 1 ;;
	esac
}

# Print one flat JSON field as a JSON string, or null when it is absent.
zte_adapter_json_field() {
	if zte_json_flat_has "$1" "$2"; then
		_zte_json_field_value=$(zte_json_flat_get "$1" "$2")
		printf '"%s"' "$(zte_json_escape "$_zte_json_field_value")"
	else
		printf 'null'
	fi
}

# Print one field as a JSON string, using null for an absent or empty value.
zte_adapter_json_nonempty_field() {
	if ! zte_json_flat_has "$1" "$2"; then
		printf 'null'
		return
	fi
	_zte_json_nonempty_value=$(zte_json_flat_get "$1" "$2")
	if [ -z "$_zte_json_nonempty_value" ]; then
		printf 'null'
	else
		printf '"%s"' "$(zte_json_escape "$_zte_json_nonempty_value")"
	fi
}

# Print an unsigned decimal field as a JSON number. The third argument controls
# whether firmware-defined empty counters become zero (1) or remain unknown (0).
zte_adapter_uint_json() {
	_zte_uint_json_source=$1
	_zte_uint_json_field=$2
	_zte_uint_json_empty_zero=${3-0}
	if ! zte_json_flat_has "$_zte_uint_json_source" "$_zte_uint_json_field"; then
		printf 'null'
		return
	fi
	_zte_uint_json_value=$(zte_json_flat_get \
		"$_zte_uint_json_source" "$_zte_uint_json_field")
	if [ -z "$_zte_uint_json_value" ]; then
		if [ "$_zte_uint_json_empty_zero" = 1 ]; then
			printf '0'
		else
			printf 'null'
		fi
		return
	fi
	zte_is_uint "$_zte_uint_json_value" || return 1
	case $_zte_uint_json_value in
		0|[1-9]|[1-9][0-9]*) printf '%s' "$_zte_uint_json_value" ;;
		*) return 1 ;;
	esac
}

# Print a 0/1 device option as JSON false/true, or null when absent/empty.
zte_adapter_optional_bool_json() {
	if ! zte_json_flat_has "$1" "$2"; then
		printf 'null'
		return
	fi
	_zte_optional_bool_value=$(zte_json_flat_get "$1" "$2")
	case $_zte_optional_bool_value in
		'') printf 'null' ;;
		0) printf 'false' ;;
		1) printf 'true' ;;
		*) return 1 ;;
	esac
}

# Succeed when the response contains at least one known read field.
zte_adapter_has_any_field() {
	_zte_old_ifs=$IFS
	IFS=,
	for _zte_field in $ZTE_READ_FIELDS; do
		IFS=$_zte_old_ifs
		zte_json_flat_has "$1" "$_zte_field" && return 0
		IFS=,
	done
	IFS=$_zte_old_ifs
	return 1
}

# $1 host, $2 optional password, $3 cookie jar; prints raw flat device JSON.
# Probes first because some target firmware exposes status without login. A
# valid object without known fields requires authentication; return 2 when no
# password is available, otherwise log in and retry exactly once.
zte_adapter_fetch() {
	_zte_host=$1 _zte_password=$2 _zte_jar=$3
	_zte_origin=$(zte_adapter_origin "$_zte_host") || return 1
	_zte_url="$_zte_origin/goform/goform_get_cmd_process?cmd=$ZTE_READ_FIELDS&multi_data=1&isTest=false"

	_zte_resp=$(zte_http_get "$_zte_url" "$_zte_jar") || return 1
	zte_json_is_flat_object "$_zte_resp" || return 1
	if zte_adapter_has_any_field "$_zte_resp"; then
		printf '%s\n' "$_zte_resp"
		return 0
	fi

	zte_adapter_login_required || return 1
	[ -n "$_zte_password" ] || return 2
	zte_session_login "$_zte_origin" "$_zte_password" "$_zte_jar" || return 3
	_zte_resp=$(zte_http_get "$_zte_url" "$_zte_jar") || return 1
	zte_json_is_flat_object "$_zte_resp" || return 1
	if ! zte_adapter_has_any_field "$_zte_resp"; then
		zte_session_login "$_zte_origin" "$_zte_password" "$_zte_jar" ||
			return 3
		_zte_resp=$(zte_http_get "$_zte_url" "$_zte_jar") || return 1
		zte_json_is_flat_object "$_zte_resp" || return 1
		zte_adapter_has_any_field "$_zte_resp" || return 1
	fi
	printf '%s\n' "$_zte_resp"
}

zte_adapter_fetch_clients_once() {
	_zte_clients_host=$1
	_zte_clients_jar=$2
	_zte_clients_origin=$(zte_adapter_origin "$_zte_clients_host") || return 1
	_zte_clients_url="$_zte_clients_origin/goform/goform_get_cmd_process?cmd=station_list&isTest=false"
	_zte_clients_response=$(zte_http_get \
		"$_zte_clients_url" "$_zte_clients_jar") || return 1
	zte_json_normalize_station_list "$_zte_clients_response"
}

# $1 host, $2 optional password, $3 cookie jar; prints the bounded normalized
# station collection. Status 2 means credentials are absent, while status 3
# means LOGIN was attempted and rejected.
zte_adapter_fetch_clients() {
	_zte_clients_fetch_host=$1
	_zte_clients_fetch_password=$2
	_zte_clients_fetch_jar=$3

	if _zte_clients_normalized=$(zte_adapter_fetch_clients_once \
		"$_zte_clients_fetch_host" "$_zte_clients_fetch_jar"); then
		printf '%s\n' "$_zte_clients_normalized"
		return 0
	fi

	zte_adapter_login_required || return 1
	[ -n "$_zte_clients_fetch_password" ] || return 2
	zte_session_login "$_zte_clients_fetch_host" \
		"$_zte_clients_fetch_password" "$_zte_clients_fetch_jar" || return 3
	_zte_clients_normalized=$(zte_adapter_fetch_clients_once \
		"$_zte_clients_fetch_host" "$_zte_clients_fetch_jar") || return 1
	printf '%s\n' "$_zte_clients_normalized"
}

zte_adapter_clients_unavailable_json() {
	case ${1-} in
		not_loaded|credentials_missing|authentication_failed|authentication_backoff|read_failed)
			printf '{"available":false,"reason":"%s","items":[]}\n' "$1"
			;;
		*) return 1 ;;
	esac
}

# Rebuild rather than pass through a supplied collection. This keeps the
# normalized device snapshot valid even if an internal caller passes malformed
# or unexpectedly extended JSON.
zte_adapter_clients_json() {
	_zte_clients_json=${1-}
	[ "${#_zte_clients_json}" -le 262144 ] || return 1
	command -v jsonfilter >/dev/null 2>&1 || return 1
	_zte_clients_available=$(jsonfilter -s "$_zte_clients_json" \
		-e '@.available') || return 1
	[ "$_zte_clients_available" = true ] || return 1
	_zte_clients_items=$(jsonfilter -s "$_zte_clients_json" -e '@.items') ||
		return 1
	case $_zte_clients_items in
		\[*\]) ;;
		*) return 1 ;;
	esac
	printf '{"available":true,"items":%s}\n' "$_zte_clients_items"
}

zte_adapter_fetch_sms_once() {
	_zte_sms_host=$1
	_zte_sms_jar=$2
	_zte_sms_origin=$(zte_adapter_origin "$_zte_sms_host") || return 1
	_zte_sms_url="$_zte_sms_origin/goform/goform_get_cmd_process?cmd=sms_data_total&page=0&data_per_page=50&mem_store=1&tags=10&order_by=order%20by%20id%20desc&isTest=false"
	_zte_sms_response=$(zte_http_get "$_zte_sms_url" "$_zte_sms_jar") ||
		return 1
	zte_json_normalize_sms_messages "$_zte_sms_response"
}

# Read the 50 newest messages using the same inbox query contract as the
# target WebUI. Return codes match the private client collection contract.
zte_adapter_fetch_sms() {
	_zte_sms_fetch_host=$1
	_zte_sms_fetch_password=$2
	_zte_sms_fetch_jar=$3

	if _zte_sms_normalized=$(zte_adapter_fetch_sms_once \
		"$_zte_sms_fetch_host" "$_zte_sms_fetch_jar"); then
		printf '%s\n' "$_zte_sms_normalized"
		return 0
	fi

	zte_adapter_login_required || return 1
	[ -n "$_zte_sms_fetch_password" ] || return 2
	zte_session_login "$_zte_sms_fetch_host" \
		"$_zte_sms_fetch_password" "$_zte_sms_fetch_jar" || return 3
	_zte_sms_normalized=$(zte_adapter_fetch_sms_once \
		"$_zte_sms_fetch_host" "$_zte_sms_fetch_jar") || return 1
	printf '%s\n' "$_zte_sms_normalized"
}

zte_adapter_sms_unavailable_json() {
	case ${1-} in
		not_loaded|credentials_missing|authentication_failed|authentication_backoff|read_failed)
			printf '{"available":false,"reason":"%s","items":[]}\n' "$1"
			;;
		*) return 1 ;;
	esac
}

# Map the target firmware's visible SIM choices to the verified card_index
# values used by SIM_SWITCH_SIMCARD. The physical slot is index 0.
zte_adapter_sim_card_index() {
	case ${1-} in
		sim1) printf '1\n' ;;
		sim2) printf '2\n' ;;
		sim3) printf '3\n' ;;
		physical) printf '0\n' ;;
		*) return 1 ;;
	esac
}

# $1 host, $2 semantic SIM target, $3 cookie jar.
# This only emits the request shape observed in the target U25S UI. Production
# capability gating remains in metadata until a spare-device switch and
# operation readback have passed.
zte_adapter_switch_sim() {
	_zte_switch_host=$1
	_zte_switch_target=$2
	_zte_switch_jar=$3
	_zte_switch_index=$(
		zte_adapter_sim_card_index "$_zte_switch_target"
	) || return 1
	_zte_switch_origin=$(zte_adapter_origin "$_zte_switch_host") || return 1
	_zte_switch_url="$_zte_switch_origin/goform/goform_set_cmd_process"
	_zte_switch_response=$(
		zte_http_post "$_zte_switch_url" \
			"isTest=false&goformId=SIM_SWITCH_SIMCARD&card_index=$_zte_switch_index" \
			"$_zte_switch_jar"
	) || return 1
	zte_json_is_flat_object "$_zte_switch_response" || return 1
	[ "$(zte_json_flat_get "$_zte_switch_response" result)" = success ]
}

# $1 raw flat device JSON, $2 optional normalized client collection ->
# normalized device object on stdout.
# sim.active_slot_raw passes the firmware value through unmapped until the
# slot numbering is calibrated on the real device (see design doc 5.6).
zte_adapter_normalize() {
	_zte_raw=$1
	zte_json_is_flat_object "$_zte_raw" || return 1
	if [ "$#" -ge 2 ]; then
		_zte_clients=$(zte_adapter_clients_json "$2") || return 1
	else
		_zte_clients=$(zte_adapter_clients_unavailable_json not_loaded) ||
			return 1
	fi

	_zte_modem_state=$(zte_json_flat_get "$_zte_raw" mc_modem_main_state)
	_zte_net_type=$(zte_json_flat_get "$_zte_raw" network_type)
	_zte_signalbar=$(zte_json_flat_get "$_zte_raw" network_signalbar)
	_zte_provider=$(zte_json_flat_get "$_zte_raw" network_provider_fullname)
	_zte_rsrp=$(zte_json_flat_get "$_zte_raw" Z5g_rsrp)
	_zte_lte_rsrp=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" network_lte_rsrp)
	_zte_rscp=$(zte_adapter_json_nonempty_field "$_zte_raw" network_rscp)
	_zte_rssi=$(zte_adapter_json_nonempty_field "$_zte_raw" lte_rssi)
	_zte_roaming=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" network_simcard_roam)
	_zte_dial_mode=$(zte_adapter_json_nonempty_field "$_zte_raw" dial_mode)
	_zte_wan_mode=$(zte_adapter_json_nonempty_field "$_zte_raw" opms_wan_mode)
	_zte_connection_mode=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" ConnectionMode)
	if [ "$_zte_connection_mode" = null ]; then
		_zte_connection_mode=$(zte_adapter_json_nonempty_field \
			"$_zte_raw" connectionMode)
	fi
	_zte_auto_roaming=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" autoConnectWhenRoaming)
	_zte_network_mode=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" network_current_network_mode)
	_zte_network_selection=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" network_net_select_mode)
	_zte_snr=$(zte_adapter_json_nonempty_field "$_zte_raw" Z5g_snr)
	_zte_sinr=$(zte_adapter_json_nonempty_field "$_zte_raw" Z5g_SINR)
	_zte_ca=$(zte_adapter_json_nonempty_field "$_zte_raw" wan_lte_ca)
	_zte_primary_band=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" network_lte_ca_pcell_band)
	_zte_primary_bandwidth=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" bandwidth)
	_zte_secondary_band=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" network_lte_ca_scell_band)
	_zte_secondary_bandwidth=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" network_lte_ca_scell_bandwidth)
	_zte_primary_arfcn=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" network_lte_ca_pcell_arfcn)
	_zte_secondary_arfcn=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" lte_ca_scell_arfcn)
	_zte_active_band=$(zte_adapter_json_nonempty_field "$_zte_raw" wan_active_band)
	_zte_pdp_ipv4=$(zte_adapter_json_nonempty_field "$_zte_raw" apn_pdp_type)
	_zte_pdp_ipv6=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" apn_ipv6_pdp_type)
	_zte_mcc=$(zte_adapter_json_nonempty_field "$_zte_raw" network_rmcc)
	_zte_mnc=$(zte_adapter_json_nonempty_field "$_zte_raw" network_rmnc)
	_zte_ppp=$(zte_json_flat_get "$_zte_raw" ppp_status)
	_zte_wifi_enabled=$(zte_adapter_optional_bool_json \
		"$_zte_raw" wifi_onoff_state) || return 1
	_zte_wifi_guest=$(zte_adapter_optional_bool_json \
		"$_zte_raw" guest_switch) || return 1
	_zte_wifi_24_ssid=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" wifi_chip1_ssid1_ssid)
	_zte_wifi_24_auth=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" wifi_chip1_ssid1_auth_mode)
	_zte_wifi_24_clients=$(zte_adapter_uint_json \
		"$_zte_raw" wifi_chip1_ssid1_access_sta_num 0) || return 1
	_zte_wifi_5_ssid=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" wifi_chip2_ssid1_ssid)
	_zte_wifi_5_auth=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" wifi_chip2_ssid1_auth_mode)
	_zte_wifi_5_clients=$(zte_adapter_uint_json \
		"$_zte_raw" wifi_chip2_ssid1_access_sta_num 0) || return 1
	_zte_wifi_radio_off=$(zte_adapter_json_nonempty_field "$_zte_raw" RadioOff)
	_zte_wifi_primary_ssid=$(zte_adapter_json_nonempty_field "$_zte_raw" SSID1)
	_zte_wifi_primary_auth=$(zte_adapter_json_nonempty_field "$_zte_raw" AuthMode)
	_zte_wifi_primary_hidden=$(zte_adapter_json_nonempty_field "$_zte_raw" HideSSID)
	_zte_wifi_primary_max=$(zte_adapter_json_nonempty_field "$_zte_raw" MAX_Access_num)
	_zte_wifi_primary_isolation=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" NoForwarding)
	_zte_wifi_guest_raw=$(zte_adapter_json_nonempty_field "$_zte_raw" m_ssid_enable)
	_zte_wifi_guest_ssid=$(zte_adapter_json_nonempty_field "$_zte_raw" m_SSID)
	_zte_wifi_guest_auth=$(zte_adapter_json_nonempty_field "$_zte_raw" m_AuthMode)
	_zte_wifi_guest_hidden=$(zte_adapter_json_nonempty_field "$_zte_raw" m_HideSSID)
	_zte_wifi_guest_max=$(zte_adapter_json_nonempty_field "$_zte_raw" m_MAX_Access_num)
	_zte_wifi_guest_isolation=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" m_NoForwarding)
	_zte_wifi_mode=$(zte_adapter_json_nonempty_field "$_zte_raw" WirelessMode)
	_zte_wifi_country=$(zte_adapter_json_nonempty_field "$_zte_raw" CountryCode)
	_zte_wifi_channel=$(zte_adapter_json_nonempty_field "$_zte_raw" Channel)
	_zte_wifi_bandwidth=$(zte_adapter_json_nonempty_field "$_zte_raw" wifi_11n_cap)
	_zte_wifi_coverage=$(zte_adapter_json_nonempty_field "$_zte_raw" wifi_coverage)
	_zte_wifi_sleep=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" SleepStatusForSingleChipCpe)
	_zte_slot=$(zte_adapter_json_field "$_zte_raw" simcard_active_slot_temp)
	_zte_sim_type=$(zte_adapter_json_field "$_zte_raw" usim_esim_type)
	_zte_battery_value=$(zte_adapter_json_field "$_zte_raw" battery_value)
	_zte_battery_pers=$(zte_adapter_json_field "$_zte_raw" battery_pers)
	_zte_temperature_level=$(
		zte_adapter_json_field "$_zte_raw" battery_temperature_level
	)
	_zte_firmware=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" wa_inner_version)
	_zte_hardware_version=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" hardware_version)
	_zte_webui_version=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" web_version)
	_zte_software_version=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" wa_version)
	_zte_market_name=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" device_market_name)
	_zte_new_version_state=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" new_version_state)
	_zte_current_upgrade_state=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" current_upgrade_state)
	_zte_realtime_tx=$(zte_adapter_uint_json \
		"$_zte_raw" flux_realtime_tx_thrpt 1) || return 1
	_zte_realtime_rx=$(zte_adapter_uint_json \
		"$_zte_raw" flux_realtime_rx_thrpt 1) || return 1
	_zte_current_tx=$(zte_adapter_uint_json \
		"$_zte_raw" flux_realtime_tx_bytes 1) || return 1
	_zte_current_rx=$(zte_adapter_uint_json \
		"$_zte_raw" flux_realtime_rx_bytes 1) || return 1
	_zte_current_time=$(zte_adapter_uint_json \
		"$_zte_raw" flux_realtime_time 1) || return 1
	_zte_monthly_tx=$(zte_adapter_uint_json \
		"$_zte_raw" flux_monthly_tx_bytes 1) || return 1
	_zte_monthly_rx=$(zte_adapter_uint_json \
		"$_zte_raw" flux_monthly_rx_bytes 1) || return 1
	_zte_monthly_time=$(zte_adapter_uint_json \
		"$_zte_raw" flux_monthly_time 1) || return 1
	_zte_month=$(zte_adapter_json_nonempty_field "$_zte_raw" date_month)
	_zte_plan_enabled=$(zte_adapter_optional_bool_json \
		"$_zte_raw" flux_data_volume_limit_switch) || return 1
	_zte_plan_unit=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" flux_data_volume_limit_unit)
	_zte_plan_limit=$(zte_adapter_json_nonempty_field \
		"$_zte_raw" flux_data_volume_limit_size)
	_zte_plan_alert=$(zte_adapter_uint_json \
		"$_zte_raw" flux_data_volume_alert_percent 0) || return 1
	_zte_plan_auto_clear=$(zte_adapter_optional_bool_json \
		"$_zte_raw" flux_auto_clear_flow_data_switch) || return 1
	_zte_plan_clear_day=$(zte_adapter_uint_json \
		"$_zte_raw" flux_clear_date 0) || return 1
	_zte_plan_disconnect=$(zte_adapter_optional_bool_json \
		"$_zte_raw" flux_limited_disconnect) || return 1

	if zte_json_flat_has "$_zte_raw" battery_exist; then
		_zte_present_raw=$(zte_json_flat_get "$_zte_raw" battery_exist)
		case $_zte_present_raw in
			1|true|yes|0|false|no) ;;
			'')
				if [ "${ZTE_ADAPTER_ID:-}" = zte_u30 ] &&
					zte_json_flat_has "$_zte_raw" battery_vol_percent; then
					_zte_present=true
				else
					return 1
				fi
				;;
			*) return 1 ;;
		esac
		if [ "$_zte_present_raw" != '' ]; then
			_zte_present=$(zte_adapter_bool "$_zte_present_raw")
		fi
	else
		_zte_present=null
	fi

	if zte_json_flat_has "$_zte_raw" battery_charging; then
		_zte_charging_raw=$(zte_json_flat_get "$_zte_raw" battery_charging)
		_zte_charging=$(
			zte_adapter_charging_bool "$_zte_charging_raw"
		) || return 1
	else
		_zte_charging=null
	fi

	if zte_json_flat_has "$_zte_raw" battery_vol_percent; then
		_zte_percent_raw=$(zte_json_flat_get "$_zte_raw" battery_vol_percent)
		case $_zte_percent_raw in
			0|[1-9]|[1-9][0-9]|100) ;;
			*) return 1 ;;
		esac
		_zte_percent=$_zte_percent_raw
	else
		_zte_percent=null
	fi

	if zte_json_flat_has "$_zte_raw" sms_data_total; then
		_zte_sms_total_raw=$(zte_json_flat_get "$_zte_raw" sms_data_total)
		if [ -z "$_zte_sms_total_raw" ]; then
			_zte_sms_total=null
		else
			zte_is_uint "$_zte_sms_total_raw" || return 1
			case $_zte_sms_total_raw in
				0|[1-9]|[1-9][0-9]*) ;;
				*) return 1 ;;
			esac
			_zte_sms_total=$_zte_sms_total_raw
		fi
	else
		_zte_sms_total=null
	fi

	_zte_missing=''
	_zte_old_ifs=$IFS
	IFS=,
	for _zte_field in $ZTE_READ_FIELDS; do
		IFS=$_zte_old_ifs
		zte_json_flat_has "$_zte_raw" "$_zte_field" ||
			_zte_missing=${_zte_missing:+$_zte_missing,}$_zte_field
		IFS=,
	done
	IFS=$_zte_old_ifs

	printf '{"online":true,"adapter":"%s","model":"%s","firmware":%s,"hardware_version":%s,"webui_version":%s,"software_version":%s,"market_name":%s,"upgrade":{"new_version_state":%s,"current_state":%s},"modem_state":"%s","cellular":{"type":"%s","provider":"%s","signalbar":"%s","rsrp":"%s","lte_rsrp":%s,"rscp":%s,"rssi":%s,"roaming":%s,"dial_mode":%s,"wan_mode":%s,"connection_mode":%s,"auto_roaming_raw":%s,"network_mode_raw":%s,"network_selection_mode_raw":%s,"radio":{"snr_raw":%s,"sinr_raw":%s,"ca_state_raw":%s,"primary_band_raw":%s,"primary_bandwidth_raw":%s,"secondary_band_raw":%s,"secondary_bandwidth_raw":%s,"primary_arfcn_raw":%s,"secondary_arfcn_raw":%s,"active_band_raw":%s},"pdp":{"ipv4_type_raw":%s,"ipv6_type_raw":%s},"mcc":%s,"mnc":%s,"ppp_status":"%s"},"sim":{"active_slot_raw":%s,"type":%s},"wifi":{"enabled":%s,"guest_enabled":%s,"bands":{"wifi_2_4":{"ssid":%s,"auth_mode":%s,"clients":%s},"wifi_5":{"ssid":%s,"auth_mode":%s,"clients":%s}},"radio_off_raw":%s,"primary":{"ssid":%s,"auth_mode":%s,"hidden_raw":%s,"max_clients_raw":%s,"isolation_raw":%s},"guest":{"enabled_raw":%s,"ssid":%s,"auth_mode":%s,"hidden_raw":%s,"max_clients_raw":%s,"isolation_raw":%s},"advanced":{"mode_raw":%s,"country_raw":%s,"channel_raw":%s,"bandwidth_raw":%s,"coverage_raw":%s},"sleep_status_raw":%s},"clients":%s,"battery":{"present":%s,"percent":%s,"charging":%s,"value":%s,"pers":%s,"temperature_level":%s},"traffic":{"realtime":{"upload_bps":%s,"download_bps":%s},"current":{"sent_bytes":%s,"received_bytes":%s,"connected_seconds":%s},"monthly":{"sent_bytes":%s,"received_bytes":%s,"connected_seconds":%s,"month":%s},"plan":{"enabled":%s,"unit":%s,"limit":%s,"alert_percent":%s,"auto_clear":%s,"clear_day":%s,"disconnect":%s}},"sms":{"total":%s},"missing":"%s"}\n' \
		"$ZTE_ADAPTER_ID" "$ZTE_ADAPTER_MODEL" "$_zte_firmware" \
		"$_zte_hardware_version" "$_zte_webui_version" \
		"$_zte_software_version" "$_zte_market_name" \
		"$_zte_new_version_state" "$_zte_current_upgrade_state" \
		"$(zte_json_escape "$_zte_modem_state")" \
		"$(zte_json_escape "$_zte_net_type")" \
		"$(zte_json_escape "$_zte_provider")" \
		"$(zte_json_escape "$_zte_signalbar")" \
		"$(zte_json_escape "$_zte_rsrp")" \
		"$_zte_lte_rsrp" "$_zte_rscp" "$_zte_rssi" "$_zte_roaming" \
		"$_zte_dial_mode" "$_zte_wan_mode" \
		"$_zte_connection_mode" "$_zte_auto_roaming" \
		"$_zte_network_mode" "$_zte_network_selection" \
		"$_zte_snr" "$_zte_sinr" "$_zte_ca" "$_zte_primary_band" \
		"$_zte_primary_bandwidth" "$_zte_secondary_band" \
		"$_zte_secondary_bandwidth" "$_zte_primary_arfcn" \
		"$_zte_secondary_arfcn" "$_zte_active_band" \
		"$_zte_pdp_ipv4" "$_zte_pdp_ipv6" \
		"$_zte_mcc" "$_zte_mnc" \
		"$(zte_json_escape "$_zte_ppp")" \
		"$_zte_slot" "$_zte_sim_type" \
		"$_zte_wifi_enabled" "$_zte_wifi_guest" \
		"$_zte_wifi_24_ssid" "$_zte_wifi_24_auth" "$_zte_wifi_24_clients" \
		"$_zte_wifi_5_ssid" "$_zte_wifi_5_auth" "$_zte_wifi_5_clients" \
		"$_zte_wifi_radio_off" \
		"$_zte_wifi_primary_ssid" "$_zte_wifi_primary_auth" \
		"$_zte_wifi_primary_hidden" "$_zte_wifi_primary_max" \
		"$_zte_wifi_primary_isolation" \
		"$_zte_wifi_guest_raw" "$_zte_wifi_guest_ssid" \
		"$_zte_wifi_guest_auth" "$_zte_wifi_guest_hidden" \
		"$_zte_wifi_guest_max" "$_zte_wifi_guest_isolation" \
		"$_zte_wifi_mode" "$_zte_wifi_country" "$_zte_wifi_channel" \
		"$_zte_wifi_bandwidth" "$_zte_wifi_coverage" "$_zte_wifi_sleep" \
		"$_zte_clients" \
		"$_zte_present" "$_zte_percent" "$_zte_charging" \
		"$_zte_battery_value" "$_zte_battery_pers" "$_zte_temperature_level" \
		"$_zte_realtime_tx" "$_zte_realtime_rx" \
		"$_zte_current_tx" "$_zte_current_rx" "$_zte_current_time" \
		"$_zte_monthly_tx" "$_zte_monthly_rx" "$_zte_monthly_time" \
		"$_zte_month" "$_zte_plan_enabled" "$_zte_plan_unit" \
		"$_zte_plan_limit" "$_zte_plan_alert" "$_zte_plan_auto_clear" \
		"$_zte_plan_clear_day" "$_zte_plan_disconnect" \
		"$_zte_sms_total" \
		"$(zte_json_escape "$_zte_missing")"
}
