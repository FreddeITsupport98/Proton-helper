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

run_expect_failure() {
    case_title="$1"
    expected_message="$2"
    shift 2
    output="$(sh "$TARGET" "$@" 2>&1)"
    status=$?
    if [ "$status" -eq 0 ]; then
        add_fail "$case_title unexpectedly succeeded"
        return 1
    fi
    if ! printf '%s\n' "$output" | grep -Fq -- "$expected_message"; then
        add_fail "$case_title missing expected error message"
        return 1
    fi
    return 0
}

if [ ! -f "$TARGET" ]; then
    add_fail "setupPVPN.sh not found at $TARGET"
else
    run_expect_failure "systemd-health-retries zero" "Invalid --systemd-health-retries value: 0 (expected integer >= 1)." --non-interactive install --dry-run --systemd-health-retries 0 || true
    run_expect_failure "systemd-health-retries non-numeric" "Invalid --systemd-health-retries value: abc (expected integer >= 1)." --non-interactive install --dry-run --systemd-health-retries abc || true
    run_expect_failure "systemd-health-delay non-numeric" "Invalid --systemd-health-delay value: abc (expected integer >= 0)." --non-interactive install --dry-run --systemd-health-delay abc || true
    run_expect_failure "systemd-health-backoff invalid value" "Invalid --systemd-health-backoff value: weird (expected fixed|exponential)." --non-interactive install --dry-run --systemd-health-backoff weird || true
    run_expect_failure "systemd-health-jitter invalid value" "Invalid --systemd-health-jitter value: abc (expected integer >= 0)." --non-interactive install --dry-run --systemd-health-jitter abc || true
    run_expect_failure "systemd-fallback-mode invalid value" "Invalid --systemd-fallback-mode value: invalid (expected auto|xdg-only|systemd-only)." --non-interactive install --dry-run --systemd-fallback-mode invalid || true
    run_expect_failure "systemd-unit-hardening invalid value" "Invalid --systemd-unit-hardening value: strict (expected off|basic)." --non-interactive install --dry-run --systemd-unit-hardening strict || true
    run_expect_failure "systemd-fallback-mode missing value" "Missing value for --systemd-fallback-mode. Use auto|xdg-only|systemd-only." --non-interactive install --dry-run --systemd-fallback-mode || true
    run_expect_failure "systemd-health-backoff missing value" "Missing value for --systemd-health-backoff. Use fixed|exponential." --non-interactive install --dry-run --systemd-health-backoff || true
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    printf 'FAIL SUMMARY (%s)\n' "$FAIL_COUNT"
    printf '%b\n' "$FAIL_LIST"
    exit 1
fi

printf '[regression] PASS: CLI parser error handling validated for startup policy arguments.\n'
exit 0
