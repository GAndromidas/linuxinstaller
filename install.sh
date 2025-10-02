#!/bin/bash
set -uo pipefail

# Installation log file
INSTALL_LOG="$HOME/.archinstaller.log"

# Function to show help
show_help() {
  cat << EOF
Archinstaller - Comprehensive Arch Linux Post-Installation Script

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    -h, --help      Show this help message and exit
    -v, --verbose   Enable verbose output (show all package installation details)
    -q, --quiet     Quiet mode (minimal output)
    -d, --dry-run   Preview what will be installed without making changes

DESCRIPTION:
    Archinstaller transforms a fresh Arch Linux installation into a fully
    configured, optimized system. It installs essential packages, configures
    the desktop environment, sets up security features, and applies performance
    optimizations.

INSTALLATION MODES:
    Standard        Complete setup with all recommended packages
    Minimal         Essential tools only for lightweight installations
    Custom          Interactive selection of packages to install

FEATURES:
    - Desktop environment detection and optimization (KDE, GNOME, Cosmic)
    - Security hardening (Fail2ban, Firewall)
    - Performance tuning (ZRAM, Plymouth boot screen)
    - Optional gaming mode with performance optimizations
    - Btrfs snapshot support with automatic configuration
    - Windows dual-boot detection and configuration
    - Automatic GPU driver detection and installation

REQUIREMENTS:
    - Fresh Arch Linux installation
    - Active internet connection
    - Regular user account with sudo privileges
    - Minimum 2GB free disk space

EXAMPLES:
    ./install.sh                Run installer with interactive prompts
    ./install.sh --verbose      Run with detailed package installation output
    ./install.sh --help         Show this help message

LOG FILE:
    Installation log saved to: ~/.archinstaller.log

MORE INFO:
    https://github.com/gandromidas/archinstaller

EOF
  exit 0
}

# Clear terminal for clean interface
clear

# Get the directory where this script is located (archinstaller root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"

source "$SCRIPTS_DIR/common.sh"

# Initialize log file
{
  echo "=========================================="
  echo "Archinstaller Installation Log"
  echo "Started: $(date)"
  echo "=========================================="
  echo ""
} > "$INSTALL_LOG"

# Function to log to both console and file
log_both() {
  echo "$1" | tee -a "$INSTALL_LOG"
}

START_TIME=$(date +%s)

# Parse flags
VERBOSE=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      show_help
      ;;
    --verbose|-v)
      VERBOSE=true
      ;;
    --quiet|-q)
      VERBOSE=false
      ;;
    --dry-run|-d)
      DRY_RUN=true
      VERBOSE=true
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done
export VERBOSE
export DRY_RUN
export INSTALL_LOG

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

# Dry-run mode banner
if [ "$DRY_RUN" = true ]; then
  echo ""
  echo -e "${YELLOW}========================================${RESET}"
  echo -e "${YELLOW}         DRY-RUN MODE ENABLED${RESET}"
  echo -e "${YELLOW}========================================${RESET}"
  echo -e "${CYAN}Preview mode: No changes will be made${RESET}"
  echo -e "${CYAN}Package installations will be simulated${RESET}"
  echo -e "${CYAN}System configurations will be previewed${RESET}"
  echo ""
  sleep 2
fi

# Prompt for sudo using UI helpers
if [ "$DRY_RUN" = false ]; then
  ui_info "Please enter your sudo password to begin the installation:"
  sudo -v || { ui_error "Sudo required. Exiting."; exit 1; }
else
  ui_info "Dry-run mode: Skipping sudo authentication"
fi

# Keep sudo alive (skip in dry-run mode)
if [ "$DRY_RUN" = false ]; then
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null; save_log_on_exit' EXIT INT TERM
else
  trap 'save_log_on_exit' EXIT INT TERM
fi

# State tracking for error recovery
STATE_FILE="$HOME/.archinstaller.state"
mkdir -p "$(dirname "$STATE_FILE")"

# Function to mark step as completed
mark_step_complete() {
  echo "$1" >> "$STATE_FILE"
}

