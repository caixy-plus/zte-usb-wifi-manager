'use strict';
'require view';
'require rpc';
'require poll';

var POLL_INTERVAL_SECONDS = 30;
var STALE_AFTER_SECONDS = 360;
var activeTab = 'device';

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

var tabs = [
	{ id: 'device', label: _('设备') },
	{ id: 'charging', label: _('智能充电') },
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
		E('label', { 'class': 'cbi-value-title' }, label),
		E('div', { 'class': 'cbi-value-field' }, dash(value))
	]);
}

function actionInput(purpose, type, value) {
	var attrs = {
		'class': type === 'checkbox' ? 'cbi-input-checkbox' : 'cbi-input-text',
		'type': type,
		'data-purpose': purpose
	};
	if (type === 'checkbox') {
		if (value)
			attrs.checked = 'checked';
	}
	else {
		attrs.value = value === null || value === undefined ? '' : String(value);
	}
	if (type === 'number') {
		attrs.min = '0';
		attrs.max = '100';
		attrs.step = '1';
	}
	return E('input', attrs);
}

function actionRow(label, control) {
	return E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title' }, label),
		E('div', { 'class': 'cbi-value-field' }, control)
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
		label = _('保护模式');
		break;
	case 'credentials_missing':
		label = _('缺少管理密码');
		break;
	case 'authentication_failed':
		label = _('认证失败');
		break;
	case 'planned_off':
		label = _('计划关闭');
		break;
	case 'framework_ready':
		label = _('框架就绪');
		break;
	case 'unsupported_device':
		label = _('不支持的设备');
		break;
	default:
		label = state || null;
	}
	if (label && state !== 'ok' && hasDevice)
		return label;
	return label;
}

function signalLabel(cellular) {
	if (cellular.rsrp !== null && cellular.rsrp !== undefined && cellular.rsrp !== '')
		return cellular.rsrp + ' dBm';
	if (cellular.signalbar !== null && cellular.signalbar !== undefined &&
		cellular.signalbar !== '')
		return cellular.signalbar + ' ' + _('格');
	return null;
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
	return device.model || status.model || capabilities.model || _('中兴随身 WiFi');
}

function batteryLabel(battery, powerSupply) {
	if (battery.present === false)
		return _('未检测到电池');
	if (battery.percent === null || battery.percent === undefined || battery.percent === '')
		return null;
	if (powerSupply && (powerSupply.direct_supply === true || powerSupply.mode_raw === '1'))
		return battery.percent + '% · ' + _('电源直供');
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
	if (updated === null || updated === undefined || updated === '')
		return null;
	var stamp = Number(updated);
	if (!Number.isFinite(stamp))
		return String(updated);
	return new Date(stamp * 1000).toLocaleString();
}

function yesNoLabel(value) {
	if (value === true)
		return _('是');
	if (value === false)
		return _('否');
	return null;
}

function chargingLabel(value, powerSupply) {
	if (powerSupply && (powerSupply.direct_supply === true || powerSupply.mode_raw === '1'))
		return _('电源直供（未给电池充电）');
	if (value === true)
		return _('充电中');
	if (value === false)
		return _('未充电');
	return null;
}

function powerSupplyModeLabel(powerSupply) {
	if (powerSupply.direct_supply === true || powerSupply.mode_raw === '1')
		return _('电源直供');
	if (powerSupply.direct_supply === false || powerSupply.mode_raw === '0')
		return _('电池充电');
	return null;
}

function enabledLabel(value) {
	if (value === true)
		return _('已启用');
	if (value === false)
		return _('已关闭');
	return null;
}

function rpcResult(call) {
	return Promise.resolve(call()).then(function(value) {
		return { ok: true, value: value };
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
		rpcResult(callChargingSettings)
	]);
}

function snapshotIsStale(updated) {
	var stamp = Number(updated);
	if (!Number.isFinite(stamp))
		return false;
	return (Date.now() / 1000) - stamp > STALE_AFTER_SECONDS;
}

function panelRoot(tabId, title, children) {
	return E('div', {
		'class': 'cbi-section zte-tab-panel',
		'data-panel': tabId
	}, [ E('h3', {}, title) ].concat(children || []));
}

function renderCredentialEntry(credentialsResult, onSave, onClear, notice) {
	var value = credentialsResult && credentialsResult.ok &&
		credentialsResult.value && typeof credentialsResult.value === 'object'
		? credentialsResult.value : {};
	var password = E('input', {
		'type': 'password',
		'class': 'cbi-input-password',
		'autocomplete': 'new-password',
		'data-purpose': 'device-password'
	});
	var clearConfirm = E('input', {
		'type': 'checkbox',
		'class': 'cbi-input-checkbox',
		'data-purpose': 'clear-credentials'
	});
	var children = [
		E('p', { 'class': 'cbi-value-description' },
			_('管理密码仅保存在本路由器，用于登录中兴 U30 Pro 设备；页面不会回显密码。')),
		row(_('本地凭据'), value.configured === true ? _('已配置') : _('未配置')),
		actionRow(_('设备管理密码'), password),
		E('div', { 'class': 'cbi-page-actions' }, [
			E('button', {
				'class': 'cbi-button cbi-button-apply',
				'type': 'button',
				'click': function() {
					return onSave(password);
				}
			}, _('保存密码'))
		]),
		E('label', { 'class': 'cbi-value' }, [
			clearConfirm, ' ',
			_('我确认清除路由器中保存的中兴设备管理密码。')
		]),
		E('div', { 'class': 'cbi-page-actions' }, [
			E('button', {
				'class': 'cbi-button cbi-button-negative',
				'type': 'button',
				'click': function() {
					return onClear(clearConfirm);
				}
			}, _('清除本地凭据'))
		])
	];
	if (notice)
		children.unshift(E('div', {
			'class': 'alert-message ' + notice.level
		}, notice.message));
	return E('div', { 'class': 'cbi-section zte-credential-entry' },
		[ E('h3', {}, _('设备凭据')) ].concat(children));
}

