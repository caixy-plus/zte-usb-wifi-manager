#!/bin/sh
# Exercise the production executor -> adapter -> HTTP chain against a
# loopback-only, stateful U30 simulator. Transport is deliberately HTTP here;
# this test proves request/readback behavior, not production TLS behavior.
set -eu

TEST_NAME=test_u30_power_e2e
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/session.sh"
. "$lib/device-profile.sh"
. "$lib/adapter-zte-u25s-metadata.sh"
. "$lib/adapter-zte-u25s.sh"
. "$lib/action-executor.sh"

work=$(mktemp -d /tmp/zte-test-u30-power-e2e.XXXXXX)
ZTE_SESSION_LOCK_FILE=$work/session.lock
ZTE_SESSION_LOCK_ATTEMPTS=1
ZTE_SESSION_LOCK_INTERVAL=0
export ZTE_SESSION_LOCK_FILE ZTE_SESSION_LOCK_ATTEMPTS
export ZTE_SESSION_LOCK_INTERVAL
simulator_pid=
trap 'stop_simulator; rm -rf "$work"' EXIT HUP INT TERM

stop_simulator() {
    if [ -n "$simulator_pid" ]; then
        kill "$simulator_pid" 2>/dev/null || true
        wait "$simulator_pid" 2>/dev/null || true
        simulator_pid=
    fi
}

start_simulator() {
    stop_simulator
    scenario=$1
    initial_mode=$2
    ready_file=$work/ready
    request_log=$work/requests
    rm -f "$ready_file" "$request_log"
    python3 tests/u25s_simulator.py \
        --host 127.0.0.1 \
        --port 0 \
        --profile u30 \
        --scenario "$scenario" \
        --ready-file "$ready_file" \
        --request-log "$request_log" \
        --login-secret unused-u30-secret \
        --allow-u30-power-writes \
        --u30-power-mode "$initial_mode" \
        >"$work/server.out" 2>"$work/server.err" &
    simulator_pid=$!

    attempts=0
    while [ ! -s "$ready_file" ]; do
        if ! kill -0 "$simulator_pid" 2>/dev/null; then
            fail "U30 power simulator exited: $(cat "$work/server.err")"
            return 1
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 100 ]; then
            fail 'U30 power simulator did not become ready'
            return 1
        fi
        sleep 0.02
    done
    simulator_host=127.0.0.1:$(cat "$ready_file")
}

run_action() {
    target=$1
    action_status=0
    action_output=$(zte_execute_power_supply_mode \
        "$simulator_host" unused-u30-secret "$work/cookies" "$target" \
        2>>"$work/action.err") || action_status=$?
}

assert_exchange() {
    expected_output=$1
    expected_status=$2
    expected_mode=$3
    expected_reads=$4
    assert_eq "$expected_output" "$action_output"
    assert_eq "$expected_status" "$action_status"
    assert_eq 1 "$(grep -c '^POST U30_POWER ' "$request_log")" \
        'the non-idempotent production POST must be issued exactly once'
    assert_eq "$expected_mode" "$(
        sed -n 's/^POST U30_POWER [^ ]* requested=\([01]\).*/\1/p' \
            "$request_log"
    )" 'simulator must receive the requested raw mode'
    assert_eq "$expected_reads" "$(grep -c '^GET U30_POWER ' "$request_log")"
    if grep -Ei 'cookie|password|digest|unused-u30-secret|sensitive-canary' \
        "$request_log" "$work/action.err" "$work/server.err" \
        "$work/server.out" >/dev/null 2>&1; then
        fail 'U30 power simulator log exposed authentication material'
    else
        pass
    fi
    assert_eq 1 "$(grep -c '^GET LD ' "$request_log")" \
        'U30 power writes must fetch a fresh login challenge'
    assert_eq 1 "$(grep -c '^POST LOGIN ' "$request_log")" \
        'U30 power writes must authenticate before POST'
}

# Select the production U30 adapter explicitly, then replace only its scheme
# for loopback transport. This does not prove HTTPS, certificates, or a real
# device security contract.
assert_success zte_device_profile_select_named zte_u30
ZTE_DEVICE_PROFILE_SCHEME=http
ZTE_DEVICE_PROFILE_TLS_INSECURE=0
export ZTE_DEVICE_PROFILE_SCHEME ZTE_DEVICE_PROFILE_TLS_INSECURE
assert_success zte_adapter_apply_profile
assert_eq zte_u30 "$ZTE_ADAPTER_ID"
assert_eq http "$ZTE_ADAPTER_TRANSPORT"
assert_success zte_adapter_login_required
assert_eq 1 "$ZTE_CAP_SET_POWER_SUPPLY_MODE"
assert_success zte_adapter_action_supported set_power_supply_mode

