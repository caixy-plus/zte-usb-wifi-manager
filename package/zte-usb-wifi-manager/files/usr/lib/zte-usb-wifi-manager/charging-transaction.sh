#!/bin/sh

# Crash-safe UCI transaction shared by rpcd and daemon startup. Callers source
# validation.sh first. rpcd alone owns the transaction flock; daemon startup
# only validates the durable marker and publishes a runtime ACK.

ZTE_CHARGING_TX_PACKAGE=zte-usb-wifi-manager
ZTE_CHARGING_TX_SECTION=$ZTE_CHARGING_TX_PACKAGE.charging
ZTE_CHARGING_TX_MARKER=$ZTE_CHARGING_TX_PACKAGE.charging_tx

zte_charging_tx_uci() {
	"${ZTE_CHARGING_UCI_BIN:-uci}" -q -P "$zte_charging_tx_savedir" "$@"
}

zte_charging_tx_unquote() {
	_zte_charging_tx_unquoted=$1
	case $_zte_charging_tx_unquoted in
		\'*)
			case $_zte_charging_tx_unquoted in *\') ;; *) return 1 ;; esac
			_zte_charging_tx_unquoted=${_zte_charging_tx_unquoted#\'}
			_zte_charging_tx_unquoted=${_zte_charging_tx_unquoted%\'}
			;;
	esac
	printf '%s\n' "$_zte_charging_tx_unquoted"
}

zte_charging_tx_field() {
	_zte_charging_tx_field_key=$1
	_zte_charging_tx_field_value=$(printf '%s\n' "$zte_charging_tx_config" |
		awk -v prefix="$_zte_charging_tx_field_key=" '
			index($0, prefix) == 1 {
				count++
				value = substr($0, length(prefix) + 1)
			}
			END {
				if (count == 1) print value
				else if (count == 0) exit 1
				else exit 2
			}
		') || return $?
	zte_charging_tx_unquote "$_zte_charging_tx_field_value" || return 2
}

zte_charging_tx_load_config() {
	zte_charging_tx_config=$(zte_charging_tx_uci show \
		"$ZTE_CHARGING_TX_PACKAGE" 2>/dev/null) || return 1
	[ -n "$zte_charging_tx_config" ]
}

zte_charging_tx_snapshot_one() {
	_zte_charging_tx_snapshot_name=$1
	_zte_charging_tx_snapshot_option=$2
	if _zte_charging_tx_snapshot_value=$(zte_charging_tx_field \
		"$ZTE_CHARGING_TX_SECTION.$_zte_charging_tx_snapshot_option"); then
		_zte_charging_tx_snapshot_present=1
	else
		_zte_charging_tx_snapshot_status=$?
		[ "$_zte_charging_tx_snapshot_status" = 1 ] || return 1
		_zte_charging_tx_snapshot_present=0
		_zte_charging_tx_snapshot_value=''
	fi
	case $_zte_charging_tx_snapshot_name in
		enabled)
			zte_charging_tx_old_enabled_present=$_zte_charging_tx_snapshot_present
			zte_charging_tx_old_enabled_value=$_zte_charging_tx_snapshot_value
			;;
		low)
			zte_charging_tx_old_low_present=$_zte_charging_tx_snapshot_present
			zte_charging_tx_old_low_value=$_zte_charging_tx_snapshot_value
			;;
		high)
			zte_charging_tx_old_high_present=$_zte_charging_tx_snapshot_present
			zte_charging_tx_old_high_value=$_zte_charging_tx_snapshot_value
			;;
	esac
}

zte_charging_tx_current_one() {
	_zte_charging_tx_current_name=$1
	_zte_charging_tx_current_option=$2
	if _zte_charging_tx_current_value=$(zte_charging_tx_field \
		"$ZTE_CHARGING_TX_SECTION.$_zte_charging_tx_current_option"); then
		_zte_charging_tx_current_present=1
	else
		_zte_charging_tx_current_status=$?
		[ "$_zte_charging_tx_current_status" = 1 ] || return 1
		_zte_charging_tx_current_present=0
		_zte_charging_tx_current_value=''
	fi
	case $_zte_charging_tx_current_name in
		enabled) zte_charging_tx_current_enabled_present=$_zte_charging_tx_current_present; zte_charging_tx_current_enabled_value=$_zte_charging_tx_current_value ;;
		low) zte_charging_tx_current_low_present=$_zte_charging_tx_current_present; zte_charging_tx_current_low_value=$_zte_charging_tx_current_value ;;
		high) zte_charging_tx_current_high_present=$_zte_charging_tx_current_present; zte_charging_tx_current_high_value=$_zte_charging_tx_current_value ;;
	esac
}

