# Phase 2 Action Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an atomic, serialized action queue and safe rpcd operation-status API while every uncalibrated production write capability remains disabled.

**Architecture:** rpcd validates a flat semantic request and atomically writes a mode-600 queued action under the runtime directory. The daemon is the only future consumer; rpcd can read operation state but never loads the HTTP/session adapter or contacts U25S.

**Tech Stack:** POSIX Shell, existing flat JSON helpers, rpcd exec protocol, UCI capability gates.

---

### Task 1: Atomic action queue library

**Files:**
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/actions.sh`
- Create: `tests/test_actions.sh`
- Modify: `Makefile`
- Modify: `tests/test_structure.sh`

- [ ] Write failing tests for valid operation types, ID validation, mode-700 directories,
  mode-600 queue files, active-operation rejection, status lookup and missing-operation errors.
- [ ] Run `./tests/test_actions.sh` and verify it fails because `actions.sh` is absent.
- [ ] Implement `zte_action_type_valid`, `zte_operation_id_valid`,
  `zte_action_init`, `zte_action_enqueue`, `zte_action_has_active` and
  `zte_action_get`.
- [ ] Validate payloads with `zte_json_is_flat_object` before embedding them.
- [ ] Create queue files through a process-specific temporary file followed by `mv`.
- [ ] Add the suite to `make test`, run `make check`, and commit.

The queue record must use this exact shape:

```json
{
  "operation_id": "op-1722345678-1234",
  "type": "switch_sim",
  "state": "queued",
  "payload": {"target":"sim1"},
  "created": 1722345678
}
```

### Task 2: Read-only operation status through rpcd

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi`
- Modify: `tests/test_rpcd.sh`
- Modify: `luci-app-zte-usb-wifi-manager/root/usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json`
- Modify: `tests/test_structure.sh`

- [ ] Add failing tests requiring `operation_status` in rpcd list output.
- [ ] Pipe `{"operation_id":"op-1722345678-1234"}` to the rpcd call and require the
  matching cached action record.
- [ ] Require malformed IDs and missing records to return structured JSON errors.
- [ ] Source only `json.sh`, `actions.sh` and static metadata; assert rpcd still does not source
  the HTTP/session adapter.
- [ ] Grant `operation_status` read ACL, run the rpcd and structure suites, and commit.

Error replies:

```json
{"ok":false,"error":"invalid_operation_id"}
{"ok":false,"error":"operation_not_found"}
```

### Task 3: Production write gates

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi`
- Modify: `tests/test_rpcd.sh`

- [ ] Add failing tests for `cellular_action`, `wifi_action`, `traffic_action` and
  `sms_action`.
- [ ] Require every method to return `{"ok":false,"error":"unsupported"}` with the current
  production metadata and assert that the pending queue stays empty.
- [ ] Add `zte_adapter_action_supported` with a fixed action-to-capability mapping.
- [ ] Validate method and action before checking support, so unknown action names return
  `invalid_action` and cannot be hidden by an `unsupported` reply.
- [ ] Run `make check` and commit.

No capability flag changes from `false` in this plan.
