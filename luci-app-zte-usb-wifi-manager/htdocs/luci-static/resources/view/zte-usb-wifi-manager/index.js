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

var callCredentialStatus = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'credential_status',
	reject: true
});

var callSetCredentials = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'set_credentials',
	params: [ 'password' ],
	reject: true
});

var callCellularAction = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'cellular_action',
	params: [ 'action', 'target' ],
	reject: true
});

var callOperationStatus = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'operation_status',
	params: [ 'operation_id' ],
	reject: true
});

var tabs = [
	{ id: 'overview', label: _('总览') },
	{ id: 'network', label: _('移动网络') },
	{ id: 'wifi', label: _('U25S Wi-Fi') },
	{ id: 'clients', label: _('接入设备') },
	{ id: 'traffic', label: _('流量') },
	{ id: 'sms', label: _('短信') },
	{ id: 'device', label: _('设备与系统') },
	{ id: 'diagnostics', label: _('诊断') },
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
	case 'authentication_failed':
		label = _('设备认证失败');
		break;
	case 'planned_off':
		label = _('计划断电');
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

function dbmLabel(value) {
	if (value === null || value === undefined || value === '')
		return null;
	return value + ' dBm';
}

function operatorCodeLabel(cellular) {
	if (!cellular.mcc || !cellular.mnc)
		return null;
	return cellular.mcc + '-' + cellular.mnc;
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

function unsignedNumber(value) {
	var number = Number(value);
	return isFinite(number) && number >= 0 && Math.floor(number) === number
		? number : null;
}

function rateLabel(value) {
	var number = unsignedNumber(value);
	if (number === null)
		return null;
	if (number < 1000)
		return number + ' B/s';
	if (number < 1000000)
		return (number / 1000).toFixed(2) + ' kB/s';
	return (number / 1000000).toFixed(2) + ' MB/s';
}

function bytesLabel(value) {
	var number = unsignedNumber(value);
	var units = [ 'B', 'KiB', 'MiB', 'GiB', 'TiB' ];
	var unit = 0;
	if (number === null)
		return null;
	while (number >= 1024 && unit < units.length - 1) {
		number /= 1024;
		unit += 1;
	}
	return unit === 0 ? number + ' ' + units[unit]
		: number.toFixed(2) + ' ' + units[unit];
}

function durationLabel(value) {
	var seconds = unsignedNumber(value);
	var hours;
	var minutes;
	if (seconds === null)
		return null;
	hours = Math.floor(seconds / 3600);
	minutes = Math.floor((seconds % 3600) / 60);
	if (hours > 0)
		return hours + _('小时') + (minutes > 0 ? minutes + _('分钟') : '');
	if (minutes > 0)
		return minutes + _('分钟');
	return seconds + _('秒');
}

function enabledLabel(value) {
	if (value === true)
		return _('已启用');
	if (value === false)
		return _('未启用');
	return null;
}

function powerExecutionReasonLabel(reason) {
	var labels = {
		ready: _('就绪'),
		mock: _('模拟后端'),
		dry_run: _('影子执行，不写硬件'),
		backend_unconfigured: _('供电后端未配置'),
		write_disabled: _('全局写操作未启用'),
		not_calibrated: _('硬件尚未校准'),
		board_unsupported: _('路由器型号不受支持'),
		control_unresolved: _('供电控制路径无法解析'),
		recovery_unavailable: _('恢复服务不可用'),
		unavailable: _('不可用')
	};

	return labels[reason] || null;
}

function powerExecutionLabel(power) {
	var execution = power.execution && typeof power.execution === 'object'
		? power.execution : {};
	var reason = powerExecutionReasonLabel(execution.reason);

	if (!power.backend)
		return _('供电状态未知');
	if (power.backend === 'hardware') {
		if (execution.available === true)
			return _('硬件控制已启用');
		return _('硬件控制不可执行') + (reason ? '（' + reason + '）' : '');
	}
	if (power.backend === 'dry-run')
		return _('影子执行（不写硬件）');
	if (power.backend === 'mock')
		return _('模拟执行');
	return _('供电控制未启用');
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
		rpcResult(function() { return callLogs(50); }),
		rpcResult(callCredentialStatus)
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

function renderCredentialEntry(credentialsResult, onSave, notice) {
	var value = credentialsResult && credentialsResult.ok &&
		credentialsResult.value && typeof credentialsResult.value === 'object'
		? credentialsResult.value : {};
	var passwordInput = E('input', {
		'type': 'password',
		'class': 'cbi-input-password',
		'placeholder': _('U25S 管理密码'),
		'autocomplete': 'new-password'
	});
	var children = [
		row(_('凭据状态'), value.configured === true
			? _('管理密码已保存') : _('未保存管理密码')),
		E('div', { 'class': 'cbi-value' }, [
			E('div', { 'class': 'cbi-value-title' }, _('U25S 管理登录')),
			E('div', { 'class': 'cbi-value-field' }, [
				passwordInput,
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'type': 'button',
					'click': function() {
						return onSave(passwordInput);
					}
				}, _('保存登录凭据'))
			])
		]),
		E('div', { 'class': 'cbi-value-description' },
			_('密码仅写入路由器的 root 0600 文件；页面不会读取或保存密码副本。'))
	];

	if (notice)
		children.push(E('div', {
			'class': 'alert-message ' + notice.level
		}, notice.message));

	return E('div', { 'class': 'cbi-section zte-credential-entry' },
		[ E('h3', {}, _('设备登录')) ].concat(children));
}

function renderOverview(status, capabilities) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var cellular = device.cellular && typeof device.cellular === 'object' ? device.cellular : {};
	var battery = device.battery && typeof device.battery === 'object' ? device.battery : {};
	var network = status.network && typeof status.network === 'object' ? status.network : {};
	var hasDevice = Object.keys(device).length > 0;

	return panelRoot('overview', _('只读状态总览'), [
		row(_('设备型号'), device.model || status.model || capabilities.model),
		row(_('设备在线'), onlineLabel(status)),
		row(_('后端状态'), stateLabel(status.state, hasDevice)),
		row(_('网络制式'), cellular.type),
		row(_('运营商'), cellular.provider),
		row(_('信号'), signalLabel(cellular)),
		row(_('电池状态'), batteryLabel(battery)),
		row(_('USB 上联'), uplinkLabel(network)),
		row(_('默认出口'), yesNoLabel(network.is_default_route)),
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
		row(_('LTE RSRP'), dbmLabel(cellular.lte_rsrp)),
		row(_('RSCP'), dbmLabel(cellular.rscp)),
		row(_('RSSI'), dbmLabel(cellular.rssi)),
		row(_('漫游状态'), cellular.roaming),
		row(_('拨号模式'), cellular.dial_mode),
		row(_('WAN 模式'), cellular.wan_mode),
		row(_('运营商代码'), operatorCodeLabel(cellular)),
		row(_('PPP 状态'), cellular.ppp_status),
		row(_('USB 上联'), uplinkLabel(network)),
		row(_('IPv4'), network.ipv4),
		row(_('网关'), network.gateway),
		row(_('默认出口'), yesNoLabel(network.is_default_route))
	]);
}

