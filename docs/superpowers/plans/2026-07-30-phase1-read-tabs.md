# Phase 1 Read Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the single LuCI overview into working read-only tabs and extend the normalized U25S snapshot with already-verified SIM and battery fields.

**Architecture:** The daemon continues to own device polling and atomically publish one cached snapshot. The LuCI view keeps a local active-tab state, renders only fields present in that snapshot, and never talks to the device or executes shell commands.

**Tech Stack:** POSIX Shell for the adapter, LuCI JavaScript View, dependency-light Shell and Node.js tests.

---

### Task 1: Extend the verified read contract

**Files:**
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh`
- Modify: `package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh`
- Modify: `tests/fixtures/u25s/read_ok.json`
- Modify: `tests/test_adapter.sh`

- [ ] **Step 1: Write the failing adapter assertions**

Extend `tests/fixtures/u25s/read_ok.json` with the verified fields:

```json
{
  "usim_esim_type": "physical",
  "battery_value": "4050",
  "battery_pers": "82",
  "battery_temperature_level": "normal"
}
```

Change the expected normalized object in `tests/test_adapter.sh` so `sim` and `battery` contain:

```json
"sim":{"active_slot_raw":"1","type":"physical"}
"battery":{"present":true,"percent":82,"charging":false,"value":"4050","pers":"82","temperature_level":"normal"}
```

Add assertions that a missing-field response yields `null` for all four new normalized values.

- [ ] **Step 2: Run the adapter test and verify RED**

Run:

```sh
./tests/test_adapter.sh
```

Expected: FAIL because the normalized object does not yet contain `sim.type` or the additional battery values.

- [ ] **Step 3: Add only the verified read fields**

Set the metadata read list to:

```sh
ZTE_READ_FIELDS='mc_modem_main_state,network_type,network_signalbar,network_provider_fullname,Z5g_rsrp,ppp_status,simcard_active_slot_temp,usim_esim_type,battery_exist,battery_vol_percent,battery_charging,battery_value,battery_pers,battery_temperature_level'
```

In `zte_adapter_normalize`, extract the four new strings with `zte_json_flat_get`, escape them with
`zte_json_escape`, and emit JSON `null` when the source field is absent. Do not interpret
`active_slot_raw` or turn the battery auxiliary values into numbers.

- [ ] **Step 4: Run adapter and full tests**

Run:

```sh
./tests/test_adapter.sh
make test
```

Expected: both commands PASS.

- [ ] **Step 5: Commit**

```sh
git add \
  package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh \
  package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh \
  tests/fixtures/u25s/read_ok.json \
  tests/test_adapter.sh
git commit -m "feat: extend verified U25S read status"
```

### Task 2: Add real tab navigation

**Files:**
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`
- Modify: `tests/test_luci.js`

- [ ] **Step 1: Write failing navigation tests**

Add helpers to `tests/test_luci.js` that collect nodes with class `zte-tab` and `zte-tab-panel`.
Add tests that:

1. render exactly ten tab buttons;
2. render only the overview panel initially;
3. call the mobile-network tab button's `click` handler;
4. observe a replacement tree containing the `network` panel;
5. preserve the selected tab after a poll refresh.

Use this status fixture:

```js
{
  online: true,
  device: {
    modem_state: 'connected',
    cellular: {
      type: 'NR5G-SA',
      provider: '中国移动',
      signalbar: '4',
      rsrp: '-68',
      ppp_status: 'ipv4_ipv6_connected'
    }
  },
  network: {
    up: true,
    l3_device: 'eth2',
    ipv4: '192.168.0.2',
    gateway: '192.168.0.1',
    is_default_route: false
  }
}
```

- [ ] **Step 2: Run the LuCI test and verify RED**

Run:

```sh
node tests/test_luci.js
```

Expected: FAIL because tabs do not have click handlers and no tab panel identity is rendered.

- [ ] **Step 3: Implement active-tab rendering**

Add closure state:

```js
var activeTab = 'overview';
```

Change tab buttons to include:

```js
'data-tab': tab.id,
'aria-selected': active ? 'true' : 'false',
'click': onSelect
```

Extract a `renderPanel(tabId, status, capabilities)` function. Each panel root must contain:

```js
{
  'class': 'cbi-section zte-tab-panel',
  'data-panel': tabId
}
```

The view's `render` function owns one `replace(next)` helper. A tab click changes `activeTab` and
replaces the root with `renderStatus(currentData, activeTab, selectTab)`. Poll refresh updates
`currentData` but does not reset `activeTab`.

- [ ] **Step 4: Run the LuCI test**

Run:

```sh
node tests/test_luci.js
```

Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add \
  luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js \
  tests/test_luci.js
git commit -m "feat: add LuCI tab navigation"
```

### Task 3: Render panels from current real data

**Files:**
- Modify: `luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js`
- Modify: `tests/test_luci.js`

- [ ] **Step 1: Write failing panel tests**

Add one test for each panel and assert these real rows:

```text
overview: 设备型号, 设备在线, 后端状态, 状态快照时间
network: 网络制式, 运营商, 信号, PPP 状态, USB 上联, IPv4, 网关, 默认出口
wifi: 数据状态
traffic: 数据状态
sms: 数据状态
battery: 电池存在, 电量, 充电状态, 电池值, 电池百分比原值, 温度级别
schedule: 功能状态
device: 设备型号, Modem 状态, SIM 类型, 活动卡槽原始值
diagnostics: 后端状态, 失败次数, 缺失字段
logs: 数据状态
```

For Wi‑Fi, traffic, SMS and logs, assert the panel says `当前快照尚未提供此模块数据` rather
than displaying invented values. For schedule, assert `阶段 3 未启用`.

- [ ] **Step 2: Run the LuCI test and verify RED**

Run:

```sh
node tests/test_luci.js
```

Expected: FAIL on the first missing panel row.

- [ ] **Step 3: Implement minimal panel renderers**

Add focused renderer functions:

```js
renderOverview(status, capabilities)
renderNetwork(status)
renderUnavailableModule()
renderBattery(status)
renderSchedule()
renderDevice(status, capabilities)
renderDiagnostics(status)
```

Render only normalized snapshot fields. Keep the existing backend-error and stale-snapshot banners
outside the active panel so they remain visible on every tab.

- [ ] **Step 4: Run tests and lint**

Run:

```sh
node tests/test_luci.js
make check
git diff --check
```

Expected: all commands PASS.

- [ ] **Step 5: Commit**

```sh
git add \
  luci-app-zte-usb-wifi-manager/htdocs/luci-static/resources/view/zte-usb-wifi-manager/index.js \
  tests/test_luci.js
git commit -m "feat: render phase 1 status panels"
```

### Task 4: Update phase status documentation

**Files:**
- Modify: `README.md`
- Modify: `tests/test_structure.sh`

- [ ] **Step 1: Write the failing structure assertions**

Require README to state that tab navigation and the verified SIM/battery details are implemented,
while Wi‑Fi, traffic, SMS and logs still wait for verified fixtures.

- [ ] **Step 2: Run structure test and verify RED**

Run:

```sh
./tests/test_structure.sh
```

Expected: FAIL because README lacks the new implementation status.

- [ ] **Step 3: Update README**

Document the exact completed fields and retain the rule that no write capability is enabled.

- [ ] **Step 4: Verify the slice**

Run:

```sh
make check
git diff --check
```

Expected: all suites PASS and no whitespace errors.

- [ ] **Step 5: Commit**

```sh
git add README.md tests/test_structure.sh
git commit -m "docs: record phase 1 tab progress"
```
