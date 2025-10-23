#!/bin/bash

# yay.sh - Install yay AUR helper
# This script installs yay, which is required for AUR package installation

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

install_yay() {
  step "Installing yay AUR helper"

  # Check if yay is already installed
  if command -v yay &>/dev/null; then
    log_success "yay is already installed"
    return 0
  fi

  # Check if base-devel is installed (required for building packages)
  if ! pacman -Q base-devel &>/dev/null; then
    log_error "base-devel package is required but not installed. Please install it first."
    return 1
  fi

  # Create temporary directory for building
  local temp_dir
  temp_dir=$(mktemp -d)
  cd "$temp_dir" || { log_error "Failed to create temporary directory"; return 1; }

  # Clone yay repository
  print_progress 1 4 "Cloning yay repository"
  if git clone https://aur.archlinux.org/yay.git . >/dev/null 2>&1; then
    print_status " [OK]" "$GREEN"
  else
    print_status " [FAIL]" "$RED"
    log_error "Failed to clone yay repository"
    cd - >/dev/null && rm -rf "$temp_dir"
    return 1
  fi

  # Build yay
  print_progress 2 4 "Building yay"
  echo -e "\n${YELLOW}Please enter your sudo password to build and install yay:${RESET}"
  sudo -v
  if makepkg -si --noconfirm --needed >/dev/null 2>&1; then
    print_status " [OK]" "$GREEN"
  else
    print_status " [FAIL]" "$RED"
    log_error "Failed to build yay"
    cd - >/dev/null && rm -rf "$temp_dir"
    return 1
  fi

  # Verify installation
  print_progress 3 4 "Verifying installation"
  if command -v yay &>/dev/null; then
    print_status " [OK]" "$GREEN"
  else
    print_status " [FAIL]" "$RED"
    log_error "yay installation verification failed"
    cd - >/dev/null && rm -rf "$temp_dir"
    return 1
  fi

  # Clean up
  print_progress 4 4 "Cleaning up"
  cd - >/dev/null && rm -rf "$temp_dir"
  print_status " [OK]" "$GREEN"

  echo -e "\n${GREEN}yay AUR helper installed successfully${RESET}"
  log_success "yay AUR helper installed"
  echo ""

  # Install rate-mirrors to get the fastest mirrors
  step "Installing rate-mirrors"
  if yay -S --noconfirm rate-mirrors-bin >/dev/null 2>&1; then
    log_success "rate-mirrors-bin installed successfully"

    # Update mirrorlist
    step "Updating mirrorlist with rate-mirrors"
    if sudo rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch >/dev/null 2>&1; then
      log_success "Mirrorlist updated successfully"
    else
      log_error "Failed to update mirrorlist"
    fi
  else
    log_error "Failed to install rate-mirrors-bin"
  fi
}

# Execute yay installation
install_yay
