#!/bin/bash
set -uo pipefail

# Simple yay installation script that works independently
echo "Installing yay (AUR helper)..."

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
  exit 0
fi

# Store original directory
ORIGINAL_DIR=$(pwd)

# Step 1: Install required dependencies
log_info "Installing build dependencies..."
if ! pacman -Q base-devel git >/dev/null 2>&1; then
  sudo pacman -S --noconfirm base-devel git >/dev/null 2>&1 || {
    log_error "Failed to install build dependencies"
    exit 1
  }
fi

# Step 2: Cleanup any existing yay installation
if [ -d /tmp/yay ]; then
  log_warning "Removing existing /tmp/yay folder"
  sudo rm -rf /tmp/yay
fi

# Step 3: Clone yay repository
log_info "Cloning yay repository..."
if ! git clone https://aur.archlinux.org/yay.git /tmp/yay >/dev/null 2>&1; then
  log_error "Failed to clone yay repository"
  exit 1
fi

# Step 4: Build and install yay
log_info "Building and installing yay..."

# Change to yay directory
cd /tmp/yay || {
  log_error "Failed to change to yay directory"
  exit 1
}

# Build and install yay
if MAKEPKG_CONF=/dev/null makepkg -si --noconfirm --log --skippgpcheck >/dev/null 2>&1; then
  log_success "yay installed successfully"
else
  log_warning "Direct build failed, trying alternative method..."
  
  # Alternative: Build first, then install
  if MAKEPKG_CONF=/dev/null makepkg -s --noconfirm --log --skippgpcheck >/dev/null 2>&1; then
    # Find the built package
    PKG_FILE=$(find . -name "yay-*.pkg.tar.zst" -type f | head -1)
    if [ -n "$PKG_FILE" ] && [ -f "$PKG_FILE" ]; then
      if sudo pacman -U --noconfirm "$PKG_FILE" >/dev/null 2>&1; then
        log_success "yay installed successfully"
      else
        log_error "Failed to install yay package"
        cd "$ORIGINAL_DIR"
        sudo rm -rf /tmp/yay
        exit 1
      fi
    else
      log_error "Built package not found"
      cd "$ORIGINAL_DIR"
      sudo rm -rf /tmp/yay
      exit 1
    fi
  else
    log_error "Failed to build yay package"
    cd "$ORIGINAL_DIR"
    sudo rm -rf /tmp/yay
    exit 1
  fi
fi

# Return to original directory and cleanup
cd "$ORIGINAL_DIR"
sudo rm -rf /tmp/yay

# Final verification
if command -v yay >/dev/null 2>&1; then
  log_success "yay installation completed successfully"
  exit 0
else
  log_error "yay installation failed"
  exit 1
fi