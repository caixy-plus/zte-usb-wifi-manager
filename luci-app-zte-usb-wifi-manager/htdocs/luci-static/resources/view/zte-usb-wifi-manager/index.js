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

var callSmsMessages = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'sms_messages',
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

var callChargingSettings = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'charging_settings',
	reject: true
});

var callSetChargingSettings = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'set_charging_settings',
	params: [ 'enabled', 'low_percent', 'high_percent' ],
	reject: true
});

var callSetCredentials = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'set_credentials',
	params: [ 'password' ],
	reject: true
});

var callClearCredentials = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'clear_credentials',
	reject: true
});

var callCellularAction = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'cellular_action',
	params: [ 'action', 'target', 'confirm', 'apn', 'auth', 'username', 'password', 'mode' ],
	reject: true
});

var callWifiAction = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'wifi_action',
	params: [ 'action', 'enabled', 'band', 'ssid', 'security', 'password', 'channel' ],
	reject: true
});

var callTrafficAction = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'traffic_action',
	params: [ 'action', 'enabled', 'limit_bytes', 'alert_percent', 'cycle_day', 'disconnect', 'confirm' ],
	reject: true
});

var callSmsAction = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'sms_action',
	params: [ 'action', 'message_id', 'number', 'content', 'confirm' ],
	reject: true
});

var callDeviceAction = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'device_action',
	params: [ 'action', 'confirm' ],
	reject: true
});

