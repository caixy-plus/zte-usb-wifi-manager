# Phase 3 Power Dry-Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement mock and dry-run power backends, policy execution records, and a hard-disabled hardware backend without touching USB power.

**Architecture:** The pure policy continues to choose `ON`, `OFF`, or `KEEP`. A separate Power Adapter validates the backend and action, atomically records the decision, and reports whether hardware executed it; only a future calibrated hardware profile may set `executed=true` outside the mock backend.

**Tech Stack:** POSIX Shell, UCI, procd daemon, JSON status files.

---

### Task 1: Power Adapter library

**Files:**
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/power-adapter.sh`
- Create: `tests/test_power_adapter.sh`
- Modify: `Makefile`
- Modify: `tests/test_structure.sh`

- [ ] Test backend/action/reason validation.
- [ ] Test `KEEP`, `mock`, `dry-run`, and rejected `hardware` results.
- [ ] Test atomic mode-600 decision records.
- [ ] Implement the minimal library and run `make check`.
- [ ] Commit.

Result shape:

```json
{"backend":"dry-run","action":"OFF","executed":false,"reason":"battery_high"}
```

### Task 2: Daemon integration

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`
- Modify: `tests/test_structure.sh`
- Modify: `README.md`

- [ ] Test loading and validation of `power.usb.backend`.
- [ ] Require unconfigured/hardware backends to remain non-executing.
- [ ] After policy calculation, record decisions only for `mock` or `dry-run`.
- [ ] Keep `policy.enabled=0` and `write_enabled=0` defaults.
- [ ] Run `make check` and commit.

This plan does not implement TR3000 GPIO, USB authorization, or controller reset commands.
