#!/bin/sh

zte_action_type_valid() {
	case ${1-} in
		switch_sim|set_apn|set_connection_mode|set_wifi|set_traffic_plan|\
reset_traffic|send_sms|delete_sms|mark_sms_read|reboot_device|shutdown_device|\
set_power_supply_mode)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

zte_operation_id_valid() {
	case ${1-} in
		op-*) ;;
		*) return 1 ;;
	esac

	_zte_operation_rest=${1#op-}
	_zte_operation_epoch=${_zte_operation_rest%%-*}
	_zte_operation_pid=${_zte_operation_rest#*-}
	[ "$_zte_operation_pid" != "$_zte_operation_rest" ] || return 1
	[ "${#_zte_operation_epoch}" -ge 10 ] || return 1
	zte_is_uint "$_zte_operation_epoch" &&
		zte_is_uint "$_zte_operation_pid"
}

zte_action_init() {
	_zte_action_root=${1-}
	[ -n "$_zte_action_root" ] && [ "$_zte_action_root" != / ] || return 1

	umask 077
	mkdir -p \
		"$_zte_action_root/actions/pending" \
		"$_zte_action_root/actions/running" \
		"$_zte_action_root/actions/verifying" \
		"$_zte_action_root/actions/results" || return 1
	chmod 700 \
		"$_zte_action_root/actions" \
		"$_zte_action_root/actions/pending" \
		"$_zte_action_root/actions/running" \
		"$_zte_action_root/actions/verifying" \
		"$_zte_action_root/actions/results"
}

# Short-lived serialization for every actions/active mutation. An existing or
# untrusted guard is never reclaimed: a crashed owner therefore blocks writes
# fail-closed until an operator resolves it.
zte_action_guard_claim() {
	_zte_action_root=$1
	zte_action_init "$_zte_action_root" || return 1
	_zte_action_guard=$_zte_action_root/actions/active.guard
	mkdir "$_zte_action_guard" 2>/dev/null || return 1
	chmod 700 "$_zte_action_guard" || return 1
}

zte_action_guard_release() {
	_zte_action_root=$1
	[ -n "$_zte_action_root" ] && [ "$_zte_action_root" != / ] || return 1
	_zte_action_guard=$_zte_action_root/actions/active.guard
	[ -d "$_zte_action_guard" ] && [ ! -L "$_zte_action_guard" ] || return 1
	rmdir "$_zte_action_guard" 2>/dev/null
}

zte_action_has_records() {
	_zte_action_root=$1
	for _zte_action_file in \
		"$_zte_action_root"/actions/pending/*.json \
		"$_zte_action_root"/actions/running/*.json \
		"$_zte_action_root"/actions/verifying/*.json
	do
		{ [ -e "$_zte_action_file" ] || [ -L "$_zte_action_file" ]; } &&
			return 0
	done
	return 1
}

zte_action_has_active() {
	_zte_action_root=$1
	[ -e "$_zte_action_root/actions/active" ] ||
		[ -L "$_zte_action_root/actions/active" ] ||
		zte_action_has_records "$_zte_action_root"
}

zte_action_process_start_id() {
	_zte_action_process_pid=$1
	zte_is_uint "$_zte_action_process_pid" || return 1
	if [ ! -d /proc ]; then
		printf '%s\n' portable
		return 0
	fi
	_zte_action_process_stat=/proc/$_zte_action_process_pid/stat
	[ -r "$_zte_action_process_stat" ] || return 1
	_zte_action_process_record=$(cat "$_zte_action_process_stat" 2>/dev/null) ||
		return 1
	case $_zte_action_process_record in
		*') '*) ;;
		*) return 1 ;;
	esac
	_zte_action_process_fields=${_zte_action_process_record##*) }
	_zte_action_process_start=$(printf '%s\n' \
		"$_zte_action_process_fields" | awk '{print $20}') || return 1
	zte_is_uint "$_zte_action_process_start" || return 1
	printf '%s\n' "$_zte_action_process_start"
}

# Tri-state result: 0 exists, 1 is positively absent, and 2 is unknown (for
# example, kill permission was denied while the proc entry still exists).
zte_action_process_liveness() {
	_zte_action_process_pid=$1
	zte_is_uint "$_zte_action_process_pid" || return 2
	kill -0 "$_zte_action_process_pid" 2>/dev/null && return 0
	if [ -d /proc ] && [ -d "/proc/$_zte_action_process_pid" ]; then
		return 2
	fi
	return 1
}

zte_action_slot_tmp_cleanup() {
	rm -f "$1"
}

_zte_action_slot_create_locked() {
	_zte_action_root=$1
	_zte_action_owner=$2
	_zte_action_nonce=${3-$$}
	case $_zte_action_owner in
		queue|automatic|reconcile) ;;
		*) return 1 ;;
	esac
	case $_zte_action_nonce in
		''|*[!A-Za-z0-9_-]*) return 1 ;;
	esac
	_zte_action_slot=$_zte_action_root/actions/active
	if [ -e "$_zte_action_slot" ] || [ -L "$_zte_action_slot" ]; then
		return 1
	fi
	_zte_action_owner_start=$(zte_action_process_start_id "$$") || return 1
	_zte_action_slot_tmp=$_zte_action_root/actions/.active.$$.\
$_zte_action_nonce.tmp
	umask 077
	rm -f "$_zte_action_slot_tmp" || return 1
	printf '%s %s %s\n' "$_zte_action_owner" "$$" \
		"$_zte_action_owner_start" >"$_zte_action_slot_tmp" ||
		return 1
	chmod 600 "$_zte_action_slot_tmp" || {
		zte_action_slot_tmp_cleanup "$_zte_action_slot_tmp" || :
		return 1
	}
	if ! ln "$_zte_action_slot_tmp" "$_zte_action_slot" 2>/dev/null; then
		zte_action_slot_tmp_cleanup "$_zte_action_slot_tmp" || :
		return 1
	fi
	zte_action_slot_tmp_cleanup "$_zte_action_slot_tmp" || :
	return 0
}

zte_action_slot_create() {
	_zte_action_root=$1
	zte_action_guard_claim "$_zte_action_root" || return 1
	_zte_action_slot_status=0
	_zte_action_slot_create_owner=$2
	_zte_action_slot_create_nonce=${3-$$}
	_zte_action_slot_create_locked \
		"$_zte_action_root" "$_zte_action_slot_create_owner" \
		"$_zte_action_slot_create_nonce" || _zte_action_slot_status=$?
	zte_action_guard_release "$_zte_action_root" || return 1
	return "$_zte_action_slot_status"
}

_zte_action_slot_remove_locked() {
	_zte_action_root=$1
	_zte_action_slot=$_zte_action_root/actions/active
	if [ -d "$_zte_action_slot" ] && [ ! -L "$_zte_action_slot" ]; then
		rmdir "$_zte_action_slot" 2>/dev/null
	elif [ -e "$_zte_action_slot" ] || [ -L "$_zte_action_slot" ]; then
		rm -f "$_zte_action_slot"
	fi
}

zte_action_slot_remove() {
	_zte_action_root=$1
	zte_action_guard_claim "$_zte_action_root" || return 1
	_zte_action_slot_status=0
	_zte_action_slot_remove_locked "$_zte_action_root" ||
		_zte_action_slot_status=$?
	zte_action_guard_release "$_zte_action_root" || return 1
	return "$_zte_action_slot_status"
}

# Print the slot type observed at one point in time. Callers must treat
# absent as final for that reconciliation pass: removing after an observed
# absence could delete a new owner that claimed immediately afterwards.
zte_action_slot_observe() {
	_zte_action_root=$1
	_zte_action_slot=$_zte_action_root/actions/active
	if [ -L "$_zte_action_slot" ]; then
		printf '%s\n' unknown
	elif [ -d "$_zte_action_slot" ]; then
		printf '%s\n' legacy
	elif [ -f "$_zte_action_slot" ]; then
		printf '%s\n' regular
	elif [ -e "$_zte_action_slot" ]; then
		printf '%s\n' unknown
	else
		printf '%s\n' absent
	fi
}

zte_action_slot_file_mode() {
	if _zte_action_slot_mode=$(stat -c '%a' "$1" 2>/dev/null); then
		printf '%s\n' "$_zte_action_slot_mode"
	else
		stat -f '%Lp' "$1" 2>/dev/null
	fi
}

# Tri-state result: 0 is live, 1 is positively stale, and 2 is unknown.
# Unknown includes malformed ownership and process-identity read failures and
# must always be retained fail-closed by reconciliation.
zte_action_slot_owner_live() {
	_zte_action_root=$1
	_zte_action_slot=$_zte_action_root/actions/active
	[ -f "$_zte_action_slot" ] && [ ! -L "$_zte_action_slot" ] || return 2
	[ "$(zte_action_slot_file_mode "$_zte_action_slot")" = 600 ] || return 2
	_zte_action_owner_record=$(cat "$_zte_action_slot" 2>/dev/null) || return 2
	_zte_action_owner=${_zte_action_owner_record%% *}
	_zte_action_owner_rest=${_zte_action_owner_record#* }
	_zte_action_owner_pid=${_zte_action_owner_rest%% *}
	_zte_action_owner_start=${_zte_action_owner_rest#* }
	[ "$_zte_action_owner_record" = \
		"$_zte_action_owner $_zte_action_owner_pid $_zte_action_owner_start" ] ||
		return 2
	case $_zte_action_owner in
		queue|automatic|reconcile) ;;
		*) return 2 ;;
	esac
	zte_is_uint "$_zte_action_owner_pid" &&
		[ "$_zte_action_owner_pid" -ge 2 ] || return 2
	case $_zte_action_owner_start in
		''|*[!A-Za-z0-9_-]*) return 2 ;;
	esac
	if zte_action_process_liveness "$_zte_action_owner_pid"; then
		:
	else
		_zte_action_process_status=$?
		[ "$_zte_action_process_status" = 1 ] && return 1
		return 2
	fi
	_zte_action_owner_observed=$(zte_action_process_start_id \
		"$_zte_action_owner_pid") || return 2
	[ "$_zte_action_owner_observed" = "$_zte_action_owner_start" ] || return 1
	return 0
}

# A queued/verifying record may release only the slot format owned by the
# manual action queue. An automatic owner is a possible successor and must be
# retained even if the durable record is ready to become terminal.
zte_action_slot_manual_owner() {
	_zte_action_root=$1
	_zte_action_slot=$_zte_action_root/actions/active
	[ -f "$_zte_action_slot" ] && [ ! -L "$_zte_action_slot" ] || return 1
	[ "$(zte_action_slot_file_mode "$_zte_action_slot")" = 600 ] || return 1
	_zte_action_owner_record=$(cat "$_zte_action_slot" 2>/dev/null) || return 1
	_zte_action_owner=${_zte_action_owner_record%% *}
	_zte_action_owner_rest=${_zte_action_owner_record#* }
	_zte_action_owner_pid=${_zte_action_owner_rest%% *}
	_zte_action_owner_start=${_zte_action_owner_rest#* }
	[ "$_zte_action_owner_record" = \
		"$_zte_action_owner $_zte_action_owner_pid $_zte_action_owner_start" ] ||
		return 1
	case $_zte_action_owner in queue|reconcile) ;; *) return 1 ;; esac
	zte_is_uint "$_zte_action_owner_pid" &&
		[ "$_zte_action_owner_pid" -ge 2 ] || return 1
	case $_zte_action_owner_start in
		''|*[!A-Za-z0-9_-]*) return 1 ;;
	esac
}

# Claim the exclusive slot shared by queued rpcd actions and daemon-owned
# automatic device writes. This is intentionally separate from the legacy USB
# power-transition marker, whose recovery semantics do not apply here.
zte_device_action_claim() {
	_zte_action_root=$1
	zte_action_has_records "$_zte_action_root" && return 1
	zte_action_slot_create "$_zte_action_root" automatic || return 1
	if zte_action_has_records "$_zte_action_root" ||
		zte_power_transition_active "$_zte_action_root"; then
		zte_action_slot_remove "$_zte_action_root" || :
		return 1
	fi
}

zte_device_action_release() {
	_zte_action_root=$1
	[ -n "$_zte_action_root" ] && [ "$_zte_action_root" != / ] || return 1
	zte_action_has_records "$_zte_action_root" && return 1
	zte_action_slot_remove "$_zte_action_root"
}

zte_power_transition_active() {
	_zte_action_root=$1
	[ -d "$_zte_action_root/actions/power-transition" ]
}

zte_power_transition_claim() {
	_zte_action_root=$1
	zte_action_init "$_zte_action_root" || return 1
	_zte_power_transition=$_zte_action_root/actions/power-transition
	mkdir "$_zte_power_transition" 2>/dev/null || return 1
	chmod 700 "$_zte_power_transition" || {
		rmdir "$_zte_power_transition" 2>/dev/null || :
		return 1
	}
	if zte_action_has_active "$_zte_action_root"; then
		rmdir "$_zte_power_transition" 2>/dev/null || :
		return 1
	fi
}

zte_power_transition_release() {
	_zte_action_root=$1
	[ -n "$_zte_action_root" ] && [ "$_zte_action_root" != / ] || return 1
	rmdir "$_zte_action_root/actions/power-transition" 2>/dev/null || :
}

zte_action_file_size() {
	_zte_action_size_file=$1
	if _zte_action_size=$(stat -c '%s' "$_zte_action_size_file" 2>/dev/null); then
		printf '%s\n' "$_zte_action_size"
	else
		stat -f '%z' "$_zte_action_size_file" 2>/dev/null
	fi
}

# Reject unsafe queue/result entries using metadata only. Content must never
# be read before this check succeeds.
zte_action_file_validate_basic() {
	_zte_action_basic_file=$1
	[ -f "$_zte_action_basic_file" ] &&
		[ ! -L "$_zte_action_basic_file" ] || return 1
	[ "$(zte_action_slot_file_mode "$_zte_action_basic_file")" = 600 ] ||
		return 1
	_zte_action_basic_size=$(zte_action_file_size \
		"$_zte_action_basic_file") || return 1
	zte_is_uint "$_zte_action_basic_size" &&
		[ "$_zte_action_basic_size" -gt 0 ] &&
		[ "$_zte_action_basic_size" -le 65536 ]
}

zte_action_get() {
	_zte_action_root=$1
	_zte_operation_id=$2
	zte_operation_id_valid "$_zte_operation_id" || return 1

	for _zte_action_state in pending running verifying results; do
		_zte_action_file=$_zte_action_root/actions/$_zte_action_state/\
$_zte_operation_id.json
		if [ -e "$_zte_action_file" ] || [ -L "$_zte_action_file" ]; then
			zte_action_file_validate_basic "$_zte_action_file" || return 1
			cat "$_zte_action_file"
			return 0
		fi
	done
	return 1
}

# Return the only operation fields safe to expose through rpcd. The durable
# queue record is private because its payload may contain credentials, SMS
# recipients/content, or message identifiers.
zte_action_public_status() {
	_zte_action_public_root=$1
	_zte_action_public_id=$2
	_zte_action_public_record=$(zte_action_get \
		"$_zte_action_public_root" "$_zte_action_public_id") || return 1
	_zte_action_public_type=$(zte_json_top_get \
		"$_zte_action_public_record" type 2>/dev/null) || return 1
	_zte_action_public_state=$(zte_json_top_get \
		"$_zte_action_public_record" state 2>/dev/null) || return 1
	zte_operation_id_valid "$_zte_action_public_id" || return 1
	[ "$(zte_json_top_get "$_zte_action_public_record" operation_id \
		2>/dev/null)" = "$_zte_action_public_id" ] || return 1
	zte_action_type_valid "$_zte_action_public_type" || return 1
	case $_zte_action_public_state in
		queued|running|verifying)
			_zte_action_public_created=$(zte_json_top_get \
				"$_zte_action_public_record" created 2>/dev/null) || return 1
			zte_is_uint "$_zte_action_public_created" || return 1
			printf '{"operation_id":"%s","type":"%s","state":"%s","created":%s}\n' \
				"$_zte_action_public_id" "$_zte_action_public_type" \
				"$_zte_action_public_state" "$_zte_action_public_created"
			;;
		succeeded|failed|timed_out)
			_zte_action_public_code=$(zte_json_top_get \
				"$_zte_action_public_record" code 2>/dev/null) || return 1
			_zte_action_public_updated=$(zte_json_top_get \
				"$_zte_action_public_record" updated 2>/dev/null) || return 1
			zte_action_code_valid "$_zte_action_public_code" || return 1
			zte_is_uint "$_zte_action_public_updated" || return 1
			printf '{"operation_id":"%s","type":"%s","state":"%s","code":"%s","updated":%s}\n' \
				"$_zte_action_public_id" "$_zte_action_public_type" \
				"$_zte_action_public_state" "$_zte_action_public_code" \
				"$_zte_action_public_updated"
			;;
		*) return 1 ;;
	esac
}

zte_action_enqueue() {
	_zte_action_root=$1
	_zte_operation_id=$2
	_zte_action_type=$3
	_zte_action_payload=$4
	_zte_action_created=$5

	zte_operation_id_valid "$_zte_operation_id" || return 1
	zte_action_type_valid "$_zte_action_type" || return 1
	zte_json_is_flat_object "$_zte_action_payload" || return 1
	zte_is_uint "$_zte_action_created" || return 1
	zte_action_init "$_zte_action_root" || return 1
	zte_action_has_active "$_zte_action_root" && return 1
	zte_action_slot_create \
		"$_zte_action_root" queue "$_zte_operation_id" || return 1
	if zte_power_transition_active "$_zte_action_root"; then
		zte_action_slot_remove "$_zte_action_root" || :
		return 1
	fi
	zte_action_get "$_zte_action_root" "$_zte_operation_id" >/dev/null 2>&1 &&
		{
			zte_action_slot_remove "$_zte_action_root" || :
			return 1
		}

	_zte_action_pending=$_zte_action_root/actions/pending
	_zte_action_target=$_zte_action_pending/$_zte_operation_id.json
	_zte_action_tmp=$_zte_action_pending/.$_zte_operation_id.tmp.$$

	umask 077
	printf '{"operation_id":"%s","type":"%s","state":"queued","payload":%s,"created":%s}\n' \
		"$_zte_operation_id" "$_zte_action_type" \
		"$_zte_action_payload" "$_zte_action_created" >"$_zte_action_tmp" ||
		{
			zte_action_slot_remove "$_zte_action_root" || :
			return 1
		}
	chmod 600 "$_zte_action_tmp" || {
		rm -f "$_zte_action_tmp"
		zte_action_slot_remove "$_zte_action_root" || :
		return 1
	}
	mv "$_zte_action_tmp" "$_zte_action_target" || {
		rm -f "$_zte_action_tmp"
		zte_action_slot_remove "$_zte_action_root" || :
		return 1
	}
}

zte_action_result_state_valid() {
	case ${1-} in
		succeeded|failed|timed_out) return 0 ;;
		*) return 1 ;;
	esac
}

zte_action_code_valid() {
	_zte_action_code=${1-}
	case $_zte_action_code in
		''|*[!a-z0-9_:-]*) return 1 ;;
	esac
	[ "${#_zte_action_code}" -le 64 ]
}

zte_action_claim() {
	_zte_action_root=$1
	zte_action_init "$_zte_action_root" || return 1
	for _zte_action_file in \
		"$_zte_action_root"/actions/running/*.json \
		"$_zte_action_root"/actions/verifying/*.json
	do
		{ [ -e "$_zte_action_file" ] || [ -L "$_zte_action_file" ]; } &&
			return 1
	done
	_zte_action_source=''
	for _zte_action_file in "$_zte_action_root"/actions/pending/*.json; do
		if [ -f "$_zte_action_file" ]; then
			_zte_action_source=$_zte_action_file
			break
		fi
	done
	[ -n "$_zte_action_source" ] || return 1

	_zte_action_name=${_zte_action_source##*/}
	_zte_operation_id=${_zte_action_name%.json}
	zte_operation_id_valid "$_zte_operation_id" || return 1
	_zte_action_running=$_zte_action_root/actions/running/$_zte_action_name
	mv "$_zte_action_source" "$_zte_action_running" || return 1
	_zte_action_rewrite_state \
		"$_zte_action_running" queued running "$_zte_operation_id" || return 1
	cat "$_zte_action_running"
}

