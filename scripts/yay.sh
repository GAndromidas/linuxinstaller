#!/bin/bash

# yay.sh - Install yay AUR helper
# This script installs yay, which is required for AUR package installation

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR"
source "$SCRIPTS_DIR/common.sh"
source "$SCRIPTS_DIR/cachyos_support.sh"

install_yay() {
  step "Installing yay AUR helper"

  # Use centralized CachyOS detection from cachyos_support.sh
  if should_skip_yay_installation; then
    return 0
  fi

  # Check if yay is already installed (fallback for any system)
  if command -v yay &>/dev/null; then
    log_success "yay is already installed"
    return 0
  fi

  # Check if base-devel is installed (required for building packages)
  if ! pacman -Q base-devel &>/dev/null; then
    log_warning "base-devel not found, installing now..."
    if sudo pacman -S --noconfirm --needed base-devel >/dev/null 2>&1; then
      log_success "base-devel installed successfully"
    else
      log_error "Failed to install base-devel package"
      return 1
    fi
  fi

  # Check if git is installed (required for cloning)
  if ! pacman -Q git &>/dev/null; then
    log_warning "git not found, installing now..."
    if sudo pacman -S --noconfirm --needed git >/dev/null 2>&1; then
      log_success "git installed successfully"
    else
      log_error "Failed to install git package"
      return 1
    fi
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

  echo -e "\n${GREEN}✓ yay AUR helper installed successfully${RESET}"
  log_success "yay AUR helper installed"
  echo ""
}

# Execute yay installation
install_yay
