# U25S Capability Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ambiguous all-writes-disabled banner with a machine-readable and human-readable matrix that distinguishes implemented reads, authenticated private reads, calibration-blocked operations, unimplemented writes, and native-console-only operations.

**Architecture:** Static implementation and verification states live in the metadata-only adapter so rpcd can serve them without loading HTTP/session code. Existing top-level capability booleans remain compatible and continue to be the only authority for enabling controls. LuCI renders the descriptive matrix but never infers or enables an operation from descriptive state.

**Tech Stack:** POSIX Shell, rpcd/ubus JSON, LuCI JavaScript, Node.js assertion tests, shellcheck.

---

### Task 1: Define the capability-status contract

**Files:**
- Modify: `tests/test_adapter.sh`
- Modify: `tests/test_rpcd.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh`

- [x] **Step 1: Add failing adapter assertions**

Require `zte_adapter_effective_capabilities_json` to preserve its existing booleans and add `feature_status` entries with only these values:

```text
implementation: implemented | not_implemented | native_console_only
verification: local_and_qemu | simulator_only | spare_device_required | native_console
access: read | write
enabled: true | false
```

The matrix must classify public telemetry reads as `implemented/local_and_qemu`, clients and SMS reads as `implemented/simulator_only`, SIM switching as `implemented/spare_device_required`, the other write families as `not_implemented/spare_device_required`, and firmware update, factory reset, backup/restore and device-password changes as `native_console_only/native_console`.

- [x] **Step 2: Verify RED**

Run `./tests/test_adapter.sh` and confirm it fails because `feature_status` is absent.

- [x] **Step 3: Implement the metadata-only JSON**

Add a fixed `zte_adapter_feature_status_json` function. Its write `enabled` values must be derived from the same global and per-feature flags as the legacy booleans. Do not add request parameters, HTTP calls, identifiers or firmware guesses.

- [x] **Step 4: Verify adapter and rpcd GREEN**

Run `./tests/test_adapter.sh` and `./tests/test_rpcd.sh`. The latter must prove the exact rpcd response carries the matrix unchanged and retains all legacy booleans.

- [x] **Step 5: Commit**

Commit metadata and tests as `feat: expose U25S capability states`.

### Task 2: Render precise capability state in LuCI

**Files:**
- Modify: `tests/test_luci.js`
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`

- [x] **Step 1: Add failing UI assertions**

Render a matrix containing each state and require Chinese labels for available read, authenticated/simulator-verified read, spare-device calibration required, not implemented and native-console-only. Prove that `feature_status.*.enabled=true` without the corresponding legacy boolean does not render a write control.

- [x] **Step 2: Verify RED**

Run `node tests/test_luci.js` and confirm failure because the matrix renderer and precise labels are absent.

- [x] **Step 3: Implement the renderer**

Add a compact capability section to Diagnostics. Validate every incoming enum against a local allowlist and render unknown values as unavailable. Replace the blanket bottom warning with a short summary pointing users to Diagnostics; keep all existing legacy-boolean control gates unchanged.

- [x] **Step 4: Verify GREEN**

Run `node tests/test_luci.js` and confirm all assertions pass.

- [x] **Step 5: Commit**

Commit UI and tests as `feat: explain U25S capability readiness`.

### Task 3: Document and verify the matrix

**Files:**
- Modify: `README.md`
- Modify: `package/zte-usb-wifi-manager/Makefile`
- Modify: `luci-app-zte-usb-wifi-manager/Makefile`
- Modify: `tests/test_packaging.sh`
- Modify: `tests/test_structure.sh`
- Modify: `docs/superpowers/plans/2026-08-01-capability-matrix.md`

- [x] **Step 1: Add a structure assertion and verify RED**

Require README to explain all four product categories and state that descriptive metadata cannot enable a write.

- [x] **Step 2: Update README and finish this checklist**

Document the matrix under current status, link users to the native console for native-only operations, and mark completed steps in this plan.

- [x] **Step 3: Bump the candidate package releases**

Change backend r17 to r18 and LuCI r6 to r7, then update the hermetic packaging
fixtures and prerelease metadata assertions. The r17/r6 validation records remain
historical evidence and must not be rewritten.

- [x] **Step 4: Run full verification**

Run `make check`, `git diff --check`, and the sensitive-data scan. Review the complete diff for accidental capability enablement.

- [x] **Step 5: Commit and push**

Commit as `docs: explain capability readiness matrix` and push `codex/phase1-phase2`.
