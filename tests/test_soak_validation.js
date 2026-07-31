'use strict';

const assert = require('assert');
const path = require('path');

const validatorPath = path.join(
	process.cwd(), 'scripts', 'verify-router-soak.js');
const { parseJsonLines, validateSamples } = require(validatorPath);

const good = [
	{ timestamp: 1000, service_running: true, pid: 123, rss_kb: 2200, fd_count: 12,
		coordinator_running: true, coordinator_pid: 456,
		coordinator_rss_kb: 500, coordinator_fd_count: 6,
		recovery_service_running: true,
		state: 'ok', status_age: 1, power: 1, recovery_inhibit: false,
		netdev_present: true, event_log_bytes: 1200 },
	{ timestamp: 87400, service_running: true, pid: 123, rss_kb: 2240, fd_count: 12,
		coordinator_running: true, coordinator_pid: 456,
		coordinator_rss_kb: 510, coordinator_fd_count: 6,
		recovery_service_running: false,
		state: 'planned_off', status_age: 2, power: 0, recovery_inhibit: true,
		netdev_present: false, event_log_bytes: 1600 },
	{ timestamp: 173800, service_running: true, pid: 123, rss_kb: 2260, fd_count: 13,
		coordinator_running: true, coordinator_pid: 456,
		coordinator_rss_kb: 505, coordinator_fd_count: 7,
		recovery_service_running: true,
		state: 'degraded', status_age: 31, power: 1, recovery_inhibit: false,
		netdev_present: true, event_log_bytes: 1900 },
	{ timestamp: 260200, service_running: true, pid: 123, rss_kb: 2250, fd_count: 12,
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
assert.throws(() => validateSamples(changed(2, { timestamp: 177401 }), options),
	/sample gap/);
assert.throws(() => validateSamples(changed(2, { state: 'mystery' }), options),
	/invalid state/);

console.log('PASS test_soak_validation (27 assertions)');
