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

zte_adapter_power_supply_raw_mode() {
	case ${1-} in
		charging) printf '%s\n' 0 ;;
		direct_supply) printf '%s\n' 1 ;;
		*) return 1 ;;
	esac
}

# U30 Pro's calibrated WebUI contract. The caller supplies only a semantic
# mode; every request key and value is fixed here.
zte_adapter_set_power_supply_mode() {
	[ "${ZTE_ADAPTER_ID:-}" = zte_u30 ] || return 1
	_zte_power_host=$1
	_zte_power_target=$2
	_zte_power_jar=$3
	_zte_power_raw=$(zte_adapter_power_supply_raw_mode \
		"$_zte_power_target") || return 1
	_zte_power_origin=$(zte_adapter_origin "$_zte_power_host") || return 1
	_zte_power_response=$(zte_http_post \
		"$_zte_power_origin/goform/goform_set_cmd_process" \
		"isTest=false&goformId=POWER_SUPPLY_SETTING&power_supply_mode=$_zte_power_raw" \
		"$_zte_power_jar") || return 1
	zte_json_is_flat_object "$_zte_power_response" || return 1
	[ "$(zte_json_flat_get "$_zte_power_response" result)" = success ]
}

zte_adapter_fetch_power_supply_mode() {
	[ "${ZTE_ADAPTER_ID:-}" = zte_u30 ] || return 1
	_zte_power_read_host=$1
	_zte_power_read_jar=$2
	_zte_power_read_origin=$(zte_adapter_origin \
		"$_zte_power_read_host") || return 1
	_zte_power_read_response=$(zte_http_get \
		"$_zte_power_read_origin/goform/goform_get_cmd_process?cmd=power_supply_mode&isTest=false" \
		"$_zte_power_read_jar") || return 1
	zte_json_is_flat_object "$_zte_power_read_response" || return 1
	zte_json_flat_has "$_zte_power_read_response" power_supply_mode || return 1
	case $(zte_json_flat_get "$_zte_power_read_response" power_supply_mode) in
		0) printf '%s\n' charging ;;
		1) printf '%s\n' direct_supply ;;
		*) return 1 ;;
	esac
}

zte_adapter_u30_post_body() {
	[ "${ZTE_ADAPTER_ID:-}" = zte_u30 ] || return 1
	_zte_u30_post_origin=$(zte_adapter_origin "$1") || return 1
	_zte_u30_post_response=$(zte_http_post \
		"$_zte_u30_post_origin/goform/goform_set_cmd_process" \
		"$2" "$3") || return 1
	zte_json_is_flat_object "$_zte_u30_post_response" || return 1
	[ "$(zte_json_flat_get "$_zte_u30_post_response" result)" = success ]
}

zte_adapter_set_connection_mode() {
	_zte_connection_host=$1
	_zte_connection_mode=$2
	_zte_connection_jar=$3
	case $_zte_connection_mode in
		automatic) _zte_connection_raw=auto_dial ;;
		manual) _zte_connection_raw=manual_dial ;;
		on_demand) _zte_connection_raw=on_demand ;;
		*) return 1 ;;
	esac
	zte_adapter_u30_post_body "$_zte_connection_host" \
		"isTest=false&goformId=SET_CONNECTION_MODE&ConnectionMode=$_zte_connection_raw&dial_roam_setting_option=off" \
		"$_zte_connection_jar"
}

zte_adapter_u30_fetch_flat() {
	[ "${ZTE_ADAPTER_ID:-}" = zte_u30 ] || return 1
	_zte_u30_fetch_fields=$2
	case $_zte_u30_fetch_fields in
		'ConnectionMode,autoConnectWhenRoaming'|\
'index,profile_name,apn_wan_apn,apn_ppp_auth_mode,apn_ppp_username'|\
'flux_data_volume_limit_switch,flux_data_volume_limit_size,flux_data_volume_alert_percent,flux_clear_date,flux_limited_disconnect'|\
'flux_monthly_tx_bytes,flux_monthly_rx_bytes,flux_monthly_time'|\
'wifi_onoff_state,wifi_chip1_ssid1_switch_onoff,wifi_chip1_ssid1_ssid,wifi_chip1_ssid1_auth_mode') ;;
		*) return 1 ;;
	esac
	_zte_u30_fetch_origin=$(zte_adapter_origin "$1") || return 1
	_zte_u30_fetch_response=$(zte_http_get \
		"$_zte_u30_fetch_origin/goform/goform_get_cmd_process?cmd=$_zte_u30_fetch_fields&multi_data=1&isTest=false" \
		"$3") || return 1
	zte_json_is_flat_object "$_zte_u30_fetch_response" || return 1
	printf '%s\n' "$_zte_u30_fetch_response"
}

