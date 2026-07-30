# GitHub Packages and Installation Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build architecture-independent APK and IPK packages in GitHub Actions, publish `v0.1.0-rc1`, and install the exact GitHub-built artifacts in disposable OpenWrt 25.12.5 and 24.10.7 QEMU guests.

**Architecture:** Package metadata identifies the shell-only backend and LuCI application as architecture-independent. A tested POSIX shell build script selects one of two pinned official OpenWrt SDKs, verifies its checksum, builds both packages, and emits a manifest. A least-privilege GitHub workflow runs the existing checks, builds both release lines, assembles raw packages plus checksums, and publishes only on a version tag; a local QEMU procedure then verifies the documented package-manager installation and ubus integration.

**Tech Stack:** POSIX shell, OpenWrt SDK, GitHub Actions, GitHub CLI, APK, opkg, QEMU x86_64, existing dependency-light shell test harness.

---

### Task 1: Make package metadata releaseable and architecture-independent

**Files:**
- Modify: `tests/test_structure.sh`
- Modify: `package/zte-usb-wifi-manager/Makefile`
- Modify: `luci-app-zte-usb-wifi-manager/Makefile`

- [ ] **Step 1: Write failing metadata assertions**

Add these assertions beside the existing backend and LuCI Makefile assertions:

```sh
assert_file_contains "$backend/Makefile" '^PKG_VERSION:=0\.1\.0_rc1$'
assert_file_contains "$backend/Makefile" '^PKG_RELEASE:=1$'
assert_file_contains "$backend/Makefile" '^PKGARCH:=all$'
assert_file_contains "$luci/Makefile" '^PKG_VERSION:=0\.1\.0_rc1$'
assert_file_contains "$luci/Makefile" '^PKG_RELEASE:=1$'
assert_file_contains "$luci/Makefile" '^LUCI_PKGARCH:=all$'
```

- [ ] **Step 2: Verify the assertions fail**

Run:

```sh
./tests/test_structure.sh
```

Expected: failures for the missing version and backend architecture metadata.

- [ ] **Step 3: Add the package metadata**

The backend metadata must be:

```make
PKG_NAME:=zte-usb-wifi-manager
PKG_VERSION:=0.1.0_rc1
PKG_RELEASE:=1
PKGARCH:=all
```

The LuCI metadata must include:

```make
PKG_VERSION:=0.1.0_rc1
PKG_RELEASE:=1
LUCI_PKGARCH:=all
```

- [ ] **Step 4: Verify metadata tests pass**

Run:

```sh
./tests/test_structure.sh
make check
```

Expected: both commands exit zero.

- [ ] **Step 5: Commit**

```sh
git add tests/test_structure.sh package/zte-usb-wifi-manager/Makefile \
    luci-app-zte-usb-wifi-manager/Makefile
git commit -m "build: add release package metadata"
```

### Task 2: Add a pinned, testable OpenWrt release matrix

**Files:**
- Create: `scripts/openwrt-release-matrix.sh`
- Create: `tests/test_packaging.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write failing matrix tests**

Create `tests/test_packaging.sh` using `tests/testlib.sh`. It must assert:

```sh
expected_2512='25.12.5|apk|openwrt-sdk-25.12.5-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst|0c8df0151a1e88feb7c03d694d61f6a18d51872815b7c811d76e2b77504d5e9c|openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz|23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461|e11279b01e7fea7f7d399e25e969d9382be6891071cbc1225804195224b27b52'
expected_2410='24.10.7|ipk|openwrt-sdk-24.10.7-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst|996d71f9eab7df2e8acb0bb2c9726426f05c10d419e5f9600d59b14d871f2acb|openwrt-24.10.7-x86-64-generic-ext4-combined.img.gz|3caea69f186b2bce80938d265e5e2a3dfd0f8713aed101df35d60b88d7270d1f|fa4ae9a869c3bc76c5d89dc6f6532194a4d1df8e7a99d6f441aeff085124c148'

