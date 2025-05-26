#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

if command -v yay >/dev/null; then
  echo -e "${YELLOW}yay is already installed. Skipping.${RESET}"
  exit 0
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
