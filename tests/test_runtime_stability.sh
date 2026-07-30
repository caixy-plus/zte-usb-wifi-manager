#!/bin/sh
set -eu

TEST_NAME=test_runtime_stability
. ./tests/testlib.sh

lib=./package/zte-usb-wifi-manager/files/usr/lib/zte-usb-wifi-manager
. "$lib/validation.sh"
. "$lib/json.sh"
. "$lib/actions.sh"
. "$lib/power-adapter.sh"
. "$lib/recovery-inhibit.sh"
. "$lib/event-log.sh"

work=$(mktemp -d /tmp/zte-test-runtime-stability.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
state=$work/state

index=0
while [ "$index" -lt 600 ]; do
    level=info
    case $((index % 3)) in
        1) level=warn ;;
        2) level=error ;;
    esac
    assert_success zte_event_write \
        "$state" "$level" state state_ok \
        "$((1722345678 + index))" 512
    index=$((index + 1))
done

assert_eq 3 \
    "$(find "$state/logs" -type f -name 'events*.jsonl' |
        wc -l | tr -d ' ')"
for event_file in "$state"/logs/events*.jsonl; do
    assert_eq 600 "$(test_file_mode "$event_file")"
    assert_success test "$(wc -c <"$event_file")" -le 512
done
events=$(zte_event_list "$state" 200)
assert_success node -e '
const payload = JSON.parse(process.argv[1]);
if (payload.events.length < 1 || payload.events.length > 200)
    process.exit(1);
' "$events"

index=0
while [ "$index" -lt 100 ]; do
    epoch=$((1722347000 + index))
    operation_id=op-$epoch-$((3000 + index))
    assert_success zte_action_enqueue \
        "$state" "$operation_id" set_wifi '{"enabled":true}' "$epoch"
    assert_success zte_action_claim "$state" >/dev/null
    assert_success zte_action_finish \
        "$state" "$operation_id" failed unsupported "$epoch"
    index=$((index + 1))
done
assert_success zte_action_prune_results "$state" 50
assert_eq 50 \
    "$(find "$state/actions/results" -type f -name 'op-*.json' |
        wc -l | tr -d ' ')"

power_record=$state/power-decision.json
index=0
while [ "$index" -lt 100 ]; do
    if [ $((index % 2)) -eq 0 ]; then
        assert_success zte_power_apply \
            dry-run OFF battery_high "$power_record" >/dev/null
    else
        assert_success zte_power_apply \
            mock ON battery_low "$power_record" >/dev/null
    fi
    index=$((index + 1))
done
assert_eq 600 "$(test_file_mode "$power_record")"
assert_success node -e \
    'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
    "$power_record"

inhibit=$state/inhibit-recovery
index=0
while [ "$index" -lt 100 ]; do
    now=$((1722348000 + index))
    assert_success zte_recovery_inhibit_write \
        "$inhibit" battery_high "$((now + 600))" "$now"
    assert_success zte_recovery_inhibit_active "$inhibit" "$now"
    assert_success zte_recovery_inhibit_clear "$inhibit"
    index=$((index + 1))
done

if find "$state" -type f \
    \( -name '*.tmp.*' -o -name '.prune.*' \) -print | grep -q .; then
    fail 'accelerated runtime test left temporary files behind'
else
    pass
fi

finish
