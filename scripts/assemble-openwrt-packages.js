#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const expectedBuilds = {
    '25.12.5': {
        directory: 'packages-25.12.5',
        format: 'apk',
        architecture: 'noarch',
        sdkFilename:
            'openwrt-sdk-25.12.5-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst',
        sdkSha256:
            '0c8df0151a1e88feb7c03d694d61f6a18d51872815b7c811d76e2b77504d5e9c',
        feedsSha256:
            'e11279b01e7fea7f7d399e25e969d9382be6891071cbc1225804195224b27b52',
        backend: /^zte-usb-wifi-manager-0\.1\.0_rc1-r14\.apk$/,
        luci: /^luci-app-zte-usb-wifi-manager-0\.1\.0_rc1-r3\.apk$/
    },
    '24.10.7': {
        directory: 'packages-24.10.7',
        format: 'ipk',
        architecture: 'all',
        sdkFilename:
            'openwrt-sdk-24.10.7-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst',
        sdkSha256:
            '996d71f9eab7df2e8acb0bb2c9726426f05c10d419e5f9600d59b14d871f2acb',
        feedsSha256:
            'fa4ae9a869c3bc76c5d89dc6f6532194a4d1df8e7a99d6f441aeff085124c148',
        backend: /^zte-usb-wifi-manager_0\.1\.0_rc1-r14_all\.ipk$/,
        luci: /^luci-app-zte-usb-wifi-manager_0\.1\.0_rc1-r3_all\.ipk$/
    }
};

function die(message) {
    throw new Error(message);
}

function sha256(file) {
    return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function assertPlainFile(file) {
    const stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.isSymbolicLink())
        die(`expected a regular non-symlink file: ${file}`);
}

function readBuild(inputDirectory, sourceCommit, release, expected) {
    const directory = path.join(inputDirectory, expected.directory);
    const directoryStat = fs.lstatSync(directory);
    if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink())
        die(`invalid artifact directory: ${expected.directory}`);

    const entries = fs.readdirSync(directory).sort();
    const manifestName = 'build-manifest.json';
    const packageNames = entries.filter(name => name !== manifestName);
    if (entries.length !== 3 || packageNames.length !== 2)
        die(`unexpected files in ${expected.directory}: ${entries.join(', ')}`);
    if (!packageNames.some(name => expected.backend.test(name)) ||
        !packageNames.some(name => expected.luci.test(name)))
        die(`unexpected package names in ${expected.directory}`);

    for (const name of entries)
        assertPlainFile(path.join(directory, name));

    const manifest = JSON.parse(
        fs.readFileSync(path.join(directory, manifestName), 'utf8')
    );
    if (manifest.openwrt_release !== release ||
        manifest.package_format !== expected.format ||
        manifest.package_architecture !== expected.architecture ||
        manifest.source_commit !== sourceCommit ||
        manifest.sdk?.filename !== expected.sdkFilename ||
        manifest.sdk?.sha256 !== expected.sdkSha256 ||
        manifest.feeds_sha256 !== expected.feedsSha256)
        die(`manifest provenance mismatch for OpenWrt ${release}`);

    if (!Array.isArray(manifest.packages) || manifest.packages.length !== 2)
        die(`invalid package list for OpenWrt ${release}`);
    const declared = new Map(
        manifest.packages.map(item => [item.filename, item.sha256])
    );
    if (declared.size !== 2)
        die(`duplicate package entries for OpenWrt ${release}`);

    for (const name of packageNames) {
        const digest = sha256(path.join(directory, name));
        if (declared.get(name) !== digest)
            die(`package checksum mismatch: ${name}`);
    }
    if ([...declared.keys()].some(name => !packageNames.includes(name)))
        die(`manifest declares an absent package for OpenWrt ${release}`);

    return { manifest, directory, packageNames };
}

function main() {
    const [inputDirectory, outputDirectory, sourceCommit, projectRef] =
        process.argv.slice(2);
    if (!inputDirectory || !outputDirectory || !sourceCommit || !projectRef ||
        process.argv.length !== 6)
        die('usage: assemble-openwrt-packages.js INPUT OUTPUT COMMIT REF');
    if (!/^[0-9a-f]{40}$/.test(sourceCommit))
        die('source commit must be a full 40-character Git SHA');
    if (!/^[A-Za-z0-9._/-]+$/.test(projectRef))
        die('project ref contains unsupported characters');
    if (projectRef.startsWith('v') && projectRef !== 'v0.1.0-rc1-r14')
        die(`release tag does not match package version: ${projectRef}`);

    const rootEntries = fs.readdirSync(inputDirectory).sort();
    const expectedDirectories = Object.values(expectedBuilds)
        .map(item => item.directory).sort();
    if (JSON.stringify(rootEntries) !== JSON.stringify(expectedDirectories))
        die(`unexpected artifact directories: ${rootEntries.join(', ')}`);

    const builds = Object.entries(expectedBuilds).map(([release, expected]) =>
        readBuild(inputDirectory, sourceCommit, release, expected)
    );

    fs.mkdirSync(outputDirectory);
    for (const build of builds) {
        for (const name of build.packageNames)
            fs.copyFileSync(
                path.join(build.directory, name),
                path.join(outputDirectory, name),
                fs.constants.COPYFILE_EXCL
            );
    }

    const combinedManifest = {
        project_ref: projectRef,
        project_tag: projectRef.startsWith('v') ? projectRef : null,
        source_commit: sourceCommit,
        builds: builds.map(build => build.manifest)
    };
    const manifestPath = path.join(outputDirectory, 'build-manifest.json');
    fs.writeFileSync(
        manifestPath,
        `${JSON.stringify(combinedManifest, null, 2)}\n`,
        { flag: 'wx' }
    );

    const checksummedFiles = fs.readdirSync(outputDirectory).sort();
    const checksumLines = checksummedFiles.map(name =>
        `${sha256(path.join(outputDirectory, name))}  ${name}`
    );
    fs.writeFileSync(
        path.join(outputDirectory, 'SHA256SUMS'),
        `${checksumLines.join('\n')}\n`,
        { flag: 'wx' }
    );
}

try {
    main();
} catch (error) {
    process.stderr.write(`assemble-openwrt-packages: ${error.message}\n`);
    process.exit(1);
}
