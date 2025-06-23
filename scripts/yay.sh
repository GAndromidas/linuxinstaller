#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/common.sh"

step "Installing yay (AUR helper)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Simple logging functions
log_info() { echo -e "${CYAN}[INFO] $1${RESET}"; }
log_success() { echo -e "${GREEN}[OK] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_error() { echo -e "${RED}[FAIL] $1${RESET}"; }

# Check if yay is already installed
if command -v yay >/dev/null 2>&1; then
  log_success "yay is already installed"
  return 0
fi

# Step 1: Cleanup previous yay installation
step "Cleanup previous yay installation"
print_progress 1 4 "Removing existing yay installation"
if command -v yay >/dev/null; then
  log_warning "yay is already installed. Removing it before reinstalling."
  echo -e "\n${YELLOW}Please enter your password to remove existing yay installation:${RESET}"
  sudo pacman -Rns --noconfirm yay >/dev/null 2>&1 || true
  if [ -f /usr/bin/yay ]; then
    sudo rm -f /usr/bin/yay
  fi
fi
if [ -d /tmp/yay ]; then
  log_warning "Removing existing /tmp/yay folder."
  sudo rm -rf /tmp/yay
fi
print_status " [OK]" "$GREEN"

# Step 2: Clone yay repo
step "Cloning yay repository"
print_progress 2 4 "Cloning yay repository"
if git clone https://aur.archlinux.org/yay.git /tmp/yay >/dev/null 2>&1; then
  print_status " [OK]" "$GREEN"
  log_success "yay repository cloned."
else
  print_status " [FAIL]" "$RED"
  log_error "Failed to clone yay repository."
  return 1
fi

# Step 3: Build and install yay
step "Building and installing yay"
print_progress 3 4 "Building and installing yay"
cd /tmp/yay || {
  print_status " [FAIL]" "$RED"
  log_error "Failed to change to yay directory"
  return 1
}

# Build and install yay
echo -e "\n${YELLOW}Please enter your password to build and install yay:${RESET}"
if makepkg -si --noconfirm >/dev/null 2>&1; then
  print_status " [OK]" "$GREEN"
  log_success "yay built and installed."
else
  print_status " [FAIL]" "$RED"
  log_error "Failed to build/install yay."
  cd /tmp
  sudo rm -rf /tmp/yay
  return 1
fi

cd /tmp
sudo rm -rf /tmp/yay

# Step 4: Final check
step "Final check"
print_progress 4 4 "Verifying yay installation"
if command -v yay >/dev/null 2>&1; then
  print_status " [OK]" "$GREEN"
  log_success "yay installed successfully!"
else
  print_status " [FAIL]" "$RED"
  log_error "yay installation failed."
  return 1
fi

print_status " [DONE]" "$GREEN"