var callPowerAction = rpc.declare({
	object: 'zte_usb_wifi',
	method: 'power_action',
	params: [ 'action', 'mode' ],
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
	{ id: 'wifi', label: _('设备 Wi-Fi') },
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

function actionInput(purpose, type, value) {
	var autocompleteValue = null;
	if (type === 'password')
		autocompleteValue = 'new-password';
	var input = E('input', {
		'class': type === 'checkbox' ? 'cbi-input-checkbox' : 'cbi-input-text',
		'type': type || 'text',
		'data-purpose': purpose,
		'autocomplete': autocompleteValue
	});
	if (type === 'checkbox')
		input.checked = value === true;
	else
		input.value = value === null || value === undefined ? '' : String(value);
	return input;
}

function actionSelect(purpose, values, selected) {
	var select = E('select', {
		'class': 'cbi-input-select',
		'data-purpose': purpose
	}, values.map(function(item) {
		return E('option', { 'value': item[0] }, item[1]);
	}));
	select.value = selected;
	return select;
}

function actionRow(label, control) {
	return E('div', { 'class': 'cbi-value' }, [
		E('div', { 'class': 'cbi-value-title' }, label),
		E('div', { 'class': 'cbi-value-field' }, control)
	]);
}

function actionButton(label, busy, callback) {
	return E('button', {
		'class': 'cbi-button cbi-button-action',
		'type': 'button',
		'disabled': busy ? 'disabled' : null,
		'click': callback
	}, label);
}

function actionSection(title, children) {
	return E('div', { 'class': 'cbi-section zte-device-action' },
		[ E('h4', {}, title) ].concat(children));
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
	case 'unsupported_device':
		label = _('不支持的 USB 设备');
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

function nativeConsoleUrl(status, capabilities) {
	var network = status.network && typeof status.network === 'object'
		? status.network : {};
	var transport = capabilities && capabilities.transport === 'https'
		? 'https' : 'http';
	if (typeof network.gateway !== 'string' ||
		!/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/.test(network.gateway))
		return null;
	return transport + '://' + network.gateway + '/';
}

function deviceModel(status, capabilities) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	return device.model || status.model || capabilities.model || 'U25S';
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

function powerSupplyModeLabel(powerSupply) {
	if (powerSupply.direct_supply === true || powerSupply.mode_raw === '1')
		return _('电源直供（停止给电池充电）');
	if (powerSupply.direct_supply === false || powerSupply.mode_raw === '0')
		return _('电池充电');
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
		rpcResult(callCredentialStatus),
		rpcResult(callSmsMessages),
		rpcResult(callChargingSettings)
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

function renderCredentialEntry(credentialsResult, onSave, onClear, notice) {
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
	if (value.configured === true) {
		var clearConfirmation = E('input', {
			'type': 'checkbox',
			'data-purpose': 'clear-credentials'
		});
		children.push(E('div', { 'class': 'cbi-value' }, [
			E('div', { 'class': 'cbi-value-title' }, _('清除登录凭据')),
			E('div', { 'class': 'cbi-value-field' }, [
				E('label', {}, [
					clearConfirmation,
					' ',
					_('确认从路由器删除已保存的 U25S 管理密码')
				]),
				E('button', {
					'class': 'cbi-button cbi-button-remove',
					'type': 'button',
					'click': function() {
						return onClear(clearConfirmation);
					}
				}, _('清除本地凭据'))
			])
		]));
	}

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

function renderNetwork(status, capabilities, onAction, actionBusy) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var cellular = device.cellular && typeof device.cellular === 'object' ? device.cellular : {};
	var radio = cellular.radio && typeof cellular.radio === 'object'
		? cellular.radio : {};
	var pdp = cellular.pdp && typeof cellular.pdp === 'object' ? cellular.pdp : {};
	var network = status.network && typeof status.network === 'object' ? status.network : {};

	var children = [
		row(_('网络制式'), cellular.type),
		row(_('运营商'), cellular.provider),
		row(_('信号'), signalLabel(cellular)),
		row(_('LTE RSRP'), dbmLabel(cellular.lte_rsrp)),
		row(_('RSCP'), dbmLabel(cellular.rscp)),
		row(_('RSSI'), dbmLabel(cellular.rssi)),
		row(_('漫游状态'), cellular.roaming),
		row(_('拨号模式'), cellular.dial_mode),
		row(_('WAN 模式'), cellular.wan_mode),
		row(_('连接模式'), cellular.connection_mode),
		row(_('漫游自动连接原始值'), cellular.auto_roaming_raw),
		row(_('网络偏好原始值'), cellular.network_mode_raw),
		row(_('选网模式原始值'), cellular.network_selection_mode_raw),
		row(_('SNR 原始值'), radio.snr_raw),
		row(_('SINR 原始值'), radio.sinr_raw),
		row(_('载波聚合状态'), radio.ca_state_raw),
		row(_('主载波频段'), radio.primary_band_raw),
		row(_('主载波带宽'), radio.primary_bandwidth_raw),
		row(_('辅载波频段'), radio.secondary_band_raw),
		row(_('辅载波带宽'), radio.secondary_bandwidth_raw),
		row(_('主载波 ARFCN'), radio.primary_arfcn_raw),
		row(_('辅载波 ARFCN'), radio.secondary_arfcn_raw),
		row(_('当前活动频段'), radio.active_band_raw),
		row(_('IPv4 PDP 类型'), pdp.ipv4_type_raw),
		row(_('IPv6 PDP 类型'), pdp.ipv6_type_raw),
		row(_('运营商代码'), operatorCodeLabel(cellular)),
		row(_('PPP 状态'), cellular.ppp_status),
		row(_('USB 上联'), uplinkLabel(network)),
		row(_('IPv4'), network.ipv4),
		row(_('网关'), network.gateway),
		row(_('默认出口'), yesNoLabel(network.is_default_route))
	];
	if (capabilities.set_apn === true) {
		var apn = actionInput('apn', 'text', '');
		var auth = actionSelect('apn-auth', [
			[ 'none', _('无') ], [ 'pap', 'PAP' ], [ 'chap', 'CHAP' ],
			[ 'pap_or_chap', 'PAP/CHAP' ]
		], 'none');
		var username = actionInput('apn-username', 'text', '');
		var password = actionInput('apn-password', 'password', '');
		children.push(actionSection(_('APN 设置'), [
			actionRow(_('APN'), apn),
			actionRow(_('认证'), auth), actionRow(_('用户名'), username),
			actionRow(_('密码'), password),
			actionButton(_('保存 APN'), actionBusy, function() {
				var request = {
					action: 'set_apn', apn: apn.value, auth: auth.value
				};
				if (auth.value !== 'none') {
					request.username = username.value;
					request['password'] = password.value;
				}
				return onAction('cellular', request, _('APN 设置'));
			})
		]));
	}
	if (capabilities.set_connection_mode === true) {
		var mode = actionSelect('connection-mode', [
			[ 'automatic', _('自动') ], [ 'manual', _('手动') ],
			[ 'on_demand', _('按需') ]
		], 'automatic');
		children.push(actionSection(_('连接模式'), [
			actionRow(_('模式'), mode),
			actionButton(_('保存连接模式'), actionBusy, function() {
				return onAction('cellular', {
					action: 'set_connection_mode', mode: mode.value
				}, _('连接模式设置'));
			})
		]));
	}
	return panelRoot('network', _('移动网络'), children);
}

function renderUnavailableModule(tabId, title, message) {
	return panelRoot(tabId, title, [
		row(_('数据状态'), message || _('当前快照尚未提供此模块数据'))
	]);
}

function profileIsU30(status, capabilities) {
	var device = status.device && typeof status.device === 'object'
		? status.device : {};
	return (device.adapter === 'zte_u30' && device.model === 'U30 Pro') ||
		(capabilities.adapter === 'zte_u30' && capabilities.model === 'U30 Pro');
}

function renderWifi(status, capabilities, onAction, actionBusy) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var wifi = device.wifi && typeof device.wifi === 'object' ? device.wifi : {};
	var bands = wifi.bands && typeof wifi.bands === 'object' ? wifi.bands : {};
	var wifi24 = bands.wifi_2_4 && typeof bands.wifi_2_4 === 'object'
		? bands.wifi_2_4 : {};
	var wifi5 = bands.wifi_5 && typeof bands.wifi_5 === 'object'
		? bands.wifi_5 : {};
	var primary = wifi.primary && typeof wifi.primary === 'object'
		? wifi.primary : {};
	var guest = wifi.guest && typeof wifi.guest === 'object' ? wifi.guest : {};
	var advanced = wifi.advanced && typeof wifi.advanced === 'object'
		? wifi.advanced : {};
	var isU30 = profileIsU30(status, capabilities);

	var children = [
		row(_('Wi-Fi 开关'), enabledLabel(wifi.enabled)),
		row(_('访客网络'), enabledLabel(wifi.guest_enabled)),
		row(_('2.4 GHz SSID'), wifi24.ssid),
		row(_('2.4 GHz 安全模式'), wifi24.auth_mode),
		row(_('2.4 GHz 客户端'), wifi24.clients)
	];
	if (!isU30) {
		children.push(
			row(_('5 GHz SSID'), wifi5.ssid),
			row(_('5 GHz 安全模式'), wifi5.auth_mode),
			row(_('5 GHz 客户端'), wifi5.clients)
		);
	}
	children = children.concat([
		row(_('无线开关原始值'), wifi.radio_off_raw),
		row(_('主网络 SSID'), primary.ssid),
		row(_('主网络安全模式'), primary.auth_mode),
		row(_('主网络隐藏原始值'), primary.hidden_raw),
		row(_('主网络最大客户端'), primary.max_clients_raw),
		row(_('主网络隔离原始值'), primary.isolation_raw),
		row(_('访客 SSID'), guest.ssid),
		row(_('访客安全模式'), guest.auth_mode),
		row(_('访客隐藏原始值'), guest.hidden_raw),
		row(_('访客最大客户端'), guest.max_clients_raw),
		row(_('访客隔离原始值'), guest.isolation_raw),
		row(_('无线模式原始值'), advanced.mode_raw),
		row(_('国家/地区原始值'), advanced.country_raw),
		row(_('信道原始值'), advanced.channel_raw),
		row(_('带宽原始值'), advanced.bandwidth_raw),
		row(_('覆盖范围原始值'), advanced.coverage_raw),
		row(_('休眠状态原始值'), wifi.sleep_status_raw)
	]);
	if (isU30)
		children.push(row(_('U30 Wi-Fi 约束'),
			_('U30 仅支持 2.4 GHz，信道固定为自动')));
	if (capabilities.set_wifi === true) {
		var enabled = actionInput('wifi-enabled', 'checkbox', wifi.enabled !== false);
		var band = isU30 ? null : actionSelect('wifi-band',
			[ [ '2g', '2.4 GHz' ], [ '5g', '5 GHz' ] ], '2g');
		var ssid = actionInput('wifi-ssid', 'text', wifi24.ssid || '');
		var security = actionSelect('wifi-security', [
			[ 'open', _('开放') ], [ 'wpa2_psk', 'WPA2-PSK' ],
			[ 'wpa3_sae', 'WPA3-SAE' ], [ 'wpa2_wpa3', 'WPA2/WPA3' ]
		], 'wpa2_psk');
		var wifiPassword = actionInput('wifi-password', 'password', '');
		var channel = isU30 ? null : actionInput('wifi-channel', 'text', 'auto');
		var wifiRows = [ actionRow(_('启用'), enabled) ];
		if (!isU30)
			wifiRows.push(actionRow(_('频段'), band));
		wifiRows.push(actionRow(_('SSID'), ssid), actionRow(_('安全模式'), security),
			actionRow(_('密码'), wifiPassword));
		if (!isU30)
			wifiRows.push(actionRow(_('信道'), channel));
		wifiRows.push(
			actionButton(_('保存 Wi-Fi 设置'), actionBusy, function() {
				var request = { action: 'set_wifi', enabled: enabled.checked === true };
				if (request.enabled) {
					request.band = isU30 ? '2g' : band.value; request.ssid = ssid.value;
					request.security = security.value;
					if (security.value !== 'open')
						request['password'] = wifiPassword.value;
					request.channel = isU30 ? 'auto' : channel.value;
				}
				return onAction('wifi', request, _('Wi-Fi 设置'));
			})
		);
		children.push(actionSection(_('Wi-Fi 设置'), wifiRows));
	}
	return panelRoot('wifi', _('设备 Wi-Fi'), children);
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

function renderClients(status, capabilities) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var wifi = device.wifi && typeof device.wifi === 'object' ? device.wifi : {};
	var bands = wifi.bands && typeof wifi.bands === 'object' ? wifi.bands : {};
	var wifi24 = bands.wifi_2_4 && typeof bands.wifi_2_4 === 'object'
		? bands.wifi_2_4 : {};
	var wifi5 = bands.wifi_5 && typeof bands.wifi_5 === 'object'
		? bands.wifi_5 : {};
	var clients = device.clients && typeof device.clients === 'object'
		? device.clients : {};
	var isU30 = profileIsU30(status, capabilities);
	var items = clients.available === true && Array.isArray(clients.items)
		? clients.items.slice(0, 64) : [];
	var total = null;

	if (isU30 && typeof wifi24.clients === 'number' && wifi24.clients >= 0)
		total = wifi24.clients;
	else if (!isU30 && typeof wifi24.clients === 'number' && wifi24.clients >= 0 &&
		typeof wifi5.clients === 'number' && wifi5.clients >= 0)
		total = wifi24.clients + wifi5.clients;

	var rows = [
		row(_('接入设备总数'), total),
		row(_('2.4 GHz 客户端'), wifi24.clients)
	];
	if (!isU30)
		rows.push(row(_('5 GHz 客户端'), wifi5.clients));
	rows.push(row(_('明细状态'), clientCollectionLabel(clients, items.length)));
	items.forEach(function(client, index) {
		if (client && typeof client === 'object')
			rows.push(row(_('客户端 ') + (index + 1), clientDetailLabel(client)));
	});
	return panelRoot('clients', _('接入设备'), rows);
}

function smsCollectionLabel(messages, count) {
	if (messages.available === true)
		return _('已加载') + '（' + count + ' ' + _('条') + '）';
	switch (messages.reason) {
	case 'credentials_missing':
		return _('未配置设备管理密码');
	case 'authentication_failed':
		return _('设备认证失败，已暂停重试');
	case 'authentication_backoff':
		return _('认证重试冷却中');
	case 'read_failed':
		return _('短信收件箱读取失败');
	case 'not_loaded':
		return _('短信收件箱尚未加载');
	default:
		return _('当前快照尚未提供短信收件箱');
	}
}

function decodeSmsContent(value) {
	var groups;
	if (typeof value !== 'string' || value === '')
		return null;
	groups = value.match(/[A-Fa-f0-9]{1,4}/g);
	if (!groups || groups.join('') !== value)
		return value;
	return groups.map(function(group) {
		return String.fromCharCode(parseInt(group, 16));
	}).join('');
}

function renderSms(status, messagesResult, capabilities, onAction, actionBusy) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var sms = device.sms && typeof device.sms === 'object' ? device.sms : {};
	var messages = messagesResult && messagesResult.ok && messagesResult.value &&
		typeof messagesResult.value === 'object' ? messagesResult.value : {};
	var items = messages.available === true && Array.isArray(messages.items)
		? messages.items.slice(0, 50) : [];
	var rows = [
		row(_('短信总数'), sms.total),
		row(_('收件箱状态'), messagesResult && messagesResult.ok
			? smsCollectionLabel(messages, items.length)
			: _('无法读取短信缓存'))
	];

	items.forEach(function(message, index) {
		if (!message || typeof message !== 'object')
			return;
		rows.push(row(_('短信 ') + (index + 1), [
			dash(message.number_raw),
			message.date_raw ? ' · ' + message.date_raw : '',
			message.tag === '1' ? ' · ' + _('未读') : ''
		]));
		rows.push(row(_('正文 ') + (index + 1),
			decodeSmsContent(message.content_encoded)));
		rows.push(row(_('消息 ID ') + (index + 1), message.id));
	});
	if (capabilities.send_sms === true) {
		var number = actionInput('sms-number', 'text', '');
		var content = E('textarea', {
			'class': 'cbi-input-textarea', 'data-purpose': 'sms-content',
			'maxlength': '700'
		}, '');
		content.value = '';
		rows.push(actionSection(_('发送短信'), [
			actionRow(_('号码'), number), actionRow(_('内容'), content),
			actionButton(_('发送短信'), actionBusy, function() {
				return onAction('sms', {
					action: 'send_sms', number: number.value, content: content.value
				}, _('短信发送'));
			})
		]));
	}
	if (capabilities.delete_sms === true || capabilities.mark_sms_read === true) {
		var messageId = actionInput('sms-message-id', 'text', '');
		var managementRows = [ actionRow(_('消息 ID'), messageId) ];
		if (capabilities.mark_sms_read === true)
			managementRows.push(actionButton(_('标记已读'), actionBusy, function() {
				return onAction('sms', {
					action: 'mark_sms_read', message_id: messageId.value
				}, _('短信标记'));
			}));
		if (capabilities.delete_sms === true) {
			var deleteConfirmation = actionInput('delete-sms', 'checkbox', false);
			managementRows.push(
				actionRow(_('删除确认'), [ deleteConfirmation, ' ', _('我确认删除该短信') ]),
				actionButton(_('删除短信'), actionBusy, function() {
				return onAction('sms', {
					action: 'delete_sms', message_id: messageId.value, confirm: true
				}, _('短信删除'), deleteConfirmation, _('请先确认删除该短信。'));
			}));
		}
		rows.push(actionSection(_('短信管理'), managementRows));
	}
	return panelRoot('sms', _('短信'), rows);
}

function renderTraffic(status, capabilities, onAction, actionBusy) {
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

	var children = [
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
	];
	if (capabilities.set_traffic_plan === true) {
		var enabled = actionInput('traffic-enabled', 'checkbox', plan.enabled === true);
		var limit = actionInput('traffic-limit-bytes', 'number', '10737418240');
		var alertPercent = actionInput('traffic-alert-percent', 'number', plan.alert_percent || 90);
		var cycleDay = actionInput('traffic-cycle-day', 'number', plan.clear_day || 1);
		var disconnect = actionInput('traffic-disconnect', 'checkbox', plan.disconnect === true);
		children.push(actionSection(_('流量套餐'), [
			actionRow(_('启用'), enabled), actionRow(_('流量上限（字节）'), limit),
			actionRow(_('提醒阈值（%）'), alertPercent),
			actionRow(_('周期起始日'), cycleDay), actionRow(_('到量断网'), disconnect),
			actionButton(_('保存流量套餐'), actionBusy, function() {
				var request = { action: 'set_traffic_plan', enabled: enabled.checked === true };
				if (request.enabled) {
					request.limit_bytes = Number(limit.value);
					request.alert_percent = Number(alertPercent.value);
					request.cycle_day = Number(cycleDay.value);
					request.disconnect = disconnect.checked === true;
				}
				return onAction('traffic', request, _('流量套餐设置'));
			})
		]));
	}
	if (capabilities.reset_traffic === true) {
		var resetConfirmation = actionInput('reset-traffic', 'checkbox', false);
		children.push(actionSection(_('流量统计清零'), [
			actionRow(_('操作确认'), [ resetConfirmation, ' ', _('我确认清零流量统计') ]),
			actionButton(_('清零流量统计'), actionBusy, function() {
				return onAction('traffic', { action: 'reset_traffic', confirm: true },
					_('流量统计清零'), resetConfirmation, _('请先确认清零流量统计。'));
			})
		]));
	}
	return panelRoot('traffic', _('流量'), children);
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
		'class': 'cbi-input-checkbox',
		'data-purpose': 'switch-sim'
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
				return onAction('cellular', {
					action: 'switch_sim', target: targetSelect.value, confirm: true
				}, _('SIM 切换'), confirmation,
				_('请先确认该操作会短暂中断蜂窝网络。'));
			}
		}, _('切换 SIM'))
	];
	return E('div', { 'class': 'cbi-section zte-sim-action' },
		[ E('h4', {}, _('SIM 切换')) ].concat(children));
}

