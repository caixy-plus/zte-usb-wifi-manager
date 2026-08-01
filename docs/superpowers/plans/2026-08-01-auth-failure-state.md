# Authentication Failure State Plan

**Goal:** Distinguish rejected U25S credentials from transport failures throughout adapter, daemon, snapshot, LuCI and soak validation.

- [x] Add failing adapter, daemon and LuCI tests.
- [x] Return adapter status 3 for rejected LOGIN and preserve backoff accounting.
- [x] Render a dedicated LuCI state and accept it in soak collection.
- [x] Run all checks, document evidence, commit and push.
