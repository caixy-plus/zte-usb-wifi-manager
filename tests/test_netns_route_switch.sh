#!/bin/sh
set -eu

TEST_NAME=netns_route_switch
. ./tests/testlib.sh

repo_root=$(pwd)
netns_token="$$-$(date +%s)"
manager_ns="zte-l4-manager-$netns_token"
u25s_ns="zte-l4-u25s-$netns_token"
wan_ns="zte-l4-wan-$netns_token"

cleanup() {
    cleanup_status=$?
    trap - EXIT HUP INT TERM
    ip netns del "$manager_ns" 2>/dev/null || :
    ip netns del "$u25s_ns" 2>/dev/null || :
    ip netns del "$wan_ns" 2>/dev/null || :
    exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

collect_network() {
    # The single-quoted program is intentionally evaluated by the namespace shell.
    # shellcheck disable=SC2016
    ip netns exec "$manager_ns" env ZTE_TEST_REPO_ROOT="$repo_root" sh -c '
        ubus() {
            printf "%s\n" \
                "{\"up\":true,\"l3_device\":\"eth2\",\"ipv4-address\":[{\"address\":\"198.18.0.2\"}],\"route\":[{\"nexthop\":\"198.18.0.1\"}]}"
        }
        jsonfilter() {
            case $4 in
                "@.up") printf "%s\n" true ;;
                "@.l3_device") printf "%s\n" eth2 ;;
                *ipv4-address*) printf "%s\n" 198.18.0.2 ;;
                "@.route[0].nexthop") printf "%s\n" 198.18.0.1 ;;
                *) return 1 ;;
            esac
        }
        . "$ZTE_TEST_REPO_ROOT/package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/json.sh"
        . "$ZTE_TEST_REPO_ROOT/package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/netifd-adapter.sh"
        zte_netifd_collect wwan eth2
    '
}

create_eth2_link() {
    ip -n "$manager_ns" link add eth2 type veth peer name u25s0 netns "$u25s_ns"
    ip -n "$manager_ns" address add 198.18.0.2/24 dev eth2
    ip -n "$u25s_ns" address add 198.18.0.1/24 dev u25s0
    ip -n "$manager_ns" link set eth2 up
    ip -n "$u25s_ns" link set u25s0 up
}

ip netns add "$manager_ns"
ip netns add "$u25s_ns"
ip netns add "$wan_ns"

ip -n "$manager_ns" link set lo up
ip -n "$u25s_ns" link set lo up
ip -n "$wan_ns" link set lo up

create_eth2_link
ip -n "$manager_ns" link add wan type veth peer name wan0 netns "$wan_ns"
ip -n "$manager_ns" address add 198.19.0.2/24 dev wan
ip -n "$wan_ns" address add 198.19.0.1/24 dev wan0
ip -n "$manager_ns" link set wan up
ip -n "$wan_ns" link set wan0 up

ip -n "$manager_ns" route add default via 198.18.0.1 dev eth2
actual=$(collect_network)
assert_eq \
    '{"up":true,"l3_device":"eth2","ipv4":"198.18.0.2","gateway":"198.18.0.1","is_default_route":true}' \
    "$actual" \
    'production collector detects eth2 as the real default route'

ip -n "$manager_ns" route replace default via 198.19.0.1 dev wan
actual=$(collect_network)
assert_eq \
    '{"up":true,"l3_device":"eth2","ipv4":"198.18.0.2","gateway":"198.18.0.1","is_default_route":false}' \
    "$actual" \
    'production collector clears the gate after the default route moves to wan'
assert_success ip netns exec "$manager_ns" ping -c 1 -W 1 198.18.0.1

ip -n "$manager_ns" link delete eth2
actual=$(collect_network)
assert_eq \
    '{"up":true,"l3_device":"eth2","ipv4":"198.18.0.2","gateway":"198.18.0.1","is_default_route":false}' \
    "$actual" \
    'production collector remains safe while eth2 is absent'

create_eth2_link
ip -n "$manager_ns" route replace default via 198.18.0.1 dev eth2
actual=$(collect_network)
assert_eq \
    '{"up":true,"l3_device":"eth2","ipv4":"198.18.0.2","gateway":"198.18.0.1","is_default_route":true}' \
    "$actual" \
    'production collector recovers after eth2 is recreated'
assert_success ip netns exec "$manager_ns" ping -c 1 -W 1 198.18.0.1

finish
