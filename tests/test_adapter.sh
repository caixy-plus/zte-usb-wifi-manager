#!/bin/sh
# HTTP stubs are invoked from production functions loaded with source, which
# ShellCheck 0.9 cannot trace across files.
# shellcheck disable=SC2034,SC2317,SC2329
set -eu
TEST_NAME=test_adapter
. ./tests/testlib.sh
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/session.sh"
. "$lib/adapter-zte-u25s-metadata.sh"
. "$lib/adapter-zte-u25s.sh"
. "$lib/snapshot.sh"

# The current target firmware advertises HAS_LOGIN:true. Writes must therefore
# authenticate, while read paths may still accept a valid anonymous probe.
assert_eq 1 "${ZTE_LOGIN_REQUIRED:-missing}"
assert_success zte_adapter_login_required
assert_eq true "$(
    zte_adapter_capabilities_json |
        node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).login_required)))'
)"
ZTE_LOGIN_REQUIRED=0
assert_failure zte_adapter_login_required
assert_eq false "$(
    zte_adapter_capabilities_json |
        node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).login_required)))'
)"
ZTE_LOGIN_REQUIRED=1

case $ZTE_READ_FIELDS in
    *Password*|*WPAPSK*|*passwd*|*sim_iccid*|*imei*|*imsi*)
        fail 'read field allowlist contains a credential or unique identifier'
        ;;
    *ConnectionMode*network_current_network_mode*RadioOff*SSID1*WirelessMode*SleepStatusForSingleChipCpe*)
        pass
        ;;
    *) fail 'read field allowlist is missing console parity fields' ;;
esac

# Capability JSON and action gates must use the same compile-time flags.
ZTE_CAP_SIM_SWITCH=1
assert_eq true "$(
    zte_adapter_capabilities_json |
        node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))'
)"
assert_success zte_adapter_action_supported switch_sim
ZTE_CAP_SIM_SWITCH=0
assert_eq false "$(
    zte_adapter_capabilities_json |
        node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).sim_switch)))'
)"
assert_failure zte_adapter_action_supported switch_sim

capability_matrix=$(zte_adapter_capabilities_json)
assert_eq implemented "$(printf '%s' "$capability_matrix" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).cellular_read?.implementation)))')"
assert_eq simulator_only "$(printf '%s' "$capability_matrix" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).clients_read?.verification)))')"
assert_eq spare_device_required "$(printf '%s' "$capability_matrix" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).sim_switch?.verification)))')"
assert_eq not_implemented "$(printf '%s' "$capability_matrix" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).wifi_write?.implementation)))')"
assert_eq native_console_only "$(printf '%s' "$capability_matrix" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).firmware_update?.implementation)))')"
assert_eq false "$(printf '%s' "$capability_matrix" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String((JSON.parse(s).feature_status||{}).sim_switch?.enabled)))')"

ZTE_CAP_SIM_SWITCH=1
assert_success zte_adapter_action_effectively_enabled \
    switch_sim 1 1
assert_eq true "$(
    zte_adapter_effective_capabilities_json 1 1 0 0 0 0 |
        node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).feature_status.sim_switch.enabled)))'
)"
assert_failure zte_adapter_action_effectively_enabled \
    switch_sim 0 1
assert_failure zte_adapter_action_effectively_enabled \
    switch_sim 1 0
assert_eq sim_switch_enabled "$(zte_adapter_action_feature_option switch_sim)"
assert_eq wifi_write_enabled "$(zte_adapter_action_feature_option set_wifi)"
assert_failure zte_adapter_action_feature_option unknown
ZTE_CAP_SIM_SWITCH=0

fixtures=./tests/fixtures/u25s
work=/tmp/zte-test-adapter.$$
mkdir -p "$work"
jar=$work/cookies.txt
printf x >"$jar"

jsonfilter() {
    node ./tests/jsonfilter_stub.js "$@"
}

# device flag mapping
assert_eq true "$(zte_adapter_bool 1)"
assert_eq false "$(zte_adapter_bool 0)"
assert_eq null "$(zte_adapter_bool '')"
assert_eq null "$(zte_adapter_bool maybe)"

