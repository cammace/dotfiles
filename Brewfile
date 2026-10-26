# Brewfile - common to every machine (laptop and server).
# bootstrap.sh runs this, then Brewfile.<role>. Generated 2026-10-25 from
# `brew bundle dump` on the MacBook. `# unsure:` marks a placement to confirm;
# `# STALE` lines were in the old Brewfile but are not installed, so they stay
# commented out until someone decides.

# --- Taps ---
tap "hudochenkov/sshpass"
tap "jetbrains/utils", "https://github.com/JetBrains/homebrew-utils"
tap "micronaut-projects/tap"
tap "oven-sh/bun"

# --- Formulae ---
# Run your GitHub Actions locally
brew "act"
# Static checker for GitHub Actions workflow files
brew "actionlint"
# Simple, modern, secure file encryption
brew "age"
# Code searching, linting, rewriting
brew "ast-grep"
# Automatic configure script builder
brew "autoconf"
# Cryptography and SSL/TLS Toolkit
brew "openssl@3", link: true
# Shell extension to jump to frequently used directories
brew "autojump"  # unsure: stale? zoxide replaces it and .zshrc never loads autojump
# Tool for generating GNU Standards-compliant Makefiles
brew "automake"
# Official Amazon AWS command-line interface
brew "awscli"
# C library implementing the SSH2 protocol
brew "libssh2"
# Clone of cat(1) with syntax highlighting and Git integration
brew "bat"
# Powerful, enterprise-ready, open source web server with automatic HTTPS
brew "caddy"  # unsure: local dev web server; needed on either box?
# Manage multiple AI agents like Claude Code, Aider and Codex in your terminal
brew "claude-squad"
# GNU File, Shell, and Text utilities
brew "coreutils"
# Tool for interacting with remote images and registries
brew "crane"
# Get a file from an HTTP, HTTPS or FTP server
brew "curl"
# Load/unload environment variables based on $PWD
brew "direnv"
# Pack, ship and run any application as a lightweight container
brew "docker"
# Isolated development environments using Docker
brew "docker-compose"
# Docker CLI plugin for extended build capabilities with BuildKit
brew "docker-buildx"
# Platform keystore credential helper for Docker (credsStore: osxkeychain)
brew "docker-credential-helper"
# Modern, maintained replacement for ls
brew "eza"
# Simple, fast and user-friendly alternative to find
brew "fd"
# Command-line fuzzy finder written in Go
brew "fzf"
# Easily access your Google Calendar(s) from a command-line
brew "gcalcli"
# Open-source, cross-platform JavaScript runtime environment
brew "node"
# Interact with Google Gemini AI models from the command-line
brew "gemini-cli"
# GitHub command-line tool
brew "gh"
# Distributed revision control system
brew "git"
# Audit git repos for secrets
brew "gitleaks"
# GNU Privacy Guard (OpenPGP)
brew "gnupg"
# Open source programming language to build simple/reliable/efficient software
brew "go"
# CLI for Drive, Gmail, Calendar, Sheets, Docs, Chat, Admin, and more
brew "googleworkspace-cli"
# Generic library support script
brew "libtool"
# Graph visualization software from AT&T and Bell Labs
brew "graphviz"
# Improved top (interactive process viewer)
brew "htop"
# Tools and libraries to manipulate images in select formats
brew "imagemagick"
# Manage your Java environment
brew "jenv"
# Asynchronous event library
brew "libevent"
# Postgres C API library
brew "libpq"
# Library for database change tracking
brew "liquibase"  # unsure: Viewer DB migrations; keep on both?
# Mac App Store command-line interface
brew "mas"
# Port scanning utility for large networks
brew "nmap"
# Manage multiple Node.js versions
brew "nvm"
# Development kit for the Java programming language
brew "openjdk@11"  # unsure: still needed beside 17/21/25?
# Development kit for the Java programming language
brew "openjdk@17"
# Development kit for the Java programming language
brew "openjdk@21"
# Development kit for the Java programming language
brew "openjdk@25"
# Open source suite of directory software
brew "openldap"
# PNG file optimizer
brew "optipng"
# Swiss-army knife of markup format conversion
brew "pandoc"
# Execute binaries from Python packages in isolated environments
brew "pipx"
# Package compiler and linker metadata toolkit
brew "pkgconf"
# PDF rendering library (based on the xpdf-3.0 code base)
brew "poppler"
# Object-relational database system
brew "postgresql@18", link: true
# Python version management
brew "pyenv"
# Interpreted, interactive, object-oriented programming language
brew "python@3.11"
# Tools for and transforming and inspecting PDF files
brew "qpdf"
# Pack repository contents into a single AI-friendly file
brew "repomix"
# Search tool like grep and The Silver Searcher
brew "ripgrep"
# Tool for downloading RTMP streaming media
brew "rtmpdump"
# Powerful, clean, object-oriented scripting language
brew "ruby"
# Extremely fast Python linter, written in Rust
brew "ruff"
# 7-Zip is a file archiver with a high compression ratio
brew "sevenzip"
# Create beautiful image of your source code
brew "silicon"
# SOcket CAT: netcat on steroids
brew "socat"
# Editor of encrypted files
brew "sops"
# PureScript package manager and build tool
brew "spago"  # unsure: stale? PureScript, no known project uses it
# Microsoft SQL Server command-line interface
brew "sqlcmd"
# Cross-shell prompt for astronauts
brew "starship"
# OCR (Optical Character Recognition) engine
brew "tesseract"
# Multi-modal AI tool to extract and summarize content
brew "summarize"
# Nodejs-based tool for optimizing SVG vector graphics files
brew "svgo"
# Generate scripting interfaces to C/C++ code
brew "swig"
# User interface to the TELNET protocol
brew "telnet"
# Terminal multiplexer
brew "tmux"
# Your CLI home video recorder
brew "vhs"
# Executes a program periodically, showing output fullscreen
brew "watch"
# ISO9660+RR manipulation tool
brew "xorriso"
# Shell extension to navigate your filesystem faster
brew "zoxide"
brew "hudochenkov/sshpass/sshpass", trusted: true
# Official Language Server Protocol for the Kotlin language
brew "jetbrains/utils/kotlin-lsp", trusted: true
# Incredibly fast JavaScript runtime, bundler, transpiler and package manager - all in one.
brew "oven-sh/bun/bun", trusted: true
# Package installer for Python; the uv entries below need it on a fresh Mac
brew "uv"  # NEW: the laptop has uv from the standalone installer in ~/.local/bin

