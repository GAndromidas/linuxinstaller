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
  install_packages_quietly "${all_packages[@]}"
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

update_mirrors_and_system() {
  # Use only the fastest mirrors
  run_step "Updating mirrorlist" sudo reflector \
    --protocol https \
    --latest 3 \
    --sort rate \
    --save /etc/pacman.d/mirrorlist \
    --fastest 1 \
    --connection-timeout 1
  
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
  
  echo -ne "${CYAN}Detecting CPU type...${RESET} "
  
  if grep -q "Intel" /proc/cpuinfo; then
    echo -e "${GREEN}Intel CPU detected${RESET}"
    pkg="intel-ucode"
  elif grep -q "AMD" /proc/cpuinfo; then
    echo -e "${GREEN}AMD CPU detected${RESET}"
    pkg="amd-ucode"
  else
    echo -e "${YELLOW}Unable to determine CPU type${RESET}"
    log_warning "Unable to determine CPU type. No microcode package will be installed."
  fi

  if [ -n "$pkg" ]; then
    echo -ne "${CYAN}Installing $pkg...${RESET} "
    if pacman -Q "$pkg" &>/dev/null; then
      echo -e "${YELLOW}[SKIP] Already installed${RESET}"
    else
      if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${RESET}"
        INSTALLED_PACKAGES+=("$pkg")
      else
        echo -e "${RED}[FAIL]${RESET}"
        log_error "Failed to install $pkg"
      fi
    fi
  fi
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
    echo -ne "${CYAN}[${current}/${total}] Installing headers for $kernel ...${RESET} "
    
    if pacman -Q "$headers_package" &>/dev/null; then
      echo -e "${YELLOW}[SKIP] Already installed${RESET}"
    else
      if sudo pacman -S --noconfirm --needed "$headers_package" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${RESET}"
        INSTALLED_PACKAGES+=("$headers_package")
      else
        echo -e "${RED}[FAIL]${RESET}"
        log_error "Failed to install $headers_package"
      fi
    fi
  done
  
  echo -e "${GREEN}✓ Kernel headers installation completed (${current}/${total} kernels processed)${RESET}\n"
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
install_all_packages
configure_pacman
update_mirrors_and_system
set_sudo_pwfeedback
install_cpu_microcode
install_kernel_headers_for_all
generate_locales
install_yay_early 