zte_charging_tx_parse_current() {
	zte_charging_tx_field "$ZTE_CHARGING_TX_SECTION" >/dev/null || return 1
	zte_charging_tx_current_one enabled enabled || return 1
	zte_charging_tx_current_one low low_percent || return 1
	zte_charging_tx_current_one high high_percent
}

zte_charging_tx_validate_old() {
	case $zte_charging_tx_old_enabled_present in
		0) zte_charging_tx_old_enabled_effective=0 ;;
		1)
			case $zte_charging_tx_old_enabled_value in 0|1) ;; *) return 1 ;; esac
			zte_charging_tx_old_enabled_effective=$zte_charging_tx_old_enabled_value
			;;
		*) return 1 ;;
	esac
	case $zte_charging_tx_old_low_present in
		0) zte_charging_tx_old_low_effective=30 ;;
		1)
			zte_is_uint "$zte_charging_tx_old_low_value" || return 1
			zte_charging_tx_old_low_effective=$zte_charging_tx_old_low_value
			;;
		*) return 1 ;;
	esac
	case $zte_charging_tx_old_high_present in
		0) zte_charging_tx_old_high_effective=80 ;;
		1)
			zte_is_uint "$zte_charging_tx_old_high_value" || return 1
			zte_charging_tx_old_high_effective=$zte_charging_tx_old_high_value
			;;
		*) return 1 ;;
	esac
	zte_validate_thresholds "$zte_charging_tx_old_low_effective" \
		"$zte_charging_tx_old_high_effective"
}

zte_charging_tx_snapshot() {
	zte_charging_tx_load_config || return 1
	zte_charging_tx_field "$ZTE_CHARGING_TX_SECTION" >/dev/null || return 1
	zte_charging_tx_snapshot_one enabled enabled || return 1
	zte_charging_tx_snapshot_one low low_percent || return 1
	zte_charging_tx_snapshot_one high high_percent || return 1
	zte_charging_tx_validate_old
}

zte_charging_tx_txid_valid() {
	_zte_txid_old_ifs=$IFS
	IFS=-
	# Intentional splitting of a strictly validated identifier candidate.
	# shellcheck disable=SC2086
	set -- $1
	IFS=$_zte_txid_old_ifs
	[ "$#" = 4 ] && [ "$1" = tx ] && zte_is_uint "$2" &&
		zte_is_uint "$3" && [ "${#4}" = 32 ] || return 1
	case $4 in *[!0-9a-f]*) return 1 ;; esac
}

