#!/usr/bin/env bash
# bootstrap.sh - set up a Mac from this dotfiles repo. Idempotent: safe to re-run.
#
# New Mac (HTTPS, no SSH key needed):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/cammace/dotfiles/main/bootstrap.sh)" \
#     bootstrap --role server
#
# Prefer that form to `curl ... | bash`: it keeps stdin on the terminal, so the
# Homebrew installer and cask installs can ask for the sudo password. Under a
# pipe, the in_tty helper below reattaches them to /dev/tty instead.
#
# Usage: bootstrap.sh [--role laptop|server] [--dry-run] [--branch NAME]
#                     [--repo URL|PATH] [--skip-network]
#
#   --role          Writes ~/.config/machine-role. Required when that file is
#                   missing; otherwise the existing role is kept.
#   --dry-run       Print every action, change nothing.
#   --branch        Branch to check out (default: main, or $DOTFILES_BRANCH).
#   --repo          Clone source (default: the public HTTPS URL, or
#                   $DOTFILES_REPO). A local path works, for tests.
#   --skip-network  Skip the network installs: Xcode CLT, Homebrew, brew
#                   bundle, Oh My Zsh, its plugins and TPM. For tests.
#
# Steps, in order: Xcode Command Line Tools, Homebrew, bare clone into ~/.cfg,
# checkout (conflicting files go to ~/.cfg-backup/<timestamp>/),
# status.showUntrackedFiles=no, ~/.config/machine-role, brew bundle (Brewfile,
# then Brewfile.<role>), Oh My Zsh + custom plugins + TPM, manual next steps.
#
# Sudo-only server settings live in macos-server.sh, which this never runs.
#
# Written for the stock /bin/bash 3.2: no mapfile, no ${x,,}, and no empty
# arrays under set -u.
set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/cammace/dotfiles.git}"
BRANCH="${DOTFILES_BRANCH:-main}"
ROLE=""
DRY_RUN=0
SKIP_NETWORK="${DOTFILES_SKIP_NETWORK:-0}"

GIT_DIR_CFG="$HOME/.cfg"
ROLE_FILE="$HOME/.config/machine-role"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.cfg-backup/$STAMP"
WARNINGS=""

say()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; WARNINGS="${WARNINGS}  - $*
"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Print a command; run it unless --dry-run.
run() {
  printf '  + %s\n' "$*"
  [ "$DRY_RUN" -eq 1 ] && return 0
  "$@"
}

# Run a command that may prompt (sudo password) with stdin on the terminal.
# Under `curl | bash` stdin is the script itself: an installer reading it would
# swallow the rest of this file, and Homebrew refuses sudo without a TTY.
in_tty() {
  if [ ! -t 0 ] && (: < /dev/tty) 2>/dev/null; then
    "$@" < /dev/tty
  else
    "$@"
  fi
}

cfg() { git --git-dir="$GIT_DIR_CFG" --work-tree="$HOME" "$@"; }

usage() {
  # Under `bash -c` or a pipe there is no file to read the header from.
  if [ -f "${BASH_SOURCE[0]:-}" ]; then
    sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  else
    echo "Usage: bootstrap.sh [--role laptop|server] [--dry-run] [--branch NAME] [--repo URL|PATH] [--skip-network]"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --role)         [ $# -ge 2 ] || die "--role needs laptop or server"; ROLE="$2"; shift 2 ;;
    --role=*)       ROLE="${1#--role=}"; shift ;;
    --branch)       [ $# -ge 2 ] || die "--branch needs a name"; BRANCH="$2"; shift 2 ;;
    --branch=*)     BRANCH="${1#--branch=}"; shift ;;
    --repo)         [ $# -ge 2 ] || die "--repo needs a URL or path"; REPO="$2"; shift 2 ;;
    --repo=*)       REPO="${1#--repo=}"; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --skip-network) SKIP_NETWORK=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "unknown argument: $1 (try --help)" ;;
  esac
done

# Decide the role before touching anything, so a missing --role fails early.
case "$ROLE" in
  laptop|server) ;;
  "")
    if [ -r "$ROLE_FILE" ]; then
      ROLE="$(tr -d '[:space:]' < "$ROLE_FILE")"
      case "$ROLE" in laptop|server) ;; *) die "$ROLE_FILE holds '$ROLE'; pass --role laptop|server" ;; esac
    else
      die "--role laptop|server is required on a fresh machine ($ROLE_FILE is missing)"
    fi ;;
  *) die "--role must be laptop or server, not '$ROLE'" ;;
esac

[ "$(uname -s)" = Darwin ] || die "this bootstrap is for macOS"
if [ "$(uname -m)" = arm64 ]; then BREW_PREFIX=/opt/homebrew; else BREW_PREFIX=/usr/local; fi
BREW="$BREW_PREFIX/bin/brew"

