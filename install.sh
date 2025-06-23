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
export INSTALL_MODE

echo -e "${YELLOW}Please enter your sudo password to begin the installation:${RESET}"
sudo -v || { echo -e "${RED}Sudo required. Exiting.${RESET}"; exit 1; }

# Keep sudo alive
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

exec > >(tee -a "$SCRIPT_DIR/install.log") 2>&1

echo -e "\n${GREEN}Starting Arch Linux installation...${RESET}\n"

# Run all installation steps with error handling and debugging
echo -e "${CYAN}Step 1: System Preparation${RESET}"
step "System Preparation" && source "$SCRIPTS_DIR/system_preparation.sh" || log_error "System preparation failed"
echo -e "${CYAN}Step 1 completed${RESET}"

echo -e "${CYAN}Step 2: Shell Setup${RESET}"
step "Shell Setup" && source "$SCRIPTS_DIR/shell_setup.sh" || log_error "Shell setup failed"
echo -e "${CYAN}Step 2 completed${RESET}"

echo -e "${CYAN}Step 3: Plymouth Setup${RESET}"
step "Plymouth Setup" && source "$SCRIPTS_DIR/plymouth.sh" || log_error "Plymouth setup failed"
echo -e "${CYAN}Step 3 completed${RESET}"

echo -e "${CYAN}Step 4: Yay Installation${RESET}"
step "Yay Installation" && source "$SCRIPTS_DIR/yay.sh" || log_error "Yay installation failed"
echo -e "${CYAN}Step 4 completed${RESET}"

echo -e "${CYAN}Step 5: Programs Installation${RESET}"
step "Programs Installation" && source "$SCRIPTS_DIR/programs.sh" || log_error "Programs installation failed"
echo -e "${CYAN}Step 5 completed${RESET}"

echo -e "${CYAN}Step 6: GameMode Installation${RESET}"
step "GameMode Installation" && source "$SCRIPTS_DIR/gamemode.sh" install || log_error "GameMode installation failed"
echo -e "${CYAN}Step 6 completed${RESET}"

echo -e "${CYAN}Step 7: Fail2ban Setup${RESET}"
step "Fail2ban Setup" && source "$SCRIPTS_DIR/fail2ban.sh" || log_error "Fail2ban setup failed"
echo -e "${CYAN}Step 7 completed${RESET}"

echo -e "${CYAN}Step 8: System Services${RESET}"
step "System Services" && source "$SCRIPTS_DIR/system_services.sh" || log_error "System services failed"
echo -e "${CYAN}Step 8 completed${RESET}"

echo -e "${CYAN}Step 9: System Boot Configuration${RESET}"
step "System Boot Configuration" && source "$SCRIPTS_DIR/system_boot_config.sh" || log_error "System boot configuration failed"
echo -e "${CYAN}Step 9 completed${RESET}"

echo -e "${CYAN}Step 10: Maintenance${RESET}"
step "Maintenance" && source "$SCRIPTS_DIR/maintenance.sh" || log_error "Maintenance failed"
echo -e "${CYAN}Step 10 completed${RESET}"

echo -e "${CYAN}Step 11: Cleanup${RESET}"
step "Cleanup" && source "$SCRIPTS_DIR/cleanup.sh" || log_error "Cleanup failed"
echo -e "${CYAN}Step 11 completed${RESET}"

echo -e "\n${GREEN}Installation completed successfully!${RESET}"
print_summary
prompt_reboot