function renderUnavailableModule(tabId, title, message) {
	return panelRoot(tabId, title, [
		row(_('数据状态'), message || _('当前快照尚未提供此模块数据'))
	]);
}

function renderWifi(status) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var wifi = device.wifi && typeof device.wifi === 'object' ? device.wifi : {};
	var bands = wifi.bands && typeof wifi.bands === 'object' ? wifi.bands : {};
	var wifi24 = bands.wifi_2_4 && typeof bands.wifi_2_4 === 'object'
		? bands.wifi_2_4 : {};
	var wifi5 = bands.wifi_5 && typeof bands.wifi_5 === 'object'
		? bands.wifi_5 : {};

	return panelRoot('wifi', _('U25S Wi-Fi'), [
		row(_('Wi-Fi 开关'), enabledLabel(wifi.enabled)),
		row(_('访客网络'), enabledLabel(wifi.guest_enabled)),
		row(_('2.4 GHz SSID'), wifi24.ssid),
		row(_('2.4 GHz 安全模式'), wifi24.auth_mode),
		row(_('2.4 GHz 客户端'), wifi24.clients),
		row(_('5 GHz SSID'), wifi5.ssid),
		row(_('5 GHz 安全模式'), wifi5.auth_mode),
		row(_('5 GHz 客户端'), wifi5.clients)
	]);
}