# The target firmware reports modem_init_complete while fully registered and
# online; authenticated fixtures also use connected.
assert_success zte_adapter_modem_ready connected
assert_success zte_adapter_modem_ready modem_init_complete
assert_failure zte_adapter_modem_ready offline
assert_failure zte_adapter_modem_ready ''

# known-field gate
assert_success zte_adapter_has_any_field "$(cat "$fixtures/read_ok.json")"
assert_failure zte_adapter_has_any_field "$(cat "$fixtures/read_session_expired.json")"

# A firmware that exposes status without authentication must not be rejected
# merely because the cookie jar and credential are empty.
: >"$jar"
anonymous_logins=$work/anonymous-logins
: >"$anonymous_logins"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_session_login() {
    printf 'login\n' >>"$anonymous_logins"
    return 1
}
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { cat "$fixtures/read_ok.json"; }
anonymous_raw=$(zte_adapter_fetch 192.168.0.1 '' "$jar")
assert_eq "$(cat "$fixtures/read_ok.json")" "$anonymous_raw"
assert_eq 0 "$(wc -l <"$anonymous_logins" | tr -d ' ')"

# If the anonymous probe is valid JSON but has no known status fields, an
# absent password is a distinct "credentials required" outcome.
: >"$jar"
: >"$anonymous_logins"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { cat "$fixtures/read_session_expired.json"; }
set +e
zte_adapter_fetch 192.168.0.1 '' "$jar" >/dev/null
anonymous_status=$?
set -e
assert_eq 2 "$anonymous_status"
assert_eq 0 "$(wc -l <"$anonymous_logins" | tr -d ' ')"

# A rejected LOGIN is distinct from transport failure so the console can ask
# for a corrected credential without hiding the reason.
set +e
zte_adapter_fetch 192.168.0.1 rejected-password "$jar" >/dev/null
authentication_status=$?
set -e
assert_eq 3 "$authentication_status"

# An explicitly configured HAS_LOGIN:false firmware variant must never enter
# LOGIN after a malformed or unknown anonymous response.
ZTE_LOGIN_REQUIRED=0
: >"$anonymous_logins"
set +e
zte_adapter_fetch 192.168.0.1 stale-optional-password "$jar" >/dev/null
anonymous_status=$?
set -e
assert_eq 1 "$anonymous_status"
assert_eq 0 "$(wc -l <"$anonymous_logins" | tr -d ' ')"
ZTE_LOGIN_REQUIRED=1

# fetch with a warm cookie jar performs no login
: >"$jar"
printf x >"$jar"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { cat "$fixtures/read_ok.json"; }
raw=$(zte_adapter_fetch 192.168.0.1 secret "$jar")
assert_eq "$(cat "$fixtures/read_ok.json")" "$raw"

# Authenticated private collections have explicit status codes and never use
# the broad status field list.
client_raw='{"station_list":[{"mac_addr":"AA:BB:CC:DD:EE:FF","hostname":"Lab client","ip_addr":"192.0.2.10","ssid_index":"1","interfacetype":"WIFI1","ULSpeed":"12","DLSpeed":"34"}]}'
client_expected='{"available":true,"items":[{"mac":"AA:BB:CC:DD:EE:FF","hostname":"Lab client","ip":"192.0.2.10","ssid_index":"1","interface":"WIFI1","upload_rate_raw":"12","download_rate_raw":"34"}]}'
client_url_log=$work/client-url
client_login_log=$work/client-login
: >"$client_url_log"
: >"$client_login_log"
zte_http_get() {
    printf '%s\n' "$1" >>"$client_url_log"
    printf '%s\n' "$client_raw"
}
zte_session_login() {
    printf 'login\n' >>"$client_login_log"
    return 1
}
assert_eq "$client_expected" \
    "$(zte_adapter_fetch_clients 192.168.0.1 secret "$jar")"
assert_eq 0 "$(wc -l <"$client_login_log" | tr -d ' ')"
assert_eq 'http://192.168.0.1/goform/goform_get_cmd_process?cmd=station_list&isTest=false' \
    "$(cat "$client_url_log")"

zte_http_get() { printf '%s\n' '{"result":"failure"}'; }
set +e
zte_adapter_fetch_clients 192.168.0.1 '' "$jar" >/dev/null
client_status=$?
set -e
assert_eq 2 "$client_status"

