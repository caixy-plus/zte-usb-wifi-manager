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

# $1 base polling interval, $2 consecutive failures. Cap at five minutes.
zte_backoff_interval() {
    _zte_base=${1-}
    _zte_failures=${2-}
    case $_zte_base in
        ''|*[!0-9]*) return 1 ;;
    esac
    case $_zte_failures in
        ''|*[!0-9]*) return 1 ;;
    esac

    while [ "${#_zte_base}" -gt 1 ] &&
        [ "${_zte_base#0}" != "$_zte_base" ]; do
        _zte_base=${_zte_base#0}
    done
    while [ "${#_zte_failures}" -gt 1 ] &&
        [ "${_zte_failures#0}" != "$_zte_failures" ]; do
        _zte_failures=${_zte_failures#0}
    done
    [ "$_zte_base" != 0 ] || return 1

    if [ "${#_zte_base}" -gt 3 ] ||
        { [ "${#_zte_base}" -eq 3 ] && [ "$_zte_base" -ge 300 ]; }; then
        printf '300\n'
        return
    fi
    if [ "${#_zte_failures}" -gt 1 ]; then
        printf '300\n'
        return
    fi

    _zte_interval=$_zte_base
    while [ "$_zte_failures" -gt 0 ]; do
        if [ "$_zte_interval" -ge 150 ]; then
            printf '300\n'
            return
        fi
        _zte_interval=$(( _zte_interval * 2 ))
        _zte_failures=$(( _zte_failures - 1 ))
    done
    printf '%s\n' "$_zte_interval"
}

# $1 last trusted device JSON, $2 current candidate, $3 ok(1/0).
zte_device_retain() {
    if [ "${3:-0}" = 1 ]; then
        printf '%s\n' "${2-}"
    else
        printf '%s\n' "${1-}"
    fi
}

# Compose the status.json snapshot.
# $1 state, $2 reason, $3 device_json (or empty for null), $4 network_json
# (or empty for null), $5 policy_state, $6 power_action, $7 failures, $8 updated
zte_snapshot_compose() {
    _zte_state=$1 _zte_reason=$2 _zte_device=$3 _zte_network=$4
    _zte_pstate=$5 _zte_paction=$6 _zte_failures=$7 _zte_updated=$8

    if [ -n "$_zte_device" ]; then
        if [ "$_zte_state" = ok ]; then
            _zte_online=$(zte_json_top_get "$_zte_device" online)
        else
            _zte_online=false
        fi
        _zte_model=$(zte_json_top_get "$_zte_device" model)
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