zte_adapter_fetch_connection_mode() {
	_zte_connection_response=$(zte_adapter_u30_fetch_flat "$1" \
		'ConnectionMode,autoConnectWhenRoaming' "$2") || return 1
	zte_json_flat_has "$_zte_connection_response" ConnectionMode || return 1
	case $(zte_json_flat_get "$_zte_connection_response" ConnectionMode) in
		auto_dial) printf '%s\n' automatic ;;
		manual_dial) printf '%s\n' manual ;;
		on_demand) printf '%s\n' on_demand ;;
		*) return 1 ;;
	esac
}

zte_adapter_fetch_apn_context() {
	_zte_apn_read_response=$(zte_adapter_u30_fetch_flat "$1" \
		'index,profile_name,apn_wan_apn,apn_ppp_auth_mode,apn_ppp_username' \
		"$2") || return 1
	for _zte_apn_read_field in index profile_name apn_wan_apn \
		apn_ppp_auth_mode apn_ppp_username; do
		zte_json_flat_has "$_zte_apn_read_response" \
			"$_zte_apn_read_field" || return 1
	done
	_zte_apn_read_index=$(zte_json_flat_get "$_zte_apn_read_response" index)
	zte_adapter_payload_uint_range "$_zte_apn_read_index" 0 19 || return 1
	printf '%s\n' "$_zte_apn_read_response"
}

zte_adapter_set_apn() {
	[ "${ZTE_ADAPTER_ID:-}" = zte_u30 ] || return 1
	_zte_apn_set_host=$1
	_zte_apn_set_apn=$2
	_zte_apn_set_pdp=$3
	_zte_apn_set_auth=$4
	_zte_apn_set_username=$5
	_zte_apn_set_password=$6
	_zte_apn_set_jar=$7
	case $_zte_apn_set_apn in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
	[ "${#_zte_apn_set_apn}" -le 100 ] || return 1
	case $_zte_apn_set_pdp in ipv4|ipv6|ipv4v6) ;; *) return 1 ;; esac
	case $_zte_apn_set_auth in
		none)
			_zte_apn_set_username=''
			_zte_apn_set_password=''
			;;
		pap|chap)
			zte_adapter_payload_text "$_zte_apn_set_username" 1 128 &&
				zte_adapter_payload_text "$_zte_apn_set_password" 1 128 || return 1
			;;
		pap_or_chap)
			zte_adapter_payload_text "$_zte_apn_set_username" 1 128 &&
				zte_adapter_payload_text "$_zte_apn_set_password" 1 128 || return 1
			_zte_apn_set_auth=pap_chap
			;;
		*) return 1 ;;
	esac
	_zte_apn_set_context=$(zte_adapter_fetch_apn_context \
		"$_zte_apn_set_host" "$_zte_apn_set_jar") || return 1
	_zte_apn_set_index=$(zte_json_flat_get \
		"$_zte_apn_set_context" index)
	_zte_apn_set_profile=$(zte_json_flat_get \
		"$_zte_apn_set_context" profile_name)
	[ -n "$_zte_apn_set_profile" ] || return 1
	_zte_apn_set_form="isTest=false&goformId=APN_PROC&apn_action=set_default&$(zte_form_pair index "$_zte_apn_set_index")&apn_mode=manual&$(zte_form_pair profile_name "$_zte_apn_set_profile")&$(zte_form_pair apn_wan_apn "$_zte_apn_set_apn")&dns_mode=auto&prefer_dns_manual=&w_standby_dns_manual=&$(zte_form_pair apn_ppp_username "$_zte_apn_set_username")&$(zte_form_pair apn_ppp_passwd "$_zte_apn_set_password")&$(zte_form_pair apn_ppp_auth_mode "$_zte_apn_set_auth")&apn_select=manual&$(zte_form_pair apn_wan_dial '*99#')&apn_pdp_type=PPP&apn_pdp_select=auto&apn_pdp_addr=&set_default_flag=1"
	zte_adapter_u30_post_body "$_zte_apn_set_host" \
		"$_zte_apn_set_form" "$_zte_apn_set_jar"
}

