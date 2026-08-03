#!/bin/sh

# Static device metadata is kept separate so rpcd can expose read-only
# capabilities without loading the HTTP and session implementation.
ZTE_ADAPTER_ID=zte_u25s
ZTE_ADAPTER_MODEL=U25S
ZTE_ADAPTER_TRANSPORT=http
ZTE_ADAPTER_TLS_VERIFICATION=not_applicable

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
ZTE_CAP_DEVICE_REBOOT=0
ZTE_CAP_DEVICE_SHUTDOWN=0
ZTE_CAP_POWER_SUPPLY_WRITE=0

# Keep calibration evidence scoped to an exact device profile. The effective
# ZTE_CAP_* variables above remain the adapter contract consumed by the daemon
# and rpcd; this matrix is the only place that may populate them for a model.
ZTE_U25S_CAP_SIM_SWITCH=$ZTE_CAP_SIM_SWITCH
ZTE_U25S_CAP_CELLULAR_WRITE=$ZTE_CAP_CELLULAR_WRITE
ZTE_U25S_CAP_WIFI_WRITE=$ZTE_CAP_WIFI_WRITE
ZTE_U25S_CAP_TRAFFIC_WRITE=$ZTE_CAP_TRAFFIC_WRITE
ZTE_U25S_CAP_SMS_WRITE=$ZTE_CAP_SMS_WRITE
ZTE_U25S_CAP_DEVICE_REBOOT=$ZTE_CAP_DEVICE_REBOOT
ZTE_U25S_CAP_DEVICE_SHUTDOWN=$ZTE_CAP_DEVICE_SHUTDOWN
ZTE_U25S_CAP_POWER_SUPPLY_WRITE=$ZTE_CAP_POWER_SUPPLY_WRITE

ZTE_U30_CAP_SIM_SWITCH=0
ZTE_U30_CAP_CELLULAR_WRITE=0
ZTE_U30_CAP_WIFI_WRITE=0
ZTE_U30_CAP_TRAFFIC_WRITE=0
ZTE_U30_CAP_SMS_WRITE=0
ZTE_U30_CAP_DEVICE_REBOOT=0
ZTE_U30_CAP_DEVICE_SHUTDOWN=0
ZTE_U30_CAP_POWER_SUPPLY_WRITE=0

zte_adapter_apply_profile_capabilities() {
	case ${1-} in
		zte_u25s)
			ZTE_CAP_SIM_SWITCH=$ZTE_U25S_CAP_SIM_SWITCH
			ZTE_CAP_CELLULAR_WRITE=$ZTE_U25S_CAP_CELLULAR_WRITE
			ZTE_CAP_WIFI_WRITE=$ZTE_U25S_CAP_WIFI_WRITE
			ZTE_CAP_TRAFFIC_WRITE=$ZTE_U25S_CAP_TRAFFIC_WRITE
			ZTE_CAP_SMS_WRITE=$ZTE_U25S_CAP_SMS_WRITE
			ZTE_CAP_DEVICE_REBOOT=$ZTE_U25S_CAP_DEVICE_REBOOT
			ZTE_CAP_DEVICE_SHUTDOWN=$ZTE_U25S_CAP_DEVICE_SHUTDOWN
			ZTE_CAP_POWER_SUPPLY_WRITE=$ZTE_U25S_CAP_POWER_SUPPLY_WRITE
			;;
		zte_u30)
			ZTE_CAP_SIM_SWITCH=$ZTE_U30_CAP_SIM_SWITCH
			ZTE_CAP_CELLULAR_WRITE=$ZTE_U30_CAP_CELLULAR_WRITE
			ZTE_CAP_WIFI_WRITE=$ZTE_U30_CAP_WIFI_WRITE
			ZTE_CAP_TRAFFIC_WRITE=$ZTE_U30_CAP_TRAFFIC_WRITE
			ZTE_CAP_SMS_WRITE=$ZTE_U30_CAP_SMS_WRITE
			ZTE_CAP_DEVICE_REBOOT=$ZTE_U30_CAP_DEVICE_REBOOT
			ZTE_CAP_DEVICE_SHUTDOWN=$ZTE_U30_CAP_DEVICE_SHUTDOWN
			ZTE_CAP_POWER_SUPPLY_WRITE=$ZTE_U30_CAP_POWER_SUPPLY_WRITE
			;;
		*) return 1 ;;
	esac
}

