#!/usr/bin/env sh

set -u

LOCAL_BIN="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
AUTOSTART_DIR="$HOME/.config/autostart"
WRAPPER="$LOCAL_BIN/protonvpn-autoconnect.sh"
UNIT="$SYSTEMD_USER_DIR/protonvpn-autoconnect.service"
DESKTOP_ENTRY="$AUTOSTART_DIR/protonvpn-autoconnect.desktop"
STARTUP_MODE="none"
SCRIPT_PATH="$0"
ACTION="quit"

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

run_with_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return $?
    fi

    if have_cmd sudo; then
        sudo "$@"
        return $?
    fi

    warn "Need root permissions for: $*"
    return 1
}

is_user_systemd_available() {
    if ! have_cmd systemctl; then
        return 1
    fi

    if ! systemctl --user show-environment >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

detect_pkg_manager() {
    if have_cmd apt; then
        printf 'apt\n'
        return 0
    fi
    if have_cmd dnf; then
        printf 'dnf\n'
        return 0
    fi
    if have_cmd yum; then
        printf 'yum\n'
        return 0
    fi
    if have_cmd pacman; then
        printf 'pacman\n'
        return 0
    fi
    if have_cmd zypper; then
        printf 'zypper\n'
        return 0
    fi
    if have_cmd apk; then
        printf 'apk\n'
        return 0
    fi
    printf 'unknown\n'
    return 1
}

install_protonvpn_cli() {
    if have_cmd protonvpn; then
        log "ProtonVPN CLI already installed."
        return 0
    fi

    PKG_MANAGER="$(detect_pkg_manager)"
    case "$PKG_MANAGER" in
        apt)
            run_with_sudo apt install -y protonvpn-stable-release || true
            run_with_sudo apt update || return 1
            run_with_sudo apt install -y python3-proton-vpn-cli || return 1
            ;;
        dnf)
            run_with_sudo dnf install -y protonvpn-cli || return 1
            ;;
        yum)
            run_with_sudo yum install -y protonvpn-cli || return 1
            ;;
        pacman)
            run_with_sudo pacman -Sy --noconfirm protonvpn-cli || return 1
            ;;
        zypper)
            run_with_sudo zypper --non-interactive install protonvpn-cli || return 1
            ;;
        apk)
            run_with_sudo apk add protonvpn-cli || return 1
            ;;
        *)
            warn "Unsupported distro/package manager. Install ProtonVPN CLI manually, then rerun this script."
            return 1
            ;;
    esac

    if ! have_cmd protonvpn; then
        warn "Install finished but protonvpn command is still not available in PATH."
        return 1
    fi

    return 0
}

uninstall_protonvpn_cli() {
    PKG_MANAGER="$(detect_pkg_manager)"
    case "$PKG_MANAGER" in
        apt)
            run_with_sudo apt remove -y python3-proton-vpn-cli python3-proton-vpn-local-agent python3-proton-keyring-linux || true
            run_with_sudo apt autoremove -y || true
            ;;
        dnf)
            run_with_sudo dnf remove -y protonvpn-cli || true
            ;;
        yum)
            run_with_sudo yum remove -y protonvpn-cli || true
            ;;
        pacman)
            run_with_sudo pacman -R --noconfirm protonvpn-cli || true
            ;;
        zypper)
            run_with_sudo zypper --non-interactive remove protonvpn-cli || true
            ;;
        apk)
            run_with_sudo apk del protonvpn-cli || true
            ;;
        *)
            warn "Unsupported package manager for CLI uninstall; skipping package removal."
            ;;
    esac
}

write_wrapper() {
    mkdir -p "$LOCAL_BIN"
    cat > "$WRAPPER" << 'EOF'
#!/usr/bin/env sh

set -u

if ! command -v protonvpn >/dev/null 2>&1; then
    printf 'protonvpn command not found.\n' >&2
    exit 1
fi

# Avoid failing autostart if already connected.
if protonvpn info 2>/dev/null | grep -Eqi 'status:[[:space:]]*connected|connected to '; then
    exit 0
fi

exec protonvpn connect
EOF
    chmod +x "$WRAPPER"
}

setup_user_systemd() {
    if ! is_user_systemd_available; then
        return 1
    fi

    mkdir -p "$SYSTEMD_USER_DIR"
    cat > "$UNIT" << EOF
[Unit]
Description=Auto-connect ProtonVPN CLI at user login
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$WRAPPER
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now protonvpn-autoconnect.service
    STARTUP_MODE="systemd"
}

setup_xdg_autostart() {
    mkdir -p "$AUTOSTART_DIR"
    cat > "$DESKTOP_ENTRY" << EOF
[Desktop Entry]
Type=Application
Name=ProtonVPN Auto Connect
Comment=Connect ProtonVPN at login
Exec=$WRAPPER
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    log "Created desktop autostart entry: $DESKTOP_ENTRY"
    STARTUP_MODE="xdg-autostart"
}

