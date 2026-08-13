#!/bin/sh
set -eu

committed=${ZTE_TEST_UCI_COMMITTED:?}
mutation_log=${ZTE_TEST_UCI_LOG:?}
counter_file=${ZTE_TEST_UCI_COUNTER:?}
fail_points_file=${ZTE_TEST_UCI_FAIL_POINTS:?}
savedir=''

[ "${1-}" = -q ] && shift
if [ "${1-}" = -t ]; then
	savedir=$2
	shift 2
fi
[ -n "$savedir" ] || exit 1
stage=$savedir/zte-usb-wifi-manager
command_name=${1-}
argument=${2-}

mutation_begin() {
	count=$(cat "$counter_file")
	count=$((count + 1))
	printf '%s\n' "$count" >"$counter_file"
	printf '%s %s\n' "$command_name" "$argument" >>"$mutation_log"
	fail_points=$(cat "$fail_points_file")
	case ,$fail_points, in
		*,$count,*) return 1 ;;
	esac
}

committed_get() {
	key=$1
	awk -v prefix="$key=" '
		index($0, prefix) == 1 {
			print substr($0, length(prefix) + 1)
			found = 1
		}
		END { if (!found) exit 1 }
	' "$committed"
}

overlay_get() {
	key=$1
	if [ -f "$stage" ]; then
		stage_value=$(awk -F '|' -v wanted="$key" '
			$2 == wanted { result = $1 "|" $3; found = 1 }
			END { if (found) print result }
		' "$stage")
		case $stage_value in
			set\|*) printf '%s\n' "${stage_value#set|}"; return 0 ;;
			delete\|*) return 1 ;;
		esac
	fi
	committed_get "$key"
}

committed_remove() {
	key=$1
	tmp=$committed.tmp.$$
	awk -v prefix="$key=" 'index($0, prefix) != 1' \
		"$committed" >"$tmp"
	mv "$tmp" "$committed"
}

committed_set() {
	key=$1
	value=$2
	committed_remove "$key"
	printf '%s=%s\n' "$key" "$value" >>"$committed"
}

case $command_name in
	get)
		overlay_get "$argument"
		;;
	show)
		# The fault targets the charging snapshot read. Package-level reads stay
		# available so the transaction code can distinguish an absent marker
		# from an unreadable charging section.
		if [ -f "${ZTE_TEST_UCI_SHOW_FAIL_FILE:?}" ]; then
			show_count_file=$ZTE_TEST_UCI_SHOW_FAIL_FILE.count
			show_count=$(cat "$show_count_file" 2>/dev/null || printf 0)
			show_count=$((show_count + 1))
			printf '%s\n' "$show_count" >"$show_count_file"
			[ "$show_count" != 2 ] || exit 1
		fi
		awk -v key="$argument" '
			index($0, key "=") == 1 || index($0, key ".") == 1
		' "$committed"
		;;
	set)
		mutation_begin || exit 1
		key=${argument%%=*}
		value=${argument#*=}
		printf 'set|%s|%s\n' "$key" "$value" >>"$stage"
		;;
	delete)
		mutation_begin || exit 1
		printf 'delete|%s|\n' "$argument" >>"$stage"
		;;
	commit)
		mutation_begin || exit 1
		if [ -f "$stage" ]; then
			while IFS='|' read -r operation key value; do
				case $operation in
					set) committed_set "$key" "$value" ;;
					delete) committed_remove "$key" ;;
					*) exit 1 ;;
				esac
			done <"$stage"
			: >"$stage"
		fi
		;;
	revert)
		mutation_begin || exit 1
		: >"$stage"
		;;
	*) exit 1 ;;
esac
