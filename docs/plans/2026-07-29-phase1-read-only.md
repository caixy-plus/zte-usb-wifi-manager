# Phase 1 Read-Only Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire real U25S read-only polling into the framework: goform login/session, batch field reads, sanitized fixtures, daemon status composition, and a real LuCI overview.

**Architecture:** New small POSIX libraries (`json.sh`, `http.sh`, `session.sh`, `snapshot.sh`, `netifd-adapter.sh`) keep every piece pure and testable on macOS/CI: HTTP and ubus access is isolated behind overridable wrapper functions, and all parsing/assembly logic is table-tested without a device. The daemon wires these together; rpcd stays unchanged and keeps serving the cached snapshot; the LuCI overview renders the new schema.

**Tech Stack:** POSIX Shell (OpenWrt `ash` compatible), curl, sha256sum/shasum/openssl, ubus + jsonfilter (device only), LuCI JavaScript views, Node.js (Makefile JSON checks).

**Conventions:**
- Run everything from the repo root. Tests source `./tests/testlib.sh` and libs via relative paths.
- TDD: failing test first, then minimal implementation, then commit.
- `make test` runs all suites + `sh -n` + JSON parse + secret scan; `make lint` runs ShellCheck.
- Test stubs that must survive command substitution (`$(...)`) write counters/logs to temp files, not shell variables.

**Sourcing order (daemon and tests):** `validation.sh` → `json.sh` → `http.sh` → `session.sh` → `policy.sh` → `snapshot.sh` → `netifd-adapter.sh` → `adapter-zte-u25s-metadata.sh` → `adapter-zte-u25s.sh`.

---

## File map

- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/json.sh` — flat JSON extract/escape/validate.
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh` — curl GET/POST wrapper with cookie jar.
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/session.sh` — SHA-256 digest, goform LOGIN, credential file read.
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/snapshot.sh` — failure tracker + status.json composition.
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/netifd-adapter.sh` — ubus/jsonfilter collect (device-only) + pure JSON assembly.
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh` — add batch fetch with relogin-retry and normalized mapping.
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd` — real polling loop with failure tracking and policy monitoring.
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js` — render real overview data.
- Create: `tests/fixtures/u25s/read_ok.json`, `read_missing_fields.json`, `read_malformed.json`, `read_session_expired.json` — sanitized device responses.
- Create: `tests/test_json.sh`, `test_http.sh`, `test_session.sh`, `test_adapter.sh`, `test_snapshot.sh`, `test_netifd.sh`.
- Modify: `tests/test_structure.sh` — assertions for new libs, daemon wiring, fixtures, view fields.
- Modify: `Makefile` — add new suites to the test loop.
- Modify: `README.md`, `AGENTS.md` — status update.

### Task 1: Flat JSON library

**Files:**
- Create: `tests/test_json.sh`
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/json.sh`

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
set -eu
TEST_NAME=test_json
. ./tests/testlib.sh
. ./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/json.sh

assert_eq 'NR5G-SA' "$(zte_json_flat_get '{"network_type":"NR5G-SA"}' network_type)"
assert_eq '-68' "$(zte_json_flat_get '{"Z5g_rsrp":"-68"}' Z5g_rsrp)"
assert_eq '82' "$(zte_json_flat_get '{"battery_vol_percent":"82"}' battery_vol_percent)"
assert_eq '82' "$(zte_json_flat_get '{"percent":82}' percent)"
assert_eq '-3' "$(zte_json_flat_get '{"v":-3}' v)"
assert_eq 'true' "$(zte_json_flat_get '{"online":true}' online)"
assert_eq 'false' "$(zte_json_flat_get '{"online":false}' online)"
assert_eq '' "$(zte_json_flat_get '{"a":"1"}' missing_key)"
# a longer key containing the requested name must not match
assert_eq '' "$(zte_json_flat_get '{"xnetwork_type":"X"}' network_type)"
# values with spaces and CJK survive
assert_eq '中国移动 4G' "$(zte_json_flat_get '{"p":"中国移动 4G"}' p)"
assert_success zte_json_is_flat_object '{"a":"b"}'
assert_failure zte_json_is_flat_object 'not json'
assert_failure zte_json_is_flat_object ''
assert_eq 'a\"b\\c' "$(zte_json_escape 'a"b\c')"
finish
```

Make it executable: `chmod +x tests/test_json.sh`.

- [ ] **Step 2: Verify RED**

Run: `./tests/test_json.sh`
Expected: failure — `json.sh` does not exist.

- [ ] **Step 3: Implement json.sh**

```sh
#!/bin/sh

# Escape a string for inclusion inside a JSON double-quoted value.
zte_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Succeed when "$1" looks like a flat JSON object.
zte_json_is_flat_object() {
    case ${1-} in
        '{'*'}') return 0 ;;
        *) return 1 ;;
    esac
}

# Print the value of key "$2" from flat JSON object "$1".
# Handles "key":"value", "key":123, "key":-12.5, "key":true/false.
# Prints nothing when the key is absent. String values must not
# contain double quotes (goform read fields never do).
zte_json_flat_get() {
    printf '%s' "$1" | sed -n \
        -e 's/.*"'"$2"'":"\([^"]*\)".*/\1/p' \
        -e 's/.*"'"$2"'":\(-[0-9][0-9.]*\)[,}].*/\1/p' \
        -e 's/.*"'"$2"'":\([0-9][0-9.]*\)[,}].*/\1/p' \
        -e 's/.*"'"$2"'":true[,}].*/true/p' \
        -e 's/.*"'"$2"'":false[,}].*/false/p'
}
```

