#!/bin/sh
set -eu

TEST_NAME=test_sensitive_data
. ./tests/testlib.sh

scanner=$(pwd)/tests/scan_sensitive_data.sh
work=/tmp/zte-test-sensitive.$$
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bad" "$work/clean"
printf 'password=%s\n' 'outside-untracked-secret-value' >"$work/outside-secret.txt"
mkdir -p "$work/outside-secret-directory"

init_repo() {
    (
        cd "$1"
        git init -q
        git config user.email test@example.invalid
        git config user.name test
    )
}

file_id() {
    node -e '
const crypto = require("crypto");
const digest = crypto.createHash("sha256").update(process.argv[1]).digest("hex");
process.stdout.write("file:" + digest.slice(0, 12));
' "$1"
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
    printf 'mac_address=%s:%s:%s:%s:%s:%s\n' 02 11 22 33 44 55 >mac.txt
    printf '{"password":"%s"}\n' 'literal-json-secret-value' >json-secret.json
    printf 'international_phone=%s\n' '+8613812345678' >international-phone.txt
    printf 'password=%s\n' 'unicode-secret-value' >'敏感.txt'
    comment_marker='#'
    printf '%s password=%s\n' "$comment_marker" 'comment-secret-value' >comment.txt
    newline_name=$(printf 'secret-filename\npart.txt')
    printf 'Cookie: newline=%s\n' 'newline-cookie-value' >"$newline_name"
    printf '\000password=binary-secret-value\n' >binary.dat
    ln -s "$work/outside-secret.txt" outside-file-link
    ln -s "$work/outside-secret-directory" outside-directory-link
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
newline_path=$(printf 'secret-filename\npart.txt')
for finding in \
    "$(file_id private.txt):1 PRIVATE_KEY" \
    "$(file_id authorization.txt):1 AUTHORIZATION" \
    "$(file_id cookie.txt):1 HTTP_COOKIE" \
    "$(file_id token.txt):1 HIGH_RISK_TOKEN" \
    "$(file_id url.txt):1 URL_CREDENTIALS" \
    "$(file_id assignment.txt):1 SECRET_ASSIGNMENT" \
    "$(file_id phone.txt):1 PHONE_NUMBER" \
    "$(file_id imei.txt):1 15_DIGIT_IDENTIFIER" \
    "$(file_id imsi.txt):1 15_DIGIT_IDENTIFIER" \
    "$(file_id iccid.txt):1 ICCID" \
    "$(file_id sensitive-field.txt):1 SENSITIVE_FIELD" \
    "$(file_id mac.txt):1 MAC_ADDRESS" \
    "$(file_id json-secret.json):1 SECRET_ASSIGNMENT" \
    "$(file_id international-phone.txt):1 PHONE_NUMBER" \
    "$(file_id '敏感.txt'):1 SECRET_ASSIGNMENT" \
    "$(file_id comment.txt):1 SECRET_ASSIGNMENT" \
    "$(file_id "$newline_path"):1 HTTP_COOKIE"; do
    case $bad_output in
        *"$finding"*) pass ;;
        *) fail "missing sanitized finding: $finding" ;;
    esac
done
for symlink in outside-file-link outside-directory-link; do
    case $bad_output in
        *"$(file_id "$symlink"):"*) fail 'scanner must skip tracked symlinks' ;;
        *) pass ;;
    esac
done
case $bad_output in
    *"$(file_id binary.dat):"*) fail 'scanner must skip tracked binary files' ;;
    *) pass ;;
esac
if printf '%s\n' "$bad_output" |
    grep -Ev '^file:[0-9a-f]{12}:[0-9]+ [A-Z0-9_]+$' |
    grep -q .; then
    fail 'scanner findings must contain only anonymous file id, line, and type'
else
    pass
fi
for secret_fragment in \
    real-auth-value real-cookie-value literal-password-value \
    literal-json-secret-value unicode-secret-value comment-secret-value \
    newline-cookie-value \
    outside-untracked-secret-value outside-secret-directory \
    13812345678 123456789012345 8986001234567890123 \
    '敏感.txt' secret-filename; do
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
        '{"password":"<secret>"}' \
        'Never commit private keys, cookies, passwords, or device identifiers.' \
        >placeholders.txt
    printf 'test phone: %s\n' '13812345678' >synthetic.txt
    printf 'test phone: %s\n' '13812345678' >'敏感.txt'
    mkdir -p tests
    printf '%s\n' \
        'synthetic.txt:1:PHONE_NUMBER' \
        '敏感.txt:1:PHONE_NUMBER' \
        >tests/sensitive-data.allowlist
    git add .
)
assert_success sh -c "cd '$work/clean' && '$scanner'"

finish
