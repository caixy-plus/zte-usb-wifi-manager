#!/bin/sh
set -eu
TEST_NAME=test_http
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh
assert_file_contains "$lib" 'curl -fsS'
assert_file_contains "$lib" 'max-time'
assert_file_contains "$lib" 'X-Requested-With'
assert_file_contains "$lib" 'application/x-www-form-urlencoded'

# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh
. "$lib"
if command -v zte_http_get >/dev/null 2>&1; then pass; else fail 'zte_http_get missing'; fi
if command -v zte_http_post >/dev/null 2>&1; then pass; else fail 'zte_http_post missing'; fi
assert_eq 'http://192.168.0.1/' "$(zte_http_referer 'http://192.168.0.1/goform/goform_get_cmd_process?cmd=LD')"
finish