: >"$client_login_log"
set +e
zte_adapter_fetch_clients 192.168.0.1 rejected "$jar" >/dev/null
client_status=$?
set -e
assert_eq 3 "$client_status"
assert_eq 1 "$(wc -l <"$client_login_log" | tr -d ' ')"

client_get_count=$work/client-get-count
printf 0 >"$client_get_count"
: >"$client_login_log"
zte_http_get() {
    count=$(cat "$client_get_count")
    count=$((count + 1))
    printf '%s' "$count" >"$client_get_count"
    if [ "$count" -eq 1 ]; then
        printf '%s\n' '{"result":"failure"}'
    else
        printf '%s\n' "$client_raw"
    fi
}
zte_session_login() {
    printf 'login\n' >>"$client_login_log"
    return 0
}
assert_eq "$client_expected" \
    "$(zte_adapter_fetch_clients 192.168.0.1 secret "$jar")"
assert_eq 2 "$(cat "$client_get_count")"
assert_eq 1 "$(wc -l <"$client_login_log" | tr -d ' ')"

device_with_clients=$(zte_adapter_normalize "$raw" "$client_expected")
assert_eq true "$(printf '%s' "$device_with_clients" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).clients.available)))')"
assert_eq 'AA:BB:CC:DD:EE:FF' "$(printf '%s' "$device_with_clients" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).clients.items[0].mac))')"
assert_eq '{"available":false,"reason":"credentials_missing","items":[]}' \
    "$(zte_adapter_clients_unavailable_json credentials_missing)"
assert_failure zte_adapter_clients_unavailable_json unknown

sms_raw='{"messages":[{"id":"7","number":"+8600000000000","content":"4F60597D","date":"26,08,01,09,30,00,+32","tag":"1","draft_group_id":"0","received_all_concat_sms":"1"}]}'
sms_expected='{"available":true,"items":[{"id":"7","number_raw":"+8600000000000","content_encoded":"4F60597D","date_raw":"26,08,01,09,30,00,+32","tag":"1","draft_group_id":"0","received_all_concat_sms":"1"}]}'
sms_url_log=$work/sms-url
sms_login_log=$work/sms-login
: >"$sms_url_log"
: >"$sms_login_log"
zte_http_get() {
    printf '%s\n' "$1" >>"$sms_url_log"
    printf '%s\n' "$sms_raw"
}
zte_session_login() {
    printf 'login\n' >>"$sms_login_log"
    return 1
}
assert_eq "$sms_expected" \
    "$(zte_adapter_fetch_sms 192.168.0.1 secret "$jar")"
assert_eq 0 "$(wc -l <"$sms_login_log" | tr -d ' ')"
assert_eq 'http://192.168.0.1/goform/goform_get_cmd_process?cmd=sms_data_total&page=0&data_per_page=50&mem_store=1&tags=10&order_by=order%20by%20id%20desc&isTest=false' \
    "$(cat "$sms_url_log")"

zte_http_get() { printf '%s\n' '{"result":"failure"}'; }
set +e
zte_adapter_fetch_sms 192.168.0.1 '' "$jar" >/dev/null
sms_status=$?
set -e
assert_eq 2 "$sms_status"

: >"$sms_login_log"
set +e
zte_adapter_fetch_sms 192.168.0.1 rejected "$jar" >/dev/null
sms_status=$?
set -e
assert_eq 3 "$sms_status"
assert_eq 1 "$(wc -l <"$sms_login_log" | tr -d ' ')"

sms_get_count=$work/sms-get-count
printf 0 >"$sms_get_count"
: >"$sms_login_log"
zte_http_get() {
    count=$(cat "$sms_get_count")
    count=$((count + 1))
    printf '%s' "$count" >"$sms_get_count"
    if [ "$count" -eq 1 ]; then
        printf '%s\n' '{"result":"failure"}'
    else
        printf '%s\n' "$sms_raw"
    fi
}
zte_session_login() {
    printf 'login\n' >>"$sms_login_log"
    return 0
}
assert_eq "$sms_expected" \
    "$(zte_adapter_fetch_sms 192.168.0.1 secret "$jar")"
