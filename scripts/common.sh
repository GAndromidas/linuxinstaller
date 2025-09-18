#!/bin/bash

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
ERRORS=()                # Collects error messages for summary
CURRENT_STEP=1           # Tracks current step for progress display
INSTALLED_PACKAGES=()    # Tracks installed packages
REMOVED_PACKAGES=()      # Tracks removed packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"  # Script directory
CONFIGS_DIR="$SCRIPT_DIR/configs"                           # Config files directory
SCRIPTS_DIR="$SCRIPT_DIR/scripts"                           # Custom scripts directory

# Helper utilities to install - conditionally includes ZSH packages
get_helper_utils() {
  local utils=(base-devel bc bluez-utils cronie curl eza fastfetch figlet flatpak fzf git openssh pacman-contrib plymouth rsync ufw)

  # Add ZSH-related utilities only if not keeping Fish on CachyOS
  if [[ "${CACHYOS_SHELL_CHOICE:-}" != "fish" ]]; then
    utils+=(zoxide)
  fi

  echo "${utils[@]}"
}

HELPER_UTILS=($(get_helper_utils))

# : "${INSTALL_MODE:=default}"

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
  # Check if gum is available, fallback to traditional menu if not
  if command -v gum >/dev/null 2>&1; then
    show_gum_menu
  else
    show_traditional_menu
  fi
}

show_gum_menu() {
  gum style --border double --margin "1 2" --padding "2 4" --foreground 51 --border-foreground 51 "🚀 ARCH INSTALLER"

  gum style --margin "1 0" --foreground 226 "This script will transform your fresh Arch Linux installation into a"
  gum style --margin "0 0 1 0" --foreground 226 "fully configured, optimized system with all the tools you need!"

  local choice=$(gum choose --cursor "→ " --selected.foreground 51 --cursor.foreground 51 \
    "Standard - Complete setup with all packages (intermediate users)" \
    "Minimal - Essential tools only (recommended for new users)" \
    "Custom - Interactive selection (choose what to install) (advanced users)" \
    "Exit - Cancel installation")

  case "$choice" in
    "Standard"*)
      export INSTALL_MODE="default"
      gum style --foreground 51 "✓ Selected: Standard installation (intermediate users)"
      ;;
    "Minimal"*)
      export INSTALL_MODE="minimal"
      gum style --foreground 46 "✓ Selected: Minimal installation (recommended for new users)"
      ;;
    "Custom"*)
      export INSTALL_MODE="custom"
      gum style --foreground 226 "✓ Selected: Custom installation (advanced users)"
      ;;
    "Exit"*)
      gum style --foreground 226 "Installation cancelled. You can run this script again anytime."
      exit 0
      ;;
  esac
}

show_traditional_menu() {
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
  echo -e "${CYAN}🚀 WELCOME TO ARCH INSTALLER${RESET}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
  echo -e "${YELLOW}This script will transform your fresh Arch Linux installation into a${RESET}"
  echo -e "${YELLOW}fully configured, optimized system with all the tools you need!${RESET}"
  echo ""
  echo -e "${CYAN}🎯 Choose your installation mode:${RESET}"
  echo ""
  printf "${BLUE}  1) Standard${RESET}%-12s - Complete setup with all packages (intermediate users)\n" ""
  printf "${GREEN}  2) Minimal${RESET}%-13s - Essential tools only (recommended for new users)\n" ""
  printf "${YELLOW}  3) Custom${RESET}%-14s - Interactive selection (choose what to install) (advanced users)\n" ""
  printf "${RED}  4) Exit${RESET}%-16s - Cancel installation\n" ""
  echo ""

  while true; do
    read -r -p "$(echo -e "${CYAN}Enter your choice [1-4]: ${RESET}")" menu_choice
          case "$menu_choice" in
          1)
            export INSTALL_MODE="default"
            echo -e "\n${BLUE}✓ Selected: Standard installation (intermediate users)${RESET}"
            break
            ;;
          2)
            export INSTALL_MODE="minimal"
            echo -e "\n${GREEN}✓ Selected: Minimal installation (recommended for new users)${RESET}"
            break
            ;;
          3)
            export INSTALL_MODE="custom"
            echo -e "\n${YELLOW}✓ Selected: Custom installation (advanced users)${RESET}"
            break
            ;;
      4)
        echo -e "\n${YELLOW}Installation cancelled. You can run this script again anytime.${RESET}"
        exit 0
        ;;
      *)
        echo -e "\n${RED}❌ Invalid choice! Please enter 1, 2, 3, or 4.${RESET}\n"
        ;;
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
log_info()    { echo -e "${CYAN}ℹ $1${RESET}"; }

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
    elif [[ "$description" == "Removing figlet and gum" ]]; then
      REMOVED_PACKAGES+=("figlet" "gum")
    fi
  else
    log_error "$description"
  fi
}

