'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const viewPath = path.join(
	__dirname,
	'..',
	'luci-app-zte-usb-wifi-manager',
	'htdocs',
	'luci-static',
	'resources',
	'view',
	'zte-usb-wifi-manager',
	'index.js'
);
const source = fs.readFileSync(viewPath, 'utf8');

function E(tag, attrs, children) {
	return { tag: tag, attrs: attrs || {}, children: children };
}

const rpcBehavior = {
	status: function() { return Promise.resolve({}); },
	sms_messages: function() { return Promise.resolve({ available: false, reason: 'not_loaded', items: [] }); },
	capabilities: function() { return Promise.resolve({}); },
	logs: function() { return Promise.resolve({ events: [] }); },
	credential_status: function() { return Promise.resolve({ configured: false }); },
	charging_settings: function() { return Promise.resolve({ enabled: false, low_percent: 30, high_percent: 80 }); },
	set_charging_settings: function() { return Promise.resolve({ ok: true, enabled: false, low_percent: 30, high_percent: 80 }); },
	set_credentials: function() { return Promise.resolve({ ok: true, configured: true }); },
	clear_credentials: function() { return Promise.resolve({ ok: true, configured: false }); },
	cellular_action: function() { return Promise.resolve({ ok: true, operation_id: 'op-test' }); },
	wifi_action: function() { return Promise.resolve({ ok: true, operation_id: 'op-test' }); },
	traffic_action: function() { return Promise.resolve({ ok: true, operation_id: 'op-test' }); },
	sms_action: function() { return Promise.resolve({ ok: true, operation_id: 'op-test' }); },
	device_action: function() { return Promise.resolve({ ok: true, operation_id: 'op-test' }); },
	power_action: function() { return Promise.resolve({ ok: true, operation_id: 'op-test' }); },
	operation_status: function() { return Promise.resolve({ operation_id: 'op-test', state: 'queued' }); }
};
const rpcSpecs = {};
const pollEntries = [];

const app = new Function('view', 'rpc', 'poll', '_', 'E', 'L', source)(
	{ extend: function(spec) { return spec; } },
	{ declare: function(spec) {
		rpcSpecs[spec.method] = spec;
		return function() {
			return rpcBehavior[spec.method].apply(null, arguments);
		};
	} },
	{ add: function(callback, interval) {
		pollEntries.push({ callback: callback, interval: interval });
		return true;
	} },
	function(message) { return message; },
	E,
	{ resolveDefault: function(promise) { return promise; } }
);

function text(node) {
	if (node === null || node === undefined)
		return '';
	if (Array.isArray(node))
		return node.map(text).join('');
	if (typeof node === 'string' || typeof node === 'number')
		return String(node);
	if (typeof node === 'object' && Object.prototype.hasOwnProperty.call(node, 'children'))
		return text(node.children);
	return '';
}

function collectRows(node, rows) {
	if (!node || typeof node !== 'object')
		return;
	if (Array.isArray(node)) {
		node.forEach(function(child) { collectRows(child, rows); });
		return;
	}
	if (node.attrs && node.attrs['class'] === 'cbi-value') {
		rows.push({
			title: text(node.children[0]),
			value: text(node.children[1]),
			titleTag: node.children[0].tag
		});
	}
	collectRows(node.children, rows);
}

function render(status, smsMessages, capabilities) {
	return app.render([
		{ ok: true, value: status },
		{ ok: true, value: capabilities || {} },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: false } },
		{ ok: true, value: smsMessages || { available: false, reason: 'not_loaded', items: [] } },
		{ ok: true, value: { enabled: false, low_percent: 30, high_percent: 80 } }
	]);
}

function rowValue(tree, title) {
	const rows = [];
	collectRows(tree, rows);
	const match = rows.find(function(row) { return row.title === title; });
	assert.ok(match, 'missing rendered row: ' + title);
	return match.value;
}

function collectByClass(node, className, matches) {
	if (!node || typeof node !== 'object')
		return;
	if (Array.isArray(node)) {
		node.forEach(function(child) { collectByClass(child, className, matches); });
		return;
	}
	if (node.attrs && String(node.attrs['class'] || '').split(/\s+/).includes(className))
		matches.push(node);
	collectByClass(node.children, className, matches);
}

function nodesByClass(tree, className) {
	const matches = [];
	collectByClass(tree, className, matches);
	return matches;
}

function collectByTag(node, tagName, matches) {
	if (!node || typeof node !== 'object')
		return;
	if (Array.isArray(node)) {
		node.forEach(function(child) { collectByTag(child, tagName, matches); });
		return;
	}
	if (node.tag === tagName)
		matches.push(node);
	collectByTag(node.children, tagName, matches);
}

function nodesByTag(tree, tagName) {
	const matches = [];
	collectByTag(tree, tagName, matches);
	return matches;
}

function tabById(tree, tabId) {
	return nodesByClass(tree, 'zte-tab').find(function(tab) {
		return tab.attrs['data-tab'] === tabId;
	});
}

function deferred() {
	let resolve;
	let reject;
	const promise = new Promise(function(resolvePromise, rejectPromise) {
		resolve = resolvePromise;
		reject = rejectPromise;
	});
	return { promise: promise, resolve: resolve, reject: reject };
}

function renderPanel(status, tabId, smsMessages, capabilities) {
	let current = render(status, smsMessages, capabilities);
	const parent = {
		replaceChild: function(next) {
			current = next;
			next.parentNode = parent;
		}
	};
	current.parentNode = parent;
	const tab = tabById(current, tabId);
	assert.ok(tab, 'missing tab: ' + tabId);
	tab.attrs.click();
	assert.strictEqual(
		nodesByClass(current, 'zte-tab-panel')[0].attrs['data-panel'],
		tabId
	);
	return current;
}

let count = 0;
let failures = 0;
let testChain = Promise.resolve();

function test(name, fn) {
	count += 1;
	testChain = testChain.then(function() {
		return fn();
	}).catch(function(error) {
		failures += 1;
		console.error('FAIL test_luci: ' + name + ': ' + error.message);
	});
}

test('renders online true, false, and unknown distinctly', function() {
	assert.strictEqual(rowValue(render({ online: true }), '设备在线'), '在线');
	assert.strictEqual(rowValue(render({ online: false }), '设备在线'), '离线');
	assert.strictEqual(rowValue(render({}), '设备在线'), '—');
});

test('renders network up true, false, and unknown distinctly', function() {
	assert.strictEqual(
		rowValue(render({ network: { up: true, l3_device: 'eth2' } }), 'USB 上联'),
		'已连接 (eth2)'
	);
	assert.strictEqual(rowValue(render({ network: { up: false } }), 'USB 上联'), '未连接');
	assert.strictEqual(rowValue(render({ network: {} }), 'USB 上联'), '—');
});

test('renders safely with missing nested objects', function() {
	assert.doesNotThrow(function() { render({}); });
	assert.strictEqual(rowValue(render({ device: {}, network: {}, policy: {} }), '信号'), '—');
});

test('marks retained device data stale for every non-ok backend state', function() {
	['degraded', 'fail_safe', 'credentials_missing', 'authentication_failed', 'planned_off'].forEach(function(state) {
		const value = rowValue(render({ state: state, device: { model: 'U25S' } }), '后端状态');
		assert.ok(
			value.indexOf('设备数据来自最近一次成功读取') !== -1,
			state + ' does not mark retained device data stale'
		);
	});
});

test('labels rejected device credentials explicitly', function() {
	assert.strictEqual(
		rowValue(render({ state: 'authentication_failed' }), '后端状态'),
		'设备认证失败'
	);
});

test('labels planned hardware power-off explicitly', function() {
	assert.strictEqual(
		rowValue(render({ state: 'planned_off' }), '后端状态'),
		'计划断电'
	);
});