assert_eq 2 "$(cat "$sms_get_count")"
assert_eq 1 "$(wc -l <"$sms_login_log" | tr -d ' ')"
assert_eq '{"available":false,"reason":"read_failed","items":[]}' \
    "$(zte_adapter_sms_unavailable_json read_failed)"
assert_failure zte_adapter_sms_unavailable_json unknown

# normalize maps every field
expected='{"online":true,"model":"U25S","firmware":"TEST_FIRMWARE","hardware_version":null,"webui_version":null,"software_version":null,"market_name":null,"upgrade":{"new_version_state":null,"current_state":null},"modem_state":"connected","cellular":{"type":"NR5G-SA","provider":"中国移动","signalbar":"4","rsrp":"-68","lte_rsrp":null,"rscp":null,"rssi":null,"roaming":null,"dial_mode":null,"wan_mode":null,"mcc":null,"mnc":null,"ppp_status":"ipv4_ipv6_connected"},"sim":{"active_slot_raw":"1","type":"physical"},"wifi":{"enabled":null,"guest_enabled":null,"bands":{"wifi_2_4":{"ssid":null,"auth_mode":null,"clients":null},"wifi_5":{"ssid":null,"auth_mode":null,"clients":null}}},"clients":{"available":false,"reason":"not_loaded","items":[]},"battery":{"present":true,"percent":82,"charging":false,"value":"4050","pers":"82","temperature_level":"normal"},"traffic":{"realtime":{"upload_bps":1250,"download_bps":3400},"current":{"sent_bytes":1024,"received_bytes":2048,"connected_seconds":3600},"monthly":{"sent_bytes":4096,"received_bytes":8192,"connected_seconds":7200,"month":"2026-08"},"plan":{"enabled":true,"unit":"data","limit":"10240","alert_percent":80,"auto_clear":true,"clear_day":1,"disconnect":false}},"sms":{"total":3},"missing":"network_lte_rsrp,network_rscp,lte_rssi,network_simcard_roam,dial_mode,opms_wan_mode,network_rmcc,network_rmnc,wifi_onoff_state,guest_switch,wifi_chip1_ssid1_ssid,wifi_chip1_ssid1_auth_mode,wifi_chip1_ssid1_access_sta_num,wifi_chip2_ssid1_ssid,wifi_chip2_ssid1_auth_mode,wifi_chip2_ssid1_access_sta_num,hardware_version,web_version,wa_version,device_market_name,new_version_state,current_upgrade_state"}'
expected=$(printf '%s' "$expected" | sed \
    -e 's/"wan_mode":null,/"wan_mode":null,"connection_mode":null,"auto_roaming_raw":null,"network_mode_raw":null,"network_selection_mode_raw":null,/' \
    -e 's/}}},"clients"/}},"radio_off_raw":null,"primary":{"ssid":null,"auth_mode":null,"hidden_raw":null,"max_clients_raw":null,"isolation_raw":null},"guest":{"enabled_raw":null,"ssid":null,"auth_mode":null,"hidden_raw":null,"max_clients_raw":null,"isolation_raw":null},"advanced":{"mode_raw":null,"country_raw":null,"channel_raw":null,"bandwidth_raw":null,"coverage_raw":null},"sleep_status_raw":null},"clients"/' \
    -e 's/"network_selection_mode_raw":null,/"network_selection_mode_raw":null,"radio":{"snr_raw":null,"sinr_raw":null,"ca_state_raw":null,"primary_band_raw":null,"primary_bandwidth_raw":null,"secondary_band_raw":null,"secondary_bandwidth_raw":null,"primary_arfcn_raw":null,"secondary_arfcn_raw":null,"active_band_raw":null},"pdp":{"ipv4_type_raw":null,"ipv6_type_raw":null},/' \
    -e 's/current_upgrade_state"}/current_upgrade_state,ConnectionMode,autoConnectWhenRoaming,network_current_network_mode,network_net_select_mode,RadioOff,SSID1,AuthMode,HideSSID,MAX_Access_num,NoForwarding,m_ssid_enable,m_SSID,m_AuthMode,m_HideSSID,m_MAX_Access_num,m_NoForwarding,WirelessMode,CountryCode,Channel,wifi_11n_cap,wifi_coverage,SleepStatusForSingleChipCpe,Z5g_snr,Z5g_SINR,wan_lte_ca,network_lte_ca_pcell_band,bandwidth,network_lte_ca_scell_band,network_lte_ca_scell_bandwidth,network_lte_ca_pcell_arfcn,lte_ca_scell_arfcn,wan_active_band,apn_pdp_type,apn_ipv6_pdp_type"}/')
