#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

if command -v yay >/dev/null; then
  echo -e "${YELLOW}yay is already installed. Removing it before reinstalling.${RESET}"
  sudo pacman -Rns --noconfirm yay || true
fi

# Clean up any existing yay clone in /tmp
if [ -d /tmp/yay ]; then
  echo -e "${YELLOW}Removing existing /tmp/yay folder.${RESET}"
  rm -rf /tmp/yay
fi

echo -e "${GREEN}Installing yay (AUR helper)...${RESET}"
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay

if command -v yay >/dev/null; then
  echo -e "${GREEN}yay installed successfully!${RESET}"
else
  echo -e "${RED}yay installation failed.${RESET}"
  exit 1
fi
