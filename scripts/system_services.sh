#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

setup_firewall_and_services() {
  step "Setting up firewall and services"
  
  # First handle firewall setup
  if command -v firewalld >/dev/null 2>&1; then
    run_step "Configuring Firewalld" configure_firewalld
  else
    run_step "Configuring UFW" configure_ufw
  fi
  
  # Then handle services
  run_step "Enabling system services" enable_services
}

configure_firewalld() {
  # Start and enable firewalld
  sudo systemctl start firewalld
  sudo systemctl enable firewalld

  # Set default policies
  sudo firewall-cmd --set-default-zone=drop
  log_success "Default policy set to deny all incoming connections."

  sudo firewall-cmd --set-default-zone=public
  log_success "Default policy set to allow all outgoing connections."

  # Allow SSH
  if ! sudo firewall-cmd --list-all | grep -q "22/tcp"; then
    sudo firewall-cmd --add-service=ssh --permanent
    sudo firewall-cmd --reload
    log_success "SSH allowed through Firewalld."
  else
    log_warning "SSH is already allowed. Skipping SSH service configuration."
  fi

  # Check if KDE Connect is installed
  if pacman -Q kdeconnect &>/dev/null; then
    # Allow specific ports for KDE Connect
    sudo firewall-cmd --add-port=1714-1764/udp --permanent
    sudo firewall-cmd --add-port=1714-1764/tcp --permanent
    sudo firewall-cmd --reload
    log_success "KDE Connect ports allowed through Firewalld."
  else
    log_warning "KDE Connect is not installed. Skipping KDE Connect service configuration."
  fi
}

configure_ufw() {
  # Install UFW if not present
  if ! command -v ufw >/dev/null 2>&1; then
    install_packages_quietly ufw
    log_success "UFW installed successfully."
  fi

  # Enable UFW
  sudo ufw enable

  # Set default policies
  sudo ufw default deny incoming
  log_success "Default policy set to deny all incoming connections."

  sudo ufw default allow outgoing
  log_success "Default policy set to allow all outgoing connections."

  # Allow SSH
  if ! sudo ufw status | grep -q "22/tcp"; then
    sudo ufw allow ssh
    log_success "SSH allowed through UFW."
  else
    log_warning "SSH is already allowed. Skipping SSH service configuration."
  fi

  # Check if KDE Connect is installed
  if pacman -Q kdeconnect &>/dev/null; then
    # Allow specific ports for KDE Connect
    sudo ufw allow 1714:1764/udp
    sudo ufw allow 1714:1764/tcp
    log_success "KDE Connect ports allowed through UFW."
  else
    log_warning "KDE Connect is not installed. Skipping KDE Connect service configuration."
  fi
}

enable_services() {
  local services=(
    "bluetooth.service"
    "cronie.service"
    "fstrim.timer"
    "paccache.timer"
    "power-profiles-daemon.service"
    "reflector.service"
    "reflector.timer"
    "sshd.service"
    "ufw.service"
  )

  for service in "${services[@]}"; do
    if [ -f "/usr/lib/systemd/system/$service" ] || [ -f "/etc/systemd/system/$service" ]; then
      sudo systemctl enable --now "$service"
      log_success "$service enabled."
    else
      log_warning "$service is not installed or not available as a systemd service. Skipping."
    fi
  done
}

setup_zram_swap() {
  step "Setting up ZRAM swap"
  
  # Install zram-generator if not present
  if ! pacman -Q zram-generator &>/dev/null; then
    install_packages_quietly zram-generator
  else
    log_warning "zram-generator is already installed. Skipping installation."
  fi

  # Stop and disable existing ZRAM service if it's running
  if systemctl is-active --quiet systemd-zram-setup@zram0; then
    log_warning "Stopping existing ZRAM service..."
    sudo systemctl stop systemd-zram-setup@zram0
    sudo systemctl disable systemd-zram-setup@zram0
  fi

  # Create or update zram-generator configuration
  local ZRAM_CONF="/etc/systemd/zram-generator.conf"
  
  # Create new configuration regardless of existing one
  sudo tee "$ZRAM_CONF" > /dev/null << EOF
[zram0]
zram-size = ram * 0.5
compression-algorithm = zstd
swap-priority = 100
EOF
  log_success "ZRAM configuration created/updated at $ZRAM_CONF"

  # Re-enable and start ZRAM
  log_warning "Re-enabling ZRAM swap..."
  sudo systemctl daemon-reexec
  sudo systemctl enable systemd-zram-setup@zram0
  sudo systemctl start systemd-zram-setup@zram0

  # Verify ZRAM is working
  if systemctl is-active --quiet systemd-zram-setup@zram0; then
    log_success "ZRAM swap has been successfully configured and activated"
    echo -e "${CYAN}Current swap status:${RESET}"
    swapon --show
  else
    log_error "Failed to activate ZRAM swap. Please check the system logs for details."
  fi
}