assert_eq "$expected" "$(zte_adapter_normalize "$raw")"
assert_success node -e 'JSON.parse(process.argv[1])' "$expected"

# Preserve the current firmware's additional radio and connection fields as
# normalized, nullable strings. Their device enums remain uninterpreted until
# authenticated fixtures prove their complete value sets.
extended_cellular=$(zte_adapter_normalize \
    '{"network_lte_rsrp":"-72","network_rscp":"-81","lte_rssi":"-55","network_simcard_roam":"0","dial_mode":"auto_dial","opms_wan_mode":"PPP","network_rmcc":"460","network_rmnc":"00"}')
assert_eq '-72' "$(printf '%s' "$extended_cellular" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.lte_rsrp))')"
assert_eq '-81' "$(printf '%s' "$extended_cellular" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.rscp))')"
assert_eq '-55' "$(printf '%s' "$extended_cellular" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.rssi))')"

console_status=$(zte_adapter_normalize '{"ConnectionMode":"auto_dial","autoConnectWhenRoaming":"1","network_current_network_mode":"LTE_NR","network_net_select_mode":"manual","RadioOff":"0","SSID1":"Primary","AuthMode":"WPA3PSK","HideSSID":"0","MAX_Access_num":"16","NoForwarding":"1","m_ssid_enable":"1","m_SSID":"Guest","m_AuthMode":"WPA2PSK","m_HideSSID":"1","m_MAX_Access_num":"4","m_NoForwarding":"1","WirelessMode":"11ax","CountryCode":"CN","Channel":"36","wifi_11n_cap":"80MHz","wifi_coverage":"2","SleepStatusForSingleChipCpe":"0"}')
assert_eq auto_dial "$(printf '%s' "$console_status" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.connection_mode))')"
assert_eq LTE_NR "$(printf '%s' "$console_status" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.network_mode_raw))')"
assert_eq Primary "$(printf '%s' "$console_status" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).wifi.primary.ssid))')"
assert_eq Guest "$(printf '%s' "$console_status" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).wifi.guest.ssid))')"
assert_eq 36 "$(printf '%s' "$console_status" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).wifi.advanced.channel_raw))')"
assert_eq 0 "$(printf '%s' "$console_status" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).wifi.sleep_status_raw))')"

radio_status=$(zte_adapter_normalize '{"Z5g_snr":"28","Z5g_SINR":"25","wan_lte_ca":"ca_activated","network_lte_ca_pcell_band":"n78","bandwidth":"100MHz","network_lte_ca_scell_band":"B3","network_lte_ca_scell_bandwidth":"20MHz","network_lte_ca_pcell_arfcn":"640000","lte_ca_scell_arfcn":"1650","wan_active_band":"NR5G","apn_pdp_type":"IPV4V6","apn_ipv6_pdp_type":"IPV6"}')
assert_eq 28 "$(printf '%s' "$radio_status" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.radio.snr_raw))')"
assert_eq n78 "$(printf '%s' "$radio_status" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.radio.primary_band_raw))')"
assert_eq IPV4V6 "$(printf '%s' "$radio_status" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.pdp.ipv4_type_raw))')"
assert_eq '0' "$(printf '%s' "$extended_cellular" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.roaming))')"
assert_eq 'auto_dial' "$(printf '%s' "$extended_cellular" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.dial_mode))')"
assert_eq 'PPP' "$(printf '%s' "$extended_cellular" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.wan_mode))')"
assert_eq '460' "$(printf '%s' "$extended_cellular" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.mcc))')"
assert_eq '00' "$(printf '%s' "$extended_cellular" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).cellular.mnc))')"

empty_extended=$(zte_adapter_normalize '{"network_type":"LTE"}')
assert_eq null "$(printf '%s' "$empty_extended" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).cellular.lte_rsrp)))')"

