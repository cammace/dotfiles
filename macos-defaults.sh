#!/usr/bin/env bash
# macos-defaults.sh - per-user macOS defaults. No sudo: run it as the login user.
#
#   ~/macos-defaults.sh [--dry-run] [--role laptop|server]
#
# The role comes from ~/.config/machine-role (bootstrap.sh writes it); a
# missing file means laptop, as in .zshrc. The common settings match the
# MacBook's current values, so a laptop run changes nothing. Server settings:
#   - no screen saver, no crash dialogs on the console
#   - App Nap off, so windowless GUI apps that serve jobs stay responsive
#   - no .DS_Store files on network shares
#   - Time Machine skips ~/.m2; OrbStack starts at login, its data skips backups
# System-wide settings (updates, restart after a freeze) need sudo and live in
# macos-server.sh. Every step is idempotent, so a re-run is safe.
set -euo pipefail

ROLE_FILE="$HOME/.config/machine-role"
DRY_RUN=0
ROLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --role)    [ $# -ge 2 ] || { echo "--role needs laptop or server" >&2; exit 2; }; ROLE="$2"; shift 2 ;;
    --role=*)  ROLE="${1#--role=}"; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ "$(uname -s)" = Darwin ] || { echo "macOS only" >&2; exit 1; }
if [ "$(id -u)" -eq 0 ]; then
  echo "run as the login user, not sudo: defaults under sudo writes root's preferences" >&2
  exit 1
fi
if [ -z "$ROLE" ]; then
  ROLE=laptop
  [ -r "$ROLE_FILE" ] && ROLE="$(tr -d '[:space:]' < "$ROLE_FILE")"
fi
case "$ROLE" in laptop|server) ;; *) echo "role must be laptop or server, not '$ROLE'" >&2; exit 2 ;; esac

run() {
  printf '  + %s\n' "$*"
  [ "$DRY_RUN" -eq 1 ] && return 0
  "$@"
}

echo "==> role=$ROLE dry_run=$DRY_RUN"

echo "==> Finder and screenshots (both roles; matches the MacBook)"
run defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
run defaults write com.apple.finder NewWindowTarget -string PfHm
run defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
run defaults write com.apple.finder WarnOnEmptyTrash -bool false
run defaults write com.apple.screencapture show-thumbnail -bool false

echo "==> Siri: hide the menu and the voice trigger; Apple Intelligence stays on (/usr/bin/fm needs it)"
run defaults write com.apple.Siri StatusMenuVisible -bool false
run defaults write com.apple.Siri VoiceTriggerUserEnabled -bool false

echo "==> Time Machine: skip caches and model stores (sticky; no sudo for paths you own)"
for p in "$HOME/.gradle" "$HOME/.ollama" "$HOME/Library/Caches"; do
  if [ -e "$p" ]; then run tmutil addexclusion "$p"; fi
done

if [ "$ROLE" = server ]; then
  echo "==> Server: no screen saver"
  run defaults -currentHost write com.apple.screensaver idleTime -int 0

  echo "==> Server: no crash dialogs (reports still go to ~/Library/Logs/DiagnosticReports)"
  run defaults write com.apple.CrashReporter DialogType -string none

  echo "==> Server: App Nap off"
  run defaults write NSGlobalDomain NSAppSleepDisabled -bool true

  echo "==> Server: no .DS_Store on network shares"
  run defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  echo "==> Server: Time Machine also skips ~/.m2"
  if [ -e "$HOME/.m2" ]; then run tmutil addexclusion "$HOME/.m2"; fi

  echo "==> Server: OrbStack"
  # Set only on a mismatch: a config change may restart the engine and bounce
  # running containers, so a re-run must not touch keys that are already right.
  if command -v orbctl >/dev/null 2>&1; then
    orb_cfg="$(orbctl config show 2>/dev/null || true)"
    for kv in app.start_at_login=true data_allow_backup=false; do
      k="${kv%%=*}"; v="${kv#*=}"
      if printf '%s\n' "$orb_cfg" | grep -Fqx "$k: $v"; then
        echo "  already $k: $v"
      else
        run orbctl config set "$k" "$v"
      fi
    done
  else
    echo "  orbctl not found; skipped"
  fi
fi

echo "==> Reloading Finder and cfprefsd so the new values load"
run killall Finder 2>/dev/null || true
run killall cfprefsd 2>/dev/null || true
echo "==> Done. Log out and back in for the App Nap and screen saver keys to apply everywhere."
