#!/bin/sh

# Static device metadata is kept separate so rpcd can expose read-only
# capabilities without loading the HTTP and session implementation.
ZTE_ADAPTER_ID=zte_u25s
ZTE_ADAPTER_MODEL=U25S

# Write capabilities remain disabled until their request parameters and
# recovery behavior have been calibrated on the target firmware.
ZTE_CAP_SIM_SWITCH=0
ZTE_CAP_CELLULAR_WRITE=0
ZTE_CAP_WIFI_WRITE=0
ZTE_CAP_SMS_WRITE=0

ZTE_READ_FIELDS='mc_modem_main_state,network_type,network_signalbar,network_provider_fullname,Z5g_rsrp,ppp_status,simcard_active_slot_temp,usim_esim_type,battery_exist,battery_vol_percent,battery_charging,battery_value,battery_pers,battery_temperature_level,sms_data_total'

# These variables are the sourced adapter contract and are consumed by other
# library files after this metadata file returns.
: "$ZTE_ADAPTER_ID" "$ZTE_ADAPTER_MODEL" "$ZTE_CAP_SIM_SWITCH"
: "$ZTE_CAP_CELLULAR_WRITE" "$ZTE_CAP_WIFI_WRITE" "$ZTE_CAP_SMS_WRITE"
: "$ZTE_READ_FIELDS"

zte_adapter_capabilities_json() {
	printf '%s\n' \
		'{"adapter":"zte_u25s","model":"U25S","read_status":true,"sim_switch":false,"cellular_write":false,"wifi_write":false,"sms_write":false}'
}

zte_adapter_framework_status_json() {
	printf '%s\n' \
		'{"online":false,"model":"U25S","state":"framework_ready","reason":"device_polling_not_configured"}'
}
