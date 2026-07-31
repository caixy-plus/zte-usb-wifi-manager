'use strict';

const assert = require('assert');
const path = require('path');

const validatorPath = path.join(
	process.cwd(), 'scripts', 'verify-router-soak.js');
const { parseJsonLines, validateSamples, parseCli } = require(validatorPath);

const identity = {
	boot_id: '11111111-2222-3333-4444-555555555555',
	manager_comm: 'zte-usb-wifi-ma', manager_start_ticks: 100,
	coordinator_comm: 'zte-usb-recover',
	coordinator_start_ticks: 200
};

const good = [
	{ ...identity, timestamp: 1000, monotonic_seconds: 500, service_running: true, pid: 123, rss_kb: 2200, fd_count: 12,
		coordinator_running: true, coordinator_pid: 456,
		coordinator_rss_kb: 500, coordinator_fd_count: 6,
		recovery_service_running: true,
		state: 'ok', status_age: 1, power: 1, recovery_inhibit: false,
		netdev_present: true, event_log_bytes: 1200 },
	{ ...identity, timestamp: 87400, monotonic_seconds: 86900, service_running: true, pid: 123, rss_kb: 2240, fd_count: 12,
		coordinator_running: true, coordinator_pid: 456,
		coordinator_rss_kb: 510, coordinator_fd_count: 6,
		recovery_service_running: false,
		state: 'planned_off', status_age: 2, power: 0, recovery_inhibit: true,
		netdev_present: false, event_log_bytes: 1600 },
	{ ...identity, timestamp: 173800, monotonic_seconds: 173300, service_running: true, pid: 123, rss_kb: 2260, fd_count: 13,
		coordinator_running: true, coordinator_pid: 456,
		coordinator_rss_kb: 505, coordinator_fd_count: 7,
		recovery_service_running: true,
		state: 'degraded', status_age: 31, power: 1, recovery_inhibit: false,
		netdev_present: true, event_log_bytes: 1900 },
	{ ...identity, timestamp: 260200, monotonic_seconds: 259700, service_running: true, pid: 123, rss_kb: 2250, fd_count: 12,
		coordinator_running: true, coordinator_pid: 456,
		coordinator_rss_kb: 508, coordinator_fd_count: 6,
		recovery_service_running: true,
		state: 'ok', status_age: 1, power: 1, recovery_inhibit: false,
		netdev_present: true, event_log_bytes: 2200 }
];

const options = {
	minDurationSeconds: 259200,
	maxRssGrowthKb: 2048,
	maxFdGrowth: 4,
	maxStatusAgeSeconds: 180,
	maxEventLogBytes: 524288,
	maxSampleGapSeconds: 90000,
	maxPidChanges: 0
};

const summary = validateSamples(good, options);
assert.strictEqual(summary.ok, true);
assert.strictEqual(summary.duration_seconds, 259200);
assert.strictEqual(summary.samples, 4);
assert.strictEqual(summary.max_rss_kb, 2260);
assert.strictEqual(summary.max_fd_count, 13);
assert.strictEqual(summary.max_sample_gap_seconds, 86400);
assert.strictEqual(summary.pid_changes, 0);
assert.strictEqual(summary.coordinator_pid_changes, 0);
assert.strictEqual(summary.test_mode, false);
assert.deepStrictEqual(summary.thresholds, options);

assert.deepStrictEqual(parseJsonLines(
	good.map((sample) => JSON.stringify(sample)).join('\n') + '\n'), good);
assert.throws(() => parseJsonLines('{"timestamp":1}\nnot-json\n'),
	/invalid JSON line 2/);
assert.throws(() => parseJsonLines(''), /no soak samples/);

function changed(index, values) {
	return good.map((sample, sampleIndex) =>
		sampleIndex === index ? Object.assign({}, sample, values) : sample);
}

assert.throws(() => validateSamples(good.slice(0, 3), options),
	/duration/);
assert.throws(() => validateSamples(changed(1, { service_running: false }),
	options), /service was not running/);
assert.throws(() => validateSamples(changed(1, {
	coordinator_running: false
}), options), /coordinator was not running/);
assert.throws(() => validateSamples(changed(1, {
	power: 0,
	recovery_inhibit: false
}), options), /power-off without recovery inhibit/);
assert.throws(() => validateSamples(changed(1, {
	power: 0,
	recovery_service_running: true
}), options), /recovery service active during power-off/);
assert.throws(() => validateSamples(changed(1, {
	power: 1, recovery_inhibit: true
}), options), /power-on recovery coordination incomplete/);
assert.throws(() => validateSamples(changed(1, {
	power: 1, recovery_service_running: false
}), options), /power-on recovery coordination incomplete/);
assert.throws(() => validateSamples(changed(2, {
	event_log_bytes: 524289
}), options), /event log exceeded limit/);
assert.throws(() => validateSamples(changed(3, { rss_kb: 5000 }), options),
	/RSS growth/);
assert.throws(() => validateSamples(changed(3, { fd_count: 20 }), options),
	/file-descriptor growth/);
assert.throws(() => validateSamples(changed(2, { pid: 456 }), options),
	/PID changes/);
assert.throws(() => validateSamples(changed(2, {
	coordinator_pid: 789
}), options), /coordinator PID changes/);
assert.throws(() => validateSamples(changed(2, { status_age: 181 }), options),
	/stale status/);
assert.throws(() => validateSamples(changed(1, { status_age: 181 }), options),
	/stale status/);
assert.throws(() => validateSamples(changed(2, { unexpected_field: 'forbidden' }),
	options), /forbidden field/);
assert.throws(() => validateSamples(changed(2, { timestamp: 900 }), options),
	/timestamps/);
assert.throws(() => validateSamples(changed(2, {
	boot_id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
}), options), /boot ID changed/);
assert.throws(() => validateSamples(changed(2, {
	monotonic_seconds: 800
}), options), /monotonic/);
assert.throws(() => validateSamples(changed(2, {
	manager_start_ticks: 101
}), options), /manager process identity changed/);
const reusedPid = good.map((sample) => Object.assign({}, sample));
Object.assign(reusedPid[1], { pid: 789, manager_start_ticks: 300 });
Object.assign(reusedPid[2], { pid: 123, manager_start_ticks: 101 });
assert.throws(() => validateSamples(reusedPid, Object.assign({}, options, {
	maxPidChanges: 2
})), /manager process identity changed/);
assert.throws(() => validateSamples(changed(2, {
	manager_comm: 'unrelated-process'
}), options), /invalid manager_comm/);
assert.throws(() => validateSamples(changed(2, {
	monotonic_seconds: 176901
}), options),
	/sample gap/);
assert.throws(() => validateSamples(changed(2, { state: 'mystery' }), options),
	/invalid state/);
assert.throws(() => validateSamples(good, Object.assign({}, options, {
	minDurationSeconds: 0
})), /minimum 72-hour duration/);
assert.strictEqual(validateSamples(good, Object.assign({}, options, {
	minDurationSeconds: 0, testMode: true
})).test_mode, true);
assert.throws(() => parseCli(['samples.jsonl', '--duration', '0']),
	/minimum 72-hour duration/);
assert.strictEqual(parseCli([
	'samples.jsonl', '--test-mode', '--duration', '0'
]).options.testMode, true);

console.log('PASS test_soak_validation (41 assertions)');