assert_eq "$expected_2512" "$(./scripts/openwrt-release-matrix.sh 25.12.5)"
assert_eq "$expected_2410" "$(./scripts/openwrt-release-matrix.sh 24.10.7)"
assert_failure ./scripts/openwrt-release-matrix.sh 23.05.6
assert_failure ./scripts/openwrt-release-matrix.sh '25.12.5;id'
```

Add `tests/test_packaging.sh` to the `make test` loop and include `scripts` in
the shell syntax and lint file searches.

- [ ] **Step 2: Verify the matrix test fails**

Run:

```sh
chmod +x tests/test_packaging.sh
./tests/test_packaging.sh
```

Expected: failure because `scripts/openwrt-release-matrix.sh` does not exist.

- [ ] **Step 3: Implement the allowlisted matrix**

Create an executable POSIX shell script with:

```sh
#!/bin/sh
set -eu

case ${1-} in
    25.12.5)
        printf '%s\n' '25.12.5|apk|openwrt-sdk-25.12.5-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst|0c8df0151a1e88feb7c03d694d61f6a18d51872815b7c811d76e2b77504d5e9c|openwrt-25.12.5-x86-64-generic-ext4-combined.img.gz|23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461|e11279b01e7fea7f7d399e25e969d9382be6891071cbc1225804195224b27b52'
        ;;
    24.10.7)
        printf '%s\n' '24.10.7|ipk|openwrt-sdk-24.10.7-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst|996d71f9eab7df2e8acb0bb2c9726426f05c10d419e5f9600d59b14d871f2acb|openwrt-24.10.7-x86-64-generic-ext4-combined.img.gz|3caea69f186b2bce80938d265e5e2a3dfd0f8713aed101df35d60b88d7270d1f|fa4ae9a869c3bc76c5d89dc6f6532194a4d1df8e7a99d6f441aeff085124c148'
        ;;
    *)
        printf 'unsupported OpenWrt release: %s\n' "${1-}" >&2
        exit 64
        ;;
esac
```

- [ ] **Step 4: Verify matrix behavior**

Run:

```sh
make test
make lint
```

Expected: all suites and ShellCheck pass.

- [ ] **Step 5: Commit**

```sh
git add Makefile scripts/openwrt-release-matrix.sh tests/test_packaging.sh
git commit -m "build: define supported OpenWrt releases"
```

### Task 3: Implement and test the SDK package builder

**Files:**
- Create: `scripts/build-openwrt-packages.sh`
- Modify: `tests/test_packaging.sh`

- [ ] **Step 1: Add failing build-script contract assertions**

Extend `tests/test_packaging.sh` to assert that the builder:

```sh
assert_file_contains scripts/build-openwrt-packages.sh 'openwrt-release-matrix\.sh'
assert_file_contains scripts/build-openwrt-packages.sh 'downloads\.openwrt\.org/releases/'
assert_file_contains scripts/build-openwrt-packages.sh 'sha256sum.*-c'
assert_file_contains scripts/build-openwrt-packages.sh 'package/zte-usb-wifi-manager/compile'
assert_file_contains scripts/build-openwrt-packages.sh 'package/luci-app-zte-usb-wifi-manager/compile'
assert_file_contains scripts/build-openwrt-packages.sh 'build-manifest\.json'
assert_failure ./scripts/build-openwrt-packages.sh 23.05.6 /tmp/zte-invalid-output
```

- [ ] **Step 2: Verify the contract test fails**

Run:

```sh
./tests/test_packaging.sh
```

Expected: failures because the builder is absent.

- [ ] **Step 3: Implement the builder**

The executable POSIX script must:

- require exactly `RELEASE OUTPUT_DIRECTORY`;
- resolve release data only through `openwrt-release-matrix.sh`;
- download from
  `https://downloads.openwrt.org/releases/$release/targets/x86/64/$sdk_file`;
- verify the pinned SHA-256 before extraction;
- extract into `mktemp -d` and clean it on exit;
- download and verify official `feeds.buildinfo`, copy its immutable commit
  pins to `feeds.conf`, then run the feed update and install commands;
- symlink both repository package directories;
- append both `CONFIG_PACKAGE_...=m` selections and run `make defconfig`;
- compile both package targets;
- locate exactly one backend and one LuCI output using format-aware names:
  `name-version.apk` for APK and `name_version_all.ipk` for IPK;
- reject symlinks and copy only regular files to a newly created output
  directory;
- generate valid `build-manifest.json` with release, format, SDK filename,
  SDK checksum, Git commit, and the two output filenames.

Use `node -e` with positional arguments to generate JSON so shell values are
escaped correctly. Do not interpolate untrusted text into JSON source.

- [ ] **Step 4: Verify local contracts**

Run:

