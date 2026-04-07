# Changelog
## Unreleased
- 2026-04-07 20:12 UTC: Improved `setupPVPN.sh` to support multiple Linux package managers and both `systemd --user` plus XDG autostart setup paths.
- 2026-04-07 20:17 UTC: Added self auto-chmod logic in `setupPVPN.sh` to keep the setup script executable.
- 2026-04-07 20:19 UTC: Added a menu-driven installer flow in `setupPVPN.sh` to select install or uninstall before execution.
- 2026-04-07 20:22 UTC: Added repair menu action and created `tests/regression` safeguard scripts (`syntax-master.sh`, `test-setupPVPN.sh`, and `run-regressions.sh`).
