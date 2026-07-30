# Phase 4 Event Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded, tmpfs-only, structured event logs and expose them through a read-only rpcd method.

**Architecture:** The daemon is the only writer and accepts fixed event levels/types plus a restricted symbolic code. Files remain under the runtime directory, rotate at a byte limit, and never accept arbitrary payloads, device IDs, numbers, or message content.

**Tech Stack:** POSIX Shell, JSONL, rpcd/ubus, LuCI JavaScript.

---

### Task 1: Bounded event log library

**Files:**
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/event-log.sh`
- Create: `tests/test_event_log.sh`
- Modify: `Makefile`
- Modify: `tests/test_structure.sh`

- [ ] Test validation, mode-700 directory, mode-600 files, exact JSONL records and two-file rotation.
- [ ] Implement fixed-field event writing and JSON array listing.
- [ ] Reject arbitrary codes longer than 64 characters or outside lowercase symbolic syntax.
- [ ] Run `make check` and commit.

### Task 2: Daemon and rpcd integration

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`
- Modify: `package/zte-usb-wifi-manager/files/usr/libexec/rpcd/zte_usb_wifi`
- Modify: `tests/test_rpcd.sh`
- Modify: `luci-app-zte-usb-wifi-manager/root/usr/share/rpcd/acl.d/luci-app-zte-usb-wifi-manager.json`

- [ ] Record service start and backend state changes only; successful polls must not write a line.
- [ ] Add `logs` with validated limit `1..200`.
- [ ] Return `{"events":[]}` for a missing log.
- [ ] Grant read ACL, run behavior tests, and commit.

### Task 3: LuCI logs panel

**Files:**
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`
- Modify: `tests/test_luci.js`

- [ ] Load logs independently from status and capabilities.
- [ ] Preserve status rendering when logs fail.
- [ ] Render event time, level, type and symbolic code without accepting HTML.
- [ ] Run `make check` and commit.
