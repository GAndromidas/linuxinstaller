#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

FAIL2BAN_ERRORS=()
INSTALLED=()
ENABLED=()
CONFIGURED=()

# ======= Fail2ban Setup Steps =======
install_fail2ban() {
  step "Installing fail2ban"
  install_packages_quietly fail2ban
}

enable_and_start_fail2ban() {
  step "Enabling and starting fail2ban"
  if sudo systemctl enable --now fail2ban >/dev/null 2>&1; then
    log_success "Fail2ban enabled and started"
    ENABLED+=("fail2ban")
    return 0
  else
    log_error "Failed to enable and start fail2ban"
    return 1
  fi
}

configure_fail2ban() {
  step "Configuring fail2ban (jail.local)"
  local jail_local="/etc/fail2ban/jail.local"
  if [ ! -f "$jail_local" ]; then
    sudo cp /etc/fail2ban/jail.conf "$jail_local"
    sudo sed -i 's/^backend = auto/backend = systemd/' "$jail_local"
    sudo sed -i 's/^bantime  = 10m/bantime = 30m/' "$jail_local"
    sudo sed -i 's/^maxretry = 5/maxretry = 3/' "$jail_local"
    log_success "Fail2ban configured"
    CONFIGURED+=("jail.local")
  else
    log_warning "jail.local already exists. Skipping creation."
  fi
}

status_fail2ban() {
  step "Checking fail2ban status"
  if sudo systemctl status fail2ban --no-pager >/dev/null 2>&1; then
    log_success "Fail2ban is running"
    return 0
  else
    log_error "Fail2ban is not running"
    return 1
  fi
}

print_summary() {
  echo -e "\n${CYAN}========= FAIL2BAN SUMMARY =========${RESET}"
  if [ ${#INSTALLED[@]} -gt 0 ]; then
    echo -e "${GREEN}Installed:${RESET} ${INSTALLED[*]}"
  fi
  if [ ${#ENABLED[@]} -gt 0 ]; then
    echo -e "${GREEN}Enabled:${RESET} ${ENABLED[*]}"
  fi
  if [ ${#CONFIGURED[@]} -gt 0 ]; then
    echo -e "${GREEN}Configured:${RESET} ${CONFIGURED[*]}"
  fi
  if [ ${#FAIL2BAN_ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}Fail2ban installed and configured successfully!${RESET}"
  else
    echo -e "${RED}Some steps failed:${RESET}"
    for err in "${FAIL2BAN_ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  fi
  echo -e "${CYAN}====================================${RESET}"
}

# ======= Main =======
main() {
  echo -e "${CYAN}=== Fail2ban Setup ===${RESET}"

  install_fail2ban
  enable_and_start_fail2ban
  configure_fail2ban
  status_fail2ban

  print_summary
}

main "$@"