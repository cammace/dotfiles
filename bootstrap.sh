#!/usr/bin/env bash
# bootstrap.sh - set up a Mac from this dotfiles repo. Idempotent: safe to re-run.
#
# New Mac (HTTPS, no SSH key needed):
#   curl -fsSLo /tmp/bootstrap.sh https://raw.githubusercontent.com/cammace/dotfiles/main/bootstrap.sh \
#     && bash /tmp/bootstrap.sh --role server
#
# Prefer that form to `curl ... | bash` or `bash -c "$(curl ...)"`: a failed
# download stops at curl instead of running an empty script that exits 0, and
# stdin stays on the terminal so the Homebrew installer can ask for the sudo
# password. Under a pipe, the in_tty helper below reattaches installers to
# /dev/tty.
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
LOCAL_GITCONFIG="$HOME/.config/git/local.gitconfig"
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
  if [ -t 0 ]; then
    "$@"
  elif (: < /dev/tty) 2>/dev/null; then
    "$@" < /dev/tty
  else
    "$@" < /dev/null
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
    if [ -f "$ROLE_FILE" ] && [ -r "$ROLE_FILE" ]; then
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
    # Download first: `bash -c "$(curl ...)"` runs an empty script and exits 0
    # when curl fails.
    brew_installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "could not download the Homebrew installer"
    in_tty /bin/bash -c "$brew_installer" || die "the Homebrew installer failed"
    [ -x "$BREW" ] || die "Homebrew installer finished but $BREW is missing"
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
  current_branch="$(cfg symbolic-ref --short -q HEAD || echo detached)"
  echo "  already checked out (branch: $current_branch); leaving the work tree alone"
  [ "$current_branch" = "$BRANCH" ] \
    || warn "--branch $BRANCH ignored: the existing checkout is on $current_branch (switch with: git --git-dir=$GIT_DIR_CFG --work-tree=$HOME switch $BRANCH)"
