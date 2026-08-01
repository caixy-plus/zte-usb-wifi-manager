# Authenticated Private Collections Plan

**Goal:** Add bounded, authenticated client and SMS collection pipelines so the LuCI console can replace the U25S pages without exposing private data through logs or public snapshots.

**Architecture:** Use the OpenWrt-native `jsonfilter` implementation to iterate verified array objects. The daemon remains the only device caller; rpcd only reads mode-600 cached collections. Authentication failures use explicit states and backoff.

- [x] Verify `jsonfilter` array/object behavior on OpenWrt 25.12.5.
- [x] Add failing station-list projection tests with bounds and unknown-field exclusion.
- [x] Implement the bounded station-list normalizer and authenticated fetch contract.
- [x] Integrate client collection status into the daemon snapshot and LuCI.
- [x] Add a separate mode-600 SMS cache, rpcd method and privacy tests.
- [ ] Run full checks and dual-version QEMU validation; commit and push.
