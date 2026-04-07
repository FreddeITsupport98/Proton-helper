#!/usr/bin/env sh

set -u
# Terminal colors
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    NC=''
fi

LOCAL_BIN="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
AUTOSTART_DIR="$HOME/.config/autostart"
WRAPPER="$LOCAL_BIN/protonvpn-autoconnect.sh"
UNIT="$SYSTEMD_USER_DIR/protonvpn-autoconnect.service"
DESKTOP_ENTRY="$AUTOSTART_DIR/protonvpn-autoconnect.desktop"
STATE_LOG_DIR="$HOME/.local/state"
LOG_FILE="$STATE_LOG_DIR/proton-helper.log"
APT_REPO_DEB_URL="https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
STARTUP_MODE="none"
SCRIPT_PATH="$0"
ACTION="quit"
CONNECT_MODE="default"
CONNECT_COUNTRY=""
CONNECT_RETRY_COUNT="1"
CONNECT_RETRY_DELAY="5"
SPLIT_TUNNEL_EXCLUDE_IPS=""
SPLIT_TUNNEL_EXCLUDE_CIDRS=""
SANITY_ONLY=0
NON_INTERACTIVE=0
DRY_RUN=0
ASSUME_YES=0
FORCE_DISABLE_KILL_SWITCH=0
UNINSTALL_PACKAGES_DECISION="no"
PURGE_CONFIG_DECISION="no"
KILL_SWITCH_WAS_ENABLED=0
KILL_SWITCH_DISABLED_FOR_UNINSTALL=0
SCRIPT_RESULT=0
PARSE_RESULT=0

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}
log_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'
}

append_persistent_log() {
    level="$1"
    shift
    message="$*"
    timestamp="$(log_timestamp)"
    mkdir -p "$STATE_LOG_DIR" 2>/dev/null || return 0
    printf '%s [%s] %s\n' "$timestamp" "$level" "$message" >> "$LOG_FILE" 2>/dev/null || true
}

log() {
    append_persistent_log "INFO" "$*"
    printf "${GREEN}INFO:${NC} %s\n" "$*"
}

warn() {
    append_persistent_log "WARN" "$*"
    printf "${YELLOW}WARN:${NC} %s\n" "$*" >&2
}