ZTE_HTTP_TIMEOUT=0.2
ZTE_POWER_SUPPLY_READBACK_INTERVAL=0
ZTE_POWER_SUPPLY_READBACK_ATTEMPTS=3
export ZTE_HTTP_TIMEOUT ZTE_POWER_SUPPLY_READBACK_INTERVAL
export ZTE_POWER_SUPPLY_READBACK_ATTEMPTS

# A structurally valid anonymous write must be rejected before application.
start_simulator u30-power-success 1
anonymous_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 1 \
    -H "Referer: http://$simulator_host/" \
    -H "Origin: http://$simulator_host" \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-binary 'isTest=false&goformId=POWER_SUPPLY_SETTING&power_supply_mode=0' \
    "http://$simulator_host/goform/goform_set_cmd_process")
assert_eq 401 "$anonymous_code" 'anonymous U30 power write must be rejected'
assert_eq 1 "$(grep -c '^POST U30_POWER 401 requested=0 count=1$' \
    "$request_log")"

# A rejected credential must stop at LOGIN and issue no power POST.
start_simulator u30-power-success 1
rejected_status=0
rejected_output=$(zte_execute_power_supply_mode "$simulator_host" wrong-fixture \
    "$work/cookies" charging 2>>"$work/action.err") || rejected_status=$?
assert_eq authentication_failed "$rejected_output"
assert_eq 1 "$rejected_status"
assert_eq 0 "$(grep -c '^POST U30_POWER ' "$request_log")"
assert_eq 1 "$(grep -c '^POST LOGIN 403$' "$request_log")"

# The simulator rejects header drift and duplicate form keys so this E2E
# cannot pass with a looser request contract than the production WebUI shape.
start_simulator u30-power-success 0
invalid_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 1 \
    -H "Referer: http://$simulator_host/" \
    -H "Origin: http://$simulator_host" \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-binary 'isTest=false&goformId=POWER_SUPPLY_SETTING&power_supply_mode=1' \
    "http://$simulator_host/goform/goform_set_cmd_process")
assert_eq 400 "$invalid_code" 'missing XHR header must be rejected'
start_simulator u30-power-success 0
invalid_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 1 \
    -H "Referer: http://$simulator_host/" \
    -H "Origin: http://$simulator_host" \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-binary 'isTest=false&goformId=POWER_SUPPLY_SETTING&power_supply_mode=1&power_supply_mode=0' \
    "http://$simulator_host/goform/goform_set_cmd_process")
assert_eq 400 "$invalid_code" 'duplicate form keys must be rejected'
assert_eq 1 "$(grep -c 'requested=<invalid>' "$request_log")" \
    'invalid untrusted mode text must be sanitized before logging'

# Both production raw values are accepted and remain visible to later reads.
start_simulator u30-power-success 0
run_action direct_supply
assert_exchange ok 0 1 1

start_simulator u30-power-success 1
run_action charging
assert_exchange ok 0 0 1

# Explicit rejection and a timeout before application leave state unchanged.
start_simulator u30-power-reject 0
run_action direct_supply
assert_exchange device_rejected 1 1 0

start_simulator u30-power-timeout-before-apply 0
run_action direct_supply
assert_exchange write_ambiguous 1 1 3

# If the device applies the write before the response is lost, safe readback
# resolves the ambiguous transport result without repeating the POST.
start_simulator u30-power-apply-then-timeout 0
run_action direct_supply
assert_exchange ok 0 1 1

# Malformed and empty success responses are ambiguous. Readback is the sole
# authority that distinguishes applied from unapplied outcomes.
for scenario in u30-power-malformed-applied u30-power-empty-applied; do
    start_simulator "$scenario" 0
    run_action direct_supply
    assert_exchange ok 0 1 1
done
for scenario in u30-power-malformed-unapplied u30-power-empty-unapplied; do
    start_simulator "$scenario" 0
    run_action direct_supply
    assert_exchange write_ambiguous 1 1 3
done

# Bounded polling permits delayed convergence, but never converts a valid
# mismatch or invalid readback into success.
start_simulator u30-power-delayed-convergence 0
run_action direct_supply
assert_exchange ok 0 1 3

start_simulator u30-power-readback-mismatch 0
run_action direct_supply
assert_exchange readback_mismatch 1 1 3

start_simulator u30-power-readback-missing 0
run_action direct_supply
assert_exchange readback_failed 1 1 3

start_simulator u30-power-readback-malformed 0
run_action direct_supply
assert_exchange readback_failed 1 1 3

start_simulator u30-power-readback-timeout 0
run_action direct_supply
assert_exchange readback_failed 1 1 3

start_simulator u30-power-readback-invalid-mode 0
run_action direct_supply
assert_exchange readback_failed 1 1 3

finish
