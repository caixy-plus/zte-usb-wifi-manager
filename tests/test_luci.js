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

const app = new Function('view', 'rpc', '_', 'E', 'L', source)(
	{ extend: function(spec) { return spec; } },
	{ declare: function() { return function() { return Promise.resolve({}); }; } },
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
	return app.render([status, {}]);
}

function rowValue(tree, title) {
	const rows = [];
	collectRows(tree, rows);
	const match = rows.find(function(row) { return row.title === title; });
	assert.ok(match, 'missing rendered row: ' + title);
	return match.value;
}

let count = 0;
let failures = 0;

function test(name, fn) {
	count += 1;
	try {
		fn();
	} catch (error) {
		failures += 1;
		console.error('FAIL test_luci: ' + name + ': ' + error.message);
	}
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

if (failures > 0) {
	console.error('FAIL test_luci (' + failures + '/' + count + ' failed)');
	process.exit(1);
}

console.log('PASS test_luci (' + count + ' assertions)');
