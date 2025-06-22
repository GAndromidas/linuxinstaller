#!/bin/bash
set -uo pipefail

# Clear terminal for clean interface
clear

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"

source "$SCRIPTS_DIR/common.sh"

arch_ascii
show_menu

echo -e "\n${YELLOW}Please enter your sudo password to begin the installation (it will not be echoed):${RESET}"
sudo -v || { echo -e "${RED}Sudo required. Exiting.${RESET}"; exit 1; }

# Keep sudo alive
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

exec > >(tee -a "$SCRIPT_DIR/install.log") 2>&1

echo -e "\n${GREEN}Starting Arch Linux installation...${RESET}\n"

# Run all installation steps with error handling
step "System Preparation" && source "$SCRIPTS_DIR/system_preparation.sh" || log_error "System preparation failed"
step "Shell Setup" && source "$SCRIPTS_DIR/shell_setup.sh" || log_error "Shell setup failed"
step "User Programs" && source "$SCRIPTS_DIR/user_programs.sh" || log_error "User programs failed"
step "System Services" && source "$SCRIPTS_DIR/system_services.sh" || log_error "System services failed"
step "System Boot Configuration" && source "$SCRIPTS_DIR/system_boot_config.sh" || log_error "System boot configuration failed"
step "Maintenance" && source "$SCRIPTS_DIR/maintenance.sh" || log_error "Maintenance failed"
step "Cleanup" && source "$SCRIPTS_DIR/cleanup.sh" || log_error "Cleanup failed"

echo -e "\n${GREEN}Installation completed successfully!${RESET}"
print_summary
prompt_reboot