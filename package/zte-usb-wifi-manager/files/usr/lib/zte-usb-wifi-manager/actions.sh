#!/bin/sh

zte_action_type_valid() {
	case ${1-} in
		switch_sim|set_apn|set_connection_mode|set_wifi|set_traffic_plan|\
reset_traffic|send_sms|delete_sms|mark_sms_read)
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
		"$_zte_action_root/actions/results" || return 1
	chmod 700 \
		"$_zte_action_root/actions" \
		"$_zte_action_root/actions/pending" \
		"$_zte_action_root/actions/running" \
		"$_zte_action_root/actions/results"
}

zte_action_has_active() {
	_zte_action_root=$1
	for _zte_action_file in \
		"$_zte_action_root"/actions/pending/*.json \
		"$_zte_action_root"/actions/running/*.json
	do
		[ -f "$_zte_action_file" ] && return 0
	done
	return 1
}

zte_action_get() {
	_zte_action_root=$1
	_zte_operation_id=$2
	zte_operation_id_valid "$_zte_operation_id" || return 1

	for _zte_action_state in pending running results; do
		_zte_action_file=$_zte_action_root/actions/$_zte_action_state/\
$_zte_operation_id.json
		if [ -s "$_zte_action_file" ]; then
			cat "$_zte_action_file"
			return 0
		fi
	done
	return 1
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
	zte_action_get "$_zte_action_root" "$_zte_operation_id" >/dev/null 2>&1 &&
		return 1

	_zte_action_pending=$_zte_action_root/actions/pending
	_zte_action_target=$_zte_action_pending/$_zte_operation_id.json
	_zte_action_tmp=$_zte_action_pending/.$_zte_operation_id.tmp.$$

	umask 077
	printf '{"operation_id":"%s","type":"%s","state":"queued","payload":%s,"created":%s}\n' \
		"$_zte_operation_id" "$_zte_action_type" \
		"$_zte_action_payload" "$_zte_action_created" >"$_zte_action_tmp" ||
		return 1
	chmod 600 "$_zte_action_tmp" || return 1
	mv "$_zte_action_tmp" "$_zte_action_target"
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

	_zte_action_tmp=$_zte_action_running.tmp.$$
	sed 's/"state":"queued"/"state":"running"/' \
		"$_zte_action_running" >"$_zte_action_tmp" || return 1
	chmod 600 "$_zte_action_tmp" || return 1
	mv "$_zte_action_tmp" "$_zte_action_running" || return 1
	cat "$_zte_action_running"
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
	_zte_action_running=$_zte_action_root/actions/running/$_zte_operation_id.json
	[ -s "$_zte_action_running" ] || return 1
	_zte_action_type=$(zte_json_top_get "$(cat "$_zte_action_running")" type)
	zte_action_type_valid "$_zte_action_type" || return 1

	_zte_action_result=$_zte_action_root/actions/results/$_zte_operation_id.json
	_zte_action_tmp=$_zte_action_result.tmp.$$
	umask 077
	printf '{"operation_id":"%s","type":"%s","state":"%s","code":"%s","updated":%s}\n' \
		"$_zte_operation_id" "$_zte_action_type" "$_zte_action_state" \
		"$_zte_action_code" "$_zte_action_updated" >"$_zte_action_tmp" ||
		return 1
	chmod 600 "$_zte_action_tmp" || return 1
	mv "$_zte_action_tmp" "$_zte_action_result" || return 1
	rm -f "$_zte_action_running"
}

zte_action_recover_running() {
	_zte_action_root=$1
	_zte_action_updated=$2
	zte_is_uint "$_zte_action_updated" || return 1
	zte_action_init "$_zte_action_root" || return 1

	for _zte_action_file in "$_zte_action_root"/actions/running/*.json; do
		[ -f "$_zte_action_file" ] || continue
		_zte_action_name=${_zte_action_file##*/}
		_zte_operation_id=${_zte_action_name%.json}
		zte_action_finish \
			"$_zte_action_root" "$_zte_operation_id" failed \
			daemon_restarted "$_zte_action_updated" || return 1
	done
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