# Function to check if step was completed
is_step_complete() {
  [ -f "$STATE_FILE" ] && grep -q "^$1$" "$STATE_FILE"
}

# Function to save log on exit
save_log_on_exit() {
  {
    echo ""
    echo "=========================================="
    echo "Installation ended: $(date)"
    echo "=========================================="
  } >> "$INSTALL_LOG"
}

# Installation start header
print_header "Starting Arch Linux Installation" \
  "This process will take approximately 10-20 minutes depending on your internet speed." \
  "You can safely leave this running - it will handle everything automatically!"

# Step 1: System Preparation
if ! is_step_complete "system_preparation"; then
  print_step_header 1 "$TOTAL_STEPS" "System Preparation"
  ui_info "Updating package lists and installing system utilities..."
  step "System Preparation" && source "$SCRIPTS_DIR/system_preparation.sh" || log_error "System preparation failed"
  mark_step_complete "system_preparation"
  ui_success "Step 1 completed"
else
  ui_info "Step 1 (System Preparation) already completed - skipping"
fi

# Step 2: Shell Setup
if ! is_step_complete "shell_setup"; then
  print_step_header 2 "$TOTAL_STEPS" "Shell Setup"
  ui_info "Installing ZSH shell with autocompletion and syntax highlighting..."
  step "Shell Setup" && source "$SCRIPTS_DIR/shell_setup.sh" || log_error "Shell setup failed"
  mark_step_complete "shell_setup"
  ui_success "Step 2 completed"
else
  ui_info "Step 2 (Shell Setup) already completed - skipping"
fi

# Step 3: Plymouth Setup
if ! is_step_complete "plymouth_setup"; then
  print_step_header 3 "$TOTAL_STEPS" "Plymouth Setup"
  ui_info "Setting up boot screen..."
  step "Plymouth Setup" && source "$SCRIPTS_DIR/plymouth.sh" || log_error "Plymouth setup failed"
  mark_step_complete "plymouth_setup"
  ui_success "Step 3 completed"
else
  ui_info "Step 3 (Plymouth Setup) already completed - skipping"
fi

# Step 4: Yay Installation
if ! is_step_complete "yay_installation"; then
  print_step_header 4 "$TOTAL_STEPS" "Yay Installation"
  ui_info "Installing AUR helper for additional software..."
  step "Yay Installation" && source "$SCRIPTS_DIR/yay.sh" || log_error "Yay installation failed"
  mark_step_complete "yay_installation"
  ui_success "Step 4 completed"
else
  ui_info "Step 4 (Yay Installation) already completed - skipping"
fi

# Step 5: Programs Installation
if ! is_step_complete "programs_installation"; then
  print_step_header 5 "$TOTAL_STEPS" "Programs Installation"
  ui_info "Installing applications based on your desktop environment..."
  step "Programs Installation" && source "$SCRIPTS_DIR/programs.sh" || log_error "Programs installation failed"
  mark_step_complete "programs_installation"
  ui_success "Step 5 completed"
else
  ui_info "Step 5 (Programs Installation) already completed - skipping"
fi

# Step 6: Gaming Mode
if ! is_step_complete "gaming_mode"; then
  print_step_header 6 "$TOTAL_STEPS" "Gaming Mode"
  ui_info "Setting up gaming tools (optional)..."
  step "Gaming Mode" && source "$SCRIPTS_DIR/gaming_mode.sh" || log_error "Gaming Mode failed"
  mark_step_complete "gaming_mode"
  ui_success "Step 6 completed"
else
  ui_info "Step 6 (Gaming Mode) already completed - skipping"
fi

# Step 7: Bootloader and Kernel Configuration
if ! is_step_complete "bootloader_config"; then
  print_step_header 7 "$TOTAL_STEPS" "Bootloader and Kernel Configuration"
  ui_info "Configuring bootloader and setting up dual-boot with Windows..."
  step "Bootloader and Kernel Configuration" && source "$SCRIPTS_DIR/bootloader_config.sh" || log_error "Bootloader and kernel configuration failed"
  mark_step_complete "bootloader_config"
  ui_success "Step 7 completed"
else
  ui_info "Step 7 (Bootloader Configuration) already completed - skipping"
