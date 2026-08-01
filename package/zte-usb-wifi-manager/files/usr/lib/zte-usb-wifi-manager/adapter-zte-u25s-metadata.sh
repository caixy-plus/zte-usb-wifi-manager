#!/bin/sh

# Static device metadata is kept separate so rpcd can expose read-only
# capabilities without loading the HTTP and session implementation.
ZTE_ADAPTER_ID=zte_u25s
ZTE_ADAPTER_MODEL=U25S

# The current target firmware's published WebUI config declares HAS_LOGIN:true
# and PASSWORD_ENCODE:true. Anonymous reads are still probed first, but every
# write must have an authenticated session.
ZTE_LOGIN_REQUIRED=1

# Write capabilities remain disabled until their request parameters and
# recovery behavior have been calibrated on the target firmware.
ZTE_CAP_SIM_SWITCH=0
ZTE_CAP_CELLULAR_WRITE=0
ZTE_CAP_WIFI_WRITE=0
ZTE_CAP_TRAFFIC_WRITE=0
ZTE_CAP_SMS_WRITE=0

ZTE_READ_FIELDS='mc_modem_main_state,network_type,network_signalbar,network_provider_fullname,Z5g_rsrp,ppp_status,simcard_active_slot_temp,usim_esim_type,battery_exist,battery_vol_percent,battery_charging,battery_value,battery_pers,battery_temperature_level,sms_data_total'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',network_lte_rsrp,network_rscp,lte_rssi,network_simcard_roam,dial_mode,opms_wan_mode,network_rmcc,network_rmnc'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',wifi_onoff_state,guest_switch,wifi_chip1_ssid1_ssid,wifi_chip1_ssid1_auth_mode,wifi_chip1_ssid1_access_sta_num'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',wifi_chip2_ssid1_ssid,wifi_chip2_ssid1_auth_mode,wifi_chip2_ssid1_access_sta_num'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',hardware_version,web_version,wa_version,device_market_name,new_version_state,current_upgrade_state'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',wa_inner_version,flux_realtime_tx_thrpt,flux_realtime_rx_thrpt,flux_realtime_tx_bytes,flux_realtime_rx_bytes,flux_realtime_time'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',flux_monthly_tx_bytes,flux_monthly_rx_bytes,flux_monthly_time,date_month,flux_data_volume_limit_switch,flux_data_volume_limit_unit'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',flux_data_volume_limit_size,flux_data_volume_alert_percent,flux_auto_clear_flow_data_switch,flux_clear_date,flux_limited_disconnect'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',ConnectionMode,autoConnectWhenRoaming,network_current_network_mode,network_net_select_mode'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',RadioOff,SSID1,AuthMode,HideSSID,MAX_Access_num,NoForwarding,m_ssid_enable,m_SSID,m_AuthMode,m_HideSSID,m_MAX_Access_num,m_NoForwarding'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',WirelessMode,CountryCode,Channel,wifi_11n_cap,wifi_coverage,SleepStatusForSingleChipCpe'

# These variables are the sourced adapter contract and are consumed by other
# library files after this metadata file returns.
: "$ZTE_ADAPTER_ID" "$ZTE_ADAPTER_MODEL" "$ZTE_CAP_SIM_SWITCH"
: "$ZTE_CAP_CELLULAR_WRITE" "$ZTE_CAP_WIFI_WRITE" "$ZTE_CAP_SMS_WRITE"
: "$ZTE_CAP_TRAFFIC_WRITE"
: "$ZTE_LOGIN_REQUIRED" "$ZTE_READ_FIELDS"

zte_adapter_login_required() {
	[ "$ZTE_LOGIN_REQUIRED" = 1 ]
}

zte_adapter_capability_bool() {
	if [ "${1-}" = 1 ]; then
		printf '%s' true
	else
		printf '%s' false
	fi
}

