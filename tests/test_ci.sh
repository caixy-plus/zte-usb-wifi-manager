#!/bin/sh
set -eu

TEST_NAME=test_ci
. ./tests/testlib.sh

work=/tmp/zte-test-ci.$$
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bin"

cat >"$work/bin/shellcheck" <<'EOF'
#!/bin/sh
count_file=${FAKE_SHELLCHECK_COUNT:?}
count=0
if [ -f "$count_file" ]; then
    count=$(cat "$count_file")
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
if [ "${FAKE_SHELLCHECK_FAIL_FIRST:-0}" = 1 ] && [ "$count" -eq 1 ]; then
    exit 1
fi
exit 0
EOF
chmod +x "$work/bin/shellcheck"

PATH="$work/bin:$PATH"
export PATH

FAKE_SHELLCHECK_COUNT=$work/failing-count
FAKE_SHELLCHECK_FAIL_FIRST=1
export FAKE_SHELLCHECK_COUNT FAKE_SHELLCHECK_FAIL_FIRST
assert_failure make lint

FAKE_SHELLCHECK_COUNT=$work/success-count
FAKE_SHELLCHECK_FAIL_FIRST=0
export FAKE_SHELLCHECK_COUNT FAKE_SHELLCHECK_FAIL_FIRST
assert_success make lint

finish
