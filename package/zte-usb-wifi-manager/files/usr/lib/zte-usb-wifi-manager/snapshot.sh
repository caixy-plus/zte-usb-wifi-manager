#!/bin/sh

# $1 current count, $2 ok(1/0), $3 threshold -> "<count>:<ok|degraded|fail_safe>"
zte_failures_next() {
    if [ "${2:-0}" = 1 ]; then
        printf '0:ok\n'
        return 0
    fi
    _zte_count=$(( ${1:-0} + 1 ))
    if [ "$_zte_count" -ge "${3:-3}" ]; then
        printf '%s:fail_safe\n' "$_zte_count"
    else
        printf '%s:degraded\n' "$_zte_count"
    fi
}

# Compose the status.json snapshot.
# $1 state, $2 reason, $3 device_json (or empty for null), $4 network_json
# (or empty for null), $5 policy_state, $6 power_action, $7 failures, $8 updated
zte_snapshot_compose() {
    _zte_state=$1 _zte_reason=$2 _zte_device=$3 _zte_network=$4
    _zte_pstate=$5 _zte_paction=$6 _zte_failures=$7 _zte_updated=$8

    if [ -n "$_zte_device" ]; then
        _zte_online=$(zte_json_flat_get "$_zte_device" online)
        _zte_model=$(zte_json_flat_get "$_zte_device" model)
        _zte_device_json=$_zte_device
    else
        _zte_online=false
        _zte_model=U25S
        _zte_device_json=null
    fi
    if [ -n "$_zte_network" ]; then
        _zte_network_json=$_zte_network
    else
        _zte_network_json=null
    fi

    printf '{"online":%s,"model":"%s","state":"%s","reason":"%s","device":%s,"network":%s,"policy":{"state":"%s","power_action":"%s"},"failures":%s,"updated":%s}\n' \
        "${_zte_online:-false}" "$(zte_json_escape "${_zte_model:-U25S}")" \
        "$(zte_json_escape "$_zte_state")" "$(zte_json_escape "$_zte_reason")" \
        "$_zte_device_json" "$_zte_network_json" \
        "$(zte_json_escape "$_zte_pstate")" "$(zte_json_escape "$_zte_paction")" \
        "$_zte_failures" "$_zte_updated"
}
