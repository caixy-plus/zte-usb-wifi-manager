#!/usr/bin/env node
'use strict';

const fs = require('fs');

const allowedFields = new Set([
	'timestamp',
	'monotonic_seconds',
	'boot_id',
	'service_running',
	'pid',
	'manager_comm',
	'manager_start_ticks',
	'rss_kb',
	'fd_count',
	'coordinator_running',
	'coordinator_pid',
	'coordinator_comm',
	'coordinator_start_ticks',
	'coordinator_rss_kb',
	'coordinator_fd_count',
	'recovery_service_running',
	'state',
	'status_age',
	'adapter',
	'power_supply_mode',
	'failure_count',
	'action_result_count',
	'usb_discontinuity_count',
	'max_failure_count',
	'max_action_result_count',
	'power',
	'recovery_inhibit',
	'netdev_present',
	'event_log_bytes'
]);
const allowedStates = new Set([
	'ok',
	'planned_off',
	'degraded',
	'fail_safe',
	'credentials_missing'
]);

function parseJsonLines(text) {
	const lines = text.split(/\r?\n/).filter((line) => line.length > 0);
	if (lines.length === 0)
		throw new Error('no soak samples');
	return lines.map((line, index) => {
		try {
			return JSON.parse(line);
		} catch (error) {
			throw new Error(`invalid JSON line ${index + 1}`);
		}
	});
}

function requireInteger(sample, field, index, minimum = 0) {
	const value = sample[field];
	if (!Number.isSafeInteger(value) || value < minimum)
		throw new Error(`sample ${index + 1} has invalid ${field}`);
	return value;
}

