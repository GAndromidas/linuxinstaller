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
  
  # Optimize pacman configuration in parallel
  (
    # Handle ParallelDownloads - works whether commented or uncommented
    if grep -q "^#ParallelDownloads" /etc/pacman.conf; then
      sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    elif grep -q "^ParallelDownloads" /etc/pacman.conf; then
      sudo sed -i 's/^ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    else
      sudo sed -i '/^\[options\]/a ParallelDownloads = 10' /etc/pacman.conf
    fi
  ) &
  
  (
    # Handle Color setting
    if grep -q "^#Color" /etc/pacman.conf; then
      sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    fi
  ) &
  
  (
    # Handle VerbosePkgLists setting
    if grep -q "^#VerbosePkgLists" /etc/pacman.conf; then
      sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    fi
  ) &
  
  (
    # Add ILoveCandy if not already present
    if ! grep -q "^ILoveCandy" /etc/pacman.conf; then
      sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
    fi
  ) &
  
  (
    # Enable multilib if not already enabled
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
      echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
    fi
  ) &
  
  # Wait for all background operations to complete
  wait
  
  log_success "Pacman optimizations configured"
  echo ""
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
  )
  
  step "Installing all packages with parallel processing"
  
  # Use the optimized parallel installation function
  install_packages_quietly "${all_packages[@]}"
}

update_mirrorlist() {
  # Use only the fastest mirrors with optimized settings
  run_step "Updating mirrorlist" sudo reflector \
    --protocol https \
    --latest 3 \
    --sort rate \
    --save /etc/pacman.d/mirrorlist \
    --fastest 1 \
    --connection-timeout 1
}

update_system() {
  # Use the optimized system update function
  fast_system_update
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
  
  local header_packages=()
  for kernel in "${kernel_types[@]}"; do
    case "$kernel" in
      "linux")
        header_packages+=("linux-headers")
        ;;
      "linux-lts")
        header_packages+=("linux-lts-headers")
        ;;
      "linux-zen")
        header_packages+=("linux-zen-headers")
        ;;
      "linux-hardened")
        header_packages+=("linux-hardened-headers")
        ;;
    esac
  done
  
  if [ ${#header_packages[@]} -gt 0 ]; then
    install_packages_quietly "${header_packages[@]}"
  fi
}

generate_locales() {
  run_step "Generating locales" bash -c "sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen && sudo locale-gen"
}

# Main execution function with optimized flow
main() {
  # Run prerequisite checks
  check_prerequisites || return 1
  
  # Run configuration tasks in parallel where possible
  (
    configure_pacman
    set_sudo_pwfeedback
  ) &
  local config_pid=$!
  
  # Run package installation tasks
  (
    install_all_packages
    install_cpu_microcode
    install_kernel_headers_for_all
  ) &
  local packages_pid=$!
  
  # Run system update tasks
  (
    update_mirrorlist
    update_system
  ) &
  local update_pid=$!
  
  # Wait for all background tasks to complete
  wait $config_pid $packages_pid $update_pid
  
  log_success "System preparation completed"
}

# Run main function
main "$@" 