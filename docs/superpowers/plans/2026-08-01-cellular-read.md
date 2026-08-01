# Cellular Read Expansion Plan

**Goal:** Extend the cached U25S snapshot and LuCI network panel with radio and connection fields proven by the current device's static service contract.

**Architecture:** Add exact non-identifying fields to the existing daemon bulk read; normalize absent/empty values to null in the adapter; render values from the cached rpcd snapshot only.

- [x] Add failing adapter and LuCI assertions for LTE RSRP, RSCP, RSSI, roaming, dial mode, WAN mode, MCC and MNC.
- [x] Confirm exact field names in the current device `service.js` and run a redacted schema-only probe.
- [x] Extend production metadata, normalization and simulator allowlist without enabling writes.
- [x] Render the normalized values without interpreting uncalibrated enums.
- [x] Run all checks, record validation evidence, commit and push.
