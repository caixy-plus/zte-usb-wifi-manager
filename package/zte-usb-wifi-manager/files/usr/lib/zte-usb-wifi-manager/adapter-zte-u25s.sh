#!/bin/sh

# Map a device flag string to JSON true/false/null.
zte_adapter_bool() {
	case ${1-} in
		1|true|yes) printf 'true' ;;
		0|false|no) printf 'false' ;;
		*) printf 'null' ;;
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

	[ -n "$_zte_password" ] || return 2
	zte_session_login "$_zte_host" "$_zte_password" "$_zte_jar" || return 1
	_zte_resp=$(zte_http_get "$_zte_url" "$_zte_jar") || return 1
	zte_json_is_flat_object "$_zte_resp" || return 1
	zte_adapter_has_any_field "$_zte_resp" || return 1
	printf '%s\n' "$_zte_resp"
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
	_zte_ppp=$(zte_json_flat_get "$_zte_raw" ppp_status)
	_zte_slot=$(zte_adapter_json_field "$_zte_raw" simcard_active_slot_temp)
	_zte_sim_type=$(zte_adapter_json_field "$_zte_raw" usim_esim_type)
	_zte_battery_value=$(zte_adapter_json_field "$_zte_raw" battery_value)
	_zte_battery_pers=$(zte_adapter_json_field "$_zte_raw" battery_pers)
	_zte_temperature_level=$(
		zte_adapter_json_field "$_zte_raw" battery_temperature_level
	)

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
		case $_zte_charging_raw in
			1|true|yes|0|false|no) ;;
			*) return 1 ;;
		esac
		_zte_charging=$(zte_adapter_bool "$_zte_charging_raw")
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

	printf '{"online":true,"model":"%s","modem_state":"%s","cellular":{"type":"%s","provider":"%s","signalbar":"%s","rsrp":"%s","ppp_status":"%s"},"sim":{"active_slot_raw":%s,"type":%s},"battery":{"present":%s,"percent":%s,"charging":%s,"value":%s,"pers":%s,"temperature_level":%s},"sms":{"total":%s},"missing":"%s"}\n' \
		"$ZTE_ADAPTER_MODEL" \
		"$(zte_json_escape "$_zte_modem_state")" \
		"$(zte_json_escape "$_zte_net_type")" \
		"$(zte_json_escape "$_zte_provider")" \
		"$(zte_json_escape "$_zte_signalbar")" \
		"$(zte_json_escape "$_zte_rsrp")" \
		"$(zte_json_escape "$_zte_ppp")" \
		"$_zte_slot" "$_zte_sim_type" \
		"$_zte_present" "$_zte_percent" "$_zte_charging" \
		"$_zte_battery_value" "$_zte_battery_pers" "$_zte_temperature_level" \
		"$_zte_sms_total" \
		"$(zte_json_escape "$_zte_missing")"
}