say "role=$ROLE branch=$BRANCH repo=$REPO dry_run=$DRY_RUN skip_network=$SKIP_NETWORK"

# --- 1. Xcode Command Line Tools --------------------------------------------
say "Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  echo "  already installed ($(xcode-select -p))"
elif [ "$SKIP_NETWORK" = 1 ]; then
  echo "  missing; skipped (--skip-network)"
elif [ -n "${SSH_CONNECTION:-}" ]; then
  # The xcode-select dialog appears on the console, which nobody sees over SSH.
  # The Homebrew installer in step 2 installs the CLT headlessly instead.
  echo "  missing; over SSH, so the Homebrew installer (next step) will install them"
else
  run xcode-select --install || true
  if [ "$DRY_RUN" -eq 0 ]; then
    echo "  finish the installer dialog; waiting up to 30 min..."
    i=0
    until xcode-select -p >/dev/null 2>&1; do
      i=$((i + 1)); [ "$i" -le 180 ] || die "Command Line Tools still missing; install them and re-run"
      sleep 10
    done
  fi
fi

# --- 2. Homebrew -------------------------------------------------------------
say "Homebrew"
if [ -x "$BREW" ]; then
  echo "  already installed ($BREW)"
elif [ "$SKIP_NETWORK" = 1 ]; then
  echo "  missing; skipped (--skip-network)"
else
  # shellcheck disable=SC2016  # printed literally, not expanded
  printf '  + /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n'
  if [ "$DRY_RUN" -eq 0 ]; then
    in_tty /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
fi
# The tracked .zprofile evals `brew shellenv` for login shells; this does the
# same for the rest of this script.
if [ "$DRY_RUN" -eq 0 ] && [ "$SKIP_NETWORK" != 1 ] && [ -x "$BREW" ]; then
  eval "$("$BREW" shellenv)"
else
  echo "  + eval \"\$($BREW shellenv)\""
fi

# --- 3. Bare clone -----------------------------------------------------------
say "Dotfiles repo ($GIT_DIR_CFG)"
command -v git >/dev/null 2>&1 || [ "$DRY_RUN" -eq 1 ] || die "git not found; install the Command Line Tools and re-run"
if [ -d "$GIT_DIR_CFG" ]; then
  # Ask without --work-tree: with one, rev-parse always answers false.
  [ "$(git --git-dir="$GIT_DIR_CFG" rev-parse --is-bare-repository 2>/dev/null)" = true ] \
    || die "$GIT_DIR_CFG exists but is not a bare git repo; move it aside and re-run"
  echo "  already cloned"
else
  run git clone --bare --branch "$BRANCH" "$REPO" "$GIT_DIR_CFG"
  # A bare clone has no fetch refspec, so later fetches would not update
  # origin/* without this.
  run git --git-dir="$GIT_DIR_CFG" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
fi

# --- 4. Checkout, backing up conflicts first ---------------------------------
say "Checkout"
if [ "$DRY_RUN" -eq 1 ] && [ ! -d "$GIT_DIR_CFG" ]; then
  echo "  would move existing files that the repo tracks to $BACKUP_DIR/, then check out $BRANCH"
elif [ -n "$(cfg ls-files 2>/dev/null | head -1)" ]; then
  # A populated index means an earlier run already checked out. Leave the work
  # tree alone so local edits are never touched on a re-run.
  echo "  already checked out (branch: $(cfg symbolic-ref --short -q HEAD || echo detached)); leaving the work tree alone"
else
  moved=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -e "$HOME/$path" ] || [ -L "$HOME/$path" ]; then
      run mkdir -p "$(dirname "$BACKUP_DIR/$path")"
      run mv "$HOME/$path" "$BACKUP_DIR/$path"
      moved=$((moved + 1))
    fi
  done < <(cfg ls-tree -r --name-only "$BRANCH")
  [ "$moved" -eq 0 ] || echo "  backed up $moved existing file(s) to $BACKUP_DIR/"
  # With an empty index, checking out the branch writes every tracked file.
  run git --git-dir="$GIT_DIR_CFG" --work-tree="$HOME" checkout "$BRANCH"
fi

# --- 5. Hide untracked files -------------------------------------------------
say "status.showUntrackedFiles"
if [ -d "$GIT_DIR_CFG" ] && [ "$(cfg config --get status.showUntrackedFiles 2>/dev/null || true)" = no ]; then
  echo "  already no"
else
  run git --git-dir="$GIT_DIR_CFG" config status.showUntrackedFiles no
fi

# --- 6. Machine role ---------------------------------------------------------
say "Machine role ($ROLE_FILE)"
current_role=""
[ -r "$ROLE_FILE" ] && current_role="$(tr -d '[:space:]' < "$ROLE_FILE")"
if [ "$current_role" = "$ROLE" ]; then
  echo "  already $ROLE"
