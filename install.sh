#!/bin/bash
set -uo pipefail

# Installation log file
INSTALL_LOG="$HOME/.linuxinstaller.log"

# Function to show help
show_help() {
  cat << EOF
LinuxInstaller - Unified Linux Post-Installation Script

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    -h, --help      Show this help message and exit
    -v, --verbose   Enable verbose output (show all package installation details)
    -m, --mode      Installation mode (default, server, minimal)

DESCRIPTION:
    LinuxInstaller transforms a fresh Linux installation into a fully
    configured, optimized system. It installs essential packages, configures
    the desktop environment, sets up security features, and applies performance
    optimizations.
EOF
  exit 0
}

# Determine directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# Default configuration
INSTALL_MODE="default"
VERBOSE="false"
TOTAL_STEPS=10

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      ;;
    -v|--verbose)
      VERBOSE="true"
      export VERBOSE
      shift
      ;;
    -m|--mode)
      INSTALL_MODE="$2"
      shift 2
      ;;
    *)
      # Ignore unknown args or handle as needed, but for now just pass
      shift
      ;;
  esac
done

export INSTALL_MODE
export SCRIPTS_DIR
export CONFIGS_DIR

# Source common functions
if [ -f "$SCRIPTS_DIR/common.sh" ]; then
  source "$SCRIPTS_DIR/common.sh"
else
  echo "Error: common.sh not found in $SCRIPTS_DIR"
  exit 1
fi

# Source distro detection
if [ -f "$SCRIPTS_DIR/distro_check.sh" ]; then
  source "$SCRIPTS_DIR/distro_check.sh"
  detect_distro
else
  echo "Error: distro_check.sh not found in $SCRIPTS_DIR"
  exit 1
fi