# --- Casks ---
# Docker engine for both Macs (replaces Docker Desktop). It sets the docker
# context to `orbstack`; bootstrap.sh starts it once after this bundle.
cask "orbstack"
# Password manager that keeps all passwords secure behind one password
cask "1password", args: { appdir: "/Applications" }
# Command-line interface for 1Password
cask "1password-cli"
# Microsoft Azure CLI (Homebrew moved it from a formula to a cask)
cask "azure-cli"
# Google's agent orchestration app (Antigravity); signs in with a Google account
cask "antigravity"
# OpenAI's coding agent that runs in your terminal
cask "codex"
# Brings the power of Copilot coding agent directly to your terminal
cask "copilot-cli"
# Set of tools to manage resources and applications hosted on Google Cloud
cask "gcloud-cli", args: { appdir: "/Applications" }
# Free cross-platform office suite, fresh version
cask "libreoffice"  # unsure: Clio office skills convert with soffice; the mini runs those jobs
cask "micronaut-projects/tap/micronaut", args: { appdir: "/Applications" }, trusted: true
# Plugin for AWS CLI to start and end sessions that connect to managed instances
cask "session-manager-plugin"
# Mesh VPN based on WireGuard
cask "tailscale-app"  # unsure: GUI app needs a login session on the mini; the tailscale formula runs headless as a daemon
# --- Desk apps (both Macs) ---
# The mini has its own monitor and keyboard, so it gets the daily-driver GUI
# apps too. Laptop-only and niche apps stay in Brewfile.laptop.
# Sets the default browser; bootstrap.sh runs `defaultbrowser chrome`
brew "defaultbrowser"
# Display controls: scaling, HiDPI, brightness
cask "betterdisplay"
# Anthropic's desktop app
cask "claude"
# Allows switching between application windows
cask "contexts", args: { appdir: "/Applications" }
# System-wide autocomplete
cask "cotypist"
cask "font-fira-code-nerd-font", args: { appdir: "/Applications" }
cask "font-hack-nerd-font", args: { appdir: "/Applications" }
cask "font-jetbrains-mono-nerd-font"
cask "font-monaspace", args: { appdir: "/Applications" }
# Web browser
cask "google-chrome", args: { appdir: "/Applications" }  # default browser on both Macs; bootstrap.sh sets it
# Media player
cask "iina"
# Terminal emulator as alternative to Apple's Terminal app
cask "iterm2", args: { appdir: "/Applications" }
# JetBrains tools manager
cask "jetbrains-toolbox", args: { appdir: "/Applications" }  # IntelliJ IDEA, DataGrip and Gateway install through Toolbox, not casks
# Markdown knowledge base (the Clio vault)
cask "obsidian"
# Local-first alternative to Logitech Options+ for HID++ devices
cask "openlogi"  # mouse driver
# Launcher; settings move with Raycast Cloud Sync or its export, not dotfiles
cask "raycast"
# Music streaming service
cask "spotify", args: { appdir: "/Applications" }
# Menu bar manager
cask "thaw"
# Git client focusing on power and productivity
cask "tower", args: { appdir: "/Applications" }
# Open-source BitTorrent client
cask "transmission", args: { appdir: "/Applications" }
# Open-source code editor
cask "visual-studio-code", args: { appdir: "/Applications" }
# Menu bar utilities
cask "vorssaint"
# Code editor; settings in ~/.config/zed
cask "zed"
# App Store (mas needs an Apple ID signed in to the App Store app)
mas "Drafts", id: 1435957248
mas "Fantastical", id: 975937182
mas "Slack", id: 803453959
mas "Windows App", id: 1295203466

# --- Go ---
go "github.com/rhysd/actionlint/cmd/actionlint"  # duplicate of brew actionlint

# --- uv tools ---
uv "claude-swap"
uv "nano-pdf"

# --- npm globals ---
npm "@box/cli"
npm "@karakeep/cli"
npm "@modelcontextprotocol/server-postgres"
npm "@pnp/cli-microsoft365"
npm "agent-browser"
npm "aws-cdk"
npm "corepack"
npm "defuddle-cli"
npm "docx"
npm "mcporter"
npm "taskforge-md"
npm "typescript-language-server"
npm "typescript"

# --- Stale (from the 04-05 Brewfile, flagged for review) ---
# tap "1password/tap"  # STALE: no installed item uses it
# brew "aider"  # STALE: listed 04-05, not installed
# brew "pnpm"  # STALE: listed 04-05, not installed (the corepack npm global provides pnpm)
# brew "yarn"  # REPLACED: the corepack npm global owns bin/yarn; with the formula linked first, corepack fails to install
# brew "python@3.10"  # STALE: not installed; deprecated upstream
# brew "tldr"  # STALE: not installed; disabled in Homebrew (tlrc replaces it)
# brew "zsh-autosuggestions"  # STALE: not installed; Oh My Zsh custom plugin supplies it (bootstrap.sh clones it)
# cask "google-cloud-sdk"  # STALE: renamed to gcloud-cli, which is listed above
