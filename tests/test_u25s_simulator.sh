#!/bin/sh
set -eu

TEST_NAME=test_u25s_simulator
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/session.sh"
. "$lib/adapter-zte-u25s-metadata.sh"
. "$lib/adapter-zte-u25s.sh"
. "$lib/action-executor.sh"

# This simulator intentionally exercises the authenticated firmware variant;
# the inspected production U25S overrides this contract to anonymous mode.
# shellcheck disable=SC2034
ZTE_LOGIN_REQUIRED=1

if python3 - <<'PY'
import importlib.util
import tempfile
import threading
from pathlib import Path

module_path = Path("tests/u25s_simulator.py")
spec = importlib.util.spec_from_file_location("u25s_simulator", module_path)
simulator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulator)

assert simulator.validate_bind_host("127.0.0.1") == "127.0.0.1"
assert simulator.validate_profile("u25s") == "u25s"
assert simulator.validate_profile("u30") == "u30"
try:
    simulator.validate_profile("generic-zte")
except ValueError:
    pass
else:
    raise AssertionError("accepted an unknown device profile")
for unsafe_host in ("localhost", "0.0.0.0", "::1"):
    try:
        simulator.validate_bind_host(unsafe_host)
    except ValueError:
        pass
    else:
        raise AssertionError(f"accepted non-literal bind host: {unsafe_host}")

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    state = simulator.SimulatorState(
        "expire-once",
        "fixture-value",
        Path("tests/fixtures/u25s/read_ok.json"),
        root / "requests",
    )
    session_id = state.create_session()
    barrier = threading.Barrier(3)
    results = []

    def check_session():
        barrier.wait()
        results.append(state.status_session_state(session_id))

    threads = [threading.Thread(target=check_session) for _ in range(2)]
    for thread in threads:
        thread.start()
    barrier.wait()
    for thread in threads:
        thread.join()

    assert sorted(results) == ["expired", "invalid"], results
PY
then
    pass
else
    fail 'simulator state transitions must be atomic and loopback-literal only'
fi

work=$(mktemp -d /tmp/zte-test-u25s-simulator.XXXXXX)
ZTE_SESSION_LOCK_FILE=$work/session-login.lock
export ZTE_SESSION_LOCK_FILE
simulator_pid=
ready_file=$work/ready
request_log=$work/requests
login_secret=simulator-fixture-value

stop_simulator() {
    if [ -n "$simulator_pid" ]; then
        kill "$simulator_pid" 2>/dev/null || :
        wait "$simulator_pid" 2>/dev/null || :
        simulator_pid=
    fi
}

cleanup() {
    stop_simulator
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

start_simulator() {
    stop_simulator
    rm -f "$ready_file" "$request_log"
    allow_arg=
    if [ "${2-0}" = 1 ]; then
        allow_arg=--allow-fixture-writes
    fi
    # allow_arg is either empty or one fixed simulator flag.
    # shellcheck disable=SC2086
    python3 tests/u25s_simulator.py \
        --host 127.0.0.1 \
        --port 0 \
        --scenario "$1" \
        --ready-file "$ready_file" \
        --request-log "$request_log" \
        --login-secret "$login_secret" \
        $allow_arg \
        >"$work/server.out" 2>"$work/server.err" &
    simulator_pid=$!

    attempts=0
    while [ ! -s "$ready_file" ]; do
        if ! kill -0 "$simulator_pid" 2>/dev/null; then
            fail "simulator exited before becoming ready: $(cat "$work/server.err")"
            return 1
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 100 ]; then
            fail 'simulator did not become ready'
            return 1
        fi
        sleep 0.05
    done

    simulator_host=127.0.0.1:$(cat "$ready_file")
}

start_u30_simulator() {
    stop_simulator
    rm -f "$ready_file" "$request_log"
    python3 tests/u25s_simulator.py \
        --host 127.0.0.1 \
        --port 0 \
        --profile u30 \
        --scenario "$1" \
        --ready-file "$ready_file" \
        --request-log "$request_log" \
        --login-secret "$login_secret" \
        >"$work/server.out" 2>"$work/server.err" &
    simulator_pid=$!

    attempts=0
    while [ ! -s "$ready_file" ]; do
        if ! kill -0 "$simulator_pid" 2>/dev/null; then
            fail "U30 simulator exited before becoming ready: $(cat "$work/server.err")"
            return 1
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 100 ]; then
            fail 'U30 simulator did not become ready'
            return 1
        fi
        sleep 0.05
    done

    simulator_host=127.0.0.1:$(cat "$ready_file")
}

assert_log_safe() {
    if grep -F "$login_secret" "$request_log" >/dev/null 2>&1 ||
        grep -E 'Cookie|password|digest' "$request_log" >/dev/null 2>&1; then
        fail 'simulator request log exposed authentication material'
    else
        pass
    fi
}