function clientCollectionLabel(clients, count) {
	if (clients.available === true)
		return _('已加载') + '（' + count + ' ' + _('台') + '）';
	switch (clients.reason) {
	case 'credentials_missing':
		return _('未配置设备管理密码');
	case 'authentication_failed':
		return _('设备认证失败，已暂停重试');
	case 'authentication_backoff':
		return _('认证重试冷却中');
	case 'read_failed':
		return _('客户端明细读取失败');
	case 'not_loaded':
		return _('客户端明细尚未加载');
	default:
		return _('当前快照尚未提供客户端明细');
	}
}

function clientDetailLabel(client) {
	var fields = [];
	if (client.hostname)
		fields.push(client.hostname);
	if (client.mac)
		fields.push(client.mac);
	if (client.ip)
		fields.push(client.ip);
	if (client.ssid_index)
		fields.push('SSID ' + client.ssid_index);
	if (client.interface)
		fields.push(client.interface);
	if (client.upload_rate_raw)
		fields.push('↑ ' + client.upload_rate_raw);
	if (client.download_rate_raw)
		fields.push('↓ ' + client.download_rate_raw);
	return fields.length ? fields.join(' · ') : null;
}

function renderClients(status) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var wifi = device.wifi && typeof device.wifi === 'object' ? device.wifi : {};
	var bands = wifi.bands && typeof wifi.bands === 'object' ? wifi.bands : {};
	var wifi24 = bands.wifi_2_4 && typeof bands.wifi_2_4 === 'object'
		? bands.wifi_2_4 : {};
	var wifi5 = bands.wifi_5 && typeof bands.wifi_5 === 'object'
		? bands.wifi_5 : {};
	var clients = device.clients && typeof device.clients === 'object'
		? device.clients : {};
	var items = clients.available === true && Array.isArray(clients.items)
		? clients.items.slice(0, 64) : [];
	var total = null;

	if (typeof wifi24.clients === 'number' && wifi24.clients >= 0 &&
		typeof wifi5.clients === 'number' && wifi5.clients >= 0)
		total = wifi24.clients + wifi5.clients;

	var rows = [
		row(_('接入设备总数'), total),
		row(_('2.4 GHz 客户端'), wifi24.clients),
		row(_('5 GHz 客户端'), wifi5.clients),
		row(_('明细状态'), clientCollectionLabel(clients, items.length))
	];
	items.forEach(function(client, index) {
		if (client && typeof client === 'object')
			rows.push(row(_('客户端 ') + (index + 1), clientDetailLabel(client)));
	});
	return panelRoot('clients', _('接入设备'), rows);
}

function renderSms(status) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var sms = device.sms && typeof device.sms === 'object' ? device.sms : {};

	return panelRoot('sms', _('短信'), [
		row(_('短信总数'), sms.total)
	]);
}

function renderTraffic(status) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var traffic = device.traffic && typeof device.traffic === 'object'
		? device.traffic : {};
	var realtime = traffic.realtime && typeof traffic.realtime === 'object'
		? traffic.realtime : {};
	var current = traffic.current && typeof traffic.current === 'object'
		? traffic.current : {};
	var monthly = traffic.monthly && typeof traffic.monthly === 'object'
		? traffic.monthly : {};
	var plan = traffic.plan && typeof traffic.plan === 'object' ? traffic.plan : {};

	return panelRoot('traffic', _('流量'), [
		row(_('实时上传'), rateLabel(realtime.upload_bps)),
		row(_('实时下载'), rateLabel(realtime.download_bps)),
		row(_('本次发送'), bytesLabel(current.sent_bytes)),
		row(_('本次接收'), bytesLabel(current.received_bytes)),
		row(_('本次连接时长'), durationLabel(current.connected_seconds)),
		row(_('本月发送'), bytesLabel(monthly.sent_bytes)),
		row(_('本月接收'), bytesLabel(monthly.received_bytes)),
		row(_('本月连接时长'), durationLabel(monthly.connected_seconds)),
		row(_('统计月份'), monthly.month),
		row(_('套餐限制'), enabledLabel(plan.enabled)),
		row(_('限制单位'), plan.unit),
		row(_('限制值'), plan.limit),
		row(_('提醒阈值'), plan.alert_percent === null ||
			plan.alert_percent === undefined ? null : plan.alert_percent + '%'),
		row(_('自动清零'), enabledLabel(plan.auto_clear)),
		row(_('清零日'), plan.clear_day),
		row(_('到量断网'), enabledLabel(plan.disconnect))
	]);
}

