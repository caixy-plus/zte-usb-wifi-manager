# AGENTS.md

## Project

ZTE USB WiFi Manager is an OpenWrt backend package plus a LuCI application for a ZTE U25S connected over USB.

## Boundaries

- Ship read-only support before device writes.
- Do not infer capabilities from generic or dormant firmware code.
- A feature belongs in the product only when visible in the target device UI, verified on the target firmware, or explicitly requested.
- Never commit credentials, cookies, device identifiers, phone numbers, or SMS content.
- LuCI calls rpcd/ubus; it does not run shell commands directly.
- Development testing never touches the main router: offline simulation first, spare-hardware bench for USB power/recovery, main router only for final read-only gray rollout. See `docs/design/testing-strategy.md`.

## Architecture

One-directional data flow; each layer only talks to the next:

1. `zte-usb-wifi-managerd` (procd-managed, respawns) loads and validates UCI
   config, uses the HTTP/session layer and U25S adapter to log in and batch-read
   the device, combines the normalized result with netifd state and read-only
   policy monitoring, and atomically writes the composed snapshot to
   `/var/run/zte-usb-wifi-manager/status.json`. Consecutive failures trigger
   polling backoff while the last trusted device state is retained.
2. `usr/libexec/rpcd/zte_usb_wifi` exposes exactly two ubus methods, `status`
   and `capabilities`. It serves the cached snapshot and never touches the
   device itself.
3. The LuCI view (`view/zte-usb-wifi-manager/index.js`) calls those ubus
   methods only. The ACL grants only those two ubus reads.

Static ZTE U25S identity and capability flags are isolated in
`adapter-zte-u25s-metadata.sh`; HTTP API details and field normalization remain
in `adapter-zte-u25s.sh` behind `zte_adapter_*` functions. The rpcd script
sources metadata only, while the daemon loads both files, keeping rpcd and the
policy core independent of the HTTP/session stack. `policy.sh` is a pure,
deterministic function (`zte_policy_decide`) mapping battery state to a power
action; `validation.sh` holds all input validation. Both are plain libraries
sourced by the daemon and directly unit-tested.

Capability gating is code, not UI: uncalibrated device features must return
`unsupported` from the adapter (`ZTE_CAP_*=0`), never merely be hidden in LuCI.

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
