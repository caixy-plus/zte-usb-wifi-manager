#!/bin/sh
# Production functions call test doubles defined below.
# shellcheck disable=SC1090,SC2317,SC2329
set -eu

TEST_NAME=test_action_executor
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
executor=$lib/action-executor.sh
if [ ! -f "$executor" ]; then
    fail 'action executor library must exist'
    finish
fi

. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/session.sh"
. "$lib/adapter-zte-u25s-metadata.sh"
. "$lib/adapter-zte-u25s.sh"
. "$executor"

work=$(mktemp -d /tmp/zte-test-action-executor.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
login_log=$work/logins
switch_log=$work/switches
fetch_log=$work/fetches
sleep_log=$work/sleeps
: >"$login_log"
: >"$switch_log"
: >"$fetch_log"
: >"$sleep_log"
ZTE_LOGIN_REQUIRED=1

zte_session_login() {
    printf '%s|%s\n' "$1" "$3" >>"$login_log"
}

# First request simulates one expired session; the idempotent retry succeeds.
zte_adapter_switch_sim() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$switch_log"
    [ "$(wc -l <"$switch_log" | tr -d ' ')" -ge 2 ]
}

zte_adapter_fetch() {
    printf '%s|%s\n' "$1" "$3" >>"$fetch_log"
    printf '%s\n' \
        '{"simcard_active_slot_temp":"2","mc_modem_main_state":"modem_init_complete","network_provider_fullname":"中国移动","ppp_status":"ipv4_ipv6_connected"}'
}

sleep() {
    printf '%s\n' "$1" >>"$sleep_log"
}

export ZTE_SIM_READBACK_ATTEMPTS=3
export ZTE_SIM_READBACK_INTERVAL=2
assert_eq ok "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim2
)"
assert_eq 2 "$(wc -l <"$login_log" | tr -d ' ')"
assert_eq 2 "$(wc -l <"$switch_log" | tr -d ' ')"
assert_eq 1 "$(wc -l <"$fetch_log" | tr -d ' ')"
assert_eq 0 "$(wc -l <"$sleep_log" | tr -d ' ')"

: >"$login_log"
: >"$switch_log"
: >"$fetch_log"
assert_eq invalid_target "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" invalid
)"
assert_eq 0 "$(wc -l <"$login_log" | tr -d ' ')"
assert_eq 0 "$(wc -l <"$switch_log" | tr -d ' ')"
assert_eq credentials_missing "$(
    zte_execute_switch_sim 192.168.0.1 '' "$work/cookies" sim1
)"
zte_session_login() { return 1; }
assert_eq authentication_failed "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim1
)"
zte_session_login() {
    printf '%s|%s\n' "$1" "$3" >>"$login_log"
}

# A successful write is not accepted until the observed active slot matches.
zte_adapter_switch_sim() { return 0; }
zte_adapter_fetch() {
    printf '%s\n' \
        '{"simcard_active_slot_temp":"1","mc_modem_main_state":"connected","network_provider_fullname":"中国移动","ppp_status":"ipv4_ipv6_connected"}'
}
: >"$sleep_log"
export ZTE_SIM_READBACK_ATTEMPTS=2
assert_eq readback_mismatch "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim3
)"
assert_eq 1 "$(wc -l <"$sleep_log" | tr -d ' ')"

# Matching the target slot alone is insufficient: each later recovery stage
# must be confirmed from fields observed in the sanitized device fixture.
export ZTE_SIM_READBACK_ATTEMPTS=1
zte_adapter_fetch() {
    printf '%s\n' \
        '{"simcard_active_slot_temp":"2","mc_modem_main_state":"","network_provider_fullname":"中国移动","ppp_status":"ipv4_ipv6_connected"}'
}
assert_eq modem_not_ready "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim2
)"

zte_adapter_fetch() {
    printf '%s\n' \
        '{"simcard_active_slot_temp":"2","mc_modem_main_state":"connected","network_provider_fullname":"","ppp_status":"ipv4_ipv6_connected"}'
}
assert_eq network_not_registered "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim2
)"

zte_adapter_fetch() {
    printf '%s\n' \
        '{"simcard_active_slot_temp":"2","mc_modem_main_state":"connected","network_provider_fullname":"中国移动","ppp_status":""}'
}
assert_eq ppp_not_restored "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim2
)"

