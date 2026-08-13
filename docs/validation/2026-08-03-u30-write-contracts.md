# U30 Pro semantic write contracts — 2026-08-03

## Evidence and handling rules

The contract is transcribed from the U30 Pro files served by the device itself:

- `js/service.js` defines `getPowerSupplySetting` and
  `setPowerSupplySetting`;
- `js/adm/power_supply.js` binds the page switch to the value `1` and sends
  `0` or `1`;
- `js/config/config.js` resolves `HAS_LOGIN:!0` to login-required and keeps
  accessible-ID support disabled on the current firmware. This authentication
  correction supersedes the earlier anonymous interpretation; see
  `2026-08-13-u30-auth-recheck.md`.

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

Every device write first completes the reviewed LD challenge and LOGIN digest
exchange using the root-owned, mode-0600 credential file. Anonymous status GETs
remain allowed, but an anonymous POST returning HTTP 200 with an empty body is
not success and must remain `write_ambiguous` unless exact readback proves the
target state.

## Execution rule

The executor issues the POST exactly once. A reviewed success marker is still
followed by an exact GET readback; the successful GET also proves that the USB
management interface remains reachable.

Transport timeout, HTTP 5xx, an empty response or malformed JSON after the POST
is ambiguous and must never trigger a second POST. An exact, successful GET of
the requested mode may safely resolve that ambiguity as success because the
mode is fully readable. If bounded readback cannot prove the requested mode,
the operation remains `timed_out/write_ambiguous` and automatic charging is
suspended until a later trusted poll.

HTTP 4xx or a valid response containing an explicit non-success result is a
definite `device_rejected` outcome. A prior matching state must not convert a
definite rejection into success. Settings containing write-only secrets are
stricter: password-free readback cannot resolve an ambiguous password change.

## Calibration gate

The values `0=charging` and `1=direct supply` agree with the page switch and the
observed `power_supply_mode=0` plus `battery_charging=1`, but capability enablement
still requires one controlled two-way real-device test that restores the
original value and proves the USB data link remains up.
