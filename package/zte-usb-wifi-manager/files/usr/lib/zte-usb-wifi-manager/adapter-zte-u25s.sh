#!/bin/sh

ZTE_ADAPTER_ID=zte_u25s
ZTE_ADAPTER_MODEL=U25S

# Write capabilities remain disabled until their request parameters and
# recovery behavior have been calibrated on the target firmware.
ZTE_CAP_SIM_SWITCH=0
ZTE_CAP_CELLULAR_WRITE=0
ZTE_CAP_WIFI_WRITE=0
ZTE_CAP_SMS_WRITE=0

ZTE_READ_FIELDS='mc_modem_main_state,network_type,network_signalbar,network_provider_fullname,Z5g_rsrp,ppp_status,simcard_active_slot_temp,battery_exist,battery_vol_percent,battery_charging'

zte_adapter_capabilities_json() {
	printf '%s\n' \
		'{"adapter":"zte_u25s","model":"U25S","read_status":true,"sim_switch":false,"cellular_write":false,"wifi_write":false,"sms_write":false}'
}

zte_adapter_framework_status_json() {
	printf '%s\n' \
		'{"online":false,"model":"U25S","state":"framework_ready","reason":"device_polling_not_configured"}'
}

# Map a device flag string to JSON true/false/null.
zte_adapter_bool() {
	case ${1-} in
		1|true|yes) printf 'true' ;;
		0|false|no) printf 'false' ;;
		*) printf 'null' ;;
	esac
}

# Succeed when the response contains at least one known read field.
zte_adapter_has_any_field() {
	case $1 in
		*'"mc_modem_main_state":'*|*'"network_type":'*|*'"network_signalbar":'*|\
		*'"network_provider_fullname":'*|*'"Z5g_rsrp":'*|*'"ppp_status":'*|\
		*'"simcard_active_slot_temp":'*|*'"battery_exist":'*|\
		*'"battery_vol_percent":'*|*'"battery_charging":'*) return 0 ;;
	esac
	return 1
}

# $1 host, $2 password, $3 cookie jar; prints raw flat device JSON.
# Logs in when the jar is empty; on a stale session (object without any
# known field) relogs in and retries exactly once.
zte_adapter_fetch() {
	_zte_host=$1 _zte_password=$2 _zte_jar=$3
	_zte_url="http://$_zte_host/goform/goform_get_cmd_process?cmd=$ZTE_READ_FIELDS&multi_data=1&isTest=false"

	if [ ! -s "$_zte_jar" ]; then
		zte_session_login "$_zte_host" "$_zte_password" "$_zte_jar" || return 1
	fi
	_zte_resp=$(zte_http_get "$_zte_url" "$_zte_jar") || return 1
	zte_json_is_flat_object "$_zte_resp" || return 1
	if ! zte_adapter_has_any_field "$_zte_resp"; then
		zte_session_login "$_zte_host" "$_zte_password" "$_zte_jar" || return 1
		_zte_resp=$(zte_http_get "$_zte_url" "$_zte_jar") || return 1
		zte_json_is_flat_object "$_zte_resp" || return 1
		zte_adapter_has_any_field "$_zte_resp" || return 1
	fi
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
	_zte_slot=$(zte_json_flat_get "$_zte_raw" simcard_active_slot_temp)
	_zte_present=$(zte_adapter_bool "$(zte_json_flat_get "$_zte_raw" battery_exist)")
	_zte_charging=$(zte_adapter_bool "$(zte_json_flat_get "$_zte_raw" battery_charging)")
	_zte_percent_raw=$(zte_json_flat_get "$_zte_raw" battery_vol_percent)
	if zte_is_uint "$_zte_percent_raw"; then _zte_percent=$_zte_percent_raw; else _zte_percent=null; fi

	_zte_missing=''
	_zte_old_ifs=$IFS
	IFS=,
	for _zte_field in $ZTE_READ_FIELDS; do
		IFS=$_zte_old_ifs
		case $_zte_raw in
			*"\"$_zte_field\":"*) ;;
			*) _zte_missing=${_zte_missing:+$_zte_missing,}$_zte_field ;;
		esac
		IFS=,
	done
	IFS=$_zte_old_ifs

	printf '{"online":true,"model":"%s","modem_state":"%s","cellular":{"type":"%s","provider":"%s","signalbar":"%s","rsrp":"%s","ppp_status":"%s"},"sim":{"active_slot_raw":"%s"},"battery":{"present":%s,"percent":%s,"charging":%s},"missing":"%s"}\n' \
		"$ZTE_ADAPTER_MODEL" \
		"$(zte_json_escape "$_zte_modem_state")" \
		"$(zte_json_escape "$_zte_net_type")" \
		"$(zte_json_escape "$_zte_provider")" \
		"$(zte_json_escape "$_zte_signalbar")" \
		"$(zte_json_escape "$_zte_rsrp")" \
		"$(zte_json_escape "$_zte_ppp")" \
		"$(zte_json_escape "$_zte_slot")" \
		"$_zte_present" "$_zte_percent" "$_zte_charging" \
		"$(zte_json_escape "$_zte_missing")"
}