# Polling remains bounded while allowing the four ordered stages to recover.
: >"$fetch_log"
: >"$sleep_log"
export ZTE_SIM_READBACK_ATTEMPTS=5
zte_adapter_fetch() {
    printf '%s\n' fetch >>"$fetch_log"
    case $(wc -l <"$fetch_log" | tr -d ' ') in
        1)
            printf '%s\n' \
                '{"simcard_active_slot_temp":"1","mc_modem_main_state":"connected","network_provider_fullname":"中国移动","ppp_status":"ipv4_ipv6_connected"}'
            ;;
        2)
            printf '%s\n' \
                '{"simcard_active_slot_temp":"2","mc_modem_main_state":"","network_provider_fullname":"中国移动","ppp_status":"ipv4_ipv6_connected"}'
            ;;
        3)
            printf '%s\n' \
                '{"simcard_active_slot_temp":"2","mc_modem_main_state":"connected","network_provider_fullname":"","ppp_status":"ipv4_ipv6_connected"}'
            ;;
        4)
            printf '%s\n' \
                '{"simcard_active_slot_temp":"2","mc_modem_main_state":"connected","network_provider_fullname":"中国移动","ppp_status":""}'
            ;;
        *)
            printf '%s\n' \
                '{"simcard_active_slot_temp":"2","mc_modem_main_state":"connected","network_provider_fullname":"中国移动","ppp_status":"ipv4_ipv6_connected"}'
            ;;
    esac
}
assert_eq ok "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim2
)"
assert_eq 5 "$(wc -l <"$fetch_log" | tr -d ' ')"
assert_eq 4 "$(wc -l <"$sleep_log" | tr -d ' ')"

# Transport or parsing failures remain distinct from a valid mismatched slot.
zte_adapter_fetch() { return 1; }
: >"$sleep_log"
export ZTE_SIM_READBACK_ATTEMPTS=2
assert_eq readback_failed "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" physical
)"
assert_eq 1 "$(wc -l <"$sleep_log" | tr -d ' ')"

# Malformed JSON and missing verification fields can never confirm success.
export ZTE_SIM_READBACK_ATTEMPTS=1
zte_adapter_fetch() {
    printf '%s\n' '{"simcard_active_slot_temp":"2"'
}
assert_eq readback_failed "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim2
)"
zte_adapter_fetch() {
    printf '%s\n' \
        '{"simcard_active_slot_temp":"","mc_modem_main_state":"","network_provider_fullname":"","ppp_status":""}'
}
assert_eq readback_failed "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim2
)"
zte_adapter_fetch() {
    printf '%s\n' \
        '{"simcard_active_slot_temp":"2","mc_modem_main_state":"connected"}'
}
assert_eq readback_failed "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim2
)"

# A second rejected idempotent write is a bounded terminal failure.
zte_adapter_switch_sim() { return 1; }
: >"$login_log"
assert_eq write_failed "$(
    zte_execute_switch_sim 192.168.0.1 secret "$work/cookies" sim1
)"
assert_eq 2 "$(wc -l <"$login_log" | tr -d ' ')"

# An explicitly configured HAS_LOGIN:false firmware variant must not reject an
# empty credential or attempt LOGIN before its gated write.
# shellcheck disable=SC2034
ZTE_LOGIN_REQUIRED=0
: >"$login_log"
zte_session_login() {
    printf 'unexpected-login\n' >>"$login_log"
    return 1
}
zte_adapter_switch_sim() { return 0; }
zte_adapter_fetch() {
    printf '%s\n' \
        '{"simcard_active_slot_temp":"2","mc_modem_main_state":"connected","network_provider_fullname":"中国移动","ppp_status":"ipv4_ipv6_connected"}'
}
export ZTE_SIM_READBACK_ATTEMPTS=1
assert_eq ok "$(
    zte_execute_switch_sim 192.168.0.1 '' "$work/cookies" sim2
)"
assert_eq 0 "$(wc -l <"$login_log" | tr -d ' ')"

# U30 power-supply writes are never retried after an ambiguous POST. A result
# is accepted only after an exact safe GET readback.
power_write_log=$work/power-writes
power_read_log=$work/power-reads
: >"$power_write_log"
: >"$power_read_log"
zte_adapter_set_power_supply_mode() {
    printf '%s\n' "$2" >>"$power_write_log"
}
zte_adapter_fetch_power_supply_mode() {
    printf '%s\n' read >>"$power_read_log"
    printf '%s\n' direct_supply
}
export ZTE_POWER_SUPPLY_READBACK_ATTEMPTS=2
export ZTE_POWER_SUPPLY_READBACK_INTERVAL=0
assert_eq ok "$(zte_execute_power_supply_mode \
    192.168.0.1 '' "$work/cookies" direct_supply)"
assert_eq 1 "$(wc -l <"$power_write_log" | tr -d ' ')"
assert_eq 1 "$(wc -l <"$power_read_log" | tr -d ' ')"

zte_adapter_set_power_supply_mode() {
    printf '%s\n' attempted >>"$power_write_log"
    return 1
}
: >"$power_write_log"
assert_eq write_ambiguous "$(zte_execute_power_supply_mode \
    192.168.0.1 '' "$work/cookies" charging)"
assert_eq 1 "$(wc -l <"$power_write_log" | tr -d ' ')"

