#!/bin/bash
set -uo pipefail

# Prevent multiple sourcing
if [[ "${COMMON_SH_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly COMMON_SH_LOADED=true

# Color variables for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Terminal formatting helpers
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)

# Global arrays and variables
ERRORS=()                   # Collects error messages for summary
CURRENT_STEP=1              # Tracks current step for progress display
INSTALLED_PACKAGES=()       # Tracks installed packages
REMOVED_PACKAGES=()         # Tracks removed packages
FAILED_PACKAGES=()          # Tracks packages that failed to install

# Timing and progress tracking
STEP_TIMES=()               # Tracks time for each step
STEP_START_TIME=0           # Start time of current step
INSTALLATION_START_TIME=0   # Overall installation start time

# UI/Flow configuration
TOTAL_STEPS=10
: "${VERBOSE:=false}"   # Can be overridden/exported by caller

# Configuration constants
readonly MIN_DISK_SPACE_KB=2097152  # 2GB in KB
readonly DEFAULT_TIMEOUT=3
readonly MAX_RETRIES=3
readonly HIGH_MEMORY_THRESHOLD_GB=32
readonly LOW_MEMORY_THRESHOLD_GB=4

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"  # Script directory
CONFIGS_DIR="$SCRIPT_DIR/configs"                           # Config files directory
SCRIPTS_DIR="$SCRIPT_DIR/scripts"                           # Custom scripts directory

# HELPER_UTILS defined in distro_check.sh

# : "${INSTALL_MODE:=default}"

# Ensure critical variables are defined
: "${HOME:=/home/$USER}"
: "${USER:=$(whoami)}"
: "${XDG_CURRENT_DESKTOP:=}"
: "${INSTALL_LOG:=$HOME/.linuxinstaller.log}"

# Helper: detect whether Plymouth is fully configured end-to-end.
# Returns 0 when:
#  - mkinitcpio.conf contains a plymouth hook (sd-plymouth or plymouth)
#  - a plymouth theme is available/set (plymouth-set-default-theme prints something)
#  - the kernel 'splash' parameter is present in systemd-boot entries OR in /etc/default/grub
# Otherwise returns 1.
is_plymouth_fully_configured() {
  local mkinitcpio_conf="/etc/mkinitcpio.conf"
  local hook_present=false
  local theme_set=false
  local splash_present=false

  # Check for plymouth hook in mkinitcpio.conf
  if grep -q "plymouth" "$mkinitcpio_conf" 2>/dev/null; then
    hook_present=true
  fi

  # Check if plymouth-set-default-theme exists and reports themes
  if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    if plymouth-set-default-theme 2>/dev/null | grep -qv "^$"; then
      theme_set=true
    fi
  fi

  # Check for splash kernel parameter in common bootloader locations
  if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
    if grep -q "splash" /boot/loader/entries/*.conf 2>/dev/null; then
      splash_present=true
    fi
  elif [ -f /etc/default/grub ]; then
    if grep -q 'splash' /etc/default/grub 2>/dev/null; then
      splash_present=true
    fi
  fi

  if [ "$hook_present" = true ] && [ "$theme_set" = true ] && [ "$splash_present" = true ]; then
    return 0
  else
    return 1
  fi
}

# ===== Logging Functions =====

# Log to both console and log file
log_to_file() {
  echo "$1" >> "$INSTALL_LOG" 2>/dev/null || true
}

# Improved terminal output functions
clear_line() {
  echo -ne "\r\033[K"
}

print_progress() {
  local current="$1"
  local total="$2"
  local description="$3"
  local max_width=$((TERM_WIDTH - 5))

  # Truncate description if too long
  if [ ${#description} -gt $max_width ]; then
    description="${description:0:$((max_width-3))}..."
  fi

  clear_line

  printf "${CYAN}%s${RESET}" "$description"
}

# Enhanced progress bar for long operations with speed indicator
show_progress_bar() {
  local current="$1"
  local total="$2"
  local description="$3"
  local speed="${4:-}"
  local max_width=$((TERM_WIDTH - 15))

  # Truncate description if too long
  if [ ${#description} -gt $max_width ]; then
    description="${description:0:$((max_width-3))}..."
  fi

  clear_line

  printf "${CYAN}%s" "$description"

  if [ -n "$speed" ]; then
    printf " ${GREEN}%s${RESET}" "$speed"
  fi

  printf "${RESET}"
}

print_status() {
  local status="$1"
  local color="$2"
  echo -e "$color$status${RESET}"
}

# Format time display helper function
format_time() {
  local seconds=$1
  if [ $seconds -lt 60 ]; then
    echo "${seconds}s"
  elif [ $seconds -lt 3600 ]; then
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    echo "${minutes}m ${remaining_seconds}s"
  else
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    echo "${hours}h ${minutes}m"
  fi
}

# Timing functions for progress estimation
start_step_timer() {
  STEP_START_TIME=$(date +%s)
  if [ $INSTALLATION_START_TIME -eq 0 ]; then
    INSTALLATION_START_TIME=$STEP_START_TIME
  fi
}

end_step_timer() {
  local step_name="${1:-Step $CURRENT_STEP}"
  local end_time=$(date +%s)
  local duration=$((end_time - STEP_START_TIME))
  STEP_TIMES+=("$duration")

  # Calculate average time per step
  local total_time=0
  for time in "${STEP_TIMES[@]}"; do
    total_time=$((total_time + time))
  done

  local avg_time=$((total_time / ${#STEP_TIMES[@]}))
  local remaining_steps=$((TOTAL_STEPS - CURRENT_STEP))
  local estimated_remaining=$((remaining_steps * avg_time))

  if [ $remaining_steps -gt 0 ]; then
    ui_info "Step completed in $(format_time $duration). Estimated remaining time: $(format_time $estimated_remaining)"
  fi
}

# Enhanced step header with time estimation
print_step_header_with_timing() {
  local step_num="$1"
  local total="$2"
  local title="$3"

  CURRENT_STEP=$step_num
  start_step_timer

  if supports_gum; then
    echo ""
    gum style --margin "1 2" --border thick --padding "1 2" --foreground 15 "Step $step_num of $total: $title"

    # Show estimated remaining time
    if [ ${#STEP_TIMES[@]} -gt 0 ]; then
      local total_time=0
      for time in "${STEP_TIMES[@]}"; do
        total_time=$((total_time + time))
      done
      local avg_time=$((total_time / ${#STEP_TIMES[@]}))
      local remaining_steps=$((TOTAL_STEPS - step_num + 1))
      local estimated_remaining=$((remaining_steps * avg_time))

      if [ $estimated_remaining -lt 60 ]; then
        gum style --margin "0 2" --foreground 226 "Estimated remaining time: ${estimated_remaining}s"
      elif [ $estimated_remaining -lt 3600 ]; then
        local minutes=$((estimated_remaining / 60))
        gum style --margin "0 2" --foreground 226 "Estimated remaining time: ${minutes}m"
      else
        local hours=$((estimated_remaining / 3600))
        local minutes=$(((estimated_remaining % 3600) / 60))
        gum style --margin "0 2" --foreground 226 "Estimated remaining time: ${hours}h ${minutes}m"
      fi
    fi
  else
    print_step_header "$step_num" "$total" "$title"
  fi
}

# Unified styling functions for consistent UI across all scripts
print_unified_step_header() {
  local step_num="$1"
  local total="$2"
  local title="$3"

  if supports_gum; then
    echo ""
    gum style --margin "1 2" --border thick --padding "1 2" --foreground 15 "Step $step_num of $total: $title"
    echo ""
  else
    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${CYAN}  Step $step_num of $total: $title${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo ""
  fi
}

print_unified_substep() {
  local description="$1"

  if supports_gum; then
    gum style --margin "0 2" --foreground 226 "> $description"
  else
    echo -e "${CYAN}> $description${RESET}"
  fi
}

print_unified_success() {
  local message="$1"

  if supports_gum; then
    gum style --margin "0 4" --foreground 10 "✓ $message"
  else
    echo -e "${GREEN}✓ $message${RESET}"
  fi
}

print_unified_error() {
  local message="$1"

  if supports_gum; then
    gum style --margin "0 4" --foreground 196 "✗ $message"
  else
    echo -e "${RED}✗ $message${RESET}"
  fi
}

# Utility/Helper Functions
supports_gum() {
  command -v gum >/dev/null 2>&1
}

ui_info() {
  local message="$1"
  if supports_gum; then
    gum style --foreground 226 "$message"
  else
    echo -e "${YELLOW}$message${RESET}"
  fi
}

ui_success() {
  local message="$1"
  if supports_gum; then
    gum style --foreground 46 "$message"
  else
    echo -e "${GREEN}$message${RESET}"
  fi
}

ui_warn() {
  local message="$1"
  if supports_gum; then
    gum style --foreground 226 "$message"
  else
    echo -e "${YELLOW}$message${RESET}"
  fi
}

ui_error() {
  local message="$1"
  if supports_gum; then
    gum style --foreground 196 "$message"
  else
    echo -e "${RED}$message${RESET}"
  fi
}

print_header() {
  local title="$1"; shift
  if supports_gum; then
    gum style --border double --margin "1 2" --padding "1 4" --foreground 51 --border-foreground 51 "$title"
    while (( "$#" )); do
      gum style --margin "1 0 0 0" --foreground 226 "$1"
      shift
    done
  else
    echo -e "${CYAN}----------------------------------------------------------------${RESET}"
    echo -e "${CYAN}$title${RESET}"
    echo -e "${CYAN}----------------------------------------------------------------${RESET}"
    while (( "$#" )); do
      echo -e "${YELLOW}$1${RESET}"
      shift
    done
  fi
}

print_step_header() {
  local step_num="$1"; local total="$2"; local title="$3"
  if supports_gum; then
    echo ""
    gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "Step ${step_num}/${total}: ${title}"
  else
    echo -e "${CYAN}Step ${step_num}/${total}: ${title}${RESET}"
  fi
}
figlet_banner() {
  local title="$1"
  echo -e "${CYAN}\n============================================================${RESET}"
  if command -v figlet >/dev/null 2>/dev/null; then
    figlet "$title"
  else
    echo -e "${CYAN}========== $title ==========${RESET}"
  fi
}

linux_ascii() {
  echo -e "${BLUE}"
  cat << "EOF"
   _     _                  ___           _        _ _
  | |   (_)_ __  _   ___   |_ _|_ __  ___| |_ __ _| | | ___ _ __
  | |   | | "_ \| | | \ \/ /| || "_ \/ __| __/ _` | | |/ _ \ "__|
  | |___| | | | | |_| |>  < | || | | \__ \ || (_| | | |  __/ |
  |_____|_|_| |_|\__,_/_/\_\___|_| |_|___/\__\__,_|_|_|\___|_|

EOF
  echo -e "${RESET}"
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

show_menu() {
  # Check if gum is available, fallback to traditional menu if not
  if command -v gum >/dev/null 2>&1; then
    show_gum_menu
  else
    show_traditional_menu
  fi
}

show_gum_menu() {
  gum style --margin "1 0" --foreground 226 "This script will transform your fresh Linux installation into a"
  gum style --margin "0 0 1 0" --foreground 226 "fully configured, optimized system with all the tools you need!"

  local choice=$(gum choose --cursor="-> " --selected.foreground 51 --cursor.foreground 51 \
    "Standard - Complete setup with all packages (intermediate users)" \
    "Minimal - Essential tools only (recommended for new users)" \
    "Server - Headless server setup (Docker, SSH, etc.)" \
    "Custom - Interactive selection (choose what to install) (advanced users)" \
    "Exit - Cancel installation")

  case "$choice" in
    "Standard"*)
      INSTALL_MODE="default"
      print_header "Installation Mode" "Standard - Complete setup with all recommended packages"
      ;;
    "Minimal"*)
      INSTALL_MODE="minimal"
      print_header "Installation Mode" "Minimal - Essential tools only for lightweight installations"
      ;;
    "Server"*)
      INSTALL_MODE="server"
      print_header "Installation Mode" "Server - Headless server setup"
      ;;
    "Custom"*)
      INSTALL_MODE="custom"
      print_header "Installation Mode" "Custom - Interactive selection of packages to install"
      ;;
    "Exit"*)
      gum style --foreground 226 "Installation cancelled. You can run this script again anytime."
      exit 0
      ;;
  esac
}

show_traditional_menu() {
  echo -e "${CYAN}----------------------------------------------------------------${RESET}"
  echo -e "${CYAN}WELCOME TO ARCH INSTALLER${RESET}"
  echo -e "${CYAN}----------------------------------------------------------------${RESET}"
  echo -e "${YELLOW}This script will transform your fresh Linux installation into a${RESET}"
  echo -e "${YELLOW}fully configured, optimized system with all the tools you need!${RESET}"
  echo ""
  echo -e "${CYAN}Choose your installation mode:${RESET}"
  echo ""
  printf "${BLUE}  1) Standard${RESET}%-12s - Complete setup with all packages (intermediate users)\n" ""
  printf "${GREEN}  2) Minimal${RESET}%-13s - Essential tools only (recommended for new users)\n" ""
  printf "${CYAN}  3) Server${RESET}%-13s - Headless server setup (Docker, SSH, etc.)\n" ""
  printf "${YELLOW}  4) Custom${RESET}%-14s - Interactive selection (choose what to install) (advanced users)\n" ""
  printf "${RED}  5) Exit${RESET}%-16s - Cancel installation\n" ""
  echo ""

  while true; do
    read -r -p "$(echo -e "${CYAN}Enter your choice [1-5]: ${RESET}")" menu_choice
          case "$menu_choice" in
        1)
          INSTALL_MODE="default"
          print_header "Installation Mode" "Standard - Complete setup with all recommended packages"
          break
          ;;
        2)
          INSTALL_MODE="minimal"
          print_header "Installation Mode" "Minimal - Essential tools only for lightweight installations"
          break
          ;;
        3)
          INSTALL_MODE="server"
          print_header "Installation Mode" "Server - Headless server setup"
          break
          ;;
        4)
          INSTALL_MODE="custom"
          print_header "Installation Mode" "Custom - Interactive selection of packages to install"
          break
          ;;
      5)
        echo -e "\n${YELLOW}Installation cancelled. You can run this script again anytime.${RESET}"
        exit 0
        ;;
      *)
        echo -e "\n${RED}Invalid choice! Please enter 1, 2, 3, 4, or 5.${RESET}\n"
        ;;
    esac
  done
}

# Function: step
# Description: Prints a step header and increments step counter
# Parameters: $1 - Step description
step() {
  local msg="\n${CYAN}> $1${RESET}"
  echo -e "$msg"
  log_to_file "STEP: $1"
  ((CURRENT_STEP++))
}

# Function: log_success
# Description: Prints success message in green
# Parameters: $1 - Success message
log_success() {
  echo -e "${GREEN}$1${RESET}"
  log_to_file "SUCCESS: $1"
}

# Function: log_warning
# Description: Prints warning message in yellow
# Parameters: $1 - Warning message
log_warning() {
  echo -e "${YELLOW}! $1${RESET}"
  log_to_file "WARNING: $1"
}

# Function: log_error
# Description: Prints error message in red and adds to error array
# Parameters: $1 - Error message
log_error() {
  echo -e "${RED}$1${RESET}"
  ERRORS+=("$1")
  log_to_file "ERROR: $1"
}

# Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function: validate_package_name
# Description: Validates package name format
# Parameters: $1 - Package name
# Returns: 0 if valid, 1 if invalid
validate_package_name() {
  local pkg="$1"

  if [[ -z "$pkg" ]]; then
    log_error "Package name cannot be empty"
    return 1
  fi

  # Package names should only contain alphanumeric, -, _, and .
  if [[ ! "$pkg" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    log_error "Invalid package name format: $pkg"
    return 1
  fi

  return 0
}

# Function: check_sudo_access
# Description: Validates sudo is available and user has privileges
# Returns: 0 on success, 1 on failure
check_sudo_access() {
  if ! command -v sudo &>/dev/null; then
    local install_cmd=""
    if [ -n "${PKG_INSTALL:-}" ]; then
      install_cmd="$PKG_INSTALL sudo"
    elif [ -n "${DISTRO_ID:-}" ]; then
      case "$DISTRO_ID" in
        arch) install_cmd="sudo pacman -S sudo" ;;
        fedora) install_cmd="sudo dnf install sudo" ;;
        debian|ubuntu) install_cmd="sudo apt-get install sudo" ;;
        *) install_cmd="install sudo using your package manager" ;;
      esac
    else
      install_cmd="install sudo using your package manager"
    fi
    log_error "sudo is not installed. Please install it: $install_cmd"
    return 1
  fi

  # Test sudo access
  if ! sudo -n true 2>/dev/null; then
    ui_info "Please enter your sudo password:"
    if ! sudo -v; then
      log_error "Sudo authentication failed"
      return 1
    fi
  fi

  return 0
}

# Function: handle_package_error
# Description: Provides actionable error messages for package installation failures
# Parameters: $1 - Package name, $2 - Error output
handle_package_error() {
  local pkg="$1"
  local error_output="$2"
  local search_cmd=""
  local refresh_cmd=""

  # Determine distro-specific commands
  if [ -n "${DISTRO_ID:-}" ]; then
    case "$DISTRO_ID" in
      arch)
        search_cmd="pacman -Ss $pkg"
        refresh_cmd="sudo pacman-key --refresh-keys"
        ;;
      fedora)
        search_cmd="dnf search $pkg"
        refresh_cmd="sudo dnf makecache"
        ;;
      debian|ubuntu)
        search_cmd="apt-cache search $pkg"
        refresh_cmd="sudo apt-get update"
        ;;
    esac
  fi

  case "$error_output" in
    *"not found"*|*"target not found"*|*"no package"*|*"unable to locate"*)
      log_error "Package '$pkg' not found in repositories"
      [ -n "$search_cmd" ] && log_info "Try searching: $search_cmd"
      ;;
    *"conflict"*|*"conflicts"*)
      log_error "Package '$pkg' conflicts with installed packages"
      log_info "You may need to resolve conflicts manually"
      ;;
    *"signature"*|*"PGP"*|*"gpg"*|*"key"*)
      log_error "Package signature verification failed for '$pkg'"
      [ -n "$refresh_cmd" ] && log_info "Try: $refresh_cmd"
      ;;
    *"permission"*|*"Permission denied"*)
      log_error "Permission denied installing '$pkg'"
      log_info "Check sudo access: sudo -v"
      ;;
    *)
      log_error "Failed to install $pkg"
      log_info "Check log for details: $INSTALL_LOG"
      ;;
  esac
}

# Function to get all installed kernel types
get_installed_kernel_types() {
  local kernel_types=()
  
  # Only works for Arch-based distros
  if [ "${DISTRO_ID:-}" != "arch" ]; then
    # For other distros, try to detect kernel version
    if [ -f /boot/vmlinuz-* ] || [ -f /boot/Image-* ]; then
      # Generic kernel detection - return empty or default
      kernel_types+=("linux")
    fi
    echo "${kernel_types[@]}"
    return 0
  fi
  
  # Arch-specific kernel detection
  if ! command_exists pacman; then
    log_warning "pacman not found. Cannot detect kernel types."
    return 1
  fi
  
  pacman -Q linux &>/dev/null && kernel_types+=("linux")
  pacman -Q linux-lts &>/dev/null && kernel_types+=("linux-lts")
  pacman -Q linux-zen &>/dev/null && kernel_types+=("linux-zen")
  pacman -Q linux-hardened &>/dev/null && kernel_types+=("linux-hardened")
  
  echo "${kernel_types[@]}"
}

# Function to configure plymouth hook and rebuild initramfs
configure_plymouth_hook_and_initramfs() {
  # Only works for Arch-based distros (mkinitcpio)
  if [ "${DISTRO_ID:-}" != "arch" ]; then
    log_info "Plymouth initramfs configuration is Arch-specific. Skipping for $DISTRO_ID."
    return 0
  fi
  
  step "Configuring Plymouth hook and rebuilding initramfs"
  local mkinitcpio_conf="/etc/mkinitcpio.conf"
  local HOOK_ADDED=false
  local HOOK_NAME=""

  # Check if mkinitcpio.conf exists
  if [ ! -f "$mkinitcpio_conf" ]; then
    log_warning "mkinitcpio.conf not found. Plymouth hook configuration skipped."
    return 0
  fi

  # ===== Determine which initcpio hook is actually available =====
  # Prefer sd-plymouth (systemd variant) if present; otherwise fallback to plymouth.
  if [ -f "/usr/lib/initcpio/install/sd-plymouth" ]; then
    HOOK_NAME="sd-plymouth"
  elif [ -f "/usr/lib/initcpio/install/plymouth" ]; then
    HOOK_NAME="plymouth"
  else
    # Try pacman installation (pacman-only policy; no AUR)
    log_error "Plymouth initcpio hooks not found. Is plymouth installed?"
    log_info "Attempting to install plymouth package..."
    if [ -n "${PKG_INSTALL:-}" ]; then
      if $PKG_INSTALL ${PKG_NOCONFIRM:-} plymouth >/dev/null 2>&1; then
        log_success "Installed plymouth."
        if [ -f "/usr/lib/initcpio/install/sd-plymouth" ]; then
          HOOK_NAME="sd-plymouth"
        elif [ -f "/usr/lib/initcpio/install/plymouth" ]; then
          HOOK_NAME="plymouth"
        fi
      fi
    fi

    if [ -z "$HOOK_NAME" ]; then
      log_error "Could not find or install a plymouth initcpio hook. Please install 'plymouth' and re-run the installer."
      return 1
    fi
  fi

  # ===== Ensure mkinitcpio.conf contains the correct hook name =====
  if grep -q "$HOOK_NAME" "$mkinitcpio_conf" 2>/dev/null; then
    log_info "Plymouth hook ($HOOK_NAME) already present in mkinitcpio.conf."
    HOOK_ADDED=true
  else
    log_info "Adding $HOOK_NAME hook to mkinitcpio.conf..."

    # Place the hook sensibly: after systemd (if present), otherwise after udev, otherwise before filesystems, otherwise append.
    if grep -q "^HOOKS=.*systemd" "$mkinitcpio_conf" && ! grep -q "^HOOKS=.*udev" "$mkinitcpio_conf"; then
        sudo sed -i "s/\\(HOOKS=.*\\)systemd/\\1systemd $HOOK_NAME/" "$mkinitcpio_conf"
        log_info "Added $HOOK_NAME hook (systemd detected)."
    elif grep -q "udev" "$mkinitcpio_conf"; then
        sudo sed -i "s/\\(HOOKS=.*\\)udev/\\1udev $HOOK_NAME/" "$mkinitcpio_conf"
        log_info "Added $HOOK_NAME hook (udev detected)."
    else
        if grep -q "filesystems" "$mkinitcpio_conf"; then
            sudo sed -i "s/\\(HOOKS=.*\\)filesystems/\\1$HOOK_NAME filesystems/" "$mkinitcpio_conf"
        else
            sudo sed -i "s/^\\(HOOKS=.*\\)\\\"$/\\1 $HOOK_NAME\\\"/" "$mkinitcpio_conf"
        fi
        log_info "Added $HOOK_NAME hook (fallback placement)."
    fi

    if [ $? -eq 0 ]; then
      log_success "Added $HOOK_NAME hook to mkinitcpio.conf."
      HOOK_ADDED=true
    else
      log_error "Failed to add $HOOK_NAME hook to mkinitcpio.conf."
      return 1
    fi
  fi

  # If mkinitcpio.conf contains sd-plymouth but the system only provides 'plymouth', normalize to the available hook.
  if grep -q "sd-plymouth" "$mkinitcpio_conf" 2>/dev/null && [ "$HOOK_NAME" != "sd-plymouth" ]; then
      sudo sed -i "s/sd-plymouth/$HOOK_NAME/g" "$mkinitcpio_conf"
      log_info "Replaced sd-plymouth with $HOOK_NAME in mkinitcpio.conf"
  fi

  # ===== Rebuild initramfs for all detected kernels (if we added a hook) =====
  if [ "${SKIP_MKINITCPIO:-false}" = "true" ]; then
    log_info "Skipping initramfs rebuild (SKIP_MKINITCPIO is set). It will be handled later."
    return 0
  fi

  if [ "$HOOK_ADDED" = true ]; then
    local kernel_types
    kernel_types=($(get_installed_kernel_types))

    if [ "${#kernel_types[@]}" -eq 0 ]; then
      log_warning "No supported kernel types detected. Cannot rebuild initramfs for Plymouth."
      return 0
    fi

    echo -e "${CYAN}Detected kernels: ${kernel_types[*]}${RESET}"

    local total=${#kernel_types[@]}
    local current=0
    local success_count=0

    for kernel in "${kernel_types[@]}"; do
      ((current++))
      print_progress "$current" "$total" "Rebuilding initramfs for $kernel (for Plymouth)"

      local mkinitcpio_output
      if mkinitcpio_output=$(sudo mkinitcpio -p "$kernel" 2>&1); then
        print_status " [OK]" "$GREEN"
        log_success "Rebuilt initramfs for $kernel"
        ((success_count++))
      else
        print_status " [FAIL]" "$RED"
        log_error "Failed to rebuild initramfs for $kernel (for Plymouth)"
        echo -e "${RED}mkinitcpio output:${RESET}\n$mkinitcpio_output"
      fi
    done

    if [ "$success_count" -eq "$total" ]; then
      log_success "Initramfs rebuilt for all detected kernels for Plymouth."
    elif [ "$success_count" -gt 0 ]; then
      log_warning "Initramfs rebuilt for some kernels for Plymouth, but not all."
    else
      log_error "Failed to rebuild initramfs for any kernel for Plymouth."
      return 1
    fi
  fi

  return 0
}

# Function: log_info
# Description: Prints info message in cyan
# Parameters: $1 - Info message
log_info() {
  echo -e "${CYAN}$1${RESET}"
  log_to_file "INFO: $1"
}

# Function: run_step
# Description: Runs a command with step logging and error handling
# Parameters: $1 - Step description, $@ - Command to execute
# Returns: 0 on success, non-zero on failure
run_step() {
  local description="$1"
  shift
  step "$description"

  local temp_log
  temp_log=$(mktemp)

  if "$@" > "$temp_log" 2>&1; then
    cat "$temp_log" >> "$INSTALL_LOG"
    rm -f "$temp_log"
    log_success "$description"

    # Track installed packages
    if [[ "$description" == "Installing helper utilities" ]]; then
      INSTALLED_PACKAGES+=("${HELPER_UTILS[@]}")
    elif [[ "$description" == "Installing UFW firewall" ]]; then
      INSTALLED_PACKAGES+=("ufw")
    elif [[ "$description" =~ ^Installing\  ]]; then
      local pkg
      pkg=$(echo "$description" | awk '{print $2}')
      INSTALLED_PACKAGES+=("$pkg")
    elif [[ "$description" == "Removing figlet and gum" ]]; then
      REMOVED_PACKAGES+=("figlet" "gum")
    fi
    return 0
  else
    cat "$temp_log" >> "$INSTALL_LOG"
    log_error "$description failed"
    echo -e "${RED}Command output:${RESET}"
    sed 's/^/  /' "$temp_log"
    rm -f "$temp_log"
    return 1
  fi
}

# Function: install_package_generic
# Description: Generic package installer for pacman, AUR, or flatpak
# Parameters: $1 - Package manager type (pacman|aur|flatpak), $@ - Packages to install
# Returns: 0 on success, 1 if some packages failed
install_package_generic() {
  local pkg_manager="$1"
  shift
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local current=0
  local failed=0

  if [ $total -eq 0 ]; then
    ui_info "No packages to install"
    return 0
  fi

  local manager_name
  case "$pkg_manager" in
    pacman) manager_name="Pacman" ;;
    aur) manager_name="AUR" ;;
    flatpak) manager_name="Flatpak" ;;
    *) manager_name="Unknown" ;;
  esac

  if supports_gum; then
    gum style --foreground 51 "Installing ${total} packages via ${manager_name}..."
  else
    echo -e "${CYAN}Installing ${total} packages via ${manager_name}...${RESET}"
  fi

  # Filter valid packages
  local valid_pkgs=()
  for pkg in "${pkgs[@]}"; do
    if validate_package_name "$pkg"; then
      valid_pkgs+=("$pkg")
    else
      ((failed++))
    fi
  done

  if [ ${#valid_pkgs[@]} -eq 0 ]; then
    return 1
  fi

  # Attempt batch installation first (except for dry-run)
  if [ "${DRY_RUN:-false}" = false ]; then
    local batch_cmd=""
    local batch_args="${valid_pkgs[*]}"

    case "$pkg_manager" in
      pacman)
        batch_cmd="sudo pacman -S --noconfirm --needed $batch_args"
        ;;
      aur)
        batch_cmd="yay -S --noconfirm --needed $batch_args"
        ;;
      flatpak)
        batch_cmd="sudo flatpak install --noninteractive -y $batch_args"
        ;;
    esac

    if [ -n "$batch_cmd" ]; then
      ui_info "Attempting batch installation for improved performance..."
      if eval "$batch_cmd" >> "$INSTALL_LOG" 2>&1; then
        ui_success "Batch installation successful"
        INSTALLED_PACKAGES+=("${valid_pkgs[@]}")
        return 0
      else
        ui_warn "Batch installation failed. Falling back to individual installation..."
      fi
    fi
  fi

  # Fallback to individual installation
  for pkg in "${valid_pkgs[@]}"; do
    ((current++))

    # Check if already installed
    local already_installed=false
    case "$pkg_manager" in
      pacman|aur)
        pacman -Q "$pkg" &>/dev/null && already_installed=true
        ;;
      flatpak)
        flatpak list | grep -q "$pkg" &>/dev/null && already_installed=true
        ;;
    esac

    if [ "$already_installed" = true ]; then
      $VERBOSE && ui_info "[$current/${#valid_pkgs[@]}] $pkg [SKIP] Already installed"
      continue
    fi

    $VERBOSE && ui_info "[$current/${#valid_pkgs[@]}] Installing $pkg..."

    local install_cmd
    case "$pkg_manager" in
      pacman)
        install_cmd="sudo pacman -S --noconfirm --needed $pkg"
        ;;
      aur)
        install_cmd="yay -S --noconfirm --needed $pkg"
        ;;
      flatpak)
        install_cmd="sudo flatpak install --noninteractive -y $pkg"
        ;;
    esac

    # Dry-run mode: simulate installation
    if [ "${DRY_RUN:-false}" = true ]; then
      ui_info "[$current/${#valid_pkgs[@]}] $pkg [DRY-RUN]"
      ui_info "  Would execute: $install_cmd"
      INSTALLED_PACKAGES+=("$pkg")
    else
      # Capture both stdout and stderr for better error diagnostics
      local error_output
      if error_output=$(eval "$install_cmd" 2>&1); then
        $VERBOSE && ui_success "[$current/${#valid_pkgs[@]}] $pkg [OK]"
        INSTALLED_PACKAGES+=("$pkg")
    else
      ui_error "[$current/${#valid_pkgs[@]}] $pkg [FAIL]"
      FAILED_PACKAGES+=("$pkg")
      handle_package_error "$pkg" "$error_output"
      log_error "Failed to install $pkg via $manager_name"
      # Log the actual error for debugging
      echo "$error_output" >> "$INSTALL_LOG"
      # Show last line of error if verbose or if it's a critical error
      if $VERBOSE || [[ "$error_output" == *"error:"* ]]; then
        local last_error=$(echo "$error_output" | grep -i "error" | tail -1)
        [ -n "$last_error" ] && log_warning "  Error: $last_error"
      fi
      ((failed++))
    fi
    fi
  done

  if [ $failed -eq 0 ]; then
    ui_success "Package installation completed (${current}/${#valid_pkgs[@]} packages processed)"
    return 0
  else
    ui_warn "Package installation completed with $failed failures (${current}/${#valid_pkgs[@]} packages processed)"
    return 1
  fi
}

# Function: install_packages_quietly
# Description: Install packages via package manager with minimal output
# Parameters: $@ - Packages to install
# Override install_packages_quietly for multi-distro support
install_packages_quietly() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then return 0; fi
    
    # Use global PKG_INSTALL if defined, else fallback to pacman
    local cmd="${PKG_INSTALL:-sudo pacman -S --needed}"
    local opts="${PKG_NOCONFIRM:-}"
    
    local final_packages=()
    for pkg in "${packages[@]}"; do
        # Use the resolver logic
        if command -v resolve_package_name >/dev/null; then
             local mapped=$(resolve_package_name "$pkg")
             [ -n "$mapped" ] && final_packages+=($mapped)
        else
             final_packages+=("$pkg")
        fi
    done
    
    if [ ${#final_packages[@]} -eq 0 ]; then return 0; fi

    # Install with minimal output: package name + OK/FAIL
    for pkg in "${final_packages[@]}"; do
        printf "%-40s" "$pkg"
        if $cmd $opts "$pkg" >/dev/null 2>&1; then
            printf "${GREEN}OK${RESET}\n"
        else
            printf "${RED}FAIL${RESET}\n"
        fi
    done
}

# Batch install helper for multiple package groups
install_package_groups() {
  local groups=("$@")
  local all_packages=()

  for group in "${groups[@]}"; do
    case "$group" in
      "helpers")
        all_packages+=("${HELPER_UTILS[@]}")
        ;;
      "zsh")
        all_packages+=(zsh zsh-autosuggestions zsh-syntax-highlighting)
        ;;
      "starship")
        all_packages+=(starship)
        ;;
      "zram")
        all_packages+=(zram-generator)
        ;;
      # Add more groups as needed
    esac
  done

  # Remove duplicates before batch install
  if [ "${#all_packages[@]}" -gt 0 ]; then
    # Use associative array to filter duplicates
    declare -A pkg_map
    for pkg in "${all_packages[@]}"; do
      pkg_map["$pkg"]=1
    done
    local unique_pkgs=()
    for pkg in "${!pkg_map[@]}"; do
      unique_pkgs+=("$pkg")
    done
    install_packages_quietly "${unique_pkgs[@]}"
  fi
}

print_summary() {
  echo -e "\n${CYAN}=== INSTALL SUMMARY ===${RESET}"
  [ "${#INSTALLED_PACKAGES[@]}" -gt 0 ] && echo -e "${GREEN}Installed: ${INSTALLED_PACKAGES[*]}${RESET}"
  [ "${#REMOVED_PACKAGES[@]}" -gt 0 ] && echo -e "${RED}Removed: ${REMOVED_PACKAGES[*]}${RESET}"
  [ "${#ERRORS[@]}" -gt 0 ] && echo -e "\n${RED}Errors: ${ERRORS[*]}${RESET}"
  echo -e "${CYAN}======================${RESET}"
}

# Function to display a styled header for summaries
# Usage: ui_header "My Header"
ui_header() {
    local title="$1"
    if supports_gum; then
        gum style --border normal --margin "1 2" --padding "1 2" --align center "$title"
    else
        echo ""
        echo -e "${CYAN}### ${title} ###${RESET}"
        echo ""
    fi
}

supports_gum() {
  command -v gum >/dev/null 2>&1
}

# Function for user confirmation with gum (or fallback)
# Usage: gum_confirm "Your question?" "Optional description."
gum_confirm() {
    local question="$1"
    local description="${2:-}" # Default to empty string if not provided

    if supports_gum; then
        # Use gum for a nice UI
        if [ -n "$description" ]; then
            gum style --foreground 226 "$description"
        fi

        if gum confirm --default=true "$question"; then
            return 0 # User said yes
        else
            return 1 # User said no
        fi
    else
        # Fallback to traditional read prompt
        echo ""
        if [ -n "$description" ]; then
            echo -e "${YELLOW}${description}${RESET}"
        fi

        local response
        while true; do
            read -r -p "$(echo -e "${CYAN}${question} [Y/n]: ${RESET}")" response
            response=${response,,} # tolower
            case "$response" in
                ""|y|yes)
                    return 0 # Yes
                    ;;
                n|no)
                    return 1 # No
                    ;;
                *)
                    echo -e "\n${RED}Please answer Y (yes) or N (no).${RESET}\n"
                    ;;
            esac
        done
    fi
}

prompt_reboot() {
  figlet_banner "Reboot System"
  echo -e "${YELLOW}Congratulations! Your Linux system is now fully configured!${RESET}"
  echo ""
  echo -e "${CYAN}What happens after reboot:${RESET}"
  echo -e "  - Boot screen will appear"
  echo -e "  - Your desktop environment will be ready to use"
  echo -e "  - Security features will be active"
  echo -e "  - Performance optimizations will be enabled"
  echo -e "  - Gaming tools will be available (if installed)"
  echo ""

  local REBOOT_CHOICE=0
  if supports_gum; then
    if gum confirm --default=true "Reboot system now?"; then
      REBOOT_CHOICE=1
    else
      REBOOT_CHOICE=0
    fi
  else
    while true; do
      read -r -p "Reboot now? [Y/n]: " yn
      case $yn in
        [Yy]*|"" ) REBOOT_CHOICE=1; break;;
        [Nn]* ) REBOOT_CHOICE=0; break;;
        * ) echo "Please answer yes or no.";;
      esac
    done
  fi

  # Remove helpers installed by the script
  local TO_REMOVE=()
  [ "${FIGLET_INSTALLED_BY_SCRIPT:-false}" = true ] && TO_REMOVE+=("figlet")
  [ "${GUM_INSTALLED_BY_SCRIPT:-false}" = true ] && TO_REMOVE+=("gum")
  [ "${YQ_INSTALLED_BY_SCRIPT:-false}" = true ] && TO_REMOVE+=("yq")

  if [ ${#TO_REMOVE[@]} -gt 0 ]; then
    log_to_file "Removing temporary helpers: ${TO_REMOVE[*]}"
    for tool in "${TO_REMOVE[@]}"; do
        if [ "$tool" == "figlet" ]; then
             $PKG_REMOVE $PKG_NOCONFIRM figlet >/dev/null 2>&1 || true
        elif [ "$tool" == "gum" ]; then
             if [ "$DISTRO_ID" == "arch" ]; then
                 $PKG_REMOVE $PKG_NOCONFIRM gum >/dev/null 2>&1 || true
             else
                 sudo rm -f /usr/local/bin/gum
             fi
        elif [ "$tool" == "yq" ]; then
             if [ "$DISTRO_ID" == "arch" ]; then
                 $PKG_REMOVE $PKG_NOCONFIRM yq >/dev/null 2>&1 || true
             else
                 sudo rm -f /usr/local/bin/yq
             fi
        fi
    done
  fi

  if [ "$REBOOT_CHOICE" -eq 1 ]; then
    echo -e "${CYAN}Rebooting...${RESET}"
    sudo reboot
  else
    echo -e "${YELLOW}Please reboot manually: sudo reboot${RESET}"
  fi

  if [ ${#ERRORS[@]} -eq 0 ]; then
    if gum_confirm "Do you want to clean up temporary logs?" "This will remove the installation log and state file."; then
      rm -f "$STATE_FILE" "$INSTALL_LOG" 2>/dev/null || true
      echo -e "${GREEN}Cleanup complete${RESET}"
    fi
  fi
}

# Pre-download package lists for faster installation
preload_package_lists() {
  step "Preloading package lists for faster installation"
  sudo pacman -Sy --noconfirm >/dev/null 2>&1
  if command -v yay >/dev/null; then
    yay -Sy --noconfirm >/dev/null 2>&1
  else
    log_warning "yay not available for AUR package list update"
  fi
}

# Optimized system update
fast_system_update() {
  step "Performing optimized system update"
  sudo pacman -Syu --noconfirm --overwrite="*"
  if command -v yay >/dev/null; then
    yay -Syu --noconfirm
  else
    log_warning "yay not available for AUR update"
  fi
}

# Performance tracking
log_performance() {
  local step_name="$1"
  local current_time=$(date +%s)
  local elapsed=$((current_time - START_TIME))
  local minutes=$((elapsed / 60))
  local seconds=$((elapsed % 60))
  echo -e "${CYAN}$step_name completed in ${minutes}m ${seconds}s (${elapsed}s)${RESET}"
}

# Function to collect errors from custom scripts
collect_custom_script_errors() {
  local script_name="$1"
  local script_errors=("$@")
  shift
  for error in "${script_errors[@]}"; do
    ERRORS+=("$script_name: $error")
  done
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function: validate_file_operation
# Description: Validates file system operations before performing them
# Parameters: $1 - Operation type (read|write), $2 - File path, $3 - Description
# Returns: 0 if valid, 1 if invalid
validate_file_operation() {
  local operation="${1:?Operation type required}"
  local file="${2:?File path required}"
  local description="${3:-File operation}"

  # Check if file exists (for read operations)
  if [[ "$operation" == "read" ]] && [ ! -f "$file" ]; then
    log_error "File $file does not exist. Cannot perform: $description"
    return 1
  fi

  # Check if directory exists (for write operations)
  if [[ "$operation" == "write" ]] && [ ! -d "$(dirname "$file")" ]; then
    log_error "Directory $(dirname "$file") does not exist. Cannot perform: $description"
    return 1
  fi

  # Check permissions
  if [[ "$operation" == "write" ]] && [ ! -w "$(dirname "$file")" ]; then
    log_error "No write permission for $(dirname "$file"). Cannot perform: $description"
    return 1
  fi

  return 0
}

# Function: install_aur_quietly
# Description: Install packages via AUR helper (wrapper for generic installer)

# Check if system uses Btrfs filesystem
is_btrfs_system() {
  findmnt -no FSTYPE / | grep -q btrfs
}

# Detect bootloader type
detect_boot_mount() {
  local boot_mount="/boot"

  # Try to detect ESP for systemd-boot
  if command -v bootctl >/dev/null 2>&1; then
    local esp_path=$(bootctl -p 2>/dev/null)
    if [ -n "$esp_path" ] && [ -d "$esp_path" ]; then
      boot_mount="$esp_path"
    fi
  fi

  # Fallback checks
  if [ ! -d "$boot_mount" ] && [ -d "/efi" ]; then
    boot_mount="/efi"
  elif [ ! -d "$boot_mount" ] && [ -d "/boot/efi" ]; then
    boot_mount="/boot/efi"
  fi

  echo "$boot_mount"
}


detect_bootloader() {
  if [ -d "/boot/grub" ] || [ -d "/boot/grub2" ] || [ -d "/boot/efi/EFI/grub" ] || command -v grub-mkconfig &>/dev/null || pacman -Q grub &>/dev/null 2>&1; then
    echo "grub"
  elif [ -d "/boot/loader/entries" ] || [ -d "/efi/loader/entries" ] || command -v bootctl &>/dev/null; then
    echo "systemd-boot"
  else
    echo "unknown"
  fi
}
# Parameters: $@ - Packages to install
install_aur_quietly() {
  if ! command -v yay &>/dev/null; then
    log_error "AUR helper (yay) not found. Cannot install AUR packages."
    return 1
  fi
  install_package_generic "aur" "$@"
}

# Function: install_flatpak_quietly
# Description: Install packages via Flatpak (wrapper for generic installer)
# Parameters: $@ - Packages to install
install_flatpak_quietly() {
  if ! command -v flatpak &>/dev/null; then
    log_error "Flatpak not found. Cannot install Flatpak packages."
    return 1
  fi
  install_package_generic "flatpak" "$@"
}

check_and_enable_multilib() {
  # Only works for Arch-based distros
  if [ "${DISTRO_ID:-}" != "arch" ]; then
    log_info "Multilib configuration is Arch-specific. Skipping for $DISTRO_ID."
    return 0
  fi
  
  local needs_sync=false

  # Check if pacman.conf exists
  if [ ! -f /etc/pacman.conf ]; then
    log_warning "pacman.conf not found. Multilib configuration skipped."
    return 0
  fi

  # 1. Check if multilib is configured in pacman.conf
  if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    if grep -q "^#\[multilib\]" /etc/pacman.conf; then
      ui_info "Enabling multilib repository in /etc/pacman.conf..."
      # Uncomment [multilib] and the following Include line
      sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
      needs_sync=true
    else
      ui_warn "Multilib repository section not found in /etc/pacman.conf. Adding it..."
      echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
      needs_sync=true
    fi
  fi

  # 2. Check if the database file exists
  if [[ ! -f "/var/lib/pacman/sync/multilib.db" ]]; then
    ui_info "Multilib database not found. Syncing repositories..."
    needs_sync=true
  fi

  # 3. Sync if needed
  if [[ "$needs_sync" == "true" ]]; then
    if sudo pacman -Sy; then
      log_success "Repositories synced successfully."
    else
      log_error "Failed to sync repositories. 'wine' and other 32-bit packages might fail."
      return 1
    fi
  else
    log_success "Multilib repository is enabled and synced."
  fi
  return 0
}

# Override install_packages_quietly for multi-distro support (duplicate removed - using definition above)
