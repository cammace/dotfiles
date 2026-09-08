#!/bin/bash
# iTerm2 Semantic History handler
# Routes cmd-clicked files to the right app by extension.
#
# Obsidian branch added 2026-09-07: a markdown note INSIDE the Clio vault opens
# in Obsidian, not Typora. Typora shows the file; Obsidian is the app that has
# the wikilinks, backlinks and graph, so for a vault note it is the correct one.
# Everything outside the vault keeps the old routing.
#
# Set SEMANTIC_OPEN_DRYRUN=1 to print the action instead of performing it.

FILE="$1"
LINE="$2"

# The vault, resolved. ~/Documents/Clio is a symlink to ~/Documents/Clio.nosync,
# so both spellings must land on the same root - compare resolved paths, never
# the literal string iTerm2 happened to pass.
VAULT_ROOT="$HOME/Documents/Clio.nosync/notebook"
VAULT_NAME="notebook"

run() {
  if [[ -n "$SEMANTIC_OPEN_DRYRUN" ]]; then
    printf '%s\n' "$*"
  else
    "$@"
  fi
}

# Resolve to a real absolute path. A relative path is resolved against $PWD.
resolve() {
  python3 - "$1" <<'PY' 2>/dev/null
import os, sys
print(os.path.realpath(os.path.abspath(sys.argv[1])))
PY
}

RESOLVED="$(resolve "$FILE")"
[[ -z "$RESOLVED" ]] && RESOLVED="$FILE"
VAULT_RESOLVED="$(resolve "$VAULT_ROOT")"
[[ -z "$VAULT_RESOLVED" ]] && VAULT_RESOLVED="$VAULT_ROOT"

ext="${RESOLVED##*.}"
ext="${ext,,}" # lowercase

# --- Obsidian: a vault-native file inside the vault ---------------------------
in_vault=0
if [[ "$RESOLVED" == "$VAULT_RESOLVED"/* ]]; then
  in_vault=1
fi

if [[ $in_vault -eq 1 ]]; then
  case "$ext" in
    md|markdown|mdx|canvas|base)
      # Vault-relative path. Strip a markdown extension (Obsidian resolves those
      # without it); keep .canvas and .base, which need theirs.
      REL="${RESOLVED#$VAULT_RESOLVED/}"
      case "$ext" in
        md|markdown|mdx) REL="${REL%.*}" ;;
      esac
      URI="$(python3 - "$VAULT_NAME" "$REL" <<'PY' 2>/dev/null
import sys, urllib.parse
vault, rel = sys.argv[1], sys.argv[2]
print("obsidian://open?vault=%s&file=%s" % (
    urllib.parse.quote(vault, safe=""),
    urllib.parse.quote(rel, safe="/"),
))
PY
)"
      if [[ -n "$URI" ]]; then
        run open "$URI"
        exit 0
      fi
      # URI build failed - fall through to the extension routing below rather
      # than silently doing nothing.
      ;;
  esac
fi

# --- Everything else: route by extension --------------------------------------
case "$ext" in
  # Code files → Zed
  py|js|ts|jsx|tsx|rb|go|rs|c|cpp|h|hpp|java|kt|swift|sh|bash|zsh|yml|yaml|toml|json|css|scss|html|xml|sql|lua|zig|ex|exs|erl|hs|ml|vim|conf|cfg|ini|env|dockerfile|makefile)
    if [[ -n "$LINE" ]]; then
      run open "zed://file${RESOLVED}:${LINE}"
    else
      run open -a "Zed" "$RESOLVED"
    fi
    ;;

  # Markdown outside the vault → Zed (a repo file is code, not prose).
  # Inside the vault it never reaches here - the Obsidian branch above took it.
  md|markdown|mdx)
    if [[ -n "$LINE" ]]; then
      run open "zed://file${RESOLVED}:${LINE}"
    else
      run open -a "Zed" "$RESOLVED"
    fi
    ;;

  # Images → Preview
  png|jpg|jpeg|gif|bmp|tiff|tif|webp|svg|ico|heic|heif)
    run open -a "Preview" "$RESOLVED"
    ;;

  # Fallback → Chrome
  *)
    run open -a "Google Chrome" "$RESOLVED"
    ;;
esac