error() {
    append_persistent_log "ERROR" "$*"
    printf "${RED}ERROR:${NC} %s\n" "$*" >&2
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_bool() {
    if [ "$1" -eq 1 ]; then
        printf 'true'
    else
        printf 'false'
    fi
}
exit_handler() {
    DRY_RUN_JSON="$(json_bool "$DRY_RUN")"
    NON_INTERACTIVE_JSON="$(json_bool "$NON_INTERACTIVE")"
    ASSUME_YES_JSON="$(json_bool "$ASSUME_YES")"
    FORCE_DISABLE_KILL_SWITCH_JSON="$(json_bool "$FORCE_DISABLE_KILL_SWITCH")"
    KILL_SWITCH_WAS_ENABLED_JSON="$(json_bool "$KILL_SWITCH_WAS_ENABLED")"
    KILL_SWITCH_DISABLED_JSON="$(json_bool "$KILL_SWITCH_DISABLED_FOR_UNINSTALL")"
    if [ "$SCRIPT_RESULT" -eq 0 ]; then
        SUCCESS_JSON='true'
    else
        SUCCESS_JSON='false'
    fi
    printf 'CI_JSON: {"action":"%s","success":%s,"dry_run":%s,"non_interactive":%s,"assume_yes":%s,"force_disable_kill_switch":%s,"connect_mode":"%s","connect_country":"%s","connect_retry_count":"%s","connect_retry_delay":"%s","split_tunnel_exclude_ips":"%s","split_tunnel_exclude_cidrs":"%s","uninstall_packages_decision":"%s","purge_config_decision":"%s","kill_switch_was_enabled":%s,"kill_switch_disabled_for_uninstall":%s}\n' "$ACTION" "$SUCCESS_JSON" "$DRY_RUN_JSON" "$NON_INTERACTIVE_JSON" "$ASSUME_YES_JSON" "$FORCE_DISABLE_KILL_SWITCH_JSON" "$CONNECT_MODE" "$CONNECT_COUNTRY" "$CONNECT_RETRY_COUNT" "$CONNECT_RETRY_DELAY" "$SPLIT_TUNNEL_EXCLUDE_IPS" "$SPLIT_TUNNEL_EXCLUDE_CIDRS" "$UNINSTALL_PACKAGES_DECISION" "$PURGE_CONFIG_DECISION" "$KILL_SWITCH_WAS_ENABLED_JSON" "$KILL_SWITCH_DISABLED_JSON"
}

trap exit_handler EXIT

sanity_check_environment() {
    for dep in grep mktemp cmp dirname date mkdir sed tr cut; do
        if ! have_cmd "$dep"; then
            error "Required core utility missing: $dep"
            return 1
        fi
    done
    return 0
}
run_command_sanity_check() {
    sanity_failed=0

    if ! sanity_check_environment; then
        sanity_failed=1
    fi

    if have_cmd ping; then
        log "Sanity check: command available: ping"
    else
        warn "Sanity check: command missing: ping"
        sanity_failed=1
    fi

    if have_cmd ip; then
        log "Sanity check: command available: ip"
    else
        warn "Sanity check: command missing: ip"
        sanity_failed=1
    fi

    if have_cmd protonvpn; then
        log "Sanity check: command available: protonvpn"
    else
        warn "Sanity check: protonvpn command not found yet (install action can provision it)."
    fi

    PKG_MANAGER_SANITY="$(detect_pkg_manager || true)"
    if [ -z "$PKG_MANAGER_SANITY" ] || [ "$PKG_MANAGER_SANITY" = "unknown" ]; then
        warn "Sanity check: no supported package manager detected for automatic CLI install."
    else
        log "Sanity check: detected package manager: $PKG_MANAGER_SANITY"
    fi

    if [ "$sanity_failed" -ne 0 ]; then
        error "Command sanity check failed."
        return 1
    fi

    log "Command sanity check passed."
    return 0
}

write_file_if_changed() {
    target_file="$1"
    tmp_file="$(mktemp)"
    target_dir="$(dirname -- "$target_file")"

    cat > "$tmp_file"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would reconcile file: $target_file"
        rm -f "$tmp_file"
        return 0
    fi

    mkdir -p "$target_dir"

    if [ -f "$target_file" ] && cmp -s "$tmp_file" "$target_file"; then
        rm -f "$tmp_file"
        log "Idempotent run: no file changes needed for $target_file"
        return 0
    fi

    mv "$tmp_file" "$target_file"
    log "Updated file: $target_file"
    return 0
}

safe_remove_path() {
    remove_target="$1"
    case "$remove_target" in
        /*) resolved_target="$remove_target" ;;
        *) resolved_target="$(pwd)/$remove_target" ;;
    esac

    if [ "$resolved_target" = "$SCRIPT_PATH" ]; then
        warn "Refusing to remove managed setup script: $SCRIPT_PATH"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would remove: $resolved_target"
        return 0
    fi

    rm -f "$resolved_target"
    return 0
}
safe_remove_tree() {
    remove_target="$1"
    case "$remove_target" in
        /*) resolved_target="$remove_target" ;;
        *) resolved_target="$(pwd)/$remove_target" ;;
    esac

    if [ "$resolved_target" = "$SCRIPT_PATH" ]; then
        warn "Refusing to recursively remove managed setup script: $SCRIPT_PATH"
        return 0
    fi

    case "$resolved_target" in
        ''|/|"$HOME"|"$HOME"/)
            warn "Refusing to recursively remove unsafe path: $resolved_target"
            return 1
            ;;
    esac

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would recursively remove: $resolved_target"
        return 0
    fi

    rm -rf "$resolved_target"
    return 0
}

run_with_sudo() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] sudo $*"
        return 0
    fi
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return $?
    fi

    if have_cmd sudo; then
        sudo "$@"
        return $?
    fi

    error "Need root permissions for: $*"
    return 1
}

is_kill_switch_enabled() {
    if ! have_cmd protonvpn; then
        return 1
    fi

    kill_switch_line="$(protonvpn config list 2>/dev/null | grep -Ei 'kill[ -]?switch' | tail -n 1 || true)"
    if [ -z "$kill_switch_line" ]; then
        return 1
    fi

    if printf '%s\n' "$kill_switch_line" | grep -Eiq '(off|disabled|false|none)'; then
        return 1
    fi

    if printf '%s\n' "$kill_switch_line" | grep -Eiq '(on|enabled|always|hard|strict)'; then
        return 0
    fi

    return 1
}

disable_kill_switch_for_uninstall() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would disable ProtonVPN kill switch before uninstall"
        KILL_SWITCH_DISABLED_FOR_UNINSTALL=1
        return 0
    fi

    if protonvpn config set kill-switch off >/dev/null 2>&1; then
        KILL_SWITCH_DISABLED_FOR_UNINSTALL=1
        log "ProtonVPN kill switch disabled for uninstall."
        return 0
    fi

    if run_with_sudo protonvpn config set kill-switch off >/dev/null 2>&1; then
        KILL_SWITCH_DISABLED_FOR_UNINSTALL=1
        log "ProtonVPN kill switch disabled for uninstall (elevated)."
        return 0
    fi

    return 1
}

ensure_kill_switch_safe_for_uninstall() {
    KILL_SWITCH_WAS_ENABLED=0
    KILL_SWITCH_DISABLED_FOR_UNINSTALL=0

    if ! is_kill_switch_enabled; then
        return 0
    fi

    KILL_SWITCH_WAS_ENABLED=1
    warn "ProtonVPN kill switch appears enabled."
    if [ "$FORCE_DISABLE_KILL_SWITCH" -eq 1 ]; then
        log "Force-disable-kill-switch flag enabled; attempting kill switch disable before uninstall."
        disable_kill_switch_for_uninstall || warn "Failed to disable kill switch with force flag."
        return 0
    fi

    if [ "$ASSUME_YES" -eq 1 ]; then
        disable_kill_switch_for_uninstall || warn "Failed to disable kill switch automatically."
        return 0
    fi

    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        warn "Non-interactive uninstall without --yes will not disable kill switch automatically."
        return 0
    fi

    if prompt_yes_no "Proton-helper" "Kill switch is enabled. Disable it before uninstall to avoid losing connectivity?"; then
        disable_kill_switch_for_uninstall || warn "Failed to disable kill switch after confirmation."
    else
        warn "Keeping kill switch enabled per user decision."
    fi

    return 0
}
validate_connect_preferences() {
    case "$CONNECT_MODE" in
        default|fastest|country)
            ;;
        *)
            error "Invalid --connect-mode value: $CONNECT_MODE (expected default|fastest|country)."
            return 1
            ;;
    esac

    if [ -n "$CONNECT_COUNTRY" ]; then
        CONNECT_COUNTRY="$(printf '%s' "$CONNECT_COUNTRY" | tr '[:lower:]' '[:upper:]')"
        case "$CONNECT_COUNTRY" in
            [A-Z][A-Z])
                ;;
            *)
                error "Invalid --country-code value: $CONNECT_COUNTRY (expected two letters like US)."
                return 1
                ;;
        esac
    fi

    if [ "$CONNECT_MODE" = "country" ] && [ -z "$CONNECT_COUNTRY" ]; then
        error "--connect-mode country requires --country-code <CC>."
        return 1
    fi

    if [ "$CONNECT_MODE" != "country" ] && [ -n "$CONNECT_COUNTRY" ]; then
        warn "Country code provided but connect mode is $CONNECT_MODE; country code will be ignored."
    fi
    case "$CONNECT_RETRY_COUNT" in
        ''|*[!0-9]*)
            error "Invalid --connect-retry value: $CONNECT_RETRY_COUNT (expected integer >= 1)."
            return 1
            ;;
        0)
            error "Invalid --connect-retry value: $CONNECT_RETRY_COUNT (expected integer >= 1)."
            return 1
            ;;
    esac

    case "$CONNECT_RETRY_DELAY" in
        ''|*[!0-9]*)
            error "Invalid --connect-retry-delay value: $CONNECT_RETRY_DELAY (expected integer >= 0)."
            return 1
            ;;
    esac

    return 0
}
validate_split_tunnel_preferences() {
    OLD_IFS="$IFS"

    if [ -n "$SPLIT_TUNNEL_EXCLUDE_IPS" ]; then
        IFS=','
        for exclude_ip in $SPLIT_TUNNEL_EXCLUDE_IPS; do
            if ! printf '%s' "$exclude_ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
                IFS="$OLD_IFS"
                error "Invalid --exclude-ip value: $exclude_ip"
                return 1
            fi
        done
        IFS="$OLD_IFS"
    fi

    if [ -n "$SPLIT_TUNNEL_EXCLUDE_CIDRS" ]; then
        IFS=','
        for exclude_cidr in $SPLIT_TUNNEL_EXCLUDE_CIDRS; do
            if ! printf '%s' "$exclude_cidr" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$'; then
                IFS="$OLD_IFS"
                error "Invalid --exclude-cidr value: $exclude_cidr"
                return 1
            fi
            cidr_prefix="$(printf '%s' "$exclude_cidr" | cut -d/ -f2)"
            if [ "$cidr_prefix" -gt 32 ]; then
                IFS="$OLD_IFS"
                error "Invalid --exclude-cidr prefix: $exclude_cidr"
                return 1
            fi
        done
        IFS="$OLD_IFS"
    fi

    return 0
}

run_status_flow() {
    STATUS_SERVICE_STATE="unavailable"
    STATUS_VPN_STATE="cli-missing"
    STATUS_SERVER="unknown"
    STATUS_IP="unknown"
    STATUS_PUBLIC_IP="unknown"
    STATUS_KILL_SWITCH_ENABLED=0

    if is_user_systemd_available; then
        if systemctl --user --quiet is-active protonvpn-autoconnect.service 2>/dev/null; then
            STATUS_SERVICE_STATE="active"
        elif systemctl --user --quiet is-failed protonvpn-autoconnect.service 2>/dev/null; then
            STATUS_SERVICE_STATE="failed"
        elif systemctl --user --quiet is-enabled protonvpn-autoconnect.service 2>/dev/null; then
            STATUS_SERVICE_STATE="inactive-enabled"
        elif [ -f "$UNIT" ]; then
            STATUS_SERVICE_STATE="inactive"
        else
            STATUS_SERVICE_STATE="not-configured"
        fi
    elif [ -f "$DESKTOP_ENTRY" ]; then
        STATUS_SERVICE_STATE="xdg-autostart-configured"
    fi

    if have_cmd protonvpn; then
        status_info="$(protonvpn info 2>/dev/null || true)"
        if [ -n "$status_info" ]; then
            if printf '%s\n' "$status_info" | grep -Eqi 'status:[[:space:]]*connected|connected to '; then
                STATUS_VPN_STATE="connected"
            else
                STATUS_VPN_STATE="disconnected"
            fi
            server_line="$(printf '%s\n' "$status_info" | grep -Ei '^[[:space:]]*(server|server name|gateway):' | head -n 1 || true)"
            ip_line="$(printf '%s\n' "$status_info" | grep -Ei '^[[:space:]]*(server ip|ip address|ip):' | head -n 1 || true)"
            if [ -n "$server_line" ]; then
                STATUS_SERVER="$(printf '%s' "${server_line#*:}" | sed 's/^[[:space:]]*//')"
            fi
            if [ -n "$ip_line" ]; then
                STATUS_IP="$(printf '%s' "${ip_line#*:}" | sed 's/^[[:space:]]*//')"
            fi
        else
            STATUS_VPN_STATE="unknown"
        fi
    fi

    if have_cmd curl; then
        STATUS_PUBLIC_IP="$(curl -fsS https://api.ipify.org 2>/dev/null || true)"
    elif have_cmd wget; then
        STATUS_PUBLIC_IP="$(wget -qO- https://api.ipify.org 2>/dev/null || true)"
    fi
    if [ -z "$STATUS_PUBLIC_IP" ]; then
        STATUS_PUBLIC_IP="unknown"
    fi

    if is_kill_switch_enabled; then
        STATUS_KILL_SWITCH_ENABLED=1
    fi

    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        STATUS_KS_JSON="$(json_bool "$STATUS_KILL_SWITCH_ENABLED")"
        STATUS_SERVICE_ESCAPED="$(json_escape "$STATUS_SERVICE_STATE")"
        STATUS_VPN_ESCAPED="$(json_escape "$STATUS_VPN_STATE")"
        STATUS_SERVER_ESCAPED="$(json_escape "$STATUS_SERVER")"
        STATUS_IP_ESCAPED="$(json_escape "$STATUS_IP")"
        STATUS_PUBLIC_IP_ESCAPED="$(json_escape "$STATUS_PUBLIC_IP")"
        printf 'STATUS_JSON: {"service_state":"%s","vpn_state":"%s","server":"%s","vpn_ip":"%s","public_ip":"%s","kill_switch_enabled":%s}\n' "$STATUS_SERVICE_ESCAPED" "$STATUS_VPN_ESCAPED" "$STATUS_SERVER_ESCAPED" "$STATUS_IP_ESCAPED" "$STATUS_PUBLIC_IP_ESCAPED" "$STATUS_KS_JSON"
    else
        printf 'Status dashboard\n'
        printf '%s\n' "- startup service: $STATUS_SERVICE_STATE"
        printf '%s\n' "- vpn state: $STATUS_VPN_STATE"
        printf '%s\n' "- server: $STATUS_SERVER"
        printf '%s\n' "- vpn ip: $STATUS_IP"
        printf '%s\n' "- public ip: $STATUS_PUBLIC_IP"
        if [ "$STATUS_KILL_SWITCH_ENABLED" -eq 1 ]; then
            printf '%s\n' '- kill switch: enabled'
        else
            printf '%s\n' '- kill switch: disabled-or-unknown'
        fi
    fi

    return 0
}

print_usage() {
    printf 'Usage: %s [--non-interactive <install|repair|status|uninstall|quit|sanity-check>] [--status] [--sanity-check] [--connect-mode <default|fastest|country>] [--country-code <CC>] [--connect-retry <N>] [--connect-retry-delay <seconds>] [--exclude-ip <IPv4>] [--exclude-cidr <CIDR>] [--dry-run] [--yes] [--force-disable-kill-switch] [--help]\n' "$SCRIPT_PATH"
}

parse_cli_args() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --non-interactive|-n)
                NON_INTERACTIVE=1
                shift
                if [ "$#" -eq 0 ]; then
                    error "Missing action for --non-interactive. Use install|repair|status|uninstall|quit|sanity-check."
                    return 1
                fi
                case "$1" in
                    install|repair|status|uninstall|quit|sanity-check)
                        ACTION="$1"
                        ;;
                    *)
                        error "Invalid non-interactive action: $1"
                        return 1
                        ;;
                esac
                ;;
            --help|-h)
                print_usage
                return 2
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            --yes|-y)
                ASSUME_YES=1
                ;;
            --force-disable-kill-switch)
                FORCE_DISABLE_KILL_SWITCH=1
                ;;
            --sanity-check)
                SANITY_ONLY=1
                ACTION="sanity-check"
                ;;
            --status)
                ACTION="status"
                NON_INTERACTIVE=1
                ;;
            --connect-mode)
                shift
                if [ "$#" -eq 0 ]; then
                    error "Missing value for --connect-mode. Use default|fastest|country."
                    return 1
                fi
                CONNECT_MODE="$1"
                ;;
            --country-code)
                shift
                if [ "$#" -eq 0 ]; then
                    error "Missing value for --country-code. Use a two-letter code like US."
                    return 1
                fi
                CONNECT_COUNTRY="$1"
                ;;
            --connect-retry)
                shift
                if [ "$#" -eq 0 ]; then
                    error "Missing value for --connect-retry. Use integer >= 1."
                    return 1
                fi
                CONNECT_RETRY_COUNT="$1"
                ;;
            --connect-retry-delay)
                shift
                if [ "$#" -eq 0 ]; then
                    error "Missing value for --connect-retry-delay. Use integer >= 0."
                    return 1
                fi
                CONNECT_RETRY_DELAY="$1"
                ;;
            --exclude-ip)
                shift
                if [ "$#" -eq 0 ]; then
                    error "Missing value for --exclude-ip. Use IPv4 address."
                    return 1
                fi
                if [ -n "$SPLIT_TUNNEL_EXCLUDE_IPS" ]; then
                    SPLIT_TUNNEL_EXCLUDE_IPS="${SPLIT_TUNNEL_EXCLUDE_IPS},$1"
                else
                    SPLIT_TUNNEL_EXCLUDE_IPS="$1"
                fi
                ;;
            --exclude-cidr)
                shift
                if [ "$#" -eq 0 ]; then
                    error "Missing value for --exclude-cidr. Use CIDR like 192.168.1.0/24."
                    return 1
                fi
                if [ -n "$SPLIT_TUNNEL_EXCLUDE_CIDRS" ]; then
                    SPLIT_TUNNEL_EXCLUDE_CIDRS="${SPLIT_TUNNEL_EXCLUDE_CIDRS},$1"
                else
                    SPLIT_TUNNEL_EXCLUDE_CIDRS="$1"
                fi
                ;;
            *)
                error "Unknown argument: $1"
                return 1
                ;;
        esac
        shift
    done

    return 0
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

