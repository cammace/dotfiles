# Dotfiles

macOS dotfiles managed with a [bare git repo](https://www.atlassian.com/git/tutorials/dotfiles): the git
dir is `~/.cfg` and the work tree is `~`. One repo sets up two kinds of Mac, a **laptop** and a headless,
always-on **server**.

## Setup

On a new Mac, run one line. It uses HTTPS, so no SSH key is needed yet:

```bash
curl -fsSL https://raw.githubusercontent.com/cammace/dotfiles/main/bootstrap.sh | bash -s -- --role server
```

Use `--role laptop` for a laptop. `bootstrap.sh` is idempotent, so a re-run is safe. In order, it:

1. Installs the Xcode Command Line Tools if they are missing.
2. Installs Homebrew if it is missing and loads `brew shellenv`.
3. Bare-clones this repo into `~/.cfg` if that directory is absent.
4. Checks out the repo. Existing files that the repo tracks move to `~/.cfg-backup/<timestamp>/` first.
   A re-run leaves an existing checkout alone.
5. Sets `status.showUntrackedFiles no`.
6. Writes the role to `~/.config/machine-role`.
7. Runs `brew bundle` for `Brewfile`, then `Brewfile.<role>`. A failed item prints a warning and does
   not stop the run.
8. Installs Oh My Zsh (keeping the tracked `.zshrc`), the custom zsh plugins `.zshrc` loads, and TPM.
9. Prints the manual next steps: 1Password and its SSH agent, `gh auth login`, `tailscale up`, and the
   Clio repo's `ops/bootstrap.sh`.

Flags:

| Flag | Effect |
|---|---|
| `--role laptop\|server` | Writes `~/.config/machine-role`. Required when that file does not exist yet. |
| `--dry-run` | Prints every action and changes nothing. |
| `--branch NAME` | Checks out `NAME` instead of `main` (also `DOTFILES_BRANCH`). |
| `--repo URL\|PATH` | Clones from somewhere else, such as a local `~/.cfg` for a test (also `DOTFILES_REPO`). |
| `--skip-network` | Skips the network installs: CLT, Homebrew, `brew bundle`, Oh My Zsh, plugins, TPM. |

To run a branch before it is merged, fetch the script from that branch and pass the same branch:

```bash
curl -fsSL https://raw.githubusercontent.com/cammace/dotfiles/BRANCH/bootstrap.sh | bash -s -- --role server --branch BRANCH
```

### Server only

`macos-server.sh` holds the settings that need `sudo`. Nothing runs it automatically. Read it, then run:

```bash
sudo ~/macos-server.sh <hostname>     # add --dry-run to preview
```

It turns off system and disk sleep, restarts after a power failure, wakes on network access, and turns on
Remote Login and Screen Sharing. With a hostname, it also sets the computer name.

## Machine role

`~/.config/machine-role` holds `laptop` or `server`. It is not tracked. A missing file means `laptop`, so a
Mac without the file behaves exactly as the laptop always has.

| Behavior | Laptop | Server |
|---|---|---|
| `~/.clio/env` sourced at shell start (runs `op read` for secrets) | yes | no: `~/.clio/bin` goes on `PATH`, and `load-clio-env` loads the rest on demand |
| `SSH_AUTH_SOCK` points at the 1Password agent | always | only once 1Password has created the socket |
| `update_ha_power.sh` reports battery power to Home Assistant | yes | exits at once |

The server skips the `op read` calls because, on a headless Mac, they raise permission prompts that nobody
can answer, and a locked 1Password stalls every new shell.

To change the role, run `bootstrap.sh --role <role>` again, or edit the file and open a new shell.

## Homebrew

| File | Contents |
|---|---|
| `Brewfile` | Common to both roles, including everything `.zshrc` runs at startup. |
| `Brewfile.laptop` | GUI apps, portable-only tools, App Store apps, VS Code extensions. |
| `Brewfile.server` | The server's extras: Ollama, whisper.cpp, Docker. |

`# unsure:` marks an item whose placement still needs a decision. `# STALE` lines were in the old Brewfile but
are not installed; they stay commented out until someone decides. To refresh after installing something:

```bash
brew bundle dump --file=/tmp/Brewfile.current   # then move new lines into the right file
```

## What's Included

| File | Description |
|---|---|
| `bootstrap.sh` | Sets up a new Mac from this repo (see Setup) |
| `macos-server.sh` | Sudo-only settings for the headless server; run by hand |
| `Brewfile`, `Brewfile.laptop`, `Brewfile.server` | Homebrew packages, casks, App Store apps, split by role |
| `.zshrc` | Oh My Zsh + Starship prompt, Nord theme, fzf-tab, machine-role switch, lazy API key loading (`load-ai-keys`) |
| `.zprofile` | Login-shell `PATH`: Homebrew, Docker Desktop, JetBrains Toolbox, Obsidian, `~/.local/bin` |
| `.bashrc` | fzf for bash |
| `.tmux.conf` | tmux with TPM, Nord theme, Resurrect/Continuum session persistence |
| `tmux_picker.sh` | Interactive Nord-themed tmux session picker; runs on SSH login |
| `.gitconfig` | Git config with 1Password SSH commit signing |
| `.gitignore` | Ignores everything except the allowlisted files above |
| `.config/starship.toml` | Starship prompt with full Nord palette |
| `.config/bat/config` | bat (cat replacement) with Nord theme |
| `.config/gh/config.yml` | GitHub CLI settings |
| `.config/git/ignore` | Global git ignore |
| `.config/ghostty/config` | Ghostty terminal: Nord theme, quick terminal, iTerm2-style splits |
| `.iterm2/*.sh` | iTerm2 semantic-history handlers (open `file:line`, GitHub refs) |
| `update_ha_power.sh` | Cron script reporting MacBook power draw to Home Assistant (laptop only) |
| `.claude/CLAUDE.md` | Claude Code instructions: response style (concise, skimmable) + work-tracking rules |
| `.claude/hooks/codex-pr-review-gate.sh` | PreToolUse gate: runs a Codex adversarial review before `gh pr create` / `git push` to a branch with an open PR |
| `.claude/hooks/unpushed-commits.py` | Stop hook: nags about commits that were never pushed |
| `.claude/scripts/` | Claude Code status line (`context-bar.sh`, `statusline-align.py`) |
| `.clio/bin/` | Copies of Clio meeting-pipeline tools; the Clio repo's `ops/bin` is their source |

## Claude Code

`.claude/CLAUDE.md` is loaded into every Claude Code session on the machine, in every directory. It holds two
things: response-style rules (answer first, no tool-call narration, no re-explaining a visible diff, ASD-STE100
sentence mechanics) and rules for when to open a task list.

Machine-local routing (which task tracker, which personal surfaces) lives in `~/.claude/rules/`, which is
deliberately untracked.

## Theme

[Nord](https://www.nordtheme.com/) color palette used consistently across terminal, tmux, Starship, fzf, bat, and zsh syntax highlighting.

## Usage

```bash
config status
config add .zshrc
config commit -m "Update zshrc"
config push
```

Nothing here may hardcode a home directory such as `/Users/<name>`; use `$HOME`, because each Mac can have a
different account name.
