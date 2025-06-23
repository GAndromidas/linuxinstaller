#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/common.sh"

step "Installing yay (AUR helper)"

# Store original directory
ORIGINAL_DIR=$(pwd)

# Step 1: Ensure required dependencies are installed
step "Checking dependencies"
print_progress 1 5 "Checking build dependencies"
if ! pacman -Q base-devel git >/dev/null 2>&1; then
  log_warning "Installing required build dependencies..."
  sudo pacman -S --noconfirm base-devel git >/dev/null 2>&1 || {
    log_error "Failed to install build dependencies"
    return 1
  }
fi
print_status " [OK]" "$GREEN"

# Step 2: Cleanup previous yay installation
step "Cleaning up previous installation"
print_progress 2 5 "Removing existing yay installation"
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
print_status " [OK]" "$GREEN"

# Step 3: Clone yay repo
step "Cloning yay repository"
print_progress 3 5 "Cloning yay repository"
if git clone https://aur.archlinux.org/yay.git /tmp/yay >/dev/null 2>&1; then
  print_status " [OK]" "$GREEN"
else
  print_status " [FAIL]" "$RED"
  log_error "Failed to clone yay repository."
  return 1
fi

# Step 4: Build and install yay
step "Building and installing yay"
print_progress 4 5 "Building yay package"

# Change to yay directory
if ! cd /tmp/yay; then
  print_status " [FAIL]" "$RED"
  log_error "Failed to change to yay directory"
  return 1
fi

# Ensure we have the right permissions and sudo access
sudo -n true 2>/dev/null || {
  log_warning "Sudo access required. Please enter your password when prompted."
  sleep 1
}

# Method 1: Try direct build and install
if MAKEPKG_CONF=/dev/null makepkg -si --noconfirm --log --skippgpcheck >/dev/null 2>&1; then
  print_status " [OK]" "$GREEN"
else
  print_status " [FAIL]" "$RED"
  log_warning "Direct build failed. Trying alternative method..."
  
  # Method 2: Build first, then install
  if MAKEPKG_CONF=/dev/null makepkg -s --noconfirm --log --skippgpcheck >/dev/null 2>&1; then
    # Find the built package
    PKG_FILE=$(find . -name "yay-*.pkg.tar.zst" -type f | head -1)
    if [ -n "$PKG_FILE" ] && [ -f "$PKG_FILE" ]; then
      if sudo pacman -U --noconfirm "$PKG_FILE" >/dev/null 2>&1; then
        print_status " [OK]" "$GREEN"
      else
        print_status " [FAIL]" "$RED"
        log_error "Failed to install yay package: $PKG_FILE"
        cd "$ORIGINAL_DIR"
        sudo rm -rf /tmp/yay
        return 1
      fi
    else
      print_status " [FAIL]" "$RED"
      log_error "Built package not found"
      cd "$ORIGINAL_DIR"
      sudo rm -rf /tmp/yay
      return 1
    fi
  else
    print_status " [FAIL]" "$RED"
    log_error "Failed to build yay package."
    cd "$ORIGINAL_DIR"
    sudo rm -rf /tmp/yay
    return 1
  fi
fi

# Return to original directory and cleanup
cd "$ORIGINAL_DIR"
sudo rm -rf /tmp/yay

# Step 5: Final check
step "Final check"
print_progress 5 5 "Verifying yay installation"
if command -v yay >/dev/null; then
  print_status " [OK]" "$GREEN"
  log_success "yay installed successfully!"
else
  print_status " [FAIL]" "$RED"
  log_error "yay installation failed."
  return 1
fi

print_status " [DONE]" "$GREEN"