ensure_apt_proton_repo() {
    if dpkg-query -W -f='${Status}' protonvpn-stable-release 2>/dev/null | grep -Fq 'install ok installed'; then
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would ensure protonvpn-stable-release is installed (with .deb fallback if needed)."
        return 0
    fi

    log "ProtonVPN repository package not detected. Preparing repository setup."

    if run_with_sudo apt install -y protonvpn-stable-release; then
        return 0
    fi

    warn "APT could not install protonvpn-stable-release directly; using official .deb fallback."

    DEB_FILE="$(mktemp)"

    if have_cmd wget; then
        wget -qO "$DEB_FILE" "$APT_REPO_DEB_URL" || {
            rm -f "$DEB_FILE"
            error "Failed to download ProtonVPN repository package with wget."
            return 1
        }
    elif have_cmd curl; then
        curl -fsSL "$APT_REPO_DEB_URL" -o "$DEB_FILE" || {
            rm -f "$DEB_FILE"
            error "Failed to download ProtonVPN repository package with curl."
            return 1
        }
    else
        rm -f "$DEB_FILE"
        error "Neither wget nor curl is installed; cannot fetch ProtonVPN repository package."
        return 1
    fi

    if [ ! -s "$DEB_FILE" ]; then
        rm -f "$DEB_FILE"
        error "Downloaded ProtonVPN repository package is empty."
        return 1
    fi

    if ! run_with_sudo dpkg -i "$DEB_FILE"; then
        rm -f "$DEB_FILE"
        error "Failed to install downloaded ProtonVPN repository package."
        return 1
    fi

    rm -f "$DEB_FILE"
    return 0
}

