#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR"
source "$SCRIPTS_DIR/common.sh"
source "$SCRIPTS_DIR/cachyos_support.sh"

check_prerequisites() {
  step "Checking system prerequisites"
  check_root_user
  if ! command -v pacman >/dev/null; then
    log_error "This script is intended for Arch Linux systems with pacman."
    return 1
  fi
  log_success "Prerequisites OK."
}

configure_pacman() {
  step "Configuring pacman optimizations"

  if $IS_CACHYOS; then
    log_info "CachyOS detected - skipping pacman.conf modifications"
    log_info "Preserving CachyOS optimized configuration (architecture, repositories, settings)"
    return 0
  fi

  # Handle ParallelDownloads - works whether commented or uncommented
  if grep -q "^#ParallelDownloads" /etc/pacman.conf; then
    # Line is commented, uncomment and set value
    sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    log_success "Uncommented and set ParallelDownloads = 10"
  elif grep -q "^ParallelDownloads" /etc/pacman.conf; then
    # Line is uncommented, just update the value
    current_value=$(grep "^ParallelDownloads" /etc/pacman.conf | awk '{print $3}')
    if [ "$current_value" != "10" ]; then
      sudo sed -i 's/^ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
      log_success "Updated ParallelDownloads = 10 (was $current_value)"
    else
      log_success "ParallelDownloads already set to 10"
    fi
  else
    # Line doesn't exist, add it after [options] section
    sudo sed -i '/^\[options\]/a ParallelDownloads = 10' /etc/pacman.conf
    log_success "Added ParallelDownloads = 10"
  fi

  # Handle Color setting
  if grep -q "^#Color" /etc/pacman.conf; then
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    log_success "Uncommented Color setting"
  elif grep -q "^Color" /etc/pacman.conf; then
    log_success "Color setting already enabled"
  fi

  # Handle VerbosePkgLists setting
  if grep -q "^#VerbosePkgLists" /etc/pacman.conf; then
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    log_success "Uncommented VerbosePkgLists setting"
  elif grep -q "^VerbosePkgLists" /etc/pacman.conf; then
    log_success "VerbosePkgLists already enabled"
  fi

  # Add ILoveCandy if not already present
  if ! grep -q "^ILoveCandy" /etc/pacman.conf; then
    sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
    log_success "Added ILoveCandy setting"
  else
    log_success "ILoveCandy already enabled"
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
    # ZSH and plugins (skip if keeping Fish on CachyOS)
    zsh zsh-autosuggestions zsh-syntax-highlighting
    # Starship
    starship
    # ZRAM
    zram-generator
  )

  step "Installing all packages"

  if $IS_CACHYOS; then
    echo -e "${CYAN}Installing packages in CachyOS compatibility mode...${RESET}"
    # Filter out packages that might conflict with CachyOS
    local filtered_packages=()
    for pkg in "${all_packages[@]}"; do
      # Skip packages that CachyOS might have custom versions of
      case "$pkg" in
        "linux"|"linux-headers")
          log_info "Skipping $pkg - CachyOS uses custom kernels"
          continue
          ;;
        "fish"|"fish-"*)
          if [[ "${CACHYOS_SHELL_CHOICE:-}" == "fish" ]]; then
            log_info "Keeping $pkg - user chose to keep Fish shell"
            filtered_packages+=("$pkg")
          else
            log_info "Excluding $pkg - Fish shell will be completely removed"
            continue
          fi
          ;;
        "zsh"|"zsh-"*|"starship")
          if [[ "${CACHYOS_SHELL_CHOICE:-}" == "fish" ]]; then
            log_info "Skipping $pkg - user chose to keep Fish shell"
            continue
          else
            filtered_packages+=("$pkg")
          fi
          ;;
        *)
          filtered_packages+=("$pkg")
          ;;
      esac
    done
    all_packages=("${filtered_packages[@]}")
    echo -e "${YELLOW}Filtered package list for CachyOS compatibility${RESET}"
  else
    echo -e "${CYAN}Installing ${#HELPER_UTILS[@]} helper utilities + ${#all_packages[@]} total packages via Pacman...${RESET}"
  fi

  local total=${#all_packages[@]}
  local current=0
  local failed_packages=()
  local skipped_packages=()

  for pkg in "${all_packages[@]}"; do
    ((current++))

    # Check if already installed
    if pacman -Q "$pkg" &>/dev/null; then
      print_progress "$current" "$total" "$pkg"
      if $IS_CACHYOS; then
        print_status " [SKIP] Already installed (CachyOS)" "$YELLOW"
      else
        print_status " [SKIP] Already installed" "$YELLOW"
      fi
      skipped_packages+=("$pkg")
      continue
    fi

    # CachyOS specific package checking
    if $IS_CACHYOS && is_package_configured "$pkg"; then
      print_progress "$current" "$total" "$pkg"
      print_status " [SKIP] Pre-configured in CachyOS" "$YELLOW"
      skipped_packages+=("$pkg")
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

  if [ ${#skipped_packages[@]} -gt 0 ] && $IS_CACHYOS; then
    echo -e "${YELLOW}CachyOS packages skipped: ${#skipped_packages[@]}${RESET}"
  fi

  if [ ${#failed_packages[@]} -gt 0 ]; then
    echo -e "${YELLOW}Failed packages: ${failed_packages[*]}${RESET}"
    log_warning "Some packages failed to install. Continuing with installation..."
  fi

  echo ""
}

update_mirrorlist() {
  # Skip mirrorlist update - reflector removed due to issues
  log_warning "Mirrorlist update skipped - reflector removed from installer"
}

update_system() {
  if $IS_CACHYOS; then
    # Be more conservative with CachyOS system updates
    log_info "CachyOS detected - performing conservative system update"
    run_step "CachyOS system update" sudo pacman -Syu --noconfirm
  else
    # Update system
    run_step "System update" sudo pacman -Syyu --noconfirm
  fi
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

  # Skip microcode installation on CachyOS - let CachyOS handle it
  if $IS_CACHYOS; then
    echo -e "${YELLOW}CachyOS detected - skipping microcode installation.${RESET}"
    echo -e "${CYAN}CachyOS manages CPU microcode automatically with optimized updates.${RESET}"
    log_success "Microcode installation skipped (CachyOS compatibility)"
    return
  fi

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



install_kernel_headers_for_all() {
  step "Installing kernel headers for all installed kernels"

  if $IS_CACHYOS; then
    log_info "CachyOS detected - checking for CachyOS kernels and headers"
    # Add CachyOS specific kernels to detection
    local cachyos_kernels=()
    pacman -Q linux-cachyos &>/dev/null && cachyos_kernels+=("linux-cachyos")
    pacman -Q linux-cachyos-lts &>/dev/null && cachyos_kernels+=("linux-cachyos-lts")

    if [ "${#cachyos_kernels[@]}" -gt 0 ]; then
      echo -e "${CYAN}Detected CachyOS kernels: ${cachyos_kernels[*]}${RESET}"

      local total=${#cachyos_kernels[@]}
      local current=0

      for kernel in "${cachyos_kernels[@]}"; do
        ((current++))
        local headers_package="${kernel}-headers"

        print_progress "$current" "$total" "$headers_package"

        if pacman -Q "$headers_package" &>/dev/null; then
          print_status " [SKIP] Already installed (CachyOS)" "$YELLOW"
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

      echo -e "\n${GREEN}✓ CachyOS kernel headers installation completed (${current}/${total} kernels processed)${RESET}\n"
      return
    fi
  fi

  # Standard kernel detection for non-CachyOS or if no CachyOS kernels found
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

# Remove Fish shell completely if on CachyOS and user chose ZSH
remove_fish_completely() {
  if $IS_CACHYOS && [[ "${CACHYOS_SHELL_CHOICE:-}" == "zsh" ]]; then
    step "Completely removing Fish shell from CachyOS (user chose ZSH)"

    # Remove fish package and all dependencies
    if pacman -Q fish &>/dev/null; then
      log_info "Removing Fish shell package and dependencies"
      sudo pacman -Rns fish --noconfirm >/dev/null 2>&1 || true
      log_success "Fish shell package removed"
    fi

    # Remove fish configurations for all users (current user)
    if [ -d "$HOME/.config/fish" ]; then
      log_info "Removing Fish configuration directory"
      rm -rf "$HOME/.config/fish" 2>/dev/null || true
    fi

    # Remove fish data directories
    if [ -d "$HOME/.local/share/fish" ]; then
      log_info "Removing Fish local data directory"
      rm -rf "$HOME/.local/share/fish" 2>/dev/null || true
    fi

    # Remove any fish-related files
    rm -f "$HOME/.fishrc" 2>/dev/null || true
    rm -f "$HOME/.fish_history" 2>/dev/null || true

    # Clean up any fish-related cache
    if [ -d "$HOME/.cache/fish" ]; then
      rm -rf "$HOME/.cache/fish" 2>/dev/null || true
    fi

    log_success "Fish shell completely removed from system"
  elif $IS_CACHYOS && [[ "${CACHYOS_SHELL_CHOICE:-}" == "fish" ]]; then
    log_info "Keeping Fish shell as requested by user"
  fi
}

# Execute ultra-fast preparation
check_prerequisites
configure_pacman
remove_fish_completely
install_all_packages
update_system
set_sudo_pwfeedback
install_cpu_microcode
install_kernel_headers_for_all
generate_locales
