# Dotfiles


Install Command line tools:
xcode-select --install


Source https://www.atlassian.com/git/tutorials/dotfiles
git clone --bare <git-repo-url> $HOME/.cfg
alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
config checkout
config config --local status.showUntrackedFiles no





Example usage:
config status
config add .vimrc
config commit -m "Add vimrc"
config add .bashrc
config commit -m "Add bashrc"
config push



Creation of the Developer directory
mkdir Developer
cd Developer

SSH Key Generation for GitHub
ssh-keygen -t ed25519 -C “cameronmace10@gmail.com”

Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

Add Homebrew to PATH
echo '# Set PATH, MANPATH, etc., for Homebrew.' >> /Users/cameron/.zprofile
 echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/cameron/.zprofile
 eval "$(/opt/homebrew/bin/brew shellenv)" 

Brewfile
brew bundle install

Install Oh-My-Zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

Make VSCode default for opening files
# See https://github.com/moretension/duti
duti -s com.microsoft.VSCode public.unix-executable all
duti -s com.microsoft.VSCode public.data all