# Apply a previously selected, whitelisted device profile without changing any
# independently calibrated write capability.
zte_adapter_apply_profile() {
	[ -n "${ZTE_DEVICE_PROFILE_ID:-}" ] || return 1
	[ -n "${ZTE_DEVICE_PROFILE_MODEL:-}" ] || return 1
	case ${ZTE_DEVICE_PROFILE_LOGIN_REQUIRED:-} in
		0|1) ;;
		*) return 1 ;;
	esac
	ZTE_ADAPTER_ID=$ZTE_DEVICE_PROFILE_ID
	ZTE_ADAPTER_MODEL=$ZTE_DEVICE_PROFILE_MODEL
	ZTE_LOGIN_REQUIRED=$ZTE_DEVICE_PROFILE_LOGIN_REQUIRED
	ZTE_ADAPTER_TRANSPORT=$ZTE_DEVICE_PROFILE_SCHEME
	if [ "$ZTE_DEVICE_PROFILE_SCHEME" = https ] &&
		[ "$ZTE_DEVICE_PROFILE_TLS_INSECURE" = 1 ]; then
		ZTE_ADAPTER_TLS_VERIFICATION=device_certificate_unverified
	else
		ZTE_ADAPTER_TLS_VERIFICATION=not_applicable
	fi
	zte_adapter_apply_profile_capabilities "$ZTE_DEVICE_PROFILE_ID" || return 1
	case $ZTE_DEVICE_PROFILE_ID in
		zte_u25s) ZTE_READ_FIELDS=$ZTE_U25S_READ_FIELDS ;;
		zte_u30)
			ZTE_READ_FIELDS=''
			_zte_profile_old_ifs=$IFS
			IFS=,
			for _zte_profile_field in $ZTE_U25S_READ_FIELDS; do
				IFS=$_zte_profile_old_ifs
				[ "$_zte_profile_field" = sms_data_total ] ||
					ZTE_READ_FIELDS=${ZTE_READ_FIELDS:+$ZTE_READ_FIELDS,}$_zte_profile_field
				IFS=,
			done
			IFS=$_zte_profile_old_ifs
			ZTE_READ_FIELDS=$ZTE_READ_FIELDS',connectionMode,power_supply_mode'
			;;
		*) return 1 ;;
	esac
}

# rpcd may apply only an exact identity already written by the polling daemon.
# It does not probe USB or contact the device.
zte_adapter_apply_cached_profile() {
	case ${1-}:${2-} in
		zte_u25s:U25S)
			ZTE_ADAPTER_ID=zte_u25s
			ZTE_ADAPTER_MODEL=U25S
			ZTE_LOGIN_REQUIRED=1
			ZTE_ADAPTER_TRANSPORT=http
			ZTE_ADAPTER_TLS_VERIFICATION=not_applicable
			zte_adapter_apply_profile_capabilities zte_u25s || return 1
			;;
		zte_u30:'U30 Pro')
			ZTE_ADAPTER_ID=zte_u30
			ZTE_ADAPTER_MODEL='U30 Pro'
			ZTE_LOGIN_REQUIRED=0
			ZTE_ADAPTER_TRANSPORT=https
			ZTE_ADAPTER_TLS_VERIFICATION=device_certificate_unverified
			zte_adapter_apply_profile_capabilities zte_u30 || return 1
			;;
		*) return 1 ;;
	esac
}

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
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',Z5g_snr,Z5g_SINR,wan_lte_ca,network_lte_ca_pcell_band,bandwidth,network_lte_ca_scell_band,network_lte_ca_scell_bandwidth'
ZTE_READ_FIELDS=$ZTE_READ_FIELDS',network_lte_ca_pcell_arfcn,lte_ca_scell_arfcn,wan_active_band,apn_pdp_type,apn_ipv6_pdp_type'
ZTE_U25S_READ_FIELDS=$ZTE_READ_FIELDS