test('does not claim stale device data when no device is retained', function() {
	const value = rowValue(render({ state: 'fail_safe' }), '后端状态');
	assert.strictEqual(value.indexOf('设备数据来自最近一次成功读取'), -1);
});

test('labels the timestamp as snapshot time', function() {
	assert.notStrictEqual(rowValue(render({ updated: 1722345678 }), '状态快照时间'), '—');
});

test('localizes framework_ready and handles non-string states', function() {
	assert.strictEqual(rowValue(render({ state: 'framework_ready' }), '后端状态'), '框架已就绪');
	assert.strictEqual(rowValue(render({ state: {} }), '后端状态'), '—');
});

test('uses a non-label element for row titles', function() {
	const rows = [];
	collectRows(render({}), rows);
	assert.ok(rows.length > 0);
	rows.forEach(function(row) {
		assert.notStrictEqual(row.titleTag, 'label');
	});
});

test('preserves independent RPC failures for rendering', async function() {
	rpcBehavior.status = function() { return Promise.reject(new Error('status unavailable')); };
	rpcBehavior.capabilities = function() { return Promise.resolve({ model: 'U25S' }); };
	rpcBehavior.logs = function() { return Promise.resolve({ events: [] }); };
	const data = await app.load();
	assert.strictEqual(data[0].ok, false);
	assert.strictEqual(data[1].ok, true);
	assert.strictEqual(data[1].value.model, 'U25S');
	assert.strictEqual(data[2].ok, true);
});

test('declares ubus calls as rejecting and rejects numeric error replies', async function() {
	assert.strictEqual(rpcSpecs.status.reject, true);
	assert.strictEqual(rpcSpecs.sms_messages.reject, true);
	assert.strictEqual(rpcSpecs.capabilities.reject, true);
	assert.strictEqual(rpcSpecs.logs.reject, true);
	assert.strictEqual(rpcSpecs.credential_status.reject, true);
	assert.strictEqual(rpcSpecs.charging_settings.reject, true);
	assert.strictEqual(rpcSpecs.set_charging_settings.reject, true);
	assert.deepStrictEqual(rpcSpecs.set_charging_settings.params,
		[ 'enabled', 'low_percent', 'high_percent' ]);
	assert.strictEqual(rpcSpecs.set_credentials.reject, true);
	assert.deepStrictEqual(rpcSpecs.set_credentials.params, [ 'password' ]);
	assert.strictEqual(rpcSpecs.clear_credentials.reject, true);
	assert.strictEqual(rpcSpecs.clear_credentials.params, undefined);
	assert.strictEqual(rpcSpecs.cellular_action.reject, true);
	assert.deepStrictEqual(rpcSpecs.cellular_action.params,
		[ 'action', 'target', 'confirm', 'apn', 'auth', 'username', 'password', 'mode' ]);
	assert.deepStrictEqual(rpcSpecs.wifi_action.params,
		[ 'action', 'enabled', 'band', 'ssid', 'security', 'password', 'channel' ]);
	assert.deepStrictEqual(rpcSpecs.traffic_action.params,
		[ 'action', 'enabled', 'limit_bytes', 'alert_percent', 'cycle_day', 'disconnect', 'confirm' ]);
	assert.deepStrictEqual(rpcSpecs.sms_action.params,
		[ 'action', 'message_id', 'number', 'content', 'confirm' ]);
	assert.deepStrictEqual(rpcSpecs.device_action.params, [ 'action', 'confirm' ]);
	assert.strictEqual(rpcSpecs.device_action.reject, true);
	assert.deepStrictEqual(rpcSpecs.power_action.params, [ 'action', 'mode' ]);
	assert.strictEqual(rpcSpecs.power_action.reject, true);
	assert.strictEqual(rpcSpecs.operation_status.reject, true);
	assert.deepStrictEqual(rpcSpecs.operation_status.params, [ 'operation_id' ]);
	rpcBehavior.status = function() { return Promise.resolve(4); };
	rpcBehavior.capabilities = function() { return Promise.resolve({}); };
	rpcBehavior.logs = function() { return Promise.resolve({ events: [] }); };
	const data = await app.load();
	assert.strictEqual(data[0].ok, false);
});

test('capability-gates every semantic write form', function() {
	const capabilities = {
		cellular_write: true, wifi_write: true, traffic_write: true,
		sms_write: true, sim_switch: true, device_reboot: true, device_shutdown: true,
		power_supply_write: true
	};
	let tree = renderPanel({}, 'network', null, capabilities);
	assert.ok(text(tree).indexOf('保存 APN') !== -1);
	assert.ok(text(tree).indexOf('保存连接模式') !== -1);
	tree = renderPanel({}, 'wifi', null, capabilities);
	assert.ok(text(tree).indexOf('保存 Wi-Fi 设置') !== -1);
	tree = renderPanel({}, 'traffic', null, capabilities);
	assert.ok(text(tree).indexOf('保存流量套餐') !== -1);
	assert.ok(text(tree).indexOf('清零流量统计') !== -1);
	tree = renderPanel({}, 'sms', null, capabilities);
	assert.ok(text(tree).indexOf('发送短信') !== -1);
	assert.ok(text(tree).indexOf('标记已读') !== -1);
	assert.ok(text(tree).indexOf('删除短信') !== -1);
	tree = renderPanel({}, 'device', null, capabilities);
	assert.ok(text(tree).indexOf('重启 U25S') !== -1);
	assert.ok(text(tree).indexOf('关闭 U25S') !== -1);
	assert.ok(text(tree).indexOf('智能充电与电源直供') !== -1);

	assert.strictEqual(text(renderPanel({}, 'network')).indexOf('保存 APN'), -1);
	assert.strictEqual(text(renderPanel({}, 'wifi')).indexOf('保存 Wi-Fi 设置'), -1);
	assert.strictEqual(text(renderPanel({}, 'traffic')).indexOf('保存流量套餐'), -1);
	assert.strictEqual(text(renderPanel({}, 'sms')).indexOf('发送短信'), -1);
	assert.strictEqual(text(renderPanel({}, 'device')).indexOf('重启 U25S'), -1);
});

test('submits U30 power-supply mode through the dedicated RPC method', async function() {
	const calls = [];
	rpcBehavior.power_action = function() {
		calls.push(Array.from(arguments));
		return Promise.resolve({ ok: true, operation_id: 'op-power' });
	};
	let tree = renderPanel({
		state: 'ok', model: 'U30 Pro',
		device: {
			model: 'U30 Pro', battery: { percent: 85, charging: false },
			power_supply: { mode_raw: '1', direct_supply: true }
		}
	}, 'device', null, { model: 'U30 Pro', power_supply_write: true });
	const charge = nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '开始充电';
	});
	const direct = nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '切换电源直供';
	});
	assert.ok(charge);
	assert.ok(direct);
	await charge.attrs.click();
	assert.deepStrictEqual(calls[0], [ 'set_power_supply_mode', 'charging' ]);

	// Re-render after the first queued operation so the second semantic mode
	// can be checked independently.
	tree = renderPanel({
		state: 'ok', model: 'U30 Pro',
		device: { model: 'U30 Pro', battery: { percent: 85 },
			power_supply: { mode_raw: '0', direct_supply: false } }
	}, 'device', null, { model: 'U30 Pro', power_supply_write: true });
	const directAgain = nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '切换电源直供';
	});
	assert.ok(directAgain);
});

