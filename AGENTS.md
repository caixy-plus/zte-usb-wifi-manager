# AGENTS.md

## Project

ZTE USB WiFi Manager is an OpenWrt backend package plus a LuCI application for
**ZTE U30 Pro smart charging** over USB. Product surface is intentionally
narrow: smart-charge policy, read-only device basics, and a native console link.

## Boundaries

- Product target is **U30 Pro only** (`access_profile=charge_v1`).
- Product writes are limited to smart-charge settings (enable + thresholds).
  Daemon may call `set_power_supply_mode` for the policy; LuCI has no manual
  charge/direct buttons and no other device action RPCs.
- Do not reintroduce full console features (cellular/Wi-Fi/SMS/traffic/clients
  writes, SIM switch, reboot/shutdown, USB VBUS power-off) without an explicit
  product request and capability re-calibration.
- Do not infer capabilities from generic or dormant firmware code.
- Never commit credentials, cookies, device identifiers, phone numbers, or SMS content.
- LuCI calls rpcd/ubus; it does not run shell commands directly.
- Development testing never touches the main router: offline simulation first,
  spare-hardware bench for USB link checks, main router only for final
  read-only gray rollout. See `docs/design/testing-strategy.md`.

## Architecture

One-directional data flow; each layer only talks to the next:

1. `zte-usb-wifi-managerd` (procd-managed, respawns) loads and validates UCI
   config, uses the HTTP/session layer and U30 adapter path to log in and
   batch-read the device, applies smart-charge policy, combines the normalized
   result with netifd state, and atomically writes the composed snapshot to
   `/var/run/zte-usb-wifi-manager/status.json`. Consecutive failures trigger
   polling backoff while the last trusted device state is retained.
2. `usr/libexec/rpcd/zte_usb_wifi` serves cached status/capabilities,
   credential state, charging settings, and smart-charge-filtered event logs.
   It never contacts the device and does not enqueue console actions.
3. The LuCI view (`view/zte-usb-wifi-manager/index.js`) calls rpcd/ubus only
   (three tabs: device, charging, logs). Password values are write-only and
   never returned to the browser.

Static identity and capability flags live in `adapter-zte-u25s-metadata.sh`
(historical filename); HTTP API details remain in `adapter-zte-u25s.sh` behind
`zte_adapter_*` functions. rpcd sources metadata only; the daemon loads both.
`smart-charge-policy.sh` is a pure, deterministic function; `validation.sh`
holds input validation. Both are unit-tested.

Capability gating is code, not UI: removed product writes stay `unsupported`
/ `ZTE_CAP_*=0`. The only remaining device write (`set_power_supply_mode`)
still requires the global write flag and its UCI feature gate.

## Layout

- `package/zte-usb-wifi-manager/`: backend package.
- `luci-app-zte-usb-wifi-manager/`: LuCI package.
- `tests/`: dependency-light POSIX Shell tests.
- `docs/design/`: accepted design artifacts.
- `docs/plans/`: implementation plans.

## Commands

```sh
make test                       # all suites + sh -n syntax + JSON parse + secret-pattern scan
make lint                       # shellcheck (must be installed) over all shipped shell files
make check                      # test + lint
./tests/test_validation.sh      # run a single suite, from the repo root
```

Tests source `tests/testlib.sh` and library files with paths relative to the
repo root, so always run them from there. `make test` also needs Node.js for
the JSON syntax check.

Use test-first development for behavior changes (state tables for `policy.sh`,
assertion lists for `validation.sh`). Keep shell POSIX-compatible with OpenWrt
`ash`.
