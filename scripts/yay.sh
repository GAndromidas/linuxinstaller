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

  # Ensure base-devel and git are installed (required for building packages)
  log_info "Ensuring base-devel and git are installed..."
  if ! sudo pacman -S --noconfirm --needed base-devel git >/dev/null 2>&1; then
    log_error "Failed to install base-devel or git. Cannot proceed with yay installation."
    return 1
  fi

  # Create temporary directory for building
  # MUST NOT be run as root - makepkg refuses to run as root
  local temp_dir
  temp_dir=$(mktemp -d)

  # Ensure the directory is accessible by the user building the package
  # If running via sudo, we need to ensure permissions are correct for the actual user
  if [ -n "${SUDO_USER:-}" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$temp_dir"
  fi
  chmod 777 "$temp_dir"

  trap "rm -rf '$temp_dir'" EXIT  # Ensure cleanup on exit

  # Switch to user context if running as root
  local run_as_user=""
  if [ "$EUID" -eq 0 ]; then
    if [ -n "${SUDO_USER:-}" ]; then
      run_as_user="sudo -u $SUDO_USER"
    else
      # Fallback to 'nobody' if absolutely necessary, though this usually fails with makepkg dependencies
      log_warning "Running as root without SUDO_USER. Attempting to build as 'nobody'..."
      run_as_user="sudo -u nobody"
      chown nobody:nobody "$temp_dir"
    fi
  fi

  cd "$temp_dir" || { log_error "Failed to create temporary directory"; return 1; }

  # Clone yay repository with retry
  print_progress 1 4 "Cloning yay repository"
  local clone_success=false
  for i in {1..3}; do
    if $run_as_user git clone https://aur.archlinux.org/yay.git . >/dev/null 2>&1; then
      clone_success=true
      break
    fi
    sleep 2
  done

  if [ "$clone_success" = true ]; then
    print_status " [OK]" "$GREEN"
  else
    print_status " [FAIL]" "$RED"
    log_error "Failed to clone yay repository after 3 attempts"
    return 1
  fi

  # Build yay
  print_progress 2 4 "Building yay"
  echo -e "\n${YELLOW}Building and installing yay...${RESET}"

  # Ensure we have sudo rights for the install phase
  sudo -v

  local build_success=false
  # makepkg needs to run as user, but -i (install) will ask for sudo internally
  if $run_as_user makepkg -si --noconfirm --needed >/dev/null 2>&1; then
    build_success=true
  fi

  if [ "$build_success" = true ]; then
    print_status " [OK]" "$GREEN"
  else
    print_status " [FAIL]" "$RED"
    log_error "Failed to build yay. Check if base-devel is properly installed."
    return 1
  fi

  # Verify installation
  print_progress 3 4 "Verifying installation"
  if command -v yay &>/dev/null; then
    print_status " [OK]" "$GREEN"
  else
    print_status " [FAIL]" "$RED"
    log_error "yay installation verification failed"
    return 1
  fi

  # Clean up (handled by trap)
  print_progress 4 4 "Cleaning up"
  cd - >/dev/null
  print_status " [OK]" "$GREEN"

  echo -e "\n${GREEN}yay AUR helper installed successfully${RESET}"
  echo ""

  # Install rate-mirrors to get the fastest mirrors (idempotent and visible)
  # Check for existing installation first to avoid unnecessary rebuilds
  if pacman -Q rate-mirrors-bin &>/dev/null || command -v rate-mirrors &>/dev/null; then
    log_success "rate-mirrors (rate-mirrors-bin) is already installed"
  else
    # Use run_step so installation output is captured and visible in logs/UI
    run_step "Installing rate-mirrors" yay -S --noconfirm rate-mirrors-bin || {
      log_error "Failed to install rate-mirrors-bin"
    }
  fi

  # Update mirrorlist using rate-mirrors (always try, but capture failures)
  run_step "Updating mirrorlist with rate-mirrors" sudo rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch || {
    log_error "Failed to update mirrorlist with rate-mirrors"
  }
}

# Execute yay installation
install_yay
