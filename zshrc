###
# START OMZ CONFIG
###
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Stop ZSH cache from cluttering my $HOME directory
export ZSH_COMPDUMP="$ZSH/cache/.zcompdump-$HOST"

# Set name of the theme to load
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="cobalt2"

# oh-my-zsh auto-update behavior
zstyle ':omz:update' mode auto # update automatically without asking
zstyle ':omz:update' frequency 13 # How often to auto-update (in days)

# oh-my-zsh plugins
plugins=(git brew zsh-syntax-highlighting zsh-autosuggestions)

HISTSIZE=5000 # Maximum number of lines that are kept in a session
SAVEHIST=5000 # Maximum number of lines that are kept in the history file

source $ZSH/oh-my-zsh.sh

eval "$(starship init zsh)"

###
# END OMZ CONFIG
###
#Prioritize Homebrews curl over MacOS
export PATH="/opt/homebrew/opt/curl/bin:$PATH"

# Set the default editor to VSCode
export EDITOR="code -w"

# Python configuration using pyenv
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Java Development Environment using jenv
export PATH="$HOME/.jenv/bin:$PATH"
eval "$(jenv init -)"
export JAVA_HOME="$(jenv prefix)"

# Config alias used for managing dotfile sync with GitHub repo
alias config="/usr/bin/git --git-dir=/Users/$USER/.cfg/ --work-tree=/Users/$USER"
alias refresh="source ~/.zshrc"

# Add Android Developer Tools to the path
export ANDROID_HOME="$HOME/Library/Android/Sdk"
export PATH="$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools:$PATH"

export PATH="$PATH:$HOME/.local/bin"