function renderSimSwitch(sim, onAction, actionBusy) {
	var selectedTarget = sim.type === 'sim1' || sim.type === 'sim2' ||
		sim.type === 'sim3' || sim.type === 'physical' ? sim.type : 'physical';
	var targetSelect = E('select', { 'class': 'cbi-input-select' }, [
		E('option', { 'value': 'physical' }, _('实体 SIM')),
		E('option', { 'value': 'sim1' }, _('eSIM 1')),
		E('option', { 'value': 'sim2' }, _('eSIM 2')),
		E('option', { 'value': 'sim3' }, _('eSIM 3'))
	]);
	var confirmation = E('input', {
		'type': 'checkbox',
		'class': 'cbi-input-checkbox'
	});
	var children;

	targetSelect.value = selectedTarget;
	children = [
		E('div', { 'class': 'cbi-value' }, [
			E('div', { 'class': 'cbi-value-title' }, _('目标 SIM')),
			E('div', { 'class': 'cbi-value-field' }, targetSelect)
		]),
		E('div', { 'class': 'cbi-value' }, [
			E('div', { 'class': 'cbi-value-title' }, _('操作确认')),
			E('div', { 'class': 'cbi-value-field' }, [
				confirmation,
				' ',
				_('我确认切换过程会短暂中断蜂窝网络')
			])
		]),
		E('button', {
			'class': 'cbi-button cbi-button-action',
			'type': 'button',
			'disabled': actionBusy ? 'disabled' : null,
			'click': function() {
				return onAction(targetSelect, confirmation);
			}
		}, _('切换 SIM'))
	];
	return E('div', { 'class': 'cbi-section zte-sim-action' },
		[ E('h4', {}, _('SIM 切换')) ].concat(children));
}

function renderDevice(status, capabilities, onAction, actionNotice, actionBusy) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var sim = device.sim && typeof device.sim === 'object' ? device.sim : {};
	var battery = device.battery && typeof device.battery === 'object' ? device.battery : {};
	var upgrade = device.upgrade && typeof device.upgrade === 'object' ? device.upgrade : {};
	var children = [
		row(_('设备型号'), device.model || status.model || capabilities.model),
		row(_('固件版本'), device.firmware),
		row(_('市场名称'), device.market_name),
		row(_('硬件版本'), device.hardware_version),
		row(_('软件版本'), device.software_version),
		row(_('WebUI 版本'), device.webui_version),
		row(_('新版本状态'), upgrade.new_version_state),
		row(_('升级状态'), upgrade.current_state),
		row(_('Modem 状态'), device.modem_state),
		row(_('SIM 类型'), sim.type),
		row(_('活动卡槽原始值'), sim.active_slot_raw),
		row(_('电池存在'), yesNoLabel(battery.present)),
		row(_('电量'), battery.percent === null || battery.percent === undefined ||
			battery.percent === '' ? null : battery.percent + '%'),
		row(_('充电状态'), chargingLabel(battery.charging)),
		row(_('温度级别'), battery.temperature_level)
	];

	if (capabilities.sim_switch === true)
		children.push(renderSimSwitch(sim, onAction, actionBusy));

	return panelRoot('device', _('设备'), children);
}

