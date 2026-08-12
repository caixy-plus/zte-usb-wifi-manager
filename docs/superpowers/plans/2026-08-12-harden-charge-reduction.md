# U30 Smart-Charge Reduction Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the first release a genuinely U30-only smart-charge product with exact hardware identification, an allowlisted package payload, a consistent LuCI/backend status contract, and green local quality gates.

**Architecture:** Treat this as a clean first release with no upgrade migration. The daemon must derive the U30 profile only from the calibrated USB identity, rpcd must derive capabilities only from the daemon's cached identity, and the OpenWrt package must explicitly install only current runtime files. LuCI consumes the existing `status.policy` snapshot contract.

**Tech Stack:** POSIX Shell for OpenWrt/rpcd/daemon, OpenWrt package Makefiles, LuCI JavaScript, shell/Node regression tests.

---

### Task 1: Lock the U30 identity and capability contract

**Files:**
- Create: `tests/test_daemon_profile.sh`
- Modify: `Makefile`
- Modify: `tests/test_rpcd.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`
- Modify: `package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi`
- Modify: `package/zte-usb-wifi-manager/files/etc/config/zte-usb-wifi-manager`

- [x] Write a daemon-profile test that supplies exact U30 sysfs identity and verifies success, then verifies missing/mismatched identity fails for both `auto` and `zte_u30` configuration.
- [x] Extend rpcd tests so a missing/unsupported cache returns unavailable capabilities and only an exact cached `zte_u30` / `U30 Pro` identity can enable `set_power_supply_mode`.
- [x] Run the focused tests and confirm they fail because the daemon guesses U30 and rpcd defaults to U30.
- [x] Change profile selection to use `zte_device_profile_detect` and make the default configuration `adapter=auto`.
- [x] Make rpcd fail closed when the cache does not contain the exact U30 identity.
- [x] Run the focused tests and confirm they pass.

### Task 2: Make the release package an explicit smart-charge payload

**Files:**
- Modify: `tests/test_structure.sh`
- Modify: `tests/test_packaging.sh`
- Modify: `package/zte-usb-wifi-manager/Makefile`
- Modify: `package/zte-usb-wifi-manager/files/etc/init.d/zte-usb-wifi-manager`
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`

- [x] Add structural tests rejecting wildcard package copying, legacy calibration/recovery executables, the recovery coordinator service instance, and first-release migration hooks.
- [x] Run the structural and packaging tests and confirm the new assertions fail.
- [x] Replace the package copy-all rule with explicit install directories/files and remove the unused post-install migration hook.
- [x] Reduce the init script to the single manager instance.
- [x] Remove legacy USB power, private SMS/client, manual action-queue orchestration, and related dead variables/functions from the daemon while retaining the smart-charge write lock and executor.
- [x] Run structural, packaging, daemon smart-charge, rpcd, syntax, and lint checks until this task is green.

### Task 3: Align LuCI with the cached status schema

**Files:**
- Modify: `tests/test_luci.js`
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`

- [x] Add a LuCI test that opens the charging tab using a real `policy` snapshot and asserts the policy state is rendered.
- [x] Run the LuCI test and confirm it fails because the view reads `status.smart_charge`.
- [x] Render a localized label from `status.policy.state` and keep unknown states visible rather than blank.
- [x] Run the LuCI test and confirm it passes.

### Task 4: Restore release gates and verify the whole change

**Files:**
- Modify: `tests/test_packaging.sh`
- Modify: `README.md` only if current first-release facts need correction

- [x] Remove the stale historical README-tag assertion from packaging tests and replace it with assertions for the current r33/r14 first-release description.
- [x] Run `make test` and inspect the complete output and exit code.
- [x] Run `make lint` and inspect the complete output and exit code.
- [x] Run `git diff --check` and review the full diff against the four requirements.
- [x] Request an independent read-only code review and address any verified important findings.
