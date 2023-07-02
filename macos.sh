#!/usr/bin/env bash
#
# Sets reasonable macOS defaults.
#
# Inspiration from https://mths.be/macos

# Exit if the operating system is not macOS.
if [ "$(uname -s)" != "Darwin" ]; then
  exit 0
fi

set +e

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until `.macos` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

###############################################################################
# General UI/UX                                                               #
###############################################################################
echo ""
echo "› System:"
echo "  › Disable the 'Are you sure you want to open this application?' dialog"
defaults write com.apple.LaunchServices LSQuarantine -bool false
echo "  > Expand save panel by default"
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

###############################################################################
# Trackpad, mouse, keyboard, Bluetooth accessories, and input                 #
###############################################################################
echo "  › Trackpad: enable tap to click for this user and for the login screen"
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

###############################################################################
# Energy saving                                                               #
###############################################################################
echo "  › Sleep the display after 15 minutes"
sudo pmset -a displaysleep 15
echo "  › et machine sleep to 5 minutes on battery"
sudo pmset -b sleep 5

###############################################################################
# Finder                                                                      #
###############################################################################
echo "  › When performing a search, search the current folder by default"
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
echo "  › Enable snap-to-grid for icons on the desktop and in other icon views"
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
echo "  › Show the ~/Library folder"
chflags nohidden ~/Library
echo "  › Show the /Volumes folder"
sudo chflags nohidden /Volumes
echo "  › Show path bar in the bottom of the Finder windows"
defaults write com.apple.finder "ShowPathbar" -bool "true"
echo "  › Default view style for folders to list"
defaults write com.apple.finder "FXPreferredViewStyle" -string "Nlsv"
echo "  › Keep folders on top when sorting by name"
defaults write com.apple.finder "_FXSortFoldersFirst" -bool "true"

###############################################################################
# Dock, Dashboard, and hot corners                                            #
###############################################################################
echo "  › Set the icon size of Dock items"
defaults write com.apple.dock tilesize -int 48
echo "  › Minimize windows into their application’s icon"
defaults write com.apple.dock minimize-to-application -bool true # -int 1
echo "  › Don’t show recent applications in Dock"
defaults write com.apple.dock show-recents -bool false
echo "  › Enable magnification"
defaults write com.apple.dock magnification -int 1

###############################################################################
# Terminal & iTerm 2                                                          #
###############################################################################












echo ""
echo "› Kill related apps"
for app in "Dock" "Finder" "SystemUIServer" "Terminal"; do
  killall "$app" > /dev/null 2>&1
done
set -e