install_protonvpn_cli() {
    if have_cmd protonvpn; then
        log "ProtonVPN CLI already installed."
        return 0
    fi

    PKG_MANAGER="$(detect_pkg_manager)"
    case "$PKG_MANAGER" in
        apt)
            ensure_apt_proton_repo || return 1
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
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] skipping post-install protonvpn command availability check."
        return 0
    fi

    if ! have_cmd protonvpn; then
        error "Install finished but protonvpn command is still not available in PATH."
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
    # shellcheck disable=SC2154
    write_file_if_changed "$WRAPPER" << EOF
#!/usr/bin/env sh

set -u
CONNECT_MODE="$CONNECT_MODE"
CONNECT_COUNTRY="$CONNECT_COUNTRY"
CONNECT_RETRY_COUNT="$CONNECT_RETRY_COUNT"
CONNECT_RETRY_DELAY="$CONNECT_RETRY_DELAY"
SPLIT_TUNNEL_EXCLUDE_IPS="$SPLIT_TUNNEL_EXCLUDE_IPS"
SPLIT_TUNNEL_EXCLUDE_CIDRS="$SPLIT_TUNNEL_EXCLUDE_CIDRS"

if ! command -v protonvpn >/dev/null 2>&1; then
    printf 'protonvpn command not found.\n' >&2
    exit 1
