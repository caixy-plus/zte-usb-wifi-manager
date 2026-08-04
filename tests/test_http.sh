#!/bin/sh
set -eu
TEST_NAME=test_http
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh

# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh
. "$lib"
if command -v zte_http_get >/dev/null 2>&1; then pass; else fail 'zte_http_get missing'; fi
if command -v zte_http_post >/dev/null 2>&1; then pass; else fail 'zte_http_post missing'; fi
if command -v zte_http_post_classified >/dev/null 2>&1; then pass; else fail 'zte_http_post_classified missing'; fi
assert_eq 'plain-._~AZaz09' "$(zte_form_encode 'plain-._~AZaz09')"
assert_eq 'a%20b%26c%3Dd%2Be%25' "$(zte_form_encode 'a b&c=d+e%')"
assert_eq '%E4%B8%AD%E6%96%87' "$(zte_form_encode '中文')"
assert_eq 'key=a%20b%26c' "$(zte_form_pair key 'a b&c')"
assert_failure zte_form_pair 'bad&key' value
assert_eq 'http://192.168.0.1/' "$(zte_http_referer 'http://192.168.0.1/goform/goform_get_cmd_process?cmd=LD')"
assert_eq 'https://192.168.0.1/' "$(zte_http_referer 'https://192.168.0.1/goform/goform_get_cmd_process?cmd=LD')"
assert_success zte_http_origin_valid 'http://192.168.0.1'
assert_success zte_http_origin_valid 'https://192.168.0.1'
assert_failure zte_http_origin_valid 'ftp://192.168.0.1'
assert_failure zte_http_origin_valid 'https://user@192.168.0.1'
assert_failure zte_http_origin_valid 'https://192.168.0.1/path'
assert_failure zte_http_origin_valid 'https://192.168.0.1?query=x'