else
  [ -z "$current_role" ] || echo "  changing $current_role -> $ROLE"
  run mkdir -p "$(dirname "$ROLE_FILE")"
  printf '  + echo %s > %s\n' "$ROLE" "$ROLE_FILE"
  [ "$DRY_RUN" -eq 1 ] || printf '%s\n' "$ROLE" > "$ROLE_FILE"
fi

# --- 7. Homebrew bundle ------------------------------------------------------
say "brew bundle (Brewfile, Brewfile.$ROLE)"
if [ "$SKIP_NETWORK" = 1 ]; then
  echo "  skipped (--skip-network)"
else
  for bf in "$HOME/Brewfile" "$HOME/Brewfile.$ROLE"; do
    if [ ! -f "$bf" ] && [ "$DRY_RUN" -eq 0 ]; then
      warn "$bf not found; skipped"
      continue
    fi
    # One stale or App Store item must not abort the whole bootstrap.
    run in_tty env HOMEBREW_BUNDLE_NO_UPGRADE=1 "$BREW" bundle --file="$bf" \
      || warn "brew bundle --file=$bf reported failures; re-run after fixing them"
  done
fi

# --- 8. Oh My Zsh, its custom plugins, TPM -----------------------------------
say "Oh My Zsh"
ZSH_DIR="$HOME/.oh-my-zsh"
if ! grep -q 'oh-my-zsh' "$HOME/.zshrc" 2>/dev/null && [ "$DRY_RUN" -eq 0 ]; then
  echo "  .zshrc does not use Oh My Zsh; skipped"
elif [ -d "$ZSH_DIR" ]; then
  echo "  already installed"
elif [ "$SKIP_NETWORK" = 1 ]; then
  echo "  missing; skipped (--skip-network)"
else
  # KEEP_ZSHRC=yes keeps the tracked .zshrc; RUNZSH/CHSH=no keep it unattended.
  # shellcheck disable=SC2016  # printed literally, not expanded
  printf '  + RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended\n'
  if [ "$DRY_RUN" -eq 0 ]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
      || warn "Oh My Zsh install failed"
  fi
fi

# Plugins .zshrc loads that are not part of Oh My Zsh itself. Without
# evalcache, pyenv/jenv/starship/zoxide never initialise.
say "Oh My Zsh custom plugins"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$ZSH_DIR/custom}"
for spec in \
  "evalcache https://github.com/mroth/evalcache" \
  "fzf-tab https://github.com/Aloxaf/fzf-tab" \
  "you-should-use https://github.com/MichaelAquilina/zsh-you-should-use.git" \
  "zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git" \
  "fast-syntax-highlighting https://github.com/zdharma-continuum/fast-syntax-highlighting"
do
  name="${spec%% *}"; url="${spec#* }"
  dest="$ZSH_CUSTOM_DIR/plugins/$name"
  if [ -d "$dest" ]; then
    echo "  $name: already present"
  elif [ "$SKIP_NETWORK" = 1 ]; then
    echo "  $name: missing; skipped (--skip-network)"
  else
    run git clone --depth 1 "$url" "$dest" || warn "could not clone $name"
  fi
done

say "TPM (tmux plugin manager)"
TPM_DIR="$HOME/.tmux/plugins/tpm"
if ! grep -q 'tmux-plugins/tpm' "$HOME/.tmux.conf" 2>/dev/null && [ "$DRY_RUN" -eq 0 ]; then
  echo "  .tmux.conf does not use TPM; skipped"
elif [ -d "$TPM_DIR" ]; then
  echo "  already installed"
elif [ "$SKIP_NETWORK" = 1 ]; then
  echo "  missing; skipped (--skip-network)"
else
  run git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" || warn "could not clone TPM"
  if [ -x "$TPM_DIR/bin/install_plugins" ] && command -v tmux >/dev/null 2>&1; then
    run "$TPM_DIR/bin/install_plugins" || warn "TPM plugin install failed; press prefix + I inside tmux"
  fi
fi

# --- 9. Manual next steps ----------------------------------------------------
say "Done$([ "$DRY_RUN" -eq 1 ] && echo ' (dry run: nothing was changed)')"
if [ -n "$WARNINGS" ]; then
  printf '\nWarnings:\n%s' "$WARNINGS"
fi
cat <<EOF

Next steps (manual):
  1. Open 1Password, sign in, and turn on Settings > Developer > Use the SSH agent.
  2. gh auth login
  3. tailscale up   (or sign in from the Tailscale app)
  4. Clone the Clio repo and run its ops/bootstrap.sh.
EOF
if [ "$ROLE" = server ]; then
  cat <<EOF
  5. Server settings (sleep, auto-restart, wake on LAN, Remote Login, Screen
     Sharing, hostname). Read it first, then:  sudo ~/macos-server.sh <hostname>
  6. Open a new shell (exec zsh -l) so the role switch takes effect.
EOF
else
  echo "  5. Open a new shell (exec zsh -l)."
fi