- [ ] **Step 4: Verify GREEN**

Run: `./tests/test_json.sh`
Expected: `PASS test_json`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_json.sh package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/json.sh
git commit -m "feat: add flat JSON extraction library"
```

### Task 2: HTTP curl wrapper

**Files:**
- Create: `tests/test_http.sh`
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh`

- [ ] **Step 1: Write the failing test**

No network in tests — assert the wrapper shape and that functions load:

```sh
#!/bin/sh
set -eu
TEST_NAME=test_http
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh
assert_file_contains "$lib" 'curl -fsS'
assert_file_contains "$lib" 'max-time'
assert_file_contains "$lib" 'X-Requested-With'
assert_file_contains "$lib" 'application/x-www-form-urlencoded'

. "$lib"
if command -v zte_http_get >/dev/null 2>&1; then pass; else fail 'zte_http_get missing'; fi
if command -v zte_http_post >/dev/null 2>&1; then pass; else fail 'zte_http_post missing'; fi
assert_eq 'http://192.168.0.1/' "$(zte_http_referer 'http://192.168.0.1/goform/goform_get_cmd_process?cmd=LD')"
finish
```

Make it executable: `chmod +x tests/test_http.sh`.

- [ ] **Step 2: Verify RED**

Run: `./tests/test_http.sh`
Expected: failure — `http.sh` does not exist.

- [ ] **Step 3: Implement http.sh**

```sh
#!/bin/sh

ZTE_HTTP_TIMEOUT=${ZTE_HTTP_TIMEOUT:-5}

# Derive "http://host/" from a full URL for the Referer header.
zte_http_referer() {
    printf '%s/\n' "$(printf '%s' "$1" | sed 's|^\(http://[^/]*\).*$|\1|')"
}

# $1 url, $2 cookie jar; prints response body
zte_http_get() {
    curl -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
        -b "$2" -c "$2" \
        -H "Referer: $(zte_http_referer "$1")" \
        -H 'X-Requested-With: XMLHttpRequest' \
        "$1"
}

# $1 url, $2 form body, $3 cookie jar; prints response body
zte_http_post() {
    curl -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
        -b "$3" -c "$3" \
        -H "Referer: $(zte_http_referer "$1")" \
        -H 'X-Requested-With: XMLHttpRequest' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data "$2" \
        "$1"
}
```

- [ ] **Step 4: Verify GREEN**

Run: `./tests/test_http.sh`
Expected: `PASS test_http`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_http.sh package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/http.sh
git commit -m "feat: add curl HTTP wrapper with cookie jar"
```

### Task 3: Session and goform login

**Files:**
- Create: `tests/test_session.sh`
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/session.sh`

Fixed test vectors (computed with `shasum -a 256`):

- `zte_sha256_hex test123` → `ecd71870d1963316a97e3ac3408c9835ad8cf0f3c1bc703527c30265534f75ae`
- `zte_session_digest test123 LD-abc123` → `3955A6F57CD749A4311DECB23407C5962119BC835A528EE1BA82B2CF04EEE078`
- `zte_session_digest admin 0000000000` → `1AF5BB73CFA199DB1C17EB9FFE782A23B496E2128D7D74EE688C6FF575B9A471`

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
set -eu
TEST_NAME=test_session
. ./tests/testlib.sh
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/session.sh"

work=/tmp/zte-test-session.$$
mkdir -p "$work"

assert_eq 'ecd71870d1963316a97e3ac3408c9835ad8cf0f3c1bc703527c30265534f75ae' \
    "$(zte_sha256_hex test123)"
assert_eq '3955A6F57CD749A4311DECB23407C5962119BC835A528EE1BA82B2CF04EEE078' \
    "$(zte_session_digest test123 LD-abc123)"
assert_eq '1AF5BB73CFA199DB1C17EB9FFE782A23B496E2128D7D74EE688C6FF575B9A471' \
    "$(zte_session_digest admin 0000000000)"

# successful login posts the expected digest (stub writes body to a file
# because zte_http_post runs inside command substitution)
post_log=$work/post-body
zte_http_get() { printf '%s\n' '{"LD":"LD-abc123"}'; }
zte_http_post() { printf '%s' "$2" >"$post_log"; printf '%s\n' '{"result":"0"}'; }
assert_success zte_session_login 192.168.0.1 test123 "$work/cookies"
assert_eq 'goformId=LOGIN&password=3955A6F57CD749A4311DECB23407C5962119BC835A528EE1BA82B2CF04EEE078' \
    "$(cat "$post_log")"

# non-zero login result is rejected
zte_http_post() { printf '%s\n' '{"result":"3"}'; }
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"

# missing or malformed LD is rejected
zte_http_get() { printf '%s\n' '{}'; }
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"
zte_http_get() { printf '%s\n' 'not json'; }
assert_failure zte_session_login 192.168.0.1 test123 "$work/cookies"

# credential file reading
printf 'password=s3cret value\n' >"$work/credentials"
assert_eq 's3cret value' "$(zte_read_password "$work/credentials")"
assert_failure zte_read_password "$work/does-not-exist"

