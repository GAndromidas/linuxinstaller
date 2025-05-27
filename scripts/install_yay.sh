#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

show_progress_bar() {
  local current=$1
  local total=$2
  local width=40
  local percent=$(( 100 * current / total ))
  local filled=$(( width * current / total ))
  local empty=$(( width - filled ))
  printf "\r["
  for ((i=0; i<filled; i++)); do printf "#"; done
  for ((i=0; i<empty; i++)); do printf " "; done
  printf "] %3d%%" $percent
  if (( current == total )); then
    echo    # new line at 100%
  fi
}

# Print figlet banner if available
if command -v figlet >/dev/null; then
  figlet "yay Install"
else
  echo -e "${CYAN}=== yay Install ===${RESET}"
fi

steps_total=4
step=1

# Step 1: Cleanup previous yay installation
show_progress_bar $step $steps_total
if command -v yay >/dev/null; then
  echo -e "${YELLOW}\nyay is already installed. Removing it before reinstalling.${RESET}"
  sudo pacman -Rns --noconfirm yay || true
  # Remove any remaining yay binary in /usr/bin
  if [ -f /usr/bin/yay ]; then
    sudo rm -f /usr/bin/yay
  fi
fi
if [ -d /tmp/yay ]; then
  echo -e "${YELLOW}Removing existing /tmp/yay folder.${RESET}"
  sudo rm -rf /tmp/yay
fi
((step++))

# Step 2: Clone yay repo
show_progress_bar $step $steps_total
echo -e "${GREEN}\nCloning yay repository...${RESET}"
cd /tmp
git clone https://aur.archlinux.org/yay.git
((step++))

# Step 3: Build and install yay
show_progress_bar $step $steps_total
echo -e "${GREEN}\nBuilding and installing yay...${RESET}"
cd yay
makepkg -si --noconfirm
cd ..
sudo rm -rf yay
((step++))

# Step 4: Final check
show_progress_bar $step $steps_total
if command -v yay >/dev/null; then
  echo -e "${GREEN}\nyay installed successfully!${RESET}"
else
  echo -e "${RED}\nyay installation failed.${RESET}"
  exit 1
fi
