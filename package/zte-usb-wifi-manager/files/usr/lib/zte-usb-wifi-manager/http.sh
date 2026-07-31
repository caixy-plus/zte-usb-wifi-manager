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
	_zte_http_url=$1
	_zte_http_jar=$2
	set -- -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
		-b "$_zte_http_jar" -c "$_zte_http_jar" \
		-H "Referer: $(zte_http_referer "$_zte_http_url")" \
		-H 'X-Requested-With: XMLHttpRequest'
	if [ -n "${ZTE_HTTP_INTERFACE:-}" ]; then
		set -- "$@" --interface "$ZTE_HTTP_INTERFACE"
	fi
	if curl "$@" "$_zte_http_url"; then
        _zte_http_status=0
	else
		_zte_http_status=$?
	fi
	zte_http_secure_cookie_jar "$_zte_http_jar" || return 1
    return "$_zte_http_status"
}

# $1 url, $2 form body, $3 cookie jar; prints response body
zte_http_post() {
	_zte_http_url=$1
	_zte_http_body=$2
	_zte_http_jar=$3
	set -- -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
		-b "$_zte_http_jar" -c "$_zte_http_jar" \
		-H "Referer: $(zte_http_referer "$_zte_http_url")" \
		-H 'X-Requested-With: XMLHttpRequest' \
		-H 'Content-Type: application/x-www-form-urlencoded' \
		--data-binary @-
	if [ -n "${ZTE_HTTP_INTERFACE:-}" ]; then
		set -- "$@" --interface "$ZTE_HTTP_INTERFACE"
	fi
	if printf '%s' "$_zte_http_body" | curl "$@" "$_zte_http_url"; then
        _zte_http_status=0
	else
		_zte_http_status=$?
	fi
	_zte_http_body=''
	zte_http_secure_cookie_jar "$_zte_http_jar" || return 1
    return "$_zte_http_status"
}
