#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup_fail2ban() {
  step "Setting up Fail2ban SSH Protection"

  # Install fail2ban
  # install_packages_quietly handles checking if installed and logging
  if ! install_packages_quietly fail2ban; then
    log_error "Failed to install fail2ban. Skipping configuration."
    return 1
  fi

  # Configure jail.local
  local jail_local="/etc/fail2ban/jail.local"

  if [ ! -f "$jail_local" ]; then
    log_info "Creating default jail.local configuration..."

    # Copy default config to local config to avoid overwriting on updates
    if sudo cp /etc/fail2ban/jail.conf "$jail_local"; then

      # Configure systemd backend (essential for Arch Linux)
      sudo sed -i 's/^backend = auto/backend = systemd/' "$jail_local"

      # Apply stricter security policies
      # Increase ban time to 1 hour (default 10m)
      sudo sed -i 's/^bantime  = 10m/bantime = 1h/' "$jail_local"

      # Keep find time at 10m
      sudo sed -i 's/^findtime  = 10m/findtime = 10m/' "$jail_local"

      # Decrease max retries to 3 (default 5)
      sudo sed -i 's/^maxretry = 5/maxretry = 3/' "$jail_local"

      log_success "Configured jail.local with hardened defaults (systemd backend, 1h ban, 3 retries)"
    else
      log_error "Failed to create $jail_local from jail.conf"
    fi
  else
    log_info "Configuration file $jail_local already exists. Skipping default configuration."
  fi

  # Enable and start the service
  log_info "Enabling and starting fail2ban service..."
  if sudo systemctl enable --now fail2ban >/dev/null 2>&1; then
    log_success "Fail2ban service enabled and started"
  else
    log_error "Failed to enable fail2ban service"
    return 1
  fi

  # Verify service status
  if systemctl is-active --quiet fail2ban; then
    log_success "Fail2ban is active and protecting your system"

    # Optional: Display active jails if any
    if command -v fail2ban-client >/dev/null; then
      local status_output
      status_output=$(sudo fail2ban-client status 2>/dev/null)
      if [ $? -eq 0 ]; then
        local jails=$(echo "$status_output" | grep "Jail list" | cut -d: -f2 | tr -d '\t')
        log_info "Active jails:${jails}"
      fi
    fi
  else
    log_warning "Fail2ban service is not running correctly. Check logs: sudo journalctl -u fail2ban"
    return 1
  fi
}

# Execute the setup
setup_fail2ban
