#!/usr/bin/env sh

set -u

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
TARGET="$ROOT_DIR/setupPVPN.sh"
FAIL_COUNT=0
FAIL_LIST=""
TMP_DIR="$(mktemp -d)"
MOCK_BIN="$TMP_DIR/mock-bin"
MOCK_HOME="$TMP_DIR/home"
ORIG_PATH="$PATH"

add_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_LIST="${FAIL_LIST}\n- $1"
}

assert_output_contains() {
    output_text="$1"
    needle="$2"
    label="$3"
    if ! printf '%s\n' "$output_text" | grep -Fq -- "$needle"; then
        add_fail "$label"
    fi
}

assert_output_not_contains() {
    output_text="$1"
    needle="$2"
    label="$3"
    if printf '%s\n' "$output_text" | grep -Fq -- "$needle"; then
        add_fail "$label"
    fi
}

if [ ! -f "$TARGET" ]; then
    add_fail "setupPVPN.sh not found at $TARGET"
fi

mkdir -p "$MOCK_BIN" "$MOCK_HOME"

cat > "$MOCK_BIN/systemctl" << 'EOF'
#!/usr/bin/env sh

set -u

scenario="${MOCK_SYSTEMD_SCENARIO:-healthy}"

if [ "$#" -gt 0 ] && [ "$1" = "--user" ]; then
    shift
fi
if [ "$#" -gt 0 ] && [ "$1" = "--quiet" ]; then
    shift
fi

cmd="${1:-}"
if [ "$#" -gt 0 ]; then
    shift
fi

case "$cmd" in
    show-environment)
        exit 0
        ;;
    daemon-reload)
        exit 0
        ;;
    enable)
        exit 0
        ;;
    start)
        if [ "$scenario" = "start-fail" ]; then
            exit 1
        fi
        exit 0
        ;;
    disable)
        exit 0
        ;;
    is-enabled)
        if [ -f "$HOME/.config/systemd/user/protonvpn-autoconnect.service" ]; then
            exit 0
        fi
        exit 1
        ;;
    is-active)
        if [ "$scenario" = "healthy" ]; then
            exit 0
        fi
        exit 1
        ;;
    is-failed)
        if [ "$scenario" = "failed-state" ]; then
            exit 0
        fi
        exit 1
        ;;
    show)
        property_name=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --property=*)
                    property_name="${1#--property=}"
                    ;;
                --property)
                    shift
                    property_name="${1:-}"
                    ;;
            esac
            shift
        done
        case "$property_name" in
            ActiveState)
                case "$scenario" in
                    healthy) printf 'active\n' ;;
                    failed-state) printf 'failed\n' ;;
                    *) printf 'inactive\n' ;;
                esac
                ;;
            SubState)
                case "$scenario" in
                    healthy) printf 'exited\n' ;;
                    failed-state) printf 'failed\n' ;;
                    *) printf 'dead\n' ;;
                esac
                ;;
            Result)
                case "$scenario" in
                    healthy) printf 'success\n' ;;
                    *) printf 'exit-code\n' ;;
                esac
                ;;
        esac
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF

cat > "$MOCK_BIN/protonvpn" << 'EOF'
#!/usr/bin/env sh

set -u

cmd="${1:-}"
case "$cmd" in
    account)
        printf 'Username: mocked-user\n'
        exit 0
        ;;
    info|status)
        printf 'Status: Disconnected\n'
        exit 0
        ;;
    config)
        printf 'Kill switch: off\n'
        exit 0
        ;;
    connect|disconnect)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF

chmod +x "$MOCK_BIN/systemctl" "$MOCK_BIN/protonvpn"

