# Dotfiles

macOS dotfiles managed with a [bare git repo](https://www.atlassian.com/git/tutorials/dotfiles).

## Setup

```bash
# Clone on a new machine
git clone --bare git@github.com:cammace/dotfiles.git $HOME/.cfg
alias config="git --git-dir=$HOME/.cfg/ --work-tree=$HOME"
config checkout
config config --local status.showUntrackedFiles no
```

## What's Included

| File | Description |
|---|---|
| `.zshrc` | Oh My Zsh + Starship prompt, Nord theme, fzf-tab, 1Password API key loading |
| `.tmux.conf` | tmux with TPM, Nord theme, Resurrect/Continuum session persistence |
| `.gitconfig` | Git config with 1Password SSH commit signing |
| `.config/starship.toml` | Starship prompt with full Nord palette |
| `.config/bat/config` | bat (cat replacement) with Nord theme |
| `Brewfile` | Homebrew packages, casks, and App Store apps |
| `tmux_picker.sh` | Interactive Nord-themed tmux session picker |
| `update_ha_power.sh` | Cron script reporting MacBook power draw to Home Assistant |
| `CLAUDE.md` | Claude Code project instructions |

## Theme

[Nord](https://www.nordtheme.com/) color palette used consistently across terminal, tmux, Starship, fzf, bat, and zsh syntax highlighting.

## Usage

```bash
config status
config add .zshrc
config commit -m "Update zshrc"
config push
```
