#!/bin/sh

zte_policy_is_uint() {
    case ${1-} in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

zte_policy_decide() {
    enabled=${1-}
    failed=${2-}
    manual_full=${3-}
    pre_departure=${4-}
    battery=${5-}
    low=${6-}
    high=${7-}
    current_power=${8-}

    zte_policy_is_uint "$battery" &&
        zte_policy_is_uint "$low" &&
        zte_policy_is_uint "$high" || return 1

    if [ "$enabled" != 1 ]; then
        printf '%s\n' 'DISABLED:KEEP'
    elif [ "$failed" = 1 ]; then
        printf '%s\n' 'FAIL_SAFE_ON:ON'
    elif [ "$manual_full" = 1 ]; then
        printf '%s\n' 'MANUAL_FULL:ON'
    elif [ "$pre_departure" = 1 ]; then
        printf '%s\n' 'PRE_DEPARTURE:ON'
    elif [ "$battery" -le "$low" ]; then
        printf '%s\n' 'MAINTAIN_CHARGING:ON'
    elif [ "$battery" -ge "$high" ]; then
        printf '%s\n' 'MAINTAIN_BATTERY:OFF'
    elif [ "$current_power" = ON ]; then
        printf '%s\n' 'MAINTAIN_CHARGING:ON'
    elif [ "$current_power" = OFF ]; then
        printf '%s\n' 'MAINTAIN_BATTERY:OFF'
    else
        return 1
    fi
}