zte_adapter_fetch_apn_setting() {
	_zte_apn_setting=$(zte_adapter_fetch_apn_context "$1" "$2") || return 1
	_zte_apn_setting_apn=$(zte_json_flat_get "$_zte_apn_setting" apn_wan_apn)
	_zte_apn_setting_auth=$(zte_json_flat_get \
		"$_zte_apn_setting" apn_ppp_auth_mode)
	_zte_apn_setting_username=$(zte_json_flat_get \
		"$_zte_apn_setting" apn_ppp_username)
	case $_zte_apn_setting_auth in
		none|pap|chap) ;;
		pap_chap|PAP_CHAP) _zte_apn_setting_auth=pap_or_chap ;;
		*) return 1 ;;
	esac
	printf '{"apn":"%s","auth":"%s","username":"%s"}\n' \
		"$(zte_json_escape "$_zte_apn_setting_apn")" \
		"$_zte_apn_setting_auth" \
		"$(zte_json_escape "$_zte_apn_setting_username")"
}

zte_adapter_set_wifi() {
	[ "${ZTE_ADAPTER_ID:-}" = zte_u30 ] || return 1
	_zte_wifi_set_host=$1
	_zte_wifi_set_enabled=$2
	_zte_wifi_set_band=$3
	_zte_wifi_set_ssid=$4
	_zte_wifi_set_security=$5
	_zte_wifi_set_password=$6
	_zte_wifi_set_channel=$7
	_zte_wifi_set_jar=$8
	case $_zte_wifi_set_enabled in
		0)
			zte_adapter_u30_post_body "$_zte_wifi_set_host" \
				'isTest=false&goformId=switchWiFiModule&SwitchOption=0' \
				"$_zte_wifi_set_jar"
			return
			;;
		1) ;;
		*) return 1 ;;
	esac
	# The observed MU3351 device config explicitly reports WIFI_HAS_5G=false.
	# Do not construct an unverified second-chip request from dormant generic UI.
	[ "$_zte_wifi_set_band" = 2g ] &&
		[ "$_zte_wifi_set_channel" = auto ] || return 1
	zte_adapter_payload_text "$_zte_wifi_set_ssid" 1 32 || return 1
	case $_zte_wifi_set_security in
		open)
			_zte_wifi_set_auth=OPEN
			_zte_wifi_set_crypto='&EncrypType=NONE'
			;;
		wpa2_psk|wpa3_sae|wpa2_wpa3)
			zte_adapter_payload_text "$_zte_wifi_set_password" 8 63 || return 1
			case $_zte_wifi_set_security in
				wpa2_psk) _zte_wifi_set_auth=WPA2PSK ;;
				wpa3_sae) _zte_wifi_set_auth=WPA3PSK ;;
				wpa2_wpa3) _zte_wifi_set_auth=WPA2PSKWPA3PSK ;;
			esac
			_zte_wifi_set_crypto="&EncrypType=CCMP&$(zte_form_pair Password "$_zte_wifi_set_password")"
			;;
		*) return 1 ;;
	esac
	_zte_wifi_set_form="isTest=false&goformId=setAccessPointInfo&ChipIndex=0&AccessPointIndex=0&AccessPointSwitchStatus=1&$(zte_form_pair SSID "$_zte_wifi_set_ssid")&ApIsolate=0&AuthMode=$_zte_wifi_set_auth&ApBroadcastDisabled=0$_zte_wifi_set_crypto"
	zte_adapter_u30_post_body "$_zte_wifi_set_host" \
		"$_zte_wifi_set_form" "$_zte_wifi_set_jar"
}

