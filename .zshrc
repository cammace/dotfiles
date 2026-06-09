###
# START OMZ CONFIG
###

# Disable default theme since Starship is used.
ZSH_THEME=""

# Oh My Zsh Auto-update
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 7

# Docker completions (in fpath before OMZ calls compinit)
fpath=("$HOME/.docker/completions" $fpath)

# Oh My Zsh Plugins
# Order matters: fzf-tab after compinit (OMZ handles this), before autosuggestions/highlighting
plugins=(
  aws
  brew
  npm
  yarn
  pip
  ssh
  extract
  macos
  colored-man-pages
  direnv
  evalcache
  fzf-tab
  you-should-use
  zsh-autosuggestions
  fast-syntax-highlighting
)
# Removed (2026-06-09 audit): kubectl, gradle (0 uses, slow completion),
# docker, docker-compose (redundant — official _docker completion is in fpath above),
# git (its aliases unused; git completion is native to zsh)

# History
HISTSIZE=1000000
SAVEHIST=1000000
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_SAVE_NO_DUPS
setopt HIST_VERIFY

# Load Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
source $ZSH/oh-my-zsh.sh

###
# END OMZ CONFIG
###

# Set default editor (Zed locally, nano over SSH)
if [[ -n "$SSH_CONNECTION" ]]; then
    export EDITOR="nano"
elif command -v zed &>/dev/null; then
    export EDITOR="zed --wait"
else
    export EDITOR="nano"
fi

# 1Password SSH agent (needed for git commit signing via op-ssh-sign)
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock

# Python (pyenv) — cached for fast startup
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
_evalcache pyenv init --path
_evalcache pyenv init -

# Java (jenv) — cached for fast startup
export PATH="$HOME/.jenv/bin:$PATH"
_evalcache jenv init -

# iTerm2 Integration
[[ -f "$HOME/.iterm2_shell_integration.zsh" ]] && source "$HOME/.iterm2_shell_integration.zsh"

# Raise file descriptor limit (Claude Code fails with "unlimited" — needs explicit number)
ulimit -n 65536

# Aliases
alias config="git --git-dir=$HOME/.cfg/ --work-tree=$HOME"
# Expose the dotfiles bare repo to Claude when launched from $HOME — WITHOUT
# exporting GIT_DIR/GIT_WORK_TREE. Those get inherited by every child shell for
# the whole session and hijack git's repo discovery in any OTHER repo Claude
# touches (e.g. ~/Documents/Clio needed `env -u GIT_DIR` to commit). Pass a hint
# var instead; Claude uses `git --git-dir="$CLAUDE_DOTFILES_GIT_DIR"
# --work-tree="$CLAUDE_DOTFILES_WORK_TREE"` (or the `config` alias) for dotfiles,
# and plain `git` works normally everywhere else.
claude() {
  if [[ "$PWD" == "$HOME" ]]; then
    CLAUDE_DOTFILES_GIT_DIR="$HOME/.cfg" CLAUDE_DOTFILES_WORK_TREE="$HOME" command claude "$@"
  else
    command claude "$@"
  fi
}
# alias clio="ssh -t dev-machine 'tmux new-session -A -s clio'"
alias clio="cd ~/Documents/Clio && claude --dangerously-skip-permissions"
alias refresh="source ~/.zshrc"
# Clear evalcache (pyenv/jenv/starship/zoxide). Run after a `brew upgrade` if a
# new shell errors with "no such file" pointing at an old versioned Cellar path.
evalcache-clear() { rm -f "$HOME/.zsh-evalcache/"*.sh "$HOME/.zsh-evalcache/"*.zwc && echo "evalcache cleared — open a new shell to rebuild"; }
alias zshconfig="code ~/.zshrc"
alias h="ssh h"
alias hermes="ssh h"

# eza (replaces ls)
alias ls='eza --group-directories-first'
alias ll='eza -l --header --git --group-directories-first'
alias la='eza -la --header --git --group-directories-first'
alias lt='eza --tree --level=2 --group-directories-first'

# bat (replaces cat)
alias cat='bat'

# Starship prompt — cached for fast startup
_evalcache starship init zsh

