#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

setup_firewall_and_services() {
  step "Setting up firewall and services"

  # Firewall Logic: Prefer Firewalld if installed (Fedora default), else UFW (Ubuntu/Debian/Arch)
  if command -v firewalld >/dev/null 2>&1; then
    run_step "Configuring Firewalld" configure_firewalld
  else
    # Ensure UFW is installed if we are going to configure it
    install_packages_quietly ufw
    run_step "Configuring UFW" configure_ufw
  fi

  # Configure user groups
  run_step "Configuring user groups" configure_user_groups

  # Enable services
  run_step "Enabling system services" enable_services
  
  # ZRAM
  run_step "Configuring ZRAM" configure_zram
}

configure_firewalld() {
  if ! sudo systemctl enable --now firewalld; then
    log_error "Failed to start firewalld"
    return 1
  fi

  # Default secure zone
  sudo firewall-cmd --set-default-zone=public >/dev/null 2>&1
  # Allow SSH
  sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
  
  # Allow KDE Connect if needed
  if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
      sudo firewall-cmd --permanent --add-service=kde-connect >/dev/null 2>&1
  fi
  
  sudo firewall-cmd --reload >/dev/null 2>&1
  log_success "Firewalld configured."
}

configure_ufw() {
  # Enable UFW with defaults
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw limit ssh
  
  if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
      sudo ufw allow 1714:1764/udp
      sudo ufw allow 1714:1764/tcp
  fi
  
  # Force enable without prompt
  echo "y" | sudo ufw enable
  log_success "UFW configured."
}

configure_user_groups() {
  local groups=("input" "video" "storage")
  
  # Sudo group difference
  if [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
      groups+=("sudo")
  else
      groups+=("wheel")
  fi
  
  # Docker group check
  if command -v docker >/dev/null; then groups+=("docker"); fi
  
  log_info "Adding user to groups: ${groups[*]}"
  for group in "${groups[@]}"; do
      if getent group "$group" >/dev/null; then
          sudo usermod -aG "$group" "$USER"
      fi
  done
}

enable_services() {
    # Cron
    local cron_svc="cronie"
    if [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then cron_svc="cron"; fi
    
    if systemctl list-unit-files | grep -q "^$cron_svc"; then
        sudo systemctl enable --now "$cron_svc"
    fi
    
    # Bluetooth
    if command -v bluetoothd >/dev/null; then
        sudo systemctl enable --now bluetooth
    fi
    
    # SSH
    local ssh_svc="sshd"
    if [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then ssh_svc="ssh"; fi
    
    if systemctl list-unit-files | grep -q "^$ssh_svc"; then
        sudo systemctl enable --now "$ssh_svc"
    fi
    
    # Fstrim
    sudo systemctl enable --now fstrim.timer 2>/dev/null
}

configure_zram() {
    # Check if zram-generator is installed (Arch/Fedora)
    if command -v zramctl >/dev/null; then
        if [ "$DISTRO_ID" == "arch" ]; then
             if [ ! -f /etc/systemd/zram-generator.conf ]; then
                 echo -e "[zram0]\nzram-size = min(ram, 8192)\ncompression-algorithm = zstd" | sudo tee /etc/systemd/zram-generator.conf >/dev/null
                 sudo systemctl daemon-reload
                 sudo systemctl start systemd-zram-setup@zram0.service
             fi
        fi
        # Fedora has defaults usually
    fi
}

setup_firewall_and_services
