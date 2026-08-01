# Phase 2 Semantic Write Request Contracts

## Goal

Complete the vendor-independent request boundary for all first-release device
write families without enabling any uncalibrated production write. A later
spare-device calibration maps these semantic values to exact U25S goform
parameters and adds operation-specific readback.

## Contract

All requests are flat JSON and pass through an exact ubus schema. Duplicate
keys, unknown keys, missing required values, invalid enum values and values
outside documented bounds are rejected before capability and queue checks.

The semantic operations are:

- `switch_sim`
- `set_apn`
- `set_connection_mode`
- `set_wifi`
- `set_traffic_plan`
- `reset_traffic`
- `send_sms`
- `delete_sms`
- `mark_sms_read`

Runtime requests are atomically queued in mode-600 files. RPC replies and
event logs contain only operation identifiers and symbolic state; APN/Wi-Fi
passwords and SMS numbers/content are not echoed. Result records do not retain
the request payload.

## Tasks

- [x] Reject duplicate JSON keys and expose validated flat-object keys.
- [x] Define strict semantic payload validation for all nine operations.
- [x] Expand rpcd list schemas so ubus passes every reviewed semantic field.
- [x] Test all capability-enabled request families through the real rpcd
  command interface and mode-600 action queue.
- [x] Keep every production device-write capability and UCI write flag off.
- [ ] Map semantic operations to exact target-firmware request parameters on a
  spare U25S.
- [ ] Verify success, rejection, session expiry, timeout and operation readback
  on spare hardware before enabling any production capability.
