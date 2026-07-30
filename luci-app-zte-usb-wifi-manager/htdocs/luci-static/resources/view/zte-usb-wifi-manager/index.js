'use strict';
'require view';
'require rpc';
'require poll';

var POLL_INTERVAL_SECONDS = 30;
var STALE_AFTER_SECONDS = 360;
var activeTab = 'overview';

var callStatus = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'status',
	reject: true
});

var callCapabilities = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'capabilities',
	reject: true
});

var callLogs = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'logs',
	params: [ 'limit' ],
	reject: true
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

function renderTab(tab, active, onSelect) {
	return E('button', {
		'class': 'cbi-button zte-tab' + (active ? ' cbi-button-positive' : ''),
		'data-tab': tab.id,
		'aria-selected': active ? 'true' : 'false',
		'click': function() {
			onSelect(tab.id);
		}
	}, tab.label);
}

function dash(value) {
	return value === null || value === undefined || value === '' ? '—' : value;
}

function row(label, value) {
	return E('div', { 'class': 'cbi-value' }, [
		E('div', { 'class': 'cbi-value-title' }, label),
		E('div', { 'class': 'cbi-value-field' }, dash(value))
	]);
}

function stateLabel(state, hasDevice) {
	var label;

	switch (state) {
	case 'ok':
		label = _('正常');
		break;
	case 'degraded':
		label = _('降级');
		break;
	case 'fail_safe':
		label = _('故障安全');
		break;
	case 'credentials_missing':
		label = _('缺少设备凭据');
		break;
	case 'framework_ready':
		label = _('框架已就绪');
		break;
	default:
		label = typeof state === 'string' ? state : null;
	}

	if (label && state !== 'ok' && hasDevice)
		return label + _('（设备数据来自最近一次成功读取）');

	return label;
}

function signalLabel(cellular) {
	if (cellular.rsrp !== null && cellular.rsrp !== undefined && cellular.rsrp !== '')
		return cellular.rsrp + ' dBm';
	if (cellular.signalbar !== null && cellular.signalbar !== undefined && cellular.signalbar !== '')
		return cellular.signalbar + ' ' + _('格');
	return null;
}

function batteryLabel(battery) {
	if (battery.present === false)
		return _('未检测到电池');
	if (battery.percent === null || battery.percent === undefined || battery.percent === '')
		return null;

	return battery.percent + '%' + (battery.charging === true ? ' · ' + _('充电中') : '');
}

function onlineLabel(status) {
	if (status.online === true)
		return _('在线');
	if (status.online === false)
		return _('离线');
	return null;
}

function uplinkLabel(network) {
	if (network.up === true)
		return network.l3_device ? _('已连接') + ' (' + network.l3_device + ')' : _('已连接');
	if (network.up === false)
		return _('未连接');
	return null;
}

function updatedLabel(updated) {
	var timestamp = Number(updated);

	if (!isFinite(timestamp) || timestamp <= 0)
		return null;

	return new Date(timestamp * 1000).toLocaleString();
}

function yesNoLabel(value) {
	if (value === true)
		return _('是');
	if (value === false)
		return _('否');
	return null;
}

function chargingLabel(value) {
	if (value === true)
		return _('充电中');
	if (value === false)
		return _('未充电');
	return null;
}

function rpcResult(call) {
	var request;

	try {
		request = call();
	}
	catch (error) {
		return Promise.resolve({ ok: false, value: {} });
	}

	return Promise.resolve(request).then(function(value) {
		if (!value || typeof value !== 'object')
			return { ok: false, value: {} };

		return {
			ok: true,
			value: value
		};
	}, function() {
		return { ok: false, value: {} };
	});
}

function loadData() {
	return Promise.all([
		rpcResult(callStatus),
		rpcResult(callCapabilities),
		rpcResult(function() { return callLogs(50); })
	]);
}

function snapshotIsStale(updated) {
	var timestamp = Number(updated);

	return isFinite(timestamp) && timestamp > 0 &&
		Math.floor(Date.now() / 1000) - timestamp > STALE_AFTER_SECONDS;
}