rm -rf "$work"
finish
```

Make it executable: `chmod +x tests/test_session.sh`.

- [ ] **Step 2: Verify RED**

Run: `./tests/test_session.sh`
Expected: failure — `session.sh` does not exist.

- [ ] **Step 3: Implement session.sh**

```sh
#!/bin/sh

# Print the lowercase hex SHA-256 of "$1" using whatever tool exists.
zte_sha256_hex() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    else
        printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}'
    fi
}

# $1 password, $2 LD challenge -> uppercase double-SHA-256 login digest.
zte_session_digest() {
    step1=$(zte_sha256_hex "$1")
    zte_sha256_hex "$step1$2" | tr '[:lower:]' '[:upper:]'
}

# $1 host, $2 password, $3 cookie jar. Never logs password, digest or cookie.
zte_session_login() {
    host=$1
    ld_response=$(zte_http_get \
        "http://$host/goform/goform_get_cmd_process?cmd=LD&isTest=false" "$3") || return 1
    ld=$(zte_json_flat_get "$ld_response" LD)
    case $ld in
        ''|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    digest=$(zte_session_digest "$2" "$ld")
    login_response=$(zte_http_post \
        "http://$host/goform/goform_set_cmd_process" \
        "goformId=LOGIN&password=$digest" "$3") || return 1
    [ "$(zte_json_flat_get "$login_response" result)" = 0 ]
}

# $1 credential file (root-only 0600, containing a "password=..." line)
zte_read_password() {
    [ -f "$1" ] || return 1
    sed -n 's/^password=//p' "$1" | head -n 1
}
```

- [ ] **Step 4: Verify GREEN**

Run: `./tests/test_session.sh`
Expected: `PASS test_session`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_session.sh package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/session.sh
git commit -m "feat: add goform login session handling"
```

### Task 4: Adapter batch read, fixtures, normalization

**Files:**
- Create: `tests/fixtures/u25s/read_ok.json`
- Create: `tests/fixtures/u25s/read_missing_fields.json`
- Create: `tests/fixtures/u25s/read_malformed.json`
- Create: `tests/fixtures/u25s/read_session_expired.json`
- Create: `tests/test_adapter.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh`

- [ ] **Step 1: Write the sanitized fixtures**

`tests/fixtures/u25s/read_ok.json` (single line; values mirror the §5.1 research, no identifiers):

```json
{"mc_modem_main_state":"connected","network_type":"NR5G-SA","network_signalbar":"4","network_provider_fullname":"中国移动","Z5g_rsrp":"-68","ppp_status":"ipv4_ipv6_connected","simcard_active_slot_temp":"1","battery_exist":"1","battery_vol_percent":"82","battery_charging":"0"}
```

`tests/fixtures/u25s/read_missing_fields.json`:

```json
{"network_type":"NR5G-SA","battery_exist":"0"}
```

`tests/fixtures/u25s/read_malformed.json`:

```json
not json at all
```

`tests/fixtures/u25s/read_session_expired.json`:

```json
{"loginfo":"login"}
```

- [ ] **Step 2: Write the failing adapter test**

```sh
#!/bin/sh
set -eu
TEST_NAME=test_adapter
. ./tests/testlib.sh
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/http.sh"
. "$lib/session.sh"
. "$lib/adapter-zte-u25s.sh"

fixtures=./tests/fixtures/u25s
work=/tmp/zte-test-adapter.$$
mkdir -p "$work"
jar=$work/cookies.txt
printf x >"$jar"

# device flag mapping
assert_eq true "$(zte_adapter_bool 1)"
assert_eq false "$(zte_adapter_bool 0)"
assert_eq null "$(zte_adapter_bool '')"
assert_eq null "$(zte_adapter_bool maybe)"

# known-field gate
assert_success zte_adapter_has_any_field "$(cat "$fixtures/read_ok.json")"
assert_failure zte_adapter_has_any_field "$(cat "$fixtures/read_session_expired.json")"

# fetch with a warm cookie jar performs no login
zte_http_get() { cat "$fixtures/read_ok.json"; }
raw=$(zte_adapter_fetch 192.168.0.1 secret "$jar")
assert_eq "$(cat "$fixtures/read_ok.json")" "$raw"

# normalize maps every field
expected='{"online":true,"model":"U25S","modem_state":"connected","cellular":{"type":"NR5G-SA","provider":"中国移动","signalbar":"4","rsrp":"-68","ppp_status":"ipv4_ipv6_connected"},"sim":{"active_slot_raw":"1"},"battery":{"present":true,"percent":82,"charging":false},"missing":""}'
assert_eq "$expected" "$(zte_adapter_normalize "$raw")"

# missing fields become null and are reported in ZTE_READ_FIELDS order
out=$(zte_adapter_normalize "$(cat "$fixtures/read_missing_fields.json")")
case $out in
    *'"battery":{"present":false,"percent":null,"charging":null}'*) pass ;;
    *) fail "missing fields not nulled: $out" ;;
esac
case $out in
    *'"missing":"mc_modem_main_state,network_signalbar,network_provider_fullname,Z5g_rsrp,ppp_status,simcard_active_slot_temp,battery_vol_percent,battery_charging"'*) pass ;;
    *) fail "missing list wrong: $out" ;;
esac

# malformed response fails without any retry
get_calls=$work/get-calls
printf 0 >"$get_calls"
zte_http_get() {
    n=$(cat "$get_calls"); n=$((n + 1)); printf '%s' "$n" >"$get_calls"
    cat "$fixtures/read_malformed.json"
}
assert_failure zte_adapter_fetch 192.168.0.1 secret "$jar"
assert_eq 1 "$(cat "$get_calls")"

# stale session triggers exactly one relogin and one retry
printf 0 >"$get_calls"
logins=$work/logins
: >"$logins"
zte_session_login() { printf 'x\n' >>"$logins"; return 0; }
zte_http_get() {
    n=$(cat "$get_calls"); n=$((n + 1)); printf '%s' "$n" >"$get_calls"
    if [ "$n" -eq 1 ]; then
        cat "$fixtures/read_session_expired.json"
    else
        cat "$fixtures/read_ok.json"
    fi
}
raw2=$(zte_adapter_fetch 192.168.0.1 secret "$jar")
assert_eq "$(cat "$fixtures/read_ok.json")" "$raw2"
assert_eq 2 "$(cat "$get_calls")"
assert_eq 1 "$(wc -l <"$logins" | tr -d ' ')"

rm -rf "$work"
finish
```