# Return 0 for no marker, 1 for a valid marker, and 2 for corrupt state.
zte_charging_tx_marker_read() {
	zte_charging_tx_load_config || return 2
	if _zte_charging_tx_marker_type=$(zte_charging_tx_field \
		"$ZTE_CHARGING_TX_MARKER"); then
		:
	else
		_zte_charging_tx_marker_field_status=$?
		[ "$_zte_charging_tx_marker_field_status" = 1 ] || return 2
		case $zte_charging_tx_config in
			*"$ZTE_CHARGING_TX_MARKER."*) return 2 ;;
		esac
		return 0
	fi
	[ "$_zte_charging_tx_marker_type" = transaction ] || return 2
	zte_charging_tx_txid=$(zte_charging_tx_field \
		"$ZTE_CHARGING_TX_MARKER.txid") || return 2
	zte_charging_tx_txid_valid "$zte_charging_tx_txid" || return 2
	zte_charging_tx_marker_state=$(zte_charging_tx_field \
		"$ZTE_CHARGING_TX_MARKER.state") || return 2
	case $zte_charging_tx_marker_state in reload_pending|restore_pending) ;; *) return 2 ;; esac
	zte_charging_tx_new_enabled=$(zte_charging_tx_field \
		"$ZTE_CHARGING_TX_MARKER.new_enabled") || return 2
	zte_charging_tx_new_low=$(zte_charging_tx_field \
		"$ZTE_CHARGING_TX_MARKER.new_low") || return 2
	zte_charging_tx_new_high=$(zte_charging_tx_field \
		"$ZTE_CHARGING_TX_MARKER.new_high") || return 2
	case $zte_charging_tx_new_enabled in 0|1) ;; *) return 2 ;; esac
	zte_validate_thresholds "$zte_charging_tx_new_low" \
		"$zte_charging_tx_new_high" || return 2
	for _zte_charging_tx_name in enabled low high; do
		_zte_charging_tx_present=$(zte_charging_tx_field \
			"$ZTE_CHARGING_TX_MARKER.old_${_zte_charging_tx_name}_present") || return 2
		case $_zte_charging_tx_present in
			0)
				if zte_charging_tx_field \
					"$ZTE_CHARGING_TX_MARKER.old_${_zte_charging_tx_name}_value" \
					>/dev/null 2>&1; then
					return 2
				else
					_zte_charging_tx_old_value_status=$?
					[ "$_zte_charging_tx_old_value_status" = 1 ] || return 2
				fi
				_zte_charging_tx_value=''
				;;
			1)
				_zte_charging_tx_value=$(zte_charging_tx_field \
					"$ZTE_CHARGING_TX_MARKER.old_${_zte_charging_tx_name}_value") || return 2
				;;
			*) return 2 ;;
		esac
		case $_zte_charging_tx_name in
			enabled) zte_charging_tx_old_enabled_present=$_zte_charging_tx_present; zte_charging_tx_old_enabled_value=$_zte_charging_tx_value ;;
			low) zte_charging_tx_old_low_present=$_zte_charging_tx_present; zte_charging_tx_old_low_value=$_zte_charging_tx_value ;;
			high) zte_charging_tx_old_high_present=$_zte_charging_tx_present; zte_charging_tx_old_high_value=$_zte_charging_tx_value ;;
		esac
	done
	zte_charging_tx_validate_old || return 2
	zte_charging_tx_parse_current || return 2
	return 1
}

zte_charging_tx_current_matches_marker_state() {
	case $zte_charging_tx_marker_state in
		reload_pending)
			[ "$zte_charging_tx_current_enabled_present" = 1 ] &&
				[ "$zte_charging_tx_current_low_present" = 1 ] &&
				[ "$zte_charging_tx_current_high_present" = 1 ] &&
				[ "$zte_charging_tx_current_enabled_value" = "$zte_charging_tx_new_enabled" ] &&
				[ "$zte_charging_tx_current_low_value" = "$zte_charging_tx_new_low" ] &&
				[ "$zte_charging_tx_current_high_value" = "$zte_charging_tx_new_high" ]
			;;
		restore_pending)
			[ "$zte_charging_tx_current_enabled_present" = "$zte_charging_tx_old_enabled_present" ] &&
				[ "$zte_charging_tx_current_low_present" = "$zte_charging_tx_old_low_present" ] &&
				[ "$zte_charging_tx_current_high_present" = "$zte_charging_tx_old_high_present" ] &&
				{ [ "$zte_charging_tx_old_enabled_present" = 0 ] || [ "$zte_charging_tx_current_enabled_value" = "$zte_charging_tx_old_enabled_value" ]; } &&
				{ [ "$zte_charging_tx_old_low_present" = 0 ] || [ "$zte_charging_tx_current_low_value" = "$zte_charging_tx_old_low_value" ]; } &&
				{ [ "$zte_charging_tx_old_high_present" = 0 ] || [ "$zte_charging_tx_current_high_value" = "$zte_charging_tx_old_high_value" ]; }
			;;
		*) return 1 ;;
	esac
}

zte_charging_tx_stage_marker_option() {
	zte_charging_tx_uci set \
		"$ZTE_CHARGING_TX_MARKER.old_$1_present=$2" || return 1
	[ "$2" = 0 ] || zte_charging_tx_uci set \
		"$ZTE_CHARGING_TX_MARKER.old_$1_value=$3"
}

