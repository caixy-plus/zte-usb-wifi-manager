#!/bin/sh
set -eu

TEST_NAME=test_soak_collector
. ./tests/testlib.sh

collector=./package/zte-usb-wifi-manager/files/usr/libexec/zte-usb-soak
if [ ! -f "$collector" ]; then
    fail 'router soak collector must exist'
    finish
fi

# The literal shell parameter expansion identifies the collector default.
# shellcheck disable=SC2016
soak_max_bytes=$(sed -n \
    's/^ZTE_SOAK_MAX_BYTES=${ZTE_SOAK_MAX_BYTES:-\([0-9][0-9]*\)}$/\1/p' \
    "$collector")
assert_eq 4194304 "$soak_max_bytes"

work=$(mktemp -d /tmp/zte-test-soak-collector.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
lib=$work/lib
bin=$work/bin
runtime=$work/runtime
proc=$work/proc
mkdir -p "$lib" "$bin" "$runtime/logs" "$runtime/netdev" \
	"$runtime/actions/results" \
    "$proc/123/fd" "$proc/456/fd" "$proc/sys/kernel/random"
printf '%s\n' '11111111-2222-3333-4444-555555555555' \
    >"$proc/sys/kernel/random/boot_id"
printf '%s\n' '500.25 100.00' >"$proc/uptime"
printf '%s\n' 123 >"$runtime/manager.pid"
printf '%s\n' 456 >"$runtime/coordinator.pid"
printf '%s\n' '{"state":"ok","updated":1722345590,"failures":0,"device":{"battery":{"percent":51},"adapter":"zte_u30","power_supply":{"mode_raw":0}}}' >"$runtime/status.json"
: >"$runtime/actions/results/one.json"
: >"$runtime/actions/results/two.json"
printf '1\n' >"$runtime/power"
printf '%s\n' '{"time":1722345590}' >"$runtime/logs/events.jsonl"
printf '%s\n' \
    'Name:	zte-usb-wifi-managerd' \
    'VmRSS:	    2345 kB' >"$proc/123/status"
printf '%s\n' zte-usb-wifi-ma >"$proc/123/comm"
printf '%s\n' '123 (zte-usb-wifi-managerd) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 100' \
    >"$proc/123/stat"
: >"$proc/123/fd/1"
: >"$proc/123/fd/2"
: >"$proc/123/fd/3"
printf '%s\n' \
    'Name:	zte-usb-recovery-coordinatord' \
    'VmRSS:	     512 kB' >"$proc/456/status"
printf '%s\n' zte-usb-recover >"$proc/456/comm"
printf '%s\n' '456 (zte-usb-recovery-coordinatord) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 200' \
    >"$proc/456/stat"
: >"$proc/456/fd/1"
: >"$proc/456/fd/2"

cat >"$lib/validation.sh" <<'EOF'
zte_is_uint() {
    case ${1-} in ''|*[!0-9]*) return 1 ;; esac
}
EOF
cat >"$lib/json.sh" <<'EOF'
zte_json_top_get() {
    case $2 in
        state)
            printf '%s' "$1" |
                sed -n 's/.*"state":"\([^"]*\)".*/\1/p'
            ;;
        updated)
            printf '%s' "$1" |
                sed -n 's/.*"updated":\([0-9][0-9]*\).*/\1/p'
            ;;
        failures)
            printf '%s' "$1" |
                sed -n 's/.*"failures":\([0-9][0-9]*\).*/\1/p'
            ;;
        adapter) printf '%s\n' "${ZTE_TEST_ADAPTER:-zte_u30}" ;;
        *) return 1 ;;
    esac
}
zte_json_top_object_get() {
    case $2 in
        device)
            if [ "${ZTE_TEST_ADAPTER:-zte_u30}" = zte_u25s ]; then
                printf '%s\n' '{"battery":{"percent":51},"adapter":"zte_u25s"}'
            else
                printf '%s\n' '{"battery":{"percent":51},"adapter":"zte_u30","power_supply":{"mode_raw":0}}'
            fi
            ;;
        power_supply) printf '%s\n' '{"mode_raw":0}' ;;
        *) return 1 ;;
    esac
}
zte_json_flat_get() {
    case $2 in
        adapter)
            case $1 in *'"battery":{'*) return 1 ;; esac
            printf '%s\n' "${ZTE_TEST_ADAPTER:-zte_u30}"
            ;;
        mode_raw) printf '%s\n' 0 ;;
        *) return 1 ;;
    esac
}
EOF
cat >"$lib/recovery-inhibit.sh" <<'EOF'
zte_recovery_inhibit_active() {
    return 1
}
EOF
cat >"$lib/recovery-adapter.sh" <<'EOF'
zte_recovery_service_running() {
    [ "${ZTE_TEST_RECOVERY_RUNNING:-1}" = 1 ]
}
EOF
cat >"$lib/power-adapter.sh" <<'EOF'
zte_power_hardware_read() {
    cat "$1"
}
zte_power_supply_read() {
    if [ -n "${ZTE_TEST_SUPPLY_STATE:-}" ]; then
        printf '%s\n' "$ZTE_TEST_SUPPLY_STATE"
    else
        cat "$1"
    fi
}
EOF
cat >"$bin/date" <<'EOF'
#!/bin/sh
if [ -n "${ZTE_TEST_CLOCK_FILE:-}" ]; then
    printf '%s\n' $((1722345600 + $(cat "$ZTE_TEST_CLOCK_FILE")))
