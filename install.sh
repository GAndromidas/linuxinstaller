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
  local requirements_failed=false

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

  # Only show success message if we had to check something specific
  # For now, we'll just silently continue if all requirements are met
}

check_system_requirements
show_menu
export INSTALL_MODE

# Silently install gum for beautiful UI throughout the script
if ! command -v gum >/dev/null 2>&1; then
  sudo pacman -S --noconfirm gum >/dev/null 2>&1 || true
fi

# Use gum for beautiful sudo prompt if available
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 226 "Please enter your sudo password to begin the installation:"
  sudo -v || { gum style --foreground 196 "Sudo required. Exiting."; exit 1; }
else
  echo -e "${YELLOW}Please enter your sudo password to begin the installation:${RESET}"
  sudo -v || { echo -e "${RED}Sudo required. Exiting.${RESET}"; exit 1; }
fi

# Keep sudo alive
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

# Use gum for beautiful installation start message
if command -v gum >/dev/null 2>&1; then
  echo ""
  gum style --border double --margin "1 2" --padding "1 4" --foreground 46 --border-foreground 46 "🚀 Starting Arch Linux Installation"
  gum style --margin "1 0" --foreground 226 "⏱️  This process will take approximately 10-20 minutes depending on your internet speed."
  gum style --margin "0 0 1 0" --foreground 226 "💡 You can safely leave this running - it will handle everything automatically!"
else
  echo -e "\n${GREEN}🚀 Starting Arch Linux installation...${RESET}"
  echo -e "${YELLOW}⏱️  This process will take approximately 10-20 minutes depending on your internet speed.${RESET}"
  echo -e "${YELLOW}💡 You can safely leave this running - it will handle everything automatically!${RESET}"
  echo ""
fi

# Run all installation steps with error handling and debugging
# Use gum for step headers if available
if command -v gum >/dev/null 2>&1; then
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 1: System Preparation"
  gum style --foreground 226 "📦 Updating package lists and installing system utilities..."
else
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
  echo -e "${CYAN}Step 1: System Preparation${RESET}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
  echo -e "${YELLOW}📦 Updating package lists and installing system utilities...${RESET}"
fi
step "System Preparation" && source "$SCRIPTS_DIR/system_preparation.sh" || log_error "System preparation failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 1 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 2: Shell Setup"
  gum style --foreground 226 "🐚 Installing ZSH shell with autocompletion and syntax highlighting..."
else
  echo -e "${GREEN}✓ Step 1 completed${RESET}"
  echo -e "${CYAN}Step 2: Shell Setup${RESET}"
  echo -e "${YELLOW}🐚 Installing ZSH shell with autocompletion and syntax highlighting...${RESET}"
fi
step "Shell Setup" && source "$SCRIPTS_DIR/shell_setup.sh" || log_error "Shell setup failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 2 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 3: Plymouth Setup"
  gum style --foreground 226 "🎨 Setting up beautiful boot screen..."
else
  echo -e "${GREEN}✓ Step 2 completed${RESET}"
  echo -e "${CYAN}Step 3: Plymouth Setup${RESET}"
  echo -e "${YELLOW}🎨 Setting up beautiful boot screen...${RESET}"
fi
step "Plymouth Setup" && source "$SCRIPTS_DIR/plymouth.sh" || log_error "Plymouth setup failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 3 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 4: Yay Installation"
  gum style --foreground 226 "📦 Installing AUR helper for additional software..."
else
  echo -e "${GREEN}✓ Step 3 completed${RESET}"
  echo -e "${CYAN}Step 4: Yay Installation${RESET}"
  echo -e "${YELLOW}📦 Installing AUR helper for additional software...${RESET}"
fi
step "Yay Installation" && source "$SCRIPTS_DIR/yay.sh" || log_error "Yay installation failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 4 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 5: Programs Installation"
  gum style --foreground 226 "🖥️  Installing applications based on your desktop environment..."
else
  echo -e "${GREEN}✓ Step 4 completed${RESET}"
  echo -e "${CYAN}Step 5: Programs Installation${RESET}"
  echo -e "${YELLOW}🖥️  Installing applications based on your desktop environment...${RESET}"
