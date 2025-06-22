#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/common.sh"

step "Installing yay (AUR helper)"

# Step 1: Cleanup previous yay installation
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

# Step 2: Clone yay repo
step "Cloning yay repository"
if git clone https://aur.archlinux.org/yay.git /tmp/yay >/dev/null 2>&1; then
  log_success "yay repository cloned."
else
  log_error "Failed to clone yay repository."
  return 1
fi

# Step 3: Build and install yay
step "Building and installing yay"
cd /tmp/yay
if makepkg -si --noconfirm; then
  log_success "yay built and installed."
else
  log_error "Failed to build/install yay."
  return 1
fi
cd /tmp
sudo rm -rf /tmp/yay

# Step 4: Final check
step "Final check"
if command -v yay >/dev/null; then
  log_success "yay installed successfully!"
else
  log_error "yay installation failed."
  return 1
fi