zte_charging_tx_stage_marker_snapshot() {
	zte_charging_tx_uci set "$ZTE_CHARGING_TX_MARKER=transaction" || return 1
	zte_charging_tx_uci set "$ZTE_CHARGING_TX_MARKER.txid=$zte_charging_tx_txid" || return 1
	zte_charging_tx_uci set "$ZTE_CHARGING_TX_MARKER.state=reload_pending" || return 1
	zte_charging_tx_uci set "$ZTE_CHARGING_TX_MARKER.new_enabled=$_zte_charging_tx_enabled" || return 1
	zte_charging_tx_uci set "$ZTE_CHARGING_TX_MARKER.new_low=$_zte_charging_tx_low" || return 1
	zte_charging_tx_uci set "$ZTE_CHARGING_TX_MARKER.new_high=$_zte_charging_tx_high" || return 1
	zte_charging_tx_stage_marker_option enabled "$zte_charging_tx_old_enabled_present" "$zte_charging_tx_old_enabled_value" || return 1
	zte_charging_tx_stage_marker_option low "$zte_charging_tx_old_low_present" "$zte_charging_tx_old_low_value" || return 1
	zte_charging_tx_stage_marker_option high "$zte_charging_tx_old_high_present" "$zte_charging_tx_old_high_value"
}

zte_charging_tx_restore_option() {
	if [ "$2" = 1 ]; then
		zte_charging_tx_uci set "$ZTE_CHARGING_TX_SECTION.$1=$3"
	else
		zte_charging_tx_uci delete "$ZTE_CHARGING_TX_SECTION.$1"
	fi
}

zte_charging_tx_commit_restore() {
	zte_charging_tx_restore_option enabled "$zte_charging_tx_old_enabled_present" "$zte_charging_tx_old_enabled_value" || return 1
	zte_charging_tx_restore_option low_percent "$zte_charging_tx_old_low_present" "$zte_charging_tx_old_low_value" || return 1
	zte_charging_tx_restore_option high_percent "$zte_charging_tx_old_high_present" "$zte_charging_tx_old_high_value" || return 1
	zte_charging_tx_uci set "$ZTE_CHARGING_TX_MARKER.state=restore_pending" || return 1
	zte_charging_tx_uci commit "$ZTE_CHARGING_TX_PACKAGE" || return 1
	zte_charging_tx_marker_state=restore_pending
}

zte_charging_tx_revert() {
	zte_charging_tx_uci revert "$ZTE_CHARGING_TX_PACKAGE" >/dev/null 2>&1
}

zte_charging_tx_file_mode() {
	stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

zte_charging_tx_ack_file_valid() {
	_zte_charging_tx_ack_file=$1
	[ -f "$_zte_charging_tx_ack_file" ] && [ ! -L "$_zte_charging_tx_ack_file" ] || return 1
	[ "$(zte_charging_tx_file_mode "$_zte_charging_tx_ack_file")" = 600 ] || return 1
	[ "$(wc -c <"$_zte_charging_tx_ack_file" | tr -d ' ')" -le 256 ]
}

zte_charging_tx_ack_matches() {
	_zte_charging_tx_ack_file=$1
	zte_charging_tx_ack_file_valid "$_zte_charging_tx_ack_file" || return 1
	[ "$(awk 'END { print NR }' "$_zte_charging_tx_ack_file")" = 1 ] || return 1
	[ "$(wc -l <"$_zte_charging_tx_ack_file" | tr -d ' ')" = 1 ] || return 1
	IFS='|' read -r _zte_ack_txid _zte_ack_state _zte_ack_enabled \
		_zte_ack_low _zte_ack_high _zte_ack_extra <"$_zte_charging_tx_ack_file" || return 1
	[ -z "${_zte_ack_extra:-}" ] &&
		[ "$_zte_ack_txid" = "$2" ] && [ "$_zte_ack_state" = "$3" ] &&
		[ "$_zte_ack_enabled" = "$4" ] && [ "$_zte_ack_low" = "$5" ] &&
		[ "$_zte_ack_high" = "$6" ]
}

zte_charging_tx_verify_marker() {
	_zte_charging_tx_guard_txid=$1
	_zte_charging_tx_guard_state=$2
	if zte_charging_tx_marker_read; then return 1; else _zte_verify_status=$?; fi
	[ "$_zte_verify_status" = 1 ] &&
		[ "$zte_charging_tx_txid" = "$_zte_charging_tx_guard_txid" ] &&
		[ "$zte_charging_tx_marker_state" = "$_zte_charging_tx_guard_state" ] &&
		zte_charging_tx_current_matches_marker_state
}

zte_charging_tx_expected() {
	case $zte_charging_tx_marker_state in
		reload_pending)
			zte_charging_tx_expected_enabled=$zte_charging_tx_new_enabled
			zte_charging_tx_expected_low=$zte_charging_tx_new_low
			zte_charging_tx_expected_high=$zte_charging_tx_new_high ;;
		restore_pending)
			zte_charging_tx_expected_enabled=$zte_charging_tx_old_enabled_effective
			zte_charging_tx_expected_low=$zte_charging_tx_old_low_effective
			zte_charging_tx_expected_high=$zte_charging_tx_old_high_effective ;;
	esac
}

