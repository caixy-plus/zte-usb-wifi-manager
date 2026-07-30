# L2 U25S API Simulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dependency-free local HTTP simulator that exercises the production U25S login, cookie, retry, parsing, and timeout paths without touching real hardware.

**Architecture:** A Python standard-library `ThreadingHTTPServer` implements only the observed read-only goform contract. A POSIX Shell integration suite starts it on loopback with an ephemeral port and calls the shipped Shell adapter through real curl; all non-login write requests remain denied.

**Tech Stack:** Python 3 standard library, POSIX Shell, curl, existing adapter/session/json libraries.

---

### Task 1: Specify the simulator contract with a failing integration test

**Files:**
- Create: `tests/test_u25s_simulator.sh`
- Modify: `Makefile`

- [ ] **Step 1: Add a lifecycle helper**

The test starts the simulator with:

```sh
python3 tests/u25s_simulator.py \
    --host 127.0.0.1 \
    --port 0 \
    --scenario "$scenario" \
    --ready-file "$ready_file" \
    --request-log "$request_log" \
    --login-secret "$login_secret"
```

It waits for the ready file, reads the ephemeral port, and always kills and
waits for the child process from its trap.

- [ ] **Step 2: Exercise production code over HTTP**

Source `json.sh`, `http.sh`, `session.sh`, both adapter files, then assert:

```text
normal        login succeeds and normalized U25S status is returned
expire-once   the adapter performs exactly two LOGIN requests and recovers
missing       a partial known-field response normalizes with a missing list
malformed     invalid JSON makes zte_adapter_fetch fail
timeout       a delayed LD response honors ZTE_HTTP_TIMEOUT and fails
write request a non-LOGIN goformId receives HTTP 403
```

The request log may contain only method, symbolic endpoint, and status; it must
never contain cookie values, the login secret, or the computed digest.

- [ ] **Step 3: Verify RED**

Run:

```sh
./tests/test_u25s_simulator.sh
```

Expected: FAIL because `tests/u25s_simulator.py` does not exist and no ready
file is produced.

### Task 2: Implement the minimum read-only simulator

**Files:**
- Create: `tests/u25s_simulator.py`
- Modify: `tests/test_u25s_simulator.sh`

- [ ] **Step 1: Implement the observed endpoints**

Use `ThreadingHTTPServer` and `BaseHTTPRequestHandler`:

```text
GET  /goform/goform_get_cmd_process?cmd=LD
POST /goform/goform_set_cmd_process with goformId=LOGIN
GET  /goform/goform_get_cmd_process?cmd=<read fields>
```

The login digest is uppercase SHA-256 of
`lowercase_sha256(login_secret) + challenge`. Successful login sets an opaque
fixture cookie. Status reads require that cookie.

- [ ] **Step 2: Implement deterministic fault scenarios**

Scenario behavior:

```text
normal       return the sanitized read_ok fixture
expire-once  reject the first authenticated status read with an empty object,
             invalidate the session, then accept the relogin
missing      return a small object containing at least one known read field
malformed    return a non-JSON response
timeout      delay the LD response beyond the test curl timeout
```

All other POST actions respond with HTTP 403. Unsupported paths and commands
respond with HTTP 404.

- [ ] **Step 3: Verify GREEN**

Run:

```sh
./tests/test_u25s_simulator.sh
```

Expected: all L2 assertions pass using loopback only.

### Task 3: Integrate, document, and verify

**Files:**
- Modify: `Makefile`
- Modify: `docs/design/testing-strategy.md`

- [ ] **Step 1: Add the L2 suite to the standard gate**

Place `tests/test_u25s_simulator.sh` after the existing adapter suite in
`make test`. Keep Python 3 as the only new test dependency; do not add a runtime
package dependency.

- [ ] **Step 2: Mark L2 implemented**

Update the testing strategy to distinguish the new loopback HTTP simulator
from the earlier fixture/stub coverage and list its deterministic scenarios.

- [ ] **Step 3: Run full verification**

Run:

```sh
make check
dash ./tests/test_u25s_simulator.sh
git diff --check
node tests/scan_sensitive_data.js
```

Expected: all tests and lint pass, the simulator binds loopback only, and the
sensitive-data scan reports nothing.

- [ ] **Step 4: Review and publish**

Review the diff for accidental device access or write enablement. Commit only
the simulator, tests, Makefile, strategy update, and this plan; push `main`
after the full gate succeeds.
