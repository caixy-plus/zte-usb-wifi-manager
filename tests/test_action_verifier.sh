#!/bin/sh
# shellcheck disable=SC2034,SC2329
set -eu

TEST_NAME=test_action_verifier
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/adapter-zte-u25s-metadata.sh"
. "$lib/action-executor.sh"

ZTE_ADAPTER_ID=zte_u30
ZTE_DEVICE_PROFILE_ID=zte_u30
host=192.168.0.1
jar=/tmp/fixture-cookie-jar
work=$(mktemp -d /tmp/zte-test-action-verifier.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mutation_log=$work/mutations
: >"$mutation_log"

# Every mutating adapter entry point is a tripwire: restart verification must
# be implemented exclusively with the read-only fetch contracts below.
record_mutation() { printf '%s\n' mutation >>"$mutation_log"; return 1; }
zte_adapter_set_apn() { record_mutation; }
zte_adapter_set_connection_mode() { record_mutation; }
zte_adapter_set_wifi() { record_mutation; }
zte_adapter_set_traffic_plan() { record_mutation; }
zte_adapter_reset_traffic() { record_mutation; }
zte_adapter_set_power_supply_mode() { record_mutation; }
zte_adapter_switch_sim() { record_mutation; }
zte_adapter_send_sms() { record_mutation; }
zte_adapter_delete_sms() { record_mutation; }
zte_adapter_mark_sms_read() { record_mutation; }
zte_adapter_device_command() { record_mutation; }
zte_session_login() { record_mutation; }

verify_success() {
    _test_action=$1
    _test_payload=$2
    _test_record=$(printf \
        '{"operation_id":"op-1722400000-8000","type":"%s","state":"verifying","payload":%s,"created":1722400000}' \
        "$_test_action" "$_test_payload")
    _test_result=$(zte_verify_action_after_restart \
        "$host" "$jar" "$_test_action" "$_test_record")
    _test_status=$?
    assert_eq 0 "$_test_status"
    assert_eq verified_after_restart "$_test_result"
}

verify_failure() {
    _test_expected=$1
    _test_action=$2
    _test_payload=$3
    _test_record=$(printf \
        '{"operation_id":"op-1722400000-8000","type":"%s","state":"verifying","payload":%s,"created":1722400000}' \
        "$_test_action" "$_test_payload")
    if _test_result=$(zte_verify_action_after_restart \
        "$host" "$jar" "$_test_action" "$_test_record"); then
        _test_status=0
    else
        _test_status=$?
    fi
    assert_eq 1 "$_test_status"
    assert_eq "$_test_expected" "$_test_result"
}

zte_adapter_fetch_apn_setting() {
    printf '%s\n' '{"apn":"fixture","auth":"none","username":""}'
}
verify_success set_apn \
    '{"action":"set_apn","apn":"fixture","auth":"none"}'
zte_adapter_fetch_apn_setting() {
    printf '%s\n' '{"apn":"other","auth":"none","username":""}'
}
verify_failure readback_mismatch set_apn \
    '{"action":"set_apn","apn":"fixture","auth":"none"}'

zte_adapter_fetch_connection_mode() { printf '%s\n' 'manual|off'; }
verify_success set_connection_mode \
    '{"action":"set_connection_mode","mode":"manual"}'

zte_adapter_fetch_wifi_setting() {
    printf '%s\n' '{"enabled":true,"band":"2g","ssid":"fixture","security":"wpa2_psk"}'
}
verify_success set_wifi \
    '{"action":"set_wifi","enabled":true,"band":"2g","ssid":"fixture","security":"wpa2_psk","password":"fixture-pass","channel":"auto"}'
zte_adapter_fetch_wifi_setting() { return 1; }
verify_failure readback_failed set_wifi \
    '{"action":"set_wifi","enabled":false}'

zte_adapter_fetch_traffic_plan() { printf '%s\n' '1|data|1000|90|1|1|0'; }
verify_success set_traffic_plan \
    '{"action":"set_traffic_plan","enabled":true,"limit_bytes":1000,"alert_percent":90,"cycle_day":1,"disconnect":false}'
zte_adapter_fetch_traffic_counters() { printf '%s\n' '0|0|0'; }
verify_success reset_traffic '{"action":"reset_traffic","confirm":true}'

zte_adapter_fetch_power_supply_mode() { printf '%s\n' direct_supply; }
verify_success set_power_supply_mode \
    '{"action":"set_power_supply_mode","mode":"direct_supply"}'

zte_adapter_fetch_sim_recovery_state() {
    printf '%s\n' \
        '{"target":"sim2","modem":"modem_init_complete","provider":"Fixture Carrier","ppp":"ipv4_ipv6_connected"}'
}
ZTE_DEVICE_PROFILE_ID=zte_u25s
ZTE_ADAPTER_ID=zte_u25s
verify_success switch_sim \
    '{"action":"switch_sim","target":"sim2","confirm":true}'
zte_adapter_fetch_sim_recovery_state() {
    printf '%s\n' \
        '{"target":"physical","modem":"modem_init_complete","provider":"Fixture Carrier","ppp":"ipv4_ipv6_connected"}'
}
verify_failure readback_mismatch switch_sim \
    '{"action":"switch_sim","target":"sim2","confirm":true}'

zte_adapter_fetch_sim_recovery_state() {
    printf '%s\n' \
        '{"target":"sim2","modem":"initializing","provider":"Fixture Carrier","ppp":"ipv4_ipv6_connected"}'
}
verify_failure readback_mismatch switch_sim \
    '{"action":"switch_sim","target":"sim2","confirm":true}'
zte_adapter_fetch_sim_recovery_state() {
    printf '%s\n' \
        '{"target":"sim2","modem":"modem_init_complete","provider":"","ppp":"ipv4_ipv6_connected"}'
}
verify_failure readback_mismatch switch_sim \
    '{"action":"switch_sim","target":"sim2","confirm":true}'
zte_adapter_fetch_sim_recovery_state() {
    printf '%s\n' \
        '{"target":"sim2","modem":"modem_init_complete","provider":"Fixture Carrier","ppp":"disconnected"}'
}
verify_failure readback_mismatch switch_sim \
    '{"action":"switch_sim","target":"sim2","confirm":true}'

# U30 has no calibrated SIM-switch contract. Recovery is inconclusive without
# performing even a read for this unsupported profile/action pair.
fetch_log=$work/fetches
: >"$fetch_log"
zte_adapter_fetch_sim_recovery_state() {
    printf '%s\n' fetch >>"$fetch_log"
    return 1
}
ZTE_DEVICE_PROFILE_ID=zte_u30
ZTE_ADAPTER_ID=zte_u30
verify_failure verification_inconclusive switch_sim \
    '{"action":"switch_sim","target":"sim2","confirm":true}'
assert_eq 0 "$(wc -l <"$fetch_log" | tr -d ' ')"

# The latest-50 SMS window cannot prove deletion. Until exact-ID or complete
# pagination exists, delete recovery is always inconclusive and does no GET.
zte_adapter_fetch_sms_message_state() {
    printf '%s\n' fetch >>"$fetch_log"
    printf '%s\n' absent
}
verify_failure verification_inconclusive delete_sms \
    '{"action":"delete_sms","message_id":"42","confirm":true}'
assert_eq 0 "$(wc -l <"$fetch_log" | tr -d ' ')"
zte_adapter_fetch_sms_message_state() { printf '%s\n' 0; }
verify_success mark_sms_read \
    '{"action":"mark_sms_read","message_id":"42"}'
zte_adapter_fetch_sms_message_state() { printf '%s\n' absent; }
verify_failure verification_inconclusive mark_sms_read \
    '{"action":"mark_sms_read","message_id":"42"}'
zte_adapter_fetch_sms_message_state() { printf '%s\n' 1; }
verify_failure readback_mismatch mark_sms_read \
    '{"action":"mark_sms_read","message_id":"42"}'

verify_failure verification_inconclusive send_sms \
    '{"action":"send_sms","number":"+12025550123","content":"fixture"}'
verify_failure verification_inconclusive reboot_device \
    '{"action":"reboot_device","confirm":true}'
verify_failure verification_inconclusive shutdown_device \
    '{"action":"shutdown_device","confirm":true}'

# Recovery revalidates the durable payload, independent of current feature
# flags. A tampered payload does not reach any fetcher.
fetch_log=$work/payload-fetches
: >"$fetch_log"
zte_adapter_fetch_connection_mode() {
    printf '%s\n' fetch >>"$fetch_log"
    printf '%s\n' 'automatic|off'
}
verify_failure readback_failed set_connection_mode \
    '{"action":"set_connection_mode","mode":"automatic","extra":"bad"}'
assert_eq 0 "$(wc -l <"$fetch_log" | tr -d ' ')"
assert_eq 0 "$(wc -l <"$mutation_log" | tr -d ' ')"

finish
