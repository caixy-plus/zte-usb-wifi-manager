#!/bin/sh

zte_password_valid() {
	_zte_password=${1-}
	[ -n "$_zte_password" ] || return 1
	[ "${#_zte_password}" -le 256 ] || return 1
	case $_zte_password in
		*'
'*|*''*) return 1 ;;
	esac
}

zte_credential_path_valid() {
	_zte_credential_path=${1-}
	case $_zte_credential_path in
		/*) ;;
		*) return 1 ;;
	esac
	case $_zte_credential_path in
		/|*/../*|*/..|*'
'*|*''*) return 1 ;;
	esac
}

# Print a file's numeric owner UID.
zte_file_owner_uid() {
	if _zte_owner=$(stat -c '%u' "$1" 2>/dev/null); then
		printf '%s\n' "$_zte_owner"
	else
		stat -f '%u' "$1" 2>/dev/null
	fi
}

zte_effective_uid() {
	id -u
}

zte_file_mode() {
	if _zte_mode=$(stat -c '%a' "$1" 2>/dev/null); then
		printf '%s\n' "$_zte_mode"
	else
		stat -f '%Lp' "$1" 2>/dev/null
	fi
}

# Print non-secret file metadata that changes when the atomically installed
# credential file is replaced. An absent path has a stable explicit revision.
zte_credential_revision() {
	zte_credential_path_valid "$1" || return 1
	if [ ! -e "$1" ] && [ ! -L "$1" ]; then
		printf '%s\n' absent
		return 0
	fi
	[ -f "$1" ] || return 1
	[ ! -L "$1" ] || return 1
	[ "$(zte_file_owner_uid "$1")" = "$(zte_effective_uid)" ] || return 1
	[ "$(zte_file_mode "$1")" = 600 ] || return 1
	if _zte_revision=$(stat -c '%d:%i:%Y:%s' "$1" 2>/dev/null); then
		printf '%s\n' "$_zte_revision"
	else
		stat -f '%d:%i:%m:%z' "$1" 2>/dev/null
	fi
}

# Remove only a secure regular credential file owned by this process. Missing
# credentials are already cleared and therefore succeed idempotently.
zte_clear_password() (
	_zte_credential_path=$1
	zte_credential_path_valid "$_zte_credential_path" || return 1
	if [ ! -e "$_zte_credential_path" ] &&
		[ ! -L "$_zte_credential_path" ]; then
		return 0
	fi
	[ -f "$_zte_credential_path" ] || return 1
	[ ! -L "$_zte_credential_path" ] || return 1
	[ "$(zte_file_owner_uid "$_zte_credential_path")" = \
		"$(zte_effective_uid)" ] || return 1
	[ "$(zte_file_mode "$_zte_credential_path")" = 600 ] || return 1
	rm -f "$_zte_credential_path"
)

# $1 credential file containing a "password=..." line.
# Accepts only a regular file owned by the effective process UID, with no
# group/other permission bits. The daemon therefore requires root ownership.
zte_read_password() {
	zte_credential_path_valid "$1" || return 1
	[ -f "$1" ] || return 1
	[ ! -L "$1" ] || return 1
	[ "$(zte_file_owner_uid "$1")" = "$(zte_effective_uid)" ] || return 1
	[ "$(zte_file_mode "$1")" = 600 ] || return 1
	_zte_password=$(
		awk '
			index($0, "password=") == 1 {
				print substr($0, 10)
				found = 1
				exit
			}
			END {
				if (!found)
					exit 1
			}
		' "$1"
	) || return 1
	zte_password_valid "$_zte_password" || return 1
	printf '%s\n' "$_zte_password"
}

# $1 absolute credential path, $2 password. Atomically installs a root-only
# file without exposing the password in process arguments or status output.
zte_write_password() (
	_zte_credential_path=$1
	_zte_password=$2
	zte_credential_path_valid "$_zte_credential_path" || return 1
	zte_password_valid "$_zte_password" || return 1
	[ ! -L "$_zte_credential_path" ] || return 1
	if [ -e "$_zte_credential_path" ]; then
		[ -f "$_zte_credential_path" ] || return 1
	fi

	_zte_credential_dir=${_zte_credential_path%/*}
	if [ ! -e "$_zte_credential_dir" ]; then
		umask 077
		mkdir -p "$_zte_credential_dir" || return 1
		chmod 700 "$_zte_credential_dir" || return 1
	else
		[ -d "$_zte_credential_dir" ] &&
			[ ! -L "$_zte_credential_dir" ] || return 1
	fi

	_zte_credential_tmp=$_zte_credential_path.tmp.$$
	[ ! -e "$_zte_credential_tmp" ] &&
		[ ! -L "$_zte_credential_tmp" ] || return 1
	umask 077
	if ! printf 'password=%s\n' "$_zte_password" >"$_zte_credential_tmp"; then
		rm -f "$_zte_credential_tmp"
		return 1
	fi
	if ! chmod 600 "$_zte_credential_tmp" ||
		! mv "$_zte_credential_tmp" "$_zte_credential_path"; then
		rm -f "$_zte_credential_tmp"
		return 1
	fi
)
