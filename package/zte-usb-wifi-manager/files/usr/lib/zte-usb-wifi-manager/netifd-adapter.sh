#!/bin/sh

zte_netifd_route_uses_device() {
    _zte_route_host=$(zte_host_ipv4 "$1") || return 1
    _zte_route_device=$2
    _zte_route_result=$(ip -4 route get "$_zte_route_host" 2>/dev/null) ||
        return 1
    _zte_route_previous=''
    for _zte_route_token in $_zte_route_result; do
        if [ "$_zte_route_previous" = dev ]; then
            [ "$_zte_route_token" = "$_zte_route_device" ]
            return
        fi
        _zte_route_previous=$_zte_route_token
    done
    return 1
}

# Return 0 when either an IPv4 or IPv6 default route uses the exact device,
# 1 when neither does, and 2 when the routing table cannot be inspected.
zte_netifd_device_is_default_route() {
    _zte_default_route_device=$1
    [ -n "$_zte_default_route_device" ] || return 2
    _zte_default_route_ipv4=$(ip route show default dev \
        "$_zte_default_route_device" 2>/dev/null) || return 2
    _zte_default_route_ipv6=$(ip -6 route show default dev \
        "$_zte_default_route_device" 2>/dev/null) || return 2
    [ -n "$_zte_default_route_ipv4$_zte_default_route_ipv6" ]
}

zte_netifd_json() {
    case ${1:-0} in
        1) _zte_up=true ;;
        *) _zte_up=false ;;
    esac
    _zte_l3_device=$(zte_json_escape "${2-}")
    _zte_ipv4=$(zte_json_escape "${3-}")
    _zte_gateway=$(zte_json_escape "${4-}")
    case ${5:-0} in
        1) _zte_is_default_route=true ;;
        *) _zte_is_default_route=false ;;
    esac

    printf '{"up":%s,"l3_device":"%s","ipv4":"%s","gateway":"%s","is_default_route":%s}\n' \
        "$_zte_up" "$_zte_l3_device" "$_zte_ipv4" "$_zte_gateway" "$_zte_is_default_route"
}

zte_netifd_collect() {
    _zte_ifname=${1-}
    _zte_fallback_netdev=${2-}

    if ! _zte_status=$(ubus call "network.interface.$_zte_ifname" status 2>/dev/null) ||
        [ -z "$_zte_status" ]; then
        zte_netifd_json 0 "$_zte_fallback_netdev" '' '' 0
        return
    fi

    _zte_up_value=$(jsonfilter -s "$_zte_status" -e '@.up' 2>/dev/null) ||
        _zte_up_value=''
    case $_zte_up_value in
        1|true) _zte_up=1 ;;
        *) _zte_up=0 ;;
    esac
    _zte_l3_device=$(jsonfilter -s "$_zte_status" -e '@.l3_device' 2>/dev/null) ||
        _zte_l3_device=''
    [ -n "$_zte_l3_device" ] || _zte_l3_device=$_zte_fallback_netdev
    _zte_ipv4=$(jsonfilter -s "$_zte_status" -e '@["ipv4-address"][0].address' 2>/dev/null) ||
        _zte_ipv4=''
    _zte_gateway=$(jsonfilter -s "$_zte_status" -e '@.route[0].nexthop' 2>/dev/null) ||
        _zte_gateway=''

    _zte_is_default_route=0
    if [ -n "$_zte_l3_device" ]; then
        _zte_default_route_status=0
        zte_netifd_device_is_default_route "$_zte_l3_device" ||
            _zte_default_route_status=$?
        case $_zte_default_route_status in
            1) ;;
            *) _zte_is_default_route=1 ;;
        esac
    fi

    zte_netifd_json \
        "$_zte_up" \
        "$_zte_l3_device" \
        "$_zte_ipv4" \
        "$_zte_gateway" \
        "$_zte_is_default_route"
}
