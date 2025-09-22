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

# Parse flags
VERBOSE=false
for arg in "$@"; do
  case "$arg" in
    --verbose|-v)
      VERBOSE=true
      ;;
    --quiet|-q)
      VERBOSE=false
      ;;
  esac
done
export VERBOSE

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
    echo -e "${RED}Error: This script should NOT be run as root!${RESET}"
    echo -e "${YELLOW}   Please run as a regular user with sudo privileges.${RESET}"
    echo -e "${YELLOW}   Example: ./install.sh (not sudo ./install.sh)${RESET}"
    exit 1
  fi

  # Check if we're on Arch Linux
  if [[ ! -f /etc/arch-release ]]; then
    echo -e "${RED}Error: This script is designed for Arch Linux only!${RESET}"
    echo -e "${YELLOW}   Please run this on a fresh Arch Linux installation.${RESET}"
    exit 1
  fi

  # Check internet connection
  if ! ping -c 1 archlinux.org &>/dev/null; then
    echo -e "${RED}Error: No internet connection detected!${RESET}"
    echo -e "${YELLOW}   Please check your network connection and try again.${RESET}"
    exit 1
  fi

  # Check available disk space (at least 2GB)
  local available_space=$(df / | awk 'NR==2 {print $4}')
  if [[ $available_space -lt 2097152 ]]; then
    echo -e "${RED}Error: Insufficient disk space!${RESET}"
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

# Prompt for sudo using UI helpers
ui_info "Please enter your sudo password to begin the installation:"
sudo -v || { ui_error "Sudo required. Exiting."; exit 1; }

# Keep sudo alive
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

# Installation start header
print_header "Starting Arch Linux Installation" \
  "This process will take approximately 10-20 minutes depending on your internet speed." \
  "You can safely leave this running - it will handle everything automatically!"

print_step_header 1 "$TOTAL_STEPS" "System Preparation"
ui_info "Updating package lists and installing system utilities..."
step "System Preparation" && source "$SCRIPTS_DIR/system_preparation.sh" || log_error "System preparation failed"
ui_success "Step 1 completed"
print_step_header 2 "$TOTAL_STEPS" "Shell Setup"
ui_info "Installing ZSH shell with autocompletion and syntax highlighting..."
step "Shell Setup" && source "$SCRIPTS_DIR/shell_setup.sh" || log_error "Shell setup failed"
ui_success "Step 2 completed"
print_step_header 3 "$TOTAL_STEPS" "Plymouth Setup"
ui_info "Setting up boot screen..."
step "Plymouth Setup" && source "$SCRIPTS_DIR/plymouth.sh" || log_error "Plymouth setup failed"
ui_success "Step 3 completed"
print_step_header 4 "$TOTAL_STEPS" "Yay Installation"
ui_info "Installing AUR helper for additional software..."
step "Yay Installation" && source "$SCRIPTS_DIR/yay.sh" || log_error "Yay installation failed"
ui_success "Step 4 completed"
print_step_header 5 "$TOTAL_STEPS" "Programs Installation"
ui_info "Installing applications based on your desktop environment..."
step "Programs Installation" && source "$SCRIPTS_DIR/programs.sh" || log_error "Programs installation failed"
ui_success "Step 5 completed"
print_step_header 6 "$TOTAL_STEPS" "Gaming Mode"
ui_info "Setting up gaming tools (optional)..."
step "Gaming Mode" && source "$SCRIPTS_DIR/gaming_mode.sh" || log_error "Gaming Mode failed"
ui_success "Step 6 completed"
print_step_header 7 "$TOTAL_STEPS" "Bootloader and Kernel Configuration"
ui_info "Configuring bootloader and setting up dual-boot with Windows..."
step "Bootloader and Kernel Configuration" && source "$SCRIPTS_DIR/bootloader_config.sh" || log_error "Bootloader and kernel configuration failed"
ui_success "Step 7 completed"
print_step_header 8 "$TOTAL_STEPS" "Fail2ban Setup"
ui_info "Setting up security protection for SSH..."
step "Fail2ban Setup" && source "$SCRIPTS_DIR/fail2ban.sh" || log_error "Fail2ban setup failed"
ui_success "Step 8 completed"
print_step_header 9 "$TOTAL_STEPS" "System Services"
ui_info "Enabling and configuring system services..."
step "System Services" && source "$SCRIPTS_DIR/system_services.sh" || log_error "System services failed"
ui_success "Step 9 completed"
print_step_header 10 "$TOTAL_STEPS" "Maintenance"
ui_info "Final cleanup and system optimization..."
step "Maintenance" && source "$SCRIPTS_DIR/maintenance.sh" || log_error "Maintenance failed"
ui_success "Step 10 completed"
print_header "Installation Completed Successfully"
echo ""
echo -e "${YELLOW}What's been set up for you:${RESET}"
echo -e "  - Desktop environment with essential applications"
echo -e "  - Security features (firewall, SSH protection)"
echo -e "  - Performance optimizations (ZRAM, boot screen)"
echo -e "  - Gaming tools (if you chose Gaming Mode)"
echo -e "  - Dual-boot with Windows (if detected)"
echo -e "  - Enhanced shell with autocompletion"
echo ""
print_programs_summary
print_summary
log_performance "Total installation time"

# Handle installation results with unified styling
if [ ${#ERRORS[@]} -eq 0 ]; then
  ui_success "All steps completed successfully"
  ui_info "Cleaning up installer files..."
  cd "$SCRIPT_DIR/.."
  rm -rf "$(basename "$SCRIPT_DIR")"
  ui_success "Installer files cleaned up"
else
  ui_warn "Some errors occurred during installation:"
  if command -v gum >/dev/null 2>&1; then
    for error in "${ERRORS[@]}"; do
      gum style --margin "0 2" --foreground 196 "- $error"
    done
  else
    for error in "${ERRORS[@]}"; do
      echo -e "${RED}   - $error${RESET}"
    done
  fi
  ui_info "Most errors are non-critical and your system should still work."
  ui_info "   The installer directory has been preserved so you can review what happened."
  ui_info "   You can run the installer again to fix any issues."
fi

prompt_reboot
