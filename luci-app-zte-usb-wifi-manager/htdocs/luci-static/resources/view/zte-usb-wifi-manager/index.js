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

function dash(value) {
	return value === null || value === undefined || value === '' ? '—' : value;
}

function row(label, value) {
	return E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title' }, label),
		E('div', { 'class': 'cbi-value-field' }, dash(value))
	]);
}

function stateLabel(state) {
	var labels = {
		ok: _('正常'),
		degraded: _('降级（显示最近一次有效设备数据）'),
		fail_safe: _('故障安全'),
		credentials_missing: _('缺少设备凭据')
	};

	return labels[state] || dash(state);
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

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callStatus(), {}),
			L.resolveDefault(callCapabilities(), {})
		]);
	},

	render: function(data) {
		var status = data && data[0] && typeof data[0] === 'object' ? data[0] : {};
		var capabilities = data && data[1] && typeof data[1] === 'object' ? data[1] : {};
		var device = status.device && typeof status.device === 'object' ? status.device : {};
		var cellular = device.cellular && typeof device.cellular === 'object' ? device.cellular : {};
		var battery = device.battery && typeof device.battery === 'object' ? device.battery : {};
		var network = status.network && typeof status.network === 'object' ? status.network : {};
		var policy = status.policy && typeof status.policy === 'object' ? status.policy : {};

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('中兴随身 WiFi 管理')),
			E('div', { 'class': 'zte-tabs' }, tabs.map(function(tab, index) {
				return renderTab(tab, index === 0);
			})),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('只读状态总览')),
				row(_('设备型号'), device.model || status.model || capabilities.model),
				row(_('设备在线'), onlineLabel(status)),
				row(_('后端状态'), stateLabel(status.state)),
				row(_('网络制式'), cellular.type),
				row(_('运营商'), cellular.provider),
				row(_('信号'), signalLabel(cellular)),
				row(_('电量'), batteryLabel(battery)),
				row(_('USB 上联'), uplinkLabel(network)),
				row(_('默认出口'), network.is_default_route === true ? _('是') :
					(network.is_default_route === false ? _('否') : null)),
				row(_('电池策略'), _('仅监控，不控制供电') +
					(policy.state ? ' (' + policy.state + ')' : '')),
				row(_('更新时间'), updatedLabel(status.updated)),
				E('div', { 'class': 'alert-message warning' },
					_('设备写接口尚未完成实机校准，当前版本仅开放只读能力。'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
