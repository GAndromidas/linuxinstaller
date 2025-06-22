#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/common.sh"

step "Installing yay (AUR helper)"

# Step 1: Cleanup previous yay installation
if command -v yay >/dev/null; then
  log_warning "yay is already installed. Removing it before reinstalling."
  sudo pacman -Rns --noconfirm yay >/dev/null 2>&1 || true
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
print_progress 1 4 "Cloning yay repository"
if git clone https://aur.archlinux.org/yay.git /tmp/yay >/dev/null 2>&1; then
  print_status " [OK]" "$GREEN"
else
  print_status " [FAIL]" "$RED"
  log_error "Failed to clone yay repository."
  return 1
fi

# Step 3: Build and install yay
step "Building and installing yay"
print_progress 2 4 "Building yay package"
cd /tmp/yay

# Use makepkg with minimal output for cleaner terminal
if MAKEPKG_CONF=/dev/null makepkg -si --noconfirm --log 2>/dev/null; then
  print_status " [OK]" "$GREEN"
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
print_progress 3 4 "Verifying yay installation"
if command -v yay >/dev/null; then
  print_status " [OK]" "$GREEN"
  log_success "yay installed successfully!"
else
  print_status " [FAIL]" "$RED"
  log_error "yay installation failed."
  return 1
fi

print_progress 4 4 "yay installation complete"
print_status " [DONE]" "$GREEN"