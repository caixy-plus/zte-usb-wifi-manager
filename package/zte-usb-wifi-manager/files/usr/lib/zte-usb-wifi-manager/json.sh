#!/bin/sh

# Escape a string for inclusion inside a JSON double-quoted value.
zte_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Succeed when "$1" is a JSON object whose values are scalar.
zte_json_is_flat_object() {
    printf '%s' "${1-}" | LC_ALL=C awk '
        function skip_space(    c) {
            while (pos <= length(json)) {
                c = substr(json, pos, 1)
                if (c != " " && c != "\t" && c != "\r" && c != "\n")
                    break
                pos++
            }
        }

        function parse_string(    c, escaped, hex) {
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
                if (c == "\\") {
                    pos++
                    if (pos > length(json))
                        return 0
                    escaped = substr(json, pos, 1)
                    if (escaped == "u") {
                        hex = substr(json, pos + 1, 4)
                        if (length(hex) != 4 || hex !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/)
                            return 0
                        pos += 5
                        continue
                    }
                    if (escaped !~ /^["\\\/bfnrt]$/)
                        return 0
                }
                pos++
            }
            return 0
        }

        function parse_number(    rest) {
            rest = substr(json, pos)
            if (!match(rest, /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/))
                return 0
            pos += RLENGTH
            return 1
        }

        function parse_scalar(    c, token) {
            c = substr(json, pos, 1)
            if (c == "\"")
                return parse_string()
            if (c == "-" || c ~ /^[0-9]$/)
                return parse_number()
            token = substr(json, pos)
            if (substr(token, 1, 4) == "true" || substr(token, 1, 4) == "null") {
                pos += 4
                return 1
            }
            if (substr(token, 1, 5) == "false") {
                pos += 5
                return 1
            }
            return 0
        }

        function parse_object(    c) {
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
                skip_space()
                if (substr(json, pos, 1) != ":")
                    return 0
                pos++
                skip_space()
                if (!parse_scalar())
                    return 0
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
            exit(parse_object() ? 0 : 1)
        }
    '
}

# Succeed when flat JSON object "$1" contains key "$2".
zte_json_flat_has() {
    case $2 in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    printf '%s' "$1" | sed -n \
        's/.*"'"$2"'"[[:space:]]*:.*/found/p' | grep -q found
}

# Print the value of key "$2" from flat JSON object "$1".
# Handles "key":"value", "key":123, "key":-12.5, "key":true/false.
# Prints nothing when the key is absent. String values must not
# contain double quotes (goform read fields never do).
zte_json_flat_get() {
    case $2 in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    printf '%s' "$1" | sed -n \
        -e 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        -e 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\(-[0-9][0-9.]*\)[[:space:]]*[,}].*/\1/p' \
        -e 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\)[[:space:]]*[,}].*/\1/p' \
        -e 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*true[[:space:]]*[,}].*/true/p' \
        -e 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*false[[:space:]]*[,}].*/false/p'
}