# These variables are the sourced adapter contract and are consumed by other
# library files after this metadata file returns.
: "$ZTE_ADAPTER_ID" "$ZTE_ADAPTER_MODEL" "$ZTE_CAP_SIM_SWITCH"
: "$ZTE_CAP_CELLULAR_WRITE" "$ZTE_CAP_WIFI_WRITE" "$ZTE_CAP_SMS_WRITE"
: "$ZTE_CAP_TRAFFIC_WRITE"
: "$ZTE_CAP_DEVICE_REBOOT" "$ZTE_CAP_DEVICE_SHUTDOWN"
: "$ZTE_CAP_POWER_SUPPLY_WRITE"
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

zte_adapter_feature_status_json() {
	_zte_feature_write_enabled=${1-0}
	_zte_feature_sim_enabled=${2-0}
	_zte_feature_cellular_enabled=${3-0}
	_zte_feature_wifi_enabled=${4-0}
	_zte_feature_traffic_enabled=${5-0}
	_zte_feature_sms_enabled=${6-0}
	_zte_feature_reboot_enabled=${7-0}
	_zte_feature_shutdown_enabled=${8-0}
	_zte_feature_power_supply_enabled=${9-0}
	_zte_feature_sim_effective=$(zte_adapter_effective_capability_bool \
		"$ZTE_CAP_SIM_SWITCH" "$_zte_feature_write_enabled" \
		"$_zte_feature_sim_enabled")
	_zte_feature_cellular_effective=$(zte_adapter_effective_capability_bool \
		"$ZTE_CAP_CELLULAR_WRITE" "$_zte_feature_write_enabled" \
		"$_zte_feature_cellular_enabled")
	_zte_feature_wifi_effective=$(zte_adapter_effective_capability_bool \
		"$ZTE_CAP_WIFI_WRITE" "$_zte_feature_write_enabled" \
		"$_zte_feature_wifi_enabled")
	_zte_feature_traffic_effective=$(zte_adapter_effective_capability_bool \
		"$ZTE_CAP_TRAFFIC_WRITE" "$_zte_feature_write_enabled" \
		"$_zte_feature_traffic_enabled")
	_zte_feature_sms_effective=$(zte_adapter_effective_capability_bool \
		"$ZTE_CAP_SMS_WRITE" "$_zte_feature_write_enabled" \
		"$_zte_feature_sms_enabled")
	_zte_feature_reboot_effective=$(zte_adapter_effective_capability_bool \
		"$ZTE_CAP_DEVICE_REBOOT" "$_zte_feature_write_enabled" \
		"$_zte_feature_reboot_enabled")
	_zte_feature_shutdown_effective=$(zte_adapter_effective_capability_bool \
		"$ZTE_CAP_DEVICE_SHUTDOWN" "$_zte_feature_write_enabled" \
		"$_zte_feature_shutdown_enabled")
	_zte_feature_power_supply_effective=$(zte_adapter_effective_capability_bool \
		"$ZTE_CAP_POWER_SUPPLY_WRITE" "$_zte_feature_write_enabled" \
		"$_zte_feature_power_supply_enabled")
	if [ "$ZTE_ADAPTER_ID" = zte_u30 ]; then
		_zte_feature_cellular_implementation=implemented
		_zte_feature_wifi_implementation=implemented
		_zte_feature_power_supply_implementation=implemented
		_zte_feature_power_supply_verification=spare_device_required
		_zte_feature_traffic_implementation=implemented
		_zte_feature_traffic_verification=spare_device_required
		_zte_feature_sms_implementation=implemented
		_zte_feature_reboot_implementation=implemented
		_zte_feature_shutdown_implementation=implemented
	else
		_zte_feature_cellular_implementation=not_implemented
		_zte_feature_wifi_implementation=not_implemented
		_zte_feature_power_supply_implementation=unsupported
		_zte_feature_power_supply_verification=not_applicable
		_zte_feature_traffic_implementation=not_implemented
		_zte_feature_traffic_verification=spare_device_required
		_zte_feature_sms_implementation=not_implemented
		_zte_feature_reboot_implementation=not_implemented
		_zte_feature_shutdown_implementation=not_implemented
	fi

	printf '%s' '{'
	printf '%s' '"cellular_read":{"implementation":"implemented","verification":"local_and_qemu","access":"read","enabled":true},'
	printf '%s' '"wifi_read":{"implementation":"implemented","verification":"local_and_qemu","access":"read","enabled":true},'
	printf '%s' '"clients_read":{"implementation":"implemented","verification":"simulator_only","access":"read","enabled":true},'
	printf '%s' '"traffic_read":{"implementation":"implemented","verification":"local_and_qemu","access":"read","enabled":true},'
	printf '%s' '"sms_read":{"implementation":"implemented","verification":"simulator_only","access":"read","enabled":true},'
	printf '%s' '"device_read":{"implementation":"implemented","verification":"local_and_qemu","access":"read","enabled":true},'
	printf '"sim_switch":{"implementation":"implemented","verification":"spare_device_required","access":"write","enabled":%s},' "$_zte_feature_sim_effective"
	printf '"cellular_write":{"implementation":"%s","verification":"spare_device_required","access":"write","enabled":%s},' \
		"$_zte_feature_cellular_implementation" "$_zte_feature_cellular_effective"
	printf '"wifi_write":{"implementation":"%s","verification":"spare_device_required","access":"write","enabled":%s},' \
		"$_zte_feature_wifi_implementation" "$_zte_feature_wifi_effective"
	printf '"traffic_write":{"implementation":"%s","verification":"%s","access":"write","enabled":%s},' \
		"$_zte_feature_traffic_implementation" \
		"$_zte_feature_traffic_verification" \
		"$_zte_feature_traffic_effective"
	printf '"sms_write":{"implementation":"%s","verification":"spare_device_required","access":"write","enabled":%s},' \
		"$_zte_feature_sms_implementation" "$_zte_feature_sms_effective"
	printf '"device_restart":{"implementation":"%s","verification":"spare_device_required","access":"write","enabled":%s},' \
		"$_zte_feature_reboot_implementation" "$_zte_feature_reboot_effective"
	printf '"device_shutdown":{"implementation":"%s","verification":"spare_device_required","access":"write","enabled":%s},' \
		"$_zte_feature_shutdown_implementation" "$_zte_feature_shutdown_effective"
	printf '"power_supply_mode":{"implementation":"%s","verification":"%s","access":"write","enabled":%s},' \
		"$_zte_feature_power_supply_implementation" \
		"$_zte_feature_power_supply_verification" \
		"$_zte_feature_power_supply_effective"
	printf '%s' '"firmware_update":{"implementation":"native_console_only","verification":"native_console","access":"write","enabled":false},'
	printf '%s' '"factory_reset":{"implementation":"native_console_only","verification":"native_console","access":"write","enabled":false},'
	printf '%s' '"backup_restore":{"implementation":"native_console_only","verification":"native_console","access":"write","enabled":false},'
	printf '%s' '"device_password":{"implementation":"native_console_only","verification":"native_console","access":"write","enabled":false}'
	printf '%s' '}'
}

