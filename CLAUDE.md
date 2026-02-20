# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is Cameron's macOS home directory containing dotfiles, shell configuration, and utility scripts. Dotfiles are synced to GitHub via a bare git repo at `~/.cfg` (public repo: `cammace/dotfiles`). Use the `config` alias for git operations (e.g., `config status`, `config add`, `config commit`, `config push`).

## Key Configuration Files

- **`.zshrc`** — Primary shell config. Oh My Zsh with Starship prompt, Nord color theme throughout. API keys loaded from 1Password with 24h cache (`_load_api_keys`). Auto-launches `tmux_picker.sh` on SSH connections.
- **`.tmux.conf`** — tmux with TPM plugin manager, Nord theme, Resurrect/Continuum for session persistence. Saves on detach. Resurrects `claude` process.
- **`Brewfile`** — Homebrew bundle for system packages, casks, App Store apps, and VS Code extensions.
- **`.gitconfig`** — Commit signing via 1Password SSH key (`op-ssh-sign`), format is SSH not GPG.

## Utility Scripts

- **`tmux_picker.sh`** — Interactive Nord-themed tmux session picker (arrow keys, enter, d to kill, q to quit). Always offers a "Claude Code" session first (`tmux new-session -A -s claude 'claude'`). Used as SSH login greeter and via `sessions` alias.
- **`update_ha_power.sh`** — Cron job that reports MacBook power draw to Home Assistant webhook. Zeroes out wattage when external display is connected or when not on a known network (checks gateway MAC).

## Environment & Toolchain

- **Python**: managed via `pyenv`
- **Java**: managed via `jenv` (OpenJDK 11, 17, 21 available via Homebrew)
- **Node**: `nvm` and `pnpm`
- **Shell**: zsh with Oh My Zsh, Starship prompt
- **Editor**: VS Code locally, nano over SSH
- **Theme**: Nord color palette used consistently across terminal, tmux, fzf, and zsh syntax highlighting

## Shell Aliases

- `config` — bare git dotfiles management (`git --git-dir=$HOME/.cfg/ --work-tree=$HOME`)
- `refresh` — re-source `.zshrc`
- `refresh-keys` — clear and reload 1Password API key cache
- `sessions` — launch `tmux_picker.sh`
- `cat` is aliased to `bat`

## Projects (~/Developer/)

Contains separate repositories: `home-assistant-config`, `ETL-Studio`, `viewer` (+ related repos), `proxmox`/`ProxmoxMCP`, `mcp-servers`.

## Conventions

- Nord color palette (`#2e3440` dark, `#88c0d0` frost/teal, etc.) is the visual standard — maintain consistency when modifying terminal/UI configs.
- 1Password is the secrets manager — never hardcode API keys. Use `op` CLI or the 1Password SSH agent.
- Do not add Co-Authored-By lines to commit messages.
