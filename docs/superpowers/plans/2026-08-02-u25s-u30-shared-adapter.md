# U25S/U30 Pro Shared Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver three verified stages of a shared U25S/U30 Pro OpenWrt console: U30 read support, calibrated semantic writes with readback, and packaged/stable deployment.

**Architecture:** Keep the existing goform normalization, semantic action queue, rpcd and LuCI layers. Add an explicit device profile selected from USB identity, make the HTTP/session origin profile-driven, and isolate only proven model differences in profile metadata or action mappings. Production writes remain independently gated until their exact U30 request and readback are proven.

**Tech Stack:** POSIX `ash`, curl, jshn/jsonfilter, procd, rpcd/ubus, LuCI JavaScript, Python simulator, Node test harness, OpenWrt 24.10/25.12 SDK and QEMU.

---

## File map

- Create `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/device-profile.sh`: whitelist USB identity and expose adapter, scheme, TLS, login and driver metadata.
- Modify `http.sh`: validate HTTP/HTTPS origin and apply profile-scoped TLS behavior.
- Modify `session.sh`: build LD/login URLs from the selected origin.
- Modify `adapter-zte-u25s*.sh`: consume profile identity/origin while retaining shared goform mappings.
- Modify `zte-usb-wifi-managerd`: select the profile before polling and publish actual model/adapter diagnostics.
- Modify rpcd metadata and LuCI view: report actual profile and capability state.
- Extend `tests/u25s_simulator.py` with separate U25S and U30 profiles; keep one simulator because the API family is shared.
- Add `tests/test_device_profile.sh` and extend HTTP/session/adapter/daemon/LuCI/packaging suites.
- Add sanitized U30 fixtures under `tests/fixtures/u30/` only after sensitive-field filtering.

### Task 1: Device profile contract

**Files:**
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/device-profile.sh`
- Create: `tests/test_device_profile.sh`
- Modify: `Makefile`
- Modify: `tests/test_structure.sh`

- [ ] **Step 1: Write failing profile tests**

Test exact U30 identity `19d2:1354`, U25 fallback only when explicitly configured, rejection of unknown devices, `https`/`http` scheme values, actual model names, driver names, and no heuristic substring matching.

```sh
ZTE_SYSFS_ROOT=$work/sys
assert_success zte_device_profile_select 19d2 1354 'U30 Pro'
assert_eq zte_u30 "$(zte_device_profile_id)"
assert_eq https "$(zte_device_profile_scheme)"
assert_eq kmod-usb-net-cdc-ncm "$(zte_device_profile_driver)"
assert_failure zte_device_profile_select 19d2 ffff 'Unknown'
```

- [ ] **Step 2: Run RED**

Run `./tests/test_device_profile.sh`; expect failure because `device-profile.sh` does not exist.

- [ ] **Step 3: Implement the minimal profile API**

Implement explicit `case "$vendor:$product"` selection and read-only getters. Do not mutate capability flags in this library.

- [ ] **Step 4: Run GREEN and register the suite**

Run `./tests/test_device_profile.sh && ./tests/test_structure.sh`; then add the suite to `make test` and confirm both pass.

- [ ] **Step 5: Commit**

Commit `feat: add explicit ZTE device profiles`.

### Task 2: Profile-driven HTTP and session origin

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/session.sh`
- Modify: `tests/test_http.sh`
- Modify: `tests/test_session.sh`

- [ ] **Step 1: Write failing origin tests**

Cover HTTPS Referer, rejection of other schemes, U30 profile adding `--insecure` only when explicitly selected, interface binding, cookie permissions, and session LD/login URLs using the same origin.

```sh
assert_eq 'https://192.168.0.1/' \
    "$(zte_http_referer 'https://192.168.0.1/goform/x')"
assert_failure zte_http_origin_valid 'ftp://192.168.0.1'
```

- [ ] **Step 2: Run RED**

Run `./tests/test_http.sh && ./tests/test_session.sh`; expect the HTTPS assertions to fail against the HTTP-only implementation.

- [ ] **Step 3: Implement validated origins**

Use `ZTE_DEVICE_ORIGIN` such as `https://192.168.0.1`; derive Referer without accepting paths, credentials or query fragments. Append curl `--insecure` only when `ZTE_DEVICE_TLS_INSECURE=1` came from the whitelisted U30 profile.

- [ ] **Step 4: Run GREEN**

Run the two focused suites and `shellcheck` on both libraries.

- [ ] **Step 5: Commit**

Commit `feat: support profile-driven goform origins`.

### Task 3: U30 simulator and sanitized fixtures

**Files:**
- Modify: `tests/u25s_simulator.py`
- Modify: `tests/test_u25s_simulator.sh`
- Create: `tests/fixtures/u30/status.json`
- Create: `tests/fixtures/u30/config-contract.json`
- Modify: `tests/scan_sensitive_data.js`

