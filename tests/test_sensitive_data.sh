#!/bin/sh
set -eu

TEST_NAME=test_sensitive_data
. ./tests/testlib.sh

scanner=$(pwd)/tests/scan_sensitive_data.sh
work=/tmp/zte-test-sensitive.$$
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bad" "$work/clean"

init_repo() {
    (
        cd "$1"
        git init -q
        git config user.email test@example.invalid
        git config user.name test
    )
}

init_repo "$work/bad"
(
    cd "$work/bad"
    begin='-----BEGIN '
    auth_scheme=Bear
    auth_scheme=${auth_scheme}er
    token_prefix=gh
    token_prefix=${token_prefix}p_
    printf '%s%s\n' "$begin" 'PRIVATE KEY-----' >private.txt
    printf 'Authorization: %s %s\n' "$auth_scheme" 'real-auth-value' >authorization.txt
    printf 'Cookie: session=%s\n' 'real-cookie-value' >cookie.txt
    printf 'api_key=%s%s\n' "$token_prefix" 'abcdefghijklmnopqrstuvwxyz123456' >token.txt
    printf 'endpoint=https://service-user:%s@example.invalid/api\n' 'real-url-password' >url.txt
    printf 'password=%s\n' 'literal-password-value' >assignment.txt
    printf 'phone_number=%s\n' '13812345678' >phone.txt
    printf 'imei=%s\n' '123456789012345' >imei.txt
    printf 'imsi=%s\n' '460001234567890' >imsi.txt
    printf 'iccid=%s\n' '8986001234567890123' >iccid.txt
    printf 'device_imei: %s\n' 'not-a-number-but-still-sensitive' >sensitive-field.txt
    git add .
)

if (
    cd "$work/bad"
    grep -R -q -E '[0-9]{8}qq' .
); then
    fail 'legacy scan unexpectedly detected the fixtures'
else
    pass
fi

bad_output=$(
    cd "$work/bad"
    "$scanner" 2>&1
) && bad_status=0 || bad_status=$?
assert_eq 1 "$bad_status" 'scanner must reject tracked sensitive data'
for finding in \
    'private.txt:1 PRIVATE_KEY' \
    'authorization.txt:1 AUTHORIZATION' \
    'cookie.txt:1 HTTP_COOKIE' \
    'token.txt:1 HIGH_RISK_TOKEN' \
    'url.txt:1 URL_CREDENTIALS' \
    'assignment.txt:1 SECRET_ASSIGNMENT' \
    'phone.txt:1 PHONE_NUMBER' \
    'imei.txt:1 15_DIGIT_IDENTIFIER' \
    'imsi.txt:1 15_DIGIT_IDENTIFIER' \
    'iccid.txt:1 ICCID' \
    'sensitive-field.txt:1 SENSITIVE_FIELD'; do
    case $bad_output in
        *"$finding"*) pass ;;
        *) fail "missing sanitized finding: $finding" ;;
    esac
done
for secret_fragment in \
    real-auth-value real-cookie-value literal-password-value \
    13812345678 123456789012345 8986001234567890123; do
    case $bad_output in
        *"$secret_fragment"*) fail "scanner output leaked fixture content" ;;
        *) pass ;;
    esac
done

init_repo "$work/clean"
(
    cd "$work/clean"
    # Literal placeholder syntax is the fixture under test.
    # shellcheck disable=SC2016
    printf '%s\n' \
        'Authorization: Bearer <token>' \
        'Cookie: session=<redacted>' \
        'password=${PASSWORD}' \
        'Never commit private keys, cookies, passwords, or device identifiers.' \
        >placeholders.txt
    printf 'test phone: %s\n' '13812345678' >synthetic.txt
    mkdir -p tests
    printf '%s\n' 'synthetic.txt:1:PHONE_NUMBER' >tests/sensitive-data.allowlist
    git add .
)
assert_success sh -c "cd '$work/clean' && '$scanner'"

finish
