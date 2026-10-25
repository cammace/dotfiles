#!/usr/bin/env bash
# macos-server.sh - macOS settings for the headless, always-on Mac mini.
# Needs sudo. bootstrap.sh never runs this; read it, then run it by hand:
#
#   sudo ~/macos-server.sh [--dry-run] [<hostname>]
#
# It sets:
#   - power: never sleep (system and disk), restart after a power failure,
#     wake on network access (Wake on LAN)
#   - Remote Login (SSH) on
#   - Screen Sharing on
#   - with <hostname>: ComputerName, HostName and LocalHostName
#
# Every step is idempotent, so a re-run is safe.
set -euo pipefail

DRY_RUN=0
NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) NAME="$1"; shift ;;
  esac
done

[ "$(uname -s)" = Darwin ] || { echo "macOS only" >&2; exit 1; }
if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  echo "run with sudo: sudo $0 $*" >&2
  exit 1
fi

run() {
  printf '  + %s\n' "$*"
  [ "$DRY_RUN" -eq 1 ] && return 0
  "$@"
}

echo "==> Power: never sleep, auto-restart after power loss, wake on LAN"
run pmset -a sleep 0
run pmset -a disksleep 0
run pmset -a autorestart 1
run pmset -a womp 1

echo "==> Remote Login (SSH)"
# systemsetup needs Full Disk Access for the terminal on recent macOS; fall
# back to launchctl, which does not.
if ! run systemsetup -f -setremotelogin on; then
  run launchctl enable system/com.openssh.sshd
  run launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist || true
fi

echo "==> Screen Sharing"
run launchctl enable system/com.apple.screensharing
# bootstrap fails when the service is already loaded; that is fine.
run launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist || true

if [ -n "$NAME" ]; then
  echo "==> Hostname: $NAME"
  run scutil --set ComputerName "$NAME"
  run scutil --set HostName "$NAME"
  run scutil --set LocalHostName "$NAME"
fi

echo "==> Done. Check with: pmset -g; systemsetup -getremotelogin"
