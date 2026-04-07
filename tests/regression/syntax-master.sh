#!/usr/bin/env sh

set -u

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
TMP_LIST="$(mktemp)"
FAIL_COUNT=0
FAIL_LIST=""

add_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_LIST="${FAIL_LIST}\n- $1"
}

printf '[syntax-master] Scanning shell scripts in: %s\n' "$ROOT_DIR"

find "$ROOT_DIR" -type f -name '*.sh' > "$TMP_LIST"

if [ ! -s "$TMP_LIST" ]; then
    add_fail "No shell scripts found to validate"
fi

while IFS= read -r script_file; do
    if [ ! -f "$script_file" ]; then
        add_fail "Missing script during scan: $script_file"
        continue
    fi

    chmod +x "$script_file" 2>/dev/null || add_fail "Auto-chmod failed: $script_file"
    sh -n "$script_file" || add_fail "sh -n failed: $script_file"

    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "$script_file" || add_fail "shellcheck failed: $script_file"
    else
        printf '[syntax-master] WARN: shellcheck not installed, skipping lint for %s\n' "$script_file"
    fi
done < "$TMP_LIST"

rm -f "$TMP_LIST"

if [ "$FAIL_COUNT" -gt 0 ]; then
    printf 'FAIL SUMMARY (%s)\n' "$FAIL_COUNT"
    printf '%b\n' "$FAIL_LIST"
    exit 1
fi

printf '[syntax-master] PASS: syntax and shell lint checks succeeded.\n'
exit 0