# Enhanced package installation with gum progress bar and better formatting
install_packages_quietly() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local current=0

  if [ $total -eq 0 ]; then
    if command -v gum >/dev/null 2>&1; then
      gum style --foreground 226 "No packages to install"
    else
      echo -e "${YELLOW}No packages to install${RESET}"
    fi
    return
  fi

  if command -v gum >/dev/null 2>&1; then
    gum style --foreground 51 "Installing ${total} packages via Pacman..."

    for pkg in "${pkgs[@]}"; do
      ((current++))
      if pacman -Q "$pkg" &>/dev/null; then
        gum style --foreground 226 "[$current/$total] $pkg [SKIP] Already installed"
        continue
      fi

      gum style --foreground 15 "[$current/$total] Installing $pkg..."
      if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
        gum style --foreground 46 "[$current/$total] $pkg [OK]"
        INSTALLED_PACKAGES+=("$pkg")
      else
        gum style --foreground 196 "[$current/$total] $pkg [FAIL]"
        log_error "Failed to install $pkg"
      fi
    done

    gum style --foreground 46 "✓ Package installation completed (${current}/${total} packages processed)"
  else
    # Fallback to traditional output
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
  fi
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
        # Skip ZSH packages if keeping Fish on CachyOS
        if [[ "${CACHYOS_SHELL_CHOICE:-}" != "fish" ]]; then
          all_packages+=(zsh zsh-autosuggestions zsh-syntax-highlighting)
        fi
        ;;
      "starship")
        # Skip Starship if keeping Fish on CachyOS
        if [[ "${CACHYOS_SHELL_CHOICE:-}" != "fish" ]]; then
          all_packages+=(starship)
        fi
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

# Get locale-aware date formatting
get_locale_date() {
  local locale_country=""
  local date_format=""

  # Try to detect locale/country from various sources
  if [[ -n "$LANG" ]]; then
    locale_country=$(echo "$LANG" | cut -d'_' -f2 | cut -d'.' -f1)
  elif [[ -n "$LC_TIME" ]]; then
    locale_country=$(echo "$LC_TIME" | cut -d'_' -f2 | cut -d'.' -f1)
  fi

  # Format date based on detected country/locale
  case "$locale_country" in
    "GR"|"EL")  # Greece
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "US")       # United States
      date_format="%m/%d/%Y %I:%M:%S %p"
      ;;
    "GB"|"UK")  # United Kingdom
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "DE")       # Germany
      date_format="%d.%m.%Y %H:%M:%S"
      ;;
    "FR")       # France
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "IT")       # Italy
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "ES")       # Spain
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "PT")       # Portugal
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "NL")       # Netherlands
      date_format="%d-%m-%Y %H:%M:%S"
      ;;
    "BE")       # Belgium
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "CH")       # Switzerland
      date_format="%d.%m.%Y %H:%M:%S"
      ;;
    "AT")       # Austria
      date_format="%d.%m.%Y %H:%M:%S"
      ;;
    "SE")       # Sweden
      date_format="%Y-%m-%d %H:%M:%S"
      ;;
    "NO")       # Norway
      date_format="%d.%m.%Y %H:%M:%S"
      ;;
    "DK")       # Denmark
      date_format="%d-%m-%Y %H:%M:%S"
      ;;
    "FI")       # Finland
      date_format="%d.%m.%Y %H:%M:%S"
      ;;
    "PL")       # Poland
      date_format="%d.%m.%Y %H:%M:%S"
      ;;
    "CZ")       # Czech Republic
      date_format="%d.%m.%Y %H:%M:%S"
      ;;
    "RU")       # Russia
      date_format="%d.%m.%Y %H:%M:%S"
      ;;
    "JP")       # Japan
      date_format="%Y/%m/%d %H:%M:%S"
      ;;
    "KR")       # South Korea
      date_format="%Y.%m.%d %H:%M:%S"
      ;;
    "CN")       # China
      date_format="%Y-%m-%d %H:%M:%S"
      ;;
    "IN")       # India
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "AU")       # Australia
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "NZ")       # New Zealand
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "CA")       # Canada
      date_format="%Y-%m-%d %H:%M:%S"
      ;;
    "BR")       # Brazil
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "MX")       # Mexico
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "AR")       # Argentina
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "TR")       # Turkey
      date_format="%d.%m.%Y %H:%M:%S"
      ;;
    "IL")       # Israel
      date_format="%d/%m/%Y %H:%M:%S"
      ;;
    "ZA")       # South Africa
      date_format="%Y/%m/%d %H:%M:%S"
      ;;
    *)          # Default: use system locale or ISO format
      if locale -k LC_TIME >/dev/null 2>&1; then
        # Use system's locale-specific date format
        date "+%x %X" 2>/dev/null && return
      fi
      # Fallback to ISO format
      date_format="%Y-%m-%d %H:%M:%S (ISO)"
      ;;
  esac

  date "+$date_format"
}

