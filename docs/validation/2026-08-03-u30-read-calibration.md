# U30 Pro read-only calibration — 2026-08-03

## Scope

Read-only calibration was performed through the Cudy USB management network.
No device write endpoint was called. Credentials, cookies, AD values, device
identifiers, telephone numbers, SMS bodies, SSIDs and client MAC addresses are
not recorded here or in fixtures.

## Verified transport and identity

- USB identity: `19d2:1354`, exact product `U30 Pro`.
- OpenWrt network device: `eth2`; logical interface: `usbwan`.
- Device management origin: `https://192.168.0.1`.
- The status request requires an HTTPS Referer and `isTest=false`.
- The device certificate is not trusted by the router image, so the selected
  U30 profile explicitly uses curl's insecure TLS mode and reports
  `device_certificate_unverified` rather than implying certificate validation.
- The inspected WebUI declares `DEVICE_MODEL=U30Air`, `DEVICE=ufi/mu3351`,
  `HAS_LOGIN=false`, `LOGIN_SECURITY_SUPPORT=false`, and
  `ACCESSIBLE_ID_SUPPORT=false`.

Authentication correction (2026-08-13): the current live file expresses
`HAS_LOGIN:!0`, which evaluates to `true`, and serves a password login page.
The login conclusion above is superseded by
`2026-08-13-u30-auth-recheck.md`; the read-field calibration remains valid.

## Sanitized observed fields

The committed `tests/fixtures/u30/status.json` contains only reviewed fields.
The response proved:

- modem state `modem_init_complete`;
- network type `5G`, signal-bar value `5`, and connected IPv4/IPv6 PPP;
- firmware family `U30ProV1.0.0B23` and hardware family `U30ProHW1.0`;
- U30 uses `connectionMode` rather than the U25S `ConnectionMode` spelling;
- battery percentage is populated even though `battery_exist` is an empty
  string; the U30 profile therefore treats a valid percentage as evidence of
  the built-in battery;
- `battery_charging=1` was observed while `power_supply_mode=0`;
- `power_supply_mode` is readable from the common goform GET endpoint.

Battery percentage and throughput values are observations, not fixed product
constants. Tests use them only to prove parsing and JSON types.

## Privacy regression found during calibration

Requesting `sms_data_total` on this U30 firmware returned a nested message
collection, including private message metadata and contents. A raw response is
therefore unsuitable for the public status snapshot. The U30 profile removes
`sms_data_total` from the general flat-field batch. SMS remains isolated behind
the dedicated bounded reader and the mode-600 private cache.

## Static power-supply contract discovery

The device WebUI service and page modules independently show:

- read command: `power_supply_mode`;
- write command: `POWER_SUPPLY_SETTING`;
- write key: `power_supply_mode` with values `0` and `1`;
- the page binds the switch as enabled when the read value is `1`;
- the static files advertised `ACCESSIBLE_ID_SUPPORT=false`; later controlled
  write evidence proved that current firmware nevertheless requires a dynamic
  AD for `POWER_SUPPLY_SETTING` (superseded by the r40 correction in
  `2026-08-13-u30-auth-recheck.md`).

This records the request shape only. The charging semantics, data-link
continuity and write/readback behavior must still pass the controlled Stage 2
real-device calibration before the capability is enabled.

## Remaining Stage 1 acceptance

- Build the next APK/IPK candidate.
- Install it on Cudy with every write feature flag set to zero.
- Prove fresh `state=ok`, `model=U30 Pro`, `adapter=zte_u30` snapshots.
- Verify LuCI, rpcd, daemon restart and router reboot recovery.
- Run `make check`, commit and push the Stage 1 checkpoint.
