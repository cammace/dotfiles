#!/bin/bash

# Install homebrew and essential packages
if ! type brew > /dev/null 2>&1; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo "Installing Brew packages..."
  brew bundle --file Brewfile
  echo "Finished setting up Homebrew"
else
  echo "Updating homebrew"
  brew update
fi

# Install Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh..."
  /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "Oh My Zsh is already installed."
fi

# Create home directories
mkdir -p "$HOME/Fonts"

# TODO: modify macos settings here.