# Print one durable restart-verification record. Status 1 means the queue is
# empty; status 2 means recovery state is inconsistent and must stay active.
zte_action_verifying_next() {
	_zte_action_root=$1
	zte_action_init "$_zte_action_root" || return 2
	for _zte_action_file in "$_zte_action_root"/actions/running/*.json; do
		{ [ -e "$_zte_action_file" ] || [ -L "$_zte_action_file" ]; } &&
			return 2
	done
	_zte_action_file=''
	for _zte_action_candidate in \
		"$_zte_action_root"/actions/verifying/*.json
	do
		if [ -e "$_zte_action_candidate" ] ||
			[ -L "$_zte_action_candidate" ]; then
			_zte_action_file=$_zte_action_candidate
			break
		fi
	done
	[ -n "$_zte_action_file" ] || return 1
	_zte_action_name=${_zte_action_file##*/}
	_zte_operation_id=${_zte_action_name%.json}
	zte_operation_id_valid "$_zte_operation_id" || return 2
	zte_action_record_validate \
		"$_zte_action_file" verifying "$_zte_operation_id" || return 2
	cat "$_zte_action_file" || return 2
}

_zte_action_finish_locked() {
	_zte_action_root=$1
	_zte_operation_id=$2
	_zte_action_state=$3
	_zte_action_code=$4
	_zte_action_updated=$5

	_zte_action_running=$_zte_action_root/actions/running/$_zte_operation_id.json
	_zte_action_verifying=$_zte_action_root/actions/verifying/$_zte_operation_id.json
	if [ -e "$_zte_action_running" ] && [ ! -e "$_zte_action_verifying" ]; then
		_zte_action_source=$_zte_action_running
	elif [ -e "$_zte_action_verifying" ] && [ ! -e "$_zte_action_running" ]; then
		_zte_action_source=$_zte_action_verifying
	else
		return 1
	fi
	zte_action_file_validate_basic "$_zte_action_source" || return 1
	_zte_action_running_record=$(cat "$_zte_action_source") || return 1
	[ "$(zte_json_top_get \
		"$_zte_action_running_record" operation_id)" = "$_zte_operation_id" ] ||
		return 1
	_zte_action_type=$(zte_json_top_get "$_zte_action_running_record" type)
	zte_action_type_valid "$_zte_action_type" || return 1

	_zte_action_result=$_zte_action_root/actions/results/$_zte_operation_id.json
	if [ -e "$_zte_action_result" ] || [ -L "$_zte_action_result" ]; then
		zte_action_terminal_record_validate \
			"$_zte_action_result" "$_zte_operation_id" \
			"$_zte_action_type" || return 1
	else
		_zte_action_tmp=$_zte_action_result.tmp.$$
		umask 077
		printf '{"operation_id":"%s","type":"%s","state":"%s","code":"%s","updated":%s}\n' \
			"$_zte_operation_id" "$_zte_action_type" "$_zte_action_state" \
			"$_zte_action_code" "$_zte_action_updated" >"$_zte_action_tmp" ||
			return 1
		chmod 600 "$_zte_action_tmp" || return 1
		mv "$_zte_action_tmp" "$_zte_action_result" || return 1
	fi
	rm "$_zte_action_source" || return 1
	_zte_action_release_manual_slot_if_idle_locked "$_zte_action_root"
}

