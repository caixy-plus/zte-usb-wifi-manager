#!/bin/sh

ZTE_SESSION_LOCK_FILE=${ZTE_SESSION_LOCK_FILE:-/var/run/zte-usb-wifi-manager-session.lock}
ZTE_SESSION_LOCK_ATTEMPTS=${ZTE_SESSION_LOCK_ATTEMPTS:-10}
ZTE_SESSION_LOCK_INTERVAL=${ZTE_SESSION_LOCK_INTERVAL:-1}

# The U25S exposes one global LD challenge. Serialize the LD -> LOGIN exchange
# across the daemon, calibration tools and action executors.
zte_session_lock_acquire() {
    _zte_lock_parent=${ZTE_SESSION_LOCK_FILE%/*}
    [ -d "$_zte_lock_parent" ] || return 1
    _zte_session_claim_file=$ZTE_SESSION_LOCK_FILE.claim.$$
    [ ! -e "$_zte_session_claim_file" ] &&
        [ ! -L "$_zte_session_claim_file" ] || return 1
    umask 077
    printf '%s\n' "$$" >"$_zte_session_claim_file" || return 1
    chmod 600 "$_zte_session_claim_file" 2>/dev/null || {
        rm -f "$_zte_session_claim_file" 2>/dev/null || :
        return 1
    }

    _zte_lock_attempt=0
    while [ "$_zte_lock_attempt" -lt "$ZTE_SESSION_LOCK_ATTEMPTS" ]; do
        if ln "$_zte_session_claim_file" \
            "$ZTE_SESSION_LOCK_FILE" 2>/dev/null; then
            rm -f "$_zte_session_claim_file" 2>/dev/null || {
                rm -f "$ZTE_SESSION_LOCK_FILE" 2>/dev/null || :
                return 1
            }
            _zte_session_claim_file=
            _zte_session_lock_owned=1
            return 0
        fi

        _zte_lock_attempt=$((_zte_lock_attempt + 1))
        [ "$_zte_lock_attempt" -lt "$ZTE_SESSION_LOCK_ATTEMPTS" ] || {
            rm -f "$_zte_session_claim_file" 2>/dev/null || :
            return 1
        }
        sleep "$ZTE_SESSION_LOCK_INTERVAL"
    done
    rm -f "$_zte_session_claim_file" 2>/dev/null || :
    return 1
}

zte_session_lock_release() {
    [ "${_zte_session_lock_owned:-0}" = 1 ] || return 0
    _zte_session_lock_owned=0
    if [ -f "$ZTE_SESSION_LOCK_FILE" ] &&
        [ ! -L "$ZTE_SESSION_LOCK_FILE" ]; then
        IFS= read -r _zte_lock_pid \
            <"$ZTE_SESSION_LOCK_FILE" || _zte_lock_pid=
        [ "$_zte_lock_pid" = "$$" ] || return 1
    else
        return 1
    fi
    rm -f "$ZTE_SESSION_LOCK_FILE" 2>/dev/null
}

zte_session_lock_cleanup() {
    zte_session_lock_release >/dev/null 2>&1 || :
    if [ -n "${_zte_session_claim_file:-}" ]; then
        rm -f "$_zte_session_claim_file" 2>/dev/null || :
    fi
}

# Print the lowercase hex SHA-256 of "$1" using whatever tool exists.
# Fails when the tool output is not a 64-character lowercase hex digest.
zte_sha256_hex() {
    if command -v sha256sum >/dev/null 2>&1; then
        _zte_hash=$(printf '%s' "$1" | sha256sum | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        _zte_hash=$(printf '%s' "$1" | shasum -a 256 | awk '{print $1}')
    else
        _zte_hash=$(printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}')
    fi
    case $_zte_hash in
        *[!0-9a-f]*|'') return 1 ;;
    esac
    [ "${#_zte_hash}" -eq 64 ] || return 1
    printf '%s\n' "$_zte_hash"
}

# $1 password, $2 LD challenge -> uppercase double-SHA-256 login digest.
# The target WebUI's SHA256() returns uppercase hex after both rounds, so the
# first digest must be uppercased before appending the LD challenge.
zte_session_digest() {
    _zte_step1=$(zte_sha256_hex "$1") || return 1
    _zte_step1=$(printf '%s\n' "$_zte_step1" |
        tr '[:lower:]' '[:upper:]') || return 1
    _zte_step2=$(zte_sha256_hex "$_zte_step1$2") || return 1
    printf '%s\n' "$_zte_step2" | tr '[:lower:]' '[:upper:]'
}

zte_session_origin() {
	case ${1-} in
		http://*|https://*) _zte_session_origin=$1 ;;
		*) _zte_session_origin=http://${1-} ;;
	esac
	zte_http_origin_valid "$_zte_session_origin" || return 1
	printf '%s\n' "$_zte_session_origin"
}

# $1 host, $2 password, $3 cookie jar. Never logs password, digest or cookie.
zte_session_login() (
    _zte_session_lock_owned=0
    _zte_session_claim_file=
    trap zte_session_lock_cleanup 0
    trap 'exit 129' 1
    trap 'exit 130' 2
    trap 'exit 143' 15
    zte_session_lock_acquire || return 1

    _zte_origin=$(zte_session_origin "$1") || return 1
    _zte_ld_response=$(zte_http_get \
        "$_zte_origin/goform/goform_get_cmd_process?cmd=LD&isTest=false" "$3") || return 1
    _zte_ld=$(zte_json_flat_get "$_zte_ld_response" LD)
    case $_zte_ld in
        ''|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    _zte_digest=$(zte_session_digest "$2" "$_zte_ld") || return 1
    _zte_login_response=$(zte_http_post \
        "$_zte_origin/goform/goform_set_cmd_process" \
        "isTest=false&goformId=LOGIN&password=$_zte_digest" "$3") || return 1
    case $(zte_json_flat_get "$_zte_login_response" result) in
        0|4) return 0 ;;
        *) return 1 ;;
    esac
)