test('renders, validates, and saves U30 smart charging settings', async function() {
	pollEntries.length = 0;
	const calls = [];
	rpcBehavior.set_charging_settings = function() {
		calls.push(Array.from(arguments));
		return Promise.resolve({
			ok: true, enabled: true, low_percent: 35, high_percent: 75
		});
	};
	let current = app.render([
		{ ok: true, value: { state: 'ok', model: 'U30 Pro', device: { model: 'U30 Pro' } } },
		{ ok: true, value: { model: 'U30 Pro', power_supply_write: false } },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: false } },
		{ ok: true, value: { available: false, items: [] } },
		{ ok: true, value: { enabled: false, low_percent: 30, high_percent: 80 } }
	]);
	const parent = {
		replaceChild: function(next) {
			current = next;
			next.parentNode = parent;
		}
	};
	current.parentNode = parent;
	tabById(current, 'device').attrs.click();
	assert.ok(text(current).indexOf('智能充电设置') !== -1);
	assert.ok(text(current).indexOf('不会关闭 USB 数据连接') !== -1);
	let enabled = nodesByTag(current, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'smart-charge-enabled';
	});
	let low = nodesByTag(current, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'smart-charge-low';
	});
	let high = nodesByTag(current, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'smart-charge-high';
	});
	assert.ok(enabled);
	assert.strictEqual(enabled.checked, false);
	assert.strictEqual(low.value, '30');
	assert.strictEqual(high.value, '80');
	enabled.checked = true;
	low.value = '35';
	high.value = '75';
	await nodesByTag(current, 'button').find(function(node) {
		return text(node) === '保存智能充电设置';
	}).attrs.click();
	assert.deepStrictEqual(calls[0], [ true, 35, 75 ]);
	assert.ok(text(current).indexOf('智能充电设置已保存') !== -1);

	tabById(current, 'device').attrs.click();
	low = nodesByTag(current, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'smart-charge-low';
	});
	high = nodesByTag(current, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'smart-charge-high';
	});
	low.value = '80';
	high.value = '75';
	await nodesByTag(current, 'button').find(function(node) {
		return text(node) === '保存智能充电设置';
	}).attrs.click();
	assert.strictEqual(calls.length, 1);
	assert.ok(text(current).indexOf('低电量阈值必须') !== -1);
});

test('requires independent confirmation and submits device controls', async function() {
	pollEntries.length = 0;
	const calls = [];
	rpcBehavior.device_action = function() {
		calls.push(Array.from(arguments));
		return Promise.resolve({ ok: true, operation_id: 'op-device' });
	};
	let tree = renderPanel({}, 'device', null,
		{ device_reboot: true, device_shutdown: true });
	const reboot = nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '重启 U25S';
	});
	const confirmations = nodesByTag(tree, 'input').filter(function(node) {
		return node.attrs.type === 'checkbox' &&
			String(node.attrs['data-purpose'] || '').indexOf('device-') === 0;
	});
	assert.strictEqual(confirmations.length, 2);
	await reboot.attrs.click();
	assert.strictEqual(calls.length, 0);

	tree = renderPanel({}, 'device', null,
		{ device_reboot: true, device_shutdown: true });
	const rebootConfirmation = nodesByTag(tree, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'device-reboot-confirm';
	});
	rebootConfirmation.checked = true;
	await nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '重启 U25S';
	}).attrs.click();
	assert.deepStrictEqual(calls[0], [ 'reboot_device', true ]);

	tree = renderPanel({}, 'device', null,
		{ device_reboot: true, device_shutdown: true });
	nodesByTag(tree, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'device-reboot-confirm';
	}).checked = true;
	await nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '关闭 U25S';
	}).attrs.click();
	assert.strictEqual(calls.length, 1, 'reboot confirmation must not authorize shutdown');

	tree = renderPanel({}, 'device', null,
		{ device_reboot: true, device_shutdown: true });
	nodesByTag(tree, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'device-shutdown-confirm';
	}).checked = true;
	await nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '关闭 U25S';
	}).attrs.click();
	assert.deepStrictEqual(calls[1], [ 'shutdown_device', true ]);

	assert.strictEqual(text(renderPanel({}, 'device', null,
		{ device_reboot: true })).indexOf('关闭 U25S'), -1);
	assert.strictEqual(text(renderPanel({}, 'device', null,
		{ device_shutdown: true })).indexOf('重启 U25S'), -1);
});

test('submits normalized requests for each write family', async function() {
	pollEntries.length = 0;
	const calls = [];
	rpcBehavior.cellular_action = function() {
		calls.push([ 'cellular' ].concat(Array.from(arguments)));
		return Promise.resolve({ ok: true, operation_id: 'op-cellular' });
	};
	rpcBehavior.wifi_action = function() {
		calls.push([ 'wifi' ].concat(Array.from(arguments)));
		return Promise.resolve({ ok: true, operation_id: 'op-wifi' });
	};
	rpcBehavior.traffic_action = function() {
		calls.push([ 'traffic' ].concat(Array.from(arguments)));
		return Promise.resolve({ ok: true, operation_id: 'op-traffic' });
	};
	rpcBehavior.sms_action = function() {
		calls.push([ 'sms' ].concat(Array.from(arguments)));
		return Promise.resolve({ ok: true, operation_id: 'op-sms' });
	};

	let tree = renderPanel({}, 'network', null, { cellular_write: true });
	nodesByTag(tree, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'apn';
	}).value = 'internet';
	await nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '保存 APN';
	}).attrs.click();
	assert.deepStrictEqual(calls[0].slice(0, 7),
		[ 'cellular', 'set_apn', undefined, undefined, 'internet', 'none', undefined ]);

	tree = renderPanel({}, 'wifi', null, { wifi_write: true });
	nodesByTag(tree, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'wifi-ssid';
	}).value = 'Fixture WiFi';
	nodesByTag(tree, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'wifi-password';
	}).value = 'fixture-pass';
	await nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '保存 Wi-Fi 设置';
	}).attrs.click();
	assert.deepStrictEqual(calls[1].slice(0, 8),
		[ 'wifi', 'set_wifi', true, '2g', 'Fixture WiFi', 'wpa2_psk', 'fixture-pass', 'auto' ]);

	tree = renderPanel({}, 'traffic', null, { traffic_write: true });
	await nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '保存流量套餐';
	}).attrs.click();
	assert.deepStrictEqual(calls[2].slice(0, 4),
		[ 'traffic', 'set_traffic_plan', false, undefined ]);

	tree = renderPanel({}, 'sms', null, { sms_write: true });
	nodesByTag(tree, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'sms-number';
	}).value = '+12025550123';
	nodesByTag(tree, 'textarea')[0].value = 'fixture message';
	await nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '发送短信';
	}).attrs.click();
	assert.deepStrictEqual(calls[3].slice(0, 5),
		[ 'sms', 'send_sms', undefined, '+12025550123', 'fixture message' ]);
});

test('keeps U30 Wi-Fi writes fixed to 2.4 GHz and automatic channel', async function() {
	const calls = [];
	rpcBehavior.wifi_action = function() {
		calls.push(Array.from(arguments));
		return Promise.resolve({ ok: true, operation_id: 'op-u30-wifi' });
	};
	const tree = renderPanel({
		device: { adapter: 'zte_u30', model: 'U30 Pro', wifi: { enabled: true } }
	}, 'wifi', null, { adapter: 'zte_u30', wifi_write: true });
	assert.strictEqual(text(tree).indexOf('5 GHz SSID'), -1);
	assert.ok(text(tree).indexOf('U30 仅支持 2.4 GHz，信道固定为自动') !== -1);
	assert.strictEqual(nodesByTag(tree, 'select').some(function(node) {
		return node.attrs['data-purpose'] === 'wifi-band';
	}), false);
	assert.strictEqual(nodesByTag(tree, 'input').some(function(node) {
		return node.attrs['data-purpose'] === 'wifi-channel';
	}), false);
	nodesByTag(tree, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'wifi-ssid';
	}).value = 'U30 Fixture';
	nodesByTag(tree, 'input').find(function(node) {
		return node.attrs['data-purpose'] === 'wifi-password';
	}).value = 'fixture-pass';
	await nodesByTag(tree, 'button').find(function(node) {
		return text(node) === '保存 Wi-Fi 设置';
	}).attrs.click();
	assert.deepStrictEqual(calls[0],
		[ 'set_wifi', true, '2g', 'U30 Fixture', 'wpa2_psk', 'fixture-pass', 'auto' ]);
});

