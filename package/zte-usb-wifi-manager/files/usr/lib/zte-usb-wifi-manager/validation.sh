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

zte_host_ipv4() {
    _zte_host_authority=${1-}
    case $_zte_host_authority in
        *:*)
            _zte_host_ipv4_value=${_zte_host_authority%%:*}
            _zte_host_port=${_zte_host_authority#*:}
            case $_zte_host_port in
                ''|*[!0-9]*|*:* ) return 1 ;;
            esac
            [ "$_zte_host_port" -ge 1 ] 2>/dev/null &&
                [ "$_zte_host_port" -le 65535 ] 2>/dev/null || return 1
            ;;
        *)
            _zte_host_ipv4_value=$_zte_host_authority
            ;;
    esac

    case $_zte_host_ipv4_value in
        ''|*[!0-9.]*) return 1 ;;
    esac
    _zte_host_old_ifs=$IFS
    IFS=.
    # Intentional field splitting after restricting the value to digits/dots.
    # shellcheck disable=SC2086
    set -- $_zte_host_ipv4_value
    IFS=$_zte_host_old_ifs
    [ "$#" -eq 4 ] || return 1
    for _zte_host_octet in "$@"; do
        case $_zte_host_octet in
            ''|*[!0-9]*) return 1 ;;
        esac
        [ "$_zte_host_octet" -le 255 ] 2>/dev/null || return 1
    done
    printf '%s\n' "$_zte_host_ipv4_value"
}

zte_validate_host() {
    zte_host_ipv4 "${1-}" >/dev/null
}

zte_validate_interface() {
    case ${1-} in
        ''|*[!A-Za-z0-9_.:@-]*) return 1 ;;
        *) return 0 ;;
    esac
}

zte_validate_netdev() {
    zte_validate_interface "${1-}"
}