else
    printf '%s\n' 1722345600
fi
EOF
cat >"$bin/sleep" <<'EOF'
#!/bin/sh
if [ -n "${ZTE_TEST_CLOCK_FILE:-}" ]; then
    current=$(cat "$ZTE_TEST_CLOCK_FILE")
    next=$((current + $1))
    printf '%s\n' "$next" >"$ZTE_TEST_CLOCK_FILE"
    case $next in
        1)
            printf '0\n' >"$ZTE_TEST_POWER_FILE"
            rmdir "$ZTE_TEST_NETDEV_PATH"
            ;;
        2)
            printf '1\n' >"$ZTE_TEST_POWER_FILE"
            mkdir -p "$ZTE_TEST_NETDEV_PATH"
            ;;
    esac
fi
EOF
chmod +x "$bin/"*

sample=$(
    ZTE_SOAK_LIB_DIR=$lib \
    ZTE_SOAK_STATUS_FILE=$runtime/status.json \
    ZTE_SOAK_POWER_PATH=$runtime/power \
    ZTE_SOAK_INHIBIT_FILE=$runtime/inhibit \
    ZTE_SOAK_EVENT_LOG=$runtime/logs/events.jsonl \
    ZTE_SOAK_ACTION_RESULTS_DIR=$runtime/actions/results \
    ZTE_SOAK_NETDEV_PATH=$runtime/netdev \
    ZTE_SOAK_PROC_ROOT=$proc \
    ZTE_SOAK_MANAGER_PID_FILE=$runtime/manager.pid \
    ZTE_SOAK_COORDINATOR_PID_FILE=$runtime/coordinator.pid \
    PATH="$bin:$PATH" \
        sh "$collector" once
)
assert_eq \
    '{"timestamp":1722345600,"monotonic_seconds":500,"boot_id":"11111111-2222-3333-4444-555555555555","service_running":true,"pid":123,"manager_comm":"zte-usb-wifi-ma","manager_start_ticks":100,"rss_kb":2345,"fd_count":3,"coordinator_running":true,"coordinator_pid":456,"coordinator_comm":"zte-usb-recover","coordinator_start_ticks":200,"coordinator_rss_kb":512,"coordinator_fd_count":2,"recovery_service_running":true,"state":"ok","status_age":10,"adapter":"zte_u30","power_supply_mode":"charging","failure_count":0,"action_result_count":2,"usb_discontinuity_count":0,"max_failure_count":0,"max_action_result_count":2,"power":1,"recovery_inhibit":false,"netdev_present":true,"event_log_bytes":20}' \
    "$sample"
