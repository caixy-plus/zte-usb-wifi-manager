#!/bin/sh

ZTE_HTTP_TIMEOUT=${ZTE_HTTP_TIMEOUT:-5}

# Percent-encode one UTF-8 form value without exposing it in process argv.
# Byte-wise C locale handling keeps multibyte text deterministic.
zte_form_encode() (
	LC_ALL=C
	export LC_ALL
	_zte_form_input=${1-}
	while [ -n "$_zte_form_input" ]; do
		_zte_form_rest=${_zte_form_input#?}
		_zte_form_char=${_zte_form_input%"$_zte_form_rest"}
		_zte_form_input=$_zte_form_rest
		case $_zte_form_char in
			[A-Za-z0-9.~_-]) printf '%s' "$_zte_form_char" ;;
			*)
				_zte_form_byte=$(printf '%d' "'$_zte_form_char") || return 1
				_zte_form_byte=$(((_zte_form_byte + 256) % 256))
				printf '%%%02X' "$_zte_form_byte"
				;;
		esac
	done
)

zte_form_pair() {
	_zte_form_key=${1-}
	case $_zte_form_key in
		''|*[!A-Za-z0-9_~-]*) return 1 ;;
	esac
	printf '%s=' "$_zte_form_key"
	zte_form_encode "${2-}"
}

zte_http_origin_valid() {
	case ${1-} in
		http://*|https://*) ;;
		*) return 1 ;;
	esac
	_zte_http_authority=${1#*://}
	case $_zte_http_authority in
		''|*/*|*\?*|*\#*|*@*|*[!A-Za-z0-9.:-]*) return 1 ;;
		:*|*:|*::* ) return 1 ;;
	esac
}

# Derive "scheme://host/" from a full URL for the Referer header.
zte_http_referer() {
	case ${1-} in
		http://*) _zte_http_scheme=http ;;
		https://*) _zte_http_scheme=https ;;
		*) return 1 ;;
	esac
	_zte_http_rest=${1#*://}
	_zte_http_authority=${_zte_http_rest%%/*}
	_zte_http_origin=$_zte_http_scheme://$_zte_http_authority
	zte_http_origin_valid "$_zte_http_origin" || return 1
	printf '%s/\n' "$_zte_http_origin"
}

zte_http_secure_cookie_jar() {
    [ ! -e "$1" ] || chmod 600 "$1"
}

# $1 url, $2 cookie jar; prints response body
zte_http_get() {
	_zte_http_url=$1
	_zte_http_jar=$2
	_zte_http_referer=$(zte_http_referer "$_zte_http_url") || return 1
	set -- -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
		-b "$_zte_http_jar" -c "$_zte_http_jar" \
		-H "Referer: $_zte_http_referer" \
		-H 'X-Requested-With: XMLHttpRequest'
	if [ "${ZTE_DEVICE_TLS_INSECURE:-0}" = 1 ]; then
		set -- "$@" --insecure
	fi
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
	_zte_http_referer=$(zte_http_referer "$_zte_http_url") || return 1
	set -- -fsS --max-time "$ZTE_HTTP_TIMEOUT" \
		-b "$_zte_http_jar" -c "$_zte_http_jar" \
		-H "Referer: $_zte_http_referer" \
		-H 'X-Requested-With: XMLHttpRequest' \
		-H 'Content-Type: application/x-www-form-urlencoded' \
		--data-binary @-
	if [ "${ZTE_DEVICE_TLS_INSECURE:-0}" = 1 ]; then
		set -- "$@" --insecure
	fi
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

# POST one device action while retaining enough HTTP status information to
# distinguish a definite client rejection from an outcome that may have been
# applied. Prints only a successful 2xx body. Stable return codes:
# 10 = transport/5xx/invalid status ambiguity, 11 = definite HTTP 4xx reject,
# 12 = request could not be prepared locally.
zte_http_post_classified() (
	umask 077
	_zte_classified_url=$1
	_zte_classified_body=$2
	_zte_classified_jar=$3
	_zte_classified_referer=$(zte_http_referer \
		"$_zte_classified_url") || return 12
	zte_http_secure_cookie_jar "$_zte_classified_jar" || return 12
	_zte_classified_response=$(mktemp \
		"$_zte_classified_jar.response.XXXXXX") || return 12
	trap 'rm -f "$_zte_classified_response"' EXIT HUP INT TERM
	set -- -sS --max-time "$ZTE_HTTP_TIMEOUT" \
		-b "$_zte_classified_jar" -c "$_zte_classified_jar" \
		-H "Referer: $_zte_classified_referer" \
		-H 'X-Requested-With: XMLHttpRequest' \
		-H 'Content-Type: application/x-www-form-urlencoded' \
		--data-binary @- -o "$_zte_classified_response" \
		--write-out '%{http_code}'
	if [ "${ZTE_DEVICE_TLS_INSECURE:-0}" = 1 ]; then
		set -- "$@" --insecure
	fi
	if [ -n "${ZTE_HTTP_INTERFACE:-}" ]; then
		set -- "$@" --interface "$ZTE_HTTP_INTERFACE"
	fi
	if _zte_classified_code=$(printf '%s' "$_zte_classified_body" | \
		curl "$@" "$_zte_classified_url"); then
		_zte_classified_curl_ok=1
	else
		_zte_classified_curl_ok=0
	fi
	_zte_classified_body=''
	_zte_classified_cookie_ok=1
	zte_http_secure_cookie_jar "$_zte_classified_jar" ||
		_zte_classified_cookie_ok=0
	[ "$_zte_classified_curl_ok" = 1 ] || return 10
	case $_zte_classified_code in
		2[0-9][0-9])
			[ "$_zte_classified_cookie_ok" = 1 ] || return 10
			cat "$_zte_classified_response"
			;;
		4[0-9][0-9]) return 11 ;;
		*) return 10 ;;
	esac
)
