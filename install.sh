#!/bin/bash
set -uo pipefail

# Installation log file
INSTALL_LOG="$HOME/.archinstaller.log"

# Function to show help
show_help() {
  cat << EOF
Archinstaller v$VERSION - Comprehensive Arch Linux Post-Installation Script

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

# Get version
VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "dev")

# State tracking for error recovery
STATE_FILE="$HOME/.archinstaller.state"
mkdir -p "$(dirname "$STATE_FILE")"

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

  # Check internet connection (will use retry logic from common.sh if available)
  if ! ping -c 1 archlinux.org &>/dev/null; then
    # Try with retry if function is available
    if declare -f check_internet_with_retry >/dev/null 2>&1; then
      if ! check_internet_with_retry; then
        echo -e "${RED}Error: No internet connection detected!${RESET}"
        echo -e "${YELLOW}   Please check your network connection and try again.${RESET}"
        exit 1
      fi
    else
      echo -e "${RED}Error: No internet connection detected!${RESET}"
      echo -e "${YELLOW}   Please check your network connection and try again.${RESET}"
      exit 1
    fi
  fi

  # Check available disk space (at least 2GB)
  local available_space=$(df / | awk 'NR==2 {print $4}')
  local min_disk_space_kb=2097152  # 2GB in KB
  if [[ $available_space -lt $min_disk_space_kb ]]; then
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

# Show resume menu if previous installation detected
show_resume_menu

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
  if ! check_sudo_access; then
    exit 1
  fi
  ui_info "Please enter your sudo password to begin the installation:"
  sudo -v || { ui_error "Sudo required. Exiting."; exit 1; }
else
  ui_info "Dry-run mode: Skipping sudo authentication"
fi

# Keep sudo alive (skip in dry-run mode)
if [ "$DRY_RUN" = false ]; then
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'cleanup_on_exit' EXIT INT TERM
else
  trap 'cleanup_on_exit' EXIT INT TERM
fi

# Function to mark step as completed (with file locking to prevent race conditions)
mark_step_complete() {
  local step="$1"
  # Use file locking to prevent race conditions
  (
    flock -x 200 2>/dev/null || true
    echo "$step" >> "$STATE_FILE"
  ) 200>"$STATE_FILE.lock" 2>/dev/null || {
    # Fallback if flock not available
    echo "$step" >> "$STATE_FILE"
  }
}

# Function to check if step was completed
is_step_complete() {
  [ -f "$STATE_FILE" ] && grep -q "^$1$" "$STATE_FILE"
}

# Enhanced resume functionality
show_resume_menu() {
  if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
    echo ""
    ui_info "Previous installation detected. The following steps were completed:"

    local completed_steps=()
    while IFS= read -r step; do
      completed_steps+=("$step")
    done < "$STATE_FILE"

    if supports_gum; then
      echo ""
      gum style --margin "0 2" --foreground 15 "Completed steps:"
      for step in "${completed_steps[@]}"; do
        gum style --margin "0 4" --foreground 10 "✓ $step"
      done

      echo ""
      if gum confirm --default=true "Resume installation from where you left off?"; then
        ui_success "Resuming installation..."
        return 0
      else
        if gum confirm --default=false "Start fresh installation (this will clear previous progress)?"; then
          rm -f "$STATE_FILE" 2>/dev/null || true
          ui_info "Starting fresh installation..."
          return 0
        else
          ui_info "Installation cancelled by user"
          exit 0
        fi
      fi
    else
      # Fallback for systems without gum
      for step in "${completed_steps[@]}"; do
        echo -e "  ${GREEN}✓${RESET} $step"
      done

      echo ""
      read -r -p "Resume installation? [Y/n]: " response
      response=${response,,}
      if [[ "$response" == "n" || "$response" == "no" ]]; then
        read -r -p "Start fresh installation? [y/N]: " response
        response=${response,,}
        if [[ "$response" == "y" || "$response" == "yes" ]]; then
          rm -f "$STATE_FILE" 2>/dev/null || true
          ui_info "Starting fresh installation..."
        else
          ui_info "Installation cancelled by user"
          exit 0
        fi
      else
        ui_success "Resuming installation..."
      fi
    fi
  fi
}

