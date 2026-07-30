# Review Findings Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify the external review report and fix every reproducible correctness, security, observability, and test-quality defect without enabling device writes.

**Architecture:** Preserve the one-way daemon → snapshot → rpcd → LuCI flow. Make unknown USB power state explicit instead of inferring it from the U25S charging flag, isolate static adapter metadata from the HTTP/session stack, and exercise production entry points with behavior tests.

**Tech Stack:** POSIX Shell for OpenWrt `ash`, LuCI JavaScript, Node.js test harness, Make, ShellCheck.

---

### Task 1: Make credential and cookie permissions explicit

**Files:**
- Modify: `tests/test_session.sh`
- Modify: `tests/test_http.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/session.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh`

- [ ] **Step 1: Write failing tests**

Add assertions that credential mode is obtained through a portable `stat`
helper and that GET and POST cookie jars end with mode `600`, including after
curl returns a failure.

- [ ] **Step 2: Verify RED**

Run:

```sh
./tests/test_session.sh
./tests/test_http.sh
```

Expected: permission assertions fail because credentials use `ls -ld` and the
HTTP wrapper does not explicitly secure the jar.

- [ ] **Step 3: Implement the minimum behavior**

Add a GNU/BusyBox and BSD compatible mode helper:

```sh
zte_file_mode() {
    if _zte_mode=$(stat -c '%a' "$1" 2>/dev/null); then
        printf '%s\n' "$_zte_mode"
    else
        stat -f '%Lp' "$1" 2>/dev/null
    fi
}
```

Replace the `ls` permission check with `[ "$(zte_file_mode "$1")" = 600 ]`.
Wrap curl status capture so `chmod 600` is attempted without changing curl's
exit code.

- [ ] **Step 4: Verify GREEN**

Run both focused suites and expect all assertions to pass.

### Task 2: Correct route detection and remove misleading configuration

**Files:**
- Modify: `tests/test_netifd.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/netifd-adapter.sh`
- Modify: `package/zte-usb-wifi-manager/Makefile`
- Modify: `package/zte-usb-wifi-manager/files/etc/config/zte-usb-wifi-manager`

- [ ] **Step 1: Write failing route behavior tests**

Make the fake `ip` implementation record its arguments and cover:

```text
IPv4 default route on eth0.1
IPv6-only default route on eth0.1
no default route
```

The implementation must pass the device as its own argument, not interpolate
it into a regular expression.

- [ ] **Step 2: Verify RED**

Run `./tests/test_netifd.sh`. Expect the argument and IPv6 cases to fail.

- [ ] **Step 3: Implement exact route queries**

Query `ip route show default dev "$device"` and, if absent, query
`ip -6 route show default dev "$device"`. Declare the OpenWrt `ip-tiny`
runtime dependency. Remove the unused `fail_safe_power` option from the
Phase 1 default configuration because no power adapter exists yet.

- [ ] **Step 4: Verify GREEN**

Run `./tests/test_netifd.sh` and the JSON syntax checks.

### Task 3: Make policy monitoring honest and test atomic snapshots

**Files:**
- Modify: `tests/test_policy.sh`
- Modify: `tests/test_structure.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/policy.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`

- [ ] **Step 1: Write failing behavior tests**

Add tests proving that:

```text
an unknown current USB power state is accepted at the low/high boundaries
an unknown state cannot select a hysteresis branch
the daemon passes UNKNOWN rather than hard-coded ON
write_status creates mode 600, leaves no temporary file, and replaces old JSON
```

- [ ] **Step 2: Verify RED**

Run `./tests/test_policy.sh` and `./tests/test_structure.sh`. Expect the unknown
power and real `write_status` behavior cases to fail.

- [ ] **Step 3: Implement the minimum behavior**

Pass `UNKNOWN` from the read-only daemon. In `zte_policy_decide`, return the
boundary decisions without needing current power, but reject values other than
`ON` or `OFF` inside the hysteresis band. Keep the snapshot policy as
`unavailable/none` when the result is unknowable. Exercise the production
`write_status` function against a temporary status path.

- [ ] **Step 4: Verify GREEN**

Run both focused suites and expect all assertions to pass.

### Task 4: Test rpcd through its real command interface and narrow imports

**Files:**
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi`
- Create: `tests/test_rpcd.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write a failing rpcd suite**

Invoke the shipped script with `list`, `call status`, `call capabilities`, an
unknown method, an existing snapshot, and a missing snapshot. Validate every
response with `JSON.parse`.

- [ ] **Step 2: Verify RED**

Run `./tests/test_rpcd.sh`. Expect failure because the production script has no
testable path overrides and sources the full adapter stack.

- [ ] **Step 3: Isolate static metadata**

Move adapter constants plus `zte_adapter_capabilities_json()` and
`zte_adapter_framework_status_json()` into the metadata library. Source only
that file from rpcd. Add root-controlled environment overrides with production
defaults for the library directory and snapshot path so the actual entry point
can be tested without modifying installed paths.

- [ ] **Step 4: Verify GREEN**

Run `./tests/test_rpcd.sh` and `./tests/test_adapter.sh`.

### Task 5: Add LuCI polling, explicit failures, and stale-snapshot warnings

**Files:**
- Modify: `tests/test_luci.js`
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`

- [ ] **Step 1: Extend the Node harness first**

Inject controllable RPC promises and a fake poll service. Add assertions that:

```text
load preserves status and capability success/failure independently
render shows a backend error banner after either RPC failure
render registers one 30-second poll callback
the poll callback replaces the rendered status content
an old updated timestamp produces a stale warning
```

- [ ] **Step 2: Verify RED**

Run `node tests/test_luci.js`. Expect the new load, poll, error, and stale tests
to fail.

- [ ] **Step 3: Implement the minimum LuCI behavior**

Require LuCI's `poll` module. Convert each RPC result to
`{ ok, value }`, render explicit error/stale alerts, and use `poll.add()` to
replace only this view's status root every 30 seconds. Do not use a raw browser
timer or introduce write methods.

- [ ] **Step 4: Verify GREEN**

Run `node tests/test_luci.js` and expect all assertions to pass.

### Task 6: Close scanner bypass, quiet the negative CI test, and verify

**Files:**
- Modify: `tests/test_sensitive_data.sh`
- Modify: `tests/scan_sensitive_data.js`
- Modify: `tests/sensitive-data.allowlist`
- Modify: `tests/test_ci.sh`

- [ ] **Step 1: Write a failing scanner fixture**

Add a tracked comment containing a synthetic secret assignment and require a
sanitized `SECRET_ASSIGNMENT` finding for it.

- [ ] **Step 2: Verify RED**

Run `./tests/test_sensitive_data.sh`. Expect the comment fixture finding to be
missing.

- [ ] **Step 3: Remove the bypass and quiet expected stderr**

Apply the same secret and sensitive-field rules to comment lines, adding exact
allowlist entries only for intentional repository examples. Redirect the
expected failing `make lint` output inside `test_ci.sh`.

- [ ] **Step 4: Run focused and full verification**

Run:

```sh
./tests/test_sensitive_data.sh
./tests/test_ci.sh
make check
git diff --check
git status --short
```

Expected: all suites pass, ShellCheck is clean, there is no diff whitespace
error, and unrelated untracked media remains untouched.

- [ ] **Step 5: Review and publish**

Review the final diff against every verified report item, commit only project
changes, and push `main` after all verification succeeds.
