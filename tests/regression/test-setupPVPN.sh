#!/usr/bin/env sh

set -u

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
TARGET="$ROOT_DIR/setupPVPN.sh"
FAIL_COUNT=0
FAIL_LIST=""

add_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_LIST="${FAIL_LIST}\n- $1"
}

assert_contains() {
    needle="$1"
    label="$2"
    if ! grep -Fq -- "$needle" "$TARGET"; then
        add_fail "$label"
    fi
}

if [ ! -f "$TARGET" ]; then
    add_fail "setupPVPN.sh not found at $TARGET"
else
    sh -n "$TARGET" || add_fail "setupPVPN.sh fails sh -n"
    assert_contains '"repair" "Repair ProtonVPN setup files and startup hooks"' "repair menu item missing"
    assert_contains 'run_repair_flow()' "run_repair_flow function missing"
    assert_contains 'run_uninstall_flow()' "run_uninstall_flow function missing"
    assert_contains "case \"\$ACTION\" in" "action case block missing"
    assert_contains 'repair)' "repair case option missing"
    assert_contains 'remove_startup_files' "startup cleanup function usage missing"
    assert_contains 'ensure_self_executable' "self auto-chmod invocation missing"
    assert_contains 'show_action_menu' "menu invocation missing"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    printf 'FAIL SUMMARY (%s)\n' "$FAIL_COUNT"
    printf '%b\n' "$FAIL_LIST"
    exit 1
fi

printf '[regression] PASS: setupPVPN.sh menu/flow guards validated.\n'
exit 0