```sh
sh -n scripts/build-openwrt-packages.sh
./tests/test_packaging.sh
make lint
```

Expected: all commands exit zero.

- [ ] **Step 5: Commit**

```sh
git add scripts/build-openwrt-packages.sh tests/test_packaging.sh
git commit -m "build: add verified OpenWrt SDK builder"
```

### Task 4: Add the GitHub packaging and prerelease workflow

**Files:**
- Create: `.github/workflows/packages.yml`
- Modify: `tests/test_packaging.sh`

- [ ] **Step 1: Add failing workflow safety assertions**

Extend `tests/test_packaging.sh` to require:

```sh
workflow=.github/workflows/packages.yml
assert_file_contains "$workflow" 'workflow_dispatch:'
assert_file_contains "$workflow" 'tags:'
assert_file_contains "$workflow" '25\.12\.5'
assert_file_contains "$workflow" '24\.10\.7'
assert_file_contains "$workflow" 'contents: read'
assert_file_contains "$workflow" 'contents: write'
assert_file_contains "$workflow" 'scripts/build-openwrt-packages\.sh'
assert_file_contains "$workflow" 'SHA256SUMS'
assert_file_contains "$workflow" 'gh release create'
assert_file_contains "$workflow" '\-\-prerelease'
```

Also reject `pull_request`, `--force-depends`, and `--force-architecture` in
the packaging workflow.

- [ ] **Step 2: Verify workflow tests fail**

Run:

```sh
./tests/test_packaging.sh
```

Expected: workflow file assertions fail.

- [ ] **Step 3: Implement the workflow**

Create a workflow with:

- global `permissions: contents: read`;
- triggers `workflow_dispatch` and the exact package-matching tag
  `v0.1.0-rc1`;
- a `check` job running `make check`;
- a two-entry build matrix for `25.12.5` and `24.10.7`;
- Ubuntu package installation for the official OpenWrt SDK build
  prerequisites;
- checkout, upload-artifact, and download-artifact actions pinned to reviewed
  full commit SHAs;
- one artifact per OpenWrt release;
- a tested `scripts/assemble-openwrt-packages.js` assembly job that rejects
  unexpected files and validates release, format, architecture, source commit,
  SDK/feed provenance, declared filenames, and package hashes before producing
  the combined manifest and `SHA256SUMS`;
- a release step guarded by
  `startsWith(github.ref, 'refs/tags/v')`, with job-level
  `permissions: contents: write`, running:

```sh
gh release create "$GITHUB_REF_NAME" dist/* \
    --verify-tag \
    --prerelease \
    --title "$GITHUB_REF_NAME" \
    --notes-file release-notes.md
```

- [ ] **Step 4: Verify workflow policy**

Run:

```sh
./tests/test_packaging.sh
make check
git diff --check
```

Expected: all commands exit zero.

- [ ] **Step 5: Commit**

```sh
git add .github/workflows/packages.yml tests/test_packaging.sh
git commit -m "ci: build OpenWrt release packages"
```

### Task 5: Document compatibility and maintainer validation

**Files:**
- Modify: `README.md`
- Create: `docs/validation/github-packages-and-qemu.md`
- Modify: `tests/test_structure.sh`

- [ ] **Step 1: Add failing documentation assertions**

Require the README and validation guide to mention both exact OpenWrt versions,
their formats, the prerelease status, GitHub Actions artifact provenance, and
the ban on installing packages for an unlisted release.

- [ ] **Step 2: Verify documentation tests fail**

Run:

```sh
./tests/test_structure.sh
```

Expected: failures for the missing compatibility table and validation guide.

- [ ] **Step 3: Update documentation**

Add a compatibility table to the README:

| OpenWrt | Package | Status |
|---|---|---|
| 25.12.5 | `.apk` | Supported and QEMU installation-tested |
| 24.10.7 | `.ipk` | Supported and QEMU installation-tested |

Before real validation completes, phrase the status as “scheduled for QEMU
installation validation”; change it to “installation-tested” only after the
evidence exists.

Create the maintainer guide with the exact `gh workflow run`, `gh run watch`,
`gh run download`, SHA-256 verification, QEMU boot, package installation,
ubus checks, uninstall checks, and release download commands used in Tasks 7
and 8.

- [ ] **Step 4: Verify documentation**

Run:

```sh
./tests/test_structure.sh
node tests/scan_sensitive_data.js
```

