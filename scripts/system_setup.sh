#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

check_prerequisites() {
  step "Checking system prerequisites"

  # Verify running Arch Linux
  if ! grep -qi arch /etc/os-release 2>/dev/null; then
    log_error "This installer is designed for Arch Linux only!"
    log_error "Detected system: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
    exit 1
  fi

  # Check for internet connection
  if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
    log_error "No internet connection detected!"
    log_error "Please check your network connection and try again."
    exit 1
  fi

  # Check available disk space (at least 2GB)
  local available_space=$(df / | awk 'NR==2 {print $4}')
  if [[ $available_space -lt 2097152 ]]; then
    log_error "Insufficient disk space!"
    log_error "At least 2GB free space is required."
    log_error "Available: $((available_space / 1024 / 1024))GB"
    exit 1
  fi

  log_success "Prerequisites check completed"
}

configure_pacman() {
  step "Configuring pacman"

  # Enable parallel downloads and color output
  local pacman_conf="/etc/pacman.conf"
  if ! grep -q "^ParallelDownloads" "$pacman_conf"; then
    sudo sed -i 's/^#ParallelDownloads/ParallelDownloads/' "$pacman_conf"
    log_success "Enabled parallel downloads in pacman"
  fi

  if ! grep -q "^Color" "$pacman_conf"; then
    sudo sed -i 's/^#Color/Color/' "$pacman_conf"
    log_success "Enabled color output in pacman"
  fi

  # Enable multilib repository if not already enabled
  if ! grep -q "^\[multilib\]" "$pacman_conf"; then
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a "$pacman_conf" >/dev/null
    log_success "Enabled multilib repository"
  fi
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

update_system() {
  run_step "System update" sudo pacman -Syyu --noconfirm
}

set_sudo_pwfeedback() {
  if ! sudo grep -q "Defaults pwfeedback" /etc/sudoers; then
    echo "Defaults pwfeedback" | sudo EDITOR='tee -a' visudo >/dev/null 2>&1
    log_success "Enabled sudo password feedback"
  fi
}

install_cpu_microcode() {
  step "Installing CPU microcode"
  local cpu_vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
  local pkg=""

  case "$cpu_vendor" in
    GenuineIntel) pkg="intel-ucode" ;;
    AuthenticAMD) pkg="amd-ucode" ;;
    *) log_warning "Unknown CPU vendor: $cpu_vendor"; return ;;
  esac

  if ! pacman -Q "$pkg" >/dev/null 2>&1; then
    log_info "Installing microcode for $cpu_vendor CPU"
  fi

  install_packages_quietly "$pkg"
}

install_kernel_headers_for_all() {
  step "Installing kernel headers"

  # Get only actual kernel packages (not firmware or other linux-* packages)
  local kernels=($(get_installed_kernel_types))

  local headers_packages=()

  for kernel in "${kernels[@]}"; do
    local header_pkg="${kernel}-headers"
    if ! pacman -Q "$header_pkg" >/dev/null 2>&1; then
      headers_packages+=("$header_pkg")
    fi
  done

  if [[ ${#headers_packages[@]} -eq 0 ]]; then
    log_success "All kernel headers already installed"
    return
  fi

  log_info "Installing headers for kernels: ${kernels[*]}"
  for pkg in "${headers_packages[@]}"; do
    log_info "Installing $pkg"
  done

  install_packages_quietly "${headers_packages[@]}"
}

generate_locales() {
  run_step "Generating locales" bash -c "sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen && sudo locale-gen"
}

install_paru() {
  step "Installing paru AUR helper"

  # Check if paru is already installed and working
  if command -v paru &>/dev/null && paru --version &>/dev/null; then
    log_success "paru is already installed and working"
    return 0
  fi

  # Install paru from source (not precompiled binary)
  log_info "Installing paru from source..."

  # Go to tmp directory
  local temp_dir=$(mktemp -d)
  local current_dir=$(pwd)
  cd "$temp_dir"

  # Download and install paru from source
  git clone https://aur.archlinux.org/paru.git
  cd paru
  makepkg -si --noconfirm --needed

  # Clean up build files and source
  cd "$current_dir"
  rm -rf "$temp_dir"

  # Clean package cache to save space
  if command -v paru &>/dev/null; then
    paru -Scc --noconfirm || true
  fi

  # Verify installation
  if command -v paru &>/dev/null && paru --version &>/dev/null; then
    log_success "paru installed successfully from source and cleaned up"
    return 0
  else
    log_error "paru installation failed"
    return 1
  fi
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
  install_paru
}

# Run main function
main
