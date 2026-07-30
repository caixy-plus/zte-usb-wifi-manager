#!/bin/sh

TEST_NAME=${TEST_NAME:-unknown}
TEST_COUNT=0
TEST_FAILURES=0

pass() {
    TEST_COUNT=$((TEST_COUNT + 1))
}

fail() {
    TEST_COUNT=$((TEST_COUNT + 1))
    TEST_FAILURES=$((TEST_FAILURES + 1))
    printf 'FAIL %s: %s\n' "$TEST_NAME" "$*" >&2
}

assert_eq() {
    expected=$1
    actual=$2
    message=${3:-"expected '$expected', got '$actual'"}
    if [ "$expected" = "$actual" ]; then
        pass
    else
        fail "$message"
    fi
}

assert_success() {
    if "$@"; then
        pass
    else
        fail "expected success: $*"
    fi
}

assert_failure() {
    if "$@"; then
        fail "expected failure: $*"
    else
        pass
    fi
}

assert_file_contains() {
    file=$1
    pattern=$2
    if [ -f "$file" ] && grep -Eq "$pattern" "$file"; then
        pass
    else
        fail "$file does not contain pattern: $pattern"
    fi
}

test_file_mode() {
    if mode=$(stat -c '%a' "$1" 2>/dev/null); then
        printf '%s\n' "$mode"
    else
        stat -f '%Lp' "$1" 2>/dev/null
    fi
}

finish() {
    if [ "$TEST_FAILURES" -ne 0 ]; then
        printf 'FAIL %s (%s/%s failed)\n' "$TEST_NAME" "$TEST_FAILURES" "$TEST_COUNT" >&2
        exit 1
    fi
    printf 'PASS %s (%s assertions)\n' "$TEST_NAME" "$TEST_COUNT"
}