function renderChargingSettings(settingsResult, onSave, notice, busy) {
	var settings = settingsResult && settingsResult.ok && settingsResult.value &&
		typeof settingsResult.value === 'object' ? settingsResult.value : {};
	var enabled = actionInput('smart-charge-enabled', 'checkbox', settings.enabled === true);
	var low = actionInput('smart-charge-low', 'number',
		settings.low_percent === undefined ? 30 : settings.low_percent);
	var high = actionInput('smart-charge-high', 'number',
		settings.high_percent === undefined ? 80 : settings.high_percent);
	low.attrs.min = '30';
	low.attrs.max = '99';
	low.attrs.step = '1';
	high.attrs.min = '31';
	high.attrs.max = '100';
	high.attrs.step = '1';

	return E('div', { 'class': 'cbi-section zte-charging-settings' }, [
		E('h4', {}, _('智能充电设置')),
		settingsResult && settingsResult.ok === false
			? E('div', { 'class': 'alert-message error' },
				_('无法读取智能充电设置，请检查 rpcd 服务。')) : null,
		notice ? E('div', { 'class': 'alert-message ' + notice.level }, notice.message) : null,
		actionRow(_('启用自动充放电'), enabled),
		actionRow(_('低电量开始充电（%）'), low),
		actionRow(_('高电量切换直供（%）'), high),
		E('div', { 'class': 'cbi-value-description' },
			_('该策略只切换 U30 Pro 内部的充电/电源直供模式，不会关闭 USB 数据连接。实际写入仍受管理员写操作开关和设备能力校准限制。')),
		E('button', {
			'class': 'cbi-button cbi-button-apply',
			'type': 'button',
			'disabled': busy ? 'disabled' : null,
			'click': function() {
				return onSave(enabled.checked === true, Number(low.value), Number(high.value));
			}
		}, _('保存智能充电设置'))
	]);
}

