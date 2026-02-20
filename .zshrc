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
  1password
  aws
  gradle
  git
  docker
  docker-compose
  kubectl
  brew
  npm
  yarn
  pip
  ssh
  extract
  macos
  colored-man-pages
  direnv
  history-substring-search
  evalcache
  fzf-tab
  you-should-use
  zsh-autosuggestions
  fast-syntax-highlighting
)

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

# Set default editor (VSCode locally, nano over SSH)
if [[ -n "$SSH_CONNECTION" ]]; then
    export EDITOR="nano"
else
    export EDITOR="code -w"
fi

export PATH="/Users/cameron/.local/bin:$PATH"

# Python (pyenv) — cached for fast startup
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
_evalcache pyenv init --path

# Java (jenv) — cached for fast startup
export PATH="$HOME/.jenv/bin:$PATH"
_evalcache jenv init -

# Android SDK paths
export ANDROID_HOME="$HOME/Library/Android/Sdk"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools:$PATH"

# iTerm2 Integration
[[ -f "$HOME/.iterm2_shell_integration.zsh" ]] && source "$HOME/.iterm2_shell_integration.zsh"

# Aliases
alias config="git --git-dir=$HOME/.cfg/ --work-tree=$HOME"
alias refresh="source ~/.zshrc"
alias zshconfig="code ~/.zshrc"

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
source <(fzf --zsh)

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

# History substring search key bindings (Up/Down arrows)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# API keys via 1Password (cached for 24h to avoid login prompts on every tab)
_load_api_keys() {
    local cache="$HOME/.cache/op-api-keys"
    local max_age=86400
    if [[ -f "$cache" ]]; then
        local file_age=$(( $(date +%s) - $(stat -f %m "$cache") ))
        if (( file_age < max_age )); then
            source "$cache"
            return
        fi
    fi
    if ! op account get &>/dev/null; then
        [[ -f "$cache" ]] && source "$cache"
        return
    fi
    mkdir -p "$(dirname "$cache")"
    {
        echo "export OPENAI_API_KEY=\"$(op item get 5fuvgno7geha7didmx5hexpgvy --fields label=password --reveal)\""
        echo "export ANTHROPIC_API_KEY=\"$(op item get hbvw7ksgi7fdpu5d3enyu755qm --fields 'label=api key' --reveal)\""
        echo "export GEMINI_API_KEY=\"$(op item get wtycgmkdrohgugo33feqqy3tby --fields 'label=api key' --reveal)\""
    } > "$cache"
    chmod 600 "$cache"
    source "$cache"
}
_load_api_keys
alias refresh-keys='rm -f ~/.cache/op-api-keys && _load_api_keys'

PAGER=cat
GH_PAGER=cat

export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# Added by Antigravity
export PATH="/Users/cameron/.antigravity/antigravity/bin:$PATH"

export GITHUB_TOKEN="$(gh auth token)"

export CLAUDE_CODE_THEME=dark

# zoxide — must be initialized at the end of .zshrc
_evalcache zoxide init --cmd cd zsh

# Launch tmux session picker on SSH login (Termius/Tailscale)
if [[ -n "$SSH_CONNECTION" && -z "$TMUX" && $- == *i* ]]; then
    ~/tmux_picker.sh
fi

alias sessions="~/tmux_picker.sh"