work=$(mktemp -d /tmp/zte-test-http.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat >"$work/bin/curl" <<'EOF'
#!/bin/sh
: >"$ZTE_TEST_CURL_ARGV"
read_stdin=0
previous=
cookie_jar=
output_file=
write_out=
for argument do
    printf '%s\n' "$argument" >>"$ZTE_TEST_CURL_ARGV"
    if [ "$previous" = '--data-binary' ] && [ "$argument" = '@-' ]; then
        read_stdin=1
    fi
    if [ "$previous" = '-c' ]; then
        cookie_jar=$argument
    fi
    if [ "$previous" = '-o' ]; then
        output_file=$argument
    fi
    if [ "$previous" = '--write-out' ]; then
        write_out=$argument
    fi
    previous=$argument
done
if [ -n "$cookie_jar" ]; then
    printf '%s\n' 'test-cookie' >"$cookie_jar"
fi
if [ "$read_stdin" -eq 1 ]; then
    cat >"$ZTE_TEST_CURL_STDIN"
else
    : >"$ZTE_TEST_CURL_STDIN"
fi
if [ -n "$output_file" ]; then
    printf '%s' "${ZTE_TEST_CURL_RESPONSE-}" >"$output_file"
else
    printf '%s' "${ZTE_TEST_CURL_RESPONSE-}"
fi
if [ -n "$write_out" ]; then
    printf '%s' "${ZTE_TEST_CURL_HTTP_CODE-200}"
fi
exit "${ZTE_TEST_CURL_EXIT-0}"
EOF
chmod +x "$work/bin/curl"

saved_path=$PATH
PATH="$work/bin:$PATH"
export PATH
ZTE_HTTP_TIMEOUT=17
export ZTE_HTTP_TIMEOUT
ZTE_TEST_CURL_ARGV=$work/argv
ZTE_TEST_CURL_STDIN=$work/stdin
ZTE_TEST_CURL_RESPONSE='GET response body'
ZTE_TEST_CURL_EXIT=0
export ZTE_TEST_CURL_ARGV ZTE_TEST_CURL_STDIN ZTE_TEST_CURL_RESPONSE ZTE_TEST_CURL_EXIT
ZTE_TEST_CURL_HTTP_CODE=200
export ZTE_TEST_CURL_HTTP_CODE

cookie_jar=$work/cookie-jar
get_url='http://192.168.0.1/goform/goform_get_cmd_process?cmd=LD&isTest=false'
assert_eq 'GET response body' "$(zte_http_get "$get_url" "$cookie_jar")"
assert_eq 600 "$(test_file_mode "$cookie_jar")" \
    'GET cookie jar must be explicitly restricted to mode 600'
expected_get_argv=$(cat <<EOF
-fsS
--max-time
17
-b
$cookie_jar
-c
$cookie_jar
-H
Referer: http://192.168.0.1/
-H
X-Requested-With: XMLHttpRequest
$get_url
EOF
)
assert_eq "$expected_get_argv" "$(cat "$ZTE_TEST_CURL_ARGV")" \
    'GET curl arguments do not match the safe request contract'
expected_empty_stdin=$work/expected-empty-stdin
: >"$expected_empty_stdin"
if cmp -s "$expected_empty_stdin" "$ZTE_TEST_CURL_STDIN"; then
    pass
else
    fail 'GET unexpectedly sent stdin bytes'
fi
assert_eq 0 "$(wc -c <"$ZTE_TEST_CURL_STDIN" | tr -d ' ')" \
    'GET stdin was not empty'

ZTE_HTTP_INTERFACE=eth2
export ZTE_HTTP_INTERFACE
assert_eq 'GET response body' "$(zte_http_get "$get_url" "$cookie_jar")"
assert_eq 1 "$(grep -c '^--interface$' "$ZTE_TEST_CURL_ARGV")"
assert_eq eth2 "$(awk 'previous == "--interface" { print; exit }
    { previous=$0 }' "$ZTE_TEST_CURL_ARGV")"
unset ZTE_HTTP_INTERFACE

ZTE_DEVICE_TLS_INSECURE=1
export ZTE_DEVICE_TLS_INSECURE
https_url='https://192.168.0.1/goform/goform_get_cmd_process?cmd=LD&isTest=false'
assert_eq 'GET response body' "$(zte_http_get "$https_url" "$cookie_jar")"
assert_eq 1 "$(grep -c '^--insecure$' "$ZTE_TEST_CURL_ARGV")"
assert_eq 'Referer: https://192.168.0.1/' "$(awk 'previous == "-H" && /^Referer:/ { print; exit }
    { previous=$0 }' "$ZTE_TEST_CURL_ARGV")"
unset ZTE_DEVICE_TLS_INSECURE

post_url='http://192.168.0.1/goform/goform_set_cmd_process'
form_body='goformId=LOGIN&password=3955A6F57CD749A4311DECB23407C5962119BC835A528EE1BA82B2CF04EEE078 digest value&token=a=b
line=two&tail=END!'
ZTE_TEST_CURL_RESPONSE='POST response body'
export ZTE_TEST_CURL_RESPONSE
assert_eq 'POST response body' "$(zte_http_post "$post_url" "$form_body" "$cookie_jar")"
assert_eq 600 "$(test_file_mode "$cookie_jar")" \
    'POST cookie jar must be explicitly restricted to mode 600'
expected_post_argv=$(cat <<EOF
-fsS
--max-time
17
-b
$cookie_jar
-c
$cookie_jar
-H
Referer: http://192.168.0.1/
-H
X-Requested-With: XMLHttpRequest
-H
Content-Type: application/x-www-form-urlencoded
--data-binary
@-
$post_url
EOF
)
assert_eq "$expected_post_argv" "$(cat "$ZTE_TEST_CURL_ARGV")" \
    'POST curl arguments expose the form body or omit required request arguments'
expected_stdin=$work/expected-stdin
printf '%s' "$form_body" >"$expected_stdin"
if cmp -s "$expected_stdin" "$ZTE_TEST_CURL_STDIN"; then
    pass
else
    fail 'POST form body bytes were not transferred unchanged over stdin'
fi
assert_eq "$(wc -c <"$expected_stdin" | tr -d ' ')" \
    "$(wc -c <"$ZTE_TEST_CURL_STDIN" | tr -d ' ')" \
    'POST stdin byte count differs from the form body'

ZTE_TEST_CURL_RESPONSE=
ZTE_TEST_CURL_EXIT=22
export ZTE_TEST_CURL_RESPONSE
export ZTE_TEST_CURL_EXIT
chmod 644 "$cookie_jar"
if zte_http_get "$get_url" "$cookie_jar"; then
    get_exit=0
else
    get_exit=$?
fi
assert_eq 22 "$get_exit" 'GET did not preserve curl exit status 22'
assert_eq 600 "$(test_file_mode "$cookie_jar")" \
    'GET failure must still restrict the cookie jar to mode 600'
chmod 644 "$cookie_jar"
if zte_http_post "$post_url" "$form_body" "$cookie_jar"; then
    post_exit=0
else
    post_exit=$?
fi
assert_eq 22 "$post_exit" 'POST did not preserve curl exit status 22'
assert_eq 600 "$(test_file_mode "$cookie_jar")" \
    'POST failure must still restrict the cookie jar to mode 600'

ZTE_TEST_CURL_EXIT=0
ZTE_TEST_CURL_RESPONSE=classified-success
ZTE_TEST_CURL_HTTP_CODE=200
export ZTE_TEST_CURL_EXIT ZTE_TEST_CURL_RESPONSE ZTE_TEST_CURL_HTTP_CODE
assert_eq classified-success \
    "$(zte_http_post_classified "$post_url" "$form_body" "$cookie_jar")"
ZTE_TEST_CURL_RESPONSE=classified-denied
ZTE_TEST_CURL_HTTP_CODE=403
export ZTE_TEST_CURL_RESPONSE ZTE_TEST_CURL_HTTP_CODE
classified_status=0
zte_http_post_classified "$post_url" "$form_body" "$cookie_jar" ||
    classified_status=$?
assert_eq 11 "$classified_status" 'HTTP 4xx must be a definite rejection'
ZTE_TEST_CURL_HTTP_CODE=500
export ZTE_TEST_CURL_HTTP_CODE
classified_status=0
zte_http_post_classified "$post_url" "$form_body" "$cookie_jar" ||
    classified_status=$?
assert_eq 10 "$classified_status" 'HTTP 5xx must remain ambiguous'
ZTE_TEST_CURL_EXIT=28
ZTE_TEST_CURL_HTTP_CODE=000
export ZTE_TEST_CURL_EXIT ZTE_TEST_CURL_HTTP_CODE
classified_status=0
zte_http_post_classified "$post_url" "$form_body" "$cookie_jar" ||
    classified_status=$?
assert_eq 10 "$classified_status" 'transport timeout must remain ambiguous'
if find "$work" -name 'cookie-jar.response.*' -print | grep . >/dev/null; then
    fail 'status-aware POST left a response temporary file behind'
else
    pass
fi

secure_call_count=$work/secure-call-count
zte_http_secure_cookie_jar() {
    count=$(cat "$secure_call_count")
    count=$((count + 1))
    printf '%s\n' "$count" >"$secure_call_count"
    [ "$count" -eq 1 ]
}
assert_post_cleanup_failure() {
    expected=$1
    http_code=$2
    curl_exit=$3
    printf '%s\n' 0 >"$secure_call_count"
    ZTE_TEST_CURL_HTTP_CODE=$http_code
    ZTE_TEST_CURL_EXIT=$curl_exit
    export ZTE_TEST_CURL_HTTP_CODE ZTE_TEST_CURL_EXIT
    classified_status=0
    zte_http_post_classified "$post_url" "$form_body" "$cookie_jar" ||
        classified_status=$?
    assert_eq "$expected" "$classified_status"
}
assert_post_cleanup_failure 10 200 0
assert_post_cleanup_failure 11 403 0
assert_post_cleanup_failure 10 000 28
if find "$work" -name 'cookie-jar.response.*' -print | grep . >/dev/null; then
    fail 'cleanup failure left a response temporary file behind'
else
    pass
fi

PATH=$saved_path
export PATH
rm -rf "$work"
trap - EXIT
finish