# Wi-Fi summary intentionally excludes every password/passphrase field.
wifi_summary=$(zte_adapter_normalize \
    '{"wifi_onoff_state":"1","guest_switch":"0","wifi_chip1_ssid1_ssid":"Lab-24","wifi_chip1_ssid1_auth_mode":"WPA2PSK","wifi_chip1_ssid1_access_sta_num":"2","wifi_chip2_ssid1_ssid":"Lab-5","wifi_chip2_ssid1_auth_mode":"WPA3PSK","wifi_chip2_ssid1_access_sta_num":"1"}')
assert_eq true "$(printf '%s' "$wifi_summary" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).wifi.enabled)))')"
assert_eq false "$(printf '%s' "$wifi_summary" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).wifi.guest_enabled)))')"
assert_eq 'Lab-24' "$(printf '%s' "$wifi_summary" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).wifi.bands.wifi_2_4.ssid))')"
assert_eq 'WPA2PSK' "$(printf '%s' "$wifi_summary" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).wifi.bands.wifi_2_4.auth_mode))')"
assert_eq 2 "$(printf '%s' "$wifi_summary" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).wifi.bands.wifi_2_4.clients)))')"
assert_eq 'Lab-5' "$(printf '%s' "$wifi_summary" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).wifi.bands.wifi_5.ssid))')"
assert_eq 'WPA3PSK' "$(printf '%s' "$wifi_summary" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).wifi.bands.wifi_5.auth_mode))')"
assert_eq 1 "$(printf '%s' "$wifi_summary" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(s).wifi.bands.wifi_5.clients)))')"
case $wifi_summary in
    *password*|*passphrase*|*WPAPSK*) fail 'normalized Wi-Fi summary leaked a password field' ;;
    *) pass ;;
esac

device_details=$(zte_adapter_normalize \
    '{"hardware_version":"HW-TEST","web_version":"WEB-TEST","wa_version":"SW-TEST","device_market_name":"U25S Test","new_version_state":"1","current_upgrade_state":"idle"}')
assert_eq 'HW-TEST' "$(printf '%s' "$device_details" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).hardware_version))')"
assert_eq 'WEB-TEST' "$(printf '%s' "$device_details" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).webui_version))')"
assert_eq 'SW-TEST' "$(printf '%s' "$device_details" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).software_version))')"
assert_eq 'U25S Test' "$(printf '%s' "$device_details" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).market_name))')"
assert_eq '1' "$(printf '%s' "$device_details" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).upgrade.new_version_state))')"
assert_eq 'idle' "$(printf '%s' "$device_details" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).upgrade.current_state))')"

# The target U25S WebUI treats battery_charging=2 as fully charged, not an
# invalid state. It must normalize to false so a full battery cannot make the
# daemon enter fail-safe or be reported as actively charging.
full_battery_out=$(zte_adapter_normalize \
    '{"battery_exist":"1","battery_vol_percent":"100","battery_charging":"2"}')
assert_eq false \
    "$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).battery.charging))' \
        "$full_battery_out")"
charging_battery_out=$(zte_adapter_normalize \
    '{"battery_exist":"1","battery_vol_percent":"99","battery_charging":"1"}')
assert_eq true \
    "$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).battery.charging))' \
        "$charging_battery_out")"

# Escaped strings and JSON whitespace survive extraction and normalization.
escaped_raw=$(printf '{\n"network_provider_fullname"\n:\n"ACME \\"5G\\""\n}')
escaped_out=$(zte_adapter_normalize "$escaped_raw")
assert_success node -e 'JSON.parse(process.argv[1])' "$escaped_out"
assert_eq 'ACME "5G"' \
    "$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).cellular.provider)' "$escaped_out")"

# Present battery fields must be semantically valid. A syntactically valid but
# damaged device response must fail the same fetch -> normalize path as polling.
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { printf '%s\n' "$invalid_response"; }
fetch_and_normalize() {
    _raw=$(zte_adapter_fetch 192.168.0.1 secret "$jar") &&
        zte_adapter_normalize "$_raw" >/dev/null
}
for invalid_response in \
    '{"battery_vol_percent":"150"}' \
    '{"battery_vol_percent":"-1"}' \
    '{"battery_vol_percent":"unknown"}' \
    '{"battery_vol_percent":"01"}' \
    '{"battery_vol_percent":"099"}' \
    '{"battery_exist":"maybe"}' \
    '{"battery_charging":"maybe"}'
