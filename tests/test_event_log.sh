#!/bin/sh
set -eu

TEST_NAME=test_event_log
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
event_log=$lib/event-log.sh
if [ ! -f "$event_log" ]; then
    fail 'event log library must exist'
    finish
fi
# shellcheck source=../package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager/event-log.sh
. "$event_log"

work=$(mktemp -d /tmp/zte-test-event-log.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
state=$work/state

for level in info warn error; do
    assert_success zte_event_level_valid "$level"
done
assert_failure zte_event_level_valid debug
for type in service state action power error; do
    assert_success zte_event_type_valid "$type"
done
assert_failure zte_event_type_valid polling
for code in service_started state_ok device_read_failed action_timed_out; do
    assert_success zte_event_code_valid "$code"
done
assert_failure zte_event_code_valid ''
assert_failure zte_event_code_valid 'contains space'
assert_failure zte_event_code_valid '../error'
assert_failure zte_event_code_valid \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

assert_success zte_event_init "$state"
assert_eq 700 "$(test_file_mode "$state/logs")"
assert_success zte_event_write \
    "$state" info service service_started 1722345678 512
event_record='{"time":1722345678,"level":"info","type":"service","code":"service_started"}'
assert_eq "$event_record" "$(cat "$state/logs/events.jsonl")"
assert_eq 600 "$(test_file_mode "$state/logs/events.jsonl")"
assert_eq '{"events":['"$event_record"']}' "$(zte_event_list "$state" 20)"

assert_success zte_event_write \
    "$state" warn state device_read_failed 1722345679 100
assert_success test -f "$state/logs/events.1.jsonl"
assert_success zte_event_write \
    "$state" error error action_timed_out 1722345680 100
assert_success test -f "$state/logs/events.2.jsonl"
events=$(zte_event_list "$state" 2)
assert_success node -e '
const events = JSON.parse(process.argv[1]).events;
if (events.length !== 2) process.exit(1);
if (events[1].code !== "action_timed_out") process.exit(1);
' "$events"

assert_failure zte_event_write \
    "$state" debug service service_started 1722345681 512
assert_failure zte_event_write \
    "$state" info service 'phone=123456' 1722345681 512
assert_failure zte_event_list "$state" 0
assert_failure zte_event_list "$state" 201
assert_eq '{"events":[]}' "$(zte_event_list "$work/missing" 20)"

finish