function panelRoot(tabId, title, children) {
	return E('div', {
		'class': 'cbi-section zte-tab-panel',
		'data-panel': tabId
	}, [ E('h3', {}, title) ].concat(children));
}

function renderOverview(status, capabilities) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var cellular = device.cellular && typeof device.cellular === 'object' ? device.cellular : {};
	var battery = device.battery && typeof device.battery === 'object' ? device.battery : {};
	var network = status.network && typeof status.network === 'object' ? status.network : {};
	var policy = status.policy && typeof status.policy === 'object' ? status.policy : {};
	var hasDevice = Object.keys(device).length > 0;

	return panelRoot('overview', _('只读状态总览'), [
		row(_('设备型号'), device.model || status.model || capabilities.model),
		row(_('设备在线'), onlineLabel(status)),
		row(_('后端状态'), stateLabel(status.state, hasDevice)),
		row(_('网络制式'), cellular.type),
		row(_('运营商'), cellular.provider),
		row(_('信号'), signalLabel(cellular)),
		row(_('电量'), batteryLabel(battery)),
		row(_('USB 上联'), uplinkLabel(network)),
		row(_('默认出口'), yesNoLabel(network.is_default_route)),
		row(_('电池策略'), _('仅监控，不控制供电') +
			(policy.state ? ' (' + policy.state + ')' : '')),
		row(_('状态快照时间'), updatedLabel(status.updated))
	]);
}

function renderNetwork(status) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var cellular = device.cellular && typeof device.cellular === 'object' ? device.cellular : {};
	var network = status.network && typeof status.network === 'object' ? status.network : {};

	return panelRoot('network', _('移动网络'), [
		row(_('网络制式'), cellular.type),
		row(_('运营商'), cellular.provider),
		row(_('信号'), signalLabel(cellular)),
		row(_('PPP 状态'), cellular.ppp_status),
		row(_('USB 上联'), uplinkLabel(network)),
		row(_('IPv4'), network.ipv4),
		row(_('网关'), network.gateway),
		row(_('默认出口'), yesNoLabel(network.is_default_route))
	]);
}

function renderUnavailableModule(tabId, title) {
	return panelRoot(tabId, title, [
		row(_('数据状态'), _('当前快照尚未提供此模块数据'))
	]);
}

function renderBattery(status) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var battery = device.battery && typeof device.battery === 'object' ? device.battery : {};

	return panelRoot('battery', _('电池与供电'), [
		row(_('电池存在'), yesNoLabel(battery.present)),
		row(_('电量'), battery.percent === null || battery.percent === undefined ||
			battery.percent === '' ? null : battery.percent + '%'),
		row(_('充电状态'), chargingLabel(battery.charging)),
		row(_('电池值'), battery.value),
		row(_('电池百分比原值'), battery.pers),
		row(_('温度级别'), battery.temperature_level)
	]);
}

function renderSms(status) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var sms = device.sms && typeof device.sms === 'object' ? device.sms : {};

	return panelRoot('sms', _('短信'), [
		row(_('短信总数'), sms.total)
	]);
}

function renderSchedule() {
	return panelRoot('schedule', _('充电日程'), [
		row(_('功能状态'), _('阶段 3 未启用'))
	]);
}

function renderDevice(status, capabilities) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var sim = device.sim && typeof device.sim === 'object' ? device.sim : {};

	return panelRoot('device', _('设备'), [
		row(_('设备型号'), device.model || status.model || capabilities.model),
		row(_('Modem 状态'), device.modem_state),
		row(_('SIM 类型'), sim.type),
		row(_('活动卡槽原始值'), sim.active_slot_raw)
	]);
}

function renderDiagnostics(status) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var hasDevice = Object.keys(device).length > 0;

	return panelRoot('diagnostics', _('系统与诊断'), [
		row(_('后端状态'), stateLabel(status.state, hasDevice)),
		row(_('失败次数'), status.failures),
		row(_('缺失字段'), device.missing)
	]);
}