function validateSample(sample, index, options) {
	if (!sample || typeof sample !== 'object' || Array.isArray(sample))
		throw new Error(`sample ${index + 1} is not an object`);
	for (const field of Object.keys(sample)) {
		if (!allowedFields.has(field))
			throw new Error(`sample ${index + 1} has forbidden field ${field}`);
	}
	for (const field of allowedFields) {
		if (!Object.prototype.hasOwnProperty.call(sample, field))
			throw new Error(`sample ${index + 1} is missing ${field}`);
	}

	requireInteger(sample, 'timestamp', index, 1);
	requireInteger(sample, 'monotonic_seconds', index);
	requireInteger(sample, 'pid', index, 1);
	requireInteger(sample, 'manager_start_ticks', index, 1);
	requireInteger(sample, 'rss_kb', index);
	requireInteger(sample, 'fd_count', index);
	requireInteger(sample, 'coordinator_pid', index, 1);
	requireInteger(sample, 'coordinator_start_ticks', index, 1);
	requireInteger(sample, 'coordinator_rss_kb', index);
	requireInteger(sample, 'coordinator_fd_count', index);
	requireInteger(sample, 'status_age', index);
	requireInteger(sample, 'failure_count', index);
	requireInteger(sample, 'action_result_count', index);
	requireInteger(sample, 'usb_discontinuity_count', index);
	requireInteger(sample, 'max_failure_count', index);
	requireInteger(sample, 'max_action_result_count', index);
	requireInteger(sample, 'event_log_bytes', index);
	if (sample.service_running !== true)
		throw new Error(`sample ${index + 1}: service was not running`);
	if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(
		sample.boot_id))
		throw new Error(`sample ${index + 1} has invalid boot_id`);
	if (sample.manager_comm !== 'zte-usb-wifi-ma')
		throw new Error(`sample ${index + 1} has invalid manager_comm`);
	if (sample.coordinator_comm !== 'zte-usb-recover')
		throw new Error(`sample ${index + 1} has invalid coordinator_comm`);
	if (sample.coordinator_running !== true)
		throw new Error(`sample ${index + 1}: coordinator was not running`);
	if (!allowedStates.has(sample.state))
		throw new Error(`sample ${index + 1} has invalid state`);
	if (sample.adapter !== 'zte_u25s' && sample.adapter !== 'zte_u30')
		throw new Error(`sample ${index + 1} has invalid adapter`);
	if (sample.adapter === 'zte_u30' &&
		!['charging', 'direct_supply'].includes(sample.power_supply_mode))
		throw new Error(`sample ${index + 1} has invalid power_supply_mode`);
	if (sample.adapter === 'zte_u25s' &&
		sample.power_supply_mode !== 'unsupported')
		throw new Error(`sample ${index + 1} has invalid power_supply_mode`);
	if (options.expectedAdapter && sample.adapter !== options.expectedAdapter)
		throw new Error(`sample ${index + 1}: unexpected adapter`);
	if (sample.failure_count > options.maxFailureCount)
		throw new Error(`sample ${index + 1}: failure count exceeded limit`);
	if (sample.action_result_count > options.maxActionResultCount)
		throw new Error(`sample ${index + 1}: action result count exceeded limit`);
	if (sample.max_failure_count < sample.failure_count)
		throw new Error(`sample ${index + 1}: invalid failure count latch`);
	if (sample.max_action_result_count < sample.action_result_count)
		throw new Error(`sample ${index + 1}: invalid action result count latch`);
	if (sample.usb_discontinuity_count > 0)
		throw new Error(`sample ${index + 1}: USB discontinuity detected`);
	if (sample.max_failure_count > options.maxFailureCount)
		throw new Error(`sample ${index + 1}: maximum failure count exceeded`);
	if (sample.max_action_result_count > options.maxActionResultCount)
		throw new Error(
			`sample ${index + 1}: maximum action result count exceeded`);
	if (sample.power !== 0 && sample.power !== 1)
		throw new Error(`sample ${index + 1} has invalid power`);
	if (typeof sample.recovery_service_running !== 'boolean' ||
		typeof sample.recovery_inhibit !== 'boolean' ||
		typeof sample.netdev_present !== 'boolean')
		throw new Error(`sample ${index + 1} has invalid boolean field`);
	if (sample.power === 0 && sample.recovery_inhibit !== true)
		throw new Error(`sample ${index + 1}: power-off without recovery inhibit`);
	if (sample.power === 0 && sample.recovery_service_running !== false)
		throw new Error(
			`sample ${index + 1}: recovery service active during power-off`);
	if (sample.power === 1 &&
		(sample.recovery_inhibit !== false ||
			sample.recovery_service_running !== true))
		throw new Error(
			`sample ${index + 1}: power-on recovery coordination incomplete`);
	if (sample.adapter === 'zte_u30' &&
		(sample.power !== 1 || sample.netdev_present !== true))
		throw new Error(`sample ${index + 1}: U30 USB continuity lost`);
	if (sample.event_log_bytes > options.maxEventLogBytes)
		throw new Error(`sample ${index + 1}: event log exceeded limit`);
	if (sample.status_age > options.maxStatusAgeSeconds)
		throw new Error(`sample ${index + 1}: stale status`);
}

