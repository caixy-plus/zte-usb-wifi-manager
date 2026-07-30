#!/bin/sh

ZTE_HTTP_TIMEOUT=${ZTE_HTTP_TIMEOUT:-5}

# Derive "http://host/" from a full URL for the Referer header.
zte_http_referer() {
    printf '%s/\n' "$(printf '%s' "$1" | sed 's|^\(http://[^/]*\).*$|\1|')"
}

zte_http_secure_cookie_jar() {
    [ ! -e "$1" ] || chmod 600 "$1"
}

# $1 url, $2 cookie jar; prints response body
zte_http_get() {
    if curl -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
        -b "$2" -c "$2" \
        -H "Referer: $(zte_http_referer "$1")" \
        -H 'X-Requested-With: XMLHttpRequest' \
        "$1"; then
        _zte_http_status=0
    else
        _zte_http_status=$?
    fi
    zte_http_secure_cookie_jar "$2" || return 1
    return "$_zte_http_status"
}

# $1 url, $2 form body, $3 cookie jar; prints response body
zte_http_post() {
    if printf '%s' "$2" | curl -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
        -b "$3" -c "$3" \
        -H "Referer: $(zte_http_referer "$1")" \
        -H 'X-Requested-With: XMLHttpRequest' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-binary @- \
        "$1"; then
        _zte_http_status=0
    else
        _zte_http_status=$?
    fi
    zte_http_secure_cookie_jar "$3" || return 1
    return "$_zte_http_status"
}
