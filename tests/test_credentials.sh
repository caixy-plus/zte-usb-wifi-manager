#!/bin/sh
set -eu

TEST_NAME=test_credentials
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
credentials=$lib/credentials.sh
if [ ! -f "$credentials" ]; then
    fail 'credential library must exist'
fi
# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/credentials.sh
. "$credentials"

work=$(mktemp -d /tmp/zte-test-credentials.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
credential_file=$work/etc/zte-usb-wifi-manager/credentials

assert_success zte_password_valid 'normal value'
assert_success zte_password_valid 'symbols-_=+!@#'
assert_failure zte_password_valid ''
assert_failure zte_password_valid "line1
line2"
assert_failure zte_password_valid "$(printf 'x%.0s' $(seq 1 257))"

assert_success zte_credential_path_valid "$credential_file"
assert_failure zte_credential_path_valid credentials
assert_failure zte_credential_path_valid /
assert_failure zte_credential_path_valid "$work/../escape"

assert_failure zte_read_password "$credential_file"
assert_eq absent "$(zte_credential_revision "$credential_file")"
assert_success zte_write_password "$credential_file" 'first secret'
first_revision=$(zte_credential_revision "$credential_file")
case $first_revision in
    *secret*|*password*) fail 'credential revision exposed credential content' ;;
    absent|'') fail 'credential revision did not describe the installed file' ;;
    *) pass ;;
esac
assert_eq 600 "$(zte_file_mode "$credential_file")"
assert_eq "$(id -u)" "$(zte_file_owner_uid "$credential_file")"
assert_eq 'first secret' "$(zte_read_password "$credential_file")"
if find "$(dirname "$credential_file")" -maxdepth 1 \
    -name 'credentials.tmp.*' -print -quit | grep -q .; then
    fail 'atomic credential write left a temporary file'
else
    pass
fi

assert_success zte_write_password "$credential_file" 'replacement secret'
replacement_revision=$(zte_credential_revision "$credential_file")
if [ "$replacement_revision" = "$first_revision" ]; then
    fail 'atomic credential replacement must change its non-secret revision'
else
    pass
fi
assert_eq 'replacement secret' "$(zte_read_password "$credential_file")"
assert_eq 600 "$(zte_file_mode "$credential_file")"

real_file=$work/real-credentials
printf '%s\n' 'password=PLACEHOLDER' >"$real_file"
chmod 600 "$real_file"
link_file=$work/credential-link
ln -s "$real_file" "$link_file"
assert_failure zte_write_password "$link_file" 'must not replace symlink'
assert_failure zte_clear_password "$link_file"
assert_eq 'password=PLACEHOLDER' "$(cat "$real_file")"

clear_file=$work/clear-credentials
assert_success zte_clear_password "$clear_file"
printf '%s\n' 'password=PLACEHOLDER' >"$clear_file"
chmod 644 "$clear_file"
assert_failure zte_clear_password "$clear_file"
assert_success test -f "$clear_file"
chmod 600 "$clear_file"
assert_success zte_clear_password "$clear_file"
assert_failure test -e "$clear_file"
assert_eq absent "$(zte_credential_revision "$clear_file")"
mkdir "$work/not-a-credential"
assert_failure zte_clear_password "$work/not-a-credential"

current_uid=$(id -u)
# Injected into zte_read_password to simulate another effective account.
# shellcheck disable=SC2329
zte_effective_uid() { printf '%s\n' "$effective_uid_result"; }
effective_uid_result=$((current_uid + 1))
assert_failure zte_read_password "$credential_file"
effective_uid_result=$current_uid

chmod 644 "$credential_file"
assert_failure zte_read_password "$credential_file"
chmod 600 "$credential_file"

finish
