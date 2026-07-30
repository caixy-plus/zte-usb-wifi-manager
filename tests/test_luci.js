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
	capabilities: function() { return Promise.resolve({}); }
};
const rpcSpecs = {};
const pollEntries = [];

const app = new Function('view', 'rpc', 'poll', '_', 'E', 'L', source)(
	{ extend: function(spec) { return spec; } },
	{ declare: function(spec) {
		rpcSpecs[spec.method] = spec;
		return function() { return rpcBehavior[spec.method](); };
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

function render(status) {
	return app.render([
		{ ok: true, value: status },
		{ ok: true, value: {} }
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

function tabById(tree, tabId) {
	return nodesByClass(tree, 'zte-tab').find(function(tab) {
		return tab.attrs['data-tab'] === tabId;
	});
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
	['degraded', 'fail_safe', 'credentials_missing'].forEach(function(state) {
		const value = rowValue(render({ state: state, device: { model: 'U25S' } }), '后端状态');
		assert.ok(
			value.indexOf('设备数据来自最近一次成功读取') !== -1,
			state + ' does not mark retained device data stale'
		);
	});
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
	const data = await app.load();
	assert.strictEqual(data[0].ok, false);
	assert.strictEqual(data[1].ok, true);
	assert.strictEqual(data[1].value.model, 'U25S');
});

test('declares ubus calls as rejecting and rejects numeric error replies', async function() {
	assert.strictEqual(rpcSpecs.status.reject, true);
	assert.strictEqual(rpcSpecs.capabilities.reject, true);
	rpcBehavior.status = function() { return Promise.resolve(4); };
	rpcBehavior.capabilities = function() { return Promise.resolve({}); };
	const data = await app.load();
	assert.strictEqual(data[0].ok, false);
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

test('renders ten tabs and switches to the mobile-network panel', function() {
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
	assert.strictEqual(nodesByClass(tree, 'zte-tab').length, 10);
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

testChain.then(function() {
	if (failures > 0) {
		console.error('FAIL test_luci (' + failures + '/' + count + ' failed)');
		process.exit(1);
	}
	console.log('PASS test_luci (' + count + ' assertions)');
});