test('shows U30 Wi-Fi constraints while writes remain disabled', function() {
	const tree = renderPanel({
		device: { adapter: 'zte_u30', model: 'U30 Pro', wifi: { enabled: true } }
	}, 'wifi', null, { adapter: 'zte_u30', wifi_write: false });
	assert.ok(text(tree).indexOf('U30 仅支持 2.4 GHz，信道固定为自动') !== -1);
	assert.strictEqual(text(tree).indexOf('保存 Wi-Fi 设置'), -1);
});

test('renders a write-only U25S password entry and credential state', function() {
	const tree = render({ state: 'ok' });
	const passwordInput = nodesByTag(tree, 'input').find(function(input) {
		return input.attrs.type === 'password';
	});
	assert.ok(passwordInput, 'missing password input');
	assert.strictEqual(passwordInput.attrs.autocomplete, 'new-password');
	assert.ok(text(tree).indexOf('设备登录') !== -1);
	assert.ok(text(tree).indexOf('保存登录凭据') !== -1);
	assert.ok(text(tree).indexOf('未保存管理密码') !== -1);
	assert.strictEqual(source.indexOf('localStorage'), -1);
	assert.strictEqual(source.indexOf('sessionStorage'), -1);
});

test('submits and clears the password without claiming authentication', async function() {
	let submittedPassword = null;
	rpcBehavior.set_credentials = function(password) {
		submittedPassword = password;
		return Promise.resolve({ ok: true, configured: true });
	};
	let current = app.render([
		{ ok: true, value: { state: 'ok' } },
		{ ok: true, value: {} },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: false } }
	]);
	const parent = {
		replaceChild: function(next) {
			current = next;
			next.parentNode = parent;
		}
	};
	current.parentNode = parent;
	const passwordInput = nodesByTag(current, 'input').find(function(input) {
		return input.attrs.type === 'password';
	});
	const saveButton = nodesByTag(current, 'button').find(function(button) {
		return text(button) === '保存登录凭据';
	});
	assert.ok(passwordInput);
	assert.ok(saveButton);
	passwordInput.value = 'temporary browser value';
	await saveButton.attrs.click();
	assert.strictEqual(submittedPassword, 'temporary browser value');
	assert.strictEqual(passwordInput.value, '');
	assert.ok(text(current).indexOf('密码已保存，等待设备需要认证时使用') !== -1);
	assert.strictEqual(text(current).indexOf('登录成功'), -1);
});

test('requires confirmation before clearing the saved local credential', async function() {
	let clearCalls = 0;
	rpcBehavior.clear_credentials = function() {
		clearCalls += 1;
		return Promise.resolve({ ok: true, configured: false });
	};
	let current = app.render([
		{ ok: true, value: { state: 'ok' } },
		{ ok: true, value: {} },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: true } }
	]);
	const parent = {
		replaceChild: function(next) {
			current = next;
			next.parentNode = parent;
		}
	};
	current.parentNode = parent;
	let confirmation = nodesByTag(current, 'input').find(function(input) {
		return input.attrs['data-purpose'] === 'clear-credentials';
	});
	let clearButton = nodesByTag(current, 'button').find(function(button) {
		return text(button) === '清除本地凭据';
	});
	assert.ok(confirmation);
	assert.ok(clearButton);
	await clearButton.attrs.click();
	assert.strictEqual(clearCalls, 0);
	assert.ok(text(current).indexOf('请先确认清除路由器中保存的 U25S 管理密码') !== -1);
	confirmation = nodesByTag(current, 'input').find(function(input) {
		return input.attrs['data-purpose'] === 'clear-credentials';
	});
	clearButton = nodesByTag(current, 'button').find(function(button) {
		return text(button) === '清除本地凭据';
	});
	confirmation.checked = true;
	await clearButton.attrs.click();
	assert.strictEqual(clearCalls, 1);
	assert.ok(text(current).indexOf('本地管理凭据已清除') !== -1);
	assert.ok(text(current).indexOf('未保存管理密码') !== -1);
});

test('gates SIM switching by capability and reports asynchronous completion', async function() {
	pollEntries.length = 0;
	let submitted = null;
	rpcBehavior.cellular_action = function(action, target, confirm) {
		submitted = { action: action, target: target, confirm: confirm };
		return Promise.resolve({ ok: true, operation_id: 'op-1722345678-1234', state: 'queued' });
	};
	rpcBehavior.operation_status = function(operationId) {
		assert.strictEqual(operationId, 'op-1722345678-1234');
		return Promise.resolve({
			operation_id: operationId,
			state: 'succeeded',
			code: 'ok'
		});
	};

	let current = app.render([
		{ ok: true, value: { state: 'ok', device: { sim: { type: 'physical' } } } },
		{ ok: true, value: { sim_switch: true } },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: true } }
	]);
	const parent = {
		replaceChild: function(next) {
			current = next;
			next.parentNode = parent;
		}
	};
	current.parentNode = parent;
	tabById(current, 'device').attrs.click();

	let select = nodesByTag(current, 'select')[0];
	let confirmation = nodesByTag(current, 'input').find(function(input) {
		return input.attrs['data-purpose'] === 'switch-sim';
	});
	let actionButton = nodesByTag(current, 'button').find(function(button) {
		return text(button) === '切换 SIM';
	});
	assert.ok(select);
	assert.ok(confirmation);
	assert.ok(actionButton);
	assert.strictEqual(text(current).indexOf('当前版本仅开放只读能力'), -1);

	await actionButton.attrs.click();
	assert.strictEqual(submitted, null);
	assert.ok(text(current).indexOf('请先确认该操作会短暂中断蜂窝网络') !== -1);

	select = nodesByTag(current, 'select')[0];
	confirmation = nodesByTag(current, 'input').find(function(input) {
		return input.attrs['data-purpose'] === 'switch-sim';
	});
	actionButton = nodesByTag(current, 'button').find(function(button) {
		return text(button) === '切换 SIM';
	});
	select.value = 'sim2';
	confirmation.checked = true;
	await actionButton.attrs.click();
	assert.deepStrictEqual(submitted, { action: 'switch_sim', target: 'sim2', confirm: true });
	assert.ok(text(current).indexOf('操作已进入队列') !== -1);

	await pollEntries[0].callback();
	assert.ok(text(current).indexOf('SIM 切换已完成') !== -1);
	tabById(current, 'overview').attrs.click();
});

test('does not render SIM write controls when the effective capability is false', function() {
	let current = app.render([
		{ ok: true, value: { state: 'ok', device: { sim: { type: 'physical' } } } },
		{ ok: true, value: { sim_switch: false } },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: true } }
	]);
	const parent = { replaceChild: function(next) { current = next; next.parentNode = parent; } };
	current.parentNode = parent;
	tabById(current, 'device').attrs.click();
	assert.strictEqual(nodesByTag(current, 'select').length, 0);
	assert.strictEqual(text(current).indexOf('切换 SIM'), -1);
	assert.ok(text(current).indexOf('详细能力状态见“系统与诊断”') !== -1);
	tabById(current, 'overview').attrs.click();
});

