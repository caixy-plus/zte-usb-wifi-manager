# GitHub Packages and Real Installation Validation Design

## Goal

Use GitHub Actions to build installable ZTE USB WiFi Manager packages for the
maintained mainstream OpenWrt release series, publish a traceable prerelease,
and install the exact GitHub-built artifacts in local OpenWrt virtual machines
to verify the documented installation procedure without touching the main
router.

## Supported Releases

The initial compatibility matrix contains the two OpenWrt release series that
are officially maintained on 2026-07-30:

| OpenWrt release | Support status | Package format | Validation environment |
|---|---|---|---|
| 25.12.5 | Stable | APK | OpenWrt 25.12.5 x86_64 QEMU |
| 24.10.7 | Old stable / security maintenance | IPK | OpenWrt 24.10.7 x86_64 QEMU |

OpenWrt 23.05 and older releases are excluded because they are end-of-life.
Snapshots are excluded because their package ABI changes continuously.

Each later project release updates the matrix deliberately. A package is never
advertised for an OpenWrt series unless the corresponding SDK build and QEMU
installation validation pass.

## Architecture

Both project packages contain only POSIX shell, JavaScript, JSON, UCI
configuration, and init scripts. They contain no target-specific executable
code. The backend package will therefore declare `PKGARCH:=all`; the LuCI
package already declares `LUCI_PKGARCH:=all`.

GitHub Actions builds once per supported OpenWrt release rather than once per
hardware target:

```text
repository tag
    |
    +-- tests and lint
    |
    +-- OpenWrt 25.12.5 SDK --> backend APK + LuCI APK
    |
    +-- OpenWrt 24.10.7 SDK --> backend IPK + LuCI IPK
    |
    +-- manifest + SHA256SUMS
    |
    `-- GitHub prerelease
