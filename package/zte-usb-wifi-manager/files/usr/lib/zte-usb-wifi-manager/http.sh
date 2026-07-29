#!/bin/sh

ZTE_HTTP_TIMEOUT=${ZTE_HTTP_TIMEOUT:-5}

# Derive "http://host/" from a full URL for the Referer header.
zte_http_referer() {
    printf '%s/\n' "$(printf '%s' "$1" | sed 's|^\(http://[^/]*\).*$|\1|')"
}

# $1 url, $2 cookie jar; prints response body
zte_http_get() {
    curl -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
        -b "$2" -c "$2" \
        -H "Referer: $(zte_http_referer "$1")" \
        -H 'X-Requested-With: XMLHttpRequest' \
        "$1"
}

# $1 url, $2 form body, $3 cookie jar; prints response body
zte_http_post() {
    curl -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
        -b "$3" -c "$3" \
        -H "Referer: $(zte_http_referer "$1")" \
        -H 'X-Requested-With: XMLHttpRequest' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data "$2" \
        "$1"
}
