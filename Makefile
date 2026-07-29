SHELL := /bin/sh

.PHONY: test lint check

test:
	@set -e; \
	for test_file in tests/test_validation.sh tests/test_policy.sh tests/test_structure.sh; do \
		"$$test_file"; \
	done
	@set -e; \
	find package tests -type f \( -name '*.sh' -o -perm -u+x \) -print | \
	while IFS= read -r shell_file; do \
		sh -n "$$shell_file"; \
	done
	@node -e "const fs=require('fs'); for (const f of process.argv.slice(1)) JSON.parse(fs.readFileSync(f,'utf8'));" \
		luci-app-zte-usb-wifi-manager/root/usr/share/luci/menu.d/luci-app-zte-usb-wifi-manager.json \
		luci-app-zte-usb-wifi-manager/root/usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json
	@! grep -R -q -E --exclude-dir=.git '[0-9]{8}qq' .

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo 'shellcheck is required for lint'; exit 1; }
	@find package tests -type f \( -name '*.sh' -o -perm -u+x \) -print | \
	while IFS= read -r shell_file; do \
		shellcheck -x -e SC1091 "$$shell_file"; \
	done

check: test lint
