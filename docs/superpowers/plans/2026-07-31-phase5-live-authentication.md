# Phase 5 Live Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the installed plugin read the real U25S when its status API allows anonymous reads, and add a secure LuCI password entry for firmware that requires authenticated reads.

**Architecture:** The adapter probes the configured read endpoint first and only performs the verified ZTE login flow when the response lacks known fields. Credential persistence is isolated in a small library shared by the daemon and rpcd; rpcd never contacts the device. LuCI can save a password but never reads it back, stores it in browser persistence, or claims it was verified.

**Tech Stack:** POSIX Shell for OpenWrt `ash`, rpcd/ubus, LuCI JavaScript, dependency-light shell and Node.js tests.

---

### Task 1: Support optional authentication and real empty fields

**Files:**
- Modify: `tests/test_adapter.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh`

- [ ] Add failing tests proving an empty cookie and empty password can read a firmware endpoint that exposes known fields, an authentication-required response returns status 2 without a password, and an empty `sms_data_total` normalizes to `null`.
- [ ] Run `./tests/test_adapter.sh` and verify the new assertions fail for the missing behavior.
- [ ] Change `zte_adapter_fetch` to probe once before login, log in only after a valid JSON response without known fields, and return 2 when login is required but no password is available.
- [ ] Treat an empty `sms_data_total` as absent data while retaining strict rejection for malformed non-empty counters.
- [ ] Run `./tests/test_adapter.sh` and verify all assertions pass.
- [ ] Commit the adapter behavior and tests.

### Task 2: Add atomic root-only credential persistence

**Files:**
- Create: `tests/test_credentials.sh`
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/credentials.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/session.sh`
- Modify: `Makefile`

- [ ] Add failing tests for password validation, atomic writes, mode `0600`, owner checks, malformed paths, symlinks, and absence without leaking the password in test output.
- [ ] Run `./tests/test_credentials.sh` and verify it fails because the library does not exist.
- [ ] Move credential file helpers out of `session.sh` into `credentials.sh` and implement atomic `zte_write_password`.
- [ ] Add the suite to `make test`, update session test imports, and run both credential and session suites.
- [ ] Commit the credential library and tests.

### Task 3: Make the daemon distinguish optional and required credentials

**Files:**
- Modify: `tests/test_structure.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`

- [ ] Add failing daemon behavior assertions for successful anonymous polling, authentication-required polling without a password, and normal polling with a configured password.
- [ ] Run `./tests/test_structure.sh` and verify the new assertions fail for the expected reason.
- [ ] Load `credentials.sh`, make the password optional, and map adapter status 2 to `credentials_missing` while retaining normal backoff for transport or parsing failures.
- [ ] Run `./tests/test_structure.sh` and verify all assertions pass.
- [ ] Commit the daemon behavior and tests.

### Task 4: Expose password write-only RPC methods

**Files:**
- Modify: `tests/test_rpcd.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi`
- Modify: `luci-app-zte-usb-wifi-manager/root/usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json`

- [ ] Add failing rpcd assertions for `credential_status` and `set_credentials`, including invalid JSON, invalid passwords, secure output mode, and responses that never echo the password.
- [ ] Run `./tests/test_rpcd.sh` and verify the new assertions fail for missing methods.
- [ ] Source only `credentials.sh`, add a test-overridable credential path, implement the read-only status and write-only save methods, and update the ACL.
- [ ] Run rpcd and JSON validation tests.
- [ ] Commit the RPC and ACL changes.

### Task 5: Add the LuCI login entry

**Files:**
- Modify: `tests/test_luci.js`
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`

- [ ] Add failing UI tests for the credential RPC declarations, password input type, configured/unconfigured label, save action, secret clearing after submission, and absence of browser persistence APIs.
- [ ] Run `node tests/test_luci.js` and verify the new assertions fail for missing UI behavior.
- [ ] Add the write-only password form, load credential status independently, save through rpcd, and report “saved, pending device use” without claiming successful authentication.
- [ ] Run `node tests/test_luci.js` and verify all assertions pass.
- [ ] Commit the LuCI entry and tests.

### Task 6: Verify and deploy the live-read build

**Files:**
- Modify: `README.md`
- Modify: package release metadata as required by the build matrix
- Create: a dated validation record under `docs/validation/`

- [ ] Update documentation to explain optional U25S authentication and the write-only credential form.
- [ ] Run `make check`.
- [ ] Run a direct sanitized read against the connected U25S and confirm the normalized response is valid JSON without unique identifiers.
- [ ] Build the OpenWrt 25.12.5 APK and 24.10.7 IPK packages.
- [ ] Install the APK on the Cudy router through the authenticated LuCI session, then verify the daemon, ubus object, live device status, permissions, and UI.
- [ ] Record evidence without passwords, cookies, IMSI, IMEI, ICCID, phone numbers, SMS content, MAC addresses, or session tokens.
- [ ] Commit and push the verified phase.
