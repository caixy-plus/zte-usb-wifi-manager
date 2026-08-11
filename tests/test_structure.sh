#!/bin/sh
# Product structure contract for the U30 smart-charge-only surface.
# shellcheck disable=SC2016,SC2317
set -eu

TEST_NAME=test_structure
. ./tests/testlib.sh

backend=package/zte-usb-wifi-manager
luci='luci-app-zte-usb-wifi-manager'
config="$backend/files/etc/config/zte-usb-wifi-manager"
daemon="$backend/files/usr/sbin/zte-usb-wifi-managerd"
rpcd="$backend/files/usr/libexec/rpcd/zte_usb_wifi"
view="$luci/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js"
acl="$luci/root/usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json"
menu="$luci/root/usr/share/luci/menu.d/luci-app-zte-usb-wifi-manager.json"
metadata="$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh"

# Config: charge product only.
if grep -Eq "^config (battery 'policy'|schedule 'work'|power 'usb')$" "$config"; then
    fail 'default config must not expose retired USB battery/power sections'
else
    pass
fi
assert_file_contains "$config" "^config smart_charge 'charging'$"
assert_file_contains "$config" "option enabled '1'"
assert_file_contains "$config" "option low_percent '30'"
assert_file_contains "$config" "option high_percent '80'"
assert_file_contains "$config" "option access_profile 'charge_v1'"
assert_file_contains "$config" "option adapter 'zte_u30'"
assert_file_contains "$config" "option set_power_supply_mode_enabled '1'"
if grep -E "switch_sim_enabled|set_apn_enabled|set_wifi_enabled|send_sms_enabled|reboot_device_enabled" "$config" >/dev/null; then
    fail 'default config must not enable removed product write gates'
else
    pass
fi

# Daemon poll: smart charge on, no VBUS policy / no private SMS/clients.
poll_once_source=$(sed -n '/^poll_once() {$/,/^}$/p' "$daemon")
case $poll_once_source in
    *zte_policy_decide*|*apply_policy_action*)
        fail 'polling must not execute battery-driven USB VBUS actions'
        ;;
    *) pass ;;
esac
case $poll_once_source in
    *'apply_smart_charge_policy'*) pass ;;
    *) fail 'polling must evaluate U30 device-side smart charging' ;;
esac
case $poll_once_source in
    *'collect_private_clients '*|*'collect_private_sms '*|*'write_sms_cache '*)
        fail 'polling must not refresh removed private client/SMS collections'
        ;;
    *) pass ;;
esac
case $poll_once_source in
    *'clients_json='*) pass ;;
    *) fail 'polling must still supply a clients placeholder for normalize' ;;
esac

# Package metadata.
assert_file_contains "$backend/Makefile" '^PKG_NAME:=zte-usb-wifi-manager$'
assert_file_contains "$backend/Makefile" '^PKG_VERSION:=0\.1\.0_rc1$'
assert_file_contains "$backend/Makefile" '^PKG_RELEASE:=33$'
assert_file_contains "$backend/Makefile" 'charge_v1'
assert_file_contains "$backend/Makefile" 'set_power_supply_mode_enabled 1'
if grep -q 'zte-usb-power-restore' "$backend/Makefile"; then
    fail 'package must not require USB power restore on uninstall'
else
    pass
fi
if grep -q 'full_v1' "$backend/Makefile"; then
    fail 'package must migrate to charge_v1, not full console profile'
else
    pass
fi

# Capabilities: only power write remains product-supported.
assert_file_contains "$metadata" '^ZTE_U30_CAP_SET_POWER_SUPPLY_MODE=1$'
assert_file_contains "$metadata" '^ZTE_U30_CAP_SET_APN=0$'
assert_file_contains "$metadata" '^ZTE_U25S_CAP_SWITCH_SIM=0$'
assert_file_contains "$metadata" '^ZTE_CAP_SWITCH_SIM=0$'