zte_charging_tx_wait_ack() {
	_zte_charging_tx_wait_txid=$zte_charging_tx_txid
	_zte_charging_tx_wait_state=$zte_charging_tx_marker_state
	_zte_charging_tx_attempt=0
	_zte_charging_tx_attempts=${ZTE_CHARGING_TX_ACK_ATTEMPTS:-20}
	while [ "$_zte_charging_tx_attempt" -lt "$_zte_charging_tx_attempts" ]; do
		zte_charging_tx_verify_marker "$_zte_charging_tx_wait_txid" \
			"$_zte_charging_tx_wait_state" || return 2
		zte_charging_tx_ack_matches "$zte_charging_tx_ack_file" \
			"$_zte_charging_tx_wait_txid" "$_zte_charging_tx_wait_state" \
			"$zte_charging_tx_expected_enabled" "$zte_charging_tx_expected_low" \
			"$zte_charging_tx_expected_high" && return 0
		_zte_charging_tx_attempt=$((_zte_charging_tx_attempt + 1))
		[ "$_zte_charging_tx_attempt" -ge "$_zte_charging_tx_attempts" ] ||
			sleep "${ZTE_CHARGING_TX_ACK_SLEEP:-0.1}"
	done
	return 1
}

zte_charging_tx_reload_and_ack() {
	_zte_charging_tx_reload_txid=$zte_charging_tx_txid
	_zte_charging_tx_reload_state=$zte_charging_tx_marker_state
	zte_charging_tx_verify_marker "$_zte_charging_tx_reload_txid" \
		"$_zte_charging_tx_reload_state" || return 2
	[ -x "$1" ] && "$1" reload >/dev/null 2>&1 || return 1
	zte_charging_tx_expected
	zte_charging_tx_wait_ack
}

zte_charging_tx_clear_marker() {
	_zte_charging_tx_clear_txid=$1
	_zte_charging_tx_clear_state=$2
	zte_charging_tx_verify_marker "$_zte_charging_tx_clear_txid" \
		"$_zte_charging_tx_clear_state" || return 2
	if ! zte_charging_tx_uci delete "$ZTE_CHARGING_TX_MARKER" ||
		! zte_charging_tx_uci commit "$ZTE_CHARGING_TX_PACKAGE"; then
		zte_charging_tx_revert || :
		return 1
	fi
	if zte_charging_tx_ack_file_valid "$zte_charging_tx_ack_file"; then
		rm -f "$zte_charging_tx_ack_file" || :
	fi
}

zte_charging_tx_recover_locked() {
	_zte_charging_tx_service=$1
	if zte_charging_tx_marker_read; then
		if [ -e "$zte_charging_tx_ack_file" ] || [ -L "$zte_charging_tx_ack_file" ]; then
			zte_charging_tx_ack_file_valid "$zte_charging_tx_ack_file" || return 1
			rm -f "$zte_charging_tx_ack_file" || return 1
		fi
		return 0
	else
		_zte_marker_status=$?
	fi
	[ "$_zte_marker_status" = 1 ] || return 1
	zte_charging_tx_current_matches_marker_state || return 1
	zte_charging_tx_expected
	_zte_recover_txid=$zte_charging_tx_txid
	_zte_recover_state=$zte_charging_tx_marker_state
	if zte_charging_tx_wait_ack; then
		zte_charging_tx_clear_marker "$_zte_recover_txid" \
			"$_zte_recover_state"
		return
	else
		_zte_ack_status=$?
		[ "$_zte_ack_status" = 1 ] || return 1
	fi
	if [ "$zte_charging_tx_marker_state" = reload_pending ]; then
		_zte_recover_txid=$zte_charging_tx_txid
		_zte_recover_state=$zte_charging_tx_marker_state
		if zte_charging_tx_reload_and_ack "$_zte_charging_tx_service"; then
			zte_charging_tx_clear_marker "$_zte_recover_txid" \
				"$_zte_recover_state"
			return
		else
			_zte_reload_status=$?
			[ "$_zte_reload_status" = 1 ] || return 1
		fi
		zte_charging_tx_verify_marker "$_zte_recover_txid" \
			"$_zte_recover_state" || return 1
		zte_charging_tx_commit_restore || { zte_charging_tx_revert || :; return 1; }
	fi
	_zte_recover_txid=$zte_charging_tx_txid
	_zte_recover_state=$zte_charging_tx_marker_state
	zte_charging_tx_reload_and_ack "$_zte_charging_tx_service" || return 1
	zte_charging_tx_clear_marker "$_zte_recover_txid" \
		"$_zte_recover_state"
}

