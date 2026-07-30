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
# Injected into zte_session_login from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { printf '%s\n' '{"LD":"LD-abc123"}'; }
# Injected into zte_session_login from the sourced production library.
# shellcheck disable=SC2329
zte_http_post() { printf '%s' "$2" >"$post_log"; printf '%s\n' '{"result":"0"}'; }
_zte_digest=unchanged-digest
_zte_step1=unchanged-step1
_zte_step2=unchanged-step2
_zte_hash=unchanged-hash
assert_success zte_session_login 192.168.0.1 test123 "$work/cookies"
assert_eq 'goformId=LOGIN&password=3955A6F57CD749A4311DECB23407C5962119BC835A528EE1BA82B2CF04EEE078' \
    "$(cat "$post_log")"
assert_eq unchanged-digest "$_zte_digest"
assert_eq unchanged-step1 "$_zte_step1"
assert_eq unchanged-step2 "$_zte_step2"
assert_eq unchanged-hash "$_zte_hash"

# non-zero login result is rejected
# Injected into zte_session_login from the sourced production library.
# shellcheck disable=SC2329
zte_http_post() { printf '%s\n' '{"result":"3"}'; }
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"

# missing or malformed LD is rejected without ever posting
post_calls=$work/post-calls
: >"$post_calls"
# Injected into zte_session_login from the sourced production library.
# shellcheck disable=SC2329
zte_http_post() { printf 'x\n' >>"$post_calls"; printf '%s\n' '{"result":"0"}'; }
# Injected into zte_session_login from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { printf '%s\n' '{}'; }
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"
# Injected into zte_session_login from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() { printf '%s\n' 'not json'; }
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"
assert_eq 0 "$(wc -l <"$post_calls" | tr -d ' ')"

# credential file reading
printf 'password=s3cret value\n' >"$work/credentials"
chmod 600 "$work/credentials"
assert_eq 600 "$(zte_file_mode "$work/credentials")" \
    'credential mode helper must report numeric mode'
assert_eq 's3cret value' "$(zte_read_password "$work/credentials")"

current_uid=$(id -u)
assert_eq "$current_uid" "$(zte_file_owner_uid "$work/credentials")" \
    'credential owner helper did not report the real owner UID'

# Injected into zte_read_password to simulate a process running as another
# account without requiring privileged chown in the test.
# shellcheck disable=SC2329
zte_effective_uid() { printf '%s\n' "$effective_uid_result"; }
effective_uid_result=$((current_uid + 1))
assert_failure zte_read_password "$work/credentials"

effective_uid_result=$current_uid
chmod 644 "$work/credentials"
assert_failure zte_read_password "$work/credentials"

for credential_mode in 400 700 200 000; do
    chmod "$credential_mode" "$work/credentials"
    assert_failure zte_read_password "$work/credentials"
done

chmod 600 "$work/credentials"
ln -s "$work/credentials" "$work/credentials-link"
assert_failure zte_read_password "$work/credentials-link"
assert_failure zte_read_password "$work/does-not-exist"

# A read failure must propagate instead of being hidden by a successful final
# command in a pipeline.
mkdir -p "$work/read-failure-bin"
cat >"$work/read-failure-bin/awk" <<'EOF'
#!/bin/sh
exit 7
EOF
chmod +x "$work/read-failure-bin/awk"
saved_path=$PATH
PATH="$work/read-failure-bin:$PATH"
assert_failure zte_read_password "$work/credentials"
PATH=$saved_path

# a broken hash tool must fail, not produce a wrong digest
mkdir -p "$work/bin"
printf '#!/bin/sh\nprintf garbage\n' >"$work/bin/sha256sum"
chmod +x "$work/bin/sha256sum"
saved_path=$PATH
PATH="$work/bin:/usr/bin:/bin"
assert_failure zte_sha256_hex test123
PATH=$saved_path

rm -rf "$work"
finish