do
    assert_failure zte_adapter_normalize "$invalid_response"
    assert_failure fetch_and_normalize
done
for invalid_response in \
    '{"sms_data_total":"-1"}' \
    '{"sms_data_total":"01"}' \
    '{"sms_data_total":"unknown"}'
do
    assert_failure zte_adapter_normalize "$invalid_response"
done
empty_sms_out=$(zte_adapter_normalize '{"sms_data_total":""}')
assert_eq null \
    "$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).sms.total))' \
        "$empty_sms_out")"

# A rejected candidate cannot replace the last trusted device snapshot.
invalid_response='{"battery_vol_percent":"01"}'
candidate=''
ok=0
if _raw=$(zte_adapter_fetch 192.168.0.1 secret "$jar") &&
    candidate=$(zte_adapter_normalize "$_raw"); then
    ok=1
fi
assert_eq 0 "$ok"
assert_eq "$expected" "$(zte_device_retain "$expected" "$candidate" "$ok")"

# Accepted boundary values always produce strict JSON.
for valid_percent in 0 1 99 100; do
    valid_out=$(zte_adapter_normalize \
        "{\"battery_vol_percent\":\"$valid_percent\"}")
    assert_success node -e 'JSON.parse(process.argv[1])' "$valid_out"
done

# missing fields become null and are reported in ZTE_READ_FIELDS order
out=$(zte_adapter_normalize "$(cat "$fixtures/read_missing_fields.json")")
case $out in
    *'"sim":{"active_slot_raw":null,"type":null}'*) pass ;;
    *) fail "missing SIM fields not nulled: $out" ;;
esac
case $out in
    *'"battery":{"present":false,"percent":null,"charging":null,"value":null,"pers":null,"temperature_level":null}'*) pass ;;
    *) fail "missing battery fields not nulled: $out" ;;
esac
case $out in
    *'"sms":{"total":null}'*) pass ;;
    *) fail "missing SMS fields not nulled: $out" ;;
esac
case $out in
    *'"missing":"mc_modem_main_state,network_signalbar,'*',flux_limited_disconnect,ConnectionMode,'*',SleepStatusForSingleChipCpe,'*',apn_ipv6_pdp_type"'*) pass ;;
    *'"missing":"mc_modem_main_state,network_signalbar,network_provider_fullname,Z5g_rsrp,ppp_status,simcard_active_slot_temp,usim_esim_type,battery_vol_percent,battery_charging,battery_value,battery_pers,battery_temperature_level,sms_data_total,network_lte_rsrp,network_rscp,lte_rssi,network_simcard_roam,dial_mode,opms_wan_mode,network_rmcc,network_rmnc,wifi_onoff_state,guest_switch,wifi_chip1_ssid1_ssid,wifi_chip1_ssid1_auth_mode,wifi_chip1_ssid1_access_sta_num,wifi_chip2_ssid1_ssid,wifi_chip2_ssid1_auth_mode,wifi_chip2_ssid1_access_sta_num,hardware_version,web_version,wa_version,device_market_name,new_version_state,current_upgrade_state,wa_inner_version,flux_realtime_tx_thrpt,flux_realtime_rx_thrpt,flux_realtime_tx_bytes,flux_realtime_rx_bytes,flux_realtime_time,flux_monthly_tx_bytes,flux_monthly_rx_bytes,flux_monthly_time,date_month,flux_data_volume_limit_switch,flux_data_volume_limit_unit,flux_data_volume_limit_size,flux_data_volume_alert_percent,flux_auto_clear_flow_data_switch,flux_clear_date,flux_limited_disconnect"'*) pass ;;
    *) fail "missing list wrong: $out" ;;
esac

# Empty counters follow the target service.js behavior and become zero, while
# malformed counters and non-boolean plan flags reject the candidate snapshot.
empty_traffic_out=$(zte_adapter_normalize \
    '{"flux_realtime_tx_thrpt":"","flux_monthly_rx_bytes":""}')