function renderLogs(logsResult) {
	if (!logsResult || !logsResult.ok)
		return panelRoot('logs', _('日志'), [
			row(_('数据状态'), _('无法读取事件日志'))
		]);

	var value = logsResult.value && typeof logsResult.value === 'object'
		? logsResult.value : {};
	var events = Array.isArray(value.events) ? value.events : [];
	if (!events.length)
		return panelRoot('logs', _('日志'), [
			row(_('数据状态'), _('暂无事件'))
		]);

	return panelRoot('logs', _('日志'), events.map(function(event) {
		event = event && typeof event === 'object' ? event : {};
		return E('div', { 'class': 'zte-log-entry' }, [
			E('div', { 'class': 'zte-log-time' }, updatedLabel(event.time)),
			E('div', { 'class': 'zte-log-message' }, [
				dash(event.level),
				' · ',
				dash(event.type),
				' · ',
				dash(event.code)
			])
		]);
	}));
}

function renderPanel(tabId, status, capabilities, logsResult) {
	switch (tabId) {
	case 'network':
		return renderNetwork(status);
	case 'wifi':
		return renderUnavailableModule('wifi', _('Wi-Fi 与设备'));
	case 'traffic':
		return renderUnavailableModule('traffic', _('流量'));
	case 'sms':
		return renderSms(status);
	case 'battery':
		return renderBattery(status);
	case 'schedule':
		return renderSchedule();
	case 'device':
		return renderDevice(status, capabilities);
	case 'diagnostics':
		return renderDiagnostics(status);
	case 'logs':
		return renderLogs(logsResult);
	default:
		return renderOverview(status, capabilities);
	}
}

function renderStatus(data, selectedTab, onSelect) {
		var statusResult = data && data[0] && typeof data[0] === 'object'
			? data[0] : { ok: false, value: {} };
		var capabilitiesResult = data && data[1] && typeof data[1] === 'object'
			? data[1] : { ok: false, value: {} };
		var status = statusResult.ok && statusResult.value &&
			typeof statusResult.value === 'object' ? statusResult.value : {};
		var capabilities = capabilitiesResult.ok && capabilitiesResult.value &&
			typeof capabilitiesResult.value === 'object' ? capabilitiesResult.value : {};
		var logsResult = data && data[2] && typeof data[2] === 'object'
			? data[2] : { ok: false, value: {} };
		var alerts = [];

		if (!statusResult.ok)
			alerts.push(E('div', { 'class': 'alert-message error' },
				_('无法读取后端状态，请检查 rpcd 服务和访问权限。')));
		if (!capabilitiesResult.ok)
			alerts.push(E('div', { 'class': 'alert-message error' },
				_('无法读取设备能力信息。')));
		if (statusResult.ok && snapshotIsStale(status.updated))
			alerts.push(E('div', { 'class': 'alert-message warning' },
				_('状态快照长时间未更新，后台守护进程可能已停止。')));

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('中兴随身 WiFi 管理')),
			alerts,
			E('div', { 'class': 'zte-tabs' }, tabs.map(function(tab) {
				return renderTab(tab, tab.id === selectedTab, onSelect);
			})),
			renderPanel(selectedTab, status, capabilities, logsResult),
			E('div', { 'class': 'alert-message warning' },
				_('设备写接口尚未完成实机校准，当前版本仅开放只读能力。'))
		]);
}

return view.extend({
	load: loadData,

	render: function(data) {
		var currentData = data;
		var root;

		function replace(next) {
			if (root && root.parentNode)
				root.parentNode.replaceChild(next, root);
			root = next;
			return root;
		}

		function selectTab(tabId) {
			activeTab = tabId;
			replace(renderStatus(currentData, activeTab, selectTab));
		}

		root = renderStatus(currentData, activeTab, selectTab);

		poll.add(function() {
			return loadData().then(function(nextData) {
				currentData = nextData;
				replace(renderStatus(currentData, activeTab, selectTab));
			});
		}, POLL_INTERVAL_SECONDS);

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
