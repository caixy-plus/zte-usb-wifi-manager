#!/bin/sh

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

    if ! _zte_status=$(ubus call "network.interface.$_zte_ifname" status 2>/dev/null) ||
        [ -z "$_zte_status" ]; then
        zte_netifd_json 0 '' '' '' 0
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
    _zte_ipv4=$(jsonfilter -s "$_zte_status" -e '@["ipv4-address"][0].address' 2>/dev/null) ||
        _zte_ipv4=''
    _zte_gateway=$(jsonfilter -s "$_zte_status" -e '@.route[0].nexthop' 2>/dev/null) ||
        _zte_gateway=''

    _zte_is_default_route=0
    if [ -n "$_zte_l3_device" ] &&
        ip route show default 2>/dev/null | grep -q "dev $_zte_l3_device "; then
        _zte_is_default_route=1
    fi

    zte_netifd_json \
        "$_zte_up" \
        "$_zte_l3_device" \
        "$_zte_ipv4" \
        "$_zte_gateway" \
        "$_zte_is_default_route"
}
