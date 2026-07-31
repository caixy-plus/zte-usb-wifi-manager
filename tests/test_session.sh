#!/bin/sh
# HTTP stubs are invoked from production functions loaded with source, which
# ShellCheck 0.9 cannot trace across files.
# shellcheck disable=SC2317
set -eu
TEST_NAME=test_session
. ./tests/testlib.sh
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/credentials.sh"
. "$lib/session.sh"

work=/tmp/zte-test-session.$$
mkdir -p "$work"
assert_eq /var/run/zte-usb-wifi-manager-session.lock \
    "$ZTE_SESSION_LOCK_FILE" \
    'default session lock must not depend on the daemon runtime directory'
assert_success test -d "${ZTE_SESSION_LOCK_FILE%/*}"
ZTE_SESSION_LOCK_FILE=$work/login.lock
ZTE_SESSION_LOCK_ATTEMPTS=1
ZTE_SESSION_LOCK_INTERVAL=0
export ZTE_SESSION_LOCK_FILE ZTE_SESSION_LOCK_ATTEMPTS
export ZTE_SESSION_LOCK_INTERVAL

assert_eq 'ecd71870d1963316a97e3ac3408c9835ad8cf0f3c1bc703527c30265534f75ae' \
    "$(zte_sha256_hex test123)"
assert_eq '9677B188078A8ABD861E7FFD312B35BC7EA176616DF6BF0BA2AC7F22764710A7' \
    "$(zte_session_digest test123 LD-abc123)"
assert_eq 'BB0BCCC1797AF4B9132536CAE0CD0E4E580DC4D043F386F848C79C4A559CD83A' \
    "$(zte_session_digest admin 0000000000)"

# successful login posts the expected digest (stub writes body to a file
# because zte_http_post runs inside command substitution)
post_log=$work/post-body
# Injected into zte_session_login from the sourced production library.
# shellcheck disable=SC2329
zte_http_get() {
    [ -f "$ZTE_SESSION_LOCK_FILE" ] || return 1
    printf '%s\n' '{"LD":"LD-abc123"}'
}
# Injected into zte_session_login from the sourced production library.
# shellcheck disable=SC2329
zte_http_post() {
    [ -f "$ZTE_SESSION_LOCK_FILE" ] || return 1
    printf '%s' "$2" >"$post_log"
    printf '%s\n' '{"result":"0"}'
}
_zte_digest=unchanged-digest
_zte_step1=unchanged-step1
_zte_step2=unchanged-step2
_zte_hash=unchanged-hash
assert_success zte_session_login 192.168.0.1 test123 "$work/cookies"
assert_eq 'goformId=LOGIN&password=9677B188078A8ABD861E7FFD312B35BC7EA176616DF6BF0BA2AC7F22764710A7' \
    "$(cat "$post_log")"
assert_eq unchanged-digest "$_zte_digest"
assert_eq unchanged-step1 "$_zte_step1"
assert_eq unchanged-step2 "$_zte_step2"
assert_eq unchanged-hash "$_zte_hash"
if [ -e "$ZTE_SESSION_LOCK_FILE" ]; then
    fail 'successful login must release the shared session lock'
else
    pass
fi

# Neither a live nor dead owner can be displaced without an atomic
# compare-and-swap primitive. Dead locks fail closed instead of risking two
# simultaneous owners.
printf '%s\n' "$$" >"$ZTE_SESSION_LOCK_FILE"
chmod 600 "$ZTE_SESSION_LOCK_FILE"
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"
assert_eq "$$" "$(cat "$ZTE_SESSION_LOCK_FILE")"
rm -f "$ZTE_SESSION_LOCK_FILE"

printf '%s\n' 2147483647 >"$ZTE_SESSION_LOCK_FILE"
chmod 600 "$ZTE_SESSION_LOCK_FILE"
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"
assert_eq 2147483647 "$(cat "$ZTE_SESSION_LOCK_FILE")"
rm -f "$ZTE_SESSION_LOCK_FILE"

# A missing custom lock parent fails closed without creating an unowned tree.
saved_lock_file=$ZTE_SESSION_LOCK_FILE
ZTE_SESSION_LOCK_FILE=$work/missing-parent/login.lock
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"
if [ -e "$work/missing-parent" ]; then
    fail 'session login must not create an unverified lock parent'
else
    pass
fi
ZTE_SESSION_LOCK_FILE=$saved_lock_file