test('renders precise capability readiness without bypassing legacy gates', function() {
	const capabilities = {
		sim_switch: false,
		feature_status: {
			cellular_read: { implementation: 'implemented', verification: 'local_and_qemu', access: 'read', enabled: true },
			clients_read: { implementation: 'implemented', verification: 'simulator_only', access: 'read', enabled: true },
			sim_switch: { implementation: 'implemented', verification: 'spare_device_required', access: 'write', enabled: true },
			wifi_write: { implementation: 'not_implemented', verification: 'spare_device_required', access: 'write', enabled: false },
			firmware_update: { implementation: 'native_console_only', verification: 'native_console', access: 'write', enabled: false }
		}
	};
	let current = render({ state: 'ok', device: { sim: { type: 'physical' } } }, null, capabilities);
	const parent = { replaceChild: function(next) { current = next; next.parentNode = parent; } };
	current.parentNode = parent;
	tabById(current, 'diagnostics').attrs.click();
	assert.ok(text(current).indexOf('能力与校准状态') !== -1);
	assert.strictEqual(rowValue(current, '移动网络状态'), '已实现（本地与 QEMU 已验证）');
	assert.strictEqual(rowValue(current, '接入设备明细'), '已实现（模拟器已验证，需设备认证）');
	assert.strictEqual(rowValue(current, 'SIM 切换'), '已实现，等待备用设备实机校准');
	assert.strictEqual(rowValue(current, 'Wi-Fi 设置'), '尚未实现');
	assert.strictEqual(rowValue(current, '固件更新'), '仅支持在 U25S 原生控制台操作');
	assert.strictEqual(nodesByTag(current, 'select').length, 0,
		'descriptive metadata must not bypass the legacy capability boolean');
	tabById(current, 'overview').attrs.click();
});

test('stops polling and reports timed-out or invalid operation states', async function() {
	pollEntries.length = 0;
	let statusCalls = 0;
	rpcBehavior.cellular_action = function() {
		return Promise.resolve({ ok: true, operation_id: 'op-timeout', state: 'queued' });
	};
	rpcBehavior.operation_status = function() {
		statusCalls += 1;
		return Promise.resolve({ operation_id: 'op-timeout', state: 'timed_out', code: 'deadline' });
	};
	rpcBehavior.capabilities = function() { return Promise.resolve({ sim_switch: true }); };

	let current = app.render([
		{ ok: true, value: { state: 'ok', device: { sim: { type: 'physical' } } } },
		{ ok: true, value: { sim_switch: true } },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: true } }
	]);
	const parent = { replaceChild: function(next) { current = next; next.parentNode = parent; } };
	current.parentNode = parent;
	tabById(current, 'device').attrs.click();
	let select = nodesByTag(current, 'select')[0];
	let confirmation = nodesByTag(current, 'input').find(function(input) {
		return input.attrs['data-purpose'] === 'switch-sim';
	});
	let button = nodesByTag(current, 'button').find(function(candidate) {
		return text(candidate) === '切换 SIM';
	});
	select.value = 'sim1';
	confirmation.checked = true;
	await button.attrs.click();
	await pollEntries[0].callback();
	assert.ok(text(current).indexOf('SIM 切换超时') !== -1);
	await pollEntries[0].callback();
	assert.strictEqual(statusCalls, 1);

	rpcBehavior.cellular_action = function() {
		return Promise.resolve({ ok: true, operation_id: 'op-invalid', state: 'queued' });
	};
	rpcBehavior.operation_status = function() {
		statusCalls += 1;
		return Promise.resolve({ ok: false, error: 'operation_not_found' });
	};
	tabById(current, 'device').attrs.click();
	select = nodesByTag(current, 'select')[0];
	confirmation = nodesByTag(current, 'input').find(function(input) {
		return input.attrs['data-purpose'] === 'switch-sim';
	});
	button = nodesByTag(current, 'button').find(function(candidate) {
		return text(candidate) === '切换 SIM';
	});
	select.value = 'sim2';
	confirmation.checked = true;
	await button.attrs.click();
	await pollEntries[0].callback();
	assert.ok(text(current).indexOf('操作记录不存在，已停止跟踪') !== -1);
	await pollEntries[0].callback();
	assert.strictEqual(statusCalls, 2);
	tabById(current, 'overview').attrs.click();
});

test('guards duplicate submissions and ignores a late status from an old operation', async function() {
	pollEntries.length = 0;
	const submission = deferred();
	const statusRequests = [];
	let submitCalls = 0;
	rpcBehavior.status = function() { return Promise.resolve({ state: 'ok' }); };
	rpcBehavior.capabilities = function() { return Promise.resolve({ sim_switch: true }); };
	rpcBehavior.cellular_action = function() {
		submitCalls += 1;
		return submission.promise;
	};
	rpcBehavior.operation_status = function(operationId) {
		const request = deferred();
		request.operationId = operationId;
		statusRequests.push(request);
		return request.promise;
	};

	let current = app.render([
		{ ok: true, value: { state: 'ok', device: { sim: { type: 'physical' } } } },
		{ ok: true, value: { sim_switch: true } },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: true } }
	]);
	const parent = { replaceChild: function(next) { current = next; next.parentNode = parent; } };
	current.parentNode = parent;
	tabById(current, 'device').attrs.click();
	let select = nodesByTag(current, 'select')[0];
	let confirmation = nodesByTag(current, 'input').find(function(input) {
		return input.attrs['data-purpose'] === 'switch-sim';
	});
	let button = nodesByTag(current, 'button').find(function(candidate) {
		return text(candidate) === '切换 SIM';
	});
	select.value = 'sim1';
	confirmation.checked = true;
	const firstSubmit = button.attrs.click();
	await button.attrs.click();
	assert.strictEqual(submitCalls, 1);
	assert.ok(text(current).indexOf('已有 SIM 切换请求正在处理') !== -1);
	submission.resolve({ ok: true, operation_id: 'op-old', state: 'queued' });
	await firstSubmit;
	button = nodesByTag(current, 'button').find(function(candidate) {
		return text(candidate) === '切换 SIM';
	});
	assert.strictEqual(button.attrs.disabled, 'disabled');
	await button.attrs.click();
	assert.strictEqual(submitCalls, 1);

	const oldPoll1 = pollEntries[0].callback();
	const oldPoll2 = pollEntries[0].callback();
	await new Promise(function(resolve) { setImmediate(resolve); });
	assert.strictEqual(statusRequests.length, 2);
	statusRequests[0].resolve({ operation_id: 'op-old', state: 'succeeded', code: 'ok' });
	await oldPoll1;

	rpcBehavior.cellular_action = function() {
		submitCalls += 1;
		return Promise.resolve({ ok: true, operation_id: 'op-new', state: 'queued' });
	};
	select = nodesByTag(current, 'select')[0];
	confirmation = nodesByTag(current, 'input').find(function(input) {
		return input.attrs['data-purpose'] === 'switch-sim';
	});
	button = nodesByTag(current, 'button').find(function(candidate) {
		return text(candidate) === '切换 SIM';
	});
	select.value = 'sim2';
	confirmation.checked = true;
	await button.attrs.click();
	assert.ok(text(current).indexOf('操作已进入队列') !== -1);

	statusRequests[1].resolve({ operation_id: 'op-old', state: 'running' });
	await oldPoll2;
	assert.ok(text(current).indexOf('操作已进入队列') !== -1);
	assert.strictEqual(text(current).indexOf('SIM 切换正在执行'), -1);
	tabById(current, 'overview').attrs.click();
});