run_case() {
    scenario_name="$1"
    case_title="$2"
    expected_primary="$3"

    case_output="$(
        PATH="$MOCK_BIN:$ORIG_PATH" \
        HOME="$MOCK_HOME" \
        MOCK_SYSTEMD_SCENARIO="$scenario_name" \
        sh "$TARGET" --non-interactive install --systemd-health-retries 1 --systemd-health-delay 0 2>&1
    )"
    case_status=$?

    if [ "$case_status" -ne 0 ]; then
        add_fail "$case_title returned non-zero exit status ($case_status)"
    fi

    assert_output_contains "$case_output" "$expected_primary" "$case_title missing expected primary signal"
    assert_output_contains "$case_output" "systemd --user startup setup failed or unhealthy; used XDG autostart fallback." "$case_title missing fallback warning"
    assert_output_contains "$case_output" "Desktop autostart entry:" "$case_title missing desktop fallback entry output"
}

if [ -f "$TARGET" ]; then
    run_case "start-fail" "start-fail case" "systemd --user start failed for protonvpn-autoconnect.service."
    run_case "failed-state" "failed-state case" "systemd --user unit protonvpn-autoconnect.service is in failed state."
    run_case "inactive-unhealthy" "inactive-unhealthy case" "systemd --user unit protonvpn-autoconnect.service remained unhealthy after 1 checks"

    healthy_output="$(
        PATH="$MOCK_BIN:$ORIG_PATH" \
        HOME="$MOCK_HOME" \
        MOCK_SYSTEMD_SCENARIO="healthy" \
        sh "$TARGET" --non-interactive install --systemd-health-retries 1 --systemd-health-delay 0 2>&1
    )"
    healthy_status=$?
    if [ "$healthy_status" -ne 0 ]; then
        add_fail "healthy case returned non-zero exit status ($healthy_status)"
    fi
    assert_output_contains "$healthy_output" "Configured user systemd autostart." "healthy case missing successful systemd setup message"
    assert_output_not_contains "$healthy_output" "systemd --user startup setup failed or unhealthy; used XDG autostart fallback." "healthy case should not trigger XDG fallback warning"

    systemd_only_output="$(
        PATH="$MOCK_BIN:$ORIG_PATH" \
        HOME="$MOCK_HOME" \
        MOCK_SYSTEMD_SCENARIO="start-fail" \
        sh "$TARGET" --non-interactive install --systemd-health-retries 1 --systemd-health-delay 0 --systemd-fallback-mode systemd-only 2>&1
    )"
    systemd_only_status=$?
    if [ "$systemd_only_status" -eq 0 ]; then
        add_fail "systemd-only mode should fail when systemd start fails"
    fi
    assert_output_contains "$systemd_only_output" "systemd-only mode is enabled and systemd startup failed; aborting without XDG fallback." "systemd-only mode missing hard-stop message"
    assert_output_not_contains "$systemd_only_output" "Desktop autostart entry:" "systemd-only mode should not configure XDG fallback"

    xdg_only_output="$(
        PATH="$MOCK_BIN:$ORIG_PATH" \
        HOME="$MOCK_HOME" \
        MOCK_SYSTEMD_SCENARIO="start-fail" \
        sh "$TARGET" --non-interactive install --systemd-fallback-mode xdg-only 2>&1
    )"
    xdg_only_status=$?
    if [ "$xdg_only_status" -ne 0 ]; then
        add_fail "xdg-only mode should succeed while bypassing systemd"
    fi
    assert_output_contains "$xdg_only_output" "Configured XDG autostart (systemd fallback mode: xdg-only)." "xdg-only mode missing explicit XDG configuration message"
    assert_output_not_contains "$xdg_only_output" "Configured user systemd autostart." "xdg-only mode should not report systemd setup"
fi

rm -rf "$TMP_DIR"

if [ "$FAIL_COUNT" -gt 0 ]; then
    printf 'FAIL SUMMARY (%s)\n' "$FAIL_COUNT"
    printf '%b\n' "$FAIL_LIST"
    exit 1
fi

printf '[regression] PASS: systemd health-check fallback behavior validated with mocked systemctl states.\n'
exit 0
