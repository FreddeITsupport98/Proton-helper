# Proton-helper
 small protonvpn helper for stetup no auto login!

## Table of Contents
- [Quick Links](#quick-links)
- [Overview](#overview)
- [Unreleased](#unreleased)
- [What setupPVPN.sh does](#what-setuppvpnsh-does)
- [Regression Safeguards](#regression-safeguards)
- [Usage](#usage)

## Quick Links
- Script: `setupPVPN.sh`
- Changelog: `changelog.md`

## Overview
This project provides a setup-focused ProtonVPN helper script.
The goal is to install ProtonVPN CLI (when needed) and configure login autostart without country/city connect flags.

## Unreleased
- 2026-04-07 20:12 UTC: Improved `setupPVPN.sh` for broader distro support (apt/dnf/yum/pacman/zypper/apk), with systemd user autostart and XDG autostart fallback.
- 2026-04-07 20:17 UTC: Added script self auto-chmod so `setupPVPN.sh` can ensure executable permissions on itself.
- 2026-04-07 20:19 UTC: Added startup menu selection to choose install or uninstall with a menu UI (whiptail/dialog when available).
- 2026-04-07 20:22 UTC: Added a third menu option `repair` plus regression/syntax safeguard scripts under `tests/regression`.

## What setupPVPN.sh does
- Detects supported package managers and installs ProtonVPN CLI when missing.
- Auto-chmods itself to executable when possible.
- Shows a menu before running so you can select install, repair, or uninstall.
- Creates a wrapper script at `~/.local/bin/protonvpn-autoconnect.sh`.
- Prefers `systemd --user` startup and falls back to desktop autostart (`~/.config/autostart`) when needed.
- Keeps setup behavior focused on default `protonvpn connect` (no country/city flags).
- Uninstall mode removes startup files and can also remove ProtonVPN CLI packages.

## Regression Safeguards
- `tests/regression/syntax-master.sh`: Base syntax/lint script for all shell scripts, with auto-chmod scanning.
- `tests/regression/test-setupPVPN.sh`: Regression assertions for menu and setup/uninstall/repair flow guards.
- `tests/regression/run-regressions.sh`: Master regression runner that executes all safeguards and prints fail summaries.

## Usage
Run:
`./setupPVPN.sh`

First-time account setup:
`protonvpn signin`

Run all safeguards:
`./tests/regression/run-regressions.sh`
