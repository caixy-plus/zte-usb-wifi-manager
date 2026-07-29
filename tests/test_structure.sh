#!/bin/sh
set -eu

TEST_NAME=test_structure
. ./tests/testlib.sh

backend=package/zte-usb-wifi-manager
luci=luci-app-zte-usb-wifi-manager

assert_file_contains "$backend/Makefile" '^PKG_NAME:=zte-usb-wifi-manager$'
assert_file_contains "$backend/files/etc/config/zte-usb-wifi-manager" "option write_enabled '0'"
assert_file_contains "$backend/files/etc/init.d/zte-usb-wifi-manager" '^USE_PROCD=1$'
assert_file_contains "$backend/files/usr/libexec/rpcd/zte_usb_wifi" '"status"'
assert_file_contains "$backend/files/usr/libexec/rpcd/zte_usb_wifi" '"capabilities"'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh" '^ZTE_CAP_SIM_SWITCH=0$'

menu="$luci/root/usr/share/luci/menu.d/luci-app-zte-usb-wifi-manager.json"
assert_file_contains "$menu" '"path": "zte-usb-wifi-manager/index"'
assert_file_contains "$menu" '"title": "中兴随身 WiFi"'

view="$luci/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js"
for tab in overview network wifi traffic sms battery schedule device diagnostics logs; do
    assert_file_contains "$view" "id: '$tab'"
done
assert_file_contains "$view" '设备写接口尚未完成实机校准'

if grep -R -q '双卡智能切换\\|SET_DUAL_SIM_SMART_SWITCH' \
    "$backend" "$luci" 2>/dev/null; then
    fail 'unsupported smart SIM switching must not be shipped'
else
    pass
fi

assert_file_contains docs/design/zte-usb-wifi-manager-ui.html '<title>中兴随身 WiFi 管理</title>'
assert_file_contains docs/design/zte-usb-wifi-manager-design.md '^# 中兴随身 WiFi 管理工具详细设计文档$'

daemon="$backend/files/usr/sbin/zte-usb-wifi-managerd"
for library in json.sh session.sh snapshot.sh netifd-adapter.sh; do
    assert_file_contains "$daemon" "$library"
done
for function in zte_adapter_fetch zte_failures_next zte_snapshot_compose; do
    assert_file_contains "$daemon" "$function"
done
assert_file_contains "$daemon" 'init_state'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/session.sh" 'goformId=LOGIN'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh" 'multi_data=1'
assert_file_contains tests/fixtures/u25s/read_ok.json 'NR5G-SA'
assert_file_contains Makefile 'tests/test_session.sh'
assert_file_contains Makefile 'tests/test_adapter.sh'

finish
