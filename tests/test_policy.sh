#!/bin/sh
set -eu

TEST_NAME=test_policy
. ./tests/testlib.sh
. ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/policy.sh

assert_eq 'DISABLED:KEEP' "$(zte_policy_decide 0 0 0 0 82 70 100 ON)"
assert_eq 'FAIL_SAFE_ON:ON' "$(zte_policy_decide 1 1 0 0 82 70 100 ON)"
assert_eq 'MANUAL_FULL:ON' "$(zte_policy_decide 1 0 1 0 82 70 100 OFF)"
assert_eq 'PRE_DEPARTURE:ON' "$(zte_policy_decide 1 0 0 1 82 70 100 OFF)"
assert_eq 'MAINTAIN_CHARGING:ON' "$(zte_policy_decide 1 0 0 0 70 70 100 OFF)"
assert_eq 'MAINTAIN_BATTERY:OFF' "$(zte_policy_decide 1 0 0 0 100 70 100 ON)"
assert_eq 'MAINTAIN_CHARGING:ON' "$(zte_policy_decide 1 0 0 0 82 70 100 ON)"
assert_eq 'MAINTAIN_BATTERY:OFF' "$(zte_policy_decide 1 0 0 0 82 70 100 OFF)"
assert_failure zte_policy_decide 1 0 0 0 unknown 70 100 ON

finish
