#!/bin/sh
set -eu

case ${1-} in
    25.12.5)
        printf '%s\n' '25.12.5|apk|openwrt-sdk-25.12.5-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst|0c8df0151a1e88feb7c03d694d61f6a18d51872815b7c811d76e2b77504d5e9c|openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz|23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461|e11279b01e7fea7f7d399e25e969d9382be6891071cbc1225804195224b27b52'
        ;;
    24.10.7)
        printf '%s\n' '24.10.7|ipk|openwrt-sdk-24.10.7-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst|996d71f9eab7df2e8acb0bb2c9726426f05c10d419e5f9600d59b14d871f2acb|openwrt-24.10.7-x86-64-generic-ext4-combined.img.gz|3caea69f186b2bce80938d265e5e2a3dfd0f8713aed101df35d60b88d7270d1f|fa4ae9a869c3bc76c5d89dc6f6532194a4d1df8e7a99d6f441aeff085124c148'
        ;;
    *)
        printf 'unsupported OpenWrt release: %s\n' "${1-}" >&2
        exit 64
        ;;
esac