function renderDiagnostics(status) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var power = status.power && typeof status.power === 'object' ? status.power : {};
	var recovery = power.recovery && typeof power.recovery === 'object'
		? power.recovery : {};
	var hasDevice = Object.keys(device).length > 0;

	return panelRoot('diagnostics', _('系统与诊断'), [
		row(_('后端状态'), stateLabel(status.state, hasDevice)),
		row(_('失败次数'), status.failures),
		row(_('缺失字段'), device.missing),
		row(_('USB 供电读回'), power.observed),
		row(_('恢复服务可用'), yesNoLabel(recovery.service_available)),
		E('div', { 'class': 'alert-message warning' },
			_('USB 断电会中断数据连接，仅用于故障恢复。'))
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

function renderPanel(tabId, status, capabilities, logsResult, onAction,
	actionNotice, actionBusy) {
	switch (tabId) {
	case 'network':
		return renderNetwork(status);
	case 'wifi':
		return renderWifi(status);
	case 'clients':
		return renderClients(status);
	case 'traffic':
		return renderTraffic(status);
	case 'sms':
		return renderSms(status);
	case 'device':
		return renderDevice(status, capabilities, onAction, actionNotice, actionBusy);
	case 'diagnostics':
		return renderDiagnostics(status);
	case 'logs':
		return renderLogs(logsResult);
	default:
		return renderOverview(status, capabilities);
	}
}

function renderStatus(data, selectedTab, onSelect, onCredentialSave,
	credentialNotice, onDeviceAction, actionNotice, actionBusy) {
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
		var credentialsResult = data && data[3] && typeof data[3] === 'object'
			? data[3] : { ok: false, value: {} };
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
		if (actionNotice)
			alerts.push(E('div', {
				'class': 'alert-message ' + actionNotice.level
			}, actionNotice.message));

		var writesAvailable = capabilities.sim_switch === true ||
			capabilities.cellular_write === true || capabilities.wifi_write === true ||
			capabilities.traffic_write === true || capabilities.sms_write === true;
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('中兴随身 WiFi 管理')),
			alerts,
			renderCredentialEntry(credentialsResult, onCredentialSave, credentialNotice),
			E('div', { 'class': 'zte-tabs' }, tabs.map(function(tab) {
				return renderTab(tab, tab.id === selectedTab, onSelect);
			})),
			renderPanel(selectedTab, status, capabilities, logsResult,
				onDeviceAction, actionNotice, actionBusy),
			E('div', { 'class': 'alert-message warning' },
				writesAvailable
					? _('仅显示已通过实机校准并由管理员启用的写操作。')
					: _('设备写接口尚未完成实机校准，当前版本仅开放只读能力。'))
		]);
}