zte_adapter_fetch_wifi_setting() {
	_zte_wifi_read_response=$(zte_adapter_u30_fetch_flat "$1" \
		'wifi_onoff_state,wifi_chip1_ssid1_switch_onoff,wifi_chip1_ssid1_ssid,wifi_chip1_ssid1_auth_mode' \
		"$2") || return 1
	for _zte_wifi_read_field in wifi_onoff_state \
		wifi_chip1_ssid1_switch_onoff wifi_chip1_ssid1_ssid \
		wifi_chip1_ssid1_auth_mode; do
		zte_json_flat_has "$_zte_wifi_read_response" \
			"$_zte_wifi_read_field" || return 1
	done
	_zte_wifi_read_module=$(zte_json_flat_get \
		"$_zte_wifi_read_response" wifi_onoff_state)
	_zte_wifi_read_switch=$(zte_json_flat_get \
		"$_zte_wifi_read_response" wifi_chip1_ssid1_switch_onoff)
	case $_zte_wifi_read_module:$_zte_wifi_read_switch in
		0:*|*:0) printf '%s\n' '{"enabled":false}'; return ;;
		1:1) ;;
		*) return 1 ;;
	esac
	_zte_wifi_read_ssid=$(zte_json_flat_get \
		"$_zte_wifi_read_response" wifi_chip1_ssid1_ssid)
	case $(zte_json_flat_get "$_zte_wifi_read_response" \
		wifi_chip1_ssid1_auth_mode) in
		OPEN) _zte_wifi_read_security=open ;;
		WPA2PSK) _zte_wifi_read_security=wpa2_psk ;;
		WPA3PSK) _zte_wifi_read_security=wpa3_sae ;;
		WPA2PSKWPA3PSK) _zte_wifi_read_security=wpa2_wpa3 ;;
		*) return 1 ;;
	esac
	printf '{"enabled":true,"band":"2g","ssid":"%s","security":"%s"}\n' \
		"$(zte_json_escape "$_zte_wifi_read_ssid")" \
		"$_zte_wifi_read_security"
}

zte_adapter_set_traffic_plan() {
	_zte_traffic_host=$1
	_zte_traffic_enabled=$2
	_zte_traffic_limit=$3
	_zte_traffic_alert=$4
	_zte_traffic_day=$5
	_zte_traffic_disconnect=$6
	_zte_traffic_jar=$7
	case $_zte_traffic_enabled in
		0)
			_zte_traffic_body='isTest=false&goformId=DATA_LIMIT_SETTING&flux_data_volume_limit_switch=0&notify_deviceui_enable=0'
			;;
		1)
			zte_adapter_payload_uint_range \
				"$_zte_traffic_limit" 1 1000000000000000 &&
				zte_adapter_payload_uint_range \
					"$_zte_traffic_alert" 1 100 &&
				zte_adapter_payload_uint_range \
					"$_zte_traffic_day" 1 31 || return 1
			case $_zte_traffic_disconnect in
				0|1) ;;
				*) return 1 ;;
			esac
			_zte_traffic_body="isTest=false&goformId=DATA_LIMIT_SETTING&flux_data_volume_limit_unit=data&flux_data_volume_limit_size=$_zte_traffic_limit&flux_data_volume_alert_percent=$_zte_traffic_alert&flux_auto_clear_flow_data_switch=1&flux_clear_date=$_zte_traffic_day&flux_limited_disconnect=$_zte_traffic_disconnect&flux_data_volume_limit_switch=1&notify_deviceui_enable=0"
			;;
		*) return 1 ;;
	esac
	zte_adapter_u30_post_body "$_zte_traffic_host" \
		"$_zte_traffic_body" "$_zte_traffic_jar"
}

