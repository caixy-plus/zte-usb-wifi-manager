#!/bin/sh

zte_netifd_json() {
    case $1 in
        1) up=true ;;
        *) up=false ;;
    esac
    l3_device=$(zte_json_escape "$2")
    ipv4=$(zte_json_escape "$3")
    gateway=$(zte_json_escape "$4")
    case $5 in
        1) is_default_route=true ;;
        *) is_default_route=false ;;
    esac

    printf '{"up":%s,"l3_device":"%s","ipv4":"%s","gateway":"%s","is_default_route":%s}\n' \
        "$up" "$l3_device" "$ipv4" "$gateway" "$is_default_route"
}

zte_netifd_collect() {
    ifname=$1

    if ! status=$(ubus call "network.interface.$ifname" status 2>/dev/null) ||
        [ -z "$status" ]; then
        zte_netifd_json 0 '' '' '' 0
        return
    fi

    up_value=$(jsonfilter -s "$status" -e '@.up')
    case $up_value in
        1|true) up=1 ;;
        *) up=0 ;;
    esac
    l3_device=$(jsonfilter -s "$status" -e '@.l3_device')
    ipv4=$(jsonfilter -s "$status" -e '@["ipv4-address"][0].address')
    gateway=$(jsonfilter -s "$status" -e '@.route[0].nexthop')

    is_default_route=0
    if [ -n "$l3_device" ] &&
        ip route show default | grep -q "dev $l3_device "; then
        is_default_route=1
    fi

    zte_netifd_json "$up" "$l3_device" "$ipv4" "$gateway" "$is_default_route"
}
