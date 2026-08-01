#!/bin/sh

# Escape a string for inclusion inside a JSON double-quoted value.
zte_json_escape() {
    printf '%s' "$1" | LC_ALL=C awk '
        {
            if (NR > 1)
                value = value "\n"
            value = value $0
        }
        END {
            backspace = sprintf("%c", 8)
            formfeed = sprintf("%c", 12)
            for (i = 1; i <= length(value); i++) {
                c = substr(value, i, 1)
                if (c == "\\")
                    printf "\\\\"
                else if (c == "\"")
                    printf "\\\""
                else if (c == backspace)
                    printf "\\b"
                else if (c == formfeed)
                    printf "\\f"
                else if (c == "\n")
                    printf "\\n"
                else if (c == "\r")
                    printf "\\r"
                else if (c == "\t")
                    printf "\\t"
                else
                    printf "%s", c
            }
        }
    '
}

# Parse a flat JSON object once for validation, exact key presence, or value
# extraction. String values are decoded for the standard JSON escapes. Unicode
# escapes are preserved as \uXXXX so they remain intact on minimal awk builds.
_zte_json_flat_query() {
    _zte_json_mode=$1
    _zte_json_input=$2
    _zte_json_wanted=${3-}
    _zte_json_parent=${4-}

    printf '%s' "$_zte_json_input" | LC_ALL=C awk \
        -v mode="$_zte_json_mode" -v wanted="$_zte_json_wanted" \
        -v parent="$_zte_json_parent" '
        function skip_space(    c) {
            while (pos <= length(json)) {
                c = substr(json, pos, 1)
                if (c != " " && c != "\t" && c != "\r" && c != "\n")
                    break
                pos++
            }
        }

        function parse_string(    c, escaped, hex) {
            parsed_string = ""
            if (substr(json, pos, 1) != "\"")
                return 0
            pos++
            while (pos <= length(json)) {
                c = substr(json, pos, 1)
                if (c == "\"") {
                    pos++
                    return 1
                }
                if (c ~ /[[:cntrl:]]/)
                    return 0
                if (c != "\\") {
                    parsed_string = parsed_string c
                    pos++
                    continue
                }

                pos++
                if (pos > length(json))
                    return 0
                escaped = substr(json, pos, 1)
                if (escaped == "u") {
                    hex = substr(json, pos + 1, 4)
                    if (length(hex) != 4 || hex !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/)
                        return 0
                    parsed_string = parsed_string "\\" "u" hex
                    pos += 5
                    continue
                }
                if (escaped == "\"" || escaped == "\\" || escaped == "/")
                    parsed_string = parsed_string escaped
                else if (escaped == "b")
                    parsed_string = parsed_string sprintf("%c", 8)
                else if (escaped == "f")
                    parsed_string = parsed_string sprintf("%c", 12)
                else if (escaped == "n")
                    parsed_string = parsed_string "\n"
                else if (escaped == "r")
                    parsed_string = parsed_string "\r"
                else if (escaped == "t")
                    parsed_string = parsed_string "\t"
                else
                    return 0
                pos++
            }
            return 0
        }

        function parse_number(    rest) {
            rest = substr(json, pos)
            if (!match(rest, /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/))
                return 0
            scalar_value = substr(rest, 1, RLENGTH)
            scalar_kind = "number"
            pos += RLENGTH
            return 1
        }

        function parse_scalar(    c, token) {
            scalar_value = ""
            scalar_kind = ""
            c = substr(json, pos, 1)
            if (c == "\"") {
                if (!parse_string())
                    return 0
                scalar_value = parsed_string
                scalar_kind = "string"
                return 1
            }
            if (c == "-" || c ~ /^[0-9]$/)
                return parse_number()
            token = substr(json, pos)
            if (substr(token, 1, 4) == "true") {
                scalar_value = "true"
                scalar_kind = "boolean"
                pos += 4
                return 1
            }
            if (substr(token, 1, 5) == "false") {
                scalar_value = "false"
                scalar_kind = "boolean"
                pos += 5
                return 1
            }
            if (substr(token, 1, 4) == "null") {
                scalar_kind = "null"
                pos += 4
                return 1
            }
            return 0
        }

        function parse_value(    c) {
            c = substr(json, pos, 1)
            if (c == "{")
                return parse_nested_object()
            if (c == "[")
                return parse_array()
            return parse_scalar()
        }

        function parse_nested_object(    c) {
            if (substr(json, pos, 1) != "{")
                return 0
            pos++
            skip_space()
            if (substr(json, pos, 1) == "}") {
                pos++
                return 1
            }
            while (pos <= length(json)) {
                if (!parse_string())
                    return 0
                skip_space()
                if (substr(json, pos, 1) != ":")
                    return 0
                pos++
                skip_space()
                if (!parse_value())
                    return 0
                skip_space()
                c = substr(json, pos, 1)
                if (c == "}") {
                    pos++
                    return 1
                }
                if (c != ",")
                    return 0
                pos++
                skip_space()
            }
            return 0
        }

        function parse_array(    c) {
            if (substr(json, pos, 1) != "[")
                return 0
            pos++
            skip_space()
            if (substr(json, pos, 1) == "]") {
                pos++
                return 1
            }
            while (pos <= length(json)) {
                if (!parse_value())
                    return 0
                skip_space()
                c = substr(json, pos, 1)
                if (c == "]") {
                    pos++
                    return 1
                }
                if (c != ",")
                    return 0
                pos++
                skip_space()
            }
            return 0
        }

        function parse_object(    c, key) {
            skip_space()
            if (substr(json, pos, 1) != "{")
                return 0
            pos++
            skip_space()
            if (substr(json, pos, 1) == "}") {
                pos++
                skip_space()
                return pos > length(json)
            }
            while (pos <= length(json)) {
                if (!parse_string())
                    return 0
                key = parsed_string
                skip_space()
                if (substr(json, pos, 1) != ":")
                    return 0
                pos++
                skip_space()
                if (!parse_scalar())
                    return 0
                if (key == wanted) {
                    found = 1
                    found_value = scalar_value
                    found_kind = scalar_kind
                }
                skip_space()
                c = substr(json, pos, 1)
                if (c == "}") {
                    pos++
                    skip_space()
                    return pos > length(json)
                }
                if (c != ",")
                    return 0
                pos++
                skip_space()
            }
            return 0
        }

        function parse_path_object(    c, key) {
            if (substr(json, pos, 1) != "{")
                return 0
            pos++
            skip_space()
            if (substr(json, pos, 1) == "}") {
                pos++
                return 1
            }
            while (pos <= length(json)) {
                if (!parse_string())
                    return 0
                key = parsed_string
                skip_space()
                if (substr(json, pos, 1) != ":")
                    return 0
                pos++
                skip_space()
                c = substr(json, pos, 1)
                if (key == wanted && c != "{" && c != "[") {
                    if (!parse_scalar())
                        return 0
                    found = 1
                    found_value = scalar_value
                    found_kind = scalar_kind
                } else if (!parse_value()) {
                    return 0
                }
                skip_space()
                c = substr(json, pos, 1)
                if (c == "}") {
                    pos++
                    return 1
                }
                if (c != ",")
                    return 0
                pos++
                skip_space()
            }
            return 0
        }

        function parse_top_object(    c, key) {
            skip_space()
            if (substr(json, pos, 1) != "{")
                return 0
            pos++
            skip_space()
            if (substr(json, pos, 1) == "}") {
                pos++
                skip_space()
                return pos > length(json)
            }
            while (pos <= length(json)) {
                if (!parse_string())
                    return 0
                key = parsed_string
                skip_space()
                if (substr(json, pos, 1) != ":")
                    return 0
                pos++
                skip_space()
                c = substr(json, pos, 1)
                if (mode == "pathget" && key == parent && c == "{") {
                    if (!parse_path_object())
                        return 0
                } else if (mode == "topget" && key == wanted && c != "{" && c != "[") {
                    if (!parse_scalar())
                        return 0
                    found = 1
                    found_value = scalar_value
                    found_kind = scalar_kind
                } else if (!parse_value()) {
                    return 0
                }
                skip_space()
                c = substr(json, pos, 1)
                if (c == "}") {
                    pos++
                    skip_space()
                    return pos > length(json)
                }
                if (c != ",")
                    return 0
                pos++
                skip_space()
            }
            return 0
        }

        {
            if (NR > 1)
                json = json "\n"
            json = json $0
        }
        END {
            pos = 1
            if (mode == "topget" || mode == "pathget")
                valid = parse_top_object()
            else
                valid = parse_object()
            if (!valid)
                exit 1
            if (mode == "validate")
                exit 0
            if (mode == "has")
                exit(found ? 0 : 1)
            if (mode == "get") {
                if (found && found_kind != "null")
                    printf "%s", found_value
                exit 0
            }
            if (mode == "topget" || mode == "pathget") {
                if (found && found_kind != "null")
                    printf "%s", found_value
                exit 0
            }
            exit 1
        }
    '
}