zte_adapter_effective_capabilities_json() {
	_zte_metadata_write_enabled=${1-0}
	_zte_metadata_sim_enabled=${2-0}
	_zte_metadata_cellular_enabled=${3-0}
	_zte_metadata_wifi_enabled=${4-0}
	_zte_metadata_traffic_enabled=${5-0}
	_zte_metadata_sms_enabled=${6-0}
	_zte_metadata_reboot_enabled=${7-0}
	_zte_metadata_shutdown_enabled=${8-0}
	_zte_metadata_power_supply_enabled=${9-0}
	if zte_adapter_login_required; then
		_zte_metadata_login_required=true
	else
		_zte_metadata_login_required=false
	fi
	printf '{"adapter":"%s","model":"%s","transport":"%s","tls_verification":"%s","login_required":%s,"read_status":true,"sim_switch":%s,"cellular_write":%s,"wifi_write":%s,"traffic_write":%s,"sms_write":%s,"device_reboot":%s,"device_shutdown":%s,"power_supply_write":%s,"feature_status":%s}\n' \
		"$ZTE_ADAPTER_ID" "$ZTE_ADAPTER_MODEL" \
		"$ZTE_ADAPTER_TRANSPORT" "$ZTE_ADAPTER_TLS_VERIFICATION" \
		"$_zte_metadata_login_required" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_SIM_SWITCH" "$_zte_metadata_write_enabled" "$_zte_metadata_sim_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_CELLULAR_WRITE" "$_zte_metadata_write_enabled" "$_zte_metadata_cellular_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_WIFI_WRITE" "$_zte_metadata_write_enabled" "$_zte_metadata_wifi_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_TRAFFIC_WRITE" "$_zte_metadata_write_enabled" "$_zte_metadata_traffic_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_SMS_WRITE" "$_zte_metadata_write_enabled" "$_zte_metadata_sms_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_DEVICE_REBOOT" "$_zte_metadata_write_enabled" "$_zte_metadata_reboot_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_DEVICE_SHUTDOWN" "$_zte_metadata_write_enabled" "$_zte_metadata_shutdown_enabled")" \
		"$(zte_adapter_effective_capability_bool "$ZTE_CAP_POWER_SUPPLY_WRITE" "$_zte_metadata_write_enabled" "$_zte_metadata_power_supply_enabled")" \
		"$(zte_adapter_feature_status_json \
			"$_zte_metadata_write_enabled" "$_zte_metadata_sim_enabled" \
			"$_zte_metadata_cellular_enabled" "$_zte_metadata_wifi_enabled" \
			"$_zte_metadata_traffic_enabled" "$_zte_metadata_sms_enabled" \
			"$_zte_metadata_reboot_enabled" "$_zte_metadata_shutdown_enabled" \
			"$_zte_metadata_power_supply_enabled")"
}

