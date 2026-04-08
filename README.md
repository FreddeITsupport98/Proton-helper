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
- 2026-04-08 21:13 UTC: Added optional debug mode for `test-wrapper-generated-lockfile.sh`; set `WRAPPER_FIXTURE_DEBUG=1` to print generated wrapper and fixture install output when the fixture test fails.
- 2026-04-08 21:08 UTC: Added generated-wrapper fixture regression `tests/regression/test-wrapper-generated-lockfile.sh` that performs a safe mocked install into temp HOME and validates emitted wrapper lockfile behavior lines.
- 2026-04-08 21:00 UTC: Refactored global exit telemetry output to use a dedicated `emit_exit_ci_json` helper, keeping the same CI keys while reducing escaping complexity in `exit_handler`.
- 2026-04-08 21:00 UTC: Added focused regression script `tests/regression/test-wrapper-lockfile.sh` to validate wrapper lockfile guard lines (lock path/dir, PID check, trap cleanup) independently.
- 2026-04-08 20:41 UTC: Added startup policy controls (`--systemd-fallback-mode`, `--systemd-unit-hardening`) plus health retry strategy controls (`--systemd-health-backoff`, `--systemd-health-jitter`) with structured startup failure state recording.
- 2026-04-08 20:41 UTC: Added wrapper lockfile concurrency guard, stricter IPv4/CIDR validation, extended `STATUS_JSON` startup-policy fields, and parser regression coverage for invalid startup arguments.
- 2026-04-08 20:32 UTC: Added configurable systemd startup health knobs (`--systemd-health-retries`, `--systemd-health-delay`) and a deterministic mocked regression harness for failed/inactive/unhealthy systemd transitions.
- 2026-04-08 20:20 UTC: Hardened `systemd --user` startup with explicit unit health verification (active/failed checks with retries) and automatic fallback to XDG autostart if systemd startup fails or is unhealthy.
- 2026-04-07 20:12 UTC: Improved `setupPVPN.sh` for broader distro support (apt/dnf/yum/pacman/zypper/apk), with systemd user autostart and XDG autostart fallback.
- 2026-04-07 20:17 UTC: Added script self auto-chmod so `setupPVPN.sh` can ensure executable permissions on itself.
- 2026-04-07 20:19 UTC: Added startup menu selection to choose install or uninstall with a menu UI (whiptail/dialog when available).
- 2026-04-07 20:22 UTC: Added a third menu option `repair` plus regression/syntax safeguard scripts under `tests/regression`.
- 2026-04-07 20:31 UTC: Added robust APT repository bootstrap fallback, network-readiness wait before autoconnect, and improved INFO/WARN/ERROR console logging.
- 2026-04-07 20:33 UTC: Added non-interactive action mode (`--non-interactive`) for automation and scriptable install/repair/uninstall flows.
- 2026-04-07 20:35 UTC: Added `--dry-run` mode to simulate install/repair/uninstall actions without changing files or packages.
- 2026-04-07 20:37 UTC: Added `--yes` auto-confirm support so non-interactive uninstall flows can remove CLI packages without prompt dialogs.
- 2026-04-07 20:38 UTC: Added explicit uninstall CI summary lines that report package removal decision as yes/no (including dry-run `would uninstall` output).
- 2026-04-07 20:39 UTC: Added machine-parseable `CI_JSON` uninstall decision output for CI log parsing.
- 2026-04-07 20:41 UTC: Added a consolidated machine-parseable `CI_JSON` line with action, dry-run, non-interactive, assume-yes, and uninstall decision fields.
- 2026-04-07 20:42 UTC: Upgraded systemd user service generation with Documentation, PATH environment, ExecStop disconnect, startup timeout, and explicit journald logging directives.
- 2026-04-07 20:45 UTC: Added conservative systemd restart hardening (`Restart=on-failure`, `RestartSec=10`) for transient startup errors.
- 2026-04-07 20:50 UTC: Added uninstall kill-switch safeguards (detect + optional/auto disable before uninstall) and kill-switch CI telemetry fields.
- 2026-04-07 20:53 UTC: Added independent `--force-disable-kill-switch` flag so kill-switch disable behavior can be controlled separately from `--yes`.
- 2026-04-07 20:55 UTC: Added preflight sanity checks, idempotent file reconciliation writes, and protected uninstall removal logic that refuses to delete the setup script itself.
- 2026-04-07 21:01 UTC: Added global `EXIT` CI telemetry output (`CI_JSON`) for install/repair/uninstall/quit paths, including success state and purge decision fields.
- 2026-04-07 21:01 UTC: Added optional uninstall purge flow for ProtonVPN user data directories (`~/.config/protonvpn`, `~/.cache/protonvpn`, `~/.local/share/protonvpn`) with `--yes` automation support.
- 2026-04-07 21:01 UTC: Added route-based network fallback (`ip route show default`) in wrapper connectivity detection for captive portal / ICMP-restricted environments.
- 2026-04-07 21:07 UTC: Added optional autoconnect profile controls via `--connect-mode <default|fastest|country>` and `--country-code <CC>` for generated wrapper behavior.
- 2026-04-07 21:09 UTC: Added autoconnect retry controls (`--connect-retry <N>`, `--connect-retry-delay <seconds>`) with validation and wrapper retry backoff logging.
- 2026-04-07 21:15 UTC: Added command sanity-check mode (`--sanity-check` or `--non-interactive sanity-check`) and integrated command sanity validation into install flow prechecks.
- 2026-04-07 21:18 UTC: Added status dashboard action (`status`) with non-interactive `STATUS_JSON` output for service/vpn/kill-switch observability.
- 2026-04-07 21:18 UTC: Added persistent timestamped logging to `~/.local/state/proton-helper.log` for INFO/WARN/ERROR messages.
- 2026-04-07 21:18 UTC: Added split tunneling exclude options (`--exclude-ip`, `--exclude-cidr`) with validation and wrapper-side apply attempts.
- 2026-04-07 21:24 UTC: Fixed wrapper generation under `set -u` by escaping runtime loop variables in heredoc content (prevents `$i`/`$network_up` expansion errors during install).
- 2026-04-07 21:29 UTC: Improved human readability by defaulting interactive runs to plain-text summaries, while keeping machine-readable telemetry for non-interactive runs and optional `--ci-json` forcing.
- 2026-04-07 21:32 UTC: Added ProtonVPN sign-in state detection so install flow only shows `protonvpn signin` guidance when authentication is not detected.