# rpcd product surface.
assert_file_contains "$rpcd" 'charging_settings'
assert_file_contains "$rpcd" 'set_charging_settings'
assert_file_contains "$rpcd" 'zte_event_list_filtered'
if grep -E 'cellular_action|wifi_action|sms_action|device_action|power_action|operation_status|sms_messages' "$rpcd" >/dev/null; then
    fail 'rpcd must not expose removed console action methods'
else
    pass
fi

# LuCI product surface.
assert_file_contains "$luci/Makefile" '^PKG_RELEASE:=14$'
assert_file_contains "$menu" '中兴智能充电'
assert_file_contains "$view" "id: 'device'"
assert_file_contains "$view" "id: 'charging'"
assert_file_contains "$view" "id: 'logs'"
for removed in overview network wifi clients traffic sms diagnostics; do
    if grep -F "id: '$removed'" "$view" >/dev/null; then
        fail "LuCI must not keep removed tab $removed"
    else
        pass
    fi
done
if grep -E 'cellular_action|wifi_action|sms_action|device_action|power_action' "$view" >/dev/null; then
    fail 'LuCI must not declare removed action RPC methods'
else
    pass
fi

assert_success node -e '
const fs = require("fs");
const acl = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const read = acl["luci-app-zte-usb-wifi-manager"].read;
const write = acl["luci-app-zte-usb-wifi-manager"].write;
if (JSON.stringify(read.ubus.zte_usb_wifi) !==
    JSON.stringify(["status", "capabilities", "charging_settings", "credential_status", "logs"]))
    process.exit(1);
if (JSON.stringify(write.ubus.zte_usb_wifi) !==
    JSON.stringify(["set_credentials", "clear_credentials", "set_charging_settings"]))
    process.exit(1);
' "$acl"

# Root Makefile keeps charge-critical suites.
assert_file_contains Makefile 'tests/test_smart_charge_policy.sh'
assert_file_contains Makefile 'tests/test_daemon_smart_charge.sh'
assert_file_contains Makefile 'tests/test_charging_transaction.sh'
assert_file_contains Makefile 'tests/test_rpcd.sh'
for removed in \
    tests/test_u25s_simulator.sh \
    tests/test_daemon_actions.sh \
    tests/test_power_adapter.sh \
    tests/test_recovery_guard.sh
do
    if grep -F "$removed" Makefile >/dev/null; then
        fail "root Makefile must drop removed suite $removed"
    else
        pass
    fi
done

# Daemon must keep smart-charge executor and not call removed SIM switch path.
assert_file_contains "$daemon" 'zte_execute_power_supply_mode'
assert_file_contains "$daemon" 'apply_smart_charge_policy'
if grep -q 'zte_execute_switch_sim' "$daemon"; then
    fail 'daemon must not invoke removed SIM switch executor'
else
    pass
fi
if grep -q 'zte_recovery_reconcile' "$daemon"; then
    fail 'daemon must not reconcile USB recovery coordinator'
else
    pass
fi

# Event types include smart_charge.
assert_file_contains \
    "$backend/files/usr/lib/zte-usb-wifi-manager/event-log.sh" \
    'smart_charge'

# Action queue only admits power mode switches.
assert_file_contains \
    "$backend/files/usr/lib/zte-usb-wifi-manager/actions.sh" \
    'set_power_supply_mode'
if grep -E 'switch_sim\|set_apn\|set_wifi\|send_sms' \
    "$backend/files/usr/lib/zte-usb-wifi-manager/actions.sh" >/dev/null; then
    # The valid-type case may only list set_power_supply_mode.
    if grep -A5 'zte_action_type_valid' \
        "$backend/files/usr/lib/zte-usb-wifi-manager/actions.sh" |
        grep -E 'switch_sim|set_apn|set_wifi|send_sms' >/dev/null; then
        fail 'action type allowlist must not include removed product actions'
    else
        pass
    fi
else
    pass
fi

finish