function renderDevice(status, capabilities, credentialsResult, onCredentialSave,
	onCredentialClear, credentialNotice) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var sim = device.sim && typeof device.sim === 'object' ? device.sim : {};
	var battery = device.battery && typeof device.battery === 'object' ? device.battery : {};
	var upgrade = device.upgrade && typeof device.upgrade === 'object' ? device.upgrade : {};
	var powerSupply = device.power_supply && typeof device.power_supply === 'object'
		? device.power_supply : {};
	var cellular = device.cellular && typeof device.cellular === 'object'
		? device.cellular : {};
	var network = status.network && typeof status.network === 'object' ? status.network : {};
	var hasDevice = Object.keys(device).length > 0;
	var model = deviceModel(status, capabilities);
	var consoleUrl = nativeConsoleUrl(status, capabilities);
	var children = [
		row(_('设备型号'), device.model || status.model || capabilities.model),
		row(_('市场名称'), device.market_name),
		row(_('固件版本'), device.firmware),
		row(_('硬件版本'), device.hardware_version),
		row(_('软件版本'), device.software_version),
		row(_('WebUI 版本'), device.webui_version),
		row(_('新版本状态'), upgrade.new_version_state),
		row(_('升级状态'), upgrade.current_state),
		row(_('Modem 状态'), device.modem_state),
		row(_('SIM 类型'), sim.type),
		row(_('活动卡槽原始值'), sim.active_slot_raw),
		row(_('网络制式'), cellular.type),
		row(_('运营商'), cellular.provider),
		row(_('信号'), signalLabel(cellular)),
		row(_('电池存在'), yesNoLabel(battery.present)),
		row(_('电量'), battery.percent === null || battery.percent === undefined ||
			battery.percent === '' ? null : battery.percent + '%'),
		row(_('充电状态'), chargingLabel(battery.charging, powerSupply)),
		row(_('供电模式'), powerSupplyModeLabel(powerSupply)),
		row(_('温度级别'), battery.temperature_level),
		row(_('设备在线'), onlineLabel(status)),
		row(_('后端状态'), stateLabel(status.state, hasDevice)),
		row(_('USB 上联'), uplinkLabel(network)),
		row(_('默认出口'), yesNoLabel(network.is_default_route)),
		row(_('状态快照时间'), updatedLabel(status.updated))
	];

	if (consoleUrl) {
		children.push(E('div', { 'class': 'cbi-section zte-native-console' }, [
			E('h4', {}, _('设备原生管理页')),
			E('p', { 'class': 'cbi-value-description' },
				_('未整合到本插件的功能，请在设备原生页面操作。')),
			E('p', {}, [
				E('a', {
					'href': consoleUrl,
					'target': '_blank',
					'rel': 'noreferrer noopener'
				}, _('打开 ') + model + _(' 原生管理页'))
			])
		]));
	}

	children.push(renderCredentialEntry(credentialsResult, onCredentialSave,
		onCredentialClear, credentialNotice));

	return panelRoot('device', _('设备基础信息'), children);
}

function smartChargeStatusLabel(status) {
	var smart = status.smart_charge && typeof status.smart_charge === 'object'
		? status.smart_charge : null;
	if (!smart)
		return null;
	if (smart.last_error)
		return _('最近错误') + ': ' + smart.last_error;
	if (smart.retry_after)
		return _('冷却中，稍后重试');
	if (smart.enabled === true)
		return _('策略已启用');
	if (smart.enabled === false)
		return _('策略已关闭');
	return null;
}

