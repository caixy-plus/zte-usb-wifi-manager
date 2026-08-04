#!/bin/sh
set -eu

[ "${1-}" = reload ] || exit 1
count=$(wc -l <"${ZTE_TEST_SERVICE_LOG:?}" | tr -d ' ')
count=$((count + 1))
printf '%s\n' reload >>"$ZTE_TEST_SERVICE_LOG"
fail_points=$(cat "${ZTE_TEST_SERVICE_FAIL_POINTS:?}")
case ,$fail_points, in
	*,$count,*) exit 1 ;;
esac

write_test_ack() {
	loaded_enabled=$(awk -F= \
		'$1 == "zte-usb-wifi-manager.charging.enabled" { print $2 }' \
		"${ZTE_TEST_UCI_COMMITTED:?}")
	loaded_low=$(awk -F= \
		'$1 == "zte-usb-wifi-manager.charging.low_percent" { print $2 }' \
		"$ZTE_TEST_UCI_COMMITTED")
	loaded_high=$(awk -F= \
		'$1 == "zte-usb-wifi-manager.charging.high_percent" { print $2 }' \
		"$ZTE_TEST_UCI_COMMITTED")
	: "${loaded_enabled:=0}" "${loaded_low:=30}" "${loaded_high:=80}"
	# shellcheck disable=SC1090
	. "${ZTE_TEST_VALIDATION_LIB:?}"
	# shellcheck disable=SC1090
	. "${ZTE_TEST_TX_LIB:?}"
	ack_result=$(zte_charging_transaction_daemon_finalize \
		"${ZTE_TEST_TX_STATE:?}" "$loaded_enabled" "$loaded_low" \
		"$loaded_high")
	if [ "${ZTE_TEST_SERVICE_POST_ACK_DRIFT:-0}" = 1 ]; then
		drift_tmp=$ZTE_TEST_UCI_COMMITTED.drift.$$
		awk '
			$1 != "zte-usb-wifi-manager.charging.enabled=1" { print }
		' "$ZTE_TEST_UCI_COMMITTED" >"$drift_tmp"
		printf '%s\n' 'zte-usb-wifi-manager.charging.enabled=0' \
			>>"$drift_tmp"
		mv "$drift_tmp" "$ZTE_TEST_UCI_COMMITTED"
	fi
	if [ -n "${ZTE_TEST_SERVICE_ACK_LOG:-}" ]; then
		ack_line=$(cat "${ZTE_TEST_TX_STATE:?}/charging-transaction.ack" \
			2>/dev/null || :)
		printf '%s|%s|%s|%s|%s\n' "$ack_result" "$loaded_enabled" \
			"$loaded_low" "$loaded_high" "$ack_line" \
			>>"$ZTE_TEST_SERVICE_ACK_LOG"
	fi
}

if [ "${ZTE_TEST_SERVICE_AUTO_ACK:-1}" = 1 ]; then
	if [ -n "${ZTE_TEST_SERVICE_ACK_DELAY:-}" ]; then
		(
			sleep "$ZTE_TEST_SERVICE_ACK_DELAY"
			write_test_ack
		) >/dev/null 2>&1 &
	else
		write_test_ack
	fi
fi