test('keeps an active operation guarded across a transient status RPC failure', async function() {
	pollEntries.length = 0;
	let statusCalls = 0;
	rpcBehavior.status = function() { return Promise.resolve({ state: 'ok' }); };
	rpcBehavior.capabilities = function() { return Promise.resolve({ sim_switch: true }); };
	rpcBehavior.cellular_action = function() {
		return Promise.resolve({ ok: true, operation_id: 'op-retry', state: 'queued' });
	};
	rpcBehavior.operation_status = function() {
		statusCalls += 1;
		if (statusCalls === 1)
			return Promise.reject(new Error('temporary ubus failure'));
		return Promise.resolve({ operation_id: 'op-retry', state: 'succeeded', code: 'ok' });
	};

	let current = app.render([
		{ ok: true, value: { state: 'ok', device: { sim: { type: 'physical' } } } },
		{ ok: true, value: { sim_switch: true } },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: true } }
	]);
	const parent = { replaceChild: function(next) { current = next; next.parentNode = parent; } };
	current.parentNode = parent;
	tabById(current, 'device').attrs.click();
	let select = nodesByTag(current, 'select')[0];
	let confirmation = nodesByTag(current, 'input').find(function(input) {
		return input.attrs['data-purpose'] === 'switch-sim';
	});
	let button = nodesByTag(current, 'button').find(function(candidate) {
		return text(candidate) === '切换 SIM';
	});
	select.value = 'sim1';
	confirmation.checked = true;
	await button.attrs.click();
	await pollEntries[0].callback();
	assert.ok(text(current).indexOf('暂时无法读取操作状态，将自动重试') !== -1);
	button = nodesByTag(current, 'button').find(function(candidate) {
		return text(candidate) === '切换 SIM';
	});
	assert.strictEqual(button.attrs.disabled, 'disabled');
	await pollEntries[0].callback();
	assert.strictEqual(statusCalls, 2);
	assert.ok(text(current).indexOf('SIM 切换已完成') !== -1);
	tabById(current, 'overview').attrs.click();
});

test('shows a visible backend error instead of an empty dashboard', function() {
	const alerts = [];
	const tree = app.render([
		{ ok: false, value: {} },
		{ ok: true, value: { model: 'U25S' } }
	]);
	collectByClass(tree, 'error', alerts);
	assert.ok(alerts.some(function(alert) {
		return text(alert).indexOf('无法读取后端状态') !== -1;
	}));
});

test('registers polling and replaces the rendered status content', async function() {
	pollEntries.length = 0;
	rpcBehavior.status = function() {
		return Promise.resolve({ online: true, model: 'refreshed-model' });
	};
	rpcBehavior.capabilities = function() { return Promise.resolve({}); };

	const tree = app.render([
		{ ok: true, value: { online: false, model: 'initial-model' } },
		{ ok: true, value: {} }
	]);
	assert.strictEqual(pollEntries.length, 1);
	assert.strictEqual(pollEntries[0].interval, 30);

	let replacement = null;
	const parent = {
		replaceChild: function(next, previous) {
			assert.strictEqual(previous, tree);
			replacement = next;
			next.parentNode = parent;
		}
	};
	tree.parentNode = parent;
	await pollEntries[0].callback();
	assert.ok(replacement);
	assert.strictEqual(rowValue(replacement, '设备型号'), 'refreshed-model');
	assert.strictEqual(rowValue(replacement, '设备在线'), '在线');
});

test('warns when an otherwise-ok snapshot has stopped updating', function() {
	const alerts = [];
	const oldTimestamp = Math.floor(Date.now() / 1000) - 361;
	const tree = render({ state: 'ok', updated: oldTimestamp });
	collectByClass(tree, 'warning', alerts);
	assert.ok(alerts.some(function(alert) {
		return text(alert).indexOf('状态快照长时间未更新') !== -1;
	}));
});

test('renders the device-console tabs without charging automation', function() {
	const tree = render({
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
	});
	assert.strictEqual(nodesByClass(tree, 'zte-tab').length, 9);
	assert.strictEqual(tabById(tree, 'battery'), undefined);
	assert.strictEqual(tabById(tree, 'schedule'), undefined);
	assert.ok(tabById(tree, 'clients'));
	assert.ok(text(tree).indexOf('电池状态') !== -1);
	assert.strictEqual(source.indexOf('立即充满'), -1);
	assert.strictEqual(source.indexOf('充电日程'), -1);
	assert.strictEqual(nodesByClass(tree, 'zte-tab-panel').length, 1);
	assert.strictEqual(
		nodesByClass(tree, 'zte-tab-panel')[0].attrs['data-panel'],
		'overview'
	);

	let replacement = null;
	const parent = {
		replaceChild: function(next, previous) {
			assert.strictEqual(previous, tree);
			replacement = next;
			next.parentNode = parent;
		}
	};
	tree.parentNode = parent;

	const networkTab = tabById(tree, 'network');
	assert.ok(networkTab);
	assert.strictEqual(typeof networkTab.attrs.click, 'function');
	networkTab.attrs.click();
	assert.ok(replacement);
	assert.strictEqual(
		nodesByClass(replacement, 'zte-tab-panel')[0].attrs['data-panel'],
		'network'
	);
});

test('preserves the selected tab after a poll refresh', async function() {
	pollEntries.length = 0;
	rpcBehavior.status = function() {
		return Promise.resolve({
			online: true,
			device: { cellular: { type: 'LTE' } }
		});
	};
	rpcBehavior.capabilities = function() { return Promise.resolve({}); };

	const tree = render({ online: false });
	assert.strictEqual(
		nodesByClass(tree, 'zte-tab-panel')[0].attrs['data-panel'],
		'network'
	);

	let replacement = null;
	const parent = {
		replaceChild: function(next) {
			replacement = next;
			next.parentNode = parent;
		}
	};
	tree.parentNode = parent;
	await pollEntries[0].callback();
	assert.ok(replacement);
	assert.strictEqual(
		nodesByClass(replacement, 'zte-tab-panel')[0].attrs['data-panel'],
		'network'
	);
});