function renderCharging(status, capabilities, settingsResult, onSave, notice, busy) {
	var device = status.device && typeof status.device === 'object' ? status.device : {};
	var battery = device.battery && typeof device.battery === 'object' ? device.battery : {};
	var powerSupply = device.power_supply && typeof device.power_supply === 'object'
		? device.power_supply : {};
	var settings = settingsResult && settingsResult.ok &&
		settingsResult.value && typeof settingsResult.value === 'object'
		? settingsResult.value : {};
	var enabled = actionInput('smart-charge-enabled', 'checkbox',
		settings.enabled === true);
	var low = actionInput('smart-charge-low', 'number',
		settings.low_percent === undefined || settings.low_percent === null
			? 30 : settings.low_percent);
	var high = actionInput('smart-charge-high', 'number',
		settings.high_percent === undefined || settings.high_percent === null
			? 80 : settings.high_percent);
	var children = [
		E('p', { 'class': 'cbi-value-description' },
			_('智能充电只切换 U30 Pro 设备内部供电模式：低电量改为电池充电，高电量改为电源直供。不会断开 USB 数据连接。')),
		row(_('当前电量'), battery.percent === null || battery.percent === undefined ||
			battery.percent === '' ? null : battery.percent + '%'),
		row(_('当前供电模式'), powerSupplyModeLabel(powerSupply)),
		row(_('当前充电状态'), chargingLabel(battery.charging, powerSupply)),
		row(_('策略运行状态'), smartChargeStatusLabel(status)),
		row(_('设备写能力'), capabilities.set_power_supply_mode === true
			? _('可用') : _('不可用'))
	];

	if (notice)
		children.push(E('div', {
			'class': 'alert-message ' + notice.level
		}, notice.message));

	children.push(E('div', { 'class': 'cbi-section zte-charging-settings' }, [
		E('h4', {}, _('自动策略')),
		actionRow(_('启用智能充电'), enabled),
		actionRow(_('低电量阈值 (%)'), low),
		actionRow(_('高电量阈值 (%)'), high),
		E('p', { 'class': 'cbi-value-description' },
			_('低阈值须为 30–99 的整数，且必须小于不超过 100 的高阈值。')),
		E('div', { 'class': 'cbi-page-actions' }, [
			E('button', {
				'class': 'cbi-button cbi-button-apply',
				'type': 'button',
				'disabled': busy ? 'disabled' : null,
				'click': function() {
					return onSave(
						enabled.checked === true,
						parseInt(low.value, 10),
						parseInt(high.value, 10)
					);
				}
			}, busy ? _('保存中…') : _('保存设置'))
		])
	]));

	return panelRoot('charging', _('智能充电'), children);
}

function renderLogs(logsResult) {
	var payload = logsResult && logsResult.ok && logsResult.value &&
		typeof logsResult.value === 'object' ? logsResult.value : {};
	var events = Array.isArray(payload.events) ? payload.events : [];
	var children = [
		E('p', { 'class': 'cbi-value-description' },
			_('仅显示智能充电插件相关事件。'))
	];
	if (!logsResult || !logsResult.ok)
		children.push(E('div', { 'class': 'alert-message error' },
			_('无法读取事件日志。')));
	else if (!events.length)
		children.push(E('div', { 'class': 'alert-message notice' },
			_('暂无智能充电事件。')));
	else {
		children = children.concat(events.slice().reverse().map(function(event) {
			event = event && typeof event === 'object' ? event : {};
			return E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' },
					updatedLabel(event.time) || dash(event.time)),
				E('div', { 'class': 'cbi-value-field' }, [
					dash(event.level),
					' · ',
					dash(event.type),
					' · ',
					dash(event.code)
				])
			]);
		}));
	}
	return panelRoot('logs', _('智能充电日志'), children);
}

function renderPanel(tabId, status, capabilities, logsResult, credentialsResult,
	onCredentialSave, onCredentialClear, credentialNotice,
	chargingSettingsResult, onChargingSave, chargingNotice, chargingBusy) {
	switch (tabId) {
	case 'charging':
		return renderCharging(status, capabilities, chargingSettingsResult,
			onChargingSave, chargingNotice, chargingBusy);
	case 'logs':
		return renderLogs(logsResult);
	default:
		return renderDevice(status, capabilities, credentialsResult,
			onCredentialSave, onCredentialClear, credentialNotice);
	}
}

function renderStatus(data, selectedTab, onSelect, onCredentialSave,
	onCredentialClear, credentialNotice, onChargingSave, chargingNotice,
	chargingBusy) {
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
	var chargingSettingsResult = data && data[4] && typeof data[4] === 'object'
		? data[4] : { ok: false, value: {} };
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
		E('h2', {}, _('中兴 U30 智能充电')),
		alerts,
		E('div', { 'class': 'zte-tabs' }, tabs.map(function(tab) {
			return renderTab(tab, tab.id === selectedTab, onSelect);
		})),
		renderPanel(selectedTab, status, capabilities, logsResult,
			credentialsResult, onCredentialSave, onCredentialClear,
			credentialNotice, chargingSettingsResult, onChargingSave,
			chargingNotice, chargingBusy)
	]);
}

return view.extend({
	load: loadData,

	render: function(data) {
		var currentData = data;
		var credentialNotice = null;
		var chargingNotice = null;
		var chargingSaving = false;
		var root;

		function renderCurrent() {
			return renderStatus(
				currentData,
				activeTab,
				selectTab,
				saveCredentials,
				clearCredentials,
				credentialNotice,
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
					message: _('请输入中兴设备管理密码。')
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
					message: _('请先确认清除路由器中保存的中兴设备管理密码。')
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
				currentData[4] = {
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

		root = renderCurrent();

		poll.add(function() {
			return loadData().then(function(nextData) {
				currentData = nextData;
				replace(renderCurrent());
			});
		}, POLL_INTERVAL_SECONDS);

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