function renderDevice(status, capabilities, onAction, actionNotice, actionBusy,
	chargingSettingsResult, onChargingSave, chargingNotice, chargingBusy) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var sim = device.sim && typeof device.sim === 'object' ? device.sim : {};
	var battery = device.battery && typeof device.battery === 'object' ? device.battery : {};
	var upgrade = device.upgrade && typeof device.upgrade === 'object' ? device.upgrade : {};
	var powerSupply = device.power_supply && typeof device.power_supply === 'object'
		? device.power_supply : {};
	var model = deviceModel(status, capabilities);
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
		row(_('供电模式'), powerSupplyModeLabel(powerSupply)),
		row(_('温度级别'), battery.temperature_level)
	];

	if (String(model).toLowerCase().indexOf('u30') !== -1)
		children.push(renderChargingSettings(chargingSettingsResult,
			onChargingSave, chargingNotice, chargingBusy));

	if (capabilities.set_power_supply_mode === true) {
		children.push(actionSection(_('智能充电与电源直供'), [
			row(_('当前模式'), powerSupplyModeLabel(powerSupply)),
			E('div', { 'class': 'cbi-value-description' },
				_('这里只切换 U30 Pro 内部供电模式，不会关闭 USB 数据连接。')),
			actionButton(_('开始充电'), actionBusy, function() {
				return onAction('power', {
					action: 'set_power_supply_mode', mode: 'charging'
				}, _('开始充电'));
			}),
			actionButton(_('切换电源直供'), actionBusy, function() {
				return onAction('power', {
					action: 'set_power_supply_mode', mode: 'direct_supply'
				}, _('电源直供切换'));
			})
		]));
	}

	if (capabilities.switch_sim === true)
		children.push(renderSimSwitch(sim, onAction, actionBusy));

	if (capabilities.reboot_device === true || capabilities.shutdown_device === true) {
		[ {
			action: 'reboot_device',
			capability: 'reboot_device',
			purpose: 'device-reboot-confirm',
			label: _('重启 ') + model,
			warning: _('我确认重启会暂时中断移动网络连接。')
		}, {
			action: 'shutdown_device',
			capability: 'shutdown_device',
			purpose: 'device-shutdown-confirm',
			label: _('关闭 ') + model,
			warning: _('我确认关机后需要人工恢复设备供电或开机。')
		} ].forEach(function(definition) {
			if (capabilities[definition.capability] !== true)
				return;
			var confirmation = E('input', {
				'type': 'checkbox',
				'class': 'cbi-input-checkbox',
				'data-purpose': definition.purpose
			});
			children.push(E('div', { 'class': 'cbi-section zte-device-action' }, [
				E('label', { 'class': 'cbi-value' }, [ confirmation, ' ', definition.warning ]),
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'type': 'button',
					'disabled': actionBusy ? 'disabled' : null,
					'click': function() {
						return onAction('device', {
							action: definition.action,
							confirm: true
						}, definition.label, confirmation, definition.warning);
					}
				}, definition.label)
			]));
		});
	}

	return panelRoot('device', _('设备'), children);
}