start_u30_simulator normal
u30_query='cmd=mc_modem_main_state,network_type,network_signalbar,battery_vol_percent&multi_data=1&isTest=false'
u30_raw=$(curl -sS --max-time 2 \
    -H 'Referer: https://192.168.0.1/' \
    "http://$simulator_host/goform/goform_get_cmd_process?$u30_query")
assert_eq "$(cat tests/fixtures/u30/status.json)" "$u30_raw" \
    'U30 profile must serve its sanitized status fixture without a login session'
for observed_field in \
    '"device_market_name":"U30 Pro"' \
    '"network_type":"5G"' \
    '"battery_vol_percent":"100"'
do
    case $u30_raw in
        *"$observed_field"*) pass ;;
        *) fail "U30 fixture is missing observed field: $observed_field" ;;
    esac
done
u30_rejected=$(curl -sS --max-time 2 \
    -H 'Referer: http://192.168.0.1/' \
    "http://$simulator_host/goform/goform_get_cmd_process?$u30_query")
assert_eq '{"Error":"none secure connection"}' "$u30_rejected" \
    'U30 profile must reject a non-HTTPS request contract'
assert_eq 1 "$(grep -c '^GET U30_STATUS 200$' "$request_log")"
assert_eq 1 "$(grep -c '^GET U30_STATUS SECURE_REQUIRED$' "$request_log")"
assert_log_safe
assert_success node -e '
const fs = require("fs");
const contract = JSON.parse(fs.readFileSync("tests/fixtures/u30/config-contract.json", "utf8"));
if (contract.profile !== "u30" || contract.device_model !== "U30Air" ||
    contract.device_family !== "ufi/mu3351" || contract.scheme !== "https" ||
    contract.referer !== "https://192.168.0.1/" || contract.login_required !== false)
    process.exit(1);
'

ZTE_HTTP_TIMEOUT=2
export ZTE_HTTP_TIMEOUT

start_simulator normal
normal_jar=$work/normal.cookies
normal_raw=$(zte_adapter_fetch "$simulator_host" "$login_secret" "$normal_jar")
assert_eq "$(cat tests/fixtures/u25s/read_ok.json)" "$normal_raw" \
    'normal scenario must return the sanitized U25S fixture'
normal_json=$(zte_adapter_normalize "$normal_raw")
case $normal_json in
    *'"model":"U25S"'*'"type":"NR5G-SA"'*'"percent":82'*) pass ;;
    *) fail 'normal scenario did not normalize through the production adapter' ;;
esac
assert_eq 1 "$(grep -c '^POST LOGIN 200$' "$request_log")" \
    'normal scenario must log in exactly once'
assert_log_safe

start_simulator expire-once
expired_jar=$work/expired.cookies
expired_raw=$(zte_adapter_fetch "$simulator_host" "$login_secret" "$expired_jar")
assert_eq "$(cat tests/fixtures/u25s/read_ok.json)" "$expired_raw" \
    'adapter must recover after the simulator expires one session'
assert_eq 2 "$(grep -c '^POST LOGIN 200$' "$request_log")" \
    'expired session must cause exactly one relogin'
assert_log_safe

start_simulator missing
missing_jar=$work/missing.cookies
missing_raw=$(zte_adapter_fetch "$simulator_host" "$login_secret" "$missing_jar")
missing_json=$(zte_adapter_normalize "$missing_raw")
case $missing_json in
    *'"type":"LTE"'*'"present":false'*battery_vol_percent*) pass ;;
    *) fail "missing-field scenario did not produce a normalized missing list: $missing_json" ;;
esac

start_simulator malformed
malformed_jar=$work/malformed.cookies
assert_failure zte_adapter_fetch "$simulator_host" "$login_secret" "$malformed_jar"

start_simulator timeout
timeout_jar=$work/timeout.cookies
ZTE_HTTP_TIMEOUT=1
export ZTE_HTTP_TIMEOUT
assert_failure zte_adapter_fetch \
    "$simulator_host" "$login_secret" "$timeout_jar" 2>/dev/null

start_simulator normal
unknown_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 \
    "http://$simulator_host/goform/goform_get_cmd_process?cmd=SET_WIFI")
assert_eq 404 "$unknown_code" 'unsupported GET commands must be denied'

login_field=password
bad_login_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 \
    --data "goformId=LOGIN&$login_field=invalid-fixture-digest" \
    "http://$simulator_host/goform/goform_set_cmd_process")
assert_eq 403 "$bad_login_code" 'an invalid login digest must be denied'
assert_eq 1 "$(grep -c '^POST LOGIN 403$' "$request_log")" \
    'a denied login may be logged only as a symbolic event'

http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 \
    --data 'goformId=SET_WIFI' \
    "http://$simulator_host/goform/goform_set_cmd_process")
