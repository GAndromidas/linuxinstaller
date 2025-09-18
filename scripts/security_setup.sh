#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Use different variable names to avoid conflicts
SECURITY_INSTALLED=()
SECURITY_ENABLED=()
SECURITY_CONFIGURED=()

# ======= Fail2ban Setup Steps =======
install_fail2ban() {
  if pacman -Q fail2ban >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing: fail2ban ... [SKIP] Already installed${RESET}"
    return 0
  fi
  echo -ne "${CYAN}Installing: fail2ban ...${RESET} "
  if sudo pacman -S --needed --noconfirm fail2ban >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${RESET}"
    SECURITY_INSTALLED+=("fail2ban")
    return 0
  else
    echo -e "${RED}[FAIL]${RESET}"
    return 1
  fi
}

enable_and_start_fail2ban() {
  echo -ne "${CYAN}Enabling & starting: fail2ban ...${RESET} "
  if sudo systemctl enable --now fail2ban >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${RESET}"
    SECURITY_ENABLED+=("fail2ban")
    return 0
  else
    echo -e "${RED}[FAIL]${RESET}"
    return 1
  fi
}

configure_fail2ban() {
  local jail_local="/etc/fail2ban/jail.local"
  if [ ! -f "$jail_local" ]; then
    echo -ne "${CYAN}Configuring: jail.local ...${RESET} "
    sudo cp /etc/fail2ban/jail.conf "$jail_local"
    sudo sed -i 's/^backend = auto/backend = systemd/' "$jail_local"
    sudo sed -i 's/^bantime  = 10m/bantime = 30m/' "$jail_local"
    sudo sed -i 's/^maxretry = 5/maxretry = 3/' "$jail_local"
    echo -e "${GREEN}[OK]${RESET}"
    SECURITY_CONFIGURED+=("jail.local")
  else
    echo -e "${YELLOW}Configuring: jail.local ... [SKIP] Already exists${RESET}"
    log_warning "jail.local already exists. Skipping creation."
  fi
}

status_fail2ban() {
  echo -ne "${CYAN}Checking: fail2ban status ...${RESET} "
  if sudo systemctl status fail2ban --no-pager >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${RESET}"
    return 0
  else
    echo -e "${RED}[FAIL]${RESET}"
    return 1
  fi
}

# ======= Firewall Configuration =======
setup_firewall() {
  step "Setting up firewall protection"

  # First handle firewall setup
  if command -v firewalld >/dev/null 2>&1; then
    run_step "Configuring Firewalld" configure_firewalld
  else
    run_step "Installing and configuring UFW" configure_ufw
  fi
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
    SECURITY_CONFIGURED+=("firewalld-ssh")
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
    SECURITY_CONFIGURED+=("firewalld-kdeconnect")
  else
    log_warning "KDE Connect is not installed. Skipping KDE Connect service configuration."
  fi

  SECURITY_ENABLED+=("firewalld")
}

configure_ufw() {
  # Install UFW if not present
  if ! command -v ufw >/dev/null 2>&1; then
    install_packages_quietly ufw
    log_success "UFW installed successfully."
    SECURITY_INSTALLED+=("ufw")
  fi

  # Enable UFW
  sudo ufw enable
  SECURITY_ENABLED+=("ufw")

  # Set default policies
  sudo ufw default deny incoming
  log_success "Default policy set to deny all incoming connections."

  sudo ufw default allow outgoing
  log_success "Default policy set to allow all outgoing connections."

  # Allow SSH
  if ! sudo ufw status | grep -q "22/tcp"; then
    sudo ufw allow ssh
    log_success "SSH allowed through UFW."
    SECURITY_CONFIGURED+=("ufw-ssh")
  else
    log_warning "SSH is already allowed. Skipping SSH service configuration."
  fi

  # Check if KDE Connect is installed
  if pacman -Q kdeconnect &>/dev/null; then
    # Allow specific ports for KDE Connect
    sudo ufw allow 1714:1764/udp
    sudo ufw allow 1714:1764/tcp
    log_success "KDE Connect ports allowed through UFW."
    SECURITY_CONFIGURED+=("ufw-kdeconnect")
  else
    log_warning "KDE Connect is not installed. Skipping KDE Connect service configuration."
  fi
}

# ======= SSH Hardening =======
harden_ssh() {
  step "Hardening SSH configuration"

  local ssh_config="/etc/ssh/sshd_config"
  local ssh_backup="/etc/ssh/sshd_config.backup"

  # Create backup if it doesn't exist
  if [ ! -f "$ssh_backup" ]; then
    sudo cp "$ssh_config" "$ssh_backup"
    log_success "Created SSH config backup"
  fi

  # Apply SSH hardening settings
  local ssh_settings=(
    "PermitRootLogin no"
    "PasswordAuthentication yes"
    "PubkeyAuthentication yes"
    "X11Forwarding no"
    "MaxAuthTries 3"
    "ClientAliveInterval 300"
    "ClientAliveCountMax 2"
    "Protocol 2"
  )

  for setting in "${ssh_settings[@]}"; do
    local key=$(echo "$setting" | cut -d' ' -f1)
    local value=$(echo "$setting" | cut -d' ' -f2-)

    if grep -q "^#*$key" "$ssh_config"; then
      sudo sed -i "s/^#*$key.*/$setting/" "$ssh_config"
    else
      echo "$setting" | sudo tee -a "$ssh_config" >/dev/null
    fi
  done

  log_success "SSH hardening applied"
  SECURITY_CONFIGURED+=("ssh-hardening")

  # Test SSH config
  if sudo sshd -t; then
    log_success "SSH configuration is valid"
  else
    log_error "SSH configuration has errors - restoring backup"
    sudo cp "$ssh_backup" "$ssh_config"
    return 1
  fi
}

print_security_summary() {
  echo -e "\n${CYAN}======= SECURITY SETUP SUMMARY =======${RESET}"
  if [ ${#SECURITY_INSTALLED[@]} -gt 0 ]; then
    echo -e "${GREEN}Installed:${RESET} ${SECURITY_INSTALLED[*]}"
  fi
  if [ ${#SECURITY_ENABLED[@]} -gt 0 ]; then
    echo -e "${GREEN}Enabled:${RESET} ${SECURITY_ENABLED[*]}"
  fi
  if [ ${#SECURITY_CONFIGURED[@]} -gt 0 ]; then
    echo -e "${GREEN}Configured:${RESET} ${SECURITY_CONFIGURED[*]}"
  fi
  if [ ${#ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}Security setup completed successfully!${RESET}"
  else
    echo -e "${RED}Some steps failed:${RESET}"
    for err in "${ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  fi
  echo -e "${CYAN}=======================================${RESET}"
}

# ======= Main =======
main() {
  echo -e "${CYAN}=== Security Setup ===${RESET}"

  # Fail2ban configuration
  run_step "Installing fail2ban" install_fail2ban
  run_step "Enabling and starting fail2ban" enable_and_start_fail2ban
  run_step "Configuring fail2ban (jail.local)" configure_fail2ban
  run_step "Checking fail2ban status" status_fail2ban

  # Firewall configuration
  setup_firewall

  # SSH hardening
  run_step "Hardening SSH configuration" harden_ssh

  print_security_summary
}

main "$@"
