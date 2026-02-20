Checkout https://github.com/unixorn/awesome-zsh-plugins

## Oh My ZSH

Alternative: Create Symlinks

If the plugins are still not found, create symlinks to Oh My Zsh’s expected location:

```shell
mkdir -p ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins
ln -s $(brew --prefix)/share/zsh-syntax-highlighting ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
ln -s $(brew --prefix)/share/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
```

## pyenv

