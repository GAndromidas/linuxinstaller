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
  # Apply all pacman optimizations at once
  sudo sed -i \
    -e 's/^#Color/Color/' \
    -e 's/^#VerbosePkgLists/VerbosePkgLists/' \
    -e 's/^#ParallelDownloads.*/ParallelDownloads = 20/' \
    -e '/^Color/a ILoveCandy' \
    /etc/pacman.conf
  
  # Enable multilib in one command
  grep -q "^\[multilib\]" /etc/pacman.conf || \
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
}

install_all_packages() {
  local all_packages=(
    # Helper utilities
    base-devel bluez-utils cronie curl eza fastfetch figlet flatpak fzf git openssh pacman-contrib reflector rsync ufw zoxide
    # ZSH and plugins
    zsh zsh-autosuggestions zsh-syntax-highlighting
    # Starship
    starship
    # ZRAM
    zram-generator
    # Basic graphics
    mesa
  )
  
  step "Installing all packages"
  echo -e "${CYAN}Installing ${#all_packages[@]} packages via Pacman...${RESET}"
  
  local total=${#all_packages[@]}
  local current=0
  local failed_packages=()
  
  for pkg in "${all_packages[@]}"; do
    ((current++))
    
    # Check if already installed
    if pacman -Q "$pkg" &>/dev/null; then
      print_progress "$current" "$total" "$pkg"
      print_status " [SKIP] Already installed" "$YELLOW"
      continue
    fi
    
    # Try to install
    print_progress "$current" "$total" "$pkg"
    if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
      print_status " [OK]" "$GREEN"
      INSTALLED_PACKAGES+=("$pkg")
    else
      print_status " [FAIL]" "$RED"
      log_error "Failed to install $pkg"
      failed_packages+=("$pkg")
    fi
  done
  
  echo -e "\n${GREEN}✓ Package installation completed (${current}/${total} packages processed)${RESET}"
  
  if [ ${#failed_packages[@]} -gt 0 ]; then
    echo -e "${YELLOW}Failed packages: ${failed_packages[*]}${RESET}"
    log_warning "Some packages failed to install. Continuing with installation..."
  fi
  
  echo ""
}

update_mirrorlist() {
  # Use only the fastest mirrors
  run_step "Updating mirrorlist" sudo reflector \
    --protocol https \
    --latest 3 \
    --sort rate \
    --save /etc/pacman.d/mirrorlist \
    --fastest 1 \
    --connection-timeout 1
}

update_system() {
  # Update system
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
  
  print_progress 1 3 "Detecting CPU type"
  
  if grep -q "Intel" /proc/cpuinfo; then
    print_status " [Intel CPU detected]" "$GREEN"
    pkg="intel-ucode"
  elif grep -q "AMD" /proc/cpuinfo; then
    print_status " [AMD CPU detected]" "$GREEN"
    pkg="amd-ucode"
  else
    print_status " [Unable to determine CPU type]" "$YELLOW"
    log_warning "Unable to determine CPU type. No microcode package will be installed."
  fi

  if [ -n "$pkg" ]; then
    print_progress 2 3 "Installing $pkg"
    if pacman -Q "$pkg" &>/dev/null; then
      print_status " [SKIP] Already installed" "$YELLOW"
    else
      if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
        print_status " [OK]" "$GREEN"
        INSTALLED_PACKAGES+=("$pkg")
      else
        print_status " [FAIL]" "$RED"
        log_error "Failed to install $pkg"
      fi
    fi
  fi
  
  print_progress 3 3 "CPU microcode installation complete"
  print_status " [DONE]" "$GREEN"
  echo ""
}

get_installed_kernel_types() {
  local kernel_types=()
  pacman -Q linux &>/dev/null && kernel_types+=("linux")
  pacman -Q linux-lts &>/dev/null && kernel_types+=("linux-lts")
  pacman -Q linux-zen &>/dev/null && kernel_types+=("linux-zen")
  pacman -Q linux-hardened &>/dev/null && kernel_types+=("linux-hardened")
  echo "${kernel_types[@]}"
}

install_kernel_headers_for_all() {
  step "Installing kernel headers for all installed kernels"
  local kernel_types
  kernel_types=($(get_installed_kernel_types))
  
  if [ "${#kernel_types[@]}" -eq 0 ]; then
    log_warning "No supported kernel types detected. Please check your system configuration."
    return
  fi
  
  echo -e "${CYAN}Detected kernels: ${kernel_types[*]}${RESET}"
  
  local total=${#kernel_types[@]}
  local current=0
  
  for kernel in "${kernel_types[@]}"; do
    ((current++))
    local headers_package="${kernel}-headers"
    
    print_progress "$current" "$total" "$headers_package"
    
    if pacman -Q "$headers_package" &>/dev/null; then
      print_status " [SKIP] Already installed" "$YELLOW"
    else
      if sudo pacman -S --noconfirm --needed "$headers_package" >/dev/null 2>&1; then
        print_status " [OK]" "$GREEN"
        INSTALLED_PACKAGES+=("$headers_package")
      else
        print_status " [FAIL]" "$RED"
        log_error "Failed to install $headers_package"
      fi
    fi
  done
  
  echo -e "\n${GREEN}✓ Kernel headers installation completed (${current}/${total} kernels processed)${RESET}\n"
}

generate_locales() {
  run_step "Generating locales" bash -c "sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen && sudo locale-gen"
}

# Install yay early (needed for AUR packages throughout the installation)
install_yay_early() {
  if [ -f "$SCRIPTS_DIR/yay.sh" ]; then
    chmod +x "$SCRIPTS_DIR/yay.sh"
    run_step "Installing yay (AUR helper)" "$SCRIPTS_DIR/yay.sh"
  else
    log_warning "yay.sh not found. AUR packages will not be available."
  fi
}

# Execute ultra-fast preparation
check_prerequisites
configure_pacman
install_all_packages
update_mirrorlist
update_system
set_sudo_pwfeedback
install_cpu_microcode
install_kernel_headers_for_all
generate_locales
install_yay_early 