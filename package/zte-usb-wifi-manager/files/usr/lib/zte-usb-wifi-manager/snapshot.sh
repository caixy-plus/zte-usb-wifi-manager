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

zte_power_decision_current_json() {
    _zte_power_decision_json=${1-}
    _zte_power_decision_profile=${2-}
    [ -n "$_zte_power_decision_profile" ] || return 1
    zte_json_is_flat_object "$_zte_power_decision_json" || return 1
    _zte_power_decision_backend=$(zte_json_flat_get \
        "$_zte_power_decision_json" backend)
    _zte_power_decision_action=$(zte_json_flat_get \
        "$_zte_power_decision_json" action)
    _zte_power_decision_executed=$(zte_json_flat_get \
        "$_zte_power_decision_json" executed)
    _zte_power_decision_reason=$(zte_json_flat_get \
        "$_zte_power_decision_json" reason)
    _zte_power_decision_outcome=$(zte_json_flat_get \
        "$_zte_power_decision_json" outcome)
    _zte_power_decision_updated=$(zte_json_flat_get \
        "$_zte_power_decision_json" updated)
    _zte_power_decision_record_profile=$(zte_json_flat_get \
        "$_zte_power_decision_json" profile)
    case $_zte_power_decision_backend in unconfigured|mock|dry-run|hardware) ;; *) return 1 ;; esac
    case $_zte_power_decision_action in ON|OFF|KEEP) ;; *) return 1 ;; esac
    case $_zte_power_decision_executed in true|false) ;; *) return 1 ;; esac
    case $_zte_power_decision_reason in battery_low|battery_high|manual_full|pre_departure|fail_safe|disabled|no_change) ;; *) return 1 ;; esac
    case $_zte_power_decision_outcome in succeeded|failed) ;; *) return 1 ;; esac
    case $_zte_power_decision_updated in ''|*[!0-9]*) return 1 ;; esac
    [ "$_zte_power_decision_updated" -gt 0 ] 2>/dev/null || return 1
    [ "$_zte_power_decision_record_profile" = \
        "$_zte_power_decision_profile" ] || return 1
    printf '%s\n' "$_zte_power_decision_json"
}

# $1 backend, $2 calibrated, $3 write enabled, $4 effective control path,
# $5 controller state, $6 supply state, $7 last decision JSON,
# $8 recovery inhibited, $9 recovery service available,
# $10 recovery service running, $11 execution available, $12 execution reason.
zte_power_snapshot_json() {
    _zte_power_snapshot_backend=${1-}
    case $_zte_power_snapshot_backend in
        unconfigured|mock|dry-run|hardware) ;;
        *) _zte_power_snapshot_backend=unconfigured ;;
    esac
    case ${2-0} in 1) _zte_power_snapshot_calibrated=true ;; *) _zte_power_snapshot_calibrated=false ;; esac
    case ${3-0} in 1) _zte_power_snapshot_write=true ;; *) _zte_power_snapshot_write=false ;; esac
    if [ -n "${4-}" ]; then
        _zte_power_snapshot_path='"'$(zte_json_escape "$4")'"'
    else
        _zte_power_snapshot_path=null
    fi
    case ${5-} in 0|1) _zte_power_snapshot_control=$5 ;; *) _zte_power_snapshot_control=null ;; esac
    case ${6-} in 0|1) _zte_power_snapshot_supply=$6 ;; *) _zte_power_snapshot_supply=null ;; esac
    case $_zte_power_snapshot_control:$_zte_power_snapshot_supply in
        1:1) _zte_power_snapshot_observed=ON ;;
        0:0) _zte_power_snapshot_observed=OFF ;;
        *) _zte_power_snapshot_observed=UNKNOWN ;;
    esac
    if [ -n "${7-}" ] && zte_json_is_flat_object "$7"; then
        _zte_power_snapshot_decision=$7
    else
        _zte_power_snapshot_decision=null
    fi
    case ${8-0} in 1) _zte_power_snapshot_inhibited=true ;; *) _zte_power_snapshot_inhibited=false ;; esac
    case ${9-0} in 1) _zte_power_snapshot_available=true ;; *) _zte_power_snapshot_available=false ;; esac
    case ${10-0} in 1) _zte_power_snapshot_recovery=true ;; *) _zte_power_snapshot_recovery=false ;; esac
	case ${11-0} in 1) _zte_power_snapshot_execution=true ;; *) _zte_power_snapshot_execution=false ;; esac
	_zte_power_snapshot_execution_reason=${12-backend_unconfigured}
	case $_zte_power_snapshot_execution_reason in
		ready|mock|dry_run|backend_unconfigured|write_disabled|not_calibrated|board_unsupported|control_unresolved|recovery_unavailable) ;;
		*) _zte_power_snapshot_execution_reason=unavailable ;;
	esac

    printf '{"backend":"%s","calibrated":%s,"write_enabled":%s,"control_path":%s,"control_state":%s,"supply_state":%s,"observed":"%s","execution":{"available":%s,"reason":"%s"},"decision":%s,"recovery":{"inhibited":%s,"service_available":%s,"service_running":%s}}\n' \
        "$_zte_power_snapshot_backend" "$_zte_power_snapshot_calibrated" \
        "$_zte_power_snapshot_write" "$_zte_power_snapshot_path" \
        "$_zte_power_snapshot_control" "$_zte_power_snapshot_supply" \
        "$_zte_power_snapshot_observed" "$_zte_power_snapshot_execution" \
		"$_zte_power_snapshot_execution_reason" "$_zte_power_snapshot_decision" \
        "$_zte_power_snapshot_inhibited" "$_zte_power_snapshot_available" \
        "$_zte_power_snapshot_recovery"
}

# Compose the status.json snapshot.
# $1 state, $2 reason, $3 device_json (or empty for null), $4 network_json
# (or empty for null), $5 policy_state, $6 power_action, $7 failures, $8 updated,
# $9 power JSON (or empty for null).
zte_snapshot_compose() {
    _zte_state=$1 _zte_reason=$2 _zte_device=$3 _zte_network=$4
    _zte_pstate=$5 _zte_paction=$6 _zte_failures=$7 _zte_updated=$8
    _zte_power=${9-}
	_zte_fallback_model=${10-U25S}

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
		_zte_model=$_zte_fallback_model
        _zte_device_json=null
    fi
    if [ -n "$_zte_network" ]; then
        _zte_network_json=$_zte_network
    else
        _zte_network_json=null
    fi
	if [ -n "$_zte_power" ]; then
		_zte_power_json=$_zte_power
	else
		_zte_power_json=null
	fi

    printf '{"online":%s,"model":"%s","state":"%s","reason":"%s","device":%s,"network":%s,"policy":{"state":"%s","power_action":"%s"},"power":%s,"failures":%s,"updated":%s}\n' \
		"${_zte_online:-false}" "$(zte_json_escape "${_zte_model:-$_zte_fallback_model}")" \
        "$(zte_json_escape "$_zte_state")" "$(zte_json_escape "$_zte_reason")" \
        "$_zte_device_json" "$_zte_network_json" \
        "$(zte_json_escape "$_zte_pstate")" "$(zte_json_escape "$_zte_paction")" \
        "$_zte_power_json" "$_zte_failures" "$_zte_updated"
}
