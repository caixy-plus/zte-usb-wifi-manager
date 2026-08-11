#!/bin/sh

_zte_event_is_uint() {
	case ${1-} in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

zte_event_level_valid() {
	case ${1-} in
		info|warn|error) return 0 ;;
		*) return 1 ;;
	esac
}

zte_event_type_valid() {
	case ${1-} in
		service|state|action|power|error|smart_charge) return 0 ;;
		*) return 1 ;;
	esac
}

zte_event_code_valid() {
	_zte_event_code=${1-}
	case $_zte_event_code in
		''|*[!a-z0-9_:-]*) return 1 ;;
	esac
	[ "${#_zte_event_code}" -le 64 ]
}

zte_event_init() {
	_zte_event_root=${1-}
	[ -n "$_zte_event_root" ] && [ "$_zte_event_root" != / ] || return 1
	umask 077
	mkdir -p "$_zte_event_root/logs" || return 1
	chmod 700 "$_zte_event_root/logs"
}

zte_event_write() {
	_zte_event_root=$1
	_zte_event_level=$2
	_zte_event_type=$3
	_zte_event_code=$4
	_zte_event_time=$5
	_zte_event_max_bytes=$6

	zte_event_level_valid "$_zte_event_level" || return 1
	zte_event_type_valid "$_zte_event_type" || return 1
	zte_event_code_valid "$_zte_event_code" || return 1
	_zte_event_is_uint "$_zte_event_time" || return 1
	_zte_event_is_uint "$_zte_event_max_bytes" || return 1
	[ "$_zte_event_max_bytes" -gt 0 ] || return 1
	zte_event_init "$_zte_event_root" || return 1

	_zte_event_dir=$_zte_event_root/logs
	_zte_event_file=$_zte_event_dir/events.jsonl
	_zte_event_line=$(printf \
		'{"time":%s,"level":"%s","type":"%s","code":"%s"}' \
		"$_zte_event_time" "$_zte_event_level" \
		"$_zte_event_type" "$_zte_event_code")
	_zte_event_line_bytes=$((
		$(printf '%s\n' "$_zte_event_line" | wc -c | tr -d ' ') + 0
	))
	_zte_event_current_bytes=0
	if [ -f "$_zte_event_file" ]; then
		_zte_event_current_bytes=$(wc -c <"$_zte_event_file" | tr -d ' ')
	fi

	if [ "$_zte_event_current_bytes" -gt 0 ] &&
		[ $((_zte_event_current_bytes + _zte_event_line_bytes)) \
			-gt "$_zte_event_max_bytes" ]; then
		if [ -f "$_zte_event_dir/events.1.jsonl" ]; then
			mv "$_zte_event_dir/events.1.jsonl" \
				"$_zte_event_dir/events.2.jsonl" || return 1
		fi
		mv "$_zte_event_file" "$_zte_event_dir/events.1.jsonl" || return 1
	fi

	umask 077
	printf '%s\n' "$_zte_event_line" >>"$_zte_event_file" || return 1
	chmod 600 "$_zte_event_file"
}

zte_event_list() {
	_zte_event_root=$1
	_zte_event_limit=$2
	_zte_event_is_uint "$_zte_event_limit" || return 1
	[ "$_zte_event_limit" -ge 1 ] &&
		[ "$_zte_event_limit" -le 200 ] || return 1

	{
		for _zte_event_file in \
			"$_zte_event_root/logs/events.2.jsonl" \
			"$_zte_event_root/logs/events.1.jsonl" \
			"$_zte_event_root/logs/events.jsonl"
		do
			[ -f "$_zte_event_file" ] && cat "$_zte_event_file"
		done
	} | tail -n "$_zte_event_limit" | awk '
		BEGIN { printf "{\"events\":[" }
		{
			if (count++)
				printf ","
			printf "%s", $0
		}
		END { print "]}" }
	'
}

# List newest events whose type matches the given filter. Scans the full
# rotated log set so product UIs can show only smart_charge history.
zte_event_list_filtered() {
	_zte_event_root=$1
	_zte_event_limit=$2
	_zte_event_type_filter=$3
	_zte_event_is_uint "$_zte_event_limit" || return 1
	[ "$_zte_event_limit" -ge 1 ] &&
		[ "$_zte_event_limit" -le 200 ] || return 1
	zte_event_type_valid "$_zte_event_type_filter" || return 1

	{
		for _zte_event_file in \
			"$_zte_event_root/logs/events.2.jsonl" \
			"$_zte_event_root/logs/events.1.jsonl" \
			"$_zte_event_root/logs/events.jsonl"
		do
			[ -f "$_zte_event_file" ] && cat "$_zte_event_file"
		done
	} | awk -v want="$_zte_event_type_filter" '
		BEGIN { n = 0 }
		{
			line = $0
			if (match(line, /"type":"[^"]+"/)) {
				type = substr(line, RSTART + 8, RLENGTH - 9)
				if (type == want) {
					n++
					buf[n] = line
				}
			}
		}
		END {
			start = n - '"$_zte_event_limit"' + 1
			if (start < 1)
				start = 1
			printf "{\"events\":["
			out = 0
			for (i = start; i <= n; i++) {
				if (out++)
					printf ","
				printf "%s", buf[i]
			}
			print "]}"
		}
	'
}
