#!/bin/sh
set -eu

TEST_NAME=test_recovery_guard
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
guard=./package/zte-usb-wifi-manager/files/usr/libexec/zte-usb-recovery-allowed
if [ ! -x "$guard" ]; then
    fail 'recovery guard must exist and be executable'
    finish
fi
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/recovery-inhibit.sh"

work=$(mktemp -d /tmp/zte-test-recovery-guard.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
inhibit=$work/inhibit-recovery
test_bin=$work/bin
mkdir -p "$test_bin"
# The generated stub expands this variable when it executes.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/sh' \
    'printf "%s\n" "${ZTE_TEST_NOW:-1722345678}"' >"$test_bin/date"
chmod +x "$test_bin/date"

guard_call() {
    ZTE_RECOVERY_LIB_DIR=$lib \
    ZTE_RECOVERY_INHIBIT_FILE=$inhibit \
    PATH="$test_bin:$PATH" \
        sh "$guard"
}

assert_success guard_call
assert_success zte_recovery_inhibit_write \
    "$inhibit" battery_high 1722346000 1722345600
assert_failure guard_call
assert_success test -f "$inhibit"
assert_success env ZTE_TEST_NOW=1722346000 \
    ZTE_RECOVERY_LIB_DIR="$lib" \
    ZTE_RECOVERY_INHIBIT_FILE="$inhibit" \
    PATH="$test_bin:$PATH" \
    sh "$guard"
assert_failure test -e "$inhibit"

printf '%s\n' '{"invalid":true}' >"$inhibit"
assert_success guard_call
assert_failure test -e "$inhibit"

finish