fi

# Step 8: Fail2ban Setup
if ! is_step_complete "fail2ban_setup"; then
  print_step_header 8 "$TOTAL_STEPS" "Fail2ban Setup"
  ui_info "Setting up security protection for SSH..."
  step "Fail2ban Setup" && source "$SCRIPTS_DIR/fail2ban.sh" || log_error "Fail2ban setup failed"
  mark_step_complete "fail2ban_setup"
  ui_success "Step 8 completed"
else
  ui_info "Step 8 (Fail2ban Setup) already completed - skipping"
fi

# Step 9: System Services
if ! is_step_complete "system_services"; then
  print_step_header 9 "$TOTAL_STEPS" "System Services"
  ui_info "Enabling and configuring system services..."
  step "System Services" && source "$SCRIPTS_DIR/system_services.sh" || log_error "System services failed"
  mark_step_complete "system_services"
  ui_success "Step 9 completed"
else
  ui_info "Step 9 (System Services) already completed - skipping"
fi

# Step 10: Maintenance
if ! is_step_complete "maintenance"; then
  print_step_header 10 "$TOTAL_STEPS" "Maintenance"
  ui_info "Final cleanup and system optimization..."
  step "Maintenance" && source "$SCRIPTS_DIR/maintenance.sh" || log_error "Maintenance failed"
  mark_step_complete "maintenance"
  ui_success "Step 10 completed"
else
  ui_info "Step 10 (Maintenance) already completed - skipping"
fi
if [ "$DRY_RUN" = true ]; then
  print_header "Dry-Run Preview Completed"
  echo ""
  echo -e "${YELLOW}This was a preview run. No changes were made to your system.${RESET}"
  echo ""
  echo -e "${CYAN}To perform the actual installation, run:${RESET}"
  echo -e "${GREEN}  ./install.sh${RESET}"
  echo ""
else
  print_header "Installation Completed Successfully"
fi
echo ""
echo -e "${YELLOW}What's been set up for you:${RESET}"
echo -e "  - Desktop environment with essential applications"
echo -e "  - VLC media player with all codecs"
echo -e "  - Security features (firewall, SSH protection)"
echo -e "  - Performance optimizations (ZRAM, boot screen)"
echo -e "  - Laptop optimizations (if laptop detected)"
echo -e "  - Gaming tools (if you chose Gaming Mode)"
echo -e "  - Btrfs snapshots (if Btrfs filesystem detected)"
echo -e "  - Dual-boot with Windows (if detected)"
echo -e "  - Enhanced shell with 50+ aliases and SSH shortcuts"
echo ""
if declare -f print_programs_summary >/dev/null 2>&1; then
  print_programs_summary
fi
print_summary
log_performance "Total installation time"

# Save final log
{
  echo ""
  echo "=========================================="
  echo "Installation Summary"
  echo "=========================================="
  echo "Completed steps:"
  [ -f "$STATE_FILE" ] && cat "$STATE_FILE" | sed 's/^/  - /'
  echo ""
  if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "Errors encountered:"
    for error in "${ERRORS[@]}"; do
      echo "  - $error"
    done
  fi
  echo ""
  echo "Installation log saved to: $INSTALL_LOG"
} >> "$INSTALL_LOG"

# Handle installation results with unified styling
if [ ${#ERRORS[@]} -eq 0 ]; then
  ui_success "All steps completed successfully"
  ui_info "Installation log saved to: $INSTALL_LOG"
else
  ui_warn "Some errors occurred during installation:"
  if command -v gum >/dev/null 2>&1; then
    for error in "${ERRORS[@]}"; do
      echo "   - $error" | gum style --foreground 196
    done
  else
    for error in "${ERRORS[@]}"; do
      echo -e "${RED}   - $error${RESET}"
    done
  fi
  ui_info "Most errors are non-critical and your system should still work."
  ui_info "Installation log saved to: $INSTALL_LOG"
  ui_info "State file saved to: $STATE_FILE"
  ui_info "You can run the installer again to resume from the last successful step."
  ui_info "The installer directory has been preserved so you can review what happened."
fi

prompt_reboot