fi
# Wait for real network connectivity before trying VPN connection.
printf 'Waiting for network connectivity...\n'
network_up=0
i=0
while [ "\$i" -lt 15 ]; do
    if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 || ip route show default 2>/dev/null | grep -q '^default '; then
        network_up=1
        break
    fi
    sleep 2
    i=\$((i + 1))
done

if [ "\$network_up" -eq 0 ]; then
    printf 'Network not available yet. Aborting ProtonVPN autoconnect.\n' >&2
    exit 1
fi

# Avoid failing autostart if already connected.
if protonvpn info 2>/dev/null | grep -Eqi 'status:[[:space:]]*connected|connected to '; then
    printf 'ProtonVPN already connected.\n'
    exit 0
fi
apply_split_tunnel_exclusions() {
    if [ -z "\$SPLIT_TUNNEL_EXCLUDE_IPS" ] && [ -z "\$SPLIT_TUNNEL_EXCLUDE_CIDRS" ]; then
        return 0
    fi
    protonvpn config set split-tunnel on >/dev/null 2>&1 || protonvpn config set split-tunneling on >/dev/null 2>&1 || true
    old_ifs="\$IFS"
    IFS=','
    for exclude_ip in \$SPLIT_TUNNEL_EXCLUDE_IPS; do
        [ -z "\$exclude_ip" ] && continue
        protonvpn config set split-tunnel-exclude-ip "\$exclude_ip" >/dev/null 2>&1 || protonvpn config set split-tunnel-ip-exclusion "\$exclude_ip" >/dev/null 2>&1 || printf 'Warning: failed to apply split-tunnel IP exclusion: %s\n' "\$exclude_ip" >&2
    done
    for exclude_cidr in \$SPLIT_TUNNEL_EXCLUDE_CIDRS; do
        [ -z "\$exclude_cidr" ] && continue
        protonvpn config set split-tunnel-exclude-cidr "\$exclude_cidr" >/dev/null 2>&1 || protonvpn config set split-tunnel-cidr-exclusion "\$exclude_cidr" >/dev/null 2>&1 || printf 'Warning: failed to apply split-tunnel CIDR exclusion: %s\n' "\$exclude_cidr" >&2
    done
    IFS="\$old_ifs"
    return 0
}
apply_split_tunnel_exclusions || true
case "\$CONNECT_MODE" in
    default)
        connect_once() { protonvpn connect; }
        ;;
    fastest)
        connect_once() { protonvpn connect --fastest; }
        ;;
    country)
        connect_once() {
            if [ -z "\$CONNECT_COUNTRY" ]; then
                printf 'CONNECT_COUNTRY is empty while CONNECT_MODE=country.\n' >&2
                return 1
            fi
            protonvpn connect --cc "\$CONNECT_COUNTRY"
        }
        ;;
    *)
        printf 'Unknown CONNECT_MODE: %s\n' "\$CONNECT_MODE" >&2
        connect_once() { protonvpn connect; }
        ;;