Make it executable: `chmod +x tests/test_adapter.sh`.

- [ ] **Step 3: Verify RED**

Run: `./tests/test_adapter.sh`
Expected: failure — `zte_adapter_bool` etc. do not exist.

- [ ] **Step 4: Extend adapter-zte-u25s.sh**

Keep all existing content (`ZTE_ADAPTER_ID`, `ZTE_CAP_*`, `ZTE_READ_FIELDS`, `zte_adapter_capabilities_json`, `zte_adapter_framework_status_json`) and append:

```sh
# Map a device flag string to JSON true/false/null.
zte_adapter_bool() {
    case ${1-} in
        1|true|yes) printf 'true' ;;
        0|false|no) printf 'false' ;;
        *) printf 'null' ;;
    esac
}

# Succeed when the response contains at least one known read field.
zte_adapter_has_any_field() {
    case $1 in
        *'"mc_modem_main_state":'*|*'"network_type":'*|*'"network_signalbar":'*|\
        *'"network_provider_fullname":'*|*'"Z5g_rsrp":'*|*'"ppp_status":'*|\
        *'"simcard_active_slot_temp":'*|*'"battery_exist":'*|\
        *'"battery_vol_percent":'*|*'"battery_charging":'*) return 0 ;;
    esac
    return 1
}

# $1 host, $2 password, $3 cookie jar; prints raw flat device JSON.
# Logs in when the jar is empty; on a stale session (object without any
# known field) relogs in and retries exactly once.
zte_adapter_fetch() {
    host=$1 password=$2 jar=$3
    url="http://$host/goform/goform_get_cmd_process?cmd=$ZTE_READ_FIELDS&multi_data=1&isTest=false"

    if [ ! -s "$jar" ]; then
        zte_session_login "$host" "$password" "$jar" || return 1
    fi
    resp=$(zte_http_get "$url" "$jar") || return 1
    zte_json_is_flat_object "$resp" || return 1
    if ! zte_adapter_has_any_field "$resp"; then
        zte_session_login "$host" "$password" "$jar" || return 1
        resp=$(zte_http_get "$url" "$jar") || return 1
        zte_json_is_flat_object "$resp" || return 1
        zte_adapter_has_any_field "$resp" || return 1
    fi
    printf '%s\n' "$resp"
}

# $1 raw flat device JSON -> normalized device object on stdout.
# sim.active_slot_raw passes the firmware value through unmapped until the
# slot numbering is calibrated on the real device (see design doc 5.6).
zte_adapter_normalize() {
    raw=$1
    zte_json_is_flat_object "$raw" || return 1

    modem_state=$(zte_json_flat_get "$raw" mc_modem_main_state)
    net_type=$(zte_json_flat_get "$raw" network_type)
    signalbar=$(zte_json_flat_get "$raw" network_signalbar)
    provider=$(zte_json_flat_get "$raw" network_provider_fullname)
    rsrp=$(zte_json_flat_get "$raw" Z5g_rsrp)
    ppp=$(zte_json_flat_get "$raw" ppp_status)
    slot=$(zte_json_flat_get "$raw" simcard_active_slot_temp)
    present=$(zte_adapter_bool "$(zte_json_flat_get "$raw" battery_exist)")
    charging=$(zte_adapter_bool "$(zte_json_flat_get "$raw" battery_charging)")
    percent_raw=$(zte_json_flat_get "$raw" battery_vol_percent)
    if zte_is_uint "$percent_raw"; then percent=$percent_raw; else percent=null; fi

    missing=''
    old_ifs=$IFS
    IFS=,
    for field in $ZTE_READ_FIELDS; do
        IFS=$old_ifs
        case $raw in
            *"\"$field\":"*) ;;
            *) missing=${missing:+$missing,}$field ;;
        esac
        IFS=,
    done
    IFS=$old_ifs

    printf '{"online":true,"model":"%s","modem_state":"%s","cellular":{"type":"%s","provider":"%s","signalbar":"%s","rsrp":"%s","ppp_status":"%s"},"sim":{"active_slot_raw":"%s"},"battery":{"present":%s,"percent":%s,"charging":%s},"missing":"%s"}\n' \
        "$ZTE_ADAPTER_MODEL" \
        "$(zte_json_escape "$modem_state")" \
        "$(zte_json_escape "$net_type")" \
        "$(zte_json_escape "$provider")" \
        "$(zte_json_escape "$signalbar")" \
        "$(zte_json_escape "$rsrp")" \
        "$(zte_json_escape "$ppp")" \
        "$(zte_json_escape "$slot")" \
        "$present" "$percent" "$charging" \
        "$(zte_json_escape "$missing")"
}
```

