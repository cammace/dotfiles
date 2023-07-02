#!/bin/bash

# Install homebrew and essential packages
if test ! $(which brew); then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "Homebrew is already installed."
fi

# Check if installation was successful
if test ! $(which brew); then
    echo "Failed to install Homebrew."
    exit
fi

# Install Brew packages
echo "Installing Brew packages..."
brew bundle --file Brewfile

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
