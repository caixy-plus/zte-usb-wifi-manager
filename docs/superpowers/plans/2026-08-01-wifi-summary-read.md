# Wi-Fi Summary Read Plan

**Goal:** Add a password-free U25S Wi-Fi summary to the cached snapshot and LuCI console.

**Architecture:** Extend the existing safe bulk read with an explicit allowlist of Wi-Fi status fields observed in the target firmware. Never request or normalize password/passphrase fields.

- [x] Confirm exact field names in the current device `service.js` and run a redacted schema-only probe.
- [x] Add failing adapter and LuCI tests, including an explicit credential-leak assertion.
- [x] Add strict adapter normalization and simulator allowlist entries.
- [x] Replace the Wi-Fi placeholder with read-only summary rows.
- [x] Run all checks, document evidence, commit and push.