_zte_action_release_manual_slot_if_idle_locked() {
	_zte_action_root=$1
	# A later manual record may already own the shared slot after external
	# recovery or state repair. Never unlink that successor merely because its
	# owner record uses the same queue/reconcile format as this operation.
	zte_action_has_records "$_zte_action_root" && return 0
	_zte_action_slot_observed=$(zte_action_slot_observe \
		"$_zte_action_root") || return 1
	case $_zte_action_slot_observed in
		absent) return 0 ;;
		regular)
			zte_action_slot_manual_owner "$_zte_action_root" || return 0
			_zte_action_slot_remove_locked "$_zte_action_root"
			;;
		*) return 0 ;;
	esac
}

zte_action_finish() {
	_zte_action_root=$1
	_zte_operation_id=$2
	_zte_action_state=$3
	_zte_action_code=$4
	_zte_action_updated=$5

	zte_operation_id_valid "$_zte_operation_id" || return 1
	zte_action_result_state_valid "$_zte_action_state" || return 1
	zte_action_code_valid "$_zte_action_code" || return 1
	zte_is_uint "$_zte_action_updated" || return 1
	zte_action_guard_claim "$_zte_action_root" || return 1
	_zte_action_finish_status=0
	_zte_action_finish_locked \
		"$_zte_action_root" "$_zte_operation_id" "$_zte_action_state" \
		"$_zte_action_code" "$_zte_action_updated" ||
		_zte_action_finish_status=$?
	zte_action_guard_release "$_zte_action_root" || return 1
	[ "$_zte_action_finish_status" = 0 ]
}

