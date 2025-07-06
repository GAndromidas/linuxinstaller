#!/bin/bash
set -uo pipefail

# Clear terminal for clean interface
clear

# Get the directory where this script is located (archinstaller root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"

source "$SCRIPTS_DIR/common.sh"

START_TIME=$(date +%s)

arch_ascii

# Check system requirements for new users
check_system_requirements() {
  echo -e "${CYAN}🔍 Checking system requirements...${RESET}"
  
  # Check if running as root
  if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}❌ Error: This script should NOT be run as root!${RESET}"
    echo -e "${YELLOW}   Please run as a regular user with sudo privileges.${RESET}"
    echo -e "${YELLOW}   Example: ./install.sh (not sudo ./install.sh)${RESET}"
    exit 1
  fi
  
  # Check if we're on Arch Linux
  if [[ ! -f /etc/arch-release ]]; then
    echo -e "${RED}❌ Error: This script is designed for Arch Linux only!${RESET}"
    echo -e "${YELLOW}   Please run this on a fresh Arch Linux installation.${RESET}"
    exit 1
  fi
  
  # Check internet connection
  if ! ping -c 1 archlinux.org &>/dev/null; then
    echo -e "${RED}❌ Error: No internet connection detected!${RESET}"
    echo -e "${YELLOW}   Please check your network connection and try again.${RESET}"
    exit 1
  fi
  
  # Check available disk space (at least 2GB)
  local available_space=$(df / | awk 'NR==2 {print $4}')
  if [[ $available_space -lt 2097152 ]]; then
    echo -e "${RED}❌ Error: Insufficient disk space!${RESET}"
    echo -e "${YELLOW}   At least 2GB free space is required.${RESET}"
    echo -e "${YELLOW}   Available: $((available_space / 1024 / 1024))GB${RESET}"
    exit 1
  fi
  
  echo -e "${GREEN}✓ System requirements met!${RESET}"
  echo ""
}

check_system_requirements
show_menu
export INSTALL_MODE

echo -e "${YELLOW}Please enter your sudo password to begin the installation:${RESET}"
sudo -v || { echo -e "${RED}Sudo required. Exiting.${RESET}"; exit 1; }

# Keep sudo alive
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

echo -e "\n${GREEN}🚀 Starting Arch Linux installation...${RESET}"
echo -e "${YELLOW}⏱️  This process will take approximately 10-20 minutes depending on your internet speed.${RESET}"
echo -e "${YELLOW}💡 You can safely leave this running - it will handle everything automatically!${RESET}"
echo ""

# Run all installation steps with error handling and debugging
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}Step 1: System Preparation${RESET}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${YELLOW}📦 Updating package lists and installing system utilities...${RESET}"
step "System Preparation" && source "$SCRIPTS_DIR/system_preparation.sh" || log_error "System preparation failed"
echo -e "${GREEN}✓ Step 1 completed${RESET}"

echo -e "${CYAN}Step 2: Shell Setup${RESET}"
echo -e "${YELLOW}🐚 Installing ZSH shell with autocompletion and syntax highlighting...${RESET}"
step "Shell Setup" && source "$SCRIPTS_DIR/shell_setup.sh" || log_error "Shell setup failed"
echo -e "${GREEN}✓ Step 2 completed${RESET}"

echo -e "${CYAN}Step 3: Plymouth Setup${RESET}"
echo -e "${YELLOW}🎨 Setting up beautiful boot screen...${RESET}"
step "Plymouth Setup" && source "$SCRIPTS_DIR/plymouth.sh" || log_error "Plymouth setup failed"
echo -e "${GREEN}✓ Step 3 completed${RESET}"

echo -e "${CYAN}Step 4: Yay Installation${RESET}"
echo -e "${YELLOW}📦 Installing AUR helper for additional software...${RESET}"
step "Yay Installation" && source "$SCRIPTS_DIR/yay.sh" || log_error "Yay installation failed"
echo -e "${GREEN}✓ Step 4 completed${RESET}"

