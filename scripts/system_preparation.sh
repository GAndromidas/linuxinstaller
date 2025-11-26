#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Function to install speedtest-cli silently if not available
install_speedtest_cli() {
  if ! command -v speedtest-cli >/dev/null 2>&1; then
    log_info "Installing speedtest-cli for network speed detection..."
    if sudo pacman -S --noconfirm --needed speedtest-cli >/dev/null 2>&1; then
      log_success "speedtest-cli installed successfully"
      return 0
    else
      log_warning "Failed to install speedtest-cli - will skip network speed test"
      return 1
    fi
  fi
  return 0
}

# Function to detect network speed and optimize downloads
detect_network_speed() {
  step "Testing network speed and optimizing download settings"

  # Install speedtest-cli if not available
  if ! install_speedtest_cli; then
    log_warning "speedtest-cli not available - skipping network speed test"
    return
  fi

  log_info "Testing internet speed (this may take a moment)..."

  # Run speedtest and capture download speed
  local speed_test_output=$(speedtest-cli --simple 2>/dev/null)

  if [ $? -eq 0 ]; then
    local download_speed=$(echo "$speed_test_output" | grep "Download:" | awk '{print $2}')

    if [ -n "$download_speed" ]; then
      log_success "Download speed: ${download_speed} Mbit/s"

      # Convert to integer for comparison
      local speed_int=$(echo "$download_speed" | cut -d. -f1)

      # Adjust parallel downloads based on speed
      if [ "$speed_int" -lt 5 ]; then
        log_warning "Slow connection detected (< 5 Mbit/s)"
        log_info "Reducing parallel downloads to 3 for stability"
        log_info "Installation will take longer - consider using ethernet"
        export PACMAN_PARALLEL=3
      elif [ "$speed_int" -lt 25 ]; then
        log_info "Moderate connection speed (5-25 Mbit/s)"
        log_info "Using standard parallel downloads (10)"
        export PACMAN_PARALLEL=10
      elif [ "$speed_int" -lt 100 ]; then
        log_success "Good connection speed (25-100 Mbit/s)"
        log_info "Using standard parallel downloads (10)"
        export PACMAN_PARALLEL=10
      else
        log_success "Excellent connection speed (100+ Mbit/s)"
        log_info "Increasing parallel downloads to 15 for faster installation"
        export PACMAN_PARALLEL=15
      fi
    else
      log_warning "Could not parse speed test results"
      export PACMAN_PARALLEL=10
    fi
  else
    log_warning "Speed test failed - using default settings"
    export PACMAN_PARALLEL=10
  fi
}

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

  # Use network-speed-based parallel downloads value (default 10 if not set)
  local parallel_downloads="${PACMAN_PARALLEL:-10}"

  # Handle ParallelDownloads - works whether commented or uncommented
  if grep -q "^#ParallelDownloads" /etc/pacman.conf; then
    # Line is commented, uncomment and set value
    sudo sed -i "s/^#ParallelDownloads.*/ParallelDownloads = $parallel_downloads/" /etc/pacman.conf
    log_success "Uncommented and set ParallelDownloads = $parallel_downloads"
  elif grep -q "^ParallelDownloads" /etc/pacman.conf; then
    # Line exists and is active, update value
    sudo sed -i "s/^ParallelDownloads.*/ParallelDownloads = $parallel_downloads/" /etc/pacman.conf
    log_success "Updated ParallelDownloads = $parallel_downloads"
  else
    # Line doesn't exist at all, add it
    sudo sed -i "/^\[options\]/a ParallelDownloads = $parallel_downloads" /etc/pacman.conf
    log_success "Added ParallelDownloads = $parallel_downloads"
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
  # Start with the full list of helper utilities
  local packages_to_install=("${HELPER_UTILS[@]}")

  # If in server mode, filter out desktop-specific helper utilities
  if [[ "${INSTALL_MODE:-}" == "server" ]]; then
    ui_info "Server mode: Filtering out desktop-specific helper utilities (bluetooth, plymouth)..."
    local server_filtered_packages=()
    for pkg in "${packages_to_install[@]}"; do
      if [[ "$pkg" != "bluez-utils" && "$pkg" != "plymouth" ]]; then
        server_filtered_packages+=("$pkg")
      fi
    done
    # Replace the original list with the filtered one
    packages_to_install=("${server_filtered_packages[@]}")
  fi

  local all_packages=(
    # Helper utilities from the (potentially filtered) list
    "${packages_to_install[@]}"
    # ZSH and plugins
    zsh zsh-autosuggestions zsh-syntax-highlighting
    # Starship
    starship
    # ZRAM
    zram-generator
  )

  step "Installing all packages"
  echo -e "${CYAN}Installing ${#packages_to_install[@]} helper utilities + ${#all_packages[@]} total packages via Pacman...${RESET}"

  # Try batch install first for speed
  printf "${CYAN}Attempting batch installation...${RESET}\n"
  if sudo pacman -S --noconfirm --needed "${all_packages[@]}" >/dev/null 2>&1; then
    printf "${GREEN} ✓ Batch installation successful${RESET}\n"
    INSTALLED_PACKAGES+=("${all_packages[@]}")
    return 0
  fi

  printf "${YELLOW} ! Batch installation failed. Falling back to individual installation...${RESET}\n"

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

  echo -e "\n${GREEN}Package installation completed (${current}/${total} packages processed)${RESET}"

  if [ ${#failed_packages[@]} -gt 0 ]; then
    echo -e "${YELLOW}Failed packages: ${failed_packages[*]}${RESET}"
    log_warning "Some packages failed to install. Continuing with installation..."
  fi

  echo ""
}

update_mirrorlist() {
  step "Updating mirrorlist for faster downloads"

  if ! command -v reflector >/dev/null; then
    log_info "Installing reflector..."
    sudo pacman -S --noconfirm --needed reflector >/dev/null 2>&1
  fi

  if command -v reflector >/dev/null; then
    log_info "Finding fastest mirrors (this may take a moment)..."
    # Backup existing mirrorlist
    [ ! -f /etc/pacman.d/mirrorlist.backup ] && sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

    if sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist; then
      log_success "Mirrorlist updated with fastest mirrors"
    else
      log_warning "Reflector failed. Keeping existing mirrorlist."
    fi
  else
    log_warning "Could not install reflector. Skipping mirrorlist update."
  fi
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
  local header_packages=()

  for kernel in "${kernel_types[@]}"; do
    header_packages+=("${kernel}-headers")
  done

  # Try batch install first
  printf "${CYAN}Attempting batch installation for headers...${RESET}\n"
  if sudo pacman -S --noconfirm --needed "${header_packages[@]}" >/dev/null 2>&1; then
    printf "${GREEN} ✓ Batch installation successful${RESET}\n"
    INSTALLED_PACKAGES+=("${header_packages[@]}")
    return 0
  fi

  printf "${YELLOW} ! Batch installation failed. Falling back to individual installation...${RESET}\n"

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

  echo -e "\\n${GREEN}Kernel headers installation completed (${current}/${total} kernels processed)${RESET}\\n"
}

install_inotify_tools() {
  step "Installing inotify-tools for grub-btrfsd"
  local pkg="inotify-tools"
  if pacman -Q "$pkg" &>/dev/null; then
    log_success "$pkg already installed. Skipping."
  else
    log_info "Installing $pkg..."
    if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
      log_success "$pkg installed successfully."
      INSTALLED_PACKAGES+=("$pkg")
    else
      log_error "Failed to install $pkg. grub-btrfsd might not function correctly."
      return 1
    fi
  fi
  echo ""
}

install_lts_kernel() {
  step "Ensuring LTS kernel is installed for snapshot recovery"
  local lts_kernel="linux-lts"

  if ! pacman -Q "$lts_kernel" &>/dev/null; then
    log_info "Installing missing LTS kernel: $lts_kernel"
    if sudo pacman -S --noconfirm --needed "$lts_kernel"; then
      log_success "LTS kernel installed successfully."
      INSTALLED_PACKAGES+=("$lts_kernel")
    else
      log_error "Failed to install LTS kernel. Btrfs fallback might not be available."
    fi
  else
    log_success "LTS kernel is already installed."
  fi
  echo ""
}

generate_locales() {
  run_step "Generating locales" bash -c "sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen && sudo locale-gen"
}

# Execute ultra-fast preparation
check_prerequisites
detect_network_speed  # This now installs speedtest-cli silently before testing
configure_pacman
update_mirrorlist
install_all_packages
update_system
set_sudo_pwfeedback
install_cpu_microcode
install_lts_kernel
install_kernel_headers_for_all

# Conditional install for grub-btrfsd dependency
BOOTLOADER=$(detect_bootloader)
if [ "$BOOTLOADER" = "grub" ]; then
    install_inotify_tools
fi

generate_locales
