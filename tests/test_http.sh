#!/bin/sh
set -eu
TEST_NAME=test_http
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh

# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh
. "$lib"
if command -v zte_http_get >/dev/null 2>&1; then pass; else fail 'zte_http_get missing'; fi
if command -v zte_http_post >/dev/null 2>&1; then pass; else fail 'zte_http_post missing'; fi
assert_eq 'http://192.168.0.1/' "$(zte_http_referer 'http://192.168.0.1/goform/goform_get_cmd_process?cmd=LD')"

work=$(mktemp -d /tmp/zte-test-http.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat >"$work/bin/curl" <<'EOF'
#!/bin/sh
: >"$ZTE_TEST_CURL_ARGV"
read_stdin=0
previous=
for argument do
    printf '%s\n' "$argument" >>"$ZTE_TEST_CURL_ARGV"
    if [ "$previous" = '--data-binary' ] && [ "$argument" = '@-' ]; then
        read_stdin=1
    fi
    previous=$argument
done
if [ "$read_stdin" -eq 1 ]; then
    cat >"$ZTE_TEST_CURL_STDIN"
else
    : >"$ZTE_TEST_CURL_STDIN"
fi
printf '%s' "${ZTE_TEST_CURL_RESPONSE-}"
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

cookie_jar=$work/cookie-jar
get_url='http://192.168.0.1/goform/goform_get_cmd_process?cmd=LD&isTest=false'
assert_eq 'GET response body' "$(zte_http_get "$get_url" "$cookie_jar")"
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
assert_eq '' "$(cat "$ZTE_TEST_CURL_STDIN")" 'GET unexpectedly sent stdin data'

post_url='http://192.168.0.1/goform/goform_set_cmd_process'
form_body='goformId=LOGIN&password=3955A6F57CD749A4311DECB23407C5962119BC835A528EE1BA82B2CF04EEE078 digest value&token=a=b'
ZTE_TEST_CURL_RESPONSE='POST response body'
export ZTE_TEST_CURL_RESPONSE
assert_eq 'POST response body' "$(zte_http_post "$post_url" "$form_body" "$cookie_jar")"
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
assert_eq "$form_body" "$(cat "$ZTE_TEST_CURL_STDIN")" \
    'POST form body was not transferred unchanged over stdin'

ZTE_TEST_CURL_RESPONSE=
ZTE_TEST_CURL_EXIT=22
export ZTE_TEST_CURL_RESPONSE
export ZTE_TEST_CURL_EXIT
assert_failure zte_http_get "$get_url" "$cookie_jar"
assert_failure zte_http_post "$post_url" "$form_body" "$cookie_jar"

PATH=$saved_path
export PATH
rm -rf "$work"
trap - EXIT
finish