zte_charging_tx_prepare_dirs() {
	_zte_charging_tx_state_dir=$1
	_zte_charging_tx_savedir_root=${ZTE_CHARGING_TX_SAVEDIR_ROOT:-$_zte_charging_tx_state_dir}
	for _zte_dir in "$_zte_charging_tx_state_dir" "$_zte_charging_tx_savedir_root"; do
		[ ! -L "$_zte_dir" ] || return 1
		[ -d "$_zte_dir" ] || (umask 077 && mkdir -p "$_zte_dir") || return 1
		chmod 700 "$_zte_dir" || return 1
	done
	zte_charging_tx_lock_file=$_zte_charging_tx_state_dir/charging-transaction.lock
	if [ -e "$zte_charging_tx_lock_file" ] || [ -L "$zte_charging_tx_lock_file" ]; then
		[ -f "$zte_charging_tx_lock_file" ] && [ ! -L "$zte_charging_tx_lock_file" ] || return 1
	else
		(umask 077 && : >"$zte_charging_tx_lock_file") || return 1
	fi
	chmod 600 "$zte_charging_tx_lock_file" || return 1
	zte_charging_tx_ack_file=$_zte_charging_tx_state_dir/charging-transaction.ack
}

zte_charging_tx_cleanup_orphans() {
	for _zte_orphan in "$_zte_charging_tx_savedir_root"/charging-uci.*; do
		[ -e "$_zte_orphan" ] || [ -L "$_zte_orphan" ] || continue
		case ${_zte_orphan##*/} in charging-uci.*) ;; *) return 1 ;; esac
		[ -d "$_zte_orphan" ] && [ ! -L "$_zte_orphan" ] || return 1
		rm -rf "$_zte_orphan" || return 1
	done
}

zte_charging_tx_begin_fail() {
	case ${zte_charging_tx_savedir:-} in
		"$_zte_charging_tx_savedir_root"/charging-uci.*)
			if [ -d "$zte_charging_tx_savedir" ] &&
				[ ! -L "$zte_charging_tx_savedir" ]; then
				rm -rf "$zte_charging_tx_savedir" || :
			fi
			;;
	esac
	"${ZTE_CHARGING_FLOCK_BIN:-flock}" -u 9 >/dev/null 2>&1 || :
	return 1
}

zte_charging_tx_begin_locked() {
	zte_charging_tx_savedir=''
	zte_charging_tx_prepare_dirs "$1" || return 1
	exec 9>>"$zte_charging_tx_lock_file" || return 1
	"${ZTE_CHARGING_FLOCK_BIN:-flock}" -n 9 >/dev/null 2>&1 || return 1
	zte_charging_tx_cleanup_orphans || { zte_charging_tx_begin_fail; return 1; }
	zte_charging_tx_savedir=$("${ZTE_CHARGING_TX_MKTEMP_BIN:-mktemp}" -d \
		"$_zte_charging_tx_savedir_root/charging-uci.XXXXXX") ||
		{ zte_charging_tx_begin_fail; return 1; }
	"${ZTE_CHARGING_TX_SAVEDIR_CHMOD_BIN:-chmod}" 700 \
		"$zte_charging_tx_savedir" || { zte_charging_tx_begin_fail; return 1; }
}

zte_charging_tx_end_locked() {
	case ${zte_charging_tx_savedir:-} in
		"$_zte_charging_tx_savedir_root"/charging-uci.*)
			[ -d "$zte_charging_tx_savedir" ] && [ ! -L "$zte_charging_tx_savedir" ] && rm -rf "$zte_charging_tx_savedir" ;;
	esac
	"${ZTE_CHARGING_FLOCK_BIN:-flock}" -u 9 >/dev/null 2>&1 || :
}