fi
step "Programs Installation" && source "$SCRIPTS_DIR/programs.sh" || log_error "Programs installation failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 5 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 6: Gaming Mode"
  gum style --foreground 226 "🎮 Setting up gaming tools (optional)..."
else
  echo -e "${GREEN}✓ Step 5 completed${RESET}"
  echo -e "${CYAN}Step 6: Gaming Mode${RESET}"
  echo -e "${YELLOW}🎮 Setting up gaming tools (optional)...${RESET}"
fi
step "Gaming Mode" && source "$SCRIPTS_DIR/gaming_mode.sh" || log_error "Gaming Mode failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 6 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 7: Bootloader and Kernel Configuration"
  gum style --foreground 226 "🔧 Configuring bootloader and setting up dual-boot with Windows..."
else
  echo -e "${GREEN}✓ Step 6 completed${RESET}"
  echo -e "${CYAN}Step 7: Bootloader and Kernel Configuration${RESET}"
  echo -e "${YELLOW}🔧 Configuring bootloader and setting up dual-boot with Windows...${RESET}"
fi
step "Bootloader and Kernel Configuration" && source "$SCRIPTS_DIR/bootloader_config.sh" || log_error "Bootloader and kernel configuration failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 7 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 8: Fail2ban Setup"
  gum style --foreground 226 "🛡️  Setting up security protection for SSH..."
else
  echo -e "${GREEN}✓ Step 7 completed${RESET}"
  echo -e "${CYAN}Step 8: Fail2ban Setup${RESET}"
  echo -e "${YELLOW}🛡️  Setting up security protection for SSH...${RESET}"
fi
step "Fail2ban Setup" && source "$SCRIPTS_DIR/fail2ban.sh" || log_error "Fail2ban setup failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 8 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 9: System Services"
  gum style --foreground 226 "⚙️  Enabling and configuring system services..."
else
  echo -e "${GREEN}✓ Step 8 completed${RESET}"
  echo -e "${CYAN}Step 9: System Services${RESET}"
  echo -e "${YELLOW}⚙️  Enabling and configuring system services...${RESET}"
fi
step "System Services" && source "$SCRIPTS_DIR/system_services.sh" || log_error "System services failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 9 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 10: Maintenance"
  gum style --foreground 226 "🧹 Final cleanup and system optimization..."
else
  echo -e "${GREEN}✓ Step 9 completed${RESET}"
  echo -e "${CYAN}Step 10: Maintenance${RESET}"
  echo -e "${YELLOW}🧹 Final cleanup and system optimization...${RESET}"
fi
step "Maintenance" && source "$SCRIPTS_DIR/maintenance.sh" || log_error "Maintenance failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 10 completed"
  echo ""
else
  echo -e "${GREEN}✓ Step 10 completed${RESET}"
  echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
  echo -e "${GREEN}🎉 INSTALLATION COMPLETED SUCCESSFULLY! 🎉${RESET}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
fi
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

# Handle installation results with gum styling
if [ ${#ERRORS[@]} -eq 0 ]; then
  if command -v gum >/dev/null 2>&1; then
    echo ""
    gum style --foreground 46 "✅ All steps completed successfully!"
    gum style --foreground 226 "🧹 Cleaning up installer files..."
  else
    echo -e "\n${GREEN}✅ All steps completed successfully!${RESET}"
    echo -e "${YELLOW}🧹 Cleaning up installer files...${RESET}"
  fi
  cd "$SCRIPT_DIR/.."
  rm -rf "$(basename "$SCRIPT_DIR")"
  if command -v gum >/dev/null 2>&1; then
    gum style --foreground 46 "✓ Installer files cleaned up"
  else
    echo -e "${GREEN}✓ Installer files cleaned up${RESET}"
  fi
else
  if command -v gum >/dev/null 2>&1; then
    echo ""
    gum style --foreground 226 "⚠️  Some errors occurred during installation:"
    for error in "${ERRORS[@]}"; do
      gum style --margin "0 2" --foreground 196 "• $error"
    done
    echo ""
    gum style --foreground 226 "💡 Don't worry! Most errors are non-critical and your system should still work."
    gum style --foreground 226 "   The installer directory has been preserved so you can review what happened."
    gum style --foreground 226 "   You can run the installer again to fix any issues."
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
fi

prompt_reboot