zte_adapter_fetch_traffic_plan() {
	_zte_traffic_response=$(zte_adapter_u30_fetch_flat "$1" \
		'flux_data_volume_limit_switch,flux_data_volume_limit_size,flux_data_volume_alert_percent,flux_clear_date,flux_limited_disconnect' \
		"$2") || return 1
	for _zte_traffic_field in \
		flux_data_volume_limit_switch flux_data_volume_limit_size \
		flux_data_volume_alert_percent flux_clear_date \
		flux_limited_disconnect; do
		zte_json_flat_has "$_zte_traffic_response" \
			"$_zte_traffic_field" || return 1
	done
	_zte_traffic_read_enabled=$(zte_json_flat_get \
		"$_zte_traffic_response" flux_data_volume_limit_switch)
	case $_zte_traffic_read_enabled in 0|1) ;; *) return 1 ;; esac
	if [ "$_zte_traffic_read_enabled" = 0 ]; then
		printf '%s\n' '0||||'
		return
	fi
	_zte_traffic_read_limit=$(zte_json_flat_get \
		"$_zte_traffic_response" flux_data_volume_limit_size)
	_zte_traffic_read_alert=$(zte_json_flat_get \
		"$_zte_traffic_response" flux_data_volume_alert_percent)
	_zte_traffic_read_day=$(zte_json_flat_get \
		"$_zte_traffic_response" flux_clear_date)
	_zte_traffic_read_disconnect=$(zte_json_flat_get \
		"$_zte_traffic_response" flux_limited_disconnect)
	zte_adapter_payload_uint_range "$_zte_traffic_read_limit" \
		1 1000000000000000 &&
		zte_adapter_payload_uint_range "$_zte_traffic_read_alert" 1 100 &&
		zte_adapter_payload_uint_range "$_zte_traffic_read_day" 1 31 || return 1
	case $_zte_traffic_read_disconnect in 0|1) ;; *) return 1 ;; esac
	printf '1|%s|%s|%s|%s\n' "$_zte_traffic_read_limit" \
		"$_zte_traffic_read_alert" "$_zte_traffic_read_day" \
		"$_zte_traffic_read_disconnect"
}

zte_adapter_reset_traffic() {
	zte_adapter_u30_post_body "$1" \
		'isTest=false&goformId=RESET_DATA_COUNTER' "$2"
}

zte_adapter_fetch_traffic_counters() {
	_zte_counter_response=$(zte_adapter_u30_fetch_flat "$1" \
		'flux_monthly_tx_bytes,flux_monthly_rx_bytes,flux_monthly_time' \
		"$2") || return 1
	_zte_counter_values=''
	for _zte_counter_field in flux_monthly_tx_bytes flux_monthly_rx_bytes \
		flux_monthly_time; do
		zte_json_flat_has "$_zte_counter_response" \
			"$_zte_counter_field" || return 1
		_zte_counter_value=$(zte_json_flat_get \
			"$_zte_counter_response" "$_zte_counter_field")
		[ -n "$_zte_counter_value" ] || _zte_counter_value=0
		zte_is_uint "$_zte_counter_value" || return 1
		_zte_counter_values=${_zte_counter_values:+$_zte_counter_values|}$_zte_counter_value
	done
	printf '%s\n' "$_zte_counter_values"
}

zte_adapter_mark_sms_read() {
	zte_adapter_payload_message_id "$2" || return 1
	_zte_sms_read_id=$(zte_form_encode "$2;") || return 1
	zte_adapter_u30_post_body "$1" \
		"isTest=false&goformId=SET_MSG_READ&msg_id=$_zte_sms_read_id&tag=0" \
		"$3"
}

zte_adapter_delete_sms() {
	zte_adapter_payload_message_id "$2" || return 1
	_zte_sms_delete_id=$(zte_form_encode "$2;") || return 1
	zte_adapter_u30_post_body "$1" \
		"isTest=false&goformId=DELETE_SMS&msg_id=$_zte_sms_delete_id&notCallback=true" \
		"$3"
}

# Return "absent" or the current numeric message tag for one exact ID.
zte_adapter_fetch_sms_message_state() {
	zte_adapter_payload_message_id "$2" || return 1
	_zte_sms_state_origin=$(zte_adapter_origin "$1") || return 1
	_zte_sms_state_response=$(zte_http_get \
		"$_zte_sms_state_origin/goform/goform_get_cmd_process?cmd=sms_data_total&page=0&data_per_page=50&mem_store=1&tags=10&order_by=order%20by%20id%20desc&isTest=false" \
		"$3") || return 1
	_zte_sms_state_items=$(jsonfilter -s "$_zte_sms_state_response" \
		-e '@.messages[*]') || return 1
	while IFS= read -r _zte_sms_state_item; do
		[ -n "$_zte_sms_state_item" ] || continue
		zte_json_is_flat_object "$_zte_sms_state_item" || return 1
		[ "$(zte_json_flat_get "$_zte_sms_state_item" id)" = "$2" ] || continue
		_zte_sms_state_tag=$(zte_json_flat_get "$_zte_sms_state_item" tag)
		case $_zte_sms_state_tag in 0|1) printf '%s\n' "$_zte_sms_state_tag" ;; *) return 1 ;; esac
		return 0
	done <<EOF
