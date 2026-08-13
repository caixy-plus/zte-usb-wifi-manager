# U30 Pro authentication recheck — 2026-08-13

## Live evidence

The deployed U30 Pro serves a password login page. Its current WebUI
`js/config/config.js` contains `HAS_LOGIN:!0`, which evaluates to JavaScript
`true`; `ACCESSIBLE_ID_SUPPORT` remains false. The power page still uses the
reviewed `POWER_SUPPLY_SETTING` contract with `power_supply_mode` values `0`
and `1`.

Two controlled anonymous writes were each followed by bounded exact GET
readback. Both returned HTTP 200 with an empty body and left
`power_supply_mode=1` unchanged. The manager correctly classified the original
attempt as `write_ambiguous`, entered cooldown, and did not retry it blindly.
The USB `eth2` management link and default route remained available throughout.
No credential, cookie, identifier, SSID, or other private device value is
recorded here.

## r34 correction

- The exact U30 profile and cached metadata now declare `login_required=true`.
- Anonymous status reads remain supported by the existing probe-first read
  path.
- Smart charging reads the protected credential only immediately before its
  authenticated executor call and clears its shell variables afterward.
- U30 power, settings, actions, and calibration simulations now exercise the
  LD/LOGIN contract. Missing or rejected credentials fail closed.

## Offline verification

- `make check`: PASS.
- U30 power executor E2E: 136 assertions PASS.
- U30 settings E2E: 56 assertions PASS.
- U30 action E2E: 46 assertions PASS.
- U30 power calibration and recovery: 110 assertions PASS.

## r35 lifecycle correction

The first r34 field upgrade also showed that a daemon sleeping between polls
could outlive procd's TERM grace period and be killed. The poll wait is now a
tracked child process: TERM interrupts that wait, reaps it, and lets the normal
exit cleanup run. A lifecycle regression test requires a 30-second wait to
terminate within three seconds; the complete `make check` suite passes with
the correction.

## r36 browser request alignment

The user-confirmed U30 password was rejected by the existing login helper with
device result code `3`. A bounded replay using the same password and digest but
the complete native-browser POST contract returned result code `0`. The
load-bearing drift was the missing same-origin POST context: the U30 WebUI sends
both `Origin` and its jQuery form content type, while the helper previously sent
only `Referer`. All POST helpers now send the validated origin and
`application/x-www-form-urlencoded; charset=UTF-8`; the simulator rejects U30
login and write requests when either value drifts. No password, digest, cookie,
or device identifier is retained in this record.

The authenticated two-way real-device mode transition remains pending until a
U30 Web management password is installed through the write-only credential
RPC. All three production write gates remain closed in the meantime.
