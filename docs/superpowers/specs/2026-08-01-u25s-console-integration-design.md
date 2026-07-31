# U25S Console Integration Design

## 1. Product decision

ZTE USB WiFi Manager is an OpenWrt LuCI integration for the device-specific
management capabilities of a USB-connected ZTE U25S. Its primary purpose is to
let an administrator inspect and manage the U25S without leaving OpenWrt.

Battery telemetry remains useful, but automatic battery cycling is removed from
the product promise. Cutting TR3000 USB VBUS also interrupts USB data, so USB
power control cannot provide seamless charge management. Existing power-control
code is retained only as a separately gated recovery mechanism for deliberate
device power cycles; it must never be driven by battery thresholds or schedules.

## 2. Scope

The integration covers U25S-specific functions:

- device, modem, firmware, battery, SIM and registration status;
- cellular connection mode, roaming, network preference, APN, reconnect and
  operator scan where the target firmware exposes verified interfaces;
- physical SIM and eSIM inventory and controlled switching;
- U25S 2.4 GHz and 5 GHz radios, primary and guest SSIDs, encryption, WPS,
  sleep settings and connected-client access control;
- current-session, real-time and monthly traffic information, plan thresholds
  and device counter reset;
- SMS folder counts, paginated metadata, on-demand message bodies, sending,
  drafts, deletion and read state;
- U25S diagnostics, device logs, time and power-saving settings, reboot,
  shutdown and scheduled reboot;
- capability reporting, operation history and links back to the native U25S
  page for deliberately unimplemented functions.

OpenWrt-native DHCP, DDNS, firewall, URL filtering, port mapping, port
forwarding and LAN configuration are not duplicated. Firmware update, factory
reset, backup/restore and device-password changes remain native-console links
until their rollback behavior is proven on spare hardware.

## 3. Capability rule

A control is available only when all three conditions are true:

1. the function is visible in the target U25S firmware;
2. its exact request, response and readback contract has been captured and
   sanitized;
3. a controlled real-device test has verified success, failure and recovery.

Discovered JavaScript symbols alone are evidence for investigation, not product
capabilities. Uncalibrated operations return `unsupported` and are not rendered
as enabled controls. Each write family also has an independent UCI feature flag
below the global `write_enabled` switch.

## 4. Architecture

The existing one-directional boundary is preserved:

1. The procd daemon is the sole owner of U25S HTTP sessions. It performs
   scheduled bulk reads and executes serialized read jobs and write jobs.
2. Device adapters translate raw goform fields into stable module contracts.
   Common authentication and HTTP code is shared, while cellular, Wi-Fi,
   clients, traffic, SMS and device-system contracts remain separate.
3. Normalized module snapshots and operation results are written atomically to
   root-owned mode-0600 runtime files.
4. rpcd validates LuCI requests, serves cached data, and enqueues jobs. It never
   contacts the U25S directly.
5. LuCI displays only normalized data and capability-gated controls.

Fast-changing, non-sensitive summaries may be included in the main status
snapshot. Large or sensitive data uses bounded module caches. SMS bodies are
loaded only after an explicit request, stored for a short time, and never placed
in logs or the general snapshot.

## 5. Module contracts

The public ubus surface is divided by responsibility:

- core: `status`, `capabilities`, `credential_status`, `set_credentials`,
  `operation_status`, `logs`;
- cellular: `cellular_status`, `cellular_action`;
- Wi-Fi and clients: `wifi_status`, `wifi_action`, `clients_status`,
  `client_action`;
- traffic: `traffic_status`, `traffic_action`;
- SMS: `sms_list`, `sms_detail`, `sms_action`;
- device: `device_status`, `device_action`, `diagnostics`.

All mutation methods return an operation identifier. The daemon moves each
operation through `queued`, `running`, `verifying` and a terminal state.
Verification reads the affected setting or service state back from the U25S;
an HTTP success response alone is insufficient.

Only one disruptive cellular or device-system operation may run at a time.
Independent read jobs may be coalesced, and duplicate refresh requests must not
create an unbounded queue.

## 6. LuCI information architecture

The page uses the following active tabs:

- Overview
- Mobile network and SIM
- U25S Wi-Fi
- Connected devices
- Traffic
- SMS
- Device and system
- Diagnostics and logs

Battery status appears in Overview and Device and system. Battery schedules and
automatic charge controls are removed. A manual USB power-cycle recovery action,
if calibrated, appears only under Diagnostics, warns that USB data will drop,
and requires explicit confirmation.

Unavailable modules explain whether the cause is unsupported firmware,
incomplete calibration, missing credentials or a backend failure. The native
console link remains visible as an escape hatch.

## 7. Security and privacy

- The U25S password is stored only in the existing root-owned mode-0600
  credential file and is never returned through ubus.
- ACLs enumerate exact ubus methods; sensitive and mutating methods are not
  granted to read-only LuCI sessions.
- Phone numbers, SMS bodies, passwords, cookies, authentication digests, IMEI,
  IMSI and ICCID are excluded from logs, fixtures, diagnostics and exports.
- Parameters use action-specific validation and encoding. Raw goform names and
  arbitrary request bodies are never accepted from LuCI.
- Dangerous operations require a confirmation token tied to the operation type
  and expire quickly.
- Runtime queues and sensitive caches are bounded, atomically written and mode
  0600. Reboot clears them.

## 8. Failure behavior

Read failures retain the last trusted snapshot, mark it stale and report a
machine-readable reason. Missing fields degrade only their module. Session
expiry triggers one serialized re-authentication attempt before backoff.

Writes fail closed. A timeout never causes automatic repetition of a
non-idempotent action. When readback cannot establish the result, the terminal
state is `unknown`, not `succeeded`, and the UI directs the administrator to the
native console. Network-disruptive operations pause conflicting jobs until
registration and PPP either recover or time out.

## 9. Delivery sequence

The work is decomposed into independently releasable subprojects:

1. Product reset: update naming, navigation and documentation; remove battery
   automation from the daemon and UI while retaining read-only battery status.
2. Read parity: capture sanitized fixtures and implement full cellular, Wi-Fi,
   clients, traffic, SMS metadata and device-system read contracts.
3. Low-risk settings: traffic-plan and U25S Wi-Fi settings with post-write
   readback.
4. Communications: SMS operations, APN, connection preferences and reconnect.
5. SIM switching: calibrate every visible target and verify SIM readiness,
   registration and PPP recovery.
6. Device operations: diagnostics, logs, time/power-saving settings, reboot and
   shutdown with explicit interruption warnings.
7. Release hardening: QEMU package lifecycle, simulator fault injection,
   spare-device calibration matrix, soak testing and signed release artifacts.

Each subproject begins with fixtures and failing tests, ships disabled writes by
default, and may be released without waiting for later subprojects.

## 10. Acceptance criteria

- Every enabled tab presents real normalized U25S data or a precise unavailable
  reason; placeholder panels are absent from a stable release.
- Every enabled write has sanitized contract evidence, simulator coverage and a
  recorded real-device success/failure/readback result for the target firmware.
- No battery policy can trigger USB VBUS changes.
- USB power cycling, if available, is represented only as disruptive recovery.
- rpcd never contacts the device and LuCI never executes shell commands.
- Secret scanning, POSIX shell tests, LuCI tests, package builds and QEMU
  install/upgrade/uninstall verification pass.
- The compatibility matrix distinguishes implemented, calibrated, unsupported
  and native-console-only capabilities by firmware version.

