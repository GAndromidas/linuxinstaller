#!/bin/bash

# Color variables for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Terminal formatting helpers
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)

# Global arrays and variables
ERRORS=()                # Collects error messages for summary
CURRENT_STEP=1           # Tracks current step for progress display
INSTALLED_PACKAGES=()    # Tracks installed packages
REMOVED_PACKAGES=()      # Tracks removed packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"  # Script directory
CONFIGS_DIR="$SCRIPT_DIR/configs"                           # Config files directory
SCRIPTS_DIR="$SCRIPT_DIR/scripts"                           # Custom scripts directory

HELPER_UTILS=(base-devel bluez-utils cronie curl eza fastfetch figlet flatpak fzf git openssh pacman-contrib reflector rsync ufw zoxide)  # Helper utilities to install

# : "${INSTALL_MODE:=default}"

# Performance tracking
START_TIME=$(date +%s)

# Ensure critical variables are defined
: "${HOME:=/home/$USER}"
: "${USER:=$(whoami)}"
: "${XDG_CURRENT_DESKTOP:=}"

# Improved terminal output functions
clear_line() {
  echo -ne "\r\033[K"
}

print_progress() {
  local current="$1"
  local total="$2"
  local description="$3"
  local max_width=$((TERM_WIDTH - 20))  # Leave space for progress indicator
  
  # Truncate description if too long
  if [ ${#description} -gt $max_width ]; then
    description="${description:0:$((max_width-3))}..."
  fi
  
  clear_line
  printf "${CYAN}[%d/%d] %s${RESET}" "$current" "$total" "$description"
}

print_status() {
  local status="$1"
  local color="$2"
  echo -e "$color$status${RESET}"
}

# Utility/Helper Functions
figlet_banner() {
  local title="$1"
  echo -e "${CYAN}\n============================================================${RESET}"
  if command -v figlet >/dev/null 2>/dev/null; then
    figlet "$title"
  else
    echo -e "${CYAN}========== $title ==========${RESET}"
  fi
}

arch_ascii() {
  echo -e "${CYAN}"
  cat << "EOF"
      _             _     ___           _        _ _
     / \   _ __ ___| |__ |_ _|_ __  ___| |_ __ _| | | ___ _ __
    / _ \ | '__/ __| '_ \ | || '_ \/ __| __/ _` | | |/ _ \ '__|
   / ___ \| | | (__| | | || || | | \__ \ || (_| | | |  __/ |
  /_/   \_\_|  \___|_| |_|___|_| |_|___/\__\__,_|_|_|\___|_|

EOF
  echo -e "${RESET}"
}

show_menu() {
  echo -e "${YELLOW}Welcome to the Arch Installer script!${RESET}"
  echo "Please select your installation mode:"
  echo "  1) Default"
  echo "  2) Minimal"
  echo "  3) Custom"
  echo "  4) Exit"

  while true; do
    read -r -p "Enter your choice [1-4]: " menu_choice
    case "$menu_choice" in
      1) INSTALL_MODE="default"; break ;;
      2) INSTALL_MODE="minimal"; break ;;
      3) INSTALL_MODE="custom"; break ;;
      4) exit 0 ;;
      *) echo "Invalid choice!";;
    esac
  done
}

step() {
  echo -e "\n${CYAN}→ $1${RESET}"
  ((CURRENT_STEP++))
}

log_success() { echo -e "${GREEN}✓ $1${RESET}"; }
log_warning() { echo -e "${YELLOW}! $1${RESET}"; }
log_error()   { echo -e "${RED}✗ $1${RESET}"; ERRORS+=("$1"); }

run_step() {
  local description="$1"
  shift
  step "$description"
  "$@"
  local status=$?
  if [ $status -eq 0 ]; then
    log_success "$description"
    if [[ "$description" == "Installing helper utilities" ]]; then
      INSTALLED_PACKAGES+=("${HELPER_UTILS[@]}")
    elif [[ "$description" == "Installing UFW firewall" ]]; then
      INSTALLED_PACKAGES+=("ufw")
    elif [[ "$description" =~ ^Installing\  ]]; then
      local pkg
      pkg=$(echo "$description" | awk '{print $2}')
      INSTALLED_PACKAGES+=("$pkg")
    elif [[ "$description" == "Removing figlet" ]]; then
      REMOVED_PACKAGES+=("figlet")
    fi
  else
    log_error "$description"
  fi
}

# Enhanced package installation with better terminal formatting
install_packages_quietly() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local current=0
  
  if [ $total -eq 0 ]; then
    echo -e "${YELLOW}No packages to install${RESET}"
    return
  fi
  
  echo -e "${CYAN}Installing ${total} packages via Pacman...${RESET}"
  
  for pkg in "${pkgs[@]}"; do
    ((current++))
    if pacman -Q "$pkg" &>/dev/null; then
      print_progress "$current" "$total" "$pkg"
      print_status " [SKIP] Already installed" "$YELLOW"
      continue
    fi
    
    print_progress "$current" "$total" "$pkg"
    if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
      print_status " [OK]" "$GREEN"
      INSTALLED_PACKAGES+=("$pkg")
    else
      print_status " [FAIL]" "$RED"
      log_error "Failed to install $pkg"
    fi
  done
  
  echo -e "\n${GREEN}✓ Package installation completed (${current}/${total} packages processed)${RESET}\n"
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
  
  if [ "${#all_packages[@]}" -gt 0 ]; then
    install_packages_quietly "${all_packages[@]}"
  fi
}

print_summary() {
  echo -e "\n${CYAN}=== INSTALL SUMMARY ===${RESET}"
  [ "${#INSTALLED_PACKAGES[@]}" -gt 0 ] && echo -e "${GREEN}Installed: ${INSTALLED_PACKAGES[*]}${RESET}"
  [ "${#REMOVED_PACKAGES[@]}" -gt 0 ] && echo -e "${RED}Removed: ${REMOVED_PACKAGES[*]}${RESET}"
  [ "${#ERRORS[@]}" -gt 0 ] && echo -e "\n${RED}Errors: ${ERRORS[*]}${RESET}"
  echo -e "${CYAN}======================${RESET}"
}

prompt_reboot() {
  figlet_banner "Reboot System"
  echo -e "${YELLOW}Setup is complete. It's strongly recommended to reboot your system now."
  echo -e "If you encounter issues, review the install log: ${CYAN}$SCRIPT_DIR/install.log${RESET}\n"
  while true; do
    read -r -p "$(echo -e "${YELLOW}Reboot now? [Y/n]: ${RESET}")" reboot_ans
    reboot_ans=${reboot_ans,,}
    case "$reboot_ans" in
      ""|y|yes)
        echo -e "\n${CYAN}Rebooting...${RESET}\n"
        sudo reboot
        break
        ;;
      n|no)
        echo -e "\n${YELLOW}Reboot skipped. You can reboot manually at any time using \`sudo reboot\`.${RESET}\n"
        break
        ;;
      *)
        echo -e "\n${RED}Please answer Y (yes) or N (no).${RESET}\n"
        ;;
    esac
  done
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
  echo -e "${CYAN}[PERF] $step_name completed in ${elapsed}s${RESET}"
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

# Validate file system operations
validate_file_operation() {
  local operation="$1"
  local file="$2"
  local description="$3"
  
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