function capabilityReadinessLabel(feature) {
	var implementation = feature && typeof feature === 'object'
		? feature.implementation : null;
	var verification = feature && typeof feature === 'object'
		? feature.verification : null;
	var access = feature && typeof feature === 'object' ? feature.access : null;
	if (access !== 'read' && access !== 'write')
		return _('不可用');
	if (implementation === 'native_console_only' && verification === 'native_console')
		return _('仅支持在 U25S 原生控制台操作');
	if (implementation === 'not_implemented')
		return _('尚未实现');
	if (implementation !== 'implemented')
		return _('不可用');
	if (verification === 'local_and_qemu')
		return _('已实现（本地与 QEMU 已验证）');
	if (verification === 'simulator_only')
		return _('已实现（模拟器已验证，需设备认证）');
	if (verification === 'spare_device_required')
		return _('已实现，等待备用设备实机校准');
	return _('不可用');
}

function renderCapabilityMatrix(capabilities) {
	var featureStatus = capabilities && typeof capabilities.feature_status === 'object'
		? capabilities.feature_status : null;
	var definitions = [
		[ 'cellular_read', _('移动网络状态') ],
		[ 'wifi_read', _('U25S Wi-Fi 状态') ],
		[ 'clients_read', _('接入设备明细') ],
		[ 'traffic_read', _('流量状态') ],
		[ 'sms_read', _('短信收件箱') ],
		[ 'device_read', _('设备状态') ],
		[ 'switch_sim', _('SIM 切换') ],
		[ 'set_apn', _('APN 设置') ],
		[ 'set_connection_mode', _('连接模式设置') ],
		[ 'set_wifi', _('Wi-Fi 设置') ],
		[ 'set_traffic_plan', _('流量套餐设置') ],
		[ 'reset_traffic', _('流量统计清零') ],
		[ 'send_sms', _('发送短信') ],
		[ 'delete_sms', _('删除短信') ],
		[ 'mark_sms_read', _('标记短信已读') ],
		[ 'reboot_device', _('设备重启') ],
		[ 'shutdown_device', _('设备关机') ],
		[ 'set_power_supply_mode', _('智能充电/电源直供') ],
		[ 'firmware_update', _('固件更新') ],
		[ 'factory_reset', _('恢复出厂设置') ],
		[ 'backup_restore', _('备份与恢复') ],
		[ 'device_password', _('设备密码') ]
	];
	if (!featureStatus)
		return [ row(_('能力矩阵'), _('当前后端未提供能力明细')) ];
	return definitions.map(function(definition) {
		return row(definition[1], capabilityReadinessLabel(featureStatus[definition[0]]));
	});
}