sample_bytes=$(printf '%s\n' "$sample" | wc -c | tr -d ' ')
assert_eq 1 "$([ $((sample_bytes * 4321)) -le "$soak_max_bytes" ] &&
    printf 1 || printf 0)"

sample_u25s=$(
    ZTE_SOAK_LIB_DIR=$lib \
    ZTE_SOAK_STATUS_FILE=$runtime/status.json \
    ZTE_SOAK_POWER_PATH=$runtime/power \
    ZTE_SOAK_INHIBIT_FILE=$runtime/inhibit \
    ZTE_SOAK_EVENT_LOG=$runtime/logs/events.jsonl \
    ZTE_SOAK_ACTION_RESULTS_DIR=$runtime/actions/results \
    ZTE_SOAK_NETDEV_PATH=$runtime/netdev \
    ZTE_SOAK_PROC_ROOT=$proc \
    ZTE_SOAK_MANAGER_PID_FILE=$runtime/manager.pid \
    ZTE_SOAK_COORDINATOR_PID_FILE=$runtime/coordinator.pid \
    ZTE_TEST_ADAPTER=zte_u25s \
    PATH="$bin:$PATH" \
        sh "$collector" once
)
assert_eq zte_u25s "$(printf '%s' "$sample_u25s" |
    sed -n 's/.*"adapter":"\([^"]*\)".*/\1/p')"
assert_eq unsupported "$(printf '%s' "$sample_u25s" |
    sed -n 's/.*"power_supply_mode":"\([^"]*\)".*/\1/p')"

printf '0\n' >"$runtime/power"
zte_recovery_inhibit_active_marker=$runtime/inhibit
: >"$zte_recovery_inhibit_active_marker"
cat >"$lib/recovery-inhibit.sh" <<'EOF'
zte_recovery_inhibit_active() {
    [ -e "$1" ]
}
EOF
sample_off=$(
    ZTE_SOAK_LIB_DIR=$lib \
    ZTE_SOAK_STATUS_FILE=$runtime/status.json \
    ZTE_SOAK_POWER_PATH=$runtime/power \
    ZTE_SOAK_INHIBIT_FILE=$runtime/inhibit \
    ZTE_SOAK_EVENT_LOG=$runtime/logs/events.jsonl \
    ZTE_SOAK_ACTION_RESULTS_DIR=$runtime/actions/results \
    ZTE_SOAK_NETDEV_PATH=$runtime/missing-netdev \
    ZTE_SOAK_PROC_ROOT=$proc \
    ZTE_SOAK_MANAGER_PID_FILE=$runtime/manager.pid \
    ZTE_SOAK_COORDINATOR_PID_FILE=$runtime/coordinator.pid \
    ZTE_TEST_RECOVERY_RUNNING=0 \
    PATH="$bin:$PATH" \
        sh "$collector" once
)
assert_eq \
    '{"timestamp":1722345600,"monotonic_seconds":500,"boot_id":"11111111-2222-3333-4444-555555555555","service_running":true,"pid":123,"manager_comm":"zte-usb-wifi-ma","manager_start_ticks":100,"rss_kb":2345,"fd_count":3,"coordinator_running":true,"coordinator_pid":456,"coordinator_comm":"zte-usb-recover","coordinator_start_ticks":200,"coordinator_rss_kb":512,"coordinator_fd_count":2,"recovery_service_running":false,"state":"ok","status_age":10,"adapter":"zte_u30","power_supply_mode":"charging","failure_count":0,"action_result_count":2,"usb_discontinuity_count":1,"max_failure_count":0,"max_action_result_count":2,"power":0,"recovery_inhibit":true,"netdev_present":false,"event_log_bytes":20}' \
    "$sample_off"

