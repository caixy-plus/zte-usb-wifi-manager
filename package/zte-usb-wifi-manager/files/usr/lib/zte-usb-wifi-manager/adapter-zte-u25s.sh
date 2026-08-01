#!/bin/sh

# Map a device flag string to JSON true/false/null.
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
	_zte_url="http://$_zte_host/goform/goform_get_cmd_process?cmd=$ZTE_READ_FIELDS&multi_data=1&isTest=false"

	_zte_resp=$(zte_http_get "$_zte_url" "$_zte_jar") || return 1
	zte_json_is_flat_object "$_zte_resp" || return 1
	if zte_adapter_has_any_field "$_zte_resp"; then
		printf '%s\n' "$_zte_resp"
		return 0
	fi

	zte_adapter_login_required || return 1
	[ -n "$_zte_password" ] || return 2
	zte_session_login "$_zte_host" "$_zte_password" "$_zte_jar" || return 1
	_zte_resp=$(zte_http_get "$_zte_url" "$_zte_jar") || return 1
	zte_json_is_flat_object "$_zte_resp" || return 1
	if ! zte_adapter_has_any_field "$_zte_resp"; then
		zte_session_login "$_zte_host" "$_zte_password" "$_zte_jar" ||
			return 1
		_zte_resp=$(zte_http_get "$_zte_url" "$_zte_jar") || return 1
		zte_json_is_flat_object "$_zte_resp" || return 1
		zte_adapter_has_any_field "$_zte_resp" || return 1
	fi
	printf '%s\n' "$_zte_resp"
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
	_zte_switch_url="http://$_zte_switch_host/goform/goform_set_cmd_process"
	_zte_switch_response=$(
		zte_http_post "$_zte_switch_url" \
			"isTest=false&goformId=SIM_SWITCH_SIMCARD&card_index=$_zte_switch_index" \
			"$_zte_switch_jar"
	) || return 1
	zte_json_is_flat_object "$_zte_switch_response" || return 1
	[ "$(zte_json_flat_get "$_zte_switch_response" result)" = success ]
}

# $1 raw flat device JSON -> normalized device object on stdout.
# sim.active_slot_raw passes the firmware value through unmapped until the
# slot numbering is calibrated on the real device (see design doc 5.6).
zte_adapter_normalize() {
	_zte_raw=$1
	zte_json_is_flat_object "$_zte_raw" || return 1

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
			*) return 1 ;;
		esac
		_zte_present=$(zte_adapter_bool "$_zte_present_raw")
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

	printf '{"online":true,"model":"%s","firmware":%s,"hardware_version":%s,"webui_version":%s,"software_version":%s,"market_name":%s,"upgrade":{"new_version_state":%s,"current_state":%s},"modem_state":"%s","cellular":{"type":"%s","provider":"%s","signalbar":"%s","rsrp":"%s","lte_rsrp":%s,"rscp":%s,"rssi":%s,"roaming":%s,"dial_mode":%s,"wan_mode":%s,"mcc":%s,"mnc":%s,"ppp_status":"%s"},"sim":{"active_slot_raw":%s,"type":%s},"wifi":{"enabled":%s,"guest_enabled":%s,"bands":{"wifi_2_4":{"ssid":%s,"auth_mode":%s,"clients":%s},"wifi_5":{"ssid":%s,"auth_mode":%s,"clients":%s}}},"battery":{"present":%s,"percent":%s,"charging":%s,"value":%s,"pers":%s,"temperature_level":%s},"traffic":{"realtime":{"upload_bps":%s,"download_bps":%s},"current":{"sent_bytes":%s,"received_bytes":%s,"connected_seconds":%s},"monthly":{"sent_bytes":%s,"received_bytes":%s,"connected_seconds":%s,"month":%s},"plan":{"enabled":%s,"unit":%s,"limit":%s,"alert_percent":%s,"auto_clear":%s,"clear_day":%s,"disconnect":%s}},"sms":{"total":%s},"missing":"%s"}\n' \
		"$ZTE_ADAPTER_MODEL" "$_zte_firmware" \
		"$_zte_hardware_version" "$_zte_webui_version" \
		"$_zte_software_version" "$_zte_market_name" \
		"$_zte_new_version_state" "$_zte_current_upgrade_state" \
		"$(zte_json_escape "$_zte_modem_state")" \
		"$(zte_json_escape "$_zte_net_type")" \
		"$(zte_json_escape "$_zte_provider")" \
		"$(zte_json_escape "$_zte_signalbar")" \
		"$(zte_json_escape "$_zte_rsrp")" \
		"$_zte_lte_rsrp" "$_zte_rscp" "$_zte_rssi" "$_zte_roaming" \
		"$_zte_dial_mode" "$_zte_wan_mode" "$_zte_mcc" "$_zte_mnc" \
		"$(zte_json_escape "$_zte_ppp")" \
		"$_zte_slot" "$_zte_sim_type" \
		"$_zte_wifi_enabled" "$_zte_wifi_guest" \
		"$_zte_wifi_24_ssid" "$_zte_wifi_24_auth" "$_zte_wifi_24_clients" \
		"$_zte_wifi_5_ssid" "$_zte_wifi_5_auth" "$_zte_wifi_5_clients" \
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