function validateSamples(samples, options) {
	if (!Array.isArray(samples) || samples.length < 2)
		throw new Error('at least two soak samples are required');
	const settings = Object.assign({
		minDurationSeconds: 259200,
		maxRssGrowthKb: 2048,
		maxFdGrowth: 4,
		maxStatusAgeSeconds: 180,
		maxEventLogBytes: 524288,
		maxSampleGapSeconds: 180,
		maxPidChanges: 0,
		maxFailureCount: 3,
		maxActionResultCount: 50,
		expectedAdapter: null,
		testMode: false
	}, options || {});
	if (typeof settings.testMode !== 'boolean')
		throw new Error('invalid testMode');
	if (settings.expectedAdapter !== null &&
		settings.expectedAdapter !== 'zte_u25s' &&
		settings.expectedAdapter !== 'zte_u30')
		throw new Error('invalid expectedAdapter');
	if (!settings.testMode && settings.minDurationSeconds < 259200)
		throw new Error('minimum 72-hour duration is required');
	for (const field of [
		'minDurationSeconds',
		'maxRssGrowthKb',
		'maxFdGrowth',
		'maxStatusAgeSeconds',
		'maxEventLogBytes',
		'maxSampleGapSeconds',
		'maxPidChanges',
		'maxFailureCount',
		'maxActionResultCount'
	]) {
		if (!Number.isSafeInteger(settings[field]) || settings[field] < 0)
			throw new Error(`invalid ${field}`);
	}

	samples.forEach((sample, index) =>
		validateSample(sample, index, settings));
	let maxSampleGap = 0;
	let pidChanges = 0;
	let coordinatorPidChanges = 0;
	const managerStarts = new Map();
	const coordinatorStarts = new Map();
	for (const sample of samples) {
		if (managerStarts.has(sample.pid) &&
			managerStarts.get(sample.pid) !== sample.manager_start_ticks)
			throw new Error('manager process identity changed');
		managerStarts.set(sample.pid, sample.manager_start_ticks);
		if (coordinatorStarts.has(sample.coordinator_pid) &&
			coordinatorStarts.get(sample.coordinator_pid) !==
				sample.coordinator_start_ticks)
			throw new Error('coordinator process identity changed');
		coordinatorStarts.set(
			sample.coordinator_pid, sample.coordinator_start_ticks);
	}
	for (let index = 1; index < samples.length; index += 1) {
		if (samples[index].usb_discontinuity_count <
			samples[index - 1].usb_discontinuity_count)
			throw new Error('USB discontinuity latch decreased');
		if (samples[index].max_failure_count <
			samples[index - 1].max_failure_count)
			throw new Error('failure count latch decreased');
		if (samples[index].max_action_result_count <
			samples[index - 1].max_action_result_count)
			throw new Error('action result latch decreased');
		if (samples[index].adapter !== samples[0].adapter)
			throw new Error('adapter changed during soak');
		if (samples[index].boot_id !== samples[0].boot_id)
			throw new Error('boot ID changed during soak');
		if (samples[index].timestamp <= samples[index - 1].timestamp)
			throw new Error('sample timestamps must be strictly increasing');
		if (samples[index].monotonic_seconds <=
			samples[index - 1].monotonic_seconds)
			throw new Error('sample monotonic time must be strictly increasing');
		const gap = samples[index].monotonic_seconds -
			samples[index - 1].monotonic_seconds;
		maxSampleGap = Math.max(maxSampleGap, gap);
		if (gap > settings.maxSampleGapSeconds)
			throw new Error(`sample gap ${gap}s exceeded limit`);
		if (samples[index].pid !== samples[index - 1].pid)
			pidChanges += 1;
		if (samples[index].coordinator_pid !==
			samples[index - 1].coordinator_pid)
			coordinatorPidChanges += 1;
	}
	if (pidChanges > settings.maxPidChanges)
		throw new Error(`daemon PID changes ${pidChanges} exceeded limit`);
	if (coordinatorPidChanges > settings.maxPidChanges)
		throw new Error(
			`coordinator PID changes ${coordinatorPidChanges} exceeded limit`);

	const duration = samples[samples.length - 1].monotonic_seconds -
		samples[0].monotonic_seconds;
	if (duration < settings.minDurationSeconds)
		throw new Error(`soak duration ${duration}s is below required duration`);
	const rssValues = samples.map((sample) => sample.rss_kb);
	const fdValues = samples.map((sample) => sample.fd_count);
	const coordinatorRssValues = samples.map(
		(sample) => sample.coordinator_rss_kb);
	const coordinatorFdValues = samples.map(
		(sample) => sample.coordinator_fd_count);
	const maxRss = Math.max(...rssValues);
	const minRss = Math.min(...rssValues);
	const maxFd = Math.max(...fdValues);
	const minFd = Math.min(...fdValues);
	const maxCoordinatorRss = Math.max(...coordinatorRssValues);
	const minCoordinatorRss = Math.min(...coordinatorRssValues);
	const maxCoordinatorFd = Math.max(...coordinatorFdValues);
	const minCoordinatorFd = Math.min(...coordinatorFdValues);
	if (maxRss - minRss > settings.maxRssGrowthKb)
		throw new Error('RSS growth exceeded limit');
	if (maxFd - minFd > settings.maxFdGrowth)
		throw new Error('file-descriptor growth exceeded limit');
	if (maxCoordinatorRss - minCoordinatorRss > settings.maxRssGrowthKb)
		throw new Error('coordinator RSS growth exceeded limit');
	if (maxCoordinatorFd - minCoordinatorFd > settings.maxFdGrowth)
		throw new Error('coordinator file-descriptor growth exceeded limit');

	const thresholds = {
		minDurationSeconds: settings.minDurationSeconds,
		maxRssGrowthKb: settings.maxRssGrowthKb,
		maxFdGrowth: settings.maxFdGrowth,
		maxStatusAgeSeconds: settings.maxStatusAgeSeconds,
		maxEventLogBytes: settings.maxEventLogBytes,
		maxSampleGapSeconds: settings.maxSampleGapSeconds,
		maxPidChanges: settings.maxPidChanges,
		maxFailureCount: settings.maxFailureCount,
		maxActionResultCount: settings.maxActionResultCount,
		expectedAdapter: settings.expectedAdapter
	};
	return {
		ok: true,
		test_mode: settings.testMode,
		thresholds,
		duration_seconds: duration,
		samples: samples.length,
		max_rss_kb: maxRss,
		max_fd_count: maxFd,
		max_coordinator_rss_kb: maxCoordinatorRss,
		max_coordinator_fd_count: maxCoordinatorFd,
		max_sample_gap_seconds: maxSampleGap,
		pid_changes: pidChanges,
		coordinator_pid_changes: coordinatorPidChanges,
		usb_discontinuity_count:
			samples[samples.length - 1].usb_discontinuity_count,
		max_failure_count: samples[samples.length - 1].max_failure_count,
		max_action_result_count:
			samples[samples.length - 1].max_action_result_count,
		final_state: samples[samples.length - 1].state
	};
}