zte_charging_tx_nonce() {
	if [ -n "${ZTE_CHARGING_TX_TEST_NONCE:-}" ]; then
		_zte_charging_tx_nonce=$ZTE_CHARGING_TX_TEST_NONCE
	else
		_zte_charging_tx_nonce=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null |
			tr -d ' \n') || return 1
	fi
	[ "${#_zte_charging_tx_nonce}" = 32 ] || return 1
	case $_zte_charging_tx_nonce in *[!0-9a-f]*) return 1 ;; esac
	printf '%s\n' "$_zte_charging_tx_nonce"
}

zte_charging_transaction_apply() (
	_zte_charging_tx_state_dir=$1; _zte_charging_tx_service=$2
	_zte_charging_tx_enabled=$3; _zte_charging_tx_low=$4; _zte_charging_tx_high=$5
	case $_zte_charging_tx_enabled in 0|1) ;; *) printf '%s\n' settings_write_failed; return ;; esac
	zte_validate_thresholds "$_zte_charging_tx_low" "$_zte_charging_tx_high" || { printf '%s\n' settings_write_failed; return; }
	zte_charging_tx_begin_locked "$_zte_charging_tx_state_dir" || { printf '%s\n' transaction_busy; return; }
	trap 'zte_charging_tx_end_locked' EXIT
	trap 'exit 1' HUP INT TERM
	if [ -n "${ZTE_CHARGING_TX_AFTER_LOCK_BARRIER:-}" ]; then
		sh -c 'printf "%s\n" "$PPID"' \
			>"$ZTE_CHARGING_TX_AFTER_LOCK_BARRIER.pid"
		: >"$ZTE_CHARGING_TX_AFTER_LOCK_BARRIER.ready"
		while [ ! -f "$ZTE_CHARGING_TX_AFTER_LOCK_BARRIER.release" ]; do sleep 0.05; done
	fi
	zte_charging_tx_recover_locked "$_zte_charging_tx_service" || { printf '%s\n' transaction_recovery_failed; return; }
	if [ -e "$zte_charging_tx_ack_file" ] ||
		[ -L "$zte_charging_tx_ack_file" ]; then
		printf '%s\n' transaction_recovery_failed
		return
	fi
	zte_charging_tx_snapshot || { printf '%s\n' settings_snapshot_failed; return; }
	_zte_charging_tx_nonce=$(zte_charging_tx_nonce) || { printf '%s\n' settings_write_failed; return; }
	# This transaction intentionally runs in a function-level subshell.
	# shellcheck disable=SC2030
	zte_charging_tx_txid=tx-$(date +%s)-$$-$_zte_charging_tx_nonce
	if ! zte_charging_tx_uci set "$ZTE_CHARGING_TX_SECTION.enabled=$_zte_charging_tx_enabled" ||
		! zte_charging_tx_uci set "$ZTE_CHARGING_TX_SECTION.low_percent=$_zte_charging_tx_low" ||
		! zte_charging_tx_uci set "$ZTE_CHARGING_TX_SECTION.high_percent=$_zte_charging_tx_high" ||
		! zte_charging_tx_stage_marker_snapshot ||
		! zte_charging_tx_uci commit "$ZTE_CHARGING_TX_PACKAGE"; then
		if zte_charging_tx_revert; then printf '%s\n' settings_write_failed; else printf '%s\n' settings_rollback_failed; fi
		return
	fi
	if zte_charging_tx_marker_read; then printf '%s\n' settings_rollback_failed; return; else [ "$?" = 1 ] || { printf '%s\n' settings_rollback_failed; return; }; fi
	zte_charging_tx_current_matches_marker_state || { printf '%s\n' transaction_recovery_failed; return; }
	_zte_apply_txid=$zte_charging_tx_txid
	_zte_apply_state=$zte_charging_tx_marker_state
	if zte_charging_tx_reload_and_ack "$_zte_charging_tx_service"; then
		if zte_charging_tx_clear_marker "$_zte_apply_txid" \
			"$_zte_apply_state"; then
			printf '%s\n' ok
		else
			_zte_clear_status=$?
			if [ "$_zte_clear_status" = 2 ]; then printf '%s\n' transaction_recovery_failed; else printf '%s\n' settings_rollback_failed; fi
		fi
		return
	else
		_zte_reload_status=$?
		[ "$_zte_reload_status" = 1 ] || { printf '%s\n' transaction_recovery_failed; return; }
	fi
	zte_charging_tx_verify_marker "$_zte_apply_txid" \
		"$_zte_apply_state" || { printf '%s\n' transaction_recovery_failed; return; }
	zte_charging_tx_commit_restore || { zte_charging_tx_revert || :; printf '%s\n' settings_rollback_failed; return; }
	_zte_apply_txid=$zte_charging_tx_txid
	_zte_apply_state=$zte_charging_tx_marker_state
	if zte_charging_tx_reload_and_ack "$_zte_charging_tx_service"; then :; else
		_zte_restore_status=$?
		if [ "$_zte_restore_status" = 2 ]; then printf '%s\n' transaction_recovery_failed; else printf '%s\n' service_restore_failed; fi
		return
	fi
	if zte_charging_tx_clear_marker "$_zte_apply_txid" \
		"$_zte_apply_state"; then :; else
		_zte_clear_status=$?
		if [ "$_zte_clear_status" = 2 ]; then printf '%s\n' transaction_recovery_failed; else printf '%s\n' settings_rollback_failed; fi
		return
	fi
	printf '%s\n' service_reload_failed
)