- [ ] **Step 1: Write failing simulator profile tests**

Require `--profile u30`, HTTPS-style request assertions, `DEVICE_MODEL=U30Air`, U30 fields, HTTP rejection fixture, and shared goform routes.

- [ ] **Step 2: Run RED**

Run `./tests/test_u25s_simulator.sh`; expect unknown `--profile` or missing U30 fixture failures.

- [ ] **Step 3: Implement U30 simulator profile**

Keep shared handlers and choose fixture/capability data by profile. Fixtures must omit IMEI, IMSI, ICCID, MAC, telephone numbers, SMS bodies, cookies and credentials.

- [ ] **Step 4: Run GREEN and sensitive scan**

Run `./tests/test_u25s_simulator.sh && ./tests/test_sensitive_data.sh`.

- [ ] **Step 5: Commit**

Commit `test: model U30 goform behavior`.

### Task 4: Stage 1 daemon and adapter integration

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh`
- Modify: `package/zte-usb-wifi-manager/files/etc/config/zte-usb-wifi-manager`
- Modify: `tests/test_adapter.sh`
- Modify: `tests/test_daemon_actions.sh`
- Modify: `tests/test_snapshot.sh`

- [ ] **Step 1: Write failing U30 read tests**

Assert actual adapter/model/origin diagnostics, normalized modem/network/battery/Wi-Fi/client/traffic/SMS values, `unsupported_device`, `transport_not_supported`, and unchanged U25 behavior.

- [ ] **Step 2: Run RED**

Run the adapter, daemon and snapshot suites; expect hard-coded U25S identity or HTTP URL failures.

- [ ] **Step 3: Select profile before polling**

Source `device-profile.sh`, select from sysfs, export origin/TLS settings, and pass actual model metadata to snapshot composition. Preserve all write capability defaults at zero.

- [ ] **Step 4: Run GREEN**

Run focused suites, JSON parsing, `sh -n`, and shellcheck.

- [ ] **Step 5: Commit**

Commit `feat: read U30 status through shared adapter`.

### Task 5: Stage 1 LuCI, rpcd and package dependency

**Files:**
- Modify: `package/zte-usb-wifi-manager/Makefile`
- Modify: `package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi`
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`
- Modify: `tests/test_luci.js`
- Modify: `tests/test_rpcd.sh`
- Modify: `tests/test_packaging.sh`

- [ ] **Step 1: Write failing presentation and dependency tests**

Assert U30 model/transport rendering, profile-specific capabilities, CDC-NCM dependency, and that U25 does not require U30 identity to render.

- [ ] **Step 2: Run RED**

Run LuCI, rpcd and packaging suites; expect missing U30 data and dependency failures.

- [ ] **Step 3: Implement profile presentation**

Expose adapter/model/transport/tls verification via capabilities and snapshot diagnostics. Add `+kmod-usb-net-cdc-ncm` without removing existing compatibility.

- [ ] **Step 4: Run GREEN and browser verification**

Run focused suites. In the QEMU/install stage, open LuCI through Playwright, assert the visible model and error banner from a real rpcd response, and capture the DOM assertion in validation evidence.

- [ ] **Step 5: Commit**

Commit `feat: present U30 profile in LuCI`.

### Task 6: Stage 1 real read-only calibration

**Files:**
- Create: `docs/validation/2026-08-02-u30-read-calibration.md`
- Update: `tests/fixtures/u30/status.json`
- Modify only profile/normalization files proven necessary by the captured response.

- [ ] **Step 1: Add failing fixture assertions for each displayed field family**
- [ ] **Step 2: Run RED for missing or mismatched U30 fields**
- [ ] **Step 3: Perform one read-only batch request through Cudy/eth2, sanitize locally, and implement only proven enum overrides**
- [ ] **Step 4: Deploy a read-only candidate with every write gate zero and verify continuously fresh `state=ok` snapshots**
- [ ] **Step 5: Run `make check`, commit and push Stage 1**

Commit `feat: complete U30 read-only management`.

### Task 7: Discover and freeze U30 write contracts

**Files:**
- Create: `tests/fixtures/u30/write-contracts.json`
- Create: `docs/validation/2026-08-02-u30-write-contracts.md`
- Modify: `tests/test_adapter.sh`

- [ ] **Step 1: Add tests that require exact goform ID, reviewed keys and readback field for every semantic action**
- [ ] **Step 2: Run RED because U30 mappings are absent**
- [ ] **Step 3: Extract mappings from U30 `service.js` and page modules; record source function and exact parameters without executing writes**
- [ ] **Step 4: Store a sanitized machine-readable contract and pass the fixture tests**
- [ ] **Step 5: Commit**