- [ ] **Step 5: Verify GREEN**

Run: `./tests/test_adapter.sh`
Expected: `PASS test_adapter`.

- [ ] **Step 6: Commit**

```bash
git add tests/fixtures tests/test_adapter.sh package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh
git commit -m "feat: add U25S batch read with relogin retry and fixtures"
```

### Task 5: Snapshot composition and failure tracker

**Files:**
- Create: `tests/test_snapshot.sh`
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/snapshot.sh`

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
set -eu
TEST_NAME=test_snapshot
. ./tests/testlib.sh
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/json.sh"
. "$lib/snapshot.sh"

assert_eq '0:ok' "$(zte_failures_next 2 1 3)"
assert_eq '1:degraded' "$(zte_failures_next 0 0 3)"
assert_eq '2:degraded' "$(zte_failures_next 1 0 3)"
assert_eq '3:fail_safe' "$(zte_failures_next 2 0 3)"

dev='{"online":true,"model":"U25S","battery":{"present":true,"percent":82,"charging":false}}'
net='{"up":true,"l3_device":"eth2","ipv4":"192.168.0.2","gateway":"192.168.0.1","is_default_route":true}'
assert_eq '{"online":true,"model":"U25S","state":"ok","reason":"","device":'"$dev"',"network":'"$net"',"policy":{"state":"DISABLED","power_action":"KEEP"},"failures":0,"updated":1722345678}' \
    "$(zte_snapshot_compose ok '' "$dev" "$net" DISABLED KEEP 0 1722345678)"
assert_eq '{"online":false,"model":"U25S","state":"fail_safe","reason":"device_read_threshold_reached","device":null,"network":null,"policy":{"state":"unavailable","power_action":"none"},"failures":3,"updated":1722345679}' \
    "$(zte_snapshot_compose fail_safe device_read_threshold_reached '' '' unavailable none 3 1722345679)"
finish
```

Make it executable: `chmod +x tests/test_snapshot.sh`.

- [ ] **Step 2: Verify RED**

Run: `./tests/test_snapshot.sh`
Expected: failure — `snapshot.sh` does not exist.

- [ ] **Step 3: Implement snapshot.sh**

```sh
#!/bin/sh

# $1 current count, $2 ok(1/0), $3 threshold -> "<count>:<ok|degraded|fail_safe>"
zte_failures_next() {
    if [ "${2:-0}" = 1 ]; then
        printf '0:ok\n'
        return 0
    fi
    count=$(( ${1:-0} + 1 ))
    if [ "$count" -ge "${3:-3}" ]; then
        printf '%s:fail_safe\n' "$count"
    else
        printf '%s:degraded\n' "$count"
    fi
}

# Compose the status.json snapshot.
# $1 state, $2 reason, $3 device_json (or empty for null), $4 network_json
# (or empty for null), $5 policy_state, $6 power_action, $7 failures, $8 updated
zte_snapshot_compose() {
    state=$1 reason=$2 device=$3 network=$4
    pstate=$5 paction=$6 failures=$7 updated=$8

    if [ -n "$device" ]; then
        online=$(zte_json_flat_get "$device" online)
        model=$(zte_json_flat_get "$device" model)
        device_json=$device
    else
        online=false
        model=U25S
        device_json=null
    fi
    if [ -n "$network" ]; then network_json=$network; else network_json=null; fi

    printf '{"online":%s,"model":"%s","state":"%s","reason":"%s","device":%s,"network":%s,"policy":{"state":"%s","power_action":"%s"},"failures":%s,"updated":%s}\n' \
        "${online:-false}" "$(zte_json_escape "${model:-U25S}")" \
        "$(zte_json_escape "$state")" "$(zte_json_escape "$reason")" \
        "$device_json" "$network_json" \
        "$(zte_json_escape "$pstate")" "$(zte_json_escape "$paction")" \
        "$failures" "$updated"
}
```

- [ ] **Step 4: Verify GREEN**

Run: `./tests/test_snapshot.sh`
Expected: `PASS test_snapshot`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_snapshot.sh package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/snapshot.sh
git commit -m "feat: add snapshot composition and failure tracking"
```

### Task 6: netifd adapter

**Files:**
- Create: `tests/test_netifd.sh`
- Create: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/netifd-adapter.sh`

- [ ] **Step 1: Write the failing test**

Only the pure assembly is tested locally; `zte_netifd_collect` is a thin device-only wrapper verified during on-device acceptance:

