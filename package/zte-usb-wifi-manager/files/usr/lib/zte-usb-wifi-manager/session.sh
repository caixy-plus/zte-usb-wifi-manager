#!/bin/sh

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
zte_session_digest() {
    _zte_step1=$(zte_sha256_hex "$1") || return 1
    _zte_step2=$(zte_sha256_hex "$_zte_step1$2") || return 1
    printf '%s\n' "$_zte_step2" | tr '[:lower:]' '[:upper:]'
}

# $1 host, $2 password, $3 cookie jar. Never logs password, digest or cookie.
zte_session_login() (
    _zte_host=$1
    _zte_ld_response=$(zte_http_get \
        "http://$_zte_host/goform/goform_get_cmd_process?cmd=LD&isTest=false" "$3") || return 1
    _zte_ld=$(zte_json_flat_get "$_zte_ld_response" LD)
    case $_zte_ld in
        ''|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    _zte_digest=$(zte_session_digest "$2" "$_zte_ld") || return 1
    _zte_login_response=$(zte_http_post \
        "http://$_zte_host/goform/goform_set_cmd_process" \
        "goformId=LOGIN&password=$_zte_digest" "$3") || return 1
    [ "$(zte_json_flat_get "$_zte_login_response" result)" = 0 ]
)

# $1 file; prints its numeric owner UID.
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

# $1 credential file containing a "password=..." line.
# Accepts only a regular file owned by the effective process UID, with no
# group/other permission bits. The daemon therefore requires root ownership.
zte_read_password() {
    [ -f "$1" ] || return 1
    [ ! -L "$1" ] || return 1
    [ "$(zte_file_owner_uid "$1")" = "$(zte_effective_uid)" ] || return 1
    [ "$(zte_file_mode "$1")" = 600 ] || return 1
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
}
