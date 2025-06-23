#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ======= Colors and Step/Log Helpers =======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

CURRENT_STEP=1
FAIL2BAN_ERRORS=()
INSTALLED=()
ENABLED=()
CONFIGURED=()

step() {
  echo -e "\n${CYAN}[$CURRENT_STEP] $1${RESET}"
  ((CURRENT_STEP++))
}

log_success() { echo -e "${GREEN}[OK] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_error()   { echo -e "${RED}[FAIL] $1${RESET}"; FAIL2BAN_ERRORS+=("$1"); }

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
    echo -e "${YELLOW}Installing: fail2ban ... [SKIP] Already installed${RESET}"
    return 0
  fi
  echo -ne "${CYAN}Installing: fail2ban ...${RESET} "
  if sudo pacman -S --needed --noconfirm fail2ban >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${RESET}"
    INSTALLED+=("fail2ban")
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
    ENABLED+=("fail2ban")
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
    CONFIGURED+=("jail.local")
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

  run_step "Installing fail2ban" install_fail2ban
  run_step "Enabling and starting fail2ban" enable_and_start_fail2ban
  run_step "Configuring fail2ban (jail.local)" configure_fail2ban
  run_step "Checking fail2ban status" status_fail2ban

  print_summary
}

main "$@"