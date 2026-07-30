#!/bin/sh
set -eu

TEST_NAME=test_packaging
. ./tests/testlib.sh

expected_2512='25.12.5|apk|openwrt-sdk-25.12.5-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst|0c8df0151a1e88feb7c03d694d61f6a18d51872815b7c811d76e2b77504d5e9c|openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz|23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461'
expected_2410='24.10.7|ipk|openwrt-sdk-24.10.7-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst|996d71f9eab7df2e8acb0bb2c9726426f05c10d419e5f9600d59b14d871f2acb|openwrt-24.10.7-x86-64-generic-ext4-combined.img.gz|3caea69f186b2bce80938d265e5e2a3dfd0f8713aed101df35d60b88d7270d1f'

assert_eq "$expected_2512" "$(./scripts/openwrt-release-matrix.sh 25.12.5)"
assert_eq "$expected_2410" "$(./scripts/openwrt-release-matrix.sh 24.10.7)"
assert_failure ./scripts/openwrt-release-matrix.sh 23.05.6 >/dev/null 2>&1
assert_failure ./scripts/openwrt-release-matrix.sh '25.12.5;id' >/dev/null 2>&1

finish
