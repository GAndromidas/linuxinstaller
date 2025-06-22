#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"

source "$SCRIPTS_DIR/common.sh"

figlet_banner "Arch Installer"
arch_ascii
show_menu

echo -e "\n${YELLOW}Please enter your sudo password to begin the installation (it will not be echoed):${RESET}"
sudo -v || { echo -e "${RED}Sudo required. Exiting.${RESET}"; exit 1; }

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

exec > >(tee -a "$SCRIPT_DIR/install.log") 2>&1

echo -e "\n${GREEN}Starting installation with mode: $INSTALL_MODE${RESET}\n"

"$SCRIPTS_DIR/system_preparation.sh"
"$SCRIPTS_DIR/shell_setup.sh"
"$SCRIPTS_DIR/user_programs.sh"
"$SCRIPTS_DIR/system_boot_config.sh"
"$SCRIPTS_DIR/system_services.sh"

print_summary
prompt_reboot