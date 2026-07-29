#!/bin/sh

# Escape a string for inclusion inside a JSON double-quoted value.
zte_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Succeed when "$1" looks like a flat JSON object.
zte_json_is_flat_object() {
    case ${1-} in
        '{'*'}') return 0 ;;
        *) return 1 ;;
    esac
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
        -e 's/.*"'"$2"'":"\([^"]*\)".*/\1/p' \
        -e 's/.*"'"$2"'":\(-[0-9][0-9.]*\)[,}].*/\1/p' \
        -e 's/.*"'"$2"'":\([0-9][0-9.]*\)[,}].*/\1/p' \
        -e 's/.*"'"$2"'":true[,}].*/true/p' \
        -e 's/.*"'"$2"'":false[,}].*/false/p'
}
