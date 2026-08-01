# U25S Console Product Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove seamless battery-cycling behavior and reposition the shipped package and LuCI page as a U25S device-console integration without regressing status polling, action gating, packaging, or legacy power restoration.

**Architecture:** The daemon continues to read battery telemetry and may restore a legacy USB-off transition to ON during startup or shutdown, but its polling loop never computes or executes a battery-driven power action. LuCI adopts the eight-tab device-console information architecture and presents battery information as device telemetry; disruptive USB recovery remains diagnostics-only and unavailable until separately designed and calibrated.

**Tech Stack:** POSIX Shell for OpenWrt ash, rpcd/ubus, LuCI JavaScript, Node.js assertion tests, Make, shellcheck.

---

### Task 1: Lock the new product boundary with failing tests

**Files:**
- Modify: `tests/test_structure.sh`
- Modify: `tests/test_luci.js`

- [x] **Step 1: Add structural assertions for the daemon and default UCI contract**

Assert that the default config contains no `policy` or `work` section, and that
the daemon polling function contains neither `zte_policy_decide` nor
`apply_policy_action`:

```sh
if grep -Eq "^config (battery 'policy'|schedule 'work')$" "$config"; then
    fail 'default config must not expose retired battery automation'
else
    pass
fi
poll_once_source=$(sed -n '/^poll_once() {$/,/^}$/p' "$daemon")
case $poll_once_source in
    *zte_policy_decide*|*apply_policy_action*)
        fail 'polling must not execute battery-driven USB power actions' ;;
    *) pass ;;
esac
```

- [x] **Step 2: Add LuCI information-architecture assertions**

Render the page and assert that tabs `battery` and `schedule` do not exist,
that `clients` does exist, that the overview says `电池状态`, and that the
source contains no `立即充满` or `充电日程` control.

- [x] **Step 3: Run the focused tests and verify RED**

Run:

```sh
./tests/test_structure.sh
node tests/test_luci.js
```

Expected: both suites fail because the legacy UCI sections, daemon policy call,
and old tabs are still present.

- [x] **Step 4: Commit the failing contract tests**

```sh
git add tests/test_structure.sh tests/test_luci.js
git commit -m "test: define U25S console product boundary"
```

### Task 2: Disable battery-driven USB actions in production

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/etc/config/zte-usb-wifi-manager`
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/snapshot.sh`
- Modify: `tests/test_snapshot.sh`

- [x] **Step 1: Remove battery-policy and schedule defaults**

Delete the `config battery 'policy'` and `config schedule 'work'` blocks. Keep
the `usb` block disabled for safe legacy restore and future explicit recovery.

- [x] **Step 2: Make the daemon poll path telemetry-only**

Remove policy/schedule configuration loading and validation. In `poll_once`, do
not call `calculate_policy`; compose the snapshot with a stable retired marker:

```sh
policy_state=retired
power_action=none
collect_power_snapshot
```

Startup and shutdown retain `early_safety_restore` and `restore_power_on` so an
upgrade cannot strand a device in a legacy OFF transition. No normal polling
path may call `zte_power_apply`.

- [x] **Step 3: Constrain snapshot semantics**

Allow `policy.state=retired` only as backward-compatible status metadata. Add a
snapshot test proving battery telemetry is retained while the policy marker is
retired and the requested action is `none`.

- [x] **Step 4: Run focused backend tests and verify GREEN**

Run:

```sh
./tests/test_snapshot.sh
./tests/test_structure.sh
./tests/test_daemon_actions.sh
```

Expected: all suites pass, and the structural test proves polling cannot invoke
the retired policy.

- [x] **Step 5: Commit the backend reset**

```sh
git add package/zte-usb-wifi-manager/files/etc/config/zte-usb-wifi-manager \
  package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd \
  package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/snapshot.sh \
  tests/test_snapshot.sh
git commit -m "refactor: retire automatic USB battery cycling"
```

### Task 3: Replace charging UI with device-console navigation

**Files:**
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`
- Modify: `tests/test_luci.js`

- [x] **Step 1: Change the tab set**

Use exactly these tab identifiers:

```js
overview, network, wifi, clients, traffic, sms, device, diagnostics, logs
```

`logs` remains separate because it is an existing bounded module. Remove
`battery` and `schedule`; battery fields move into Overview and Device.

- [x] **Step 2: Replace policy presentation**

Remove `powerExecutionLabel()`, `renderBattery()` and `renderSchedule()` from
normal UI rendering. Overview renders `电池状态` from the device snapshot.
Device renders battery presence, percent, charging state and temperature.
Diagnostics may show read-only USB/recovery state with the warning
`USB 断电会中断数据连接，仅用于故障恢复` and must render no recovery button.

- [x] **Step 3: Add connected-device placeholder with precise status**

Until verified fixtures exist, the `clients` tab renders:

```text
尚未获取经过实机验证的 U25S 客户端数据
```

The Wi-Fi and traffic placeholders use the same precise calibration language,
not a generic empty-state message.

- [x] **Step 4: Run LuCI tests and verify GREEN**

Run:

```sh
node tests/test_luci.js
```

Expected: all LuCI assertions pass.

- [x] **Step 5: Commit the UI reset**

```sh
git add luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js tests/test_luci.js
git commit -m "feat: reposition LuCI as U25S device console"
```

### Task 4: Align package and public documentation

**Files:**
- Modify: `README.md`
- Modify: `package/zte-usb-wifi-manager/Makefile`
- Modify: `luci-app-zte-usb-wifi-manager/Makefile`
- Modify: `docs/design/zte-usb-wifi-manager-design.md`
- Modify: `tests/test_structure.sh`

- [x] **Step 1: Update package metadata and tests**

Bump backend release from 15 to 16 and LuCI release from 4 to 5. Change the
backend package description to `U25S device-console integration and safely
gated device actions for OpenWrt.` Update exact release assertions.

- [x] **Step 2: Rewrite README positioning and current-state summary**

Lead with U25S console integration. State prominently that seamless charging
control is not supported because removing USB VBUS interrupts USB data. Describe
USB power only as a future, disruptive recovery action. Preserve verified build,
installation and compatibility evidence without claiming new live writes.

- [x] **Step 3: Mark the old design as superseded where it conflicts**

Add a notice at the top of the old design pointing to
`docs/superpowers/specs/2026-08-01-u25s-console-integration-design.md`. Replace
the old phase-3 automatic battery section with telemetry and explicit recovery.

- [x] **Step 4: Run documentation and structure checks**

Run:

```sh
./tests/test_structure.sh
./tests/test_sensitive_data.sh
git diff --check
```

Expected: all pass and no credential/device identifiers are introduced.

- [x] **Step 5: Commit documentation and release metadata**

```sh
git add README.md package/zte-usb-wifi-manager/Makefile \
  luci-app-zte-usb-wifi-manager/Makefile \
  docs/design/zte-usb-wifi-manager-design.md tests/test_structure.sh
git commit -m "docs: publish U25S console product direction"
```

### Task 5: Verify and publish the product-reset baseline

**Files:**
- Modify only if verification exposes a regression.

- [x] **Step 1: Run the complete local gate**

Run:

```sh
make check
```

Expected: every Shell, Node, JSON, packaging and secret-scan suite passes and
shellcheck reports no findings.

- [x] **Step 2: Inspect the exact committed diff**

Run:

```sh
git status --short
git log --oneline -5
git diff origin/codex/phase1-phase2...HEAD --check
```

Expected: no uncommitted files and no whitespace errors.

- [x] **Step 3: Push the branch**

```sh
git push origin codex/phase1-phase2
```

Expected: the remote branch advances to the product-reset commits.