# Enhanced step completion with progress tracking
mark_step_complete_with_progress() {
  local step_name="$1"
  echo "$step_name" >> "$STATE_FILE"

  # Show overall progress
  local completed_count=$(wc -l < "$STATE_FILE" 2>/dev/null || echo "0")

  if supports_gum; then
    echo ""
    gum style --margin "0 2" --foreground 10 "✓ Step completed! Progress: $completed_count/$TOTAL_STEPS"
  else
    ui_success "Step completed! Progress: $completed_count/$TOTAL_STEPS"
  fi
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

# Function to cleanup on exit
cleanup_on_exit() {
  local exit_code=$?
  
  # Kill background processes
  jobs -p | xargs -r kill 2>/dev/null || true
  
  # If failed, show recovery instructions
  if [ $exit_code -ne 0 ] && [ "$DRY_RUN" != "true" ]; then
    echo ""
    ui_error "Installation failed. Recovery steps:"
    ui_info "1. Check log: $INSTALL_LOG"
    ui_info "2. Resume: ./install.sh (will skip completed steps)"
    ui_info "3. Fresh start: rm $STATE_FILE && ./install.sh"
  fi
  
  # Save final log entry
  save_log_on_exit
}

# Installation start header
print_header "Starting Arch Linux Installation" \
  "This process will take approximately 10-20 minutes depending on your internet speed." \
  "You can safely leave this running - it will handle everything automatically!"

# Step 1: System Preparation
if ! is_step_complete "system_preparation"; then
  print_step_header_with_timing 1 "$TOTAL_STEPS" "System Preparation"
  ui_info "Updating package lists and installing system utilities..."
  step "System Preparation" && source "$SCRIPTS_DIR/system_preparation.sh" || log_error "System preparation failed"
  mark_step_complete_with_progress "system_preparation"
else
  ui_info "Step 1 (System Preparation) already completed - skipping"
fi

# Step 2: Shell Setup
if ! is_step_complete "shell_setup"; then
  print_step_header_with_timing 2 "$TOTAL_STEPS" "Shell Setup"
  ui_info "Installing ZSH shell with autocompletion and syntax highlighting..."
  step "Shell Setup" && source "$SCRIPTS_DIR/shell_setup.sh" || log_error "Shell setup failed"
  mark_step_complete_with_progress "shell_setup"
else
  ui_info "Step 2 (Shell Setup) already completed - skipping"
fi

# Step 3: Plymouth Setup
if [[ "$INSTALL_MODE" == "server" ]]; then
  ui_info "Server mode selected, skipping Plymouth (graphical boot) setup."
else
  if ! is_step_complete "plymouth_setup"; then
    print_step_header_with_timing 3 "$TOTAL_STEPS" "Plymouth Setup"
    ui_info "Setting up boot screen..."
    step "Plymouth Setup" && source "$SCRIPTS_DIR/plymouth.sh" || log_error "Plymouth setup failed"
    mark_step_complete_with_progress "plymouth_setup"
  else
    ui_info "Step 3 (Plymouth Setup) already completed - skipping"
  fi
fi

# Step 4: Yay Installation
if ! is_step_complete "yay_installation"; then
  print_step_header_with_timing 4 "$TOTAL_STEPS" "Yay Installation"
  ui_info "Installing AUR helper for additional software..."
  step "Yay Installation" && source "$SCRIPTS_DIR/yay.sh" || log_error "Yay installation failed"
  mark_step_complete_with_progress "yay_installation"
else
  ui_info "Step 4 (Yay Installation) already completed - skipping"
fi

# Step 5: Programs Installation
if ! is_step_complete "programs_installation"; then
  print_step_header_with_timing 5 "$TOTAL_STEPS" "Programs Installation"
  ui_info "Installing applications based on your desktop environment..."
  step "Programs Installation" && source "$SCRIPTS_DIR/programs.sh" || log_error "Programs installation failed"
  mark_step_complete_with_progress "programs_installation"
else
  ui_info "Step 5 (Programs Installation) already completed - skipping"
fi

# Step 6: Gaming Mode
if [[ "$INSTALL_MODE" == "server" ]]; then
  ui_info "Server mode selected, skipping Gaming Mode setup."
else
  if ! is_step_complete "gaming_mode"; then
    print_step_header_with_timing 6 "$TOTAL_STEPS" "Gaming Mode"
    ui_info "Setting up gaming tools (optional)..."
    step "Gaming Mode" && source "$SCRIPTS_DIR/gaming_mode.sh" || log_error "Gaming Mode failed"
    mark_step_complete_with_progress "gaming_mode"
  else
    ui_info "Step 6 (Gaming Mode) already completed - skipping"
  fi
fi

# Step 7: Bootloader and Kernel Configuration
if ! is_step_complete "bootloader_config"; then
  print_step_header_with_timing 7 "$TOTAL_STEPS" "Bootloader and Kernel Configuration"
  ui_info "Configuring bootloader..."
  step "Bootloader and Kernel Configuration" && source "$SCRIPTS_DIR/bootloader_config.sh" || log_error "Bootloader and kernel configuration failed"
  mark_step_complete_with_progress "bootloader_config"
else
  ui_info "Step 7 (Bootloader Configuration) already completed - skipping"
fi

# Step 8: Fail2ban Setup
if ! is_step_complete "fail2ban_setup"; then
  print_step_header_with_timing 8 "$TOTAL_STEPS" "Fail2ban Setup"
  ui_info "Setting up security protection for SSH..."
  step "Fail2ban Setup" && source "$SCRIPTS_DIR/fail2ban.sh" || log_error "Fail2ban setup failed"
  mark_step_complete_with_progress "fail2ban_setup"
else
  ui_info "Step 8 (Fail2ban Setup) already completed - skipping"
fi

# Step 9: System Services
if ! is_step_complete "system_services"; then
  print_step_header_with_timing 9 "$TOTAL_STEPS" "System Services"
  ui_info "Enabling and configuring system services..."
  step "System Services" && source "$SCRIPTS_DIR/system_services.sh" || log_error "System services failed"
  mark_step_complete_with_progress "system_services"
else
  ui_info "Step 9 (System Services) already completed - skipping"
fi

# Step 10: Maintenance
if ! is_step_complete "maintenance"; then
  print_step_header_with_timing 10 "$TOTAL_STEPS" "Maintenance"
  ui_info "Final cleanup and system optimization..."
  step "Maintenance" && source "$SCRIPTS_DIR/maintenance.sh" || log_error "Maintenance failed"
  mark_step_complete_with_progress "maintenance"
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
if supports_gum; then
  echo ""
  gum style --margin "1 2" --border thick --padding "1 2" --foreground 15 "Installation Summary"
  echo ""
  gum style --margin "0 2" --foreground 10 "Desktop Environment: Configured"
  gum style --margin "0 2" --foreground 10 "System Utilities: Installed"
  gum style --margin "0 2" --foreground 10 "Security Features: Enabled"
  gum style --margin "0 2" --foreground 10 "Performance Optimizations: Applied"
  gum style --margin "0 2" --foreground 10 "Shell Configuration: Complete"
  echo ""
else
  echo -e "${CYAN}Installation Summary${RESET}"
  echo ""
  echo -e "${GREEN}Desktop Environment:${RESET} Configured"
  echo -e "${GREEN}System Utilities:${RESET} Installed"
  echo -e "${GREEN}Security Features:${RESET} Enabled"
  echo -e "${GREEN}Performance Optimizations:${RESET} Applied"
  echo -e "${GREEN}Shell Configuration:${RESET} Complete"
  echo ""
fi
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

# Handle installation results with minimal styling
if [ ${#ERRORS[@]} -eq 0 ]; then
  if supports_gum; then
    echo ""
    gum style --margin "0 2" --foreground 10 "Installation completed successfully"
    gum style --margin "0 2" --foreground 15 "Log: $INSTALL_LOG"
  else
    ui_success "Installation completed successfully"
    ui_info "Log: $INSTALL_LOG"
  fi


else
  if supports_gum; then
    echo ""
    gum style --margin "0 2" --foreground 196 "Installation completed with warnings"
    gum style --margin "0 2" --foreground 15 "Log: $INSTALL_LOG"
  else
    ui_warn "Installation completed with warnings"
    ui_info "Log: $INSTALL_LOG"
  fi
fi

prompt_reboot
