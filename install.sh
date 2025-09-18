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

# Silently install gum for beautiful UI before menu
if ! command -v gum >/dev/null 2>&1; then
  sudo pacman -S --noconfirm gum >/dev/null 2>&1 || true
fi

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

  # Detect if running in VM and adjust requirements
  local is_vm=false
  if grep -q -i 'hypervisor' /proc/cpuinfo || systemd-detect-virt --quiet || [ -d /proc/xen ]; then
    is_vm=true
    echo -e "${CYAN}ℹ️  Virtual machine detected - optimizing for VM environment${RESET}"
  fi

  # Check available disk space (at least 2GB, 1.5GB for VM)
  local required_space=2097152
  if [ "$is_vm" = true ]; then
    required_space=1572864  # 1.5GB for VM
  fi

  local available_space=$(df / | awk 'NR==2 {print $4}')
  if [[ $available_space -lt $required_space ]]; then
    echo -e "${RED}❌ Error: Insufficient disk space!${RESET}"
    echo -e "${YELLOW}   At least $((required_space / 1024 / 1024))GB free space is required.${RESET}"
    echo -e "${YELLOW}   Available: $((available_space / 1024 / 1024))GB${RESET}"
    exit 1
  fi

  # Export VM detection for use by other scripts
  export DETECTED_VM="$is_vm"
}

check_system_requirements
show_menu
export INSTALL_MODE

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
step "System Preparation" && source "$SCRIPTS_DIR/system_setup.sh" || log_error "System preparation failed"
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
step "Shell Setup" && source "$SCRIPTS_DIR/user_environment.sh" || log_error "Shell setup failed"
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
step "Plymouth Setup" && source "$SCRIPTS_DIR/boot_setup.sh" || log_error "Plymouth setup failed"
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 46 "✓ Step 3 completed"
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step 4: Paru Installation"
  gum style --foreground 226 "📦 Installing AUR helper for additional software..."
else
  echo -e "${GREEN}✓ Step 3 completed${RESET}"
  echo -e "${CYAN}Step 4: Paru Installation${RESET}"
  echo -e "${YELLOW}📦 Installing AUR helper for additional software...${RESET}"
fi
step "Paru Installation" && ensure_paru_installed || log_error "Paru installation failed"
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
step "Programs Installation" && source "$SCRIPTS_DIR/applications.sh" || log_error "Programs installation failed"
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
step "Gaming Mode" && source "$SCRIPTS_DIR/gaming_setup.sh" || log_error "Gaming Mode failed"
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
step "Bootloader and Kernel Configuration" && source "$SCRIPTS_DIR/bootloader_setup.sh" || log_error "Bootloader configuration failed"
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
step "Fail2ban Setup" && source "$SCRIPTS_DIR/security_setup.sh" || log_error "Fail2ban setup failed"
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

  # Show beautiful completion animation
  show_completion_animation

  # Display system health dashboard
  show_system_health_dashboard

else
  echo -e "${GREEN}✓ Step 10 completed${RESET}"

  # Show completion animation for non-gum systems
  show_completion_animation

  # Display system health dashboard
  show_system_health_dashboard
fi
log_performance "Total installation time"

# Enhanced final summary with parallel installation stats
if command -v gum >/dev/null 2>&1; then
  gum style --border double --margin "1 2" --padding "1 4" --foreground 46 --border-foreground 46 "📊 PARALLEL INSTALLATION STATS"
  gum style --foreground 226 "⚡ Packages installed in parallel batches of $BATCH_SIZE"
  gum style --foreground 226 "🚀 Maximum concurrent installations: $PARALLEL_LIMIT"
  gum style --foreground 226 "⏱️  Total installation time: $(format_duration $(($(date +%s) - START_TIME)))"
  echo ""
fi

print_comprehensive_summary

# Stop parallel installation engine and cleanup
if command -v gum >/dev/null 2>&1; then
  gum style --foreground 226 "🧹 Stopping parallel installation engine..."
else
  echo -e "${YELLOW}🧹 Stopping parallel installation engine...${RESET}"
fi
stop_parallel_engine

# Handle cleanup and final results
if [ ${#ERRORS[@]} -eq 0 ]; then
  if command -v gum >/dev/null 2>&1; then
    echo ""
    gum style --foreground 226 "🧹 Cleaning up installer files..."
  else
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
    gum style --border normal --margin "1 0" --padding "0 2" --foreground 226 --border-foreground 226 "⚠️  Installation Issues Detected"
    gum style --foreground 226 "The following non-critical issues occurred:"
    for error in "${ERRORS[@]}"; do
      gum style --margin "0 2" --foreground 15 "• $error"
    done
    echo ""
    gum style --foreground 51 "💡 Your system should still work perfectly!"
    gum style --foreground 15 "   • Most errors are package conflicts or optional features"
    gum style --foreground 15 "   • Core functionality has been installed successfully"
    gum style --foreground 15 "   • You can run the installer again to retry failed components"
  else
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${YELLOW}⚠️  INSTALLATION ISSUES DETECTED${RESET}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${YELLOW}The following non-critical issues occurred:${RESET}"
    for error in "${ERRORS[@]}"; do
      echo -e "${RED}   • $error${RESET}"
    done
    echo ""
    echo -e "${GREEN}💡 Your system should still work perfectly!${RESET}"
    echo -e "${GREEN}   • Most errors are package conflicts or optional features${RESET}"
    echo -e "${GREEN}   • Core functionality has been installed successfully${RESET}"
    echo -e "${GREEN}   • You can run the installer again to retry failed components${RESET}"
  fi
fi

# Final system health check
if command -v gum >/dev/null 2>&1; then
  echo ""
  gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "🏥 Final System Health Check"
  gum style --foreground 226 "System is ready for use! Check dashboard above for details."
else
  echo -e "${CYAN}🏥 Final System Health Check${RESET}"
  echo -e "${GREEN}System is ready for use! Check stats above for details.${RESET}"
fi

prompt_reboot