zte_adapter_capabilities_json() {
	zte_adapter_effective_capabilities_json 1 1 1 1 1 1 1 1 1
}

zte_adapter_action_supported() {
	case ${1-} in
		switch_sim) [ "$ZTE_CAP_SIM_SWITCH" = 1 ] ;;
		set_apn|set_connection_mode) [ "$ZTE_CAP_CELLULAR_WRITE" = 1 ] ;;
		set_wifi) [ "$ZTE_CAP_WIFI_WRITE" = 1 ] ;;
		set_traffic_plan|reset_traffic) [ "$ZTE_CAP_TRAFFIC_WRITE" = 1 ] ;;
		send_sms|delete_sms|mark_sms_read) [ "$ZTE_CAP_SMS_WRITE" = 1 ] ;;
		reboot_device) [ "$ZTE_CAP_DEVICE_REBOOT" = 1 ] ;;
		shutdown_device) [ "$ZTE_CAP_DEVICE_SHUTDOWN" = 1 ] ;;
		set_power_supply_mode) [ "$ZTE_CAP_POWER_SUPPLY_WRITE" = 1 ] ;;
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
		reboot_device) printf '%s\n' device_reboot_enabled ;;
		shutdown_device) printf '%s\n' device_shutdown_enabled ;;
		set_power_supply_mode) printf '%s\n' power_supply_write_enabled ;;
		*) return 1 ;;
	esac
}

zte_adapter_payload_schema() {
	_zte_schema_payload=$1
	_zte_schema_allowed=$2
	_zte_schema_required=$3
	_zte_schema_keys=$(zte_json_flat_keys "$_zte_schema_payload") || return 1
	for _zte_schema_required_key in $_zte_schema_required; do
		zte_json_flat_has \
			"$_zte_schema_payload" "$_zte_schema_required_key" || return 1
	done
	while IFS= read -r _zte_schema_key; do
		[ -n "$_zte_schema_key" ] || continue
		case " $_zte_schema_allowed " in
			*" $_zte_schema_key "*) ;;
			*) return 1 ;;
		esac
	done <<EOF