function parseCli(argv) {
	if (argv.length < 1)
		throw new Error('usage: verify-router-soak.js FILE [options]');
	const result = {
		file: argv[0],
		options: {}
	};
	const mappings = {
		'--duration': 'minDurationSeconds',
		'--max-rss-growth-kb': 'maxRssGrowthKb',
		'--max-fd-growth': 'maxFdGrowth',
		'--max-status-age': 'maxStatusAgeSeconds',
		'--max-event-log-bytes': 'maxEventLogBytes',
		'--max-sample-gap': 'maxSampleGapSeconds',
		'--max-pid-changes': 'maxPidChanges',
		'--max-failures': 'maxFailureCount',
		'--max-action-results': 'maxActionResultCount'
	};
	for (let index = 1; index < argv.length;) {
		const name = argv[index];
		if (name === '--test-mode') {
			result.options.testMode = true;
			index += 1;
			continue;
		}
		if (name === '--adapter') {
			const adapter = argv[index + 1];
			if (adapter !== 'zte_u25s' && adapter !== 'zte_u30')
				throw new Error('invalid option --adapter');
			result.options.expectedAdapter = adapter;
			index += 2;
			continue;
		}
		const value = argv[index + 1];
		if (!Object.prototype.hasOwnProperty.call(mappings, name) ||
			value === undefined || !/^\d+$/.test(value))
			throw new Error(`invalid option ${name || ''}`.trim());
		result.options[mappings[name]] = Number(value);
		index += 2;
	}
	if (result.options.testMode !== true &&
		Object.prototype.hasOwnProperty.call(
			result.options, 'minDurationSeconds') &&
		result.options.minDurationSeconds < 259200)
		throw new Error('minimum 72-hour duration is required');
	return result;
}

if (require.main === module) {
	try {
		const cli = parseCli(process.argv.slice(2));
		const samples = parseJsonLines(fs.readFileSync(cli.file, 'utf8'));
		process.stdout.write(
			`${JSON.stringify(validateSamples(samples, cli.options))}\n`);
	} catch (error) {
		process.stderr.write(`${error.message}\n`);
		process.exitCode = 1;
	}
}

module.exports = {
	parseJsonLines,
	validateSamples,
	parseCli
};
