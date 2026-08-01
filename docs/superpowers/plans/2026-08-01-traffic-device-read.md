# Traffic and Device Read Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add verified read-only U25S traffic counters, traffic-plan state, and firmware version to the normalized snapshot and LuCI console.

**Architecture:** Extend the existing single safe bulk-read request with exact fields observed in the target firmware service layer and confirmed by a schema-only live probe. Normalize values inside the U25S adapter, treating firmware-defined empty counters as zero while preserving unknown configuration values as null; rpcd continues serving only the daemon snapshot.

**Tech Stack:** POSIX Shell, ZTE goform GET API, LuCI JavaScript, Python loopback simulator, Node/Shell tests.

---

### Task 1: Add failing adapter and LuCI tests

**Files:**
- Modify: `tests/fixtures/u25s/read_ok.json`
- Modify: `tests/test_adapter.sh`
- Modify: `tests/test_luci.js`

- [x] **Step 1: Extend the synthetic successful fixture**

Add non-identifying fixture values for firmware version, current and monthly
traffic, plan switch/unit/limit/alert, auto-clear day and disconnect behavior.

- [x] **Step 2: Assert the normalized contract**

Require `device.firmware` plus `device.traffic` with nested `realtime`,
`current`, `monthly`, and `plan` objects. Empty firmware counters normalize to
integer zero; configured numeric strings remain integers.

- [x] **Step 3: Assert LuCI traffic and device rendering**

Require the traffic tab to render rates, bytes, durations and plan state from
the normalized snapshot, and the device tab to render firmware version.

- [x] **Step 4: Run focused tests and verify RED**

Run `./tests/test_adapter.sh && node tests/test_luci.js`. Expected: adapter
normalization assertions fail because the fields are not implemented.

### Task 2: Implement adapter normalization and simulator support

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh`
- Modify: `tests/u25s_simulator.py`
- Modify: `tests/fixtures/u25s/read_missing_fields.json`
- Modify: `tests/test_adapter.sh`

- [x] **Step 1: Add exact observed fields to `ZTE_READ_FIELDS` and simulator allowlist**

Use the field names captured in the target `service.js`; do not use wildcards
or request identifiers such as ICCID/IMEI.

- [x] **Step 2: Add strict numeric helpers**

Create an adapter helper that accepts an absent field as JSON null, an empty
counter as zero only when requested by the caller, and otherwise accepts only
unsigned decimal strings. Invalid counter syntax rejects the snapshot.

- [x] **Step 3: Emit the normalized traffic and firmware objects**

Keep all JSON assembly inside the adapter and escape firmware text. Preserve
missing configuration fields as null rather than inventing defaults.

- [x] **Step 4: Run adapter and simulator tests and verify GREEN**

Run `./tests/test_adapter.sh && ./tests/test_u25s_simulator.sh` and expect both
suites to pass.

### Task 3: Render the new data in LuCI

**Files:**
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`
- Modify: `tests/test_luci.js`

- [x] **Step 1: Add byte, rate, duration and enabled-state presentation helpers**

Helpers must preserve null as an em dash and distinguish zero from unknown.
Use bounded, deterministic unit formatting without browser locale dependence.

- [x] **Step 2: Replace the traffic placeholder**

Render current upload/download rate, current sent/received bytes and duration,
monthly sent/received bytes and duration, and plan enabled/unit/limit/alert/
clear-day/disconnect state.

- [x] **Step 3: Add firmware to Device and run LuCI tests**

Run `node tests/test_luci.js` and expect all assertions to pass.

### Task 4: Record evidence, verify, commit and push

**Files:**
- Create: `docs/validation/2026-08-01-traffic-device-read.md`
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-08-01-traffic-device-read.md`

- [x] **Step 1: Record schema-only evidence**

Document field names, response types, empty-value behavior and the fact that no
raw SSID, client identifier, firmware value or credential was captured.

- [x] **Step 2: Update current status and complete the checklist**

State that traffic and firmware reads are implemented from verified contracts;
do not claim a write capability.

- [x] **Step 3: Run `make check` and inspect the exit code**

Expected: every suite and shellcheck exits zero.

- [x] **Step 4: Commit and push**

Use focused commits for tests, adapter, LuCI, and documentation, then push
`codex/phase1-phase2`.