echo -e "${CYAN}Step 5: Programs Installation${RESET}"
echo -e "${YELLOW}🖥️  Installing applications based on your desktop environment...${RESET}"
step "Programs Installation" && source "$SCRIPTS_DIR/programs.sh" || log_error "Programs installation failed"
echo -e "${GREEN}✓ Step 5 completed${RESET}"

echo -e "${CYAN}Step 6: Gaming Mode${RESET}"
echo -e "${YELLOW}🎮 Setting up gaming tools (optional)...${RESET}"
step "Gaming Mode" && source "$SCRIPTS_DIR/gaming_mode.sh" || log_error "Gaming Mode failed"
echo -e "${GREEN}✓ Step 6 completed${RESET}"

echo -e "${CYAN}Step 7: Bootloader and Kernel Configuration${RESET}"
echo -e "${YELLOW}🔧 Configuring bootloader and setting up dual-boot with Windows...${RESET}"
step "Bootloader and Kernel Configuration" && source "$SCRIPTS_DIR/bootloader_config.sh" || log_error "Bootloader and kernel configuration failed"
echo -e "${GREEN}✓ Step 7 completed${RESET}"

echo -e "${CYAN}Step 8: Fail2ban Setup${RESET}"
echo -e "${YELLOW}🛡️  Setting up security protection for SSH...${RESET}"
step "Fail2ban Setup" && source "$SCRIPTS_DIR/fail2ban.sh" || log_error "Fail2ban setup failed"
echo -e "${GREEN}✓ Step 8 completed${RESET}"

echo -e "${CYAN}Step 9: System Services${RESET}"
echo -e "${YELLOW}⚙️  Enabling and configuring system services...${RESET}"
step "System Services" && source "$SCRIPTS_DIR/system_services.sh" || log_error "System services failed"
echo -e "${GREEN}✓ Step 9 completed${RESET}"

echo -e "${CYAN}Step 10: Maintenance${RESET}"
echo -e "${YELLOW}🧹 Final cleanup and system optimization...${RESET}"
step "Maintenance" && source "$SCRIPTS_DIR/maintenance.sh" || log_error "Maintenance failed"
echo -e "${GREEN}✓ Step 10 completed${RESET}"

echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}🎉 INSTALLATION COMPLETED SUCCESSFULLY! 🎉${RESET}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${YELLOW}🎯 What's been set up for you:${RESET}"
echo -e "  • 🖥️  Desktop environment with all essential applications"
echo -e "  • 🛡️  Security features (firewall, SSH protection)"
echo -e "  • ⚡ Performance optimizations (ZRAM, boot screen)"
echo -e "  • 🎮 Gaming tools (if you chose Gaming Mode)"
echo -e "  • 🔧 Dual-boot with Windows (if detected)"
echo -e "  • 🐚 Enhanced shell with autocompletion"
echo ""
print_programs_summary
print_summary
log_performance "Total installation time"

# Handle installation results
if [ ${#ERRORS[@]} -eq 0 ]; then
  echo -e "\n${GREEN}✅ All steps completed successfully!${RESET}"
  echo -e "${YELLOW}🧹 Cleaning up installer files...${RESET}"
  cd "$SCRIPT_DIR/.."
  rm -rf "$(basename "$SCRIPT_DIR")"
  echo -e "${GREEN}✓ Installer files cleaned up${RESET}"
else
  echo -e "\n${YELLOW}⚠️  Some errors occurred during installation:${RESET}"
  for error in "${ERRORS[@]}"; do
    echo -e "${RED}   • $error${RESET}"
  done
  echo ""
  echo -e "${YELLOW}💡 Don't worry! Most errors are non-critical and your system should still work.${RESET}"
  echo -e "${YELLOW}   The installer directory has been preserved so you can review what happened.${RESET}"
  echo -e "${YELLOW}   You can run the installer again to fix any issues.${RESET}"
fi

prompt_reboot