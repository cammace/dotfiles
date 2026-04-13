# Dotfiles

This is a bare-repo dotfiles setup. The git directory is `~/.cfg` and the work tree is `~`.

## Git

All git commands must use `--git-dir=$HOME/.cfg/ --work-tree=$HOME` or be run in a session launched with the appropriate env vars.

Untracked files are hidden by default (`status.showUntrackedFiles=no`). This is intentional — only explicitly added files are tracked.

The alias for manual use is: `config` (e.g., `config status`, `config add`, `config commit`).