$_zte_sms_state_items
EOF
	printf '%s\n' absent
}

# Match the target WebUI's encodeMessage()/getEncodeType() contract without
# adding a locale or iconv dependency. The input is decoded as strict UTF-8;
# each Unicode scalar is emitted as uppercase hexadecimal with at least four
# digits, exactly as the browser implementation does.
zte_adapter_sms_encode() {
	printf '%s' "${1-}" | od -An -v -tu1 | LC_ALL=C awk '
		function gsm7(cp) {
			if (cp == 10 || cp == 13 || (cp >= 32 && cp <= 126 && cp != 96))
				return 1
			return cp == 163 || cp == 165 || cp == 232 || cp == 233 ||
				cp == 249 || cp == 236 || cp == 242 || cp == 199 ||
				cp == 216 || cp == 248 || cp == 197 || cp == 229 ||
				cp == 916 || cp == 934 || cp == 915 || cp == 923 ||
				cp == 937 || cp == 928 || cp == 936 || cp == 931 ||
				cp == 920 || cp == 926 || cp == 198 || cp == 230 ||
				cp == 223 || cp == 201 || cp == 161 || cp == 196 ||
				cp == 214 || cp == 209 || cp == 220 || cp == 167 ||
				cp == 191 || cp == 228 || cp == 246 || cp == 241 ||
				cp == 252 || cp == 224 || cp == 8364
		}
		function emit(cp) {
			if (cp < 0 || cp > 1114111 || (cp >= 55296 && cp <= 57343)) {
				bad = 1
				return
			}
			if (!gsm7(cp))
				type = "UNICODE"
			if (cp <= 65535)
				body = body sprintf("%04X", cp)
			else
				body = body sprintf("%X", cp)
		}
		{
			for (i = 1; i <= NF; i++)
				bytes[++count] = $i + 0
		}
		END {
			type = "GSM7_default"
			for (i = 1; i <= count && !bad; i++) {
				b1 = bytes[i]
				if (b1 < 128) {
					emit(b1)
					continue
				}
				if (b1 >= 194 && b1 <= 223) {
					if (++i > count || bytes[i] < 128 || bytes[i] > 191) { bad = 1; break }
					emit((b1 - 192) * 64 + bytes[i] - 128)
					continue
				}
				if (b1 >= 224 && b1 <= 239) {
					if (i + 2 > count) { bad = 1; break }
					b2 = bytes[++i]; b3 = bytes[++i]
					if (b2 < 128 || b2 > 191 || b3 < 128 || b3 > 191 ||
						(b1 == 224 && b2 < 160) || (b1 == 237 && b2 > 159)) { bad = 1; break }
					emit((b1 - 224) * 4096 + (b2 - 128) * 64 + b3 - 128)
					continue
				}
				if (b1 >= 240 && b1 <= 244) {
					if (i + 3 > count) { bad = 1; break }
					b2 = bytes[++i]; b3 = bytes[++i]; b4 = bytes[++i]
					if (b2 < 128 || b2 > 191 || b3 < 128 || b3 > 191 ||
						b4 < 128 || b4 > 191 || (b1 == 240 && b2 < 144) ||
						(b1 == 244 && b2 > 143)) { bad = 1; break }
					cp = (b1 - 240) * 262144 + (b2 - 128) * 4096 + (b3 - 128) * 64 + b4 - 128
					emit(cp)
					continue
				}
				bad = 1
			}
			if (bad)
				exit 1
			printf "%s|%s\n", type, body
		}
	'
}