# Ensure helper tools (figlet, gum, yq)
# Install them silently if missing
for tool in figlet gum yq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
      # Inline installation logic for robustness across distros
      if [ "$tool" == "figlet" ]; then
          $PKG_INSTALL $PKG_NOCONFIRM figlet >/dev/null 2>&1
      elif [ "$tool" == "gum" ]; then
          if [ "$DISTRO_ID" == "arch" ]; then
              $PKG_INSTALL $PKG_NOCONFIRM gum >/dev/null 2>&1
          else
              # Binary install for others to avoid repo mess
              ARCH="amd64"; [[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"
              VER="0.13.0"
              curl -L -s -o /tmp/gum.tar.gz "https://github.com/charmbracelet/gum/releases/download/v${VER}/gum_${VER}_linux_${ARCH}.tar.gz"
              tar -xzf /tmp/gum.tar.gz -C /tmp >/dev/null 2>&1
              sudo mv /tmp/gum_${VER}_linux_${ARCH}/gum /usr/local/bin/gum >/dev/null 2>&1
              rm -rf /tmp/gum*
          fi
      elif [ "$tool" == "yq" ]; then
          if [ "$DISTRO_ID" == "arch" ]; then
               $PKG_INSTALL $PKG_NOCONFIRM yq >/dev/null 2>&1
          else
               sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
               sudo chmod +x /usr/local/bin/yq
          fi
      fi
  fi
done

# Show ASCII banner and interactive menu (uses gum if available)
# The functions `linux_ascii` and `show_menu` are defined in common.sh.

setup_package_providers
detect_de
define_common_packages
linux_ascii
show_menu

setup_package_providers
detect_de
define_common_packages

# State tracking for step resume and idempotency
STATE_FILE="$HOME/.linuxinstaller.state"
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE" 2>/dev/null || true

# Helper: compute simple file hash
get_file_hash() {
  local file="$1"
  if [ -f "$file" ]; then
    md5sum "$file" | awk '{print $1}'
  else
    echo "nohash"
  fi
}

# Mark step as completed (supports optional config-file hashing)
mark_step_complete() {
  local step="$1"
  local config_file="${2:-}"

  local entry="$step"
  if [ -n "$config_file" ]; then
    local hash
    hash=$(get_file_hash "$config_file")
    entry="$step:$hash"
  fi

  # Use file locking to avoid races
  (
    flock -x 200 2>/dev/null || true
    grep -v "^$step:" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
    mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
    echo "$entry" >> "$STATE_FILE"
  ) 200>"$STATE_FILE.lock" 2>/dev/null || {
    # fallback if flock is not available
    grep -v "^$step:" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
    mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
    echo "$entry" >> "$STATE_FILE"
  }
}

# Check whether a step (optionally tied to a config file) is complete
is_step_complete() {
  local step="$1"
  local config_file="${2:-}"

  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi

  if [ -n "$config_file" ]; then
    local current_hash
    current_hash=$(get_file_hash "$config_file")
    if grep -q "^$step:$current_hash$" "$STATE_FILE"; then
      return 0
    else
      return 1
    fi
  else
    if grep -q "^$step" "$STATE_FILE"; then
      return 0
    else
      return 1
    fi
  fi
}

# Mark step complete and print progress
mark_step_complete_with_progress() {
  local step_name="$1"
  local config_file="${2:-}"

  mark_step_complete "$step_name" "$config_file"

  local completed_count=0
  if [ -f "$STATE_FILE" ]; then
    completed_count=$(cut -d':' -f1 < "$STATE_FILE" | sort -u | wc -l 2>/dev/null || echo "0")
  fi

  ui_success "Step completed! Progress: ${completed_count}/${TOTAL_STEPS}"
}

# Basic pre-checks (non-invasive)
check_system_requirements() {
  # Do not run as root
  if [[ $EUID -eq 0 ]]; then
    ui_error "Do not run this script as root. Please run as a regular user with sudo privileges."
    exit 1
  fi

  # Ensure Arch

  # Internet check: prefer reusable helper if available
  if declare -f check_internet_with_retry >/dev/null 2>&1; then
    if ! check_internet_with_retry; then
      ui_error "No internet connection detected. Please check your network."
      exit 1
    fi
  else
    if ! ping -c 1 -W 5 archlinux.org &>/dev/null; then
      ui_error "No internet connection detected. Please check your network."
      exit 1
    fi
  fi

  # Disk space check (uses MIN_DISK_SPACE_KB from common.sh)
  if [ -n "${MIN_DISK_SPACE_KB:-}" ]; then
    local avail_kb
    avail_kb=$(df / | awk 'NR==2 {print $4}' || echo 0)
    if [ "$avail_kb" -lt "$MIN_DISK_SPACE_KB" ]; then
      ui_error "Insufficient disk space. Need at least $((MIN_DISK_SPACE_KB/1024/1024)) GB free."
      exit 1
    fi
  fi

  ui_success "Prerequisites OK."
}

# Resume prompt - offer to resume or start fresh
show_resume_menu() {
  if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
    echo ""
    ui_info "Previous installation detected. The following steps were completed:"
    local completed_steps=()
    while IFS= read -r line; do
      step_name=$(echo "$line" | cut -d':' -f1)
      # avoid duplicates
      if [[ ! " ${completed_steps[*]} " =~ " ${step_name} " ]]; then
        completed_steps+=("$step_name")
      fi
    done < "$STATE_FILE"

    for step_name in "${completed_steps[@]}"; do
      echo -e "  ${GREEN}✓${RESET} $step_name"
    done

    if supports_gum; then
      echo ""
      if gum confirm --default=true "Resume installation from where you left off?"; then
        ui_success "Resuming installation..."
        return 0
      else
        if gum confirm --default=false "Start fresh installation (this will clear previous progress)?"; then
          rm -f "$STATE_FILE" "$STATE_FILE.lock" 2>/dev/null || true
          ui_info "Starting fresh installation..."
          return 0
        else
          ui_info "Installation cancelled by user"
          exit 0
        fi
      fi
    else
      echo ""
      read -r -p "Resume installation? [Y/n]: " response
      response=${response,,}
      if [[ "$response" == "n" || "$response" == "no" ]]; then
        read -r -p "Start fresh installation? [y/N]: " response2
        response2=${response2,,}
        if [[ "$response2" == "y" || "$response2" == "yes" ]]; then
          rm -f "$STATE_FILE" "$STATE_FILE.lock" 2>/dev/null || true
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

# Logging cleanup helpers
save_log_on_exit() {
  {
    echo ""
    echo "=========================================="
    echo "Installation ended: $(date)"
    echo "=========================================="
  } >> "$INSTALL_LOG"
}

cleanup_on_exit() {
  local exit_code=$?
  # Kill background jobs if any
  jobs -p | xargs -r kill 2>/dev/null || true

  if [ $exit_code -ne 0 ]; then
    ui_error "Installation failed. Check the log: $INSTALL_LOG"
    if [ ${#ERRORS[@]} -gt 0 ]; then
      ui_info "Errors encountered:"
      for e in "${ERRORS[@]}"; do
        ui_info "  - $e"
      done
    fi
  fi

  save_log_on_exit
}

trap 'cleanup_on_exit' EXIT INT TERM

# Initialize log
START_TIME=$(date +%s)
echo "==========================================" > "$INSTALL_LOG"
echo "LinuxInstaller Installation Log" >> "$INSTALL_LOG"
echo "Started: $(date)" >> "$INSTALL_LOG"
echo "==========================================" >> "$INSTALL_LOG"

# Prompt for sudo (ensure we have credentials early)
if ! check_sudo_access; then
  ui_error "Sudo required. Exiting."
  exit 1
fi
ui_info "Please enter your sudo password to begin the installation:"
sudo -v || { ui_error "Sudo required. Exiting."; exit 1; }

# Keep sudo alive in background
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

# Offer resume if previous run exists
show_resume_menu

# Run lightweight prerequisite checks
check_system_requirements

# Main Installation Loop

print_header "Starting Linux Installation" \
  "This process will take approximately 10-20 minutes depending on your internet speed." \
  "You can safely leave this running - it will handle everything automatically!"

# Step 1: System Preparation
# Essential for setting up pacman, mirrors, and base utilities
if ! is_step_complete "system_preparation"; then
  print_step_header_with_timing 1 "$TOTAL_STEPS" "System Preparation"
  ui_info "Updating package lists and installing system utilities..."
  step "System Preparation" && source "$SCRIPTS_DIR/system_preparation.sh" || log_error "System preparation failed"
  mark_step_complete_with_progress "system_preparation"
else
  ui_info "Step 1 (System Preparation) already completed - skipping"
fi

# Step 2: Universal Package Setup
# Moved early so AUR packages are available for subsequent steps (like Plymouth themes)
if ! is_step_complete "universal_setup"; then
  print_step_header_with_timing 2 "$TOTAL_STEPS" "Universal Package Setup"
  ui_info "Setting up AUR/Flatpak/Snap support..."
  step "Universal Package Setup" && source "$SCRIPTS_DIR/setup_universal.sh" || log_error "Yay installation failed"
  mark_step_complete_with_progress "universal_setup"
else
  ui_info "Step 2 (Universal Package Setup) already completed - skipping"
fi

# Step 3: Shell Setup
# Sets up ZSH/Fish so user environment is ready
if ! is_step_complete "shell_setup"; then
  print_step_header_with_timing 3 "$TOTAL_STEPS" "Shell Setup"
  ui_info "Installing ZSH shell with autocompletion and syntax highlighting..."
  step "Shell Setup" && source "$SCRIPTS_DIR/shell_setup.sh" || log_error "Shell setup failed"
  mark_step_complete_with_progress "shell_setup"
else
  ui_info "Step 3 (Shell Setup) already completed - skipping"
fi

# Step 4: Programs Installation
# Installs kernels, headers, and desktop apps. Must run BEFORE Bootloader config.
if ! is_step_complete "programs_installation" "$CONFIGS_DIR/programs.yaml"; then
  print_step_header_with_timing 4 "$TOTAL_STEPS" "Programs Installation"
  ui_info "Installing applications based on your desktop environment..."
  step "Programs Installation" && source "$SCRIPTS_DIR/programs.sh" || log_error "Programs installation failed"
  mark_step_complete_with_progress "programs_installation" "$CONFIGS_DIR/programs.yaml"
else
  ui_info "Step 4 (Programs Installation) already completed - skipping"
fi

# Step 5: Plymouth Setup
# Configures boot splash.
if [[ "$INSTALL_MODE" == "server" ]]; then
  ui_info "Server mode selected, skipping Plymouth (graphical boot) setup."
else
  if ! is_step_complete "plymouth_setup"; then
    print_step_header_with_timing 5 "$TOTAL_STEPS" "Plymouth Setup"
    ui_info "Setting up boot screen..."
    # Skip intermediate rebuilds; bootloader_config will handle the final rebuild
    export SKIP_MKINITCPIO=true
    step "Plymouth Setup" && source "$SCRIPTS_DIR/plymouth.sh" || log_error "Plymouth setup failed"
    unset SKIP_MKINITCPIO
    mark_step_complete_with_progress "plymouth_setup"
  else
    ui_info "Step 5 (Plymouth Setup) already completed - skipping"
  fi
fi

# Step 6: Bootloader and Kernel Configuration
if ! is_step_complete "bootloader_config"; then
  print_step_header_with_timing 6 "$TOTAL_STEPS" "Bootloader and Kernel Configuration"
  ui_info "Configuring bootloader..."
  step "Bootloader and Kernel Configuration" && source "$SCRIPTS_DIR/bootloader_config.sh" || log_error "Bootloader and kernel configuration failed"
  mark_step_complete_with_progress "bootloader_config"
else
  ui_info "Step 6 (Bootloader Configuration) already completed - skipping"
fi

# Step 7: Gaming Mode
# Optional gaming optimizations
if [[ "$INSTALL_MODE" == "server" ]]; then
  ui_info "Server mode selected, skipping Gaming Mode setup."
else
  if ! is_step_complete "gaming_mode"; then
    print_step_header_with_timing 7 "$TOTAL_STEPS" "Gaming Mode"
    ui_info "Setting up gaming tools (optional)..."
    step "Gaming Mode" && source "$SCRIPTS_DIR/gaming_mode.sh" || log_error "Gaming Mode failed"
    mark_step_complete_with_progress "gaming_mode"
  else
    ui_info "Step 7 (Gaming Mode) already completed - skipping"
  fi
fi

# Step 8: Fail2ban Setup
# Security
if ! is_step_complete "fail2ban_setup"; then
  print_step_header_with_timing 8 "$TOTAL_STEPS" "Fail2ban Setup"
  ui_info "Setting up security protection for SSH..."
  step "Fail2ban Setup" && source "$SCRIPTS_DIR/fail2ban.sh" || log_error "Fail2ban setup failed"
  mark_step_complete_with_progress "fail2ban_setup"
else
  ui_info "Step 8 (Fail2ban Setup) already completed - skipping"
fi

# Step 9: System Services
# Enabling services should happen after everything is installed and configured
if ! is_step_complete "system_services"; then
  print_step_header_with_timing 9 "$TOTAL_STEPS" "System Services"
  ui_info "Enabling and configuring system services..."
  step "System Services" && source "$SCRIPTS_DIR/system_services.sh" || log_error "System services failed"
  mark_step_complete_with_progress "system_services"
else
  ui_info "Step 9 (System Services) already completed - skipping"
fi

# Step 10: Maintenance
# Final cleanup
if ! is_step_complete "maintenance"; then
  print_step_header_with_timing 10 "$TOTAL_STEPS" "Maintenance"
  ui_info "Final cleanup and system optimization..."
  step "Maintenance" && source "$SCRIPTS_DIR/maintenance.sh" || log_error "Maintenance failed"
  mark_step_complete_with_progress "maintenance"
else
  ui_info "Step 10 (Maintenance) already completed - skipping"
fi

echo ""
echo "==========================================" >> "$INSTALL_LOG"
echo "Installation ended: $(date)" >> "$INSTALL_LOG"
echo "==========================================" >> "$INSTALL_LOG"

# Display a friendly Installation Summary (uses gum if available)
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

# Call component summaries if available (programs/gaming)
if declare -f print_programs_summary >/dev/null 2>&1; then
  print_programs_summary
fi

if declare -f print_gaming_summary >/dev/null 2>&1; then
  print_gaming_summary
fi

# Print generic installation summary from common.sh
if declare -f print_summary >/dev/null 2>&1; then
  print_summary
fi

# Log performance/time taken if available
if declare -f log_performance >/dev/null 2>&1; then
  log_performance "Total installation time"
fi

# Save a compact installation summary to the install log
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

# Final result message (styled when gum available)
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

# Delegate reboot prompt to centralized function in common.sh
prompt_reboot
