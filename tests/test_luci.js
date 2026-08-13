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
	capabilities: function() { return Promise.resolve({}); },
	logs: function() { return Promise.resolve({ events: [] }); },
	credential_status: function() { return Promise.resolve({ configured: false }); },
	charging_settings: function() {
		return Promise.resolve({ enabled: false, low_percent: 30, high_percent: 80 });
	},
	set_charging_settings: function() {
		return Promise.resolve({ ok: true, enabled: false, low_percent: 30, high_percent: 80 });
	},
	set_credentials: function() { return Promise.resolve({ ok: true, configured: true }); },
	clear_credentials: function() { return Promise.resolve({ ok: true, configured: false }); }
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

function collectTabs(node, tabs) {
	if (!node || typeof node !== 'object')
		return;
	if (Array.isArray(node)) {
		node.forEach(function(child) { collectTabs(child, tabs); });
		return;
	}
	if (node.attrs && node.attrs['data-tab'])
		tabs.push(node.attrs['data-tab']);
	collectTabs(node.children, tabs);
}

function findNode(node, predicate) {
	if (!node || typeof node !== 'object')
		return null;
	if (Array.isArray(node)) {
		for (const child of node) {
			const found = findNode(child, predicate);
			if (found)
				return found;
		}
		return null;
	}
	if (predicate(node))
		return node;
	return findNode(node.children, predicate);
}

function render(status, capabilities, charging) {
	return app.render([
		{ ok: true, value: status },
		{ ok: true, value: capabilities || {} },
		{ ok: true, value: { events: [] } },
		{ ok: true, value: { configured: false } },
		{ ok: true, value: charging || { enabled: false, low_percent: 30, high_percent: 80 } }
	]);
}

assert.deepStrictEqual(Object.keys(rpcSpecs).sort(), [
	'capabilities',
	'charging_settings',
	'clear_credentials',
	'credential_status',
	'logs',
	'set_charging_settings',
	'set_credentials',
	'status'
]);

assert.ok(!source.includes('cellular_action'));
assert.ok(!source.includes('wifi_action'));
assert.ok(!source.includes('sms_action'));
assert.ok(!source.includes('device_action'));
assert.ok(!source.includes('power_action'));
assert.ok(!source.includes('operation_status'));
assert.ok(source.includes("id: 'device'"));
assert.ok(source.includes("id: 'charging'"));
assert.ok(source.includes("id: 'logs'"));
assert.ok(!source.includes("id: 'network'"));
assert.ok(!source.includes("id: 'wifi'"));
assert.ok(!source.includes("id: 'sms'"));

const statusFixture = {
	state: 'ok',
	online: true,
	updated: Math.floor(Date.now() / 1000),
	model: 'U30 Pro',
	policy: { state: 'BATTERY_HIGH', power_action: 'keep' },
	device: {
		model: 'U30 Pro',
		market_name: 'U30 Pro',
		firmware: '1.0',
		hardware_version: 'H1',
		software_version: 'S1',
		webui_version: 'W1',
		modem_state: 'online',
		battery: { present: true, percent: 55, charging: true, temperature_level: 'normal' },
		power_supply: { mode_raw: '0', direct_supply: false },
		cellular: { type: 'LTE', provider: 'Test', rsrp: -95 },
		sim: { type: 'nano', active_slot_raw: '1' },
		upgrade: { new_version_state: 'none', current_state: 'idle' }
	},
	network: {
		up: true,
		l3_device: 'eth2',
		gateway: '192.168.0.1',
		is_default_route: true
	}
};
const capabilitiesFixture = {
	model: 'U30 Pro',
	transport: 'https',
	set_power_supply_mode: true
};
const root = render(statusFixture, capabilitiesFixture);

const body = text(root);
assert.ok(body.includes('中兴 U30 智能充电'));
assert.ok(body.includes('设备基础信息') || body.includes('U30 Pro'));
assert.ok(body.includes('原生管理页') || body.includes('192.168.0.1'));

const tabs = [];
collectTabs(root, tabs);
assert.deepStrictEqual(tabs, [ 'device', 'charging', 'logs' ]);

const rows = [];
collectRows(root, rows);
const titles = rows.map(function(row) { return row.title; });
assert.ok(titles.includes('设备型号') || titles.includes('电量') || body.includes('55%'));

const credentialEntry = findNode(root, function(node) {
	return node.attrs && node.attrs['class'] === 'cbi-section zte-credential-entry';
});
assert.ok(credentialEntry);
const credentialRows = [];
collectRows(credentialEntry, credentialRows);
const passwordRow = credentialRows.find(function(item) {
	return item.title === '设备管理密码';
});
assert.ok(passwordRow);
assert.ok(passwordRow.value.includes('保存密码'));
const clearRow = credentialRows.find(function(item) {
	return item.title === '清除本地凭据';
});
assert.ok(clearRow);
assert.ok(clearRow.value.includes('我确认清除路由器中保存的中兴设备管理密码。'));
assert.ok(clearRow.value.includes('清除本地凭据'));
assert.strictEqual(findNode(credentialEntry, function(node) {
	return node.attrs && node.attrs['class'] === 'cbi-page-actions';
}), null);

assert.strictEqual(pollEntries.length, 1);
assert.strictEqual(pollEntries[0].interval, 30);

const chargingTab = findNode(root, function(node) {
	return node.attrs && node.attrs['data-tab'] === 'charging';
});
assert.ok(chargingTab);
chargingTab.attrs.click();
const chargingRoot = render(statusFixture, capabilitiesFixture, {
	enabled: true,
	low_percent: 30,
	high_percent: 80
});
const chargingRows = [];
collectRows(chargingRoot, chargingRows);
const policyRow = chargingRows.find(function(item) {
	return item.title === '策略运行状态';
});
assert.ok(policyRow);
assert.strictEqual(policyRow.value, '高电量，保持电源直供');

console.log('test_luci: ok');