assert_eq 403 "$http_code" 'non-login write requests must be denied'
assert_eq 1 "$(grep -c '^POST WRITE 403$' "$request_log")" \
    'denied write must be recorded without its request body'
assert_log_safe

start_simulator normal 1
action_jar=$work/action.cookies
assert_success zte_session_login \
    "$simulator_host" "$login_secret" "$action_jar"
export ZTE_SIM_READBACK_ATTEMPTS=1
export ZTE_SIM_READBACK_INTERVAL=0
assert_eq ok "$(
    zte_execute_switch_sim \
        "$simulator_host" "$login_secret" "$action_jar" sim2
)" 'calibrated SIM request must succeed only after matching status readback'
assert_eq 1 "$(grep -c '^POST SIM_SWITCH_SIMCARD 200$' "$request_log")"
switched_raw=$(zte_adapter_fetch \
    "$simulator_host" "$login_secret" "$action_jar")
assert_eq 2 "$(zte_json_flat_get "$switched_raw" simcard_active_slot_temp)"
for fixture_action in \
    FIXTURE_SWITCH_SIM \
    FIXTURE_SET_APN \
    FIXTURE_SET_CONNECTION_MODE \
    FIXTURE_SET_WIFI \
    FIXTURE_SET_TRAFFIC_PLAN \
    FIXTURE_RESET_TRAFFIC \
    FIXTURE_SEND_SMS \
    FIXTURE_DELETE_SMS \
    FIXTURE_MARK_SMS_READ
do
    assert_eq '{"result":"0"}' "$(
        zte_http_post \
            "http://$simulator_host/goform/goform_set_cmd_process" \
            "goformId=$fixture_action&fixture_value=verified" \
            "$action_jar"
    )"
    readback=$(zte_http_get \
        "http://$simulator_host/fixture/action_state" "$action_jar")
    assert_eq \
        '{"action":"'"$fixture_action"'","value":"verified"}' \
        "$readback"
done
assert_log_safe

start_simulator write-denied 1
denied_jar=$work/denied.cookies
assert_success zte_session_login \
    "$simulator_host" "$login_secret" "$denied_jar"
assert_failure zte_http_post \
    "http://$simulator_host/goform/goform_set_cmd_process" \
    'goformId=FIXTURE_SET_WIFI&fixture_value=verified' \
    "$denied_jar" 2>/dev/null

start_simulator write-timeout 1
write_timeout_jar=$work/write-timeout.cookies
assert_success zte_session_login \
    "$simulator_host" "$login_secret" "$write_timeout_jar"
ZTE_HTTP_TIMEOUT=1
export ZTE_HTTP_TIMEOUT
assert_failure zte_http_post \
    "http://$simulator_host/goform/goform_set_cmd_process" \
    'goformId=FIXTURE_SET_WIFI&fixture_value=verified' \
    "$write_timeout_jar" 2>/dev/null

start_simulator write-expire-once 1
write_expired_jar=$work/write-expired.cookies
assert_success zte_session_login \
    "$simulator_host" "$login_secret" "$write_expired_jar"
assert_failure zte_http_post \
    "http://$simulator_host/goform/goform_set_cmd_process" \
    'goformId=FIXTURE_SWITCH_SIM&fixture_value=verified' \
    "$write_expired_jar" 2>/dev/null
assert_success zte_session_login \
    "$simulator_host" "$login_secret" "$write_expired_jar"
assert_eq '{"result":"0"}' "$(
    zte_http_post \
        "http://$simulator_host/goform/goform_set_cmd_process" \
        'goformId=FIXTURE_SWITCH_SIM&fixture_value=verified' \
        "$write_expired_jar"
)"
assert_log_safe

start_simulator write-expire-once 1
calibrated_expired_jar=$work/calibrated-expired.cookies
assert_eq ok "$(
    zte_execute_switch_sim \
        "$simulator_host" "$login_secret" \
        "$calibrated_expired_jar" physical 2>/dev/null
)" 'calibrated idempotent write must relogin and retry once'
assert_eq 2 "$(grep -c '^POST LOGIN 200$' "$request_log")"
assert_eq 1 "$(grep -c '^POST SIM_SWITCH_SIMCARD 401$' "$request_log")"
assert_eq 1 "$(grep -c '^POST SIM_SWITCH_SIMCARD 200$' "$request_log")"
assert_log_safe

stop_simulator
external_ready=$work/external-ready
if python3 tests/u25s_simulator.py \
    --host 0.0.0.0 \
    --port 0 \
    --scenario normal \
    --ready-file "$external_ready" \
    --request-log "$request_log" \
    --login-secret "$login_secret" \
    >/dev/null 2>&1; then
    fail 'simulator must reject non-loopback bind addresses'
else
    pass
fi
if [ -e "$external_ready" ]; then
    fail 'rejected external bind must not publish a ready file'
else
    pass
fi

finish
