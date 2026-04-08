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
    sh -n "$TARGET" || add_fail "setupPVPN.sh fails sh -n during lockfile regression"
    assert_contains "LOCK_FILE=\"\\\$HOME/.local/state/proton-helper-autoconnect.lock\"" "wrapper lockfile variable assignment missing"
    assert_contains "LOCK_DIR=\"\\\$HOME/.local/state\"" "wrapper lock directory variable assignment missing"
    assert_contains "mkdir -p \"\\\$LOCK_DIR\" >/dev/null 2>&1 || true" "wrapper lock directory creation missing"
    assert_contains "if [ -f \"\\\$LOCK_FILE\" ]; then" "wrapper lockfile existence check missing"
    assert_contains "lock_pid=\"\$(cat \"\\\$LOCK_FILE\" 2>/dev/null || true)\"" "wrapper lockfile PID read missing"
    assert_contains "kill -0 \"\\\$lock_pid\" >/dev/null 2>&1" "wrapper lock PID liveness check missing"
    assert_contains "Another ProtonVPN autoconnect instance is already running (pid=%s)." "wrapper duplicate-run lock message missing"
    assert_contains "> \"\\\$LOCK_FILE\" 2>/dev/null || true" "wrapper lockfile write missing"
    assert_contains "cleanup_lock() {" "wrapper lock cleanup function missing"
    assert_contains "rm -f \"\\\$LOCK_FILE\"" "wrapper lock cleanup remove missing"
    assert_contains "trap cleanup_lock EXIT INT TERM" "wrapper lock cleanup trap missing"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    printf 'FAIL SUMMARY (%s)\n' "$FAIL_COUNT"
    printf '%b\n' "$FAIL_LIST"
    exit 1
fi

printf '[regression] PASS: wrapper lockfile guard assertions validated.\n'
exit 0
