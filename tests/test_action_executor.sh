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
        '{"simcard_active_slot_temp":"2","mc_modem_main_state":"connected","network_provider_fullname":"中国移动","ppp_status":"ipv4_ipv6_connected"}'
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

finish