zte_adapter_sms_time() {
	_zte_sms_time_base=$(date '+%y;%m;%d;%H;%M;%S') || return 1
	_zte_sms_time_offset=$(date '+%z') || return 1
	case $_zte_sms_time_offset in
		[+-][0-9][0-9][0-9][0-9]) ;;
		*) return 1 ;;
	esac
	_zte_sms_time_sign=${_zte_sms_time_offset%????}
	_zte_sms_time_hour=${_zte_sms_time_offset#?}
	_zte_sms_time_hour=${_zte_sms_time_hour%??}
	_zte_sms_time_minute=${_zte_sms_time_offset#???}
	case $_zte_sms_time_hour in 0[0-9]) _zte_sms_time_hour=${_zte_sms_time_hour#0} ;; esac
	case $_zte_sms_time_minute in
		00) _zte_sms_time_zone=$_zte_sms_time_sign$_zte_sms_time_hour ;;
		15) _zte_sms_time_zone=$_zte_sms_time_sign$_zte_sms_time_hour.25 ;;
		30) _zte_sms_time_zone=$_zte_sms_time_sign$_zte_sms_time_hour.5 ;;
		45) _zte_sms_time_zone=$_zte_sms_time_sign$_zte_sms_time_hour.75 ;;
		*) return 1 ;;
	esac
	printf '%s;%s\n' "$_zte_sms_time_base" "$_zte_sms_time_zone"
}

zte_adapter_send_sms() {
	[ "${ZTE_ADAPTER_ID:-}" = zte_u30 ] || return 1
	_zte_sms_send_host=$1
	_zte_sms_send_number=$2
	_zte_sms_send_content=$3
	_zte_sms_send_jar=$4
	if ! zte_adapter_payload_phone "$_zte_sms_send_number" ||
		! zte_adapter_payload_text "$_zte_sms_send_content" 1 700; then
		return 1
	fi
	_zte_sms_send_encoded=$(zte_adapter_sms_encode \
		"$_zte_sms_send_content") || return 1
	_zte_sms_send_type=${_zte_sms_send_encoded%%|*}
	_zte_sms_send_body=${_zte_sms_send_encoded#*|}
	_zte_sms_send_time=$(zte_adapter_sms_time) || return 1
	_zte_sms_send_form="isTest=false&goformId=SEND_SMS&notCallback=true&$(zte_form_pair Number "$_zte_sms_send_number")&$(zte_form_pair sms_time "$_zte_sms_send_time")&MessageBody=$_zte_sms_send_body&ID=-1&encode_type=$_zte_sms_send_type"
	zte_adapter_u30_post_body "$_zte_sms_send_host" \
		"$_zte_sms_send_form" "$_zte_sms_send_jar"
}

zte_adapter_fetch_sms_command_status() {
	[ "${ZTE_ADAPTER_ID:-}" = zte_u30 ] || return 1
	_zte_sms_status_command=$2
	case $_zte_sms_status_command in 1|2|3|4|5|6) ;; *) return 1 ;; esac
	_zte_sms_status_origin=$(zte_adapter_origin "$1") || return 1
	_zte_sms_status_response=$(zte_http_get \
		"$_zte_sms_status_origin/goform/goform_get_cmd_process?cmd=sms_cmd_status_info&sms_cmd=$_zte_sms_status_command&isTest=false" \
		"$3") || return 1
	zte_json_is_flat_object "$_zte_sms_status_response" || return 1
	case $(zte_json_flat_get "$_zte_sms_status_response" \
		sms_cmd_status_result) in
		3) printf '%s\n' succeeded ;;
		2) printf '%s\n' failed ;;
		0|1|'') printf '%s\n' pending ;;
		*) return 1 ;;
	esac
}

zte_adapter_device_command() {
	case $2 in
		reboot) _zte_device_goform=REBOOT_DEVICE ;;
		shutdown) _zte_device_goform=SHUTDOWN_DEVICE ;;
		*) return 1 ;;
	esac
	zte_adapter_u30_post_body "$1" \
		"isTest=false&goformId=$_zte_device_goform" "$3"
}

