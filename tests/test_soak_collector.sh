#!/bin/sh
set -eu

TEST_NAME=test_soak_collector
. ./tests/testlib.sh

collector=./package/zte-usb-wifi-manager/files/usr/libexec/zte-usb-soak
if [ ! -f "$collector" ]; then
    fail 'router soak collector must exist'
    finish
fi

work=$(mktemp -d /tmp/zte-test-soak-collector.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
lib=$work/lib
bin=$work/bin
runtime=$work/runtime
proc=$work/proc
mkdir -p "$lib" "$bin" "$runtime/logs" "$runtime/netdev" \
    "$proc/123/fd" "$proc/456/fd"
printf '%s\n' 123 >"$runtime/manager.pid"
printf '%s\n' 456 >"$runtime/coordinator.pid"
printf '%s\n' '{"state":"ok","updated":1722345590}' >"$runtime/status.json"
printf '1\n' >"$runtime/power"
printf '%s\n' '{"time":1722345590}' >"$runtime/logs/events.jsonl"
printf '%s\n' \
    'Name:	zte-usb-wifi-managerd' \
    'VmRSS:	    2345 kB' >"$proc/123/status"
: >"$proc/123/fd/1"
: >"$proc/123/fd/2"
: >"$proc/123/fd/3"
printf '%s\n' \
    'Name:	zte-usb-recovery-coordinatord' \
    'VmRSS:	     512 kB' >"$proc/456/status"
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
printf '%s\n' 1722345600
EOF
chmod +x "$bin/"*

sample=$(
    ZTE_SOAK_LIB_DIR=$lib \
    ZTE_SOAK_STATUS_FILE=$runtime/status.json \
    ZTE_SOAK_POWER_PATH=$runtime/power \
    ZTE_SOAK_INHIBIT_FILE=$runtime/inhibit \
    ZTE_SOAK_EVENT_LOG=$runtime/logs/events.jsonl \
    ZTE_SOAK_NETDEV_PATH=$runtime/netdev \
    ZTE_SOAK_PROC_ROOT=$proc \
    ZTE_SOAK_MANAGER_PID_FILE=$runtime/manager.pid \
    ZTE_SOAK_COORDINATOR_PID_FILE=$runtime/coordinator.pid \
    PATH="$bin:$PATH" \
        sh "$collector" once
)
assert_eq \
    '{"timestamp":1722345600,"service_running":true,"pid":123,"rss_kb":2345,"fd_count":3,"coordinator_running":true,"coordinator_pid":456,"coordinator_rss_kb":512,"coordinator_fd_count":2,"recovery_service_running":true,"state":"ok","status_age":10,"power":1,"recovery_inhibit":false,"netdev_present":true,"event_log_bytes":20}' \
    "$sample"

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
    ZTE_SOAK_NETDEV_PATH=$runtime/missing-netdev \
    ZTE_SOAK_PROC_ROOT=$proc \
    ZTE_SOAK_MANAGER_PID_FILE=$runtime/manager.pid \
    ZTE_SOAK_COORDINATOR_PID_FILE=$runtime/coordinator.pid \
    ZTE_TEST_RECOVERY_RUNNING=0 \
    PATH="$bin:$PATH" \
        sh "$collector" once
)
assert_eq \
    '{"timestamp":1722345600,"service_running":true,"pid":123,"rss_kb":2345,"fd_count":3,"coordinator_running":true,"coordinator_pid":456,"coordinator_rss_kb":512,"coordinator_fd_count":2,"recovery_service_running":false,"state":"ok","status_age":10,"power":0,"recovery_inhibit":true,"netdev_present":false,"event_log_bytes":20}' \
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

finish