const completeStatus = {
	online: true,
	state: 'ok',
	failures: 2,
	updated: Math.floor(Date.now() / 1000),
	device: {
		model: 'U25S',
		firmware: 'TEST_FIRMWARE',
		hardware_version: 'HW-TEST',
		webui_version: 'WEB-TEST',
		software_version: 'SW-TEST',
		market_name: 'U25S Test',
		upgrade: { new_version_state: '1', current_state: 'idle' },
		modem_state: 'connected',
		missing: 'station_list',
		cellular: {
			type: 'NR5G-SA',
			provider: '中国移动',
			signalbar: '4',
			rsrp: '-68',
			lte_rsrp: '-72',
			rscp: '-81',
			rssi: '-55',
			roaming: '0',
			dial_mode: 'auto_dial',
			wan_mode: 'PPP',
			connection_mode: 'auto_dial',
			auto_roaming_raw: '1',
			network_mode_raw: 'LTE_NR',
			network_selection_mode_raw: 'auto',
			radio: {
				snr_raw: '28', sinr_raw: '25', ca_state_raw: 'ca_activated',
				primary_band_raw: 'n78', primary_bandwidth_raw: '100MHz',
				secondary_band_raw: 'B3', secondary_bandwidth_raw: '20MHz',
				primary_arfcn_raw: '640000', secondary_arfcn_raw: '1650',
				active_band_raw: 'NR5G'
			},
			pdp: { ipv4_type_raw: 'IPV4V6', ipv6_type_raw: 'IPV6' },
			mcc: '460',
			mnc: '00',
			ppp_status: 'ipv4_ipv6_connected'
		},
		sim: {
			active_slot_raw: '1',
			type: 'physical'
		},
		wifi: {
			enabled: true,
			guest_enabled: false,
			bands: {
				wifi_2_4: { ssid: 'Lab-24', auth_mode: 'WPA2PSK', clients: 2 },
				wifi_5: { ssid: 'Lab-5', auth_mode: 'WPA3PSK', clients: 1 }
			},
			radio_off_raw: '0',
			primary: {
				ssid: 'Primary', auth_mode: 'WPA3PSK', hidden_raw: '0',
				max_clients_raw: '16', isolation_raw: '1'
			},
			guest: {
				enabled_raw: '1', ssid: 'Guest', auth_mode: 'WPA2PSK',
				hidden_raw: '1', max_clients_raw: '4', isolation_raw: '1'
			},
			advanced: {
				mode_raw: '11ax', country_raw: 'CN', channel_raw: '36',
				bandwidth_raw: '80MHz', coverage_raw: '2'
			},
			sleep_status_raw: '0'
		},
		clients: {
			available: true,
			items: [
				{
					mac: '02:00:00:00:00:01',
					hostname: 'test-phone',
					ip: '192.0.2.10',
					ssid_index: '1',
					interface: 'wlan0',
					upload_rate_raw: '1024',
					download_rate_raw: '2048'
				}
			]
		},
		battery: {
			present: true,
			percent: 82,
			charging: false,
			value: '4050',
			pers: '82',
			temperature_level: 'normal'
		},
		sms: { total: 3 },
		traffic: {
			realtime: { upload_bps: 1250, download_bps: 3400 },
			current: { sent_bytes: 1024, received_bytes: 2048, connected_seconds: 3600 },
			monthly: {
				sent_bytes: 4096,
				received_bytes: 8192,
				connected_seconds: 7200,
				month: '2026-08'
			},
			plan: {
				enabled: true,
				unit: 'data',
				limit: '10240',
				alert_percent: 80,
				auto_clear: true,
				clear_day: 1,
				disconnect: false
			}
		}
	},
	network: {
		up: true,
		l3_device: 'eth2',
		ipv4: '192.168.0.2',
		gateway: '192.168.0.1',
		is_default_route: false
	},
	policy: {
		state: 'PRE_DEPARTURE',
		power_action: 'ON'
	},
	power: {
		backend: 'hardware',
		calibrated: true,
		write_enabled: true,
		control_path: '/sys/class/gpio/modem_power/value',
		control_state: 1,
		supply_state: 1,
		observed: 'ON',
		execution: {
			available: true,
			reason: 'ready'
		},
		decision: {
			backend: 'hardware',
			action: 'ON',
			executed: true,
			reason: 'pre_departure',
			outcome: 'succeeded',
			updated: 1722345678,
			profile: 'hardware|1|1|cudy,tr3000-v1|/sys/class/gpio/modem_power/value'
		},
		recovery: {
			inhibited: false,
			service_available: true,
			service_running: true
		}
	}
};

test('renders the overview panel from current status', function() {
	const tree = renderPanel(completeStatus, 'overview');
	assert.strictEqual(rowValue(tree, '设备型号'), 'U25S');
	assert.strictEqual(rowValue(tree, '设备在线'), '在线');
	assert.strictEqual(rowValue(tree, '后端状态'), '正常');
	assert.strictEqual(rowValue(tree, '电池状态'), '82%');
	assert.notStrictEqual(rowValue(tree, '状态快照时间'), '—');
});

test('renders the mobile-network panel from current status', function() {
	const tree = renderPanel(completeStatus, 'network');
	assert.strictEqual(rowValue(tree, '网络制式'), 'NR5G-SA');
	assert.strictEqual(rowValue(tree, '运营商'), '中国移动');
	assert.strictEqual(rowValue(tree, '信号'), '-68 dBm');
	assert.strictEqual(rowValue(tree, 'LTE RSRP'), '-72 dBm');
	assert.strictEqual(rowValue(tree, 'RSCP'), '-81 dBm');
	assert.strictEqual(rowValue(tree, 'RSSI'), '-55 dBm');
	assert.strictEqual(rowValue(tree, '漫游状态'), '0');
	assert.strictEqual(rowValue(tree, '拨号模式'), 'auto_dial');
	assert.strictEqual(rowValue(tree, 'WAN 模式'), 'PPP');
	assert.strictEqual(rowValue(tree, '连接模式'), 'auto_dial');
	assert.strictEqual(rowValue(tree, '漫游自动连接原始值'), '1');
	assert.strictEqual(rowValue(tree, '网络偏好原始值'), 'LTE_NR');
	assert.strictEqual(rowValue(tree, '选网模式原始值'), 'auto');
	assert.strictEqual(rowValue(tree, 'SNR 原始值'), '28');
	assert.strictEqual(rowValue(tree, 'SINR 原始值'), '25');
	assert.strictEqual(rowValue(tree, '载波聚合状态'), 'ca_activated');
	assert.strictEqual(rowValue(tree, '主载波频段'), 'n78');
	assert.strictEqual(rowValue(tree, '辅载波频段'), 'B3');
	assert.strictEqual(rowValue(tree, 'IPv4 PDP 类型'), 'IPV4V6');
	assert.strictEqual(rowValue(tree, 'IPv6 PDP 类型'), 'IPV6');
	assert.strictEqual(rowValue(tree, '运营商代码'), '460-00');
	assert.strictEqual(rowValue(tree, 'PPP 状态'), 'ipv4_ipv6_connected');
	assert.strictEqual(rowValue(tree, 'USB 上联'), '已连接 (eth2)');
	assert.strictEqual(rowValue(tree, 'IPv4'), '192.168.0.2');
	assert.strictEqual(rowValue(tree, '网关'), '192.168.0.1');
	assert.strictEqual(rowValue(tree, '默认出口'), '否');
});

test('renders verified Wi-Fi summary without credentials', function() {
	const tree = renderPanel(completeStatus, 'wifi');
	assert.strictEqual(rowValue(tree, 'Wi-Fi 开关'), '已启用');
	assert.strictEqual(rowValue(tree, '访客网络'), '未启用');
	assert.strictEqual(rowValue(tree, '2.4 GHz SSID'), 'Lab-24');
	assert.strictEqual(rowValue(tree, '2.4 GHz 安全模式'), 'WPA2PSK');
	assert.strictEqual(rowValue(tree, '2.4 GHz 客户端'), '2');
	assert.strictEqual(rowValue(tree, '5 GHz SSID'), 'Lab-5');
	assert.strictEqual(rowValue(tree, '5 GHz 安全模式'), 'WPA3PSK');
	assert.strictEqual(rowValue(tree, '5 GHz 客户端'), '1');
	assert.strictEqual(rowValue(tree, '主网络 SSID'), 'Primary');
	assert.strictEqual(rowValue(tree, '访客 SSID'), 'Guest');
	assert.strictEqual(rowValue(tree, '信道原始值'), '36');
	assert.strictEqual(rowValue(tree, '带宽原始值'), '80MHz');
	assert.strictEqual(rowValue(tree, '休眠状态原始值'), '0');
	assert.strictEqual(text(nodesByClass(tree, 'zte-tab-panel')[0]).indexOf('密码'), -1);
});

test('links to the native U25S console through the management gateway', function() {
	const tree = render(completeStatus);
	const link = nodesByTag(tree, 'a').find(function(node) {
		return text(node) === '打开 U25S 原生控制台';
	});
	assert.ok(link);
	assert.strictEqual(link.attrs.href, 'http://192.168.0.1/');
	assert.strictEqual(link.attrs.rel, 'noreferrer noopener');
});

test('renders the U30 HTTPS transport and native console identity', function() {
	const status = Object.assign({}, completeStatus, {
		model: 'U30 Pro',
		device: Object.assign({}, completeStatus.device, {
			adapter: 'zte_u30', model: 'U30 Pro'
		})
	});
	const capabilities = {
		adapter: 'zte_u30', model: 'U30 Pro', transport: 'https',
		tls_verification: 'device_certificate_unverified'
	};
	const tree = render(status, null, capabilities);
	const link = nodesByTag(tree, 'a').find(function(node) {
		return text(node) === '打开 U30 Pro 原生控制台';
	});
	assert.ok(link);
	assert.strictEqual(link.attrs.href, 'https://192.168.0.1/');
	const diagnostics = renderPanel(status, 'diagnostics', null, capabilities);
	assert.strictEqual(rowValue(diagnostics, '设备适配器'), 'zte_u30');
	assert.strictEqual(rowValue(diagnostics, '管理传输'), 'HTTPS');
	assert.strictEqual(rowValue(diagnostics, 'TLS 验证'), '设备证书未验证');
});