zte_action_record_validate() {
	_zte_action_record_file=$1
	_zte_action_record_expected_state=$2
	_zte_action_record_expected_id=$3
	zte_action_file_validate_basic "$_zte_action_record_file" || return 1
	_zte_action_record=$(cat "$_zte_action_record_file") || return 1
	[ "$(zte_json_top_get "$_zte_action_record" operation_id)" = \
		"$_zte_action_record_expected_id" ] || return 1
	[ "$(zte_json_top_get "$_zte_action_record" state)" = \
		"$_zte_action_record_expected_state" ] || return 1
	_zte_action_record_type=$(zte_json_top_get \
		"$_zte_action_record" type) || return 1
	zte_action_type_valid "$_zte_action_record_type" || return 1
	_zte_action_record_payload=$(zte_json_top_object_get \
		"$_zte_action_record" payload) || return 1
	zte_json_is_flat_object "$_zte_action_record_payload" || return 1
	_zte_action_record_created=$(zte_json_top_get \
		"$_zte_action_record" created) || return 1
	zte_is_uint "$_zte_action_record_created"
}

zte_action_terminal_record_validate() {
	_zte_action_terminal_file=$1
	_zte_action_terminal_id=$2
	_zte_action_terminal_expected_type=${3-}
	zte_action_file_validate_basic "$_zte_action_terminal_file" || return 1
	_zte_action_terminal_record=$(cat \
		"$_zte_action_terminal_file") || return 1
	zte_json_is_flat_object "$_zte_action_terminal_record" || return 1
	[ "$(zte_json_flat_keys "$_zte_action_terminal_record")" = \
"operation_id
type
state
code
updated" ] || return 1
	[ "$(zte_json_flat_get "$_zte_action_terminal_record" operation_id)" = \
		"$_zte_action_terminal_id" ] || return 1
	_zte_action_terminal_type=$(zte_json_flat_get \
		"$_zte_action_terminal_record" type)
	zte_action_type_valid "$_zte_action_terminal_type" || return 1
	[ -z "$_zte_action_terminal_expected_type" ] ||
		[ "$_zte_action_terminal_type" = \
			"$_zte_action_terminal_expected_type" ] || return 1
	_zte_action_terminal_state=$(zte_json_flat_get \
		"$_zte_action_terminal_record" state)
	zte_action_result_state_valid "$_zte_action_terminal_state" || return 1
	_zte_action_terminal_code=$(zte_json_flat_get \
		"$_zte_action_terminal_record" code)
	zte_action_code_valid "$_zte_action_terminal_code" || return 1
	_zte_action_terminal_updated=$(zte_json_flat_get \
		"$_zte_action_terminal_record" updated)
	zte_is_uint "$_zte_action_terminal_updated"
}

# Rewrite only the state field through a same-directory atomic replacement.
# The containing directory is authoritative during a crash window, so callers
# can safely repair an old state value after restart.
_zte_action_rewrite_state() {
	_zte_action_rewrite_file=$1
	_zte_action_rewrite_old=$2
	_zte_action_rewrite_new=$3
	_zte_action_rewrite_id=$4
	zte_action_record_validate \
		"$_zte_action_rewrite_file" "$_zte_action_rewrite_old" \
		"$_zte_action_rewrite_id" || return 1
	_zte_action_rewrite_record=$(cat "$_zte_action_rewrite_file") || return 1
	_zte_action_rewrite_type=$(zte_json_top_get \
		"$_zte_action_rewrite_record" type) || return 1
	_zte_action_rewrite_payload=$(zte_json_top_object_get \
		"$_zte_action_rewrite_record" payload) || return 1
	_zte_action_rewrite_created=$(zte_json_top_get \
		"$_zte_action_rewrite_record" created) || return 1
	_zte_action_rewrite_tmp=$_zte_action_rewrite_file.tmp.$$
	umask 077
	printf '{"operation_id":"%s","type":"%s","state":"%s","payload":%s,"created":%s}\n' \
		"$_zte_action_rewrite_id" "$_zte_action_rewrite_type" \
		"$_zte_action_rewrite_new" "$_zte_action_rewrite_payload" \
		"$_zte_action_rewrite_created" >"$_zte_action_rewrite_tmp" || return 1
	chmod 600 "$_zte_action_rewrite_tmp" || return 1
	mv "$_zte_action_rewrite_tmp" "$_zte_action_rewrite_file" || return 1
}

_zte_action_records_same_identity() {
	_zte_action_same_left=$1
	_zte_action_same_left_state=$2
	_zte_action_same_right=$3
	_zte_action_same_right_state=$4
	_zte_action_same_id=$5
	zte_action_record_validate \
		"$_zte_action_same_left" "$_zte_action_same_left_state" \
		"$_zte_action_same_id" || return 1
	zte_action_record_validate \
		"$_zte_action_same_right" "$_zte_action_same_right_state" \
		"$_zte_action_same_id" || return 1
	_zte_action_same_left_record=$(cat "$_zte_action_same_left") || return 1
	_zte_action_same_right_record=$(cat "$_zte_action_same_right") || return 1
	[ "$(zte_json_top_get "$_zte_action_same_left_record" type)" = \
		"$(zte_json_top_get "$_zte_action_same_right_record" type)" ] || return 1
	[ "$(zte_json_top_get "$_zte_action_same_left_record" created)" = \
		"$(zte_json_top_get "$_zte_action_same_right_record" created)" ] || return 1
	[ "$(zte_json_top_object_get "$_zte_action_same_left_record" payload)" = \
		"$(zte_json_top_object_get "$_zte_action_same_right_record" payload)" ]
}

_zte_action_recover_running_locked() {
	_zte_action_root=$1
	# Validate the complete set before moving any record. Directory location is
	# authoritative: queued in running means claim did not finish and running in
	# verifying means the recovery rename completed before its state rewrite.
	for _zte_action_file in "$_zte_action_root"/actions/running/*.json; do
		[ -e "$_zte_action_file" ] || [ -L "$_zte_action_file" ] || continue
		zte_action_file_validate_basic "$_zte_action_file" || return 1
		_zte_action_name=${_zte_action_file##*/}
		_zte_operation_id=${_zte_action_name%.json}
		zte_operation_id_valid "$_zte_operation_id" || return 1
		_zte_action_record=$(cat "$_zte_action_file" 2>/dev/null) || return 1
		_zte_action_state=$(zte_json_top_get \
			"$_zte_action_record" state 2>/dev/null) || return 1
		case $_zte_action_state in queued|running) ;; *) return 1 ;; esac
		zte_action_record_validate \
			"$_zte_action_file" "$_zte_action_state" \
			"$_zte_operation_id" || return 1
		_zte_action_type=$(zte_json_top_get \
			"$_zte_action_record" type) || return 1
		_zte_action_result=$_zte_action_root/actions/results/$_zte_action_name
		if [ -e "$_zte_action_result" ] || [ -L "$_zte_action_result" ]; then
			[ "$_zte_action_state" = running ] || return 1
			zte_action_terminal_record_validate \
				"$_zte_action_result" "$_zte_operation_id" \
				"$_zte_action_type" || return 1
		fi
		_zte_action_target=$_zte_action_root/actions/verifying/$_zte_action_name
		if [ -e "$_zte_action_target" ] || [ -L "$_zte_action_target" ]; then
			[ "$_zte_action_state" = running ] || return 1
			_zte_action_target_record=$(cat \
				"$_zte_action_target" 2>/dev/null) || return 1
			_zte_action_target_state=$(zte_json_top_get \
				"$_zte_action_target_record" state 2>/dev/null) || return 1
			case $_zte_action_target_state in running|verifying) ;; *) return 1 ;; esac
			_zte_action_records_same_identity \
				"$_zte_action_file" running "$_zte_action_target" \
				"$_zte_action_target_state" "$_zte_operation_id" || return 1
		fi
	done
	for _zte_action_file in "$_zte_action_root"/actions/verifying/*.json; do
		[ -e "$_zte_action_file" ] || [ -L "$_zte_action_file" ] || continue
		zte_action_file_validate_basic "$_zte_action_file" || return 1
		_zte_action_name=${_zte_action_file##*/}
		_zte_operation_id=${_zte_action_name%.json}
		zte_operation_id_valid "$_zte_operation_id" || return 1
		_zte_action_record=$(cat "$_zte_action_file" 2>/dev/null) || return 1
		_zte_action_state=$(zte_json_top_get \
			"$_zte_action_record" state 2>/dev/null) || return 1
		case $_zte_action_state in running|verifying) ;; *) return 1 ;; esac
		zte_action_record_validate \
			"$_zte_action_file" "$_zte_action_state" \
			"$_zte_operation_id" || return 1
		_zte_action_type=$(zte_json_top_get \
			"$_zte_action_record" type) || return 1
		_zte_action_result=$_zte_action_root/actions/results/$_zte_action_name
		if [ -e "$_zte_action_result" ] || [ -L "$_zte_action_result" ]; then
			zte_action_terminal_record_validate \
				"$_zte_action_result" "$_zte_operation_id" \
				"$_zte_action_type" || return 1
		fi
	done

	for _zte_action_file in "$_zte_action_root"/actions/running/*.json; do
		[ -f "$_zte_action_file" ] || continue
		_zte_action_name=${_zte_action_file##*/}
		_zte_operation_id=${_zte_action_name%.json}
		_zte_action_record=$(cat "$_zte_action_file") || return 1
		_zte_action_state=$(zte_json_top_get \
			"$_zte_action_record" state) || return 1
		_zte_action_result=$_zte_action_root/actions/results/$_zte_action_name
		if [ -e "$_zte_action_result" ]; then
			rm "$_zte_action_file" || return 1
			continue
		fi
		if [ "$_zte_action_state" = queued ]; then
			_zte_action_target=$_zte_action_root/actions/pending/$_zte_action_name
			[ ! -e "$_zte_action_target" ] && [ ! -L "$_zte_action_target" ] ||
				return 1
			mv "$_zte_action_file" "$_zte_action_target" || return 1
			continue
		fi
		_zte_action_target=$_zte_action_root/actions/verifying/$_zte_action_name
		if [ -e "$_zte_action_target" ]; then
			rm "$_zte_action_file" || return 1
		else
			mv "$_zte_action_file" "$_zte_action_target" || return 1
		fi
	done
	for _zte_action_file in "$_zte_action_root"/actions/verifying/*.json; do
		[ -f "$_zte_action_file" ] || continue
		_zte_action_name=${_zte_action_file##*/}
		_zte_operation_id=${_zte_action_name%.json}
		_zte_action_result=$_zte_action_root/actions/results/$_zte_action_name
		if [ -e "$_zte_action_result" ]; then
			rm "$_zte_action_file" || return 1
			continue
		fi
		_zte_action_record=$(cat "$_zte_action_file") || return 1
		_zte_action_state=$(zte_json_top_get \
			"$_zte_action_record" state) || return 1
		[ "$_zte_action_state" = running ] || continue
		_zte_action_rewrite_state \
			"$_zte_action_file" running verifying \
			"$_zte_operation_id" || return 1
	done
	_zte_action_release_manual_slot_if_idle_locked "$_zte_action_root"
}

