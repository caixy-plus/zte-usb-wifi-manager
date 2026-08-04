#!/bin/sh
set -eu

lock_dir=${ZTE_TEST_FLOCK_DIR:?}
[ -z "${ZTE_TEST_FLOCK_LOG:-}" ] || printf '%s|%s\n' "$$" "$*" >>"$ZTE_TEST_FLOCK_LOG"
case ${1-} in
	-n)
		mkdir "$lock_dir" 2>/dev/null || exit 1
		if [ -n "${ZTE_TEST_FLOCK_BARRIER:-}" ]; then
			: >"${ZTE_TEST_FLOCK_ACQUIRED:?}"
			while [ ! -f "${ZTE_TEST_FLOCK_RELEASE:?}" ]; do
				sleep 0.05
			done
		fi
		;;
	-u)
		rmdir "$lock_dir" 2>/dev/null || exit 1
		;;
	*) exit 1 ;;
esac
