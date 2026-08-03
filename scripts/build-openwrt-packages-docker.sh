#!/bin/sh
set -eu

die() {
	printf 'build-openwrt-packages-docker: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || die 'usage: build-openwrt-packages-docker.sh RELEASE OUTPUT_DIRECTORY'
command -v docker >/dev/null 2>&1 || die 'docker is required'

release=$1
output_dir=$2
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
git_common_dir=$(git -C "$repo_root" rev-parse --path-format=absolute \
	--git-common-dir) || die 'source must be a git worktree'
case $output_dir in
	/*) ;;
	*) output_dir=$PWD/$output_dir ;;
esac
output_parent=$(dirname "$output_dir")
output_name=$(basename "$output_dir")
mkdir -p "$output_parent"
download_cache=$output_parent/.openwrt-sdk-cache
mkdir -p "$download_cache"

image=zte-openwrt-sdk-builder:ubuntu-24.04-amd64
docker build --platform linux/amd64 -t "$image" \
	-f "$script_dir/Dockerfile.openwrt-sdk" "$repo_root"

# The source is read-only. The output parent is mounted separately so the
# inner atomic staging/rename contract remains intact.
docker run --rm --platform linux/amd64 \
	-v "$repo_root:$repo_root:ro" \
	-v "$git_common_dir:$git_common_dir:ro" \
	-v "$output_parent:/output" \
	-v "$download_cache:/downloads" \
	-e OPENWRT_DOWNLOAD_CACHE=/downloads \
	-w "$repo_root" "$image" \
	./scripts/build-openwrt-packages.sh "$release" "/output/$output_name"