function renderDiagnostics(status, capabilities) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var power = status.power && typeof status.power === 'object' ? status.power : {};
	var recovery = power.recovery && typeof power.recovery === 'object'
		? power.recovery : {};
	var hasDevice = Object.keys(device).length > 0;

	return panelRoot('diagnostics', _('系统与诊断'), [
		row(_('设备适配器'), capabilities.adapter || device.adapter),
		row(_('管理传输'), capabilities.transport === 'https' ? 'HTTPS' :
			(capabilities.transport === 'http' ? 'HTTP' : null)),
		row(_('TLS 验证'), capabilities.tls_verification ===
			'device_certificate_unverified' ? _('设备证书未验证') :
			(capabilities.tls_verification === 'verified' ? _('已验证') : null)),
		row(_('后端状态'), stateLabel(status.state, hasDevice)),
		row(_('失败次数'), status.failures),
		row(_('缺失字段'), device.missing),
		row(_('USB 供电读回'), power.observed),
		row(_('恢复服务可用'), yesNoLabel(recovery.service_available)),
		E('div', { 'class': 'alert-message warning' },
			_('USB 断电会中断数据连接，仅用于故障恢复。')),
		E('h3', {}, _('能力与校准状态')),
		renderCapabilityMatrix(capabilities)
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

function renderPanel(tabId, status, capabilities, logsResult, smsResult, onAction,
	actionNotice, actionBusy, chargingSettingsResult, onChargingSave,
	chargingNotice, chargingBusy) {
	switch (tabId) {
	case 'network':
		return renderNetwork(status, capabilities, onAction, actionBusy);
	case 'wifi':
		return renderWifi(status, capabilities, onAction, actionBusy);
	case 'clients':
		return renderClients(status, capabilities);
	case 'traffic':
		return renderTraffic(status, capabilities, onAction, actionBusy);
	case 'sms':
		return renderSms(status, smsResult, capabilities, onAction, actionBusy);
	case 'device':
		return renderDevice(status, capabilities, onAction, actionNotice, actionBusy,
			chargingSettingsResult, onChargingSave, chargingNotice, chargingBusy);
	case 'diagnostics':
		return renderDiagnostics(status, capabilities);
	case 'logs':
		return renderLogs(logsResult);
	default:
		return renderOverview(status, capabilities);
	}
}

function renderStatus(data, selectedTab, onSelect, onCredentialSave,
	onCredentialClear, credentialNotice, onAction, actionNotice, actionBusy,
	onChargingSave, chargingNotice, chargingBusy) {
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
		var smsResult = data && data[4] && typeof data[4] === 'object'
			? data[4] : { ok: false, value: {} };
		var chargingSettingsResult = data && data[5] && typeof data[5] === 'object'
			? data[5] : { ok: false, value: {} };
		var alerts = [];
		var consoleUrl = nativeConsoleUrl(status, capabilities);
		var currentModel = deviceModel(status, capabilities);

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

		var writesAvailable = [
			'switch_sim', 'set_apn', 'set_connection_mode', 'set_wifi',
			'set_traffic_plan', 'reset_traffic', 'send_sms', 'delete_sms',
			'mark_sms_read', 'reboot_device', 'shutdown_device',
			'set_power_supply_mode'
		].some(function(action) { return capabilities[action] === true; });
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('中兴随身 WiFi 管理')),
			consoleUrl ? E('p', { 'class': 'zte-native-console' }, [
				E('a', {
					'href': consoleUrl,
					'target': '_blank',
					'rel': 'noreferrer noopener'
				}, _('打开 ') + currentModel + _(' 原生控制台'))
			]) : null,
			alerts,
			renderCredentialEntry(credentialsResult, onCredentialSave,
				onCredentialClear, credentialNotice),
			E('div', { 'class': 'zte-tabs' }, tabs.map(function(tab) {
				return renderTab(tab, tab.id === selectedTab, onSelect);
			})),
			renderPanel(selectedTab, status, capabilities, logsResult, smsResult,
				onAction, actionNotice, actionBusy, chargingSettingsResult,
				onChargingSave, chargingNotice, chargingBusy),
			E('div', { 'class': 'alert-message warning' },
				writesAvailable
					? _('仅显示已通过实机校准并由管理员启用的写操作；详细能力状态见“系统与诊断”。')
					: _('详细能力状态见“系统与诊断”；未校准操作不会显示为可用控件。'))
		]);
}

