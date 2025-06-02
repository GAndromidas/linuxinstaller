#!/bin/bash
set -e

# ===== Colors for output =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ===== Output Functions =====
log_success() { echo -e "${GREEN}[OK] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_error()   { echo -e "${RED}[FAIL] $1${RESET}"; }
step()        { echo -e "\n${CYAN}[$1] $2${RESET}"; }

# ===== Simple Banner =====
echo -e "${CYAN}=== yay Install ===${RESET}"

CUR_STEP=1

# Step 1: Cleanup previous yay installation
step $CUR_STEP "Cleanup previous yay installation"
if command -v yay >/dev/null; then
  log_warning "yay is already installed. Removing it before reinstalling."
  sudo pacman -Rns --noconfirm yay || true
  if [ -f /usr/bin/yay ]; then
    sudo rm -f /usr/bin/yay
  fi
fi
if [ -d /tmp/yay ]; then
  log_warning "Removing existing /tmp/yay folder."
  sudo rm -rf /tmp/yay
fi
((CUR_STEP++))

# Step 2: Clone yay repo
step $CUR_STEP "Cloning yay repository"
if git clone https://aur.archlinux.org/yay.git /tmp/yay >/dev/null 2>&1; then
  log_success "yay repository cloned."
else
  log_error "Failed to clone yay repository."
  exit 1
fi
((CUR_STEP++))

# Step 3: Build and install yay
step $CUR_STEP "Building and installing yay"
cd /tmp/yay
if makepkg -si --noconfirm >/dev/null 2>&1; then
  log_success "yay built and installed."
else
  log_error "Failed to build/install yay."
  exit 1
fi
cd /tmp
sudo rm -rf /tmp/yay
((CUR_STEP++))

# Step 4: Final check
step $CUR_STEP "Final check"
if command -v yay >/dev/null; then
  log_success "yay installed successfully!"
else
  log_error "yay installation failed."
  exit 1
fi