```sh
#!/bin/sh
set -eu
TEST_NAME=test_netifd
. ./tests/testlib.sh
lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/json.sh"
. "$lib/netifd-adapter.sh"

assert_eq '{"up":true,"l3_device":"eth2","ipv4":"192.168.0.2","gateway":"192.168.0.1","is_default_route":true}' \
    "$(zte_netifd_json 1 eth2 192.168.0.2 192.168.0.1 1)"
assert_eq '{"up":false,"l3_device":"eth2","ipv4":"","gateway":"","is_default_route":false}' \
    "$(zte_netifd_json 0 eth2 '' '' 0)"
finish
```

Make it executable: `chmod +x tests/test_netifd.sh`.

- [ ] **Step 2: Verify RED**

Run: `./tests/test_netifd.sh`
Expected: failure — `netifd-adapter.sh` does not exist.

- [ ] **Step 3: Implement netifd-adapter.sh**

```sh
#!/bin/sh

# $1 up(1/0), $2 l3_device, $3 ipv4, $4 gateway, $5 is_default(1/0) -> JSON
zte_netifd_json() {
    up=false; [ "${1:-0}" = 1 ] && up=true
    def=false; [ "${5:-0}" = 1 ] && def=true
    printf '{"up":%s,"l3_device":"%s","ipv4":"%s","gateway":"%s","is_default_route":%s}\n' \
        "$up" "$(zte_json_escape "${2-}")" "$(zte_json_escape "${3-}")" \
        "$(zte_json_escape "${4-}")" "$def"
}

# $1 logical interface name; prints netifd JSON. Device-only: requires
# ubus, jsonfilter and ip. Kept thin on purpose; logic lives in zte_netifd_json.
zte_netifd_collect() {
    ifname=$1
    status=$(ubus call "network.interface.$ifname" status 2>/dev/null) || status=''
    if [ -z "$status" ]; then
        zte_netifd_json 0 '' '' '' 0
        return 0
    fi
    up_raw=$(printf '%s' "$status" | jsonfilter -e '@.up' 2>/dev/null)
    l3=$(printf '%s' "$status" | jsonfilter -e '@.l3_device' 2>/dev/null)
    ipv4=$(printf '%s' "$status" | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
    gw=$(printf '%s' "$status" | jsonfilter -e '@.route[0].nexthop' 2>/dev/null)
    up=0; [ "$up_raw" = true ] && up=1
    def=0
    if [ -n "$l3" ] && ip route show default 2>/dev/null | grep -q "dev $l3 "; then
        def=1
    fi
    zte_netifd_json "$up" "$l3" "$ipv4" "$gw" "$def"
}
```

- [ ] **Step 4: Verify GREEN**

Run: `./tests/test_netifd.sh`
Expected: `PASS test_netifd`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_netifd.sh package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/netifd-adapter.sh
git commit -m "feat: add netifd status adapter"
```

### Task 7: Daemon real polling loop

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd`
- Modify: `tests/test_structure.sh`

- [ ] **Step 1: Extend the failing structure test**

Append before `finish` in `tests/test_structure.sh`:

```sh
daemon="$backend/files/usr/sbin/zte-usb-wifi-managerd"
assert_file_contains "$daemon" 'json.sh'
assert_file_contains "$daemon" 'session.sh'
assert_file_contains "$daemon" 'snapshot.sh'
assert_file_contains "$daemon" 'netifd-adapter.sh'
assert_file_contains "$daemon" 'zte_adapter_fetch'
assert_file_contains "$daemon" 'zte_failures_next'
assert_file_contains "$daemon" 'zte_snapshot_compose'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/session.sh" 'goformId=LOGIN'
assert_file_contains "$backend/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh" 'multi_data=1'
assert_file_contains tests/fixtures/u25s/read_ok.json 'NR5G-SA'
assert_file_contains Makefile 'test_session.sh'
assert_file_contains Makefile 'test_adapter.sh'
```

- [ ] **Step 2: Verify RED**

Run: `./tests/test_structure.sh`
Expected: failures — daemon does not reference the new libs yet.

- [ ] **Step 3: Rewrite the daemon**

Replace the whole content of `package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd` with:

