# Framework Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the open-source OpenWrt package skeleton, tested policy core, rpcd contract, LuCI navigation shell, project documentation, and CI for the ZTE USB WiFi Manager.

**Architecture:** Keep device-specific HTTP details behind a ZTE adapter and expose normalized state through a small POSIX Shell core. A procd-managed daemon owns polling and policy decisions, rpcd exposes the cached state, and the LuCI JavaScript page consumes only rpcd methods. Device write operations remain capability-gated until verified on the U25S firmware.

**Tech Stack:** OpenWrt APK packages, POSIX Shell, procd, UCI, ubus/rpcd, LuCI JavaScript views, GitHub Actions.

---

## File map

- `package/zte-usb-wifi-manager/Makefile`: backend OpenWrt package metadata.
- `package/zte-usb-wifi-manager/files/etc/config/zte-usb-wifi-manager`: safe default UCI configuration.
- `package/zte-usb-wifi-manager/files/etc/init.d/zte-usb-wifi-manager`: procd service definition.
- `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/validation.sh`: configuration validation.
- `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/policy.sh`: deterministic battery policy.
- `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh`: read-only adapter capability boundary.
- `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`: polling daemon shell.
- `package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi`: rpcd method contract.
- `luci-app-zte-usb-wifi-manager/Makefile`: LuCI package metadata.
- `luci-app-zte-usb-wifi-manager/root/usr/share/luci/menu.d/luci-app-zte-usb-wifi-manager.json`: single LuCI menu entry.
- `luci-app-zte-usb-wifi-manager/root/usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json`: least-privilege ACL.
- `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`: tabbed page shell.
- `tests/test_validation.sh`: validation behavior.
- `tests/test_policy.sh`: state-machine behavior.
- `tests/test_structure.sh`: package and LuCI contract checks.

### Task 1: Validation core

**Files:**
- Create: `tests/test_validation.sh`
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/validation.sh`

- [x] **Step 1: Write the failing validation test**

```sh
#!/bin/sh
set -eu
. ./tests/testlib.sh
. ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/validation.sh

assert_success zte_validate_thresholds 70 100
assert_failure zte_validate_thresholds 100 70
assert_failure zte_validate_thresholds text 100
assert_success zte_validate_host 192.168.0.1
assert_failure zte_validate_host '192.168.0.1;reboot'
finish
```

- [x] **Step 2: Verify RED**

Run: `./tests/test_validation.sh`  
Expected: failure because `validation.sh` does not exist.

- [x] **Step 3: Implement minimal validation**

```sh
zte_is_uint() {
    case ${1-} in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

zte_validate_thresholds() {
    zte_is_uint "${1-}" && zte_is_uint "${2-}" &&
        [ "$1" -ge 30 ] && [ "$1" -lt "$2" ] && [ "$2" -le 100 ]
}

zte_validate_host() {
    case ${1-} in ''|*[!A-Za-z0-9.:-]*) return 1 ;; *) return 0 ;; esac
}
```

- [x] **Step 4: Verify GREEN**

Run: `./tests/test_validation.sh`  
Expected: `PASS test_validation`.

### Task 2: Battery policy core

**Files:**
- Create: `tests/test_policy.sh`
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/policy.sh`

- [x] **Step 1: Write the failing state table**

```sh
assert_eq 'FAIL_SAFE_ON:ON' "$(zte_policy_decide 1 1 0 0 82 70 100 ON)"
assert_eq 'MANUAL_FULL:ON' "$(zte_policy_decide 1 0 1 0 82 70 100 OFF)"
assert_eq 'PRE_DEPARTURE:ON' "$(zte_policy_decide 1 0 0 1 82 70 100 OFF)"
assert_eq 'MAINTAIN_CHARGING:ON' "$(zte_policy_decide 1 0 0 0 70 70 100 OFF)"
assert_eq 'MAINTAIN_BATTERY:OFF' "$(zte_policy_decide 1 0 0 0 100 70 100 ON)"
assert_eq 'MAINTAIN_CHARGING:ON' "$(zte_policy_decide 1 0 0 0 82 70 100 ON)"
assert_eq 'MAINTAIN_BATTERY:OFF' "$(zte_policy_decide 1 0 0 0 82 70 100 OFF)"
assert_eq 'DISABLED:KEEP' "$(zte_policy_decide 0 0 0 0 82 70 100 ON)"
```

- [x] **Step 2: Verify RED**

Run: `./tests/test_policy.sh`  
Expected: failure because `policy.sh` does not exist.

- [x] **Step 3: Implement the deterministic priority order**

Implement `zte_policy_decide enabled failed manual_full pre_departure battery low high current_power` with this priority: disabled, failure, manual full, pre-departure, low boundary, high boundary, hysteresis.

- [x] **Step 4: Verify GREEN**

Run: `./tests/test_policy.sh`  
Expected: `PASS test_policy`.

### Task 3: OpenWrt backend package shell

**Files:**
- Create: backend package files listed in the file map.
- Create: `tests/test_structure.sh`

- [x] **Step 1: Write failing structure assertions**

Assert the package Makefile exists, the init script declares `USE_PROCD=1`, rpcd lists `status`, UCI defaults are read-only safe, and the adapter declares manual SIM switching unsupported until calibrated.

- [x] **Step 2: Verify RED**

Run: `./tests/test_structure.sh`  
Expected: one or more missing-file failures.

- [x] **Step 3: Add minimal backend package**

The daemon sources `validation.sh` and `policy.sh`, writes a normalized JSON snapshot under `/var/run/zte-usb-wifi-manager/status.json`, and never executes a device write operation in the framework release.

- [x] **Step 4: Verify GREEN**

Run: `./tests/test_structure.sh`  
Expected: `PASS test_structure`.

### Task 4: LuCI package shell

**Files:**
- Create: LuCI package files listed in the file map.

- [x] **Step 1: Extend the failing structure test**

Assert there is exactly one menu entry, it points to `zte-usb-wifi-manager/index`, the ACL grants only the required UCI and ubus reads, and the page defines the ten approved tabs.

- [x] **Step 2: Verify RED**

Run: `./tests/test_structure.sh`  
Expected: failure for missing LuCI package files.

- [x] **Step 3: Implement the page shell**

Create a LuCI `view.extend()` module that calls `zte_usb_wifi.status`, renders a status header, and exposes ten tabs. Write actions render disabled with the explanation “设备写接口尚未完成实机校准”.

- [x] **Step 4: Verify GREEN**

Run: `./tests/test_structure.sh`  
Expected: `PASS test_structure`.

### Task 5: Open-source project and CI

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `CODE_OF_CONDUCT.md`
- Create: `AGENTS.md`
- Create: `.gitignore`
- Create: `.github/workflows/ci.yml`
- Create: `Makefile`

- [x] **Step 1: Add root verification entry point**

`make test` must run all POSIX Shell tests and `sh -n` over all shipped shell files.

- [x] **Step 2: Add CI**

GitHub Actions runs on Ubuntu, installs ShellCheck, executes `make test`, and scans tracked files for the known local device password pattern without printing secrets.

- [x] **Step 3: Add open-source documentation**

README must state current scope, unsupported writes, target hardware, repository layout, test command, and link to both design artifacts. MIT license and contribution/security policies must be complete.

- [x] **Step 4: Final verification**

Run: `make test`  
Expected: all three test suites pass and all shell files pass syntax checks.

- [ ] **Step 5: Publish**

Initialize Git history, create `caixy-plus/zte-usb-wifi-manager` as a public GitHub repository, push `main`, and verify the remote visibility and default branch.