zte_adapter_effective_capability_bool() {
	if [ "${1-}" = 1 ] && [ "${2-}" = 1 ] && [ "${3-}" = 1 ]; then
		printf '%s' true
	else
		printf '%s' false
	fi
}

zte_adapter_effective_capabilities_json() {
	_zte_metadata_write_enabled=${1-0}
	_zte_metadata_sim_enabled=${2-0}
	_zte_metadata_cellular_enabled=${3-0}
	_zte_metadata_wifi_enabled=${4-0}
	_zte_metadata_traffic_enabled=${5-0}
	_zte_metadata_sms_enabled=${6-0}
	if zte_adapter_login_required; then
		_zte_metadata_login_required=true
	else
		_zte_metadata_login_required=false
	fi
	printf '{"adapter":"zte_u25s","model":"U25S","login_required":%s,"read_status":true,"sim_switch":%s,"cellular_write":%s,"wifi_write":%s,"traffic_write":%s,"sms_write":%s}\n' \
		"$_zte_metadata_login_required" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_SIM_SWITCH" "$_zte_metadata_write_enabled" "$_zte_metadata_sim_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_CELLULAR_WRITE" "$_zte_metadata_write_enabled" "$_zte_metadata_cellular_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_WIFI_WRITE" "$_zte_metadata_write_enabled" "$_zte_metadata_wifi_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_TRAFFIC_WRITE" "$_zte_metadata_write_enabled" "$_zte_metadata_traffic_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_SMS_WRITE" "$_zte_metadata_write_enabled" "$_zte_metadata_sms_enabled")"
}

zte_adapter_capabilities_json() {
	zte_adapter_effective_capabilities_json 1 1 1 1 1 1
}

zte_adapter_action_supported() {
	case ${1-} in
		switch_sim) [ "$ZTE_CAP_SIM_SWITCH" = 1 ] ;;
		set_apn|set_connection_mode) [ "$ZTE_CAP_CELLULAR_WRITE" = 1 ] ;;
		set_wifi) [ "$ZTE_CAP_WIFI_WRITE" = 1 ] ;;
		set_traffic_plan|reset_traffic) [ "$ZTE_CAP_TRAFFIC_WRITE" = 1 ] ;;
		send_sms|delete_sms|mark_sms_read) [ "$ZTE_CAP_SMS_WRITE" = 1 ] ;;
		*) return 1 ;;
	esac
}

zte_adapter_action_effectively_enabled() {
	_zte_metadata_action=${1-}
	_zte_metadata_write_enabled=${2-}
	_zte_metadata_feature_enabled=${3-}

	[ "$_zte_metadata_write_enabled" = 1 ] || return 1
	zte_adapter_action_supported "$_zte_metadata_action" || return 1
	[ "$_zte_metadata_feature_enabled" = 1 ]
}

zte_adapter_action_feature_option() {
	case ${1-} in
		switch_sim) printf '%s\n' sim_switch_enabled ;;
		set_apn|set_connection_mode) printf '%s\n' cellular_write_enabled ;;
		set_wifi) printf '%s\n' wifi_write_enabled ;;
		set_traffic_plan|reset_traffic) printf '%s\n' traffic_write_enabled ;;
		send_sms|delete_sms|mark_sms_read) printf '%s\n' sms_write_enabled ;;
		*) return 1 ;;
	esac
}

zte_adapter_action_payload_valid() {
	_zte_metadata_action=${1-}
	_zte_metadata_payload=${2-}
	case $_zte_metadata_action in
		switch_sim)
			_zte_metadata_target=$(
				zte_json_flat_get "$_zte_metadata_payload" target
			)
			case $_zte_metadata_target in
				sim1|sim2|sim3|physical) return 0 ;;
				*) return 1 ;;
			esac
			;;
		*) return 1 ;;
	esac
}

zte_adapter_framework_status_json() {
	printf '%s\n' \
		'{"online":false,"model":"U25S","state":"framework_ready","reason":"device_polling_not_configured"}'
}