return view.extend({
	load: loadData,

	render: function(data) {
		var currentData = data;
		var credentialNotice = null;
		var actionNotice = null;
		var chargingNotice = null;
		var chargingSaving = false;
		var currentOperationId = null;
		var actionSubmitting = false;
		var operationGeneration = 0;
		var currentOperationLabel = null;
		var root;

		function renderCurrent() {
			return renderStatus(
				currentData,
				activeTab,
				selectTab,
				saveCredentials,
				clearCredentials,
				credentialNotice,
				submitAction,
				actionNotice,
				actionSubmitting || currentOperationId !== null,
				saveChargingSettings,
				chargingNotice,
				chargingSaving
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

		function clearCredentials(confirmation) {
			if (!confirmation || confirmation.checked !== true) {
				credentialNotice = {
					level: 'error',
					message: _('请先确认清除路由器中保存的 U25S 管理密码。')
				};
				replace(renderCurrent());
				return Promise.resolve();
			}
			return Promise.resolve(callClearCredentials()).then(function(reply) {
				if (!reply || reply.ok !== true || reply.configured !== false) {
					credentialNotice = {
						level: 'error',
						message: _('本地管理凭据清除失败，请检查后端日志。')
					};
					replace(renderCurrent());
					return;
				}
				currentData[3] = { ok: true, value: { configured: false } };
				credentialNotice = {
					level: 'success',
					message: _('本地管理凭据已清除。')
				};
				replace(renderCurrent());
			}, function() {
				credentialNotice = {
					level: 'error',
					message: _('本地管理凭据清除失败，请检查 rpcd 服务和权限。')
				};
				replace(renderCurrent());
			});
		}

		function saveChargingSettings(enabled, lowPercent, highPercent) {
			if (!Number.isInteger(lowPercent) || !Number.isInteger(highPercent) ||
				lowPercent < 30 || highPercent > 100 || lowPercent >= highPercent) {
				chargingNotice = {
					level: 'error',
					message: _('低电量阈值必须为 30–99 的整数，且小于不超过 100 的高电量阈值。')
				};
				replace(renderCurrent());
				return Promise.resolve();
			}
			if (chargingSaving)
				return Promise.resolve();
			chargingSaving = true;
			chargingNotice = { level: 'info', message: _('正在保存智能充电设置。') };
			replace(renderCurrent());
			return Promise.resolve(callSetChargingSettings(
				enabled === true, lowPercent, highPercent
			)).then(function(reply) {
				chargingSaving = false;
				if (!reply || reply.ok !== true) {
					chargingNotice = {
						level: 'error',
						message: _('智能充电设置保存失败，请检查输入和后端日志。')
					};
					replace(renderCurrent());
					return;
				}
				currentData[5] = {
					ok: true,
					value: {
						enabled: reply.enabled === true,
						low_percent: Number(reply.low_percent),
						high_percent: Number(reply.high_percent)
					}
				};
				chargingNotice = {
					level: 'success',
					message: _('智能充电设置已保存。')
				};
				replace(renderCurrent());
			}, function() {
				chargingSaving = false;
				chargingNotice = {
					level: 'error',
					message: _('无法保存智能充电设置，请检查 rpcd 服务和权限。')
				};
				replace(renderCurrent());
			});
		}

		function invokeAction(method, request) {
			request = request || {};
			switch (method) {
			case 'cellular':
				return callCellularAction(request.action, request.target, request.confirm, request.apn,
					request.auth, request.username, request.password, request.mode);
			case 'wifi':
				return callWifiAction(request.action, request.enabled, request.band,
					request.ssid, request.security, request.password, request.channel);
			case 'traffic':
				return callTrafficAction(request.action, request.enabled,
					request.limit_bytes, request.alert_percent, request.cycle_day,
					request.disconnect, request.confirm);
			case 'sms':
				return callSmsAction(request.action, request.message_id, request.number,
					request.content, request.confirm);
			case 'device':
				return callDeviceAction(request.action, request.confirm);
			case 'power':
				return callPowerAction(request.action, request.mode);
			default:
				return Promise.reject(new Error('unsupported action method'));
			}
		}

		function submitAction(method, request, label, confirmation, confirmationMessage) {
			var requestGeneration;
			label = label || _('设备操作');
			if (actionSubmitting || currentOperationId !== null) {
				actionNotice = {
					level: 'info',
					message: _('已有 ') + (currentOperationLabel || _('设备操作')) +
					_('请求正在处理，请等待结果。')
				};
				replace(renderCurrent());
				return Promise.resolve();
			}
			if (confirmationMessage && (!confirmation || confirmation.checked !== true)) {
				actionNotice = {
					level: 'error',
					message: confirmationMessage
				};
				replace(renderCurrent());
				return Promise.resolve();
			}
			actionSubmitting = true;
			currentOperationLabel = label;
			operationGeneration += 1;
			requestGeneration = operationGeneration;
			actionNotice = {
				level: 'info',
				message: _('正在提交') + label + _('请求。')
			};
			replace(renderCurrent());
			return Promise.resolve(invokeAction(method, request)).then(function(reply) {
				if (requestGeneration !== operationGeneration)
					return;
				actionSubmitting = false;
				if (!reply || reply.ok !== true || typeof reply.operation_id !== 'string') {
					currentOperationLabel = null;
					actionNotice = {
						level: 'error',
						message: label + _('请求被拒绝，请检查输入、能力开关和事件日志。')
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
				currentOperationLabel = null;
				actionNotice = {
					level: 'error',
					message: _('无法提交') + label + _('请求，请检查 rpcd 服务。')
				};
				replace(renderCurrent());
			});
		}

		function refreshOperation() {
			var operationId;
			var generation;
			var operationLabel;
			if (!currentOperationId)
				return Promise.resolve();
			operationId = currentOperationId;
			generation = operationGeneration;
			operationLabel = currentOperationLabel || _('设备操作');
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
						currentOperationLabel = null;
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
					actionNotice = { level: 'success', message: operationLabel + _('已完成。') };
					currentOperationId = null;
					currentOperationLabel = null;
					operationGeneration += 1;
					break;
				case 'failed':
					actionNotice = {
						level: 'error',
						message: operationLabel + _('失败：') + dash(reply.code)
					};
					currentOperationId = null;
					currentOperationLabel = null;
					operationGeneration += 1;
					break;
				case 'timed_out':
					actionNotice = {
						level: 'error',
						message: operationLabel + _('超时：') + dash(reply.code)
					};
					currentOperationId = null;
					currentOperationLabel = null;
					operationGeneration += 1;
					break;
				case 'queued':
				case 'running':
				case 'verifying':
					actionNotice = {
						level: 'info',
						message: operationLabel + _('正在执行。')
					};
					break;
				default:
					actionNotice = {
						level: 'error',
						message: _('无法读取操作执行状态：') + dash(reply.state)
					};
					currentOperationId = null;
					currentOperationLabel = null;
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