zte_charging_tx_ack_write() {
	_zte_ack_file=$1; _zte_ack_tmp=$1.tmp.$$
	if [ -e "$_zte_ack_file" ] || [ -L "$_zte_ack_file" ]; then
		zte_charging_tx_ack_file_valid "$_zte_ack_file" || return 1
	fi
	(umask 077 && printf '%s|%s|%s|%s|%s\n' "$2" "$3" "$4" "$5" "$6" >"$_zte_ack_tmp") || return 1
	chmod 600 "$_zte_ack_tmp" || { rm -f "$_zte_ack_tmp"; return 1; }
	mv "$_zte_ack_tmp" "$_zte_ack_file"
}

zte_charging_tx_daemon_savedir_prepare() {
	_zte_charging_tx_daemon_savedir=$1/charging-ack-read
	if [ -e "$_zte_charging_tx_daemon_savedir" ] ||
		[ -L "$_zte_charging_tx_daemon_savedir" ]; then
		[ -d "$_zte_charging_tx_daemon_savedir" ] &&
			[ ! -L "$_zte_charging_tx_daemon_savedir" ] || return 1
		[ "$(zte_charging_tx_file_mode \
			"$_zte_charging_tx_daemon_savedir")" = 700 ] || return 1
	else
		(umask 077 && mkdir "$_zte_charging_tx_daemon_savedir") || return 1
		chmod 700 "$_zte_charging_tx_daemon_savedir" || return 1
	fi
	zte_charging_tx_savedir=$_zte_charging_tx_daemon_savedir
}

zte_charging_transaction_daemon_finalize() (
	_zte_charging_tx_state_dir=$1; _zte_loaded_enabled=$2; _zte_loaded_low=$3; _zte_loaded_high=$4
	if [ ! -d "$_zte_charging_tx_state_dir" ] ||
		[ -L "$_zte_charging_tx_state_dir" ]; then
		printf '%s\n' transaction_recovery_failed
		return
	fi
	zte_charging_tx_daemon_savedir_prepare "$_zte_charging_tx_state_dir" || { printf '%s\n' transaction_recovery_failed; return; }
	if zte_charging_tx_marker_read; then printf '%s\n' ok; return; else _zte_marker_status=$?; fi
	[ "$_zte_marker_status" = 1 ] || { printf '%s\n' transaction_recovery_failed; return; }
	zte_charging_tx_current_matches_marker_state || { printf '%s\n' transaction_recovery_failed; return; }
	zte_charging_tx_expected
	if [ "$_zte_loaded_enabled" != "$zte_charging_tx_expected_enabled" ] ||
		[ "$_zte_loaded_low" != "$zte_charging_tx_expected_low" ] ||
		[ "$_zte_loaded_high" != "$zte_charging_tx_expected_high" ]; then
		printf '%s\n' transaction_recovery_failed
		return
	fi
	# marker_read assigns this value in the current daemon-finalize subshell.
	# shellcheck disable=SC2031
	zte_charging_tx_ack_write "$_zte_charging_tx_state_dir/charging-transaction.ack" \
		"$zte_charging_tx_txid" "$zte_charging_tx_marker_state" \
		"$zte_charging_tx_expected_enabled" "$zte_charging_tx_expected_low" \
		"$zte_charging_tx_expected_high" || { printf '%s\n' transaction_recovery_failed; return; }
	printf '%s\n' ok
)
