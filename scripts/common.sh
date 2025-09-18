#!/bin/bash

# Color variables for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
WHITE='\033[1;37m'
RESET='\033[0m'

# Terminal formatting helpers
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)

# Global arrays and variables
ERRORS=()                # Collects error messages for summary
CURRENT_STEP=1           # Tracks current step for progress display
INSTALLED_PACKAGES=()    # Tracks installed packages
REMOVED_PACKAGES=()      # Tracks removed packages

# Enhanced parallel installation variables
PARALLEL_LIMIT=10        # Maximum parallel installations
BATCH_SIZE=5             # Packages per batch
PARALLEL_JOBS=()         # Track parallel jobs
FAILED_PACKAGES=()       # Track failed installations
START_TIME=$(date +%s)   # Track total installation time

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
  if command -v gum >/dev/null 2>&1; then
    gum style --margin "1 0" --foreground 51 "→ $1"
  else
    echo -e "\n${CYAN}→ $1${RESET}"
  fi
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

# Clean package installation system with minimal output
install_packages_quietly() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local installed_count=0
  local skipped_count=0
  local failed_packages=()
  local packages_to_install=()

  if [ $total -eq 0 ]; then
    if command -v gum >/dev/null 2>&1; then
      gum style --foreground 226 "No packages to install"
    else
      echo -e "${YELLOW}No packages to install${RESET}"
    fi
    return 0
  fi

  # Filter out already installed packages
  for pkg in "${pkgs[@]}"; do
    if pacman -Q "$pkg" &>/dev/null; then
      ((skipped_count++))
    else
      packages_to_install+=("$pkg")
    fi
  done

  if command -v gum >/dev/null 2>&1; then
    if [ ${#packages_to_install[@]} -gt 0 ]; then
      gum style --foreground 51 "📦 Installing ${#packages_to_install[@]} packages via Pacman..."

      if sudo pacman -S --noconfirm --needed "${packages_to_install[@]}" >/dev/null 2>&1; then
        installed_count=${#packages_to_install[@]}
        INSTALLED_PACKAGES+=("${packages_to_install[@]}")
        gum style --foreground 46 "✓ Successfully installed ${installed_count} packages"
      else
        # If batch install fails, try one by one to identify failures
        for pkg in "${packages_to_install[@]}"; do
          if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
            ((installed_count++))
            INSTALLED_PACKAGES+=("$pkg")
          else
            failed_packages+=("$pkg")
          fi
        done
        gum style --foreground 196 "⚠️  Some packages failed to install"
      fi
    fi

    if [ $skipped_count -gt 0 ]; then
      gum style --foreground 226 "⏭️  Skipped ${skipped_count} already installed packages"
    fi

    if [ ${#failed_packages[@]} -gt 0 ]; then
      gum style --foreground 196 "❌ Failed: ${failed_packages[*]}"
    fi
  else
    # Fallback to traditional output
    if [ ${#packages_to_install[@]} -gt 0 ]; then
      echo -e "${CYAN}📦 Installing ${#packages_to_install[@]} packages via Pacman...${RESET}"

      if sudo pacman -S --noconfirm --needed "${packages_to_install[@]}" >/dev/null 2>&1; then
        installed_count=${#packages_to_install[@]}
        INSTALLED_PACKAGES+=("${packages_to_install[@]}")
        echo -e "${GREEN}✓ Successfully installed ${installed_count} packages${RESET}"
      else
        # If batch install fails, try one by one to identify failures
        for pkg in "${packages_to_install[@]}"; do
          if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
            ((installed_count++))
            INSTALLED_PACKAGES+=("$pkg")
          else
            failed_packages+=("$pkg")
          fi
        done
        echo -e "${RED}⚠️  Some packages failed to install${RESET}"
      fi
    fi

    if [ $skipped_count -gt 0 ]; then
      echo -e "${YELLOW}⏭️  Skipped ${skipped_count} already installed packages${RESET}"
    fi

    if [ ${#failed_packages[@]} -gt 0 ]; then
      echo -e "${RED}❌ Failed: ${failed_packages[*]}${RESET}"
    fi
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

# Clean AUR package installation with minimal output
install_aur_packages_quietly() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local installed_count=0
  local skipped_count=0
  local failed_packages=()
  local packages_to_install=()

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

  # Filter out already installed packages
  for pkg in "${pkgs[@]}"; do
    if paru -Q "$pkg" &>/dev/null; then
      ((skipped_count++))
    else
      packages_to_install+=("$pkg")
    fi
  done

  if command -v gum >/dev/null 2>&1; then
    if [ ${#packages_to_install[@]} -gt 0 ]; then
      gum style --foreground 51 "🔧 Installing ${#packages_to_install[@]} AUR packages via paru..."

      if paru -S --noconfirm --needed "${packages_to_install[@]}" >/dev/null 2>&1; then
        installed_count=${#packages_to_install[@]}
        INSTALLED_PACKAGES+=("${packages_to_install[@]}")
        gum style --foreground 46 "✓ Successfully installed ${installed_count} AUR packages"
      else
        # If batch install fails, try one by one to identify failures
        for pkg in "${packages_to_install[@]}"; do
          if paru -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
            ((installed_count++))
            INSTALLED_PACKAGES+=("$pkg")
          else
            failed_packages+=("$pkg")
          fi
        done
        gum style --foreground 196 "⚠️  Some AUR packages failed to install"
      fi
    fi

    if [ $skipped_count -gt 0 ]; then
      gum style --foreground 226 "⏭️  Skipped ${skipped_count} already installed AUR packages"
    fi

    if [ ${#failed_packages[@]} -gt 0 ]; then
      gum style --foreground 196 "❌ Failed AUR packages: ${failed_packages[*]}"
    fi
  else
    # Fallback to traditional output
    if [ ${#packages_to_install[@]} -gt 0 ]; then
      echo -e "${CYAN}🔧 Installing ${#packages_to_install[@]} AUR packages via paru...${RESET}"

      if paru -S --noconfirm --needed "${packages_to_install[@]}" >/dev/null 2>&1; then
        installed_count=${#packages_to_install[@]}
        INSTALLED_PACKAGES+=("${packages_to_install[@]}")
        echo -e "${GREEN}✓ Successfully installed ${installed_count} AUR packages${RESET}"
      else
        # If batch install fails, try one by one to identify failures
        for pkg in "${packages_to_install[@]}"; do
          if paru -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
            ((installed_count++))
            INSTALLED_PACKAGES+=("$pkg")
          else
            failed_packages+=("$pkg")
          fi
        done
        echo -e "${RED}⚠️  Some AUR packages failed to install${RESET}"
      fi
    fi

    if [ $skipped_count -gt 0 ]; then
      echo -e "${YELLOW}⏭️  Skipped ${skipped_count} already installed AUR packages${RESET}"
    fi

    if [ ${#failed_packages[@]} -gt 0 ]; then
      echo -e "${RED}❌ Failed AUR packages: ${failed_packages[*]}${RESET}"
    fi
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

    # Check if service unit file exists first
    if ! systemctl list-unit-files "$service" --quiet 2>/dev/null | grep -q "$service"; then
      print_status " [SKIP] Service not available" "$YELLOW"
      continue
    fi

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

print_comprehensive_summary() {
  local total_installed=${#INSTALLED_PACKAGES[@]}
  local total_removed=${#REMOVED_PACKAGES[@]}
  local total_errors=${#ERRORS[@]}
  local install_time=$(date)
  local gaming_mode=false
  local windows_detected=false
  local bootloader_type="Unknown"

  # Detect gaming mode
  if [ -f "/tmp/archinstaller_gaming" ] || command -v steam >/dev/null 2>&1 || command -v lutris >/dev/null 2>&1; then
    gaming_mode=true
  fi

  # Detect Windows dual-boot
  if [ -d /boot/efi/EFI/Microsoft ] || [ -d /boot/EFI/Microsoft ] || lsblk -f | grep -qi ntfs; then
    windows_detected=true
  fi

  # Detect bootloader
  if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
    bootloader_type="systemd-boot"
  elif [ -d /boot/grub ] || [ -f /etc/default/grub ]; then
    bootloader_type="GRUB"
  fi

  if command -v gum >/dev/null 2>&1; then
    echo ""
    gum style --border double --margin "1 2" --padding "1 4" --foreground 51 --border-foreground 51 "🎉 ARCH LINUX INSTALLATION COMPLETED"

    # System Configuration Summary
    echo ""
    gum style --border normal --margin "1 0" --padding "0 2" --foreground 46 --border-foreground 46 "📋 System Configuration Summary"

    # ZRAM Configuration
    if [ "$gaming_mode" = true ]; then
      gum style --foreground 51 "⚡ ZRAM Profile: Gaming (performance-focused tuning)"
      gum style --foreground 15 "   • High swappiness (150-180) for maximum performance"
      gum style --foreground 15 "   • Aggressive memory management optimizations"
      gum style --foreground 15 "   • Optimized for gaming workloads and multitasking"
    else
      gum style --foreground 51 "⚡ ZRAM Profile: Regular (balanced for desktop use)"
      gum style --foreground 15 "   • Moderate swappiness (80-100) for stability"
      gum style --foreground 15 "   • Conservative memory management"
      gum style --foreground 15 "   • Optimized for general desktop workflows"
    fi

    # System Information
    local current_de="${XDG_CURRENT_DESKTOP:-Unknown}"
    local cpu_info=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//' | cut -c1-40)
    local ram_gb=$(get_ram_gb)
    local gpu_info=$(lspci | grep -E 'VGA|3D' | head -1 | cut -d: -f3 | sed 's/^ *//' | cut -c1-40)

    gum style --foreground 51 "💻 System Information:"
    gum style --foreground 15 "   • CPU: $cpu_info"
    gum style --foreground 15 "   • RAM: ${ram_gb}GB"
    gum style --foreground 15 "   • GPU: $gpu_info"
    gum style --foreground 15 "   • Desktop: $current_de"

    # Security Features
    echo ""
    gum style --foreground 51 "🛡️  Security Features Enabled:"
    gum style --foreground 15 "   • UFW Firewall configured and active"
    gum style --foreground 15 "   • Fail2ban protection for SSH (if SSH enabled)"
    gum style --foreground 15 "   • Secure sudo configuration with password feedback"

    # Boot Configuration
    echo ""
    gum style --foreground 51 "🥾 Boot Configuration:"
    gum style --foreground 15 "   • Bootloader: $bootloader_type"
    gum style --foreground 15 "   • Plymouth boot screen enabled"
    if [ "$windows_detected" = true ]; then
      gum style --foreground 15 "   • Windows dual-boot configured"
    fi

    # Performance Optimizations
    echo ""
    gum style --foreground 51 "🚀 Performance Optimizations:"
    gum style --foreground 15 "   • Parallel package downloads enabled"
    gum style --foreground 15 "   • CPU microcode installed and configured"
    gum style --foreground 15 "   • GPU drivers automatically detected and installed"

    # Package Statistics
    echo ""
    gum style --border normal --margin "1 0" --padding "0 2" --foreground 226 --border-foreground 226 "📊 Package Installation Statistics"
    gum style --foreground 46 "✅ Packages Successfully Installed: $total_installed"
    if [ $total_removed -gt 0 ]; then
      gum style --foreground 196 "🗑️  Packages Removed: $total_removed"
    fi
    if [ $total_errors -gt 0 ]; then
      gum style --foreground 196 "❌ Installation Errors: $total_errors"
      gum style --foreground 226 "   ℹ️  Don't worry! Most errors are non-critical."
    else
      gum style --foreground 46 "🎯 Zero Installation Errors - Perfect Setup!"
    fi

    # What's Next
    echo ""
    gum style --border normal --margin "1 0" --padding "0 2" --foreground 51 --border-foreground 51 "🔮 What's Next?"
    gum style --foreground 15 "1. Reboot your system to activate all changes"
    gum style --foreground 15 "2. Your enhanced ZSH shell will be ready on first login"
    gum style --foreground 15 "3. All applications are installed and configured"
    if [ "$gaming_mode" = true ]; then
      gum style --foreground 15 "4. Gaming tools (Steam, Lutris, etc.) are ready to use"
      gum style --foreground 15 "5. MangoHud overlay available for performance monitoring"
    fi
    gum style --foreground 15 "$([ "$gaming_mode" = true ] && echo "6" || echo "4"). Check 'fastfetch' command for beautiful system info"

    echo ""
    gum style --foreground 226 "💡 Useful Commands After Reboot:"
    gum style --foreground 15 "   • fastfetch - Beautiful system information"
    gum style --foreground 15 "   • update - Update all packages (Pacman + AUR + Flatpak)"
    gum style --foreground 15 "   • clean - Clean package cache and unused packages"
    if [ "$gaming_mode" = true ]; then
      gum style --foreground 15 "   • mangohud <game> - Launch games with performance overlay"
    fi

    echo ""
    gum style --foreground 46 "🔧 Important Notes:"
    gum style --foreground 15 "   • Your ZSH shell includes helpful aliases and autocompletion"
    gum style --foreground 15 "   • Firewall is active - configure ports as needed"
    if [ "$gaming_mode" = true ]; then
      gum style --foreground 15 "   • Steam and gaming tools are ready - just login and play!"
    fi
    gum style --foreground 15 "   • All kernel headers installed for DKMS compatibility"
    gum style --foreground 15 "   • ZRAM swap is active - check with 'zramctl'"

  else
    # Fallback for systems without gum
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}🎉 ARCH LINUX INSTALLATION COMPLETED SUCCESSFULLY! 🎉${RESET}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    echo -e "${CYAN}📋 SYSTEM CONFIGURATION SUMMARY:${RESET}"
    if [ "$gaming_mode" = true ]; then
      echo -e "${GREEN}⚡ ZRAM Profile: Gaming (performance-focused tuning)${RESET}"
      echo -e "   • High swappiness (150-180) for maximum performance"
      echo -e "   • Aggressive memory management optimizations"
    else
      echo -e "${GREEN}⚡ ZRAM Profile: Regular (balanced for desktop use)${RESET}"
      echo -e "   • Moderate swappiness (80-100) for stability"
      echo -e "   • Conservative memory management"
    fi

    local cpu_info=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//' | cut -c1-40)
    local ram_gb=$(get_ram_gb)
    local gpu_info=$(lspci | grep -E 'VGA|3D' | head -1 | cut -d: -f3 | sed 's/^ *//' | cut -c1-40)

    echo -e "${GREEN}💻 System: $cpu_info, ${ram_gb}GB RAM${RESET}"
    echo -e "${GREEN}🖥️  Desktop: ${XDG_CURRENT_DESKTOP:-Unknown}${RESET}"
    echo -e "${GREEN}🎮 Graphics: $gpu_info${RESET}"
    echo -e "${GREEN}🥾 Bootloader: $bootloader_type$([ "$windows_detected" = true ] && echo " + Windows dual-boot" || echo "")${RESET}"
    echo -e "${GREEN}🛡️  Security: UFW Firewall + Fail2ban + Secure sudo${RESET}"
    echo -e "${GREEN}🚀 Performance: Plymouth + GPU drivers + CPU microcode${RESET}"
    echo ""

    echo -e "${YELLOW}📊 PACKAGE STATISTICS:${RESET}"
    echo -e "${GREEN}✅ Installed: $total_installed packages${RESET}"
    [ $total_removed -gt 0 ] && echo -e "${RED}🗑️  Removed: $total_removed packages${RESET}"
    [ $total_errors -gt 0 ] && echo -e "${RED}❌ Errors: $total_errors (mostly non-critical)${RESET}" || echo -e "${GREEN}🎯 Zero errors - Perfect setup!${RESET}"
    echo ""

    echo -e "${CYAN}🔮 WHAT'S NEXT:${RESET}"
    echo -e "1. Reboot to activate all changes"
    echo -e "2. Enhanced ZSH shell ready on login"
    echo -e "3. All applications configured and ready"
    [ "$gaming_mode" = true ] && echo -e "4. Gaming tools ready (Steam, Lutris, MangoHud)"
    echo ""

    echo -e "${YELLOW}💡 USEFUL COMMANDS:${RESET}"
    echo -e "   • fastfetch - System information"
    echo -e "   • update - Update all packages"
    echo -e "   • clean - Clean package cache"
    [ "$gaming_mode" = true ] && echo -e "   • mangohud <game> - Performance overlay"
    echo ""

    echo -e "${GREEN}🔧 IMPORTANT NOTES:${RESET}"
    echo -e "   • ZSH shell with aliases and autocompletion ready"
    echo -e "   • Firewall active - configure ports as needed"
    [ "$gaming_mode" = true ] && echo -e "   • Gaming tools ready - just login and play!"
    echo -e "   • Kernel headers installed for compatibility"
    echo -e "   • ZRAM swap active - check with 'zramctl'"
  fi
}

# Legacy function for compatibility
print_summary() {
  print_comprehensive_summary
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

# =============================================================================
# ENHANCED PARALLEL INSTALLATION ENGINE
# =============================================================================

# Dynamic progress bar with ETA calculation
draw_progress_bar() {
    local progress="$1"
    local width="$2"
    local message="$3"
    local color="${4:-CYAN}"

    local filled_width=$((progress * width / 100))
    local empty_width=$((width - filled_width))

    # Create progress bar
    local bar=""
    for ((i=0; i<filled_width; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty_width; i++)); do
        bar+="░"
    done

    # Calculate ETA
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local eta=""
    if [[ $progress -gt 5 ]]; then
        local total_estimated=$((elapsed * 100 / progress))
        local remaining=$((total_estimated - elapsed))
        eta=" | ETA: $(format_duration $remaining)"
    fi

    # Print progress bar with beautiful formatting
    printf "\r${CYAN}▌${WHITE}%s${CYAN}▐ %3d%%%s ${GRAY}%s${RESET}" \
           "$bar" "$progress" "$eta" "$message"
}

# Animate progress with spinner and real-time updates
animate_progress() {
    local progress_file="$1"
    local message="$2"
    local width=$((TERM_WIDTH - 20))

    local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local spinner_index=0

    while true; do
        if [[ -f "$progress_file" ]]; then
            local progress=$(cat "$progress_file" 2>/dev/null || echo "0")
            local spinner="${spinner_chars[$spinner_index]}"

            # Draw progress with spinner
            printf "\r${CYAN}%s ${RESET}" "$spinner"
            draw_progress_bar "$progress" "$width" "$message" "CYAN"

            # Update spinner
            spinner_index=$(((spinner_index + 1) % ${#spinner_chars[@]}))

            # Exit if complete
            if [[ "$progress" -ge 100 ]]; then
                printf "\r${GREEN}✓ ${RESET}"
                draw_progress_bar "100" "$width" "$message" "GREEN"
                echo ""
                break
            fi
        fi

        sleep 0.1
    done
}

# Format duration helper
format_duration() {
    local duration="$1"
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))

    if [[ $hours -gt 0 ]]; then
        printf "%dh %dm %ds" "$hours" "$minutes" "$seconds"
    elif [[ $minutes -gt 0 ]]; then
        printf "%dm %ds" "$minutes" "$seconds"
    else
        printf "%ds" "$seconds"
    fi
}

# Beautiful ASCII art step transitions
show_step_transition() {
    local current="$1"
    local total="$2"
    local step_name="$3"
    local icon="$4"

    if command -v gum >/dev/null 2>&1; then
        gum style --border double --margin "1 2" --padding "1 4" --foreground 51 --border-foreground 51 "STEP $current OF $total"
        gum style --margin "1 0" --foreground 226 "$icon $step_name"
    else
        clear
        echo -e "${CYAN}"
        printf "%*s" $((TERM_WIDTH/2 + 10)) ""
        echo "╭─────────────────────────╮"
        printf "%*s" $((TERM_WIDTH/2 + 10)) ""
        echo "│    STEP $current OF $total    │"
        printf "%*s" $((TERM_WIDTH/2 + 10)) ""
        echo "╰─────────────────────────╯"
        echo -e "${RESET}"
        echo ""
        echo -e "${YELLOW}$icon ${WHITE}$step_name${RESET}"
        echo ""
    fi

    # Progress indicator
    local progress_width=50
    local filled=$((current * progress_width / total))
    local empty=$((progress_width - filled))

    printf "${CYAN}["
    printf "%*s" "$filled" "" | tr ' ' '█'
    printf "${GRAY}"
    printf "%*s" "$empty" "" | tr ' ' '░'
    printf "${CYAN}] %d/%d${RESET}\n" "$current" "$total"
    echo ""
}

# Initialize parallel installation engine
init_parallel_engine() {
    # Create job control directory
    mkdir -p "/tmp/arch_installer_jobs_$$"
    export JOB_DIR="/tmp/arch_installer_jobs_$$"
}

# Install packages in parallel batches - THE MAIN FEATURE!
install_packages_parallel() {
    local packages=("$@")
    local total_packages=${#packages[@]}

    if [[ $total_packages -eq 0 ]]; then
        return 0
    fi



    # Initialize parallel engine if not done
    if [[ ! -d "/tmp/arch_installer_jobs_$$" ]]; then
        init_parallel_engine
    fi

    # Split packages into batches
    local batch_num=0
    for ((i=0; i<total_packages; i+=BATCH_SIZE)); do
        local batch=("${packages[@]:i:BATCH_SIZE}")
        install_batch_parallel "$batch_num" "${batch[@]}" &

        # Limit concurrent batches
        if (( $(jobs -r | wc -l) >= PARALLEL_LIMIT )); then
            wait -n  # Wait for any job to complete
        fi

        ((batch_num++))
    done

    # Wait for all batches to complete
    wait
}

# Install a batch of packages in parallel
install_batch_parallel() {
    local batch_id="$1"
    shift
    local packages=("$@")

    local batch_status="${JOB_DIR:-/tmp}/batch_${batch_id}.status"

    echo "RUNNING" > "$batch_status"

    # Try pacman first, then AUR for failed packages
    local failed_packages=()

    for package in "${packages[@]}"; do
        if install_single_package "$package" >/dev/null 2>&1; then
            INSTALLED_PACKAGES+=("$package")
        else
            failed_packages+=("$package")
        fi
    done

    # Retry failed packages with AUR helper
    for package in "${failed_packages[@]}"; do
        if install_aur_package "$package" >/dev/null 2>&1; then
            INSTALLED_PACKAGES+=("$package")
        else
            FAILED_PACKAGES+=("$package")
        fi
    done

    echo "COMPLETED" > "$batch_status"
}

# Install a single package
install_single_package() {
    local package="$1"

    # Check if already installed
    if pacman -Qi "$package" &>/dev/null; then
        return 0
    fi

    # Install with pacman
    sudo pacman -S --noconfirm --needed "$package" 2>/dev/null
}

# Install package via AUR
install_aur_package() {
    local package="$1"

    # Check if paru is available
    if ! command -v paru >/dev/null 2>&1; then
        return 1
    fi

    # Install with paru
    paru -S --noconfirm --needed "$package" 2>/dev/null
}

# Enhanced category-based parallel installation
install_category_parallel() {
    local category="$1"
    shift
    local packages=("$@")

    if [[ ${#packages[@]} -eq 0 ]]; then
        return 0
    fi

    if command -v gum >/dev/null 2>&1; then
        gum style --foreground 51 "📦 Installing $category (${#packages[@]} packages)"
    else
        echo -e "${CYAN}📦 Installing $category (${#packages[@]} packages)${RESET}"
    fi

    # Create progress file
    local progress_file="/tmp/arch_installer_progress_$$"
    echo "0" > "$progress_file"

    # Start progress animation in background
    animate_progress "$progress_file" "$category" &
    local progress_pid=$!

    # Start parallel installation
    local start_time=$(date +%s)

    # Update progress during installation
    {
        echo "25" > "$progress_file"
        install_packages_parallel "${packages[@]}"
        echo "100" > "$progress_file"
    } &

    wait

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Stop progress animation
    kill $progress_pid 2>/dev/null || true
    wait $progress_pid 2>/dev/null || true

    # Show results
    local successful=$((${#packages[@]} - ${#FAILED_PACKAGES[@]}))

    if command -v gum >/dev/null 2>&1; then
        gum style --foreground 46 "✓ $category: $successful/${#packages[@]} packages installed in ${duration}s"
        if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
            gum style --foreground 226 "⚠ Failed packages: ${FAILED_PACKAGES[*]}"
        fi
    else
        echo -e "${GREEN}✓ $category: $successful/${#packages[@]} packages installed in ${duration}s${RESET}"
        if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
            echo -e "${YELLOW}⚠ Failed packages: ${FAILED_PACKAGES[*]}${RESET}"
        fi
    fi

    # Reset failed packages for next category
    FAILED_PACKAGES=()
    rm -f "$progress_file"
    echo ""
}

# System Health Dashboard
show_system_health_dashboard() {
    if command -v gum >/dev/null 2>&1; then
        gum style --border double --margin "1 2" --padding "1 4" --foreground 51 --border-foreground 51 "🏥 SYSTEM HEALTH DASHBOARD"
    else
        echo -e "${CYAN}"
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                  🏥 SYSTEM HEALTH DASHBOARD                  ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo -e "${RESET}"
    fi

    # Get system stats
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
    local memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "N/A")
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//' 2>/dev/null || echo "N/A")
    local installed_count=${#INSTALLED_PACKAGES[@]}
    local failed_count=${#FAILED_PACKAGES[@]}

    if command -v gum >/dev/null 2>&1; then
        gum style --margin "1 0" --foreground 226 "System Performance:"
        gum style --foreground 15 "  🖥️  CPU Usage:    ${cpu_usage}%"
        gum style --foreground 15 "  💾 Memory Usage: ${memory_usage}%"
        gum style --foreground 15 "  💽 Disk Usage:   ${disk_usage}%"
        echo ""
        gum style --foreground 226 "Installation Statistics:"
        gum style --foreground 46 "  ✅ Installed: $installed_count packages"
        if [[ $failed_count -gt 0 ]]; then
            gum style --foreground 196 "  ⚠️  Failed:    $failed_count packages"
        fi
        gum style --foreground 51 "  ⏱️  Duration:  $(format_duration $(($(date +%s) - START_TIME)))"
    else
        echo -e "${WHITE}System Performance:${RESET}"
        echo -e "  ${CYAN}🖥️  CPU Usage:    ${cpu_usage}%${RESET}"
        echo -e "  ${CYAN}💾 Memory Usage: ${memory_usage}%${RESET}"
        echo -e "  ${CYAN}💽 Disk Usage:   ${disk_usage}%${RESET}"
        echo ""
        echo -e "${WHITE}Installation Statistics:${RESET}"
        echo -e "  ${GREEN}✅ Installed: $installed_count packages${RESET}"
        if [[ $failed_count -gt 0 ]]; then
            echo -e "  ${YELLOW}⚠️  Failed:    $failed_count packages${RESET}"
        fi
        echo -e "  ${BLUE}⏱️  Duration:  $(format_duration $(($(date +%s) - START_TIME)))${RESET}"
    fi

    echo ""
}

# Completion animation
show_completion_animation() {
    if command -v gum >/dev/null 2>&1; then
        gum style --border double --margin "1 2" --padding "1 4" --foreground 46 --border-foreground 46 "🎉 INSTALLATION COMPLETE! 🎉"
    else
        clear
        echo -e "${GREEN}"
        echo "    ╔══════════════════════════════════════════════════════════════╗"
        echo "    ║                    🎉 INSTALLATION COMPLETE! 🎉             ║"
        echo "    ║                                                              ║"
        echo "    ║  ███████╗██╗   ██╗ ██████╗ ██████╗███████╗███████╗███████╗  ║"
        echo "    ║  ██╔════╝██║   ██║██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝  ║"
        echo "    ║  ███████╗██║   ██║██║     ██║     █████╗  ███████╗███████╗  ║"
        echo "    ║  ╚════██║██║   ██║██║     ██║     ██╔══╝  ╚════██║╚════██║  ║"
        echo "    ║  ███████║╚██████╔╝╚██████╗╚██████╗███████╗███████║███████║  ║"
        echo "    ║  ╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝╚══════╝╚══════╝╚══════╝  ║"
        echo "    ║                                                              ║"
        echo "    ╚══════════════════════════════════════════════════════════════╝"
        echo -e "${RESET}"

        # Celebration animation
        local celebration=("🎊" "🎉" "✨" "🌟" "⭐" "💫" "🎈" "🎆")
        for i in {1..3}; do
            for char in "${celebration[@]}"; do
                printf "\r${YELLOW}%*s%s%*s${RESET}" \
                       $((TERM_WIDTH/2 - 1)) "" "$char" $((TERM_WIDTH/2 - 1)) ""
                sleep 0.1
            done
        done
        echo ""
    fi
}

# Stop parallel engine and cleanup
stop_parallel_engine() {
    echo -e "${YELLOW}DEBUG: Active background jobs before wait:${RESET}"
    jobs -l

    # Wait for all background jobs to finish
    wait

    echo -e "${YELLOW}DEBUG: Active background jobs after wait:${RESET}"
    jobs -l

    # Clean up job control directory
    rm -rf "${JOB_DIR:-/tmp/arch_installer_jobs_$}" 2>/dev/null || true
    rm -f "/tmp/arch_installer_progress_$" 2>/dev/null || true
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
