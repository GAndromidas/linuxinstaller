#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

check_prerequisites() {
  step "Checking system prerequisites"
  if [[ $EUID -eq 0 ]]; then
    log_error "Do not run this script as root. Please run as a regular user with sudo privileges."
    return 1
  fi
  if ! command -v pacman >/dev/null; then
    log_error "This script is intended for Arch Linux systems with pacman."
    return 1
  fi
  log_success "Prerequisites OK."
}

configure_pacman() {
  step "Configuring pacman optimizations"

  # Handle ParallelDownloads - works whether commented or uncommented
  if grep -q "^#ParallelDownloads" /etc/pacman.conf; then
    # Line is commented, uncomment and set value
    sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    log_success "Uncommented and set ParallelDownloads = 10"
  elif grep -q "^ParallelDownloads" /etc/pacman.conf; then
    # Line is uncommented, just update the value
    sudo sed -i 's/^ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    log_success "Updated ParallelDownloads = 10"
  else
    # Line doesn't exist, add it after [options] section
    sudo sed -i '/^\[options\]/a ParallelDownloads = 10' /etc/pacman.conf
    log_success "Added ParallelDownloads = 10"
  fi

  # Handle Color setting
  if grep -q "^#Color" /etc/pacman.conf; then
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    log_success "Uncommented Color setting"
  fi

  # Handle VerbosePkgLists setting
  if grep -q "^#VerbosePkgLists" /etc/pacman.conf; then
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    log_success "Uncommented VerbosePkgLists setting"
  fi

  # Add ILoveCandy if not already present
  if ! grep -q "^ILoveCandy" /etc/pacman.conf; then
    sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
    log_success "Added ILoveCandy setting"
  fi

  # Enable multilib if not already enabled
  if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
    log_success "Enabled multilib repository"
  else
    log_success "Multilib repository already enabled"
  fi

  echo ""
}

install_all_packages() {
  local all_packages=(
    # Helper utilities from HELPER_UTILS array
    "${HELPER_UTILS[@]}"
    # ZSH and plugins
    zsh zsh-autosuggestions zsh-syntax-highlighting
    # Starship
    starship
    # ZRAM
    zram-generator
  )

  step "Installing essential system packages"
  install_packages_quietly "${all_packages[@]}"
}

update_mirrorlist() {
  # Skip mirrorlist update - reflector removed due to issues
  log_warning "Mirrorlist update skipped - reflector removed from installer"
}

update_system() {
  run_step "System update" sudo pacman -Syyu --noconfirm
}

set_sudo_pwfeedback() {
  if ! sudo grep -q '^Defaults.*pwfeedback' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    run_step "Enabling sudo password feedback" bash -c "echo 'Defaults env_reset,pwfeedback' | sudo EDITOR='tee -a' visudo"
  else
    log_warning "sudo pwfeedback already enabled. Skipping."
  fi
}

install_cpu_microcode() {
  step "Detecting CPU and installing appropriate microcode"
  local pkg=""

  if grep -q "Intel" /proc/cpuinfo; then
    pkg="intel-ucode"
    log_success "Intel CPU detected"
  elif grep -q "AMD" /proc/cpuinfo; then
    pkg="amd-ucode"
    log_success "AMD CPU detected"
  else
    log_warning "Unable to determine CPU type. No microcode package will be installed."
    return 0
  fi

  install_packages_quietly "$pkg"
}

install_kernel_headers_for_all() {
  step "Installing kernel headers for all installed kernels"
  local kernel_types
  kernel_types=($(get_installed_kernel_types))

  if [ "${#kernel_types[@]}" -eq 0 ]; then
    log_warning "No supported kernel types detected. Please check your system configuration."
    return 1
  fi

  log_info "Detected kernels: ${kernel_types[*]}"

  local headers_packages=()
  for kernel in "${kernel_types[@]}"; do
    headers_packages+=("${kernel}-headers")
  done

  install_packages_quietly "${headers_packages[@]}"
}

generate_locales() {
  run_step "Generating locales" bash -c "sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen && sudo locale-gen"
}

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

  echo -e "\n${GREEN}✓ yay AUR helper installed successfully${RESET}"
  log_success "yay AUR helper installed"
  echo ""
}

# Execute system setup steps
main() {
  check_prerequisites
  configure_pacman
  install_all_packages
  update_system
  set_sudo_pwfeedback
  install_cpu_microcode
  install_kernel_headers_for_all
  generate_locales
  install_yay
}

# Run main function
main