test('renders aggregate counts and authenticated client details', function() {
	const tree = renderPanel(completeStatus, 'clients');
	assert.strictEqual(rowValue(tree, '接入设备总数'), '3');
	assert.strictEqual(rowValue(tree, '2.4 GHz 客户端'), '2');
	assert.strictEqual(rowValue(tree, '5 GHz 客户端'), '1');
	assert.strictEqual(rowValue(tree, '明细状态'), '已加载（1 台）');
	const panelText = text(nodesByClass(tree, 'zte-tab-panel')[0]);
	assert.ok(panelText.indexOf('test-phone') !== -1);
	assert.ok(panelText.indexOf('02:00:00:00:00:01') !== -1);
	assert.ok(panelText.indexOf('192.0.2.10') !== -1);
	assert.ok(panelText.indexOf('wlan0') !== -1);
});

test('keeps U30 client totals scoped to the supported 2.4 GHz radio', function() {
	const status = JSON.parse(JSON.stringify(completeStatus));
	status.device.adapter = 'zte_u30';
	status.device.model = 'U30 Pro';
	const tree = renderPanel(status, 'clients', null, { adapter: 'zte_u30' });
	assert.strictEqual(rowValue(tree, '接入设备总数'), '2');
	assert.strictEqual(rowValue(tree, '2.4 GHz 客户端'), '2');
	assert.strictEqual(text(tree).indexOf('5 GHz 客户端'), -1);
});

test('explains why authenticated client details are unavailable', function() {
	const reasons = {
		credentials_missing: '未配置设备管理密码',
		authentication_failed: '设备认证失败，已暂停重试',
		authentication_backoff: '认证重试冷却中',
		read_failed: '客户端明细读取失败',
		not_loaded: '客户端明细尚未加载'
	};
	Object.keys(reasons).forEach(function(reason) {
		const status = JSON.parse(JSON.stringify(completeStatus));
		status.device.clients = { available: false, reason: reason, items: [] };
		assert.strictEqual(
			rowValue(renderPanel(status, 'clients'), '明细状态'),
			reasons[reason]
		);
	});
});

test('keeps aggregate client total unknown when a band count is missing', function() {
	const status = JSON.parse(JSON.stringify(completeStatus));
	status.device.wifi.bands.wifi_5.clients = null;
	assert.strictEqual(rowValue(renderPanel(status, 'clients'), '接入设备总数'), '—');
});

test('renders verified traffic status', function() {
	const tree = renderPanel(completeStatus, 'traffic');
	assert.strictEqual(rowValue(tree, '实时上传'), '1.25 kB/s');
	assert.strictEqual(rowValue(tree, '实时下载'), '3.40 kB/s');
	assert.strictEqual(rowValue(tree, '本次发送'), '1.00 KiB');
	assert.strictEqual(rowValue(tree, '本次接收'), '2.00 KiB');
	assert.strictEqual(rowValue(tree, '本次连接时长'), '1小时');
	assert.strictEqual(rowValue(tree, '本月发送'), '4.00 KiB');
	assert.strictEqual(rowValue(tree, '本月接收'), '8.00 KiB');
	assert.strictEqual(rowValue(tree, '本月连接时长'), '2小时');
	assert.strictEqual(rowValue(tree, '统计月份'), '2026-08');
	assert.strictEqual(rowValue(tree, '套餐限制'), '已启用');
	assert.strictEqual(rowValue(tree, '提醒阈值'), '80%');
});

test('renders the authenticated SMS cache and decodes message content', function() {
	const tree = renderPanel(completeStatus, 'sms', {
		available: true,
		items: [ {
			id: '7',
			number_raw: '+8600000000000',
			content_encoded: '4F60597D',
			date_raw: '26,08,01,09,30,00,+32',
			tag: '1'
		} ]
	});
	assert.strictEqual(rowValue(tree, '短信总数'), '3');
	assert.strictEqual(rowValue(tree, '收件箱状态'), '已加载（1 条）');
	assert.strictEqual(rowValue(tree, '消息 ID 1'), '7');
	const panelText = text(nodesByClass(tree, 'zte-tab-panel')[0]);
	assert.ok(panelText.indexOf('+8600000000000') !== -1);
	assert.ok(panelText.indexOf('你好') !== -1);
	assert.strictEqual(panelText.indexOf('4F60597D'), -1);
});

test('explains why the private SMS cache is unavailable', function() {
	const tree = renderPanel(completeStatus, 'sms', {
		available: false,
		reason: 'authentication_backoff',
		items: []
	});
	assert.strictEqual(rowValue(tree, '收件箱状态'), '认证重试冷却中');
});

test('renders device and SIM details from normalized status', function() {
	const tree = renderPanel(completeStatus, 'device');
	assert.strictEqual(rowValue(tree, '设备型号'), 'U25S');
	assert.strictEqual(rowValue(tree, '固件版本'), 'TEST_FIRMWARE');
	assert.strictEqual(rowValue(tree, '市场名称'), 'U25S Test');
	assert.strictEqual(rowValue(tree, '硬件版本'), 'HW-TEST');
	assert.strictEqual(rowValue(tree, '软件版本'), 'SW-TEST');
	assert.strictEqual(rowValue(tree, 'WebUI 版本'), 'WEB-TEST');
	assert.strictEqual(rowValue(tree, '新版本状态'), '1');
	assert.strictEqual(rowValue(tree, '升级状态'), 'idle');
	assert.strictEqual(rowValue(tree, 'Modem 状态'), 'connected');
	assert.strictEqual(rowValue(tree, 'SIM 类型'), 'physical');
	assert.strictEqual(rowValue(tree, '活动卡槽原始值'), '1');
	assert.strictEqual(rowValue(tree, '电池存在'), '是');
	assert.strictEqual(rowValue(tree, '电量'), '82%');
	assert.strictEqual(rowValue(tree, '充电状态'), '未充电');
	assert.strictEqual(rowValue(tree, '温度级别'), 'normal');
});

test('renders backend diagnostics without inventing data', function() {
	const tree = renderPanel(completeStatus, 'diagnostics');
	assert.strictEqual(rowValue(tree, '后端状态'), '正常');
	assert.strictEqual(rowValue(tree, '失败次数'), '2');
	assert.strictEqual(rowValue(tree, '缺失字段'), 'station_list');
	assert.strictEqual(rowValue(tree, 'USB 供电读回'), 'ON');
	assert.ok(text(tree).indexOf('USB 断电会中断数据连接，仅用于故障恢复') !== -1);
});

test('renders bounded event log entries as text', function() {
	let current = app.render([
		{ ok: true, value: completeStatus },
		{ ok: true, value: {} },
		{ ok: true, value: {
			events: [
				{
					time: 1722345678,
					level: 'warn',
					type: 'state',
					code: 'state_degraded'
				}
			]
		} }
	]);
	const parent = {
		replaceChild: function(next) {
			current = next;
			next.parentNode = parent;
		}
	};
	current.parentNode = parent;
	tabById(current, 'logs').attrs.click();
	assert.ok(text(current).indexOf('warn · state · state_degraded') !== -1);
	assert.strictEqual(source.indexOf('innerHTML'), -1);
});

testChain.then(function() {
	if (failures > 0) {
		console.error('FAIL test_luci (' + failures + '/' + count + ' failed)');
		process.exit(1);
	}
	console.log('PASS test_luci (' + count + ' assertions)');
});