# Succeed when "$1" is a JSON object whose values are scalar.
zte_json_is_flat_object() {
    _zte_json_flat_query validate "${1-}" ''
}

# Succeed when flat JSON object "$1" contains key "$2".
zte_json_flat_has() {
    case ${2-} in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    _zte_json_flat_query has "$1" "$2"
}

# Print the scalar value of key "$2" from flat JSON object "$1".
# Missing, empty-string, and null values print nothing; use
# zte_json_flat_has when their presence must be distinguished.
zte_json_flat_get() {
    case ${2-} in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    _zte_json_flat_query get "$1" "$2"
}

# Print an exact top-level scalar from a general JSON object. Nested values are
# parsed and skipped, so similarly named descendant keys cannot match.
zte_json_top_get() {
    case ${2-} in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    _zte_json_flat_query topget "$1" "$2"
}

# Print a scalar at exact two-segment object path "$2.$3".
zte_json_path_get() {
    case ${2-} in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    case ${3-} in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    _zte_json_flat_query pathget "$1" "$3" "$2"
}

zte_json_mac_valid() {
    _zte_json_mac=${1-}
    _zte_json_old_ifs=$IFS
    IFS=:
    # Word splitting is intentional: a MAC address must contain six octets.
    # shellcheck disable=SC2086
    set -- $_zte_json_mac
    IFS=$_zte_json_old_ifs
    [ "$#" -eq 6 ] || return 1
    for _zte_json_octet in "$@"; do
        [ "${#_zte_json_octet}" -eq 2 ] || return 1
        case $_zte_json_octet in
            *[!0-9A-Fa-f]*) return 1 ;;
        esac
    done
}