return view.extend({
	load: loadData,

	render: function(data) {
		var currentData = data;
		var credentialNotice = null;
		var actionNotice = null;
		var currentOperationId = null;
		var actionSubmitting = false;
		var operationGeneration = 0;
		var root;

		function renderCurrent() {
			return renderStatus(
				currentData,
				activeTab,
				selectTab,
				saveCredentials,
				credentialNotice,
				switchSim,
				actionNotice,
				actionSubmitting || currentOperationId !== null
			);
		}

		function replace(next) {
			if (root && root.parentNode)
				root.parentNode.replaceChild(next, root);
			root = next;
			return root;
		}

		function selectTab(tabId) {
			activeTab = tabId;
			replace(renderCurrent());
		}

		function saveCredentials(passwordInput) {
			var credentialValue = passwordInput && typeof passwordInput.value === 'string'
				? passwordInput.value : '';
			if (passwordInput)
				passwordInput.value = '';
			if (!credentialValue) {
				credentialNotice = {
					level: 'error',
					message: _('请输入 U25S 管理密码。')
				};
				replace(renderCurrent());
				return Promise.resolve();
			}

			return Promise.resolve(callSetCredentials(credentialValue)).then(function(reply) {
				credentialValue = '';
				if (!reply || reply.ok !== true) {
					credentialNotice = {
						level: 'error',
						message: _('密码保存失败，请检查后端日志。')
					};
					replace(renderCurrent());
					return;
				}
				currentData[3] = {
					ok: true,
					value: { configured: true }
				};
				credentialNotice = {
					level: 'success',
					message: _('密码已保存，等待设备需要认证时使用。')
				};
				replace(renderCurrent());
			}, function() {
				credentialValue = '';
				credentialNotice = {
					level: 'error',
					message: _('密码保存失败，请检查 rpcd 服务和权限。')
				};
				replace(renderCurrent());
			});
		}

		function switchSim(targetSelect, confirmation) {
			var target = targetSelect && typeof targetSelect.value === 'string'
				? targetSelect.value : '';
			var requestGeneration;
			if (actionSubmitting || currentOperationId !== null) {
				actionNotice = {
					level: 'info',
					message: _('已有 SIM 切换请求正在处理，请等待结果。')
				};
				replace(renderCurrent());
				return Promise.resolve();
			}
			if (!confirmation || confirmation.checked !== true) {
				actionNotice = {
					level: 'error',
					message: _('请先确认该操作会短暂中断蜂窝网络。')
				};
				replace(renderCurrent());
				return Promise.resolve();
			}
			actionSubmitting = true;
			operationGeneration += 1;
			requestGeneration = operationGeneration;
			actionNotice = {
				level: 'info',
				message: _('正在提交 SIM 切换请求。')
			};
			replace(renderCurrent());
			return Promise.resolve(callCellularAction('switch_sim', target)).then(function(reply) {
				if (requestGeneration !== operationGeneration)
					return;
				actionSubmitting = false;
				if (!reply || reply.ok !== true || typeof reply.operation_id !== 'string') {
					actionNotice = {
						level: 'error',
						message: _('SIM 切换请求被拒绝，请检查能力开关和事件日志。')
					};
					replace(renderCurrent());
					return;
				}
				currentOperationId = reply.operation_id;
				actionNotice = {
					level: 'info',
					message: _('操作已进入队列，页面将自动刷新执行结果。')
				};
				replace(renderCurrent());
			}, function() {
				if (requestGeneration !== operationGeneration)
					return;
				actionSubmitting = false;
				actionNotice = {
					level: 'error',
					message: _('无法提交 SIM 切换请求，请检查 rpcd 服务。')
				};
				replace(renderCurrent());
			});
		}

		function refreshOperation() {
			var operationId;
			var generation;
			if (!currentOperationId)
				return Promise.resolve();
			operationId = currentOperationId;
			generation = operationGeneration;
			return Promise.resolve(callOperationStatus(operationId)).then(function(reply) {
				if (generation !== operationGeneration ||
					operationId !== currentOperationId)
					return;
				if (!reply || typeof reply !== 'object')
					throw new Error('invalid operation reply');
				if (reply.ok === false) {
					if (reply.error === 'operation_not_found') {
						actionNotice = {
							level: 'error',
							message: _('操作记录不存在，已停止跟踪。')
						};
						currentOperationId = null;
						operationGeneration += 1;
					}
					else {
						actionNotice = {
							level: 'warning',
							message: _('暂时无法读取操作状态，将自动重试：') +
								dash(reply.error)
						};
					}
					return;
				}
				switch (reply.state) {
				case 'succeeded':
					actionNotice = { level: 'success', message: _('SIM 切换已完成。') };
					currentOperationId = null;
					operationGeneration += 1;
					break;
				case 'failed':
					actionNotice = {
						level: 'error',
						message: _('SIM 切换失败：') + dash(reply.code)
					};
					currentOperationId = null;
					operationGeneration += 1;
					break;
				case 'timed_out':
					actionNotice = {
						level: 'error',
						message: _('SIM 切换超时：') + dash(reply.code)
					};
					currentOperationId = null;
					operationGeneration += 1;
					break;
				case 'queued':
				case 'running':
				case 'verifying':
					actionNotice = {
						level: 'info',
						message: _('SIM 切换正在执行。')
					};
					break;
				default:
					actionNotice = {
						level: 'error',
						message: _('无法读取操作执行状态：') + dash(reply.state)
					};
					currentOperationId = null;
					operationGeneration += 1;
				}
			}, function() {
				if (generation !== operationGeneration ||
					operationId !== currentOperationId)
					return;
				actionNotice = {
					level: 'warning',
					message: _('暂时无法读取操作状态，将自动重试。')
				};
			});
		}

		root = renderCurrent();

		poll.add(function() {
			return loadData().then(function(nextData) {
				currentData = nextData;
				return refreshOperation();
			}).then(function() {
				replace(renderCurrent());
			});
		}, POLL_INTERVAL_SECONDS);

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
