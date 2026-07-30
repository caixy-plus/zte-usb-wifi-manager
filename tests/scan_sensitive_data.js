#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const { spawnSync } = require('child_process');

const allowlistPath = 'tests/sensitive-data.allowlist';

function trackedPaths() {
    const result = spawnSync('git', ['ls-files', '-z'], {
        encoding: null,
        maxBuffer: 64 * 1024 * 1024
    });
    if (result.status !== 0 || result.error)
        throw new Error('could not enumerate tracked files');

    const paths = [];
    let start = 0;
    for (;;) {
        const end = result.stdout.indexOf(0, start);
        if (end === -1)
            break;
        if (end > start)
            paths.push(result.stdout.subarray(start, end));
        start = end + 1;
    }
    return paths;
}

function loadAllowlist() {
    try {
        return new Set(fs.readFileSync(allowlistPath, 'utf8').split(/\r?\n/));
    } catch (error) {
        if (error.code === 'ENOENT')
            return new Set();
        throw error;
    }
}

function anonymousId(pathBuffer) {
    return crypto.createHash('sha256').update(pathBuffer).digest('hex').slice(0, 12);
}

function isPlaceholder(line) {
    return /<[A-Za-z0-9_ -]+>/.test(line) ||
        /\$\{[A-Za-z0-9_]+\}/.test(line) ||
        /(^|[^A-Z])(REDACTED|PLACEHOLDER|CHANGEME|DUMMY|NOT[_ -]?SET)([^A-Z]|$)/i.test(line) ||
        /YOUR_[A-Z0-9_]+/i.test(line);
}

function findingTypes(line) {
    const types = [];
    const placeholder = isPlaceholder(line);

    if (/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/.test(line))
        types.push('PRIVATE_KEY');
    if (/authorization\s*[:=]\s*(basic|bearer)\s+\S+/i.test(line) && !placeholder)
        types.push('AUTHORIZATION');
    if (/(^|[^a-z-])(cookie|set-cookie)\s*[:=]\s*\S+/i.test(line) && !placeholder)
        types.push('HTTP_COOKIE');
    if (/(ghp_|github_pat_|glpat-|xox[baprs]-|sk-|AKIA)[A-Za-z0-9_-]{8}/.test(line) &&
        !placeholder)
        types.push('HIGH_RISK_TOKEN');
    if (/[A-Za-z][A-Za-z0-9+.-]*:\/\/[^/:@\s]+:[^/@\s]+@/.test(line) && !placeholder)
        types.push('URL_CREDENTIALS');

    const secretKey = /(^|[^a-z0-9_])["']?(password|passwd|secret|token|api_key|apikey|access_key)["']?\s*[:=]\s*("[^"]+"|'[^']+'|[a-z0-9][a-z0-9._-]*(?=[\s#;,}]|$))/i;
    if (!/^\s*#/.test(line) && secretKey.test(line) && !placeholder)
        types.push('SECRET_ASSIGNMENT');

    if (/(^|[^0-9])(?:\+?86)?1[3-9][0-9]{9}([^0-9]|$)/.test(line))
        types.push('PHONE_NUMBER');
    if (/(^|[^0-9])[0-9]{15}([^0-9]|$)/.test(line))
        types.push('15_DIGIT_IDENTIFIER');
    if (/(^|[^0-9])[0-9]{19,20}([^0-9]|$)/.test(line))
        types.push('ICCID');

    const sensitiveKey = /(^|[^a-z0-9])["']?(imei|imsi|iccid|msisdn|phone_number|device_id)["']?\s*[:=]\s*("[^"]+"|'[^']+'|[a-z0-9][a-z0-9._-]*(?=[\s#;,}]|$))/i;
    if (!/^\s*#/.test(line) && sensitiveKey.test(line) && !placeholder)
        types.push('SENSITIVE_FIELD');

    return types;
}

function main() {
    const allowlist = loadAllowlist();
    const findings = [];

    for (const pathBuffer of trackedPaths()) {
        let content;
        try {
            content = fs.readFileSync(pathBuffer);
        } catch {
            throw new Error(`could not read tracked file ${anonymousId(pathBuffer)}`);
        }
        if (content.includes(0))
            continue;

        const path = pathBuffer.toString('utf8');
        const fileId = anonymousId(pathBuffer);
        const lines = content.toString('utf8').split(/\r?\n/);
        lines.forEach((line, index) => {
            const lineNumber = index + 1;
            for (const type of findingTypes(line)) {
                if (!allowlist.has(`${path}:${lineNumber}:${type}`))
                    findings.push(`file:${fileId}:${lineNumber} ${type}`);
            }
        });
    }

    if (findings.length > 0) {
        process.stdout.write([...new Set(findings)].sort().join('\n') + '\n');
        return 1;
    }
    return 0;
}

try {
    process.exitCode = main();
} catch (error) {
    process.stderr.write(`sensitive scan failed: ${error.message}\n`);
    process.exitCode = 2;
}
