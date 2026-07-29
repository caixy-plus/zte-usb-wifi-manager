#!/bin/sh

# Print the lowercase hex SHA-256 of "$1" using whatever tool exists.
zte_sha256_hex() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    else
        printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}'
    fi
}

# $1 password, $2 LD challenge -> uppercase double-SHA-256 login digest.
zte_session_digest() {
    step1=$(zte_sha256_hex "$1")
    zte_sha256_hex "$step1$2" | tr '[:lower:]' '[:upper:]'
}

# $1 host, $2 password, $3 cookie jar. Never logs password, digest or cookie.
zte_session_login() {
    host=$1
    ld_response=$(zte_http_get \
        "http://$host/goform/goform_get_cmd_process?cmd=LD&isTest=false" "$3") || return 1
    ld=$(zte_json_flat_get "$ld_response" LD)
    case $ld in
        ''|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    digest=$(zte_session_digest "$2" "$ld")
    login_response=$(zte_http_post \
        "http://$host/goform/goform_set_cmd_process" \
        "goformId=LOGIN&password=$digest" "$3") || return 1
    [ "$(zte_json_flat_get "$login_response" result)" = 0 ]
}

# $1 credential file (root-only 0600, containing a "password=..." line)
zte_read_password() {
    [ -f "$1" ] || return 1
    sed -n 's/^password=//p' "$1" | head -n 1
}