$_zte_schema_keys
EOF
}

zte_adapter_payload_text() {
	_zte_payload_text=${1-}
	_zte_payload_text_min=$2
	_zte_payload_text_max=$3
	[ "${#_zte_payload_text}" -ge "$_zte_payload_text_min" ] &&
		[ "${#_zte_payload_text}" -le "$_zte_payload_text_max" ] || return 1
	case $_zte_payload_text in
		*[[:cntrl:]]*) return 1 ;;
		*) return 0 ;;
	esac
}

zte_adapter_payload_uint_range() {
	_zte_payload_uint=${1-}
	_zte_payload_uint_min=$2
	_zte_payload_uint_max=$3
	zte_is_uint "$_zte_payload_uint" &&
		[ "$_zte_payload_uint" -ge "$_zte_payload_uint_min" ] &&
		[ "$_zte_payload_uint" -le "$_zte_payload_uint_max" ]
}

zte_adapter_payload_message_id() {
	_zte_payload_message_id=${1-}
	zte_adapter_payload_text "$_zte_payload_message_id" 1 64 || return 1
	case $_zte_payload_message_id in
		*[!A-Za-z0-9._:-]*) return 1 ;;
		*) return 0 ;;
	esac
}

zte_adapter_payload_phone() {
	_zte_payload_phone=${1-}
	zte_adapter_payload_text "$_zte_payload_phone" 3 20 || return 1
	case $_zte_payload_phone in
		+*) _zte_payload_phone=${_zte_payload_phone#+} ;;
	esac
	case $_zte_payload_phone in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

zte_adapter_action_payload_valid() {
	_zte_metadata_action=${1-}
	_zte_metadata_payload=${2-}
	zte_json_is_flat_object "$_zte_metadata_payload" || return 1
	[ "$(zte_json_flat_get "$_zte_metadata_payload" action)" = \
		"$_zte_metadata_action" ] || return 1
	case $_zte_metadata_action in
		set_power_supply_mode)
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action mode' 'action mode' || return 1
			case $(zte_json_flat_get "$_zte_metadata_payload" mode) in
				charging|direct_supply) return 0 ;;
				*) return 1 ;;
			esac
			;;
		switch_sim)
			zte_adapter_payload_schema \
				"$_zte_metadata_payload" 'action target' \
				'action target' || return 1
			_zte_metadata_target=$(
				zte_json_flat_get "$_zte_metadata_payload" target
			)
			case $_zte_metadata_target in
				sim1|sim2|sim3|physical) return 0 ;;
				*) return 1 ;;
			esac
			;;
		set_apn)
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action apn auth username password' \
				'action apn auth' || return 1
			_zte_metadata_apn=$(zte_json_flat_get "$_zte_metadata_payload" apn)
			case $_zte_metadata_apn in
				''|*[!A-Za-z0-9._-]*) return 1 ;;
			esac
			[ "${#_zte_metadata_apn}" -le 100 ] || return 1
			_zte_metadata_auth=$(zte_json_flat_get "$_zte_metadata_payload" auth)
			case $_zte_metadata_auth in
				none) ;;
				pap|chap|pap_or_chap)
					zte_json_flat_has "$_zte_metadata_payload" username &&
						zte_json_flat_has "$_zte_metadata_payload" password ||
						return 1
					zte_adapter_payload_text "$(zte_json_flat_get \
						"$_zte_metadata_payload" username)" 1 128 || return 1
					zte_adapter_payload_text "$(zte_json_flat_get \
						"$_zte_metadata_payload" password)" 1 128 || return 1
					;;
				*) return 1 ;;
			esac
			;;
		set_connection_mode)
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action mode' 'action mode' || return 1
			case $(zte_json_flat_get "$_zte_metadata_payload" mode) in
				automatic|manual|on_demand) return 0 ;;
				*) return 1 ;;
			esac
			;;
		set_wifi)
			_zte_metadata_enabled=$(zte_json_flat_get \
				"$_zte_metadata_payload" enabled)
			case $_zte_metadata_enabled in
				false)
					zte_adapter_payload_schema "$_zte_metadata_payload" \
						'action enabled' 'action enabled'
					return
					;;
				true) ;;
				*) return 1 ;;
			esac
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action enabled band ssid security password channel' \
				'action enabled band ssid security channel' || return 1
			case $(zte_json_flat_get "$_zte_metadata_payload" band) in
				2g|5g) ;;
				*) return 1 ;;
			esac
			zte_adapter_payload_text "$(zte_json_flat_get \
				"$_zte_metadata_payload" ssid)" 1 32 || return 1
			_zte_metadata_security=$(zte_json_flat_get \
				"$_zte_metadata_payload" security)
			case $_zte_metadata_security in
				open) ;;
				wpa2_psk|wpa3_sae|wpa2_wpa3)
					zte_json_flat_has "$_zte_metadata_payload" password || return 1
					zte_adapter_payload_text "$(zte_json_flat_get \
						"$_zte_metadata_payload" password)" 8 63 || return 1
					;;
				*) return 1 ;;
			esac
			_zte_metadata_channel=$(zte_json_flat_get \
				"$_zte_metadata_payload" channel)
			[ "$_zte_metadata_channel" = auto ] ||
				zte_adapter_payload_uint_range \
					"$_zte_metadata_channel" 1 196
			;;
		set_traffic_plan)
			_zte_metadata_enabled=$(zte_json_flat_get \
				"$_zte_metadata_payload" enabled)
			case $_zte_metadata_enabled in
				false)
					zte_adapter_payload_schema "$_zte_metadata_payload" \
						'action enabled' 'action enabled'
					return
					;;
				true) ;;
				*) return 1 ;;
			esac
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action enabled limit_bytes alert_percent cycle_day disconnect' \
				'action enabled limit_bytes alert_percent cycle_day disconnect' ||
				return 1
			zte_adapter_payload_uint_range "$(zte_json_flat_get \
				"$_zte_metadata_payload" limit_bytes)" 1 1000000000000000 &&
				zte_adapter_payload_uint_range "$(zte_json_flat_get \
				"$_zte_metadata_payload" alert_percent)" 1 100 &&
				zte_adapter_payload_uint_range "$(zte_json_flat_get \
				"$_zte_metadata_payload" cycle_day)" 1 31 || return 1
			case $(zte_json_flat_get "$_zte_metadata_payload" disconnect) in
				true|false) return 0 ;;
				*) return 1 ;;
			esac
			;;
		reset_traffic)
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action confirm' 'action confirm' || return 1
			[ "$(zte_json_flat_get "$_zte_metadata_payload" confirm)" = true ]
			;;
		send_sms)
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action number content' 'action number content' || return 1
			zte_adapter_payload_phone "$(zte_json_flat_get \
				"$_zte_metadata_payload" number)" &&
				zte_adapter_payload_text "$(zte_json_flat_get \
					"$_zte_metadata_payload" content)" 1 3060
			;;
		delete_sms)
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action message_id confirm' 'action message_id confirm' || return 1
			zte_adapter_payload_message_id "$(zte_json_flat_get \
				"$_zte_metadata_payload" message_id)" &&
				[ "$(zte_json_flat_get \
					"$_zte_metadata_payload" confirm)" = true ]
			;;
		mark_sms_read)
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action message_id' 'action message_id' || return 1
			zte_adapter_payload_message_id "$(zte_json_flat_get \
				"$_zte_metadata_payload" message_id)"
			;;
		reboot_device|shutdown_device)
			zte_adapter_payload_schema "$_zte_metadata_payload" \
				'action confirm' 'action confirm' || return 1
			[ "$(zte_json_flat_get "$_zte_metadata_payload" confirm)" = true ]
			;;
		*) return 1 ;;
	esac
}

zte_adapter_framework_status_json() {
	printf '%s\n' \
		'{"online":false,"model":"U25S","state":"framework_ready","reason":"device_polling_not_configured"}'
}
