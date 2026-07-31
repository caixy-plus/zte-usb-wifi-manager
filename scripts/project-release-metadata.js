#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

function readMakeValue(file, key) {
	const matches = fs.readFileSync(file, 'utf8')
		.split(/\r?\n/)
		.filter(line => line.startsWith(`${key}:=`))
		.map(line => line.slice(key.length + 2).trim());
	if (matches.length !== 1 || matches[0].length === 0)
		throw new Error(`expected exactly one ${key} in ${file}`);
	return matches[0];
}

function loadReleaseMetadata(root) {
	const backendMakefile = path.join(
		root, 'package/zte-usb-wifi-manager/Makefile');
	const luciMakefile = path.join(
		root, 'luci-app-zte-usb-wifi-manager/Makefile');
	const packageVersion = readMakeValue(backendMakefile, 'PKG_VERSION');
	const luciPackageVersion = readMakeValue(luciMakefile, 'PKG_VERSION');
	const backendRelease = readMakeValue(backendMakefile, 'PKG_RELEASE');
	const luciRelease = readMakeValue(luciMakefile, 'PKG_RELEASE');

	if (!/^\d+\.\d+\.\d+(?:_rc[1-9]\d*)?$/.test(packageVersion) ||
		luciPackageVersion !== packageVersion)
		throw new Error('backend and LuCI package versions must match');
	if (!/^[1-9]\d*$/.test(backendRelease) || !/^[1-9]\d*$/.test(luciRelease))
		throw new Error('package releases must be positive integers');

	const tagVersion = packageVersion.replace(/_/g, '-');
	return {
		packageVersion,
		backendRelease,
		luciRelease,
		backendVersion: `${packageVersion}-r${backendRelease}`,
		luciVersion: `${packageVersion}-r${luciRelease}`,
		tag: `v${tagVersion}-r${backendRelease}`,
		channel: /_rc[A-Za-z0-9.]*$/.test(packageVersion)
			? 'prerelease' : 'stable'
	};
}

if (require.main === module) {
	try {
		if (process.argv.length > 3)
			throw new Error('usage: project-release-metadata.js [REPOSITORY_ROOT]');
		const root = process.argv[2] || path.resolve(__dirname, '..');
		const metadata = loadReleaseMetadata(root);
		process.stdout.write([
			metadata.packageVersion,
			metadata.backendRelease,
			metadata.luciRelease,
			metadata.tag,
			metadata.channel
		].join('|') + '\n');
	} catch (error) {
		process.stderr.write(`project-release-metadata: ${error.message}\n`);
		process.exitCode = 1;
	}
}

module.exports = { loadReleaseMetadata };