## What setupPVPN.sh does
- Detects supported package managers and installs ProtonVPN CLI when missing.
- On APT systems, bootstraps Proton repository package with official `.deb` fallback if direct package install is unavailable.
- Auto-chmods itself to executable when possible.
- Shows a menu before running so you can select install, repair, or uninstall.
- Supports non-interactive mode: `--non-interactive install|repair|uninstall|quit`.
- Supports dry-run simulation mode: `--dry-run`.
- Supports auto-confirm mode: `--yes` (used for uninstall package prompt automation).
- Supports explicit kill-switch force mode: `--force-disable-kill-switch`.
- Supports autoconnect mode selection: `--connect-mode default|fastest|country`.
- Supports optional country selection for country mode: `--country-code <CC>`.
- Supports autoconnect retry controls: `--connect-retry <N>` and `--connect-retry-delay <seconds>`.
- Supports systemd startup health tuning: `--systemd-health-retries <N>` and `--systemd-health-delay <seconds>`.
- Supports systemd health retry strategy controls: `--systemd-health-backoff <fixed|exponential>` and `--systemd-health-jitter <seconds>`.
- Supports startup fallback policy controls: `--systemd-fallback-mode <auto|xdg-only|systemd-only>`.
- Supports optional systemd unit hardening controls: `--systemd-unit-hardening <off|basic>`.
- Supports explicit command sanity-check mode: `--sanity-check` (or `--non-interactive sanity-check`).
- Supports status dashboard action: `--non-interactive status` (or `--status`).
- Supports split tunneling exclusions: `--exclude-ip <IPv4>` and `--exclude-cidr <CIDR>`.
- Supports optional forced machine telemetry in interactive mode: `--ci-json`.
- Prints explicit CI summary lines for uninstall package decision (`yes`/`no`), including dry-run reporting.
- Prints machine-parseable `CI_JSON` lines for uninstall decision output.
- Prints a consolidated `CI_JSON` line with runtime flags and uninstall decision for strict CI parsing.
- Emits a global machine-parseable `CI_JSON` line on script exit for all actions (includes `success` and `purge_config_decision`).
- Uses dedicated helper `emit_exit_ci_json` to keep global exit telemetry formatting centralized and easier to maintain.
- Global exit `CI_JSON` now also includes `connect_mode` and `connect_country`.
- Global exit `CI_JSON` also includes `connect_retry_count` and `connect_retry_delay`.
- Global exit `CI_JSON` includes `split_tunnel_exclude_ips` and `split_tunnel_exclude_cidrs`.
- By default, `CI_JSON` is emitted for non-interactive runs; interactive runs show readable summaries unless `--ci-json` is used.
- Uninstall flow now checks ProtonVPN kill switch status and can disable it first to avoid connectivity lockouts.
- Uninstall flow can optionally purge ProtonVPN user config/cache/share data and respects non-interactive safe defaults.
- Performs preflight sanity checks for required core utilities.
- Performs command sanity checks for install/runtime command dependencies before install flow proceeds.
- Writes persistent timestamped logs to `~/.local/state/proton-helper.log`.
- Writes structured startup failure state to `~/.local/state/proton-helper-last-failure.json` when startup setup fails.
- Uses idempotent file reconciliation to avoid rewriting unchanged managed files.
- Creates a wrapper script at `~/.local/bin/protonvpn-autoconnect.sh`.
- Prefers `systemd --user` startup and falls back to desktop autostart (`~/.config/autostart`) when needed.
- Verifies `systemd --user` unit runtime health after start and automatically falls back to XDG autostart if the systemd unit is unhealthy.
- Systemd service now supports cleaner management via `ExecStop` disconnect and improved journald diagnostics.
- Systemd service includes conservative restart settings for transient failures.
- Wrapper waits for actual network connectivity before attempting `protonvpn connect`.
- Wrapper connectivity check includes default-route fallback when direct ping checks are blocked.
- Wrapper can connect using default, fastest, or country mode based on configured autoconnect options.
- Wrapper retries failed connect attempts based on configured retry count and delay.
- Wrapper attempts to apply split tunneling exclusions before connect attempts.
- Wrapper now uses a lockfile guard to avoid concurrent autoconnect runs.
- Keeps setup behavior focused on default `protonvpn connect` (no country/city flags).
- Uninstall mode removes startup files and can also remove ProtonVPN CLI packages.
- Uninstall safety guard explicitly refuses to remove the setup script itself.
- Install flow now suppresses redundant signin prompts when ProtonVPN CLI already appears authenticated.