```

The package payload is architecture-independent, but package formats and SDK
metadata remain release-specific. APK and IPK artifacts are not interchangeable
between OpenWrt release series.

## Build Components

### Package metadata

The backend package receives an explicit project version and the `all`
architecture marker. The LuCI package receives the same project version so all
four published artifacts identify the same source release.

The first published version is `0.1.0-rc1`, represented by Git tag
`v0.1.0-rc1`. It is a GitHub prerelease because the project remains a read-only
developer preview and has not completed main-router acceptance.

### Build script

A repository script owns the OpenWrt SDK build procedure. It accepts only a
known release key from the compatibility matrix and performs these operations:

1. Resolve the exact official SDK archive for the release and `x86/64` target.
2. Download the SDK archive and the official checksum list over HTTPS.
3. Verify the SDK archive against the checksum published by OpenWrt.
4. Extract the SDK into a temporary directory.
5. Download the release's official `feeds.buildinfo`, verify its checksum, and
   use its immutable feed commit IDs when installing SDK feeds.
6. Link both project package directories into the SDK.
7. select both packages as modules and run `make defconfig`.
8. Compile the backend and LuCI packages.
9. Copy only the expected project APK or IPK files into a clean output
   directory.
10. Fail if either package is missing, duplicated, has the wrong format, or has
    the wrong architecture metadata (`noarch` for APK, `all` for IPK).

The script uses strict shell error handling and never accepts an arbitrary SDK
URL from an untrusted pull request.

### GitHub Actions

The packaging workflow supports:

- `workflow_dispatch` for build and installation-validation runs without
  publishing a release;
- `push` of tags matching `v*` for immutable release builds.

Pull requests continue to use the existing read-only CI workflow. Packaging
does not run with write permissions on pull requests.

The workflow uses a matrix for the two supported OpenWrt releases. Each matrix
job uploads its raw package files as a GitHub Actions artifact. A final job
downloads both results, rejects unexpected filenames, produces `SHA256SUMS`
and a machine-readable build manifest, and uploads the complete bundle.

For tag builds only, the final job receives `contents: write` permission and
creates a GitHub prerelease containing:

- `zte-usb-wifi-manager-*.apk`
- `luci-app-zte-usb-wifi-manager-*.apk`
- `zte-usb-wifi-manager_*_all.ipk`
- `luci-app-zte-usb-wifi-manager_*_all.ipk`
- `SHA256SUMS`
- `build-manifest.json`

The manifest records the project tag, commit SHA, OpenWrt versions, SDK archive
names, SDK and feeds checksums, package formats, package architectures, and
artifact checksums. The release tag must be exactly `v0.1.0-rc1`, matching the
package version; other tags cannot publish the fixed release payload.

## Real Installation Validation

The validation must use artifacts downloaded from the completed GitHub Actions
run. Rebuilding locally and installing those local files does not satisfy the
requirement.

Two official OpenWrt x86_64 disk images run under QEMU on the local development
machine. QEMU uses user-mode networking and a temporary forwarded SSH port.
Before package downloads, explicit reject routes block RFC 1918, carrier-grade
NAT, and link-local destinations, and IPv6 is disabled. The guest therefore
retains public package-source access but cannot contact the main router or U25S.

For each supported version, the validation procedure:

1. Download and verify the official OpenWrt disk image.
2. Boot a disposable QEMU virtual machine and wait for SSH readiness.
3. Confirm `/etc/openwrt_release` matches the intended release.
4. Run the release-appropriate package index update.
5. Copy the exact GitHub-built backend and LuCI packages into `/tmp`.
6. Install them using the README command:
   - OpenWrt 25.12.5: `apk add --allow-untrusted`
   - OpenWrt 24.10.7: `opkg install`
7. Verify both packages appear in the package database.
8. Verify shipped files, executable modes, configuration files, init script,
   LuCI menu, LuCI ACL, and rpcd executable are present.
9. Create a dummy root-owned `0600` credentials file and retain
   `write_enabled=0`.
10. Enable and start the service, then verify procd registers the service.
11. Restart rpcd and verify `ubus list zte_usb_wifi`,
    `ubus call zte_usb_wifi capabilities`, and
    `ubus call zte_usb_wifi status` return valid JSON. Device status may report
    an expected connection error because no U25S is attached.
12. Stop and disable the service.
13. Uninstall both packages with the release-appropriate package manager and
    verify the package database no longer lists them.
14. Destroy the virtual machine disk overlay.

Installation fails validation if the package manager requires
`--force-depends`, `--force-architecture`, manual file copying into `/`, or any
command not documented in the README.

## Automated and Manual Evidence

Repository tests will statically verify:

- both maintained OpenWrt versions are present in the packaging matrix;
- both APK and IPK outputs are required;
- SDK checksum verification cannot be skipped;
- release permissions are absent from pull-request jobs;
- package metadata declares architecture `all`;
- README commands match the validation script;
- no force-dependency or force-architecture option is introduced.

The first real validation produces a sanitized report under
`docs/validation/`. It records commands, versions, package filenames,
checksums, and pass/fail results. It excludes credentials, cookies, device
identifiers, local network identifiers, and GitHub tokens.

## Failure Handling

- A failed test or SDK build prevents artifact publication.
- A missing or mismatched official checksum stops before SDK extraction.
- An unexpected artifact name or count stops bundle creation.
- One failing OpenWrt matrix entry prevents the release job.
- A QEMU installation failure leaves the GitHub release as a prerelease and is
  reported accurately; it is never relabeled stable.
- Existing releases are immutable. Fixes use a new release candidate tag
  rather than replacing published files.

## Security Boundaries

- GitHub Actions use least-privilege permissions: read-only by default and
  `contents: write` only in the tag release job.
- Third-party GitHub Actions are pinned to reviewed full commit SHAs.
- SDKs and firmware images come only from `downloads.openwrt.org` and are
  verified using the corresponding official checksum files.
- Workflow inputs select predefined matrix entries and cannot inject shell
  commands or arbitrary URLs.
- No router credentials, U25S credentials, cookies, or device identifiers are
  stored in GitHub Secrets, workflow logs, artifacts, or validation reports.
- QEMU tests remain isolated from physical routers and USB devices.

## Documentation

The README installation section will list the supported OpenWrt series and map
each series to its package format. It will link to the GitHub prerelease, retain
the checksum verification step, and explicitly state that other OpenWrt
versions are unsupported until added to the tested compatibility matrix.

The build and validation procedure will be documented for maintainers so a
future release can update OpenWrt versions without silently weakening checksum,
permission, or installation checks.