print_summary() {
  echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}║                    INSTALLATION SUMMARY                     ║${RESET}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"

  # System Information
  echo -e "\n${YELLOW}📋 System Information:${RESET}"
  echo -e "   OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")"
  echo -e "   Kernel: $(uname -r)"
  echo -e "   Architecture: $(uname -m)"
  echo -e "   Desktop: ${XDG_CURRENT_DESKTOP:-Unknown}"
  echo -e "   Shell: $SHELL"
  echo -e "   Locale: ${LANG:-Not set} ($(echo "$LANG" | cut -d'_' -f2 | cut -d'.' -f1 2>/dev/null || echo "Unknown country"))"

  # CachyOS Detection
  if [[ -f /etc/cachy-release ]] || [[ -f /usr/share/cachy-browser/cachy-browser ]] || [[ $(uname -r) =~ cachyos ]]; then
    echo -e "   Distribution: ${GREEN}CachyOS Detected${RESET}"
  else
    echo -e "   Distribution: ${CYAN}Standard Arch Linux${RESET}"
  fi

  # Installation Mode
  echo -e "   Install Mode: ${INSTALL_MODE:-default}"
  echo -e "   Date: $(get_locale_date)"

  # Package Summary
  if [ "${#INSTALLED_PACKAGES[@]}" -gt 0 ]; then
    echo -e "\n${GREEN}📦 Successfully Installed (${#INSTALLED_PACKAGES[@]} packages):${RESET}"
    printf "   %s\n" "${INSTALLED_PACKAGES[@]}" | sort | column -c 80 | sed 's/^/   /'
  fi

  if [ "${#REMOVED_PACKAGES[@]}" -gt 0 ]; then
    echo -e "\n${RED}🗑️  Removed (${#REMOVED_PACKAGES[@]} packages):${RESET}"
    printf "   %s\n" "${REMOVED_PACKAGES[@]}" | sort
  fi

  # AUR Helper Status
  echo -e "\n${YELLOW}🔧 AUR Helper Status:${RESET}"
  if command -v yay >/dev/null 2>&1; then
    echo -e "   ${GREEN}✓ yay installed and working${RESET}"
  elif command -v paru >/dev/null 2>&1; then
    echo -e "   ${GREEN}✓ paru detected${RESET}"
  else
    echo -e "   ${RED}✗ No AUR helper found${RESET}"
  fi

  # Critical Dependencies Check
  echo -e "\n${YELLOW}🔍 Critical Dependencies:${RESET}"
  local critical_deps=("base-devel" "git" "sudo" "systemd")
  for dep in "${critical_deps[@]}"; do
    if pacman -Q "$dep" >/dev/null 2>&1; then
      echo -e "   ${GREEN}✓ $dep${RESET}"
    else
      echo -e "   ${RED}✗ $dep (MISSING!)${RESET}"
    fi
  done

  # Service Status
  echo -e "\n${YELLOW}⚙️  Key Services:${RESET}"
  local services=("NetworkManager" "bluetooth" "ufw" "fail2ban")
  for service in "${services[@]}"; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
      echo -e "   ${GREEN}✓ $service enabled${RESET}"
    elif systemctl list-unit-files | grep -q "$service"; then
      echo -e "   ${YELLOW}! $service disabled${RESET}"
    else
      echo -e "   ${CYAN}- $service not installed${RESET}"
    fi
  done

  # Errors and Warnings
  if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo -e "\n${RED}❌ ERRORS ENCOUNTERED (${#ERRORS[@]}):${RESET}"
    echo -e "${RED}╭─────────────────────────────────────────────────────────────╮${RESET}"
    for i in "${!ERRORS[@]}"; do
      echo -e "${RED}│ $((i+1)). ${ERRORS[i]}${RESET}"
    done
    echo -e "${RED}╰─────────────────────────────────────────────────────────────╯${RESET}"

    echo -e "\n${YELLOW}🔍 Diagnostic Information for Troubleshooting:${RESET}"

    # Log file locations
    echo -e "   ${CYAN}Log files to check:${RESET}"
    echo -e "     • /var/log/pacman.log (package installation logs)"
    echo -e "     • journalctl -xe (system logs)"
    echo -e "     • ~/.cache/yay/ (AUR build logs, if applicable)"

    # Common fixes
    echo -e "\n   ${CYAN}Common fixes to try:${RESET}"
    echo -e "     • sudo pacman -Syu (update system)"
    echo -e "     • sudo pacman -S --needed base-devel git (install build tools)"
    echo -e "     • systemctl --failed (check failed services)"
    echo -e "     • ping archlinux.org (test internet connection)"

    # System state for debugging
    echo -e "\n   ${CYAN}System state snapshot:${RESET}"
    echo -e "     • Available disk space: $(df -h / | awk 'NR==2 {print $4}' || echo "Unknown")"
    echo -e "     • Memory usage: $(free -h | awk 'NR==2 {print $3"/"$2}' || echo "Unknown")"
    echo -e "     • Network: $(ping -c 1 archlinux.org >/dev/null 2>&1 && echo "Connected" || echo "Disconnected")"
    echo -e "     • Pacman lock: $([ -f /var/lib/pacman/db.lck ] && echo "LOCKED" || echo "Free")"

    # Environment info
    echo -e "\n   ${CYAN}Environment variables:${RESET}"
    echo -e "     • HOME: $HOME"
    echo -e "     • USER: $USER"
    echo -e "     • PATH length: ${#PATH} chars"
    echo -e "     • LANG: ${LANG:-Not set}"

    echo -e "\n${RED}⚠️  IMPORTANT: When reporting issues, include the above diagnostic information!${RESET}"

  else
    echo -e "\n${GREEN}✅ INSTALLATION COMPLETED SUCCESSFULLY!${RESET}"
    echo -e "${GREEN}   All steps completed without errors.${RESET}"
  fi

  echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}║                     END OF SUMMARY                          ║${RESET}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
}