Commit `docs: freeze U30 semantic write contracts`.

### Task 8: Stage 2 non-destructive writes

**Files:**
- Modify: `adapter-zte-u25s.sh`
- Modify: `adapter-zte-u25s-metadata.sh`
- Modify: `action-executor.sh`
- Modify: `tests/test_action_executor.sh`
- Modify: `tests/test_adapter.sh`
- Modify: `tests/u25s_simulator.py`

- [ ] **Step 1: Write failing tests for APN, connection mode, Wi-Fi and traffic-plan mapping/readback**
- [ ] **Step 2: Run RED**
- [ ] **Step 3: Implement exact profile mappings with one session-expiry retry and no retry after ambiguous write acceptance**
- [ ] **Step 4: Run simulator success/rejection/timeout/readback suites**
- [ ] **Step 5: Execute controlled real writes one family at a time, restore original values, and enable only proven static capabilities**
- [ ] **Step 6: Commit**

Commit `feat: execute calibrated U30 settings`.

### Task 9: Stage 2 SMS and disruptive actions

**Files:**
- Modify the same adapter/executor files as Task 8.
- Modify: `tests/test_rpcd.sh`
- Modify: `tests/test_luci.js`
- Modify: `tests/test_sim_calibration.sh`

- [ ] **Step 1: Write failing tests for SMS send/delete/read, SIM switching, reboot and shutdown mappings plus independent confirmation**
- [ ] **Step 2: Run RED**
- [ ] **Step 3: Implement SMS mappings and safe readback first**
- [ ] **Step 4: Validate SIM switch on available slots with PPP recovery and no duplicate execution**
- [ ] **Step 5: Validate reboot reconnect/readback; validate shutdown only when an explicit recovery path exists**
- [ ] **Step 6: Keep any unexecuted dangerous capability zero, run full Stage 2 tests, commit and push**

Commit `feat: complete calibrated U30 device actions`.

### Task 10: Stage 3 packaging and upgrade lifecycle

**Files:**
- Modify backend and LuCI `Makefile` release numbers.
- Modify `.github/workflows/packages.yml`
- Modify `tests/test_packaging.sh`
- Create SDK/QEMU validation documents under `docs/validation/`.

- [ ] **Step 1: Update failing release/manifest assertions to the next backend and LuCI revisions**
- [ ] **Step 2: Run RED**
- [ ] **Step 3: Bump package releases and update release notes for U25S/U30, HTTPS and CDC-NCM**
- [ ] **Step 4: Run `make check`, push, trigger GitHub dual-SDK builds, and verify checksums**
- [ ] **Step 5: Install APK/IPK in fresh isolated QEMU overlays; verify procd/rpcd/ubus/LuCI/ACL/config retention/uninstall**
- [ ] **Step 6: Commit validation evidence**

Commit `docs: validate U30 package lifecycle`.

### Task 11: Cudy deployment and recovery validation

**Files:**
- Create: `docs/validation/2026-08-02-u30-cudy-deployment.md`
- Modify code only for reproduced failures, always starting with a failing regression test.

- [ ] **Step 1: Back up package list and plugin UCI; confirm USB primary metric 10 and wireless backup metric 20**
- [ ] **Step 2: Install the candidate, keep all write feature flags zero, and verify read-only status**
- [ ] **Step 3: Test daemon restart, router reboot, U30 reboot and USB re-enumeration**
- [ ] **Step 4: Enable only previously calibrated write flags and rerun their readback checks**
- [ ] **Step 5: Verify OpenClash, LAN, firewall and wireless backup are unchanged**
- [ ] **Step 6: Record sanitized evidence and commit**

Commit `docs: validate U30 on Cudy`.

### Task 12: Stability, audit and release readiness

**Files:**
- Modify: `tests/test_runtime_stability.sh`
- Modify: `tests/test_soak_validation.js`
- Update: `docs/validation/first-release-capability-matrix.md`
- Create: `docs/validation/2026-08-05-u30-72h.md`
- Update: `README.md`

- [ ] **Step 1: Add failing soak assertions for profile identity, HTTPS errors, re-enumeration and per-action result bounds**
- [ ] **Step 2: Run accelerated RED/GREEN stability tests**
- [ ] **Step 3: Run the real 72-hour collector without high-frequency flash writes**
- [ ] **Step 4: Audit RSS, FDs, log size, snapshot freshness, action limits, reconnects and route continuity**
- [ ] **Step 5: Freeze only evidence-backed capabilities; run secret scan, `make check`, code review and package verification**
- [ ] **Step 6: Commit and push all evidence; mark the goal complete only if every three-stage gate is proven**

Commit `release: complete U25S and U30 console validation`.