else
  moved=0
  # Move aside whatever is in the way of a tracked path: the path itself, or
  # a parent that is a file or a symlink (git will not write through either).
  # `planned` stops a dry run, where nothing actually moves, from listing a
  # blocking parent once per tracked file under it.
  planned=""
  backup_one() {
    case "
$planned
" in *"
$1
"*) return 0 ;; esac
    run mkdir -p "$(dirname "$BACKUP_DIR/$1")"
    run mv "$HOME/$1" "$BACKUP_DIR/$1"
    planned="$planned
$1"
    moved=$((moved + 1))
  }
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    blocked=""
    prefix=""
    rest="$path"
    while [ "${rest#*/}" != "$rest" ]; do
      prefix="${prefix:+$prefix/}${rest%%/*}"
      rest="${rest#*/}"
      if [ -L "$HOME/$prefix" ] || { [ -e "$HOME/$prefix" ] && [ ! -d "$HOME/$prefix" ]; }; then
        blocked="$prefix"
        break
      fi
    done
    if [ -n "$blocked" ]; then
      backup_one "$blocked"
    elif [ -e "$HOME/$path" ] || [ -L "$HOME/$path" ]; then
      backup_one "$path"
    fi
  done < <(cfg ls-tree -r --name-only "$BRANCH")
  if [ "$moved" -gt 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then echo "  would back up $moved path(s) to $BACKUP_DIR/"
    else echo "  backed up $moved path(s) to $BACKUP_DIR/"; fi
  fi
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
[ -f "$ROLE_FILE" ] && [ -r "$ROLE_FILE" ] && current_role="$(tr -d '[:space:]' < "$ROLE_FILE")"
if [ "$current_role" = "$ROLE" ]; then
  echo "  already $ROLE"
else
  [ -z "$current_role" ] || echo "  changing $current_role -> $ROLE"
  run mkdir -p "$(dirname "$ROLE_FILE")"
  printf '  + echo %s > %s\n' "$ROLE" "$ROLE_FILE"
  [ "$DRY_RUN" -eq 1 ] || printf '%s\n' "$ROLE" > "$ROLE_FILE"
fi

# --- 6b. Machine-local git overrides ----------------------------------------
# .gitconfig ends with an include of this untracked file. The tracked editor
# (zed --wait) does not exist on a headless server, so the server gets nano.
# Never overwritten: once it exists it is the machine's to edit.
say "Machine-local git config ($LOCAL_GITCONFIG)"
if [ -e "$LOCAL_GITCONFIG" ]; then
  echo "  already present; leaving it alone"
elif [ "$ROLE" = server ]; then
  run mkdir -p "$(dirname "$LOCAL_GITCONFIG")"
  printf '  + write %s (core.editor = nano)\n' "$LOCAL_GITCONFIG"
  if [ "$DRY_RUN" -eq 0 ]; then
    cat > "$LOCAL_GITCONFIG" <<'GITCONFIG'
# Machine-local git overrides for this server. Written once by bootstrap.sh;
# not tracked, never overwritten. Included last from ~/.gitconfig, so it wins
# over `git config --global` writes too: change settings here, not there.
[core]
	editor = nano
# Commit signing still goes through the 1Password app (op-ssh-sign), which
# stalls while 1Password is locked. To sign with an on-disk key instead, add
# a [user] signingkey and a [gpg "ssh"] program here.
GITCONFIG
  fi
else
  echo "  none needed for $ROLE"
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

# --- 7b. OrbStack (Docker on both roles) --------------------------------------
# The orbstack cask is in the common Brewfile. Its first start installs the
# Docker socket and CLI links (it may ask for the admin password) and switches
# the docker context to `orbstack`. It also adds one `source
# ~/.orbstack/shell/init.zsh` line to .zprofile, which the repo already tracks.
# The perl alarm stops a first start that waits on a GUI prompt nobody sees.
say "OrbStack"
if [ "$SKIP_NETWORK" = 1 ]; then
  echo "  skipped (--skip-network)"
elif [ "$DRY_RUN" -eq 1 ]; then
  echo "  + orbctl start"
elif ! command -v orbctl >/dev/null 2>&1; then
  warn "orbctl not found: the orbstack cask did not install; check the brew bundle output above"
elif orbctl status 2>/dev/null | grep -qi '^running'; then
  echo "  already running"
else
  run in_tty perl -e 'alarm 300; exec @ARGV' orbctl start \
    || warn "orbctl start failed or took over 5 min; open OrbStack once (Screen Sharing) to finish its setup"
fi

# --- 8. Oh My Zsh, its custom plugins, TPM -----------------------------------
say "Oh My Zsh"
ZSH_DIR="$HOME/.oh-my-zsh"
if ! grep -q 'oh-my-zsh' "$HOME/.zshrc" 2>/dev/null && [ "$DRY_RUN" -eq 0 ]; then
  echo "  .zshrc does not use Oh My Zsh; skipped"
elif [ -f "$ZSH_DIR/oh-my-zsh.sh" ]; then
  echo "  already installed"
elif [ -d "$ZSH_DIR" ]; then
  warn "$ZSH_DIR exists but has no oh-my-zsh.sh (a broken install); move it aside and re-run"
elif [ "$SKIP_NETWORK" = 1 ]; then
  echo "  missing; skipped (--skip-network)"
else
  # KEEP_ZSHRC=yes keeps the tracked .zshrc; RUNZSH/CHSH=no keep it unattended.
  # shellcheck disable=SC2016  # printed literally, not expanded
  printf '  + RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended\n'
  if [ "$DRY_RUN" -eq 0 ]; then
    if omz_installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
      RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$omz_installer" "" --unattended </dev/null \
        || warn "Oh My Zsh install failed"
    else
      warn "could not download the Oh My Zsh installer"
    fi
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
  elif [ "$DRY_RUN" -eq 0 ] && [ ! -f "$ZSH_DIR/oh-my-zsh.sh" ]; then
    # Cloning into a missing Oh My Zsh would create ~/.oh-my-zsh, and the
    # installer refuses to run over an existing directory on the next try.
    echo "  $name: skipped (Oh My Zsh is not installed)"
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

# --- 9. Shell smoke test -----------------------------------------------------
# Start the shell the way a new terminal would and report anything it prints
# on stderr. SSH_CONNECTION and TMUX are dropped so the SSH-login tmux picker
# stays out of it; perl's alarm caps a hang (a wedged op read, say) at 60 s.
# stderr goes to a file, not a pipe: a child that outlives the killed zsh would
# hold a pipe open and make the capture wait for it, defeating the cap.
say "Shell smoke test (zsh -i)"
if [ "$DRY_RUN" -eq 1 ] || [ "$SKIP_NETWORK" = 1 ]; then
  echo "  skipped ($([ "$DRY_RUN" -eq 1 ] && echo dry run || echo --skip-network): the shell needs the installs above)"
elif ! command -v zsh >/dev/null 2>&1; then
  warn "zsh not found; skipped the shell smoke test"
else
  smoke_rc=0
  smoke_log="$(mktemp -t bootstrap-smoke)"
  env -u SSH_CONNECTION -u TMUX perl -e 'alarm 60; exec @ARGV' \
    zsh -i -c 'exit 0' >/dev/null 2>"$smoke_log" </dev/null || smoke_rc=$?
  # A shell with no terminal always says this about zle; it is not an error.
  smoke_err="$(grep -v "can't change option: zle" "$smoke_log" | sed '/^$/d' || true)"
  if [ "$smoke_rc" -eq 0 ] && [ -z "$smoke_err" ]; then
    echo "  ok: a new zsh starts cleanly"
  else
    [ "$smoke_rc" -ne 14 ] || smoke_rc="14 (timed out after 60 s)"
    warn "a new zsh exited $smoke_rc or printed errors; first lines:
$(printf '%s\n' "$smoke_err" | head -10 | sed 's/^/      /')"
  fi
fi

# --- 10. Manual next steps ---------------------------------------------------
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
  6. OrbStack, Ollama and every LaunchAgent run only inside a logged-in user
     session. For them to come back after a power cut, turn on automatic login
     (System Settings > Users & Groups; needs FileVault off). OrbStack cannot
     update itself without its GUI: brew upgrade --greedy orbstack
  7. Open a new shell (exec zsh -l) so the role switch takes effect.
EOF
else
  echo "  5. Open a new shell (exec zsh -l)."
fi
