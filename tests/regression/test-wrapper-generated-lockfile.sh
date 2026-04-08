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
WRAPPER_FILE=""
INSTALL_OUTPUT=""

add_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_LIST="${FAIL_LIST}\n- $1"
}

assert_file_contains() {
    target_file="$1"
    needle="$2"
    label="$3"
    if ! grep -Fq -- "$needle" "$target_file"; then
        add_fail "$label"
    fi
}
debug_dump_on_fail() {
    case "${WRAPPER_FIXTURE_DEBUG:-0}" in
        1|true|TRUE|yes|YES)
            ;;
        *)
            return 0
            ;;
    esac

    printf '[debug] wrapper fixture debug enabled (WRAPPER_FIXTURE_DEBUG=%s)\n' "${WRAPPER_FIXTURE_DEBUG:-0}"
    if [ -n "$WRAPPER_FILE" ] && [ -f "$WRAPPER_FILE" ]; then
        printf '%s\n' '[debug] --- generated wrapper begin ---'
        cat "$WRAPPER_FILE"
        printf '%s\n' '[debug] --- generated wrapper end ---'
    else
        printf '%s\n' '[debug] generated wrapper file not available.'
    fi

    if [ -n "$INSTALL_OUTPUT" ]; then
        printf '%s\n' '[debug] --- fixture install output begin ---'
        printf '%s\n' "$INSTALL_OUTPUT"
        printf '%s\n' '[debug] --- fixture install output end ---'
    fi
}

if [ ! -f "$TARGET" ]; then
    add_fail "setupPVPN.sh not found at $TARGET"
fi

mkdir -p "$MOCK_BIN" "$MOCK_HOME"

cat > "$MOCK_BIN/systemctl" << 'EOF'
#!/usr/bin/env sh

set -u

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
    show-environment|daemon-reload|enable|start|disable)
        exit 0
        ;;
    is-active)
        exit 0
        ;;
    is-failed)
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
            ActiveState) printf 'active\n' ;;
            SubState) printf 'exited\n' ;;
            Result) printf 'success\n' ;;
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
        printf 'Username: fixture-user\n'
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

cat > "$MOCK_BIN/ping" << 'EOF'
#!/usr/bin/env sh
exit 0
EOF

cat > "$MOCK_BIN/ip" << 'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = "route" ] && [ "${2:-}" = "show" ] && [ "${3:-}" = "default" ]; then
    printf 'default via 192.0.2.1 dev eth0\n'
    exit 0
fi
exit 0
EOF

chmod +x "$MOCK_BIN/systemctl" "$MOCK_BIN/protonvpn" "$MOCK_BIN/ping" "$MOCK_BIN/ip"

if [ -f "$TARGET" ]; then
    INSTALL_OUTPUT="$(
        PATH="$MOCK_BIN:$ORIG_PATH" \
        HOME="$MOCK_HOME" \
        sh "$TARGET" --non-interactive install --systemd-health-retries 1 --systemd-health-delay 0 2>&1
    )"
    install_status=$?
    if [ "$install_status" -ne 0 ]; then
        add_fail "fixture install failed ($install_status)"
    fi

    WRAPPER_FILE="$MOCK_HOME/.local/bin/protonvpn-autoconnect.sh"
    if [ ! -f "$WRAPPER_FILE" ]; then
        add_fail "generated wrapper not found at $WRAPPER_FILE"
    else
        sh -n "$WRAPPER_FILE" || add_fail "generated wrapper fails sh -n"
        assert_file_contains "$WRAPPER_FILE" "LOCK_FILE=\"\$HOME/.local/state/proton-helper-autoconnect.lock\"" "generated wrapper lockfile variable missing"
        assert_file_contains "$WRAPPER_FILE" "LOCK_DIR=\"\$HOME/.local/state\"" "generated wrapper lock directory variable missing"
        assert_file_contains "$WRAPPER_FILE" "mkdir -p \"\$LOCK_DIR\" >/dev/null 2>&1 || true" "generated wrapper lock directory create missing"
        assert_file_contains "$WRAPPER_FILE" "if [ -f \"\$LOCK_FILE\" ]; then" "generated wrapper lock existence check missing"
        assert_file_contains "$WRAPPER_FILE" "lock_pid=" "generated wrapper lock pid assignment missing"
        assert_file_contains "$WRAPPER_FILE" "kill -0 \"\$lock_pid\" >/dev/null 2>&1" "generated wrapper lock pid check missing"
        assert_file_contains "$WRAPPER_FILE" "Another ProtonVPN autoconnect instance is already running (pid=%s)." "generated wrapper duplicate-run message missing"
        assert_file_contains "$WRAPPER_FILE" "printf '%s\\n' \"\$\$\" > \"\$LOCK_FILE\" 2>/dev/null || true" "generated wrapper lock write missing"
        assert_file_contains "$WRAPPER_FILE" "cleanup_lock() {" "generated wrapper cleanup function missing"
        assert_file_contains "$WRAPPER_FILE" "rm -f \"\$LOCK_FILE\"" "generated wrapper cleanup remove missing"
        assert_file_contains "$WRAPPER_FILE" "trap cleanup_lock EXIT INT TERM" "generated wrapper cleanup trap missing"
    fi
    if ! printf '%s\n' "$INSTALL_OUTPUT" | grep -Fq -- "Configured user systemd autostart."; then
        add_fail "fixture install did not report successful systemd setup"
    fi
fi

rm -rf "$TMP_DIR"

if [ "$FAIL_COUNT" -gt 0 ]; then
    debug_dump_on_fail
    printf 'FAIL SUMMARY (%s)\n' "$FAIL_COUNT"
    printf '%b\n' "$FAIL_LIST"
    exit 1
fi

printf '[regression] PASS: generated wrapper lockfile fixture validated.\n'
exit 0