```sh
#!/bin/sh
set -eu

. /lib/functions.sh
. /usr/lib/zte-usb-wifi-manager/validation.sh
. /usr/lib/zte-usb-wifi-manager/json.sh
. /usr/lib/zte-usb-wifi-manager/http.sh
. /usr/lib/zte-usb-wifi-manager/session.sh
. /usr/lib/zte-usb-wifi-manager/policy.sh
. /usr/lib/zte-usb-wifi-manager/snapshot.sh
. /usr/lib/zte-usb-wifi-manager/netifd-adapter.sh
. /usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh

STATE_DIR=/var/run/zte-usb-wifi-manager
STATUS_FILE=$STATE_DIR/status.json
COOKIE_JAR=$STATE_DIR/cookies.txt

load_config() {
    config_load zte-usb-wifi-manager
    config_get enabled main enabled 1
    config_get poll_interval main poll_interval 30
    config_get failure_threshold main failure_threshold 3
    config_get host zte host 192.168.0.1
    config_get interface zte interface usbwan
    config_get netdev zte netdev eth2
    config_get credential_file zte credential_file /etc/zte-usb-wifi-manager/credentials
    config_get battery_enabled policy enabled 0
    config_get low_percent policy low_percent 70
    config_get high_percent policy high_percent 100

    zte_validate_host "$host" || {
        logger -t zte-usb-wifi-manager 'invalid device host'
        return 1
    }
    zte_validate_thresholds "$low_percent" "$high_percent" || {
        logger -t zte-usb-wifi-manager 'invalid battery thresholds'
        return 1
    }

    case $poll_interval in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$poll_interval" -ge 10 ]
}

write_status() {
    umask 077
    mkdir -p "$STATE_DIR"
    tmp_file=$STATUS_FILE.tmp.$$
    printf '%s\n' "$1" >"$tmp_file"
    mv "$tmp_file" "$STATUS_FILE"
}

collect_network() {
    if command -v ubus >/dev/null 2>&1 && command -v jsonfilter >/dev/null 2>&1; then
        zte_netifd_collect "$interface"
    else
        zte_netifd_json 0 "$netdev" '' '' 0
    fi
}

poll_once() {
    password=$(zte_read_password "$credential_file" 2>/dev/null) || password=''

    device_json=''
    ok=0
    if [ -n "$password" ]; then
        if raw=$(zte_adapter_fetch "$host" "$password" "$COOKIE_JAR" 2>/dev/null); then
            device_json=$(zte_adapter_normalize "$raw")
            ok=1
        fi
    fi

    if [ -z "$password" ]; then
        health=credentials_missing
    else
        next=$(zte_failures_next "$failures" "$ok" "$failure_threshold")
        failures=${next%%:*}
        health=${next##*:}
    fi

    case $health in
        ok) state=ok reason='' ;;
        credentials_missing) state=credentials_missing reason=credential_file_unreadable ;;
        degraded) state=degraded reason=device_read_failed ;;
        *) state=fail_safe reason=device_read_threshold_reached ;;
    esac

    network_json=$(collect_network)

    # Policy runs in monitoring mode only: no power backend exists yet,
    # so the decision is reported but never executed.
    policy_state=unavailable
    power_action=none
    if [ "$ok" = 1 ]; then
        percent=$(zte_json_flat_get "$device_json" percent)
        if zte_is_uint "$percent"; then
            decision=$(zte_policy_decide "$battery_enabled" 0 0 0 \
                "$percent" "$low_percent" "$high_percent" ON) || decision=''
            if [ -n "$decision" ]; then
                policy_state=${decision%%:*}
                power_action=${decision##*:}
            fi
        fi
    fi

    write_status "$(zte_snapshot_compose "$state" "$reason" "$device_json" \
        "$network_json" "$policy_state" "$power_action" "$failures" "$(date +%s)")"
}

main() {
    load_config
    failures=0
    while [ "$enabled" = 1 ]; do
        poll_once
        sleep "$poll_interval"
    done
}

main "$@"
```

Note: `zte_json_flat_get "$device_json" percent` matches the nested `"percent":82}` substring; a `null` percent extracts empty and disables policy evaluation, which is the intended behavior.

- [ ] **Step 4: Add the new suites to the Makefile**

In the root `Makefile`, replace the test loop's file list with:

```make
	for test_file in tests/test_validation.sh tests/test_policy.sh \
	    tests/test_json.sh tests/test_http.sh tests/test_session.sh \
	    tests/test_adapter.sh tests/test_snapshot.sh tests/test_netifd.sh \
	    tests/test_structure.sh; do \
```

- [ ] **Step 5: Verify GREEN**

Run: `make test`
Expected: all suites PASS including `test_structure`.

- [ ] **Step 6: Commit**

```bash
git add package/zte-usb-wifi-manager/files/usr/sbin/zte-usb-wifi-managerd tests/test_structure.sh Makefile
git commit -m "feat: poll U25S read-only status in the daemon"
```

### Task 8: LuCI overview renders real status

**Files:**
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`
- Modify: `tests/test_structure.sh`

- [ ] **Step 1: Extend the failing structure test**

Append after the existing view assertions in `tests/test_structure.sh`:

```sh
assert_file_contains "$view" 'status.device'
assert_file_contains "$view" 'is_default_route'
assert_file_contains "$view" 'battery'
assert_file_contains "$view" '仅监控'
```

- [ ] **Step 2: Verify RED**

Run: `./tests/test_structure.sh`
Expected: failures — the view does not render the new schema yet.

- [ ] **Step 3: Rewrite the view**

Replace the whole content of `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js` with:

```js
'use strict';
'require view';
'require rpc';
'require ui';

var callStatus = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'status',
	expect: {}
});

var callCapabilities = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'capabilities',
	expect: {}
});

var tabs = [
	{ id: 'overview', label: _('总览') },
	{ id: 'network', label: _('移动网络') },
	{ id: 'wifi', label: _('Wi-Fi 与设备') },
	{ id: 'traffic', label: _('流量') },
	{ id: 'sms', label: _('短信') },
	{ id: 'battery', label: _('电池与供电') },
	{ id: 'schedule', label: _('充电日程') },
	{ id: 'device', label: _('设备') },
	{ id: 'diagnostics', label: _('系统与诊断') },
	{ id: 'logs', label: _('日志') }
];

function renderTab(tab, active) {
	return E('button', {
		'class': 'cbi-button zte-tab' + (active ? ' cbi-button-positive' : ''),
		'data-tab': tab.id,
		'disabled': active ? '' : null
	}, tab.label);
}

