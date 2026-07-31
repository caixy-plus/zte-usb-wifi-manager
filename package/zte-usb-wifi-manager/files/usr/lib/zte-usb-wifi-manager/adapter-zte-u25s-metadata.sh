#!/bin/sh

# Static device metadata is kept separate so rpcd can expose read-only
# capabilities without loading the HTTP and session implementation.
ZTE_ADAPTER_ID=zte_u25s
ZTE_ADAPTER_MODEL=U25S

# The target firmware's published WebUI config declares HAS_LOGIN:false. Its
# own service layer therefore treats the device as logged in without LOGIN.
ZTE_LOGIN_REQUIRED=0

# Write capabilities remain disabled until their request parameters and
# recovery behavior have been calibrated on the target firmware.
ZTE_CAP_SIM_SWITCH=0
ZTE_CAP_CELLULAR_WRITE=0
ZTE_CAP_WIFI_WRITE=0
ZTE_CAP_TRAFFIC_WRITE=0
ZTE_CAP_SMS_WRITE=0

ZTE_READ_FIELDS='mc_modem_main_state,network_type,network_signalbar,network_provider_fullname,Z5g_rsrp,ppp_status,simcard_active_slot_temp,usim_esim_type,battery_exist,battery_vol_percent,battery_charging,battery_value,battery_pers,battery_temperature_level,sms_data_total'

# These variables are the sourced adapter contract and are consumed by other
# library files after this metadata file returns.
: "$ZTE_ADAPTER_ID" "$ZTE_ADAPTER_MODEL" "$ZTE_CAP_SIM_SWITCH"
: "$ZTE_CAP_CELLULAR_WRITE" "$ZTE_CAP_WIFI_WRITE" "$ZTE_CAP_SMS_WRITE"
: "$ZTE_CAP_TRAFFIC_WRITE"
: "$ZTE_LOGIN_REQUIRED" "$ZTE_READ_FIELDS"

zte_adapter_login_required() {
	[ "$ZTE_LOGIN_REQUIRED" = 1 ]
}

zte_adapter_capabilities_json() {
	if zte_adapter_login_required; then
		_zte_metadata_login_required=true
	else
		_zte_metadata_login_required=false
	fi
	printf '{"adapter":"zte_u25s","model":"U25S","login_required":%s,"read_status":true,"sim_switch":false,"cellular_write":false,"wifi_write":false,"traffic_write":false,"sms_write":false}\n' \
		"$_zte_metadata_login_required"
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
		*) return 0 ;;
	esac
}

zte_adapter_framework_status_json() {
	printf '%s\n' \
		'{"online":false,"model":"U25S","state":"framework_ready","reason":"device_polling_not_configured"}'
}
