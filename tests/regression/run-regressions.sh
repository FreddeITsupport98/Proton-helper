#!/usr/bin/env sh

set -u

REG_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
FAIL_COUNT=0
FAIL_LIST=""

add_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_LIST="${FAIL_LIST}\n- $1"
}

find "$REG_DIR" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true

if ! "$REG_DIR/syntax-master.sh"; then
    add_fail "syntax-master.sh"
fi

if ! "$REG_DIR/test-setupPVPN.sh"; then
    add_fail "test-setupPVPN.sh"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    printf 'FAIL SUMMARY (%s)\n' "$FAIL_COUNT"
    printf '%b\n' "$FAIL_LIST"
    exit 1
fi

printf '[regression] PASS: all regression checks completed.\n'
exit 0