zte_adapter_set_power_supply_mode() { return 0; }
zte_adapter_fetch_power_supply_mode() { printf '%s\n' charging; }
export ZTE_POWER_SUPPLY_READBACK_ATTEMPTS=1
assert_eq readback_mismatch "$(zte_execute_power_supply_mode \
    192.168.0.1 '' "$work/cookies" direct_supply)"
assert_eq invalid_target "$(zte_execute_power_supply_mode \
    192.168.0.1 '' "$work/cookies" invalid)"

# Non-destructive U30 settings use one non-retriable POST followed by bounded,
# safe GET readback. The queued record remains the only payload source.
setting_write_log=$work/setting-writes
: >"$setting_write_log"
zte_adapter_set_connection_mode() {
    printf 'connection|%s\n' "$2" >>"$setting_write_log"
}
zte_adapter_fetch_connection_mode() { printf '%s\n' automatic; }
export ZTE_SETTING_READBACK_ATTEMPTS=2
export ZTE_SETTING_READBACK_INTERVAL=0
connection_record='{"payload":{"action":"set_connection_mode","mode":"automatic"}}'
assert_eq ok "$(zte_execute_u30_setting 192.168.0.1 '' "$work/cookies" \
    set_connection_mode "$connection_record")"
assert_eq 'connection|automatic' "$(cat "$setting_write_log")"

zte_adapter_fetch_connection_mode() { printf '%s\n' manual; }
assert_eq readback_mismatch "$(zte_execute_u30_setting 192.168.0.1 '' \
    "$work/cookies" set_connection_mode "$connection_record")"
zte_adapter_set_connection_mode() { return 1; }
assert_eq write_ambiguous "$(zte_execute_u30_setting 192.168.0.1 '' \
    "$work/cookies" set_connection_mode "$connection_record")"

zte_adapter_set_traffic_plan() {
    printf 'traffic|%s|%s|%s|%s|%s\n' "$2" "$3" "$4" "$5" "$6" \
        >>"$setting_write_log"
}
zte_adapter_fetch_traffic_plan() { printf '%s\n' '1|10737418240|90|1|0'; }
traffic_record='{"payload":{"action":"set_traffic_plan","enabled":true,"limit_bytes":10737418240,"alert_percent":90,"cycle_day":1,"disconnect":false}}'
assert_eq ok "$(zte_execute_u30_setting 192.168.0.1 '' "$work/cookies" \
    set_traffic_plan "$traffic_record")"

zte_adapter_reset_traffic() { printf '%s\n' reset >>"$setting_write_log"; }
zte_adapter_fetch_traffic_counters() { printf '%s\n' '0|0|0'; }
reset_record='{"payload":{"action":"reset_traffic","confirm":true}}'
assert_eq ok "$(zte_execute_u30_setting 192.168.0.1 '' "$work/cookies" \
    reset_traffic "$reset_record")"
assert_eq invalid_action "$(zte_execute_u30_setting 192.168.0.1 '' \
    "$work/cookies" reboot_device '{"payload":{}}')"

# SMS delete/read actions must be confirmed from a fresh inbox read. Device
# reboot requires an observed outage followed by recovery; shutdown requires
# a bounded sequence of failed probes and remains capability-gated.
zte_adapter_delete_sms() { return 0; }
zte_adapter_mark_sms_read() { return 0; }
zte_adapter_fetch_sms_message_state() { printf '%s\n' absent; }
delete_record='{"payload":{"action":"delete_sms","message_id":"42","confirm":true}}'
assert_eq ok "$(zte_execute_u30_sms_action 192.168.0.1 '' "$work/cookies" \
    delete_sms "$delete_record")"
zte_adapter_fetch_sms_message_state() { printf '%s\n' 0; }
read_record='{"payload":{"action":"mark_sms_read","message_id":"42"}}'
assert_eq ok "$(zte_execute_u30_sms_action 192.168.0.1 '' "$work/cookies" \
    mark_sms_read "$read_record")"
zte_adapter_fetch_sms_message_state() { printf '%s\n' 1; }
assert_eq readback_mismatch "$(zte_execute_u30_sms_action 192.168.0.1 '' \
    "$work/cookies" mark_sms_read "$read_record")"

device_probe_count=0
zte_adapter_device_command() { return 0; }
zte_adapter_probe_status() {
    device_probe_count=$((device_probe_count + 1))
    [ "$device_probe_count" -ge 2 ]
}
export ZTE_DEVICE_ACTION_ATTEMPTS=3
export ZTE_DEVICE_ACTION_INTERVAL=0
assert_eq ok "$(zte_execute_u30_device_action 192.168.0.1 '' \
    "$work/cookies" reboot_device)"
zte_adapter_probe_status() { return 1; }
assert_eq ok "$(zte_execute_u30_device_action 192.168.0.1 '' \
    "$work/cookies" shutdown_device)"
zte_adapter_device_command() { return 1; }
assert_eq write_ambiguous "$(zte_execute_u30_device_action 192.168.0.1 '' \
    "$work/cookies" reboot_device)"

finish