esac

attempt=1
while [ "\$attempt" -le "\$CONNECT_RETRY_COUNT" ]; do
    if connect_once; then
        exit 0
    fi

    if [ "\$attempt" -lt "\$CONNECT_RETRY_COUNT" ]; then
        printf 'ProtonVPN connect attempt %s/%s failed; retrying in %ss.\n' "\$attempt" "\$CONNECT_RETRY_COUNT" "\$CONNECT_RETRY_DELAY" >&2
        sleep "\$CONNECT_RETRY_DELAY"
    fi

    attempt=\$((attempt + 1))
done

printf 'ProtonVPN connect failed after %s attempt(s).\n' "\$CONNECT_RETRY_COUNT" >&2
exit 1
EOF
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would chmod +x $WRAPPER"
    else
        chmod +x "$WRAPPER"
    fi
}

setup_user_systemd() {
    if ! is_user_systemd_available; then
        return 1
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would write and enable managed user unit $UNIT"
        STARTUP_MODE="systemd"
        return 0
    fi

    write_file_if_changed "$UNIT" << EOF
[Unit]
Description=ProtonVPN Auto-Connect Service
Documentation=https://protonvpn.com/support/linux-cli/
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"
ExecStart=$WRAPPER
ExecStop=/usr/bin/env protonvpn disconnect
TimeoutStartSec=60
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now protonvpn-autoconnect.service
    STARTUP_MODE="systemd"
}