zte_json_optional_bounded_string() {
    _zte_json_bounded_value=${1-}
    _zte_json_bounded_max=${2-}
    case $_zte_json_bounded_max in
        ''|*[!0-9]*) return 1 ;;
    esac
    if [ -z "$_zte_json_bounded_value" ]; then
        printf 'null'
        return
    fi
    [ "${#_zte_json_bounded_value}" -le "$_zte_json_bounded_max" ] ||
        return 1
    printf '"%s"' "$(zte_json_escape "$_zte_json_bounded_value")"
}

# Project the target U25S station_list response into a bounded client object.
# jsonfilter is the native OpenWrt parser; only explicitly listed fields leave
# this function, so unknown device fields cannot leak into the cached snapshot.
zte_json_normalize_station_list() {
    _zte_station_raw=${1-}
    [ "${#_zte_station_raw}" -le 262144 ] || return 1
    command -v jsonfilter >/dev/null 2>&1 || return 1

    _zte_station_list=$(jsonfilter -s "$_zte_station_raw" \
        -e '@.station_list' 2>/dev/null) || return 1
    case $_zte_station_list in
        \[*\]) ;;
        *) return 1 ;;
    esac
    _zte_station_items=$(jsonfilter -s "$_zte_station_raw" \
        -e '@.station_list[*]' 2>/dev/null) || return 1

    _zte_station_output='{"available":true,"items":['
    _zte_station_separator=''
    _zte_station_count=0
    while IFS= read -r _zte_station_item; do
        [ -n "$_zte_station_item" ] || continue
        _zte_station_count=$((_zte_station_count + 1))
        [ "$_zte_station_count" -le 64 ] || return 1

        _zte_station_mac=$(jsonfilter -s "$_zte_station_item" \
            -e '@.mac_addr' 2>/dev/null) || return 1
        zte_json_mac_valid "$_zte_station_mac" || return 1
        _zte_station_hostname=$(jsonfilter -s "$_zte_station_item" \
            -e '@.hostname' 2>/dev/null) || _zte_station_hostname=''
        _zte_station_ip=$(jsonfilter -s "$_zte_station_item" \
            -e '@.ip_addr' 2>/dev/null) || _zte_station_ip=''
        _zte_station_ssid=$(jsonfilter -s "$_zte_station_item" \
            -e '@.ssid_index' 2>/dev/null) || _zte_station_ssid=''
        _zte_station_interface=$(jsonfilter -s "$_zte_station_item" \
            -e '@.interfacetype' 2>/dev/null) || _zte_station_interface=''
        _zte_station_upload=$(jsonfilter -s "$_zte_station_item" \
            -e '@.ULSpeed' 2>/dev/null) || _zte_station_upload=''
        _zte_station_download=$(jsonfilter -s "$_zte_station_item" \
            -e '@.DLSpeed' 2>/dev/null) || _zte_station_download=''

        _zte_station_hostname_json=$(zte_json_optional_bounded_string \
            "$_zte_station_hostname" 253) || return 1
        _zte_station_ip_json=$(zte_json_optional_bounded_string \
            "$_zte_station_ip" 64) || return 1
        _zte_station_ssid_json=$(zte_json_optional_bounded_string \
            "$_zte_station_ssid" 32) || return 1
        _zte_station_interface_json=$(zte_json_optional_bounded_string \
            "$_zte_station_interface" 32) || return 1
        _zte_station_upload_json=$(zte_json_optional_bounded_string \
            "$_zte_station_upload" 32) || return 1
        _zte_station_download_json=$(zte_json_optional_bounded_string \
            "$_zte_station_download" 32) || return 1

        _zte_station_output=$_zte_station_output$_zte_station_separator'{"mac":"'$(
            zte_json_escape "$_zte_station_mac"
        )'","hostname":'$_zte_station_hostname_json',"ip":'$_zte_station_ip_json',"ssid_index":'$_zte_station_ssid_json',"interface":'$_zte_station_interface_json',"upload_rate_raw":'$_zte_station_upload_json',"download_rate_raw":'$_zte_station_download_json'}'
        _zte_station_separator=,
    done <<EOF
$_zte_station_items
EOF
    printf '%s]}\n' "$_zte_station_output"
}