# Two actual shell processes must never overlap their LD -> LOGIN exchanges.
concurrent_helper=$work/concurrent-login
cat >"$concurrent_helper" <<'EOF'
#!/bin/sh
set -eu
lib=$1
ZTE_SESSION_LOCK_FILE=$2
event_log=$3
release_gate=$4
role=$5
ZTE_SESSION_LOCK_ATTEMPTS=5
ZTE_SESSION_LOCK_INTERVAL=1
case $role in
    stale-*) ZTE_SESSION_LOCK_ATTEMPTS=1 ;;
esac
export ZTE_SESSION_LOCK_FILE ZTE_SESSION_LOCK_ATTEMPTS
export ZTE_SESSION_LOCK_INTERVAL
. "$lib/json.sh"
. "$lib/session.sh"
zte_http_get() {
    printf '%s:get\n' "$role" >>"$event_log"
    if [ "$role" = first ]; then
        while [ ! -e "$release_gate" ]; do
            sleep 0.05
        done
    elif [ "$role" = signal ]; then
        while [ ! -e "$release_gate" ]; do
            sleep 0.05
        done
    fi
    printf '%s\n' '{"LD":"LD-abc123"}'
}
zte_http_post() {
    printf '%s:post\n' "$role" >>"$event_log"
    printf '%s\n' '{"result":"0"}'
}
zte_session_login 192.168.0.1 test123 "$role.cookies"
EOF
chmod +x "$concurrent_helper"
concurrent_log=$work/concurrent-events
release_gate=$work/release-first
: >"$concurrent_log"
"$concurrent_helper" "$lib" "$ZTE_SESSION_LOCK_FILE" \
    "$concurrent_log" "$release_gate" first &
first_pid=$!
concurrent_attempt=0
while ! grep -Fqx 'first:get' "$concurrent_log"; do
    concurrent_attempt=$((concurrent_attempt + 1))
    [ "$concurrent_attempt" -lt 100 ] || break
    sleep 0.02
done
assert_eq first:get "$(cat "$concurrent_log")"
"$concurrent_helper" "$lib" "$ZTE_SESSION_LOCK_FILE" \
    "$concurrent_log" "$release_gate" second &
second_pid=$!
sleep 0.1
assert_eq first:get "$(cat "$concurrent_log")"
: >"$release_gate"
assert_success wait "$first_pid"
assert_success wait "$second_pid"
assert_eq 'first:get
first:post
second:get
second:post' "$(cat "$concurrent_log")"
if [ -e "$ZTE_SESSION_LOCK_FILE" ]; then
    fail 'concurrent logins must release the shared session lock'
else
    pass
fi

# Two contenders observing the same dead PID must both fail closed and leave
# that exact lock in place; neither may enter the HTTP exchange.
: >"$concurrent_log"
printf '%s\n' 2147483647 >"$ZTE_SESSION_LOCK_FILE"
chmod 600 "$ZTE_SESSION_LOCK_FILE"
"$concurrent_helper" "$lib" "$ZTE_SESSION_LOCK_FILE" \
    "$concurrent_log" "$release_gate" stale-one &
stale_one_pid=$!
"$concurrent_helper" "$lib" "$ZTE_SESSION_LOCK_FILE" \
    "$concurrent_log" "$release_gate" stale-two &
stale_two_pid=$!
if wait "$stale_one_pid"; then
    fail 'first stale-lock contender must fail closed'
else
    pass
fi
if wait "$stale_two_pid"; then
    fail 'second stale-lock contender must fail closed'
else
    pass
fi
assert_eq '' "$(cat "$concurrent_log")"
assert_eq 2147483647 "$(cat "$ZTE_SESSION_LOCK_FILE")"
rm -f "$ZTE_SESSION_LOCK_FILE"

# TERM inside the LD request must run the login subshell cleanup trap.
: >"$concurrent_log"
rm -f "$release_gate"
"$concurrent_helper" "$lib" "$ZTE_SESSION_LOCK_FILE" \
    "$concurrent_log" "$release_gate" signal &
signal_pid=$!
signal_attempt=0
while ! grep -Fqx 'signal:get' "$concurrent_log"; do
    signal_attempt=$((signal_attempt + 1))
    [ "$signal_attempt" -lt 100 ] || break
    sleep 0.02
done
signal_child=$(ps -eo pid=,ppid= |
    awk -v parent="$signal_pid" '$2 == parent { print $1; exit }')
case $signal_child in
    ''|*[!0-9]*) fail 'could not identify the login lock holder' ;;
    *) assert_success kill -TERM "$signal_child" ;;
esac
: >"$release_gate"
if wait "$signal_pid"; then
    fail 'interrupted login must fail'
else
    pass
fi
if [ -e "$ZTE_SESSION_LOCK_FILE" ]; then
    fail 'interrupted login must release the shared session lock'
else
    pass
fi

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