printf 'invalid\n' >"$runtime/power"
assert_failure env \
    ZTE_SOAK_LIB_DIR="$lib" \
    ZTE_SOAK_STATUS_FILE="$runtime/status.json" \
    ZTE_SOAK_POWER_PATH="$runtime/power" \
    ZTE_SOAK_INHIBIT_FILE="$runtime/inhibit" \
    ZTE_SOAK_EVENT_LOG="$runtime/logs/events.jsonl" \
    ZTE_SOAK_NETDEV_PATH="$runtime/netdev" \
    ZTE_SOAK_PROC_ROOT="$proc" \
    ZTE_SOAK_MANAGER_PID_FILE="$runtime/manager.pid" \
    ZTE_SOAK_COORDINATOR_PID_FILE="$runtime/coordinator.pid" \
    PATH="$bin:$PATH" \
    sh "$collector" once

printf '1\n' >"$runtime/power"
assert_failure env \
    ZTE_SOAK_LIB_DIR="$lib" \
    ZTE_SOAK_STATUS_FILE="$runtime/status.json" \
    ZTE_SOAK_POWER_PATH="$runtime/power" \
    ZTE_SOAK_INHIBIT_FILE="$runtime/inhibit" \
    ZTE_SOAK_EVENT_LOG="$runtime/logs/events.jsonl" \
    ZTE_SOAK_NETDEV_PATH="$runtime/netdev" \
    ZTE_SOAK_PROC_ROOT="$proc" \
    ZTE_SOAK_MANAGER_PID_FILE="$runtime/manager.pid" \
    ZTE_SOAK_COORDINATOR_PID_FILE="$runtime/coordinator.pid" \
    ZTE_TEST_SUPPLY_STATE=0 \
    PATH="$bin:$PATH" \
    sh "$collector" once

printf '1\n' >"$runtime/power"
rm -f "$runtime/inhibit"
printf '0\n' >"$runtime/clock"
latched_output=$runtime/latched.jsonl
ZTE_SOAK_LIB_DIR=$lib \
ZTE_SOAK_STATUS_FILE=$runtime/status.json \
ZTE_SOAK_POWER_PATH=$runtime/power \
ZTE_SOAK_INHIBIT_FILE=$runtime/inhibit \
ZTE_SOAK_EVENT_LOG=$runtime/logs/events.jsonl \
ZTE_SOAK_ACTION_RESULTS_DIR=$runtime/actions/results \
ZTE_SOAK_NETDEV_PATH=$runtime/netdev \
ZTE_SOAK_PROC_ROOT=$proc \
ZTE_SOAK_MANAGER_PID_FILE=$runtime/manager.pid \
ZTE_SOAK_COORDINATOR_PID_FILE=$runtime/coordinator.pid \
ZTE_SOAK_STATE_DIR=$runtime/soak-state \
ZTE_SOAK_LOCK_DIR=$runtime/soak.lock \
ZTE_SOAK_OUTPUT=$latched_output \
ZTE_SOAK_MONITOR_INTERVAL=1 \
ZTE_TEST_CLOCK_FILE=$runtime/clock \
ZTE_TEST_POWER_FILE=$runtime/power \
ZTE_TEST_NETDEV_PATH=$runtime/netdev \
PATH="$bin:$PATH" \
    sh "$collector" run 3 2 >/dev/null
latched_second=$(sed -n '2p' "$latched_output")
assert_eq 1 "$(printf '%s' "$latched_second" |
    sed -n 's/.*"usb_discontinuity_count":\([0-9][0-9]*\).*/\1/p')"
assert_eq 1 "$(printf '%s' "$latched_second" |
    sed -n 's/.*"power":\([0-9][0-9]*\).*/\1/p')"
assert_eq true "$(printf '%s' "$latched_second" |
    sed -n 's/.*"netdev_present":\([^,}]*\).*/\1/p')"

finish