Expected: all assertions pass and no sensitive data is reported.

- [ ] **Step 5: Commit**

```sh
git add README.md docs/validation/github-packages-and-qemu.md \
    tests/test_structure.sh
git commit -m "docs: describe package compatibility validation"
```

### Task 6: Verify, integrate, and push the implementation

**Files:**
- Read all changed files

- [ ] **Step 1: Run full local verification**

```sh
make check
git diff origin/main...HEAD --check
node tests/scan_sensitive_data.js
```

Expected: all commands exit zero.

- [ ] **Step 2: Review release security boundaries**

Confirm from the staged workflow that pull requests cannot trigger packaging,
write permission exists only on the tag release job, SDK URLs are allowlisted,
and checksums are pinned.

- [ ] **Step 3: Integrate into main**

Fast-forward or merge the implementation branch into `main` without including
the unrelated `0x0ss-2.png` and `20260720_102413.mp4`, then push `main`.

- [ ] **Step 4: Confirm remote state**

```sh
git fetch origin main
git rev-parse HEAD
git rev-parse origin/main
```

Expected: both hashes are identical.

### Task 7: Run GitHub packaging and validate Actions artifacts

**Files:**
- Create during evidence capture:
  `docs/validation/2026-07-30-github-actions-build.md`

- [ ] **Step 1: Trigger the workflow on main**

```sh
gh workflow run packages.yml --ref main
run_id=$(gh run list --workflow packages.yml --limit 1 \
    --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --exit-status
```

Expected: check, both SDK builds, and assembly succeed; release is skipped
because the run is not a tag.

- [ ] **Step 2: Download and verify GitHub artifacts**

```sh
artifact_dir=$(mktemp -d)
gh run download "$run_id" --name openwrt-packages --dir "$artifact_dir"
(cd "$artifact_dir" && sha256sum -c SHA256SUMS)
```

Expected: four package files verify successfully.

- [ ] **Step 3: Record sanitized build evidence**

Record the run URL, commit SHA, package filenames, package sizes, and SHA-256
values. Do not record authentication data or local network identifiers.

### Task 8: Perform real QEMU installations and publish the prerelease

**Files:**
- Create: `docs/validation/2026-07-30-qemu-installation.md`
- Modify: `README.md`

- [ ] **Step 1: Install local QEMU when absent**

On macOS:

```sh
brew install qemu
```

Expected: `qemu-system-x86_64` and `qemu-img` are available.

- [ ] **Step 2: Validate the workflow-dispatch artifacts**

For both matrix releases, download and verify the pinned official combined
ext4 image, boot a disposable overlay with QEMU user networking, configure the
guest network through the serial console, and install the matching GitHub
artifact pair using the README commands.

Verify package database entries, installed modes, procd registration,
`ubus list zte_usb_wifi`, capabilities JSON, status JSON, and clean uninstall.
Capture the serial/SSH command transcript with secrets and local addresses
excluded.

- [ ] **Step 3: Commit and push validation evidence**

```sh
git add docs/validation/2026-07-30-github-actions-build.md \
    docs/validation/2026-07-30-qemu-installation.md README.md
git commit -m "test: record OpenWrt package installation"
git push origin main
```

- [ ] **Step 4: Create and push the prerelease tag**

```sh
git tag -a v0.1.0-rc1 -m "ZTE USB WiFi Manager v0.1.0-rc1"
git push origin v0.1.0-rc1
```

Expected: the tag workflow creates a GitHub prerelease with four packages,
`SHA256SUMS`, and `build-manifest.json`.

- [ ] **Step 5: Verify exact release assets**

Download the release assets with:

```sh
release_dir=$(mktemp -d)
gh release download v0.1.0-rc1 --dir "$release_dir"
(cd "$release_dir" && sha256sum -c SHA256SUMS)
```

Install the exact release APK pair in a fresh 25.12.5 QEMU overlay and the
exact release IPK pair in a fresh 24.10.7 overlay. Repeat the package database,
procd, ubus, and uninstall checks.

- [ ] **Step 6: Final verification**

```sh
make check
git fetch origin main --tags
git status --short --branch
gh release view v0.1.0-rc1
```

Expected: all tests pass, `main` matches `origin/main`, the release is marked
prerelease, and only the two pre-existing unrelated media files remain
untracked in the original workspace.
