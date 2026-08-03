#!/bin/sh
set -eu

TEST_NAME=test_smart_charge_policy
. ./tests/testlib.sh
. ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/smart-charge-policy.sh

# Disabled automation and every untrusted input preserve the current mode.
assert_eq 'DISABLED:KEEP' "$(zte_smart_charge_decide 0 50 30 80 charging)"
assert_eq 'STATE_UNKNOWN:KEEP' "$(zte_smart_charge_decide 1 unknown 30 80 charging)"
assert_eq 'STATE_UNKNOWN:KEEP' "$(zte_smart_charge_decide 1 50 30 80 unknown)"

# Boundary values switch modes; the open interval is hysteretic.
assert_eq 'BATTERY_LOW:CHARGE' "$(zte_smart_charge_decide 1 30 30 80 direct_supply)"
assert_eq 'BATTERY_HIGH:DIRECT_SUPPLY' "$(zte_smart_charge_decide 1 80 30 80 charging)"
assert_eq 'HYSTERESIS:CHARGE' "$(zte_smart_charge_decide 1 50 30 80 charging)"
assert_eq 'HYSTERESIS:DIRECT_SUPPLY' "$(zte_smart_charge_decide 1 50 30 80 direct_supply)"

# Configuration and observed values are strict and fail closed.
assert_failure zte_smart_charge_decide 1 50 80 30 charging
assert_failure zte_smart_charge_decide 1 50 30 101 charging
assert_failure zte_smart_charge_decide 1 101 30 80 charging
assert_failure zte_smart_charge_decide maybe 50 30 80 charging

finish
