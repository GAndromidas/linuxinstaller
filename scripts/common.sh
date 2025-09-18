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

HELPER_UTILS=(base-devel bc bluez-utils cronie curl eza fastfetch figlet flatpak fzf git openssh pacman-contrib plymouth rsync ufw zoxide)  # Helper utilities to install

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
      INSTALL_MODE="default"
      gum style --foreground 51 "✓ Selected: Standard installation (intermediate users)"
      ;;
    "Minimal"*)
      INSTALL_MODE="minimal"
      gum style --foreground 46 "✓ Selected: Minimal installation (recommended for new users)"
      ;;
    "Custom"*)
      INSTALL_MODE="custom"
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
          INSTALL_MODE="default"
          echo -e "\n${BLUE}✓ Selected: Standard installation (intermediate users)${RESET}"
          break
          ;;
        2)
          INSTALL_MODE="minimal"
          echo -e "\n${GREEN}✓ Selected: Minimal installation (recommended for new users)${RESET}"
          break
          ;;
        3)
          INSTALL_MODE="custom"
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

# Unified package installation system with progress tracking
install_packages_quietly() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local current=0
  local failed_packages=()

  if [ $total -eq 0 ]; then
    if command -v gum >/dev/null 2>&1; then
      gum style --foreground 226 "No packages to install"
    else
      echo -e "${YELLOW}No packages to install${RESET}"
    fi
    return 0
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
        failed_packages+=("$pkg")
      fi
    done

    gum style --foreground 46 "✓ Package installation completed (${current}/${total} packages processed)"
    if [ ${#failed_packages[@]} -gt 0 ]; then
      gum style --foreground 226 "Failed packages: ${failed_packages[*]}"
    fi
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
        failed_packages+=("$pkg")
      fi
    done

    echo -e "\n${GREEN}✓ Package installation completed (${current}/${total} packages processed)${RESET}"
    if [ ${#failed_packages[@]} -gt 0 ]; then
      echo -e "${YELLOW}Failed packages: ${failed_packages[*]}${RESET}"
    fi
    echo ""
  fi

  # Return 1 if any packages failed, 0 otherwise
  [ ${#failed_packages[@]} -eq 0 ]
}

# Standalone paru installation function that can be called from other scripts
ensure_paru_installed() {
  # Check if paru is already installed and working
  if command -v paru &>/dev/null && paru --version >/dev/null 2>&1; then
    return 0
  fi

  log_warning "paru not found or not working - installing it now..."

  # Check dependencies
  local deps_needed=()
  if ! pacman -Q base-devel &>/dev/null; then
    deps_needed+=(base-devel)
  fi
  if ! command -v git &>/dev/null; then
    deps_needed+=(git)
  fi

  # Install dependencies if needed
  if [[ ${#deps_needed[@]} -gt 0 ]]; then
    log_info "Installing paru dependencies: ${deps_needed[*]}"
    sudo pacman -S --noconfirm --needed "${deps_needed[@]}" || {
      log_error "Failed to install paru dependencies"
      return 1
    }
  fi

  # Store original directory and create temp directory
  local original_dir="$PWD"
  local temp_dir
  temp_dir=$(mktemp -d -t paru-install-XXXXXX) || {
    log_error "Failed to create temporary directory"
    return 1
  }

  # Cleanup function
  cleanup_paru_install() {
    cd "$original_dir" 2>/dev/null
    rm -rf "$temp_dir" 2>/dev/null
  }
  trap cleanup_paru_install EXIT

  cd "$temp_dir" || { log_error "Failed to enter temp directory"; return 1; }

  # Clone and build paru from source
  log_info "Downloading paru source..."
  if ! git clone --depth 1 https://aur.archlinux.org/paru.git . 2>/dev/null; then
    log_error "Failed to download paru source"
    return 1
  fi

  log_info "Installing paru from source..."
  if ! makepkg -si --noconfirm --needed 2>/dev/null; then
    log_error "Failed to install paru from source"
    return 1
  fi

  # Clean package cache to save space after installation
  if command -v paru &>/dev/null; then
    paru -Scc --noconfirm || true
  fi

  # Verify installation
  if command -v paru &>/dev/null && paru --version >/dev/null 2>&1; then
    log_success "paru installed from source and cleaned up successfully"
  else
    log_error "paru installation verification failed"
    return 1
  fi

  # Cleanup
  cleanup_paru_install
  trap - EXIT

  return 0
}

# AUR package installation with paru
install_aur_quietly() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local current=0
  local failed_packages=()

  if [ $total -eq 0 ]; then
    if command -v gum >/dev/null 2>&1; then
      gum style --foreground 226 "No AUR packages to install"
    else
      echo -e "${YELLOW}No AUR packages to install${RESET}"
    fi
    return 0
  fi

  if ! command -v paru >/dev/null 2>&1; then
    log_error "paru is not installed. Cannot install AUR packages."
    return 1
  fi

  if command -v gum >/dev/null 2>&1; then
    gum style --foreground 51 "Installing ${total} AUR packages via paru..."

    for pkg in "${pkgs[@]}"; do
      ((current++))
      if paru -Q "$pkg" &>/dev/null; then
        gum style --foreground 226 "[$current/$total] $pkg [SKIP] Already installed"
        continue
      fi

      gum style --foreground 15 "[$current/$total] Installing $pkg..."
      if paru -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
        gum style --foreground 46 "[$current/$total] $pkg [OK]"
        INSTALLED_PACKAGES+=("$pkg")
      else
        gum style --foreground 196 "[$current/$total] $pkg [FAIL]"
        log_error "Failed to install AUR package $pkg"
        failed_packages+=("$pkg")
      fi
    done

    gum style --foreground 46 "✓ AUR package installation completed (${current}/${total} packages processed)"
    if [ ${#failed_packages[@]} -gt 0 ]; then
      gum style --foreground 226 "Failed AUR packages: ${failed_packages[*]}"
    fi
  else
    echo -e "${CYAN}Installing ${total} AUR packages via paru...${RESET}"

    for pkg in "${pkgs[@]}"; do
      ((current++))
      if paru -Q "$pkg" &>/dev/null; then
        print_progress "$current" "$total" "$pkg"
        print_status " [SKIP] Already installed" "$YELLOW"
        continue
      fi

      print_progress "$current" "$total" "$pkg"
      if paru -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
        print_status " [OK]" "$GREEN"
        INSTALLED_PACKAGES+=("$pkg")
      else
        print_status " [FAIL]" "$RED"
        log_error "Failed to install AUR package $pkg"
        failed_packages+=("$pkg")
      fi
    done

    echo -e "\n${GREEN}✓ AUR package installation completed (${current}/${total} packages processed)${RESET}"
    if [ ${#failed_packages[@]} -gt 0 ]; then
      echo -e "${YELLOW}Failed AUR packages: ${failed_packages[*]}${RESET}"
    fi
    echo ""
  fi

  # Return 1 if any packages failed, 0 otherwise
  [ ${#failed_packages[@]} -eq 0 ]
}

# Flatpak package installation
install_flatpak_quietly() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local current=0
  local failed_packages=()

  if [ $total -eq 0 ]; then
    if command -v gum >/dev/null 2>&1; then
      gum style --foreground 226 "No Flatpak packages to install"
    else
      echo -e "${YELLOW}No Flatpak packages to install${RESET}"
    fi
    return 0
  fi

  if ! command -v flatpak >/dev/null 2>&1; then
    log_error "flatpak is not installed. Cannot install Flatpak packages."
    return 1
  fi

  if command -v gum >/dev/null 2>&1; then
    gum style --foreground 51 "Installing ${total} Flatpak packages..."

    for pkg in "${pkgs[@]}"; do
      ((current++))
      if flatpak list | grep -q "$pkg"; then
        gum style --foreground 226 "[$current/$total] $pkg [SKIP] Already installed"
        continue
      fi

      gum style --foreground 15 "[$current/$total] Installing $pkg..."
      if flatpak install -y flathub "$pkg" >/dev/null 2>&1; then
        gum style --foreground 46 "[$current/$total] $pkg [OK]"
        INSTALLED_PACKAGES+=("$pkg")
      else
        gum style --foreground 196 "[$current/$total] $pkg [FAIL]"
        log_error "Failed to install Flatpak package $pkg"
        failed_packages+=("$pkg")
      fi
    done

    gum style --foreground 46 "✓ Flatpak package installation completed (${current}/${total} packages processed)"
    if [ ${#failed_packages[@]} -gt 0 ]; then
      gum style --foreground 226 "Failed Flatpak packages: ${failed_packages[*]}"
    fi
  else
    echo -e "${CYAN}Installing ${total} Flatpak packages...${RESET}"

    for pkg in "${pkgs[@]}"; do
      ((current++))
      if flatpak list | grep -q "$pkg"; then
        print_progress "$current" "$total" "$pkg"
        print_status " [SKIP] Already installed" "$YELLOW"
        continue
      fi

      print_progress "$current" "$total" "$pkg"
      if flatpak install -y flathub "$pkg" >/dev/null 2>&1; then
        print_status " [OK]" "$GREEN"
        INSTALLED_PACKAGES+=("$pkg")
      else
        print_status " [FAIL]" "$RED"
        log_error "Failed to install Flatpak package $pkg"
        failed_packages+=("$pkg")
      fi
    done

    echo -e "\n${GREEN}✓ Flatpak package installation completed (${current}/${total} packages processed)${RESET}"
    if [ ${#failed_packages[@]} -gt 0 ]; then
      echo -e "${YELLOW}Failed Flatpak packages: ${failed_packages[*]}${RESET}"
    fi
    echo ""
  fi

  # Return 1 if any packages failed, 0 otherwise
  [ ${#failed_packages[@]} -eq 0 ]
}

# Kernel detection utility function
get_installed_kernel_types() {
  local kernel_types=()
  pacman -Q linux &>/dev/null && kernel_types+=("linux")
  pacman -Q linux-lts &>/dev/null && kernel_types+=("linux-lts")
  pacman -Q linux-zen &>/dev/null && kernel_types+=("linux-zen")
  pacman -Q linux-hardened &>/dev/null && kernel_types+=("linux-hardened")
  echo "${kernel_types[@]}"
}

# Service management utilities
enable_system_services() {
  local services=("$@")
  local total=${#services[@]}
  local current=0
  local failed_services=()

  if [ $total -eq 0 ]; then
    log_warning "No services to enable"
    return 0
  fi

  step "Enabling ${total} system services"
  for service in "${services[@]}"; do
    ((current++))
    print_progress "$current" "$total" "$service"

    if systemctl is-enabled "$service" &>/dev/null; then
      print_status " [SKIP] Already enabled" "$YELLOW"
    else
      if sudo systemctl enable --now "$service" >/dev/null 2>&1; then
        print_status " [OK]" "$GREEN"
      else
        print_status " [FAIL]" "$RED"
        log_error "Failed to enable service $service"
        failed_services+=("$service")
      fi
    fi
  done

  echo -e "\n${GREEN}✓ Service management completed (${current}/${total} services processed)${RESET}"
  if [ ${#failed_services[@]} -gt 0 ]; then
    echo -e "${YELLOW}Failed services: ${failed_services[*]}${RESET}"
  fi
  echo ""

  # Return 1 if any services failed, 0 otherwise
  [ ${#failed_services[@]} -eq 0 ]
}

# System optimization utilities
optimize_system_config() {
  local config_file="$1"
  local setting="$2"
  local value="$3"
  local section="${4:-}"

  if [ ! -f "$config_file" ]; then
    log_error "Configuration file $config_file not found"
    return 1
  fi

  # Handle different config file formats
  if [[ "$config_file" == *"pacman.conf" ]]; then
    # Pacman config handling
    if grep -q "^#$setting" "$config_file"; then
      # Uncomment and set value
      sudo sed -i "s/^#$setting.*/$setting = $value/" "$config_file"
      log_success "Uncommented and set $setting = $value in $config_file"
    elif grep -q "^$setting" "$config_file"; then
      # Update existing value
      sudo sed -i "s/^$setting.*/$setting = $value/" "$config_file"
      log_success "Updated $setting = $value in $config_file"
    else
      # Add new setting
      if [ -n "$section" ]; then
        sudo sed -i "/^\[$section\]/a $setting = $value" "$config_file"
      else
        echo "$setting = $value" | sudo tee -a "$config_file" >/dev/null
      fi
      log_success "Added $setting = $value to $config_file"
    fi
  else
    # Generic config handling
    if grep -q "^$setting" "$config_file"; then
      sudo sed -i "s/^$setting.*/$setting=$value/" "$config_file"
      log_success "Updated $setting=$value in $config_file"
    else
      echo "$setting=$value" | sudo tee -a "$config_file" >/dev/null
      log_success "Added $setting=$value to $config_file"
    fi
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

  # Show ZRAM profile information
  if [ -f "/tmp/archinstaller_gaming" ] || command -v steam >/dev/null 2>&1 || command -v lutris >/dev/null 2>&1; then
    echo -e "${GREEN}ZRAM Profile: Gaming (performance-focused tuning)${RESET}"
  else
    echo -e "${GREEN}ZRAM Profile: Regular (balanced for desktop use)${RESET}"
  fi

  [ "${#ERRORS[@]}" -gt 0 ] && echo -e "\n${RED}Errors: ${ERRORS[*]}${RESET}"
  echo -e "${CYAN}======================${RESET}"
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
  if command -v paru >/dev/null; then
    paru -Sy --noconfirm >/dev/null 2>&1
  else
    log_warning "paru not available for AUR package list update"
  fi
}

# Optimized system update
fast_system_update() {
  step "Performing optimized system update"
  sudo pacman -Syu --noconfirm --overwrite="*"
  if command -v paru >/dev/null; then
    paru -Syu --noconfirm
  else
    log_warning "paru not available for AUR update"
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