prompt_reboot() {
  figlet_banner "Reboot System"
  echo -e "${YELLOW}🎉 Congratulations! Your Arch Linux system is now fully configured!${RESET}"
  echo ""
  echo -e "${CYAN}📋 What happens after reboot:${RESET}"
  echo -e "  • 🎨 Beautiful boot screen will appear"
  echo -e "  • 🖥️  Your desktop environment will be ready to use"
  echo -e "  • 🛡️  Security features will be active"
  echo -e "  • ⚡ Performance optimizations will be enabled"
  echo -e "  • 🎮 Gaming tools will be available (if installed)"
  echo ""
  echo -e "${YELLOW}💡 It's strongly recommended to reboot now to apply all changes.\n"
  while true; do
    read -r -p "$(echo -e "${YELLOW}Reboot now? [Y/n]: ${RESET}")" reboot_ans
    reboot_ans=${reboot_ans,,}
    case "$reboot_ans" in
      ""|y|yes)
        echo -e "\n${CYAN}🔄 Rebooting your system...${RESET}"
        echo -e "${YELLOW}   Thank you for using Arch Installer! 🚀${RESET}\n"
        # Silently uninstall figlet and gum before reboot
        sudo pacman -R figlet gum --noconfirm >/dev/null 2>&1 || true
        sudo reboot
        break
        ;;
      n|no)
        echo -e "\n${YELLOW}⏸️  Reboot skipped. You can reboot manually at any time using:${RESET}"
        echo -e "${CYAN}   sudo reboot${RESET}"
        echo -e "${YELLOW}   Or simply restart your computer.${RESET}\n"
        break
        ;;
      *)
        echo -e "\n${RED}❌ Please answer Y (yes) or N (no).${RESET}\n"
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

# Get installed kernel types
get_installed_kernel_types() {
  local kernel_types=()
  pacman -Q linux &>/dev/null && kernel_types+=("linux")
  pacman -Q linux-lts &>/dev/null && kernel_types+=("linux-lts")
  pacman -Q linux-zen &>/dev/null && kernel_types+=("linux-zen")
  pacman -Q linux-hardened &>/dev/null && kernel_types+=("linux-hardened")
  echo "${kernel_types[@]}"
}

# Check if running as root user
check_root_user() {
  if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}❌ Error: This script should NOT be run as root!${RESET}"
    echo -e "${YELLOW}   Please run as a regular user with sudo privileges.${RESET}"
    echo -e "${YELLOW}   Example: ./install.sh (not sudo ./install.sh)${RESET}"
    exit 1
  fi
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