## Regression Safeguards
- `tests/regression/syntax-master.sh`: Base syntax/lint script for all shell scripts, with auto-chmod scanning.
- `tests/regression/test-setupPVPN.sh`: Regression assertions for menu and setup/uninstall/repair flow guards.
- `tests/regression/test-systemd-health-fallback.sh`: Deterministic fallback checks that mock `systemctl` states (`start-fail`, `failed-state`, `inactive-unhealthy`, `healthy`).
- `tests/regression/test-cli-parser.sh`: Parser error-path checks for invalid/missing startup policy argument values.
- `tests/regression/test-wrapper-lockfile.sh`: Focused static assertions for wrapper lockfile guard behavior and cleanup trap coverage.
- `tests/regression/test-wrapper-generated-lockfile.sh`: Fixture-style regression that generates the real wrapper with mocked commands and validates lockfile guard content in emitted script output.
  - Optional debug on failure: run with `WRAPPER_FIXTURE_DEBUG=1` to dump generated wrapper content and fixture install output when assertions fail.
- `tests/regression/run-regressions.sh`: Master regression runner that executes all safeguards and prints fail summaries.

## Usage
Run:
`./setupPVPN.sh`
Run non-interactively:
`./setupPVPN.sh --non-interactive install`
Run dry-run simulation:
`./setupPVPN.sh --non-interactive repair --dry-run`
Run non-interactive uninstall with auto-confirm:
`./setupPVPN.sh --non-interactive uninstall --yes`
Run non-interactive uninstall dry-run with auto-confirm and CI summary output:
`./setupPVPN.sh --non-interactive uninstall --yes --dry-run`
Run non-interactive uninstall with forced kill-switch disable but without package auto-confirm:
`./setupPVPN.sh --non-interactive uninstall --force-disable-kill-switch`
Run non-interactive uninstall with full auto-confirm (packages + purge user data):
`./setupPVPN.sh --non-interactive uninstall --yes`
Run install with fastest autoconnect profile:
`./setupPVPN.sh --non-interactive install --connect-mode fastest`
Run install with country-specific autoconnect profile:
`./setupPVPN.sh --non-interactive install --connect-mode country --country-code US`
Run install with retry tuning:
`./setupPVPN.sh --non-interactive install --connect-mode fastest --connect-retry 3 --connect-retry-delay 10`
Run install with systemd health tuning:
`./setupPVPN.sh --non-interactive install --systemd-health-retries 2 --systemd-health-delay 1`
Run install with exponential backoff and jitter:
`./setupPVPN.sh --non-interactive install --systemd-health-backoff exponential --systemd-health-jitter 1`
Run install with explicit startup fallback policy:
`./setupPVPN.sh --non-interactive install --systemd-fallback-mode systemd-only`
Run install with optional systemd unit hardening:
`./setupPVPN.sh --non-interactive install --systemd-unit-hardening basic`
Run sanity-check command mode only:
`./setupPVPN.sh --sanity-check`
Run status dashboard in non-interactive JSON mode:
`./setupPVPN.sh --non-interactive status`
Run install with split tunnel exclusions:
`./setupPVPN.sh --non-interactive install --exclude-ip 192.168.1.10 --exclude-cidr 10.0.0.0/24`
Run install interactively but still force machine telemetry output:
`./setupPVPN.sh --ci-json`
Expected CI parse lines include:
`CI_JSON: {"would_uninstall_packages":"yes"}` (dry-run) or `CI_JSON: {"uninstall_packages":"yes"}` (normal run)
Consolidated parse line:
`CI_JSON: {"action":"uninstall","dry_run":true,"non_interactive":true,"assume_yes":false,"force_disable_kill_switch":true,"uninstall_packages_decision":"no","kill_switch_was_enabled":true,"kill_switch_disabled_for_uninstall":true}`
Global exit parse line (all actions):
`CI_JSON: {\"action\":\"install\",\"success\":true,\"dry_run\":false,\"non_interactive\":true,\"assume_yes\":false,\"force_disable_kill_switch\":false,\"uninstall_packages_decision\":\"no\",\"purge_config_decision\":\"no\",\"kill_switch_was_enabled\":false,\"kill_switch_disabled_for_uninstall\":false}`
Global exit parse line with connect fields:
`CI_JSON: {"action":"install","success":true,"dry_run":false,"non_interactive":true,"assume_yes":false,"force_disable_kill_switch":false,"connect_mode":"country","connect_country":"US","uninstall_packages_decision":"no","purge_config_decision":"no","kill_switch_was_enabled":false,"kill_switch_disabled_for_uninstall":false}`
Global exit parse line with retry fields:
`CI_JSON: {"action":"install","success":true,"dry_run":false,"non_interactive":true,"assume_yes":false,"force_disable_kill_switch":false,"connect_mode":"fastest","connect_country":"","connect_retry_count":"3","connect_retry_delay":"10","uninstall_packages_decision":"no","purge_config_decision":"no","kill_switch_was_enabled":false,"kill_switch_disabled_for_uninstall":false}`
Global exit parse line with systemd health fields:
`CI_JSON: {\"action\":\"install\",\"success\":true,\"dry_run\":false,\"non_interactive\":true,\"assume_yes\":false,\"force_disable_kill_switch\":false,\"connect_mode\":\"default\",\"connect_country\":\"\",\"connect_retry_count\":\"1\",\"connect_retry_delay\":\"5\",\"systemd_health_retries\":\"3\",\"systemd_health_delay\":\"2\",\"uninstall_packages_decision\":\"no\",\"purge_config_decision\":\"no\",\"kill_switch_was_enabled\":false,\"kill_switch_disabled_for_uninstall\":false}`
Status parse line:
`STATUS_JSON: {"service_state":"active","vpn_state":"connected","server":"SE#12","vpn_ip":"10.2.0.5","public_ip":"203.0.113.20","kill_switch_enabled":true}`
Status parse line with startup policy fields:
`STATUS_JSON: {\"service_state\":\"active\",\"vpn_state\":\"connected\",\"server\":\"SE#12\",\"vpn_ip\":\"10.2.0.5\",\"public_ip\":\"203.0.113.20\",\"kill_switch_enabled\":true,\"systemd_health_retries\":\"3\",\"systemd_health_delay\":\"2\",\"systemd_health_backoff\":\"fixed\",\"systemd_health_jitter_max\":\"0\",\"systemd_fallback_mode\":\"auto\",\"systemd_unit_hardening\":\"off\",\"last_startup_failure_present\":false}`

First-time account setup:
`protonvpn signin`

Run all safeguards:
`./tests/regression/run-regressions.sh`
