# Credential Refresh and Clear Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make newly saved U25S credentials take effect on the next daemon poll and let administrators securely remove the local credential from LuCI.

**Architecture:** The credential library exposes a non-secret file revision and a guarded idempotent clear operation. The daemon compares revisions before each poll; a change clears only the session cookie, private-auth cooldown and SMS refresh timer. rpcd adds a parameterless local clear method, and LuCI requires explicit confirmation before invoking it.

**Tech Stack:** POSIX Shell, OpenWrt `stat`, rpcd/ubus, LuCI JavaScript, Node.js tests, shellcheck.

---

### Task 1: Secure credential revision and removal

**Files:**
- Modify: `tests/test_credentials.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/credentials.sh`

- [x] Add failing tests for `zte_credential_revision` on absent and replaced files, and `zte_clear_password` for an absent file, a valid mode-0600 file, a symlink, insecure permissions and a non-regular path.
- [x] Run `./tests/test_credentials.sh` and verify RED for missing functions.
- [x] Implement revision as device/inode/mtime/size metadata only; never hash or print the password. Implement idempotent clear after the same path, owner and mode checks used by reads.
- [x] Run `./tests/test_credentials.sh` and verify GREEN.
- [x] Commit as `feat: manage credential revisions safely`.

### Task 2: Reset private authentication cooldown on change

**Files:**
- Modify: `tests/test_structure.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`

- [x] Add a failing extracted-function behavior test proving an unchanged revision preserves cooldown, while a changed revision sets `private_auth_retry_after=0`, `next_sms_poll_at=0`, removes the cookie jar and stores the new revision.
- [x] Run `./tests/test_structure.sh` and verify RED.
- [x] Add `refresh_credential_revision` and call it before reading credentials in `poll_once`; initialize the baseline revision once before the daemon loop.
- [x] Run structure, daemon and session suites and verify GREEN.
- [x] Commit as `fix: apply changed U25S credentials promptly`.

### Task 3: Add the clear-credentials RPC and LuCI control

**Files:**
- Modify: `tests/test_rpcd.sh`
- Modify: `tests/test_luci.js`
- Modify: `package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi`
- Modify: `luci-app-zte-usb-wifi-manager/root/usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json`
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`

- [x] Add failing tests for a parameterless `clear_credentials` RPC, exact write ACL, non-echoing success/failure responses, confirmation-gated LuCI button and configured-state refresh.
- [x] Run rpcd and LuCI suites and verify RED.
- [x] Implement the local clear method and the confirmed UI action. Do not restart services, contact the device or expose the old password.
- [x] Run rpcd, LuCI, ACL and sensitive-data suites and verify GREEN.
- [x] Commit as `feat: clear saved U25S credentials`.

### Task 4: Package, document and verify

**Files:**
- Modify: `README.md`
- Modify: `package/zte-usb-wifi-manager/Makefile`
- Modify: `luci-app-zte-usb-wifi-manager/Makefile`
- Modify: `tests/test_packaging.sh`
- Modify: `tests/test_structure.sh`
- Modify: this plan

- [x] Add failing documentation and release assertions for backend r19 / LuCI r8.
- [x] Update package releases and explain immediate retry plus local credential removal.
- [x] Run `make check`, secret scan and `git diff --check`; audit that all device write capabilities remain false.
- [ ] Commit, push, build with both official SDKs, and validate both packages in isolated QEMU.