function row(label, value) {
	return E('tr', {}, [
		E('td', { 'class': 'td left', 'style': 'width:33%' }, label),
		E('td', { 'class': 'td left' }, value)
	]);
}

function dash(value) {
	return (value === null || value === undefined || value === '') ? '—' : value;
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callStatus(), {}),
			L.resolveDefault(callCapabilities(), {})
		]);
	},

	render: function(data) {
		var status = data[0] || {};
		var dev = status.device || {};
		var cel = dev.cellular || {};
		var bat = dev.battery || {};
		var net = status.network || {};
		var pol = status.policy || {};

		var stateText = {
			ok: _('正常'),
			degraded: _('读取失败，重试中'),
			fail_safe: _('故障保护'),
			credentials_missing: _('缺少设备凭据')
		}[status.state] || _('未知');

		var batteryText = (bat.percent === null || bat.percent === undefined)
			? '—'
			: bat.percent + '%' + (bat.charging ? _('（充电中）') : '');

		var uplinkText = net.up
			? (net.l3_device || '') + ' ' + (net.ipv4 || '') +
				(net.is_default_route ? _('（默认出口）') : '')
			: _('未连接');

		var updated = status.updated
			? new Date(status.updated * 1000).toLocaleString()
			: '—';

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('中兴随身 WiFi 管理')),
			E('div', { 'class': 'zte-tabs' }, tabs.map(function(tab, index) {
				return renderTab(tab, index === 0);
			})),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('总览')),
				E('table', { 'class': 'table' }, [
					row(_('设备在线'), status.online ? _('在线') : _('离线')),
					row(_('后端状态'), stateText + (status.reason ? '（' + status.reason + '）' : '')),
					row(_('网络制式'), dash(cel.type)),
					row(_('运营商'), dash(cel.provider)),
					row(_('信号'), cel.rsrp ? 'RSRP ' + cel.rsrp + ' dBm' : dash(cel.signalbar)),
					row(_('电量'), batteryText),
					row(_('USB 上联'), uplinkText),
					row(_('电池策略'), dash(pol.state) + _('（仅监控，不控制供电）')),
					row(_('更新时间'), updated)
				]),
				E('div', { 'class': 'alert-message warning' },
					_('设备写接口尚未完成实机校准，当前版本仅开放只读能力。'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
```

- [ ] **Step 4: Verify GREEN**

Run: `./tests/test_structure.sh`
Expected: `PASS test_structure`.

- [ ] **Step 5: Commit**

```bash
git add luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js tests/test_structure.sh
git commit -m "feat: render real read-only status in the LuCI overview"
```

### Task 9: Docs and final verification

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Update README 当前状态**

Replace the `## 当前状态` bullet list in `README.md` with:

```markdown
仓库目前处于**只读管理阶段**：

- 已接入 U25S goform 登录（双重 SHA-256）与批量状态读取。
- 守护进程聚合设备、netifd 与电池策略监控状态，经 rpcd/ubus 提供给 LuCI 总览。
- 电池策略仅监控不执行，USB 供电控制（Power Adapter）尚未实现。
- 设备写操作仍未开放；号卡切换等待实机校准 `card_index` 语义后才会开放。

项目不会根据固件通用代码中的残留符号自行增加功能。产品能力以当前设备原生管理页面、实机验证结果和明确需求为准。
```

And remove the now-outdated roadmap item 1 / mark路线 progress: change the first two `## 路线` items to:

```markdown
1. ~~接入 U25S 只读登录和批量状态读取。~~（已完成）
2. 将实机响应固化为脱敏测试 fixture，替换当前合成 fixture。
```

- [ ] **Step 2: Update AGENTS.md architecture**

In `AGENTS.md`, replace the first architecture list item with:

```markdown
1. `zte-usb-wifi-managerd` (procd-managed, respawns) loads UCI config, validates
   it via `validation.sh`, polls the U25S through `session.sh` (goform login)
   and the adapter's batch read, runs `policy.sh` in monitoring mode, and
   writes a normalized JSON snapshot to
   `/var/run/zte-usb-wifi-manager/status.json` (atomic tmp-then-mv).
   HTTP goes through `http.sh`; failure tracking and snapshot assembly live in
   `snapshot.sh`; netifd reads live in `netifd-adapter.sh`.
```

- [ ] **Step 3: Full verification**

Run: `make check`
Expected: all test suites PASS, `sh -n` clean, JSON parse clean, secret scan clean, ShellCheck clean.

- [ ] **Step 4: Commit**

```bash
git add README.md AGENTS.md
git commit -m "docs: record read-only management phase"
```

---

## On-device acceptance (manual, after this plan lands)

These need the TR3000 + U25S and are NOT part of the automated tasks:

1. Create `/etc/zte-usb-wifi-manager/credentials` (mode `0600`) with `password=<device login password>`.
2. Install both packages, `service zte-usb-wifi-manager restart`, then `ubus call zte_usb_wifi status` shows real network/battery data.
3. Verify relogin: delete `/var/run/zte-usb-wifi-manager/cookies.txt`, wait one poll, status recovers.
4. Capture a real `multi_data=1` response, sanitize it (no IMEI/IMSI/ICCID/phone numbers), and replace the synthetic fixture values.
5. Calibrate `simcard_active_slot_temp` raw-value semantics and record the mapping decision in the adapter.
