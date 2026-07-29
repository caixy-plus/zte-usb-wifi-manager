# AGENTS.md

## Project

ZTE USB WiFi Manager is an OpenWrt backend package plus a LuCI application for a ZTE U25S connected over USB.

## Boundaries

- Ship read-only support before device writes.
- Do not infer capabilities from generic or dormant firmware code.
- A feature belongs in the product only when visible in the target device UI, verified on the target firmware, or explicitly requested.
- Never commit credentials, cookies, device identifiers, phone numbers, or SMS content.
- LuCI calls rpcd/ubus; it does not run shell commands directly.

## Layout

- `package/zte-usb-wifi-manager/`: backend package.
- `luci-app-zte-usb-wifi-manager/`: LuCI package.
- `tests/`: dependency-light POSIX Shell tests.
- `docs/design/`: accepted design artifacts.
- `docs/plans/`: implementation plans.

## Commands

```sh
make test
make lint
make check
```

Use test-first development for behavior changes. Keep shell POSIX-compatible with OpenWrt `ash`.
