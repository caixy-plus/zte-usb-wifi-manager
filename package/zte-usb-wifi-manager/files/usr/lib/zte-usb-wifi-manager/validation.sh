#!/bin/sh

zte_is_uint() {
    case ${1-} in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

zte_validate_thresholds() {
    zte_is_uint "${1-}" &&
        zte_is_uint "${2-}" &&
        [ "$1" -ge 30 ] &&
        [ "$1" -lt "$2" ] &&
        [ "$2" -le 100 ]
}

zte_validate_host() {
    case ${1-} in
        ''|*[!A-Za-z0-9.:-]*) return 1 ;;
        *) return 0 ;;
    esac
}
