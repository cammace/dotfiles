# uv
export PATH="$HOME/.local/bin:$PATH"

# Server: `ssh <host> <cmd>` runs a non-interactive, non-login zsh that reads
# only this file, so it would miss Homebrew (login shells get it from
# .zprofile). Static exports, no fork: this runs for every zsh on that Mac.
# A missing ~/.config/machine-role means laptop, which skips this block.
if [[ ! -o login && -r "$HOME/.config/machine-role" && "$(<"$HOME/.config/machine-role")" == server* \
      && -d /opt/homebrew/bin && ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
  export HOMEBREW_PREFIX=/opt/homebrew HOMEBREW_CELLAR=/opt/homebrew/Cellar HOMEBREW_REPOSITORY=/opt/homebrew
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
  export MANPATH="${MANPATH:-}:" INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
fi
