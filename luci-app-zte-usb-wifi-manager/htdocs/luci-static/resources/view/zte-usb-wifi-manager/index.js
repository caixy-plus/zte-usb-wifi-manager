'use strict';
'require view';
'require rpc';
'require poll';

var POLL_INTERVAL_SECONDS = 30;
var STALE_AFTER_SECONDS = 360;

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
		rpcResult(callCapabilities)
	]);
}

function snapshotIsStale(updated) {
	var timestamp = Number(updated);

	return isFinite(timestamp) && timestamp > 0 &&
		Math.floor(Date.now() / 1000) - timestamp > STALE_AFTER_SECONDS;
}

function renderStatus(data) {
		var statusResult = data && data[0] && typeof data[0] === 'object'
			? data[0] : { ok: false, value: {} };
		var capabilitiesResult = data && data[1] && typeof data[1] === 'object'
			? data[1] : { ok: false, value: {} };
		var status = statusResult.ok && statusResult.value &&
			typeof statusResult.value === 'object' ? statusResult.value : {};
		var capabilities = capabilitiesResult.ok && capabilitiesResult.value &&
			typeof capabilitiesResult.value === 'object' ? capabilitiesResult.value : {};
		var device = status.device && typeof status.device === 'object' ? status.device : {};
		var hasDevice = status.device && typeof status.device === 'object' &&
			Object.keys(status.device).length > 0;
		var cellular = device.cellular && typeof device.cellular === 'object' ? device.cellular : {};
		var battery = device.battery && typeof device.battery === 'object' ? device.battery : {};
		var network = status.network && typeof status.network === 'object' ? status.network : {};
		var policy = status.policy && typeof status.policy === 'object' ? status.policy : {};
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
			E('div', { 'class': 'zte-tabs' }, tabs.map(function(tab, index) {
				return renderTab(tab, index === 0);
			})),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('只读状态总览')),
				row(_('设备型号'), device.model || status.model || capabilities.model),
				row(_('设备在线'), onlineLabel(status)),
				row(_('后端状态'), stateLabel(status.state, hasDevice)),
				row(_('网络制式'), cellular.type),
				row(_('运营商'), cellular.provider),
				row(_('信号'), signalLabel(cellular)),
				row(_('电量'), batteryLabel(battery)),
				row(_('USB 上联'), uplinkLabel(network)),
				row(_('默认出口'), network.is_default_route === true ? _('是') :
					(network.is_default_route === false ? _('否') : null)),
				row(_('电池策略'), _('仅监控，不控制供电') +
					(policy.state ? ' (' + policy.state + ')' : '')),
				row(_('状态快照时间'), updatedLabel(status.updated)),
				E('div', { 'class': 'alert-message warning' },
					_('设备写接口尚未完成实机校准，当前版本仅开放只读能力。'))
			])
		]);
}

return view.extend({
	load: loadData,

	render: function(data) {
		var root = renderStatus(data);

		poll.add(function() {
			return loadData().then(function(nextData) {
				var replacement = renderStatus(nextData);

				if (root.parentNode)
					root.parentNode.replaceChild(replacement, root);
				root = replacement;
			});
		}, POLL_INTERVAL_SECONDS);

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
