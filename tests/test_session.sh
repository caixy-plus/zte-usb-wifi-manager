#!/bin/sh
set -eu
TEST_NAME=test_session
. ./tests/testlib.sh
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/session.sh"

work=/tmp/zte-test-session.$$
mkdir -p "$work"

assert_eq 'ecd71870d1963316a97e3ac3408c9835ad8cf0f3c1bc703527c30265534f75ae' \
    "$(zte_sha256_hex test123)"
assert_eq '3955A6F57CD749A4311DECB23407C5962119BC835A528EE1BA82B2CF04EEE078' \
    "$(zte_session_digest test123 LD-abc123)"
assert_eq '1AF5BB73CFA199DB1C17EB9FFE782A23B496E2128D7D74EE688C6FF575B9A471' \
    "$(zte_session_digest admin 0000000000)"

# successful login posts the expected digest (stub writes body to a file
# because zte_http_post runs inside command substitution)
post_log=$work/post-body
zte_http_get() { printf '%s\n' '{"LD":"LD-abc123"}'; }
zte_http_post() { printf '%s' "$2" >"$post_log"; printf '%s\n' '{"result":"0"}'; }
assert_success zte_session_login 192.168.0.1 test123 "$work/cookies"
assert_eq 'goformId=LOGIN&password=3955A6F57CD749A4311DECB23407C5962119BC835A528EE1BA82B2CF04EEE078' \
    "$(cat "$post_log")"

# non-zero login result is rejected
zte_http_post() { printf '%s\n' '{"result":"3"}'; }
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"

# missing or malformed LD is rejected without ever posting
post_calls=$work/post-calls
: >"$post_calls"
zte_http_post() { printf 'x\n' >>"$post_calls"; printf '%s\n' '{"result":"0"}'; }
zte_http_get() { printf '%s\n' '{}'; }
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"
zte_http_get() { printf '%s\n' 'not json'; }
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"
assert_eq 0 "$(wc -l <"$post_calls" | tr -d ' ')"

# credential file reading
printf 'password=s3cret value\n' >"$work/credentials"
chmod 600 "$work/credentials"
assert_eq 's3cret value' "$(zte_read_password "$work/credentials")"
chmod 644 "$work/credentials"
assert_failure zte_read_password "$work/credentials"
assert_failure zte_read_password "$work/does-not-exist"

# a broken hash tool must fail, not produce a wrong digest
mkdir -p "$work/bin"
printf '#!/bin/sh\nprintf garbage\n' >"$work/bin/sha256sum"
chmod +x "$work/bin/sha256sum"
assert_failure env PATH="$work/bin:/usr/bin:/bin" zte_sha256_hex test123

rm -rf "$work"
finish
