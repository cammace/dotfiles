#!/usr/bin/env bash
# syncthing-setup.sh - private settings sync between Cam's Macs.
#
#   ~/syncthing-setup.sh [--dry-run]                   private options + the folder
#   ~/syncthing-setup.sh pair <device-id> [address...] trust the other Mac, share the folder
#   ~/syncthing-setup.sh link [--dry-run]              link synced files into place
#
# One Syncthing folder, ~/Sync/mac-settings, carries what this public repo must
# not: iTerm2's settings plist, ~/.ssh/config, the .pub keys and private helper
# scripts. The Macs talk to each other directly over the LAN or a tailnet:
# global discovery, relays and NAT traversal are off, so no Syncthing server
# learns about them. Without global discovery a peer is found by LAN broadcast
# or by the addresses given to `pair` (tcp://<tailnet-ip>:22000).
# Staggered versioning keeps old copies in .stversions, so a bad edit or a
# delete can be undone.
#
# Sync is one-way: the laptop sends, the server only receives. The mini has
# FileVault off and logs in by itself, and ssh runs bin/homelab-direct on every
# connection; a two-way folder would let anyone at the mini's desk run code on
# the laptop. For two-way, set MAC_SETTINGS_FOLDER_TYPE=sendreceive on both Macs
# and re-run. The role comes from ~/.config/machine-role (missing = laptop).
#
# Layout of ~/Sync/mac-settings and where `link` points each file:
#   iTerm2/             read by iTerm2 itself (bootstrap.sh sets the folder)
#   ssh/config, *.pub   -> ~/.ssh/
#   bin/*               -> ~/.local/bin/
# `link` never replaces a real file that differs from the synced copy; it
# warns and leaves it. An identical file is swapped for the link atomically.
# Every step is idempotent, so a re-run is safe.
set -euo pipefail

FOLDER_ID=mac-settings
ROLE_FILE="$HOME/.config/machine-role"
ROLE=laptop
[ -r "$ROLE_FILE" ] && ROLE="$(tr -d '[:space:]' < "$ROLE_FILE")"
case "$ROLE" in
  server) FOLDER_TYPE="${MAC_SETTINGS_FOLDER_TYPE:-receiveonly}" ;;
  *)      FOLDER_TYPE="${MAC_SETTINGS_FOLDER_TYPE:-sendonly}" ;;
esac
SYNC_DIR="$HOME/Sync/$FOLDER_ID"
DRY_RUN=0
CMD=setup
case "${1:-}" in
  pair|link) CMD="$1"; shift ;;
  -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
if [ "${1:-}" = --dry-run ]; then DRY_RUN=1; shift; fi

run() {
  printf '  + %s\n' "$*"
  [ "$DRY_RUN" -eq 1 ] && return 0
  "$@"
}
st() { run syncthing cli "$@"; }
my_id() { if [ "$DRY_RUN" -eq 1 ]; then echo '<device-id>'; else syncthing device-id; fi; }

need_syncthing() {
  command -v syncthing >/dev/null 2>&1 || { echo "syncthing not found (brew bundle)" >&2; exit 1; }
  [ "$DRY_RUN" -eq 1 ] && return 0
  # The brew service may still be starting; the cli needs its REST API.
  for _ in $(seq 1 30); do
    syncthing cli show system >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "syncthing is not running; start it with: brew services start syncthing" >&2
  exit 1
}

case "$CMD" in
setup)
  need_syncthing
  st config options global-ann-enabled set false
  st config options relays-enabled set false
  st config options natenabled set false
  st config options uraccepted set -- -1
  run mkdir -p "$SYNC_DIR"
  if [ "$DRY_RUN" -eq 0 ] && syncthing cli config folders list | grep -qx "$FOLDER_ID"; then
    echo "  folder $FOLDER_ID already exists"
  else
    st config folders add --id "$FOLDER_ID" --label "Mac settings" --path "$SYNC_DIR"
  fi
  # Set on every run, not only at creation, so an existing folder converges.
  st config folders "$FOLDER_ID" type set "$FOLDER_TYPE"
  st config folders "$FOLDER_ID" versioning type set staggered
  echo "  this Mac's device ID: $(my_id)"
  ;;
pair)
  [ $# -ge 1 ] || { echo "usage: $0 pair <device-id> [address...]" >&2; exit 2; }
  peer="$1"; shift
  addrs=("${@:-dynamic}")
  need_syncthing
  if [ "$DRY_RUN" -eq 0 ] && syncthing cli config devices list | grep -qx "$peer"; then
    echo "  device already known"
  else
    # One --addresses flag per address: a comma-joined value is stored as a
    # single, unusable address.
    addr_flags=()
    for a in "${addrs[@]}"; do addr_flags+=(--addresses "$a"); done
    st config devices add --device-id "$peer" "${addr_flags[@]}"
  fi
  if [ "$DRY_RUN" -eq 0 ] && syncthing cli config folders "$FOLDER_ID" devices list | grep -qx "$peer"; then
    echo "  folder already shared with it"
  else
    st config folders "$FOLDER_ID" devices add --device-id "$peer"
  fi
  echo "  run the same on the other Mac with this Mac's ID: $(my_id)"
  ;;
link)
  [ -d "$SYNC_DIR" ] || { echo "  $SYNC_DIR not found; run $0 first and pair" >&2; exit 1; }
  rc=0
  link_one() {
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      return 0
    elif [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
      run mkdir -p "$(dirname "$dst")"
      run ln -s "$src" "$dst"
    elif [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      # Same bytes: swap in the link atomically, so a running ssh never sees no config.
      run ln -s "$src" "$dst.syncthing-link.$$"
      run mv -f "$dst.syncthing-link.$$" "$dst"
    else
      echo "  WARN: $dst differs from $src; left alone (diff them, keep one, re-run)" >&2
      rc=1
    fi
  }
  shopt -s nullglob
  [ -f "$SYNC_DIR/ssh/config" ] && link_one "$SYNC_DIR/ssh/config" "$HOME/.ssh/config"
  for f in "$SYNC_DIR"/ssh/*.pub; do link_one "$f" "$HOME/.ssh/$(basename "$f")"; done
  for f in "$SYNC_DIR"/bin/*; do link_one "$f" "$HOME/.local/bin/$(basename "$f")"; done
  exit "$rc"
  ;;
esac
