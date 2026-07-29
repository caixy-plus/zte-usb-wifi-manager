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

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callStatus(), {}),
			L.resolveDefault(callCapabilities(), {})
		]);
	},

	render: function(data) {
		var status = data[0] || {};
		var capabilities = data[1] || {};

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('中兴随身 WiFi 管理')),
			E('div', { 'class': 'zte-tabs' }, tabs.map(function(tab, index) {
				return renderTab(tab, index === 0);
			})),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('框架状态')),
				E('p', {}, status.state === 'framework_ready'
					? _('后端框架已就绪，设备轮询尚未配置。')
					: _('正在等待后端状态。')),
				E('p', {}, _('目标型号：') + (status.model || capabilities.model || 'U25S')),
				E('div', { 'class': 'alert-message warning' },
					_('设备写接口尚未完成实机校准，当前版本仅开放只读框架。'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