setup_xdg_autostart() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would write desktop autostart entry $DESKTOP_ENTRY"
        STARTUP_MODE="xdg-autostart"
        return 0
    fi
    write_file_if_changed "$DESKTOP_ENTRY" << EOF
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

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would disable and stop protonvpn-autoconnect.service"
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
    safe_remove_path "$UNIT"
    safe_remove_path "$DESKTOP_ENTRY"
    safe_remove_path "$WRAPPER"
}
purge_user_protonvpn_data() {
    safe_remove_tree "$HOME/.config/protonvpn" || true
    safe_remove_tree "$HOME/.cache/protonvpn" || true
    safe_remove_tree "$HOME/.local/share/protonvpn" || true
}


prompt_yes_no() {
    prompt_title="$1"
    prompt_text="$2"

    if have_cmd whiptail && [ -t 1 ] && [ -t 2 ]; then
        whiptail --title "$prompt_title" --yesno "$prompt_text" 10 70
        return $?
    fi

    if have_cmd dialog && [ -t 1 ] && [ -t 2 ]; then
        dialog --yesno "$prompt_text" 10 70
        return $?
    fi

    printf '%s (y/N): ' "$prompt_text"
    read -r yn_answer
    case "$yn_answer" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}
prompt_remove_cli_with_menu() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        UNINSTALL_PACKAGES_DECISION="yes"
        log "Auto-confirm enabled with --yes; uninstalling ProtonVPN CLI packages."
        return 0
    fi

    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        UNINSTALL_PACKAGES_DECISION="no"
        log "Non-interactive uninstall without --yes: keeping ProtonVPN CLI packages."
        return 1
    fi
    if have_cmd whiptail && [ -t 1 ] && [ -t 2 ]; then
        if whiptail --title "Proton-helper" --yesno "Also uninstall ProtonVPN CLI packages?" 10 70; then
            UNINSTALL_PACKAGES_DECISION="yes"
            return 0
        fi
        UNINSTALL_PACKAGES_DECISION="no"
        return 1
    fi

    if have_cmd dialog && [ -t 1 ] && [ -t 2 ]; then
        if dialog --yesno "Also uninstall ProtonVPN CLI packages?" 10 70; then
            UNINSTALL_PACKAGES_DECISION="yes"
            return 0
        fi
        UNINSTALL_PACKAGES_DECISION="no"
        return 1
    fi

    UNINSTALL_PACKAGES_DECISION="no"
    return 1
}
prompt_purge_config_with_menu() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        PURGE_CONFIG_DECISION="yes"
        log "Auto-confirm enabled with --yes; purging ProtonVPN user config/cache data."
        return 0
    fi

    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        PURGE_CONFIG_DECISION="no"
        log "Non-interactive uninstall without --yes: keeping ProtonVPN user config/cache data."
        return 1
    fi

    if prompt_yes_no "Proton-helper" "Also purge ProtonVPN user config/cache data (~/.config/protonvpn, ~/.cache/protonvpn, ~/.local/share/protonvpn)?"; then
        PURGE_CONFIG_DECISION="yes"
        return 0
    fi

    PURGE_CONFIG_DECISION="no"
    return 1
}

