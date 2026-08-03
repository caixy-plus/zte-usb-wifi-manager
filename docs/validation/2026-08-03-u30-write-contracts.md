# U30 Pro semantic write contracts — 2026-08-03

## Evidence and handling rules

The contract is transcribed from the U30 Pro files served by the device itself:

- `js/service.js` defines `getPowerSupplySetting` and
  `setPowerSupplySetting`;
- `js/adm/power_supply.js` binds the page switch to the value `1` and sends
  `0` or `1`;
- `js/config/config.js` plus `js/config/ufi/mu3351/config.js` resolve to
  anonymous login and no accessible-ID support on the inspected firmware.

User-provided browser captures were used only as a discovery hint. Their
Cookie and AD values are session material and are deliberately absent from the
repository, fixtures, logs and commands.

## Power-supply mode

| Property | Frozen value |
|---|---|
| GET command | `power_supply_mode` |
| POST goform ID | `POWER_SUPPLY_SETTING` |
| Mutable key | `power_supply_mode` |
| Fixed key | `isTest=false` |
| Charging candidate | `0` |
| Direct-supply candidate | `1` |
| Success marker | `result=success` |
| Readback | exact `power_supply_mode` match |

Only the three reviewed POST keys are permitted. Extra values, Cookie text,
caller-supplied AD, arbitrary origins and arbitrary goform IDs must be rejected
before an HTTP call is built.

## AD and session rule

The common WebUI request wrapper adds `AD` only when
`ACCESSIBLE_ID_SUPPORT=true`. It is false for the inspected U30 profile, so the
production profile omits AD. The implementation must not accept a browser AD
as configuration because it is derived session material. A future firmware
that enables accessible-ID support must be treated as a different, unsupported
write-security contract until its derivation is independently implemented and
tested.

## Execution rule

The action executor may report success only after all of the following:

1. the POST returns the reviewed success marker;
2. a new GET returns the requested mode;
3. the USB management interface remains reachable.

Transport timeout or malformed response after the POST is ambiguous. The
executor must not repeat the write automatically. A readback mismatch is a
failure and leaves automatic charging suspended until a later trusted poll.

## Calibration gate

The values `0=charging` and `1=direct supply` agree with the page switch and the
observed `power_supply_mode=0` plus `battery_charging=1`, but capability enablement
still requires one controlled two-way real-device test that restores the
original value and proves the USB data link remains up.
