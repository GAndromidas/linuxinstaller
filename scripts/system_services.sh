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
  # Enable all services at once without checking
  sudo systemctl enable --now \
    bluetooth.service \
    cronie.service \
    fstrim.timer \
    paccache.timer \
    power-profiles-daemon.service \
    reflector.service \
    reflector.timer \
    sshd.service \
    ufw.service \
    2>/dev/null || true
}

setup_zram_swap() {
  step "Setting up ZRAM swap"
  
  # Create ZRAM config in one command
  sudo tee /etc/systemd/zram-generator.conf > /dev/null << EOF
[zram0]
zram-size = ram * 0.5
compression-algorithm = zstd
swap-priority = 100
EOF
  
  # Enable and start ZRAM
  sudo systemctl enable --now systemd-zram-setup@zram0 2>/dev/null || true
}

cleanup_helpers() {
  run_step "Cleaning yay build dir" sudo rm -rf /tmp/yay
}

detect_and_install_gpu_drivers() {
  step "Installing basic graphics drivers"
  
  # Just install basic mesa - let user handle specific drivers
  install_packages_quietly mesa
  
  # Only do NVIDIA if explicitly detected
  if lspci | grep -qi nvidia; then
    echo -e "${YELLOW}NVIDIA GPU detected. Install drivers manually if needed.${RESET}"
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
  # All maintenance in one command
  {
    sudo paccache -r 2>/dev/null || true
    sudo pacman -Rns $(pacman -Qtdq 2>/dev/null) --noconfirm 2>/dev/null || true
    sudo pacman -Syu --noconfirm
    yay -Syu --noconfirm 2>/dev/null || true
  } >/dev/null 2>&1
}

cleanup_and_optimize() {
  step "Performing final cleanup and optimizations"
  
  # Check if lsblk is available for SSD detection
  if command_exists lsblk; then
    if lsblk -d -o rota | grep -q '^0$'; then
      run_step "Running fstrim on SSDs" sudo fstrim -v /
    fi
  else
    log_warning "lsblk not available. Skipping SSD optimization."
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