show_action_menu() {
    if have_cmd whiptail && [ -t 1 ] && [ -t 2 ]; then
        ACTION="$(whiptail --title "Proton-helper" --menu "Choose an action" 17 72 4 \
            "install" "Install/setup ProtonVPN autostart" \
            "repair" "Repair ProtonVPN setup files and startup hooks" \
            "status" "Show ProtonVPN setup and health dashboard" \
            "uninstall" "Remove ProtonVPN setup" \
            "quit" "Cancel and exit" \
            3>&1 1>&2 2>&3)" || ACTION="quit"
        return 0
    fi

    if have_cmd dialog && [ -t 1 ] && [ -t 2 ]; then
        ACTION="$(dialog --stdout --title "Proton-helper" --menu "Choose an action" 17 72 4 \
            "install" "Install/setup ProtonVPN autostart" \
            "repair" "Repair ProtonVPN setup files and startup hooks" \
            "status" "Show ProtonVPN setup and health dashboard" \
            "uninstall" "Remove ProtonVPN setup" \
            "quit" "Cancel and exit")" || ACTION="quit"
        return 0
    fi
    printf '1) install\n2) repair\n3) status\n4) uninstall\n5) quit\nSelect: '
    read -r CHOICE
    case "$CHOICE" in
        1) ACTION="install" ;;
        2) ACTION="repair" ;;
        3) ACTION="status" ;;
        4) ACTION="uninstall" ;;
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

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would chmod +x $SCRIPT_PATH"
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
    run_command_sanity_check || return 1
    validate_connect_preferences || return 1
    validate_split_tunnel_preferences || return 1
    if ! install_protonvpn_cli; then
        error "Setup stopped because ProtonVPN CLI could not be installed."
        return 1
    fi

    write_wrapper

    if setup_user_systemd; then
        log "Configured user systemd autostart."
    else
        setup_xdg_autostart
        warn "systemd --user not available; used XDG autostart fallback."
    fi
    if [ "$CONNECT_MODE" = "country" ]; then
        log "Autoconnect mode configured: country ($CONNECT_COUNTRY)."
    else
        log "Autoconnect mode configured: $CONNECT_MODE."
    fi
    log "Autoconnect retry configured: attempts=$CONNECT_RETRY_COUNT delay=${CONNECT_RETRY_DELAY}s."
    if [ -n "$SPLIT_TUNNEL_EXCLUDE_IPS" ] || [ -n "$SPLIT_TUNNEL_EXCLUDE_CIDRS" ]; then
        log "Split tunneling exclusions configured: ips=${SPLIT_TUNNEL_EXCLUDE_IPS:-none} cidrs=${SPLIT_TUNNEL_EXCLUDE_CIDRS:-none}."
    fi

    log "ProtonVPN startup setup completed."
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
    ensure_kill_switch_safe_for_uninstall
    remove_startup_files
    log "Removed ProtonVPN startup files."
    UNINSTALL_PACKAGES_DECISION="no"
    PURGE_CONFIG_DECISION="no"

    if prompt_remove_cli_with_menu; then
        uninstall_protonvpn_cli
        log "ProtonVPN CLI package removal requested."
    else
        log "Kept ProtonVPN CLI packages installed."
    fi

    if prompt_purge_config_with_menu; then
        purge_user_protonvpn_data
        log "ProtonVPN user config/cache purge requested."
    else
        log "Kept ProtonVPN user config/cache data."
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'CI SUMMARY: would uninstall packages: %s\n' "$UNINSTALL_PACKAGES_DECISION"
        printf 'CI_JSON: {"would_uninstall_packages":"%s"}\n' "$UNINSTALL_PACKAGES_DECISION"
        printf 'CI SUMMARY: would purge configs: %s\n' "$PURGE_CONFIG_DECISION"
        printf 'CI_JSON: {"would_purge_configs":"%s"}\n' "$PURGE_CONFIG_DECISION"
    else
        printf 'CI SUMMARY: uninstall packages: %s\n' "$UNINSTALL_PACKAGES_DECISION"
        printf 'CI_JSON: {"uninstall_packages":"%s"}\n' "$UNINSTALL_PACKAGES_DECISION"
        printf 'CI SUMMARY: purge configs: %s\n' "$PURGE_CONFIG_DECISION"
        printf 'CI_JSON: {"purge_configs":"%s"}\n' "$PURGE_CONFIG_DECISION"
    fi
    DRY_RUN_JSON="$(json_bool "$DRY_RUN")"
    NON_INTERACTIVE_JSON="$(json_bool "$NON_INTERACTIVE")"
    ASSUME_YES_JSON="$(json_bool "$ASSUME_YES")"
    FORCE_DISABLE_KILL_SWITCH_JSON="$(json_bool "$FORCE_DISABLE_KILL_SWITCH")"
    KILL_SWITCH_WAS_ENABLED_JSON="$(json_bool "$KILL_SWITCH_WAS_ENABLED")"
    KILL_SWITCH_DISABLED_JSON="$(json_bool "$KILL_SWITCH_DISABLED_FOR_UNINSTALL")"
    printf 'CI_JSON: {"action":"%s","dry_run":%s,"non_interactive":%s,"assume_yes":%s,"force_disable_kill_switch":%s,"uninstall_packages_decision":"%s","kill_switch_was_enabled":%s,"kill_switch_disabled_for_uninstall":%s}\n' "$ACTION" "$DRY_RUN_JSON" "$NON_INTERACTIVE_JSON" "$ASSUME_YES_JSON" "$FORCE_DISABLE_KILL_SWITCH_JSON" "$UNINSTALL_PACKAGES_DECISION" "$KILL_SWITCH_WAS_ENABLED_JSON" "$KILL_SWITCH_DISABLED_JSON"

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
if ! sanity_check_environment; then
    SCRIPT_RESULT=1
    false
fi

parse_cli_args "$@" || PARSE_RESULT=$?

if [ "$PARSE_RESULT" -eq 1 ]; then
    SCRIPT_RESULT=1
elif [ "$PARSE_RESULT" -eq 2 ]; then
    SCRIPT_RESULT=0
else
    if [ "$SANITY_ONLY" -eq 1 ]; then
        ACTION="sanity-check"
    elif [ "$NON_INTERACTIVE" -eq 0 ]; then
        show_action_menu
    else
        log "Running non-interactive action: $ACTION"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "Dry-run mode enabled. No changes will be written."
    fi

    case "$ACTION" in
        install)
            run_install_flow || SCRIPT_RESULT=1
            ;;
        repair)
            run_repair_flow || SCRIPT_RESULT=1
            ;;
        status)
            run_status_flow || SCRIPT_RESULT=1
            ;;
        uninstall)
            run_uninstall_flow || SCRIPT_RESULT=1
            ;;
        sanity-check)
            run_command_sanity_check || SCRIPT_RESULT=1
            ;;
        *)
            log "Cancelled."
            ;;
    esac
fi

if [ "$SCRIPT_RESULT" -ne 0 ]; then
    false
fi