zte_adapter_probe_status() {
	_zte_probe_origin=$(zte_adapter_origin "$1") || return 1
	_zte_probe_response=$(zte_http_get \
		"$_zte_probe_origin/goform/goform_get_cmd_process?cmd=mc_modem_main_state&isTest=false" \
		"$2") || return 1
	zte_json_is_flat_object "$_zte_probe_response" &&
		zte_json_flat_has "$_zte_probe_response" mc_modem_main_state
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
	if zte_json_flat_has "$_zte_raw" power_supply_mode; then
		_zte_power_supply_mode=$(zte_json_flat_get \
			"$_zte_raw" power_supply_mode)
		case $_zte_power_supply_mode in
			0) _zte_direct_supply=false ;;
			1) _zte_direct_supply=true ;;
			*) return 1 ;;
		esac
		_zte_power_supply_mode_json="\"$_zte_power_supply_mode\""
	else
		_zte_power_supply_mode_json=null
		_zte_direct_supply=null
	fi

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

	printf '{"online":true,"adapter":"%s","model":"%s","firmware":%s,"hardware_version":%s,"webui_version":%s,"software_version":%s,"market_name":%s,"upgrade":{"new_version_state":%s,"current_state":%s},"modem_state":"%s","cellular":{"type":"%s","provider":"%s","signalbar":"%s","rsrp":"%s","lte_rsrp":%s,"rscp":%s,"rssi":%s,"roaming":%s,"dial_mode":%s,"wan_mode":%s,"connection_mode":%s,"auto_roaming_raw":%s,"network_mode_raw":%s,"network_selection_mode_raw":%s,"radio":{"snr_raw":%s,"sinr_raw":%s,"ca_state_raw":%s,"primary_band_raw":%s,"primary_bandwidth_raw":%s,"secondary_band_raw":%s,"secondary_bandwidth_raw":%s,"primary_arfcn_raw":%s,"secondary_arfcn_raw":%s,"active_band_raw":%s},"pdp":{"ipv4_type_raw":%s,"ipv6_type_raw":%s},"mcc":%s,"mnc":%s,"ppp_status":"%s"},"sim":{"active_slot_raw":%s,"type":%s},"wifi":{"enabled":%s,"guest_enabled":%s,"bands":{"wifi_2_4":{"ssid":%s,"auth_mode":%s,"clients":%s},"wifi_5":{"ssid":%s,"auth_mode":%s,"clients":%s}},"radio_off_raw":%s,"primary":{"ssid":%s,"auth_mode":%s,"hidden_raw":%s,"max_clients_raw":%s,"isolation_raw":%s},"guest":{"enabled_raw":%s,"ssid":%s,"auth_mode":%s,"hidden_raw":%s,"max_clients_raw":%s,"isolation_raw":%s},"advanced":{"mode_raw":%s,"country_raw":%s,"channel_raw":%s,"bandwidth_raw":%s,"coverage_raw":%s},"sleep_status_raw":%s},"clients":%s,"battery":{"present":%s,"percent":%s,"charging":%s,"value":%s,"pers":%s,"temperature_level":%s},"power_supply":{"mode_raw":%s,"direct_supply":%s},"traffic":{"realtime":{"upload_bps":%s,"download_bps":%s},"current":{"sent_bytes":%s,"received_bytes":%s,"connected_seconds":%s},"monthly":{"sent_bytes":%s,"received_bytes":%s,"connected_seconds":%s,"month":%s},"plan":{"enabled":%s,"unit":%s,"limit":%s,"alert_percent":%s,"auto_clear":%s,"clear_day":%s,"disconnect":%s}},"sms":{"total":%s},"missing":"%s"}\n' \
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
		"$_zte_power_supply_mode_json" "$_zte_direct_supply" \
		"$_zte_realtime_tx" "$_zte_realtime_rx" \
		"$_zte_current_tx" "$_zte_current_rx" "$_zte_current_time" \
		"$_zte_monthly_tx" "$_zte_monthly_rx" "$_zte_monthly_time" \
		"$_zte_month" "$_zte_plan_enabled" "$_zte_plan_unit" \
		"$_zte_plan_limit" "$_zte_plan_alert" "$_zte_plan_auto_clear" \
		"$_zte_plan_clear_day" "$_zte_plan_disconnect" \
		"$_zte_sms_total" \
		"$(zte_json_escape "$_zte_missing")"
}