zte_action_recover_running() {
	_zte_action_root=$1
	_zte_action_updated=$2
	zte_is_uint "$_zte_action_updated" || return 1
	zte_action_init "$_zte_action_root" || return 1
	zte_action_guard_claim "$_zte_action_root" || return 1
	_zte_action_recover_status=0
	_zte_action_recover_running_locked "$_zte_action_root" ||
		_zte_action_recover_status=$?
	zte_action_guard_release "$_zte_action_root" || return 1
	return "$_zte_action_recover_status"
}

_zte_action_reconcile_active_locked() {
	_zte_action_root=$1
	zte_action_init "$_zte_action_root" || return 1
	_zte_action_record_found=0
	for _zte_action_file in \
		"$_zte_action_root"/actions/pending/*.json \
		"$_zte_action_root"/actions/running/*.json \
		"$_zte_action_root"/actions/verifying/*.json
	do
		if [ -f "$_zte_action_file" ]; then
			_zte_action_record_found=1
			break
		fi
	done

	_zte_action_slot=$_zte_action_root/actions/active
	_zte_action_slot_observed=$(zte_action_slot_observe "$_zte_action_root") ||
		return 1
	if [ "$_zte_action_record_found" = 1 ]; then
		if [ "$_zte_action_slot_observed" = absent ]; then
			_zte_action_slot_create_locked \
				"$_zte_action_root" reconcile || return 1
		fi
	else
		case $_zte_action_slot_observed in
			absent|unknown) return 0 ;;
			legacy)
				_zte_action_slot_remove_locked "$_zte_action_root" || :
				return 0
				;;
			regular) ;;
			*) return 0 ;;
		esac
		if zte_action_slot_owner_live "$_zte_action_root"; then
			return 0
		else
			_zte_action_owner_status=$?
		fi
		[ "$_zte_action_owner_status" = 1 ] || return 0
		_zte_action_slot_remove_locked "$_zte_action_root" || :
	fi
}

zte_action_reconcile_active() {
	_zte_action_root=$1
	zte_action_guard_claim "$_zte_action_root" || return 1
	_zte_action_reconcile_status=0
	_zte_action_reconcile_active_locked "$_zte_action_root" ||
		_zte_action_reconcile_status=$?
	zte_action_guard_release "$_zte_action_root" || return 1
	return "$_zte_action_reconcile_status"
}

zte_action_prune_results() {
	_zte_action_root=$1
	_zte_action_max=$2
	zte_is_uint "$_zte_action_max" &&
		[ "$_zte_action_max" -ge 1 ] || return 1
	zte_action_init "$_zte_action_root" || return 1

	_zte_action_results=$_zte_action_root/actions/results
	_zte_action_count=0
	for _zte_action_file in "$_zte_action_results"/op-*.json; do
		[ -f "$_zte_action_file" ] || continue
		_zte_action_count=$((_zte_action_count + 1))
	done
	_zte_action_remove=$((_zte_action_count - _zte_action_max))
	[ "$_zte_action_remove" -gt 0 ] || return 0

	_zte_action_list=$_zte_action_results/.prune.$$
	find "$_zte_action_results" -type f -name 'op-*.json' |
		LC_ALL=C sort >"$_zte_action_list" || return 1
	sed -n "1,${_zte_action_remove}p" "$_zte_action_list" |
		while IFS= read -r _zte_action_file; do
			case $_zte_action_file in
				"$_zte_action_results"/op-*.json)
					rm -f "$_zte_action_file" || exit 1
					;;
				*) exit 1 ;;
			esac
		done
	_zte_action_status=$?
	rm -f "$_zte_action_list"
	return "$_zte_action_status"
}
