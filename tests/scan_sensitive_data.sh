#!/bin/sh
set -eu

allowlist=tests/sensitive-data.allowlist
findings=$(mktemp "${TMPDIR:-/tmp}/zte-sensitive-findings.XXXXXX")
trap 'rm -f "$findings"' EXIT HUP INT TERM

git ls-files | while IFS= read -r file; do
    [ -f "$file" ] || continue
    LC_ALL=C git grep -I -q -e . -- "$file" 2>/dev/null || continue

    awk -v path="$file" -v allowlist="$allowlist" -v findings="$findings" '
        BEGIN {
            while ((getline entry < allowlist) > 0) {
                allowed[entry] = 1
            }
            close(allowlist)
        }
        function report(type, key) {
            key = path ":" FNR ":" type
            if (!(key in allowed)) {
                print path ":" FNR " " type >> findings
            }
        }
        function is_placeholder(text, upper) {
            upper = toupper(text)
            return text ~ /<[A-Za-z0-9_ -]+>/ ||
                text ~ /\$\{[A-Za-z0-9_]+\}/ ||
                upper ~ /(^|[^A-Z])(REDACTED|PLACEHOLDER|CHANGEME|DUMMY|NOT[_ -]?SET)([^A-Z]|$)/ ||
                upper ~ /YOUR_[A-Z0-9_]+/
        }
        {
            line = $0
            lower = tolower(line)

            if (line ~ /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/) {
                report("PRIVATE_KEY")
            }
            if (lower ~ /authorization[[:space:]]*[:=][[:space:]]*(basic|bearer)[[:space:]]+[^[:space:]]+/ &&
                !is_placeholder(line)) {
                report("AUTHORIZATION")
            }
            if (lower ~ /(^|[^a-z-])(cookie|set-cookie)[[:space:]]*[:=][[:space:]]*[^[:space:]]+/ &&
                !is_placeholder(line)) {
                report("HTTP_COOKIE")
            }
            if (line ~ /(ghp_|github_pat_|glpat-|xox[baprs]-|sk-|AKIA)[A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-]/ &&
                !is_placeholder(line)) {
                report("HIGH_RISK_TOKEN")
            }
            if (line ~ /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\/:@[:space:]]+:[^\/@[:space:]]+@/ &&
                !is_placeholder(line)) {
                report("URL_CREDENTIALS")
            }
            if (line !~ /^[[:space:]]*#/ &&
                (lower ~ /(^|[^a-z0-9_])(password|passwd|secret|token|api_key|apikey|access_key)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']+["'\'']/ ||
                 lower ~ /(^|[^a-z0-9_])(password|passwd|secret|token|api_key|apikey|access_key)[[:space:]]*[:=][[:space:]]*[a-z0-9][a-z0-9._-]*([[:space:]#;,}]|$)/) &&
                !is_placeholder(line)) {
                report("SECRET_ASSIGNMENT")
            }
            if (line ~ /(^|[^0-9])1[3-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]([^0-9]|$)/) {
                report("PHONE_NUMBER")
            }
            if (line ~ /(^|[^0-9])[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]([^0-9]|$)/) {
                report("15_DIGIT_IDENTIFIER")
            }
            if (line ~ /(^|[^0-9])[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]([0-9])?([^0-9]|$)/) {
                report("ICCID")
            }
            if (line !~ /^[[:space:]]*#/ &&
                (lower ~ /(^|[^a-z0-9])(imei|imsi|iccid|msisdn|phone_number|device_id)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']+["'\'']/ ||
                 lower ~ /(^|[^a-z0-9])(imei|imsi|iccid|msisdn|phone_number|device_id)[[:space:]]*[:=][[:space:]]*[a-z0-9][a-z0-9._-]*([[:space:]#;,}]|$)/) &&
                !is_placeholder(line)) {
                report("SENSITIVE_FIELD")
            }
        }
    ' "$file"
done

if [ -s "$findings" ]; then
    LC_ALL=C sort -u "$findings"
    exit 1
fi
