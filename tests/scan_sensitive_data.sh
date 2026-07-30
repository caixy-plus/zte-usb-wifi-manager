#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd)
exec node "$script_dir/scan_sensitive_data.js"
