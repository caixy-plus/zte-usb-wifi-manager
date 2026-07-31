SHELL := /bin/sh

.PHONY: test lint check

test:
	@set -e; \
	for test_file in \
		tests/test_validation.sh \
		tests/test_policy.sh \
		tests/test_schedule.sh \
		tests/test_json.sh \
		tests/test_http.sh \
		tests/test_credentials.sh \
		tests/test_session.sh \
		tests/test_adapter.sh \
		tests/test_u25s_simulator.sh \
		tests/test_actions.sh \
		tests/test_action_executor.sh \
		tests/test_daemon_actions.sh \
		tests/test_power_adapter.sh \
		tests/test_event_log.sh \
		tests/test_recovery_inhibit.sh \
		tests/test_recovery_guard.sh \
		tests/test_runtime_stability.sh \
		tests/test_rpcd.sh \
		tests/test_snapshot.sh \
		tests/test_netifd.sh \
		tests/test_structure.sh \
		tests/test_sensitive_data.sh \
		tests/test_packaging.sh \
		tests/test_ci.sh; do \
		"$$test_file"; \
	done
	@node tests/test_luci.js
	@set -e; \
	find package scripts tests -type f \( -name '*.sh' -o -perm -u+x \) -print | \
	while IFS= read -r shell_file; do \
		sh -n "$$shell_file"; \
	done
	@node -e "const fs=require('fs'); for (const f of process.argv.slice(1)) JSON.parse(fs.readFileSync(f,'utf8'));" \
		luci-app-zte-usb-wifi-manager/root/usr/share/luci/menu.d/luci-app-zte-usb-wifi-manager.json \
		luci-app-zte-usb-wifi-manager/root/usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json
	@tests/scan_sensitive_data.sh

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo 'shellcheck is required for lint'; exit 1; }
	@set -e; \
	find package scripts tests -type f \( -name '*.sh' -o -perm -u+x \) -print | \
	while IFS= read -r shell_file; do \
		shellcheck -x -e SC1091 "$$shell_file"; \
	done

check: test lint