cleanup_helpers() {
  run_step "Cleaning yay build dir" sudo rm -rf /tmp/yay
}

detect_and_install_gpu_drivers() {
  step "Detecting GPU and installing appropriate drivers"
  local GPU_INFO
  GPU_INFO=$(lspci | grep -E "VGA|3D")
  if echo "$GPU_INFO" | grep -qi nvidia; then
    echo -e "${YELLOW}NVIDIA GPU detected!${RESET}"
    echo "Choose a driver to install:"
    echo "  1) Open-source NVIDIA (nvidia-open-dkms) with Vulkan"
    echo "  2) Latest proprietary (nvidia-dkms)"
    echo "  3) Legacy 390xx (AUR, very old cards)"
    echo "  4) Legacy 340xx (AUR, ancient cards)"
    echo "  5) Open-source Nouveau (recommended for unsupported/old cards)"
    echo "  6) Skip GPU driver installation"
    read -r -p "Enter your choice [1-6, default 1]: " nvidia_choice
    case "$nvidia_choice" in
      1)
        step "Installing Open-source NVIDIA driver with Vulkan support"
        install_packages_quietly nvidia-open-dkms nvidia-utils
        ;;
      2)
        step "Installing NVIDIA DKMS driver"
        install_packages_quietly nvidia-dkms nvidia-utils
        ;;
      3)
        run_step "Installing NVIDIA 390xx legacy DKMS driver" yay -S --noconfirm --needed nvidia-390xx-dkms nvidia-390xx-utils lib32-nvidia-390xx-utils
        ;;
      4)
        run_step "Installing NVIDIA 340xx legacy DKMS driver" yay -S --noconfirm --needed nvidia-340xx-dkms nvidia-340xx-utils lib32-nvidia-340xx-utils
        ;;
      6)
        echo -e "${YELLOW}Skipping NVIDIA driver installation.${RESET}"
        ;;
      ""|5|*)
        step "Installing open-source Nouveau driver for NVIDIA"
        install_packages_quietly xf86-video-nouveau mesa
        ;;
    esac
  elif echo "$GPU_INFO" | grep -qi amd; then
    step "Installing AMDGPU drivers"
    install_packages_quietly xf86-video-amdgpu mesa
  elif echo "$GPU_INFO" | grep -qi intel; then
    step "Installing Intel graphics drivers"
    install_packages_quietly mesa xf86-video-intel
  else
    log_warning "No supported GPU detected or unable to determine GPU vendor."
  fi
}

remove_orphans() {
  orphans=$(pacman -Qtdq 2>/dev/null || true)
  if [[ -n "$orphans" ]]; then
    sudo pacman -Rns --noconfirm $orphans
  else
    echo "No orphaned packages to remove."
  fi
}

setup_maintenance() {
  if command -v paccache >/dev/null; then
    run_step "Cleaning pacman cache (keep last 3 packages)" sudo paccache -r
  else
    log_warning "paccache not found. Skipping paccache cache cleaning."
  fi
  run_step "Removing orphaned packages" remove_orphans
  run_step "System update" sudo pacman -Syu --noconfirm
  if command -v yay >/dev/null; then
    run_step "AUR update (yay)" yay -Syu --noconfirm
  fi
}

cleanup_and_optimize() {
  step "Performing final cleanup and optimizations"
  if lsblk -d -o rota | grep -q '^0$'; then
    run_step "Running fstrim on SSDs" sudo fstrim -v /
  fi
  run_step "Cleaning /tmp directory" sudo rm -rf /tmp/*

  if [[ -d "$SCRIPT_DIR" ]]; then
    if [ "${#ERRORS[@]}" -eq 0 ]; then
      cd "$HOME"
      run_step "Deleting installer directory" rm -rf "$SCRIPT_DIR"
    else
      echo -e "\n${YELLOW}Issues detected during installation. The installer folder and install.log will NOT be deleted.${RESET}\n"
      echo -e "${RED}ERROR: One or more steps failed. Please check the log for details:${RESET}"
      echo -e "${CYAN}$SCRIPT_DIR/install.log${RESET}\n"
    fi
  fi

  run_step "Syncing disk writes" sync
}

# Execute all service and maintenance steps
setup_firewall_and_services
setup_zram_swap
cleanup_helpers
detect_and_install_gpu_drivers
setup_maintenance
cleanup_and_optimize 