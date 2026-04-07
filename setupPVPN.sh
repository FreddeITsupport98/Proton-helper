#!/usr/bin/env sh

set -u

LOCAL_BIN="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
WRAPPER="$LOCAL_BIN/protonvpn-autoconnect.sh"
UNIT="$SYSTEMD_USER_DIR/protonvpn-autoconnect.service"

mkdir -p "$LOCAL_BIN" "$SYSTEMD_USER_DIR"

cat > "$WRAPPER" << 'EOF'
#!/usr/bin/env sh

# Avoid failing autostart if already connected.
if /usr/bin/protonvpn info 2>/dev/null | /usr/bin/grep -Eqi '(^|\s)connected(\s|$)|status:\s*connected'; then
    exit 0
fi

exec /usr/bin/protonvpn connect
EOF

chmod +x "$WRAPPER"

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

printf 'Done. ProtonVPN autostart service is enabled.\n'
printf 'Check status with: systemctl --user --no-pager status protonvpn-autoconnect.service\n'
