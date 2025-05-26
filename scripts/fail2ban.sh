#!/bin/bash

# ======= Colors and Step/Log Helpers =======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

CURRENT_STEP=1
ERRORS=()
INSTALLED=()
ENABLED=()
CONFIGURED=()

step() {
  echo -e "\n${CYAN}[$CURRENT_STEP] $1${RESET}"
  ((CURRENT_STEP++))
}

log_success() { echo -e "${GREEN}[OK] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_error()   { echo -e "${RED}[FAIL] $1${RESET}"; ERRORS+=("$1"); }

run_step() {
  local description="$1"
  shift
  step "$description"
  "$@"
  local status=$?
  if [ $status -eq 0 ]; then
    log_success "$description"
  else
    log_error "$description"
  fi
  return $status
}

# ======= Fail2ban Setup Steps =======

install_fail2ban() {
  if pacman -Q fail2ban >/dev/null 2>&1; then
    log_warning "fail2ban is already installed. Skipping."
    return 0
  fi
  sudo pacman -S --needed --noconfirm fail2ban
}

enable_and_start_fail2ban() {
  sudo systemctl enable --now fail2ban
}

configure_fail2ban() {
  # This is a basic example. Adjust to your custom config logic as needed.
  local jail_local="/etc/fail2ban/jail.local"
  if [ ! -f "$jail_local" ]; then
    sudo cp /etc/fail2ban/jail.conf "$jail_local"
    sudo sed -i 's/^backend = auto/backend = systemd/' "$jail_local"
    sudo sed -i 's/^bantime  = 10m/bantime = 30m/' "$jail_local"
    sudo sed -i 's/^maxretry = 5/maxretry = 3/' "$jail_local"
    log_success "Basic jail.local created and customized."
    CONFIGURED+=("jail.local")
  else
    log_warning "jail.local already exists. Skipping creation."
  fi
  # You can add more configuration or jail file tweaks below as needed.
}

status_fail2ban() {
  sudo systemctl status fail2ban --no-pager
}

print_summary() {
  echo -e "\n${CYAN}========= FAIL2BAN SUMMARY =========${RESET}"
  if [ ${#ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}Fail2ban installed and configured successfully!${RESET}"
  else
    echo -e "${RED}Some steps failed:${RESET}"
    for err in "${ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  fi
  echo -e "${CYAN}====================================${RESET}"
}

# ======= Main =======
main() {
  run_step "Installing fail2ban" install_fail2ban
  run_step "Enabling and starting fail2ban" enable_and_start_fail2ban
  run_step "Configuring fail2ban (jail.local)" configure_fail2ban
  run_step "Checking fail2ban status" status_fail2ban

  print_summary
}

main "$@"