disable_user_systemd_unit() {
    if ! is_user_systemd_available; then
        return 0
    fi

    if [ -f "$UNIT" ] || systemctl --user --quiet is-enabled protonvpn-autoconnect.service 2>/dev/null; then
        systemctl --user disable --now protonvpn-autoconnect.service >/dev/null 2>&1 || true
        systemctl --user daemon-reload
    fi

    return 0
}

remove_startup_files() {
    disable_user_systemd_unit
    rm -f "$UNIT" "$DESKTOP_ENTRY" "$WRAPPER"
}

prompt_remove_cli_with_menu() {
    if have_cmd whiptail && [ -t 1 ] && [ -t 2 ]; then
        whiptail --title "Proton-helper" --yesno "Also uninstall ProtonVPN CLI packages?" 10 70
        return $?
    fi

    if have_cmd dialog && [ -t 1 ] && [ -t 2 ]; then
        dialog --yesno "Also uninstall ProtonVPN CLI packages?" 10 70
        return $?
    fi

    return 1
}

show_action_menu() {
    if have_cmd whiptail && [ -t 1 ] && [ -t 2 ]; then
        ACTION="$(whiptail --title "Proton-helper" --menu "Choose an action" 17 72 4 \
            "install" "Install/setup ProtonVPN autostart" \
            "repair" "Repair ProtonVPN setup files and startup hooks" \
            "uninstall" "Remove ProtonVPN setup" \
            "quit" "Cancel and exit" \
            3>&1 1>&2 2>&3)" || ACTION="quit"
        return 0
    fi

    if have_cmd dialog && [ -t 1 ] && [ -t 2 ]; then
        ACTION="$(dialog --stdout --title "Proton-helper" --menu "Choose an action" 17 72 4 \
            "install" "Install/setup ProtonVPN autostart" \
            "repair" "Repair ProtonVPN setup files and startup hooks" \
            "uninstall" "Remove ProtonVPN setup" \
            "quit" "Cancel and exit")" || ACTION="quit"
        return 0
    fi
    printf '1) install\n2) repair\n3) uninstall\n4) quit\nSelect: '
    read -r CHOICE
    case "$CHOICE" in
        1) ACTION="install" ;;
        2) ACTION="repair" ;;
        3) ACTION="uninstall" ;;
        *) ACTION="quit" ;;
    esac
}

ensure_self_executable() {
    case "$SCRIPT_PATH" in
        /*) ;;
        *) SCRIPT_PATH="$(pwd)/$SCRIPT_PATH" ;;
    esac

    if [ ! -f "$SCRIPT_PATH" ]; then
        warn "Could not verify script path for auto-chmod: $SCRIPT_PATH"
        return 0
    fi

    if [ -x "$SCRIPT_PATH" ]; then
        return 0
    fi

    if chmod +x "$SCRIPT_PATH" 2>/dev/null; then
        log "Auto-chmod applied to script: $SCRIPT_PATH"
        return 0
    fi

    if run_with_sudo chmod +x "$SCRIPT_PATH"; then
        log "Auto-chmod applied with elevated permissions: $SCRIPT_PATH"
        return 0
    fi

    warn "Failed to auto-chmod script: $SCRIPT_PATH"
    return 0
}

run_install_flow() {
    if ! install_protonvpn_cli; then
        warn "Setup stopped because ProtonVPN CLI could not be installed."
        return 1
    fi

    write_wrapper

    if setup_user_systemd; then
        log "Configured user systemd autostart."
    else
        setup_xdg_autostart
        warn "systemd --user not available; used XDG autostart fallback."
    fi

    printf 'Done. ProtonVPN startup setup completed.\n'
    printf 'If this is your first time, run: protonvpn signin\n'
    if [ "$STARTUP_MODE" = "systemd" ]; then
        printf 'Check status with: systemctl --user --no-pager status protonvpn-autoconnect.service\n'
    fi
    if [ "$STARTUP_MODE" = "xdg-autostart" ]; then
        printf 'Desktop autostart entry: %s\n' "$DESKTOP_ENTRY"
    fi

    return 0
}

run_uninstall_flow() {
    remove_startup_files
    log "Removed ProtonVPN startup files."

    if prompt_remove_cli_with_menu; then
        uninstall_protonvpn_cli
        log "ProtonVPN CLI package removal requested."
    else
        log "Kept ProtonVPN CLI packages installed."
    fi

    printf 'Done. ProtonVPN uninstall flow completed.\n'
    return 0
}
run_repair_flow() {
    log "Starting repair flow..."
    remove_startup_files
    STARTUP_MODE="none"
    run_install_flow
    return $?
}

ensure_self_executable
show_action_menu

case "$ACTION" in
    install)
        run_install_flow
        ;;
    repair)
        run_repair_flow
        ;;
    uninstall)
        run_uninstall_flow
        ;;
    *)
        log "Cancelled."
        ;;
esac