assert_eq 0 "$(node -e 'const v=JSON.parse(process.argv[1]);process.stdout.write(String(v.traffic.realtime.upload_bps))' "$empty_traffic_out")"
assert_eq 0 "$(node -e 'const v=JSON.parse(process.argv[1]);process.stdout.write(String(v.traffic.monthly.received_bytes))' "$empty_traffic_out")"
for invalid_response in \
    '{"flux_realtime_tx_thrpt":"01"}' \
    '{"flux_monthly_rx_bytes":"-1"}' \
    '{"flux_data_volume_alert_percent":"80%"}' \
    '{"flux_data_volume_limit_switch":"yes"}'
do
    assert_failure zte_adapter_normalize "$invalid_response"
done

# malformed response fails without any retry
get_calls=$work/get-calls
printf 0 >"$get_calls"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() {
    n=$(cat "$get_calls"); n=$((n + 1)); printf '%s' "$n" >"$get_calls"
    cat "$fixtures/read_malformed.json"
}
assert_failure zte_adapter_fetch 192.168.0.1 secret "$jar"
assert_eq 1 "$(cat "$get_calls")"

# stale session triggers exactly one relogin and one retry
ZTE_LOGIN_REQUIRED=1
printf 0 >"$get_calls"
logins=$work/logins
: >"$logins"
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_session_login() { printf 'x\n' >>"$logins"; return 0; }
# Injected into zte_adapter_fetch from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() {
    n=$(cat "$get_calls"); n=$((n + 1)); printf '%s' "$n" >"$get_calls"
    if [ "$n" -eq 1 ]; then
        cat "$fixtures/read_session_expired.json"
    else
        cat "$fixtures/read_ok.json"
    fi
}
raw2=$(zte_adapter_fetch 192.168.0.1 secret "$jar")
assert_eq "$(cat "$fixtures/read_ok.json")" "$raw2"
assert_eq 2 "$(cat "$get_calls")"
assert_eq 1 "$(wc -l <"$logins" | tr -d ' ')"
ZTE_LOGIN_REQUIRED=0

# Target firmware login page exposes four SIM choices. Keep the semantic
# action payload independent of the firmware's non-sequential physical slot.
assert_eq 1 "$(zte_adapter_sim_card_index sim1)"
assert_eq 2 "$(zte_adapter_sim_card_index sim2)"
assert_eq 3 "$(zte_adapter_sim_card_index sim3)"
assert_eq 0 "$(zte_adapter_sim_card_index physical)"
assert_failure zte_adapter_sim_card_index ''
assert_failure zte_adapter_sim_card_index sim4
assert_failure zte_adapter_sim_card_index 0

# Enumerated but unimplemented actions are strict default-deny. Enabling a
# capability flag alone must never make an unvalidated payload queueable.
for unregistered_action in \
    set_apn set_connection_mode set_wifi set_traffic_plan reset_traffic \
    send_sms delete_sms mark_sms_read
do
    assert_failure zte_adapter_action_payload_valid \
        "$unregistered_action" '{}'
done
assert_failure zte_adapter_action_payload_valid unknown '{}'

# The calibrated request shape must contain only the verified goform id and
# card_index mapping. A response other than the observed success token fails.
switch_post_log=$work/switch-post
zte_http_post() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >"$switch_post_log"
    printf '%s\n' '{"result":"success"}'
}
assert_success zte_adapter_switch_sim 192.168.0.1 sim2 "$jar"
assert_eq \
    "http://192.168.0.1/goform/goform_set_cmd_process|isTest=false&goformId=SIM_SWITCH_SIMCARD&card_index=2|$jar" \
    "$(cat "$switch_post_log")"
zte_http_post() { printf '%s\n' '{"result":"failure"}'; }
assert_failure zte_adapter_switch_sim 192.168.0.1 physical "$jar"
zte_http_post() { printf '%s\n' 'not-json'; }
assert_failure zte_adapter_switch_sim 192.168.0.1 sim1 "$jar"
assert_failure zte_adapter_switch_sim 192.168.0.1 invalid "$jar"

rm -rf "$work"
finish