# Nord colors for zsh-autosuggestions
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#4c566a"

# CLI Tools — cached for fast startup
_evalcache fzf --zsh

# fzf configuration with fd/bat/eza previews
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS="
  --height 40%
  --layout reverse
  --border
  --color=fg:#d8dee9,bg:#2e3440,hl:#88c0d0
  --color=fg+:#eceff4,bg+:#3b4252,hl+:#5e81ac
  --color=info:#81a1c1,prompt:#88c0d0,pointer:#b48ead
  --color=marker:#a3be8c,spinner:#b48ead,header:#88c0d0"

export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="
  --preview 'bat -n --color=always --line-range :300 {}'
  --bind 'ctrl-/:change-preview-window(down|hidden|)'"

export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -50'"

export FZF_CTRL_R_OPTS="
  --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
  --color header:italic
  --header 'CTRL-Y to copy to clipboard'"

# fzf-tab configuration
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:complete:ls:*' fzf-preview 'eza -1 --color=always $realpath'

# Completion improvements
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.zcompcache"

# Prefix-aware history search on Up/Down (native zsh — replaces history-substring-search).
# Type a prefix, press Up: cycles only through history lines starting with it.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

# 1Password service account — read-only access to AI + Homelab vaults.
# Token lives in macOS Keychain (unlocked at login, no biometric prompt).
# To rotate: generate a new SA token at 1password.com/developer, then:
#   security add-generic-password -U -s op-service-account -a homelab-ai -T /usr/bin/security \
#     -w "$(op item get puelzwd65pdakekao3k2ejztom --fields credential --reveal --vault Private)"
export OP_SERVICE_ACCOUNT_TOKEN="$(security find-generic-password -s op-service-account -a homelab-ai -w 2>/dev/null)"

# AI API keys — LAZY-loaded on demand. Each `op read` is a ~0.5s network call;
# fetching all three at every shell start cost ~1.4s. They're rarely needed
# interactively, so populate on demand with `load-ai-keys` (no on-disk cache).
# Homelab secrets (Unifi, HA, etc.) are NOT exported; scripts call `op read` inline.
load-ai-keys() {
    [[ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]] || { print -u2 "load-ai-keys: no OP_SERVICE_ACCOUNT_TOKEN"; return 1; }
    [[ -n "$OPENAI_API_KEY"    ]] || export OPENAI_API_KEY="$(op read 'op://AI/Open AI API Key/api key' 2>/dev/null)"
    [[ -n "$ANTHROPIC_API_KEY" ]] || export ANTHROPIC_API_KEY="$(op read 'op://AI/Anthropic API Key/api key' 2>/dev/null)"
    [[ -n "$GEMINI_API_KEY"    ]] || export GEMINI_API_KEY="$(op read 'op://AI/Gemini API Key/api key' 2>/dev/null)"
}

export PAGER=cat
export GH_PAGER=cat

export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="$(ruby -e 'puts Gem.default_bindir'):$PATH"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# Added by Antigravity
export PATH="/Users/cameron/.antigravity/antigravity/bin:$PATH"


export CLAUDE_CODE_THEME=dark

# Launch tmux session picker on SSH login (Termius/Tailscale)
# If the picker exits without selecting a session (q to quit), disconnect
if [[ -n "$SSH_CONNECTION" && -z "$TMUX" && $- == *i* ]]; then
    ~/tmux_picker.sh || true
    [[ -z "$TMUX" ]] && exit
fi

alias sessions="~/tmux_picker.sh"

# zoxide — must be initialized at the end of .zshrc
export _ZO_DOCTOR=0
_evalcache zoxide init --cmd cd zsh

# # OpenClaw Completion
# source "/Users/cameron/.openclaw/completions/openclaw.zsh"

# opencode
export PATH=/Users/cameron/.opencode/bin:$PATH

# Clio env (managed by setup/bootstrap.sh — safe to remove)
[ -f "$HOME/.clio/env" ] && source "$HOME/.clio/env"

export GOOGLE_SERVICE_ACCOUNT_KEY="$HOME/.config/commhospital/sa-key.json"