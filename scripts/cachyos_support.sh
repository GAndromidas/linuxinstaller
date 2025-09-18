#!/bin/bash
set -uo pipefail

# CachyOS Support Functions
# This script provides CachyOS detection and compatibility functions

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Global variable to track if we're on CachyOS
IS_CACHYOS=false

# Function to detect CachyOS
detect_cachyos() {
  local cachyos_detected=false

  # Method 1: Check /etc/os-release
  if [ -f /etc/os-release ]; then
    if grep -qi "cachyos" /etc/os-release; then
      cachyos_detected=true
    fi
  fi

  # Method 2: Check for CachyOS specific packages
  if ! $cachyos_detected; then
    if pacman -Q cachyos-hello &>/dev/null || \
       pacman -Q cachyos-kernel-manager &>/dev/null || \
       pacman -Q cachyos-settings &>/dev/null; then
      cachyos_detected=true
    fi
  fi

  # Method 3: Check pacman.conf for CachyOS repositories
  if ! $cachyos_detected; then
    if grep -qi "cachyos" /etc/pacman.conf; then
      cachyos_detected=true
    fi
  fi

  # Method 4: Check for CachyOS kernels
  if ! $cachyos_detected; then
    if pacman -Q linux-cachyos &>/dev/null || \
       pacman -Q linux-cachyos-lts &>/dev/null; then
      cachyos_detected=true
    fi
  fi

  if $cachyos_detected; then
    IS_CACHYOS=true
    echo -e "${GREEN}✓ CachyOS detected!${RESET}"
    echo -e "${CYAN}  Running in CachyOS compatibility mode${RESET}"
    echo -e "${YELLOW}  Some steps will be skipped or modified for CachyOS${RESET}"
    export IS_CACHYOS
    return 0
  else
    IS_CACHYOS=false
    export IS_CACHYOS
    return 1
  fi
}

# Function to check current shell and detect if it's fish
get_current_shell() {
  local current_shell=""

  # Check user's shell from /etc/passwd
  current_shell=$(getent passwd "$USER" | cut -d: -f7)

  # Get just the shell name
  current_shell=$(basename "$current_shell")

  echo "$current_shell"
}

# Function to detect if fish is the default shell (common in CachyOS)
is_fish_shell() {
  local shell=$(get_current_shell)
  [[ "$shell" == "fish" ]]
}

# Function to show CachyOS specific information
show_cachyos_info() {
  if $IS_CACHYOS; then
    echo -e "\n${CYAN}═══ CachyOS Compatibility Mode ═══${RESET}"
    echo -e "${YELLOW}The following will be SKIPPED:${RESET}"
    echo -e "  • ${RED}Plymouth setup${RESET} - CachyOS has this pre-configured"
    echo -e "  • ${RED}Kernel configuration${RESET} - CachyOS manages its own kernels"
    echo -e "  • ${RED}Some bootloader modifications${RESET} - CachyOS handles boot configuration"
    echo -e ""
    echo -e "${YELLOW}The following will be MODIFIED:${RESET}"
    if [[ "${CACHYOS_SHELL_CHOICE:-}" == "zsh" ]]; then
      echo -e "  • ${RED}Fish shell${RESET} - Will be COMPLETELY REMOVED (NO BACKUPS!)"
      echo -e "  • ${GREEN}ZSH setup${RESET} - Will replace Fish with your ZSH configuration"
    elif [[ "${CACHYOS_SHELL_CHOICE:-}" == "fish" ]]; then
      echo -e "  • ${GREEN}Fish shell${RESET} - Will be kept as-is (CachyOS configuration preserved)"
      echo -e "  • ${GREEN}Fastfetch config${RESET} - Will be replaced with archinstaller version"
    else
      echo -e "  • ${YELLOW}Shell setup${RESET} - You will choose Fish→ZSH or Fish enhancement"
    fi
    echo -e "  • ${GREEN}Package installation${RESET} - Will skip already installed packages"
    echo -e "  • ${GREEN}System preparation${RESET} - Will be more conservative with changes"
    echo -e ""
    echo -e "${YELLOW}The following will PROCEED normally:${RESET}"
    echo -e "  • ${CYAN}AUR helper setup${RESET} - Will replace paru with yay (archinstaller standard)"
    echo -e "  • ${CYAN}Programs installation${RESET}"
    echo -e "  • ${CYAN}Gaming mode setup${RESET}"
    echo -e "  • ${CYAN}System services${RESET}"
    echo -e "  • ${CYAN}Security setup (Fail2ban)${RESET}"
    echo -e "  • ${CYAN}Maintenance tasks${RESET}"
    echo -e ""
    if is_fish_shell && [[ "${CACHYOS_SHELL_CHOICE:-}" == "zsh" ]]; then
      echo -e "${RED}⚠️  CRITICAL WARNING FOR FISH USERS ⚠️${RESET}"
      echo -e "${RED}Fish shell will be PERMANENTLY DELETED with NO RECOVERY!${RESET}"
      echo -e "${RED}This includes ALL configurations, history, and customizations!${RESET}"
    elif is_fish_shell && [[ "${CACHYOS_SHELL_CHOICE:-}" == "fish" ]]; then
      echo -e "${GREEN}✓ Fish shell will be enhanced with archinstaller features${RESET}"
      echo -e "${CYAN}  Your Fish configuration will be preserved and improved${RESET}"
    elif is_fish_shell; then
      echo -e "${YELLOW}⚠️  You will choose how to handle Fish shell configuration${RESET}"
    fi
    echo -e "${CYAN}══════════════════════════════════════${RESET}\n"
  fi
}

# Function to check if we should skip Plymouth
should_skip_plymouth() {
  # Ensure reliable CachyOS detection
  ensure_cachyos_detection
  if $IS_CACHYOS; then
    log_info "Skipping Plymouth setup - CachyOS has Plymouth pre-configured"
    return 0  # Skip Plymouth
  fi
  return 1  # Don't skip Plymouth
}

# Function to check if we should skip bootloader kernel config
should_skip_kernel_config() {
  # Ensure reliable CachyOS detection
  ensure_cachyos_detection
  if $IS_CACHYOS; then
    log_info "Skipping kernel configuration - CachyOS manages its own kernel setup"
    return 0  # Skip kernel config
  fi
  return 1  # Don't skip kernel config
}

# Function to check if we should modify bootloader config
should_modify_bootloader() {
  # Ensure reliable CachyOS detection
  ensure_cachyos_detection
  if $IS_CACHYOS; then
    # We'll still do some bootloader modifications but be more conservative
    log_info "Using conservative bootloader modifications for CachyOS"
    return 0  # Do modified bootloader config
  fi
  return 1  # Do full bootloader config
}

# Function to show shell choice menu for CachyOS Fish users
show_shell_choice_menu() {
  if ! $IS_CACHYOS || ! is_fish_shell; then
    return 1  # Not CachyOS with Fish, skip menu
  fi

  echo -e "\n${CYAN}═══ CachyOS Shell Configuration ═══${RESET}"
  echo -e "${YELLOW}CachyOS uses Fish shell by default. Choose your preference:${RESET}"
  echo ""

  local choice=""
  if command -v gum >/dev/null 2>&1; then
    choice=$(gum choose --cursor "→ " --selected.foreground 51 --cursor.foreground 51 \
      "🐚 Convert to ZSH - Replace Fish with archinstaller ZSH setup" \
      "🐠 Keep Fish - Replace fastfetch config only" \
      "❌ Cancel - Exit installation")
  else
    echo -e "${CYAN}1) 🐚 Convert to ZSH - Replace Fish with archinstaller ZSH setup${RESET}"
    echo -e "${CYAN}2) 🐠 Keep Fish - Replace fastfetch config only${RESET}"
    echo -e "${CYAN}3) ❌ Cancel - Exit installation${RESET}"
    echo ""
    while true; do
      read -r -p "$(echo -e "${YELLOW}Enter your choice [1-3]: ${RESET}")" menu_choice
      case "$menu_choice" in
        1) choice="🐚 Convert to ZSH - Replace Fish with archinstaller ZSH setup"; break ;;
        2) choice="🐠 Keep Fish - Replace fastfetch config only"; break ;;
        3) choice="❌ Cancel - Exit installation"; break ;;
        *) echo -e "${RED}❌ Invalid choice! Please enter 1, 2, or 3.${RESET}" ;;
      esac
    done
  fi

  case "$choice" in
    *"Convert to ZSH"*)
      export CACHYOS_SHELL_CHOICE="zsh"
      log_success "User chose: Convert Fish to ZSH"
      return 0
      ;;
    *"Keep Fish"*)
      export CACHYOS_SHELL_CHOICE="fish"
      log_success "User chose: Keep Fish, replace fastfetch config only"
      return 0
      ;;
    *"Cancel"*)
      echo -e "${YELLOW}Installation cancelled by user choice.${RESET}"
      exit 0
      ;;
  esac
}

# Function to handle fish to zsh conversion for CachyOS
handle_shell_conversion() {
  if ! $IS_CACHYOS || ! is_fish_shell; then
    return 1  # Not CachyOS with Fish, no conversion needed
  fi

  if [[ "${CACHYOS_SHELL_CHOICE:-}" == "zsh" ]]; then
    echo -e "\n${YELLOW}═══ Converting from Fish to ZSH ═══${RESET}"
    echo -e "${CYAN}Completely replacing Fish with ZSH...${RESET}"

    # Remove fish config completely
    if [ -d "$HOME/.config/fish" ]; then
      log_info "Removing existing Fish configuration completely"
      rm -rf "$HOME/.config/fish" 2>/dev/null || true
      log_success "Fish configuration removed"
    fi

    # Remove any fish-related files in home directory
    if [ -f "$HOME/.fishrc" ]; then
      rm -f "$HOME/.fishrc" 2>/dev/null || true
    fi

    if [ -d "$HOME/.local/share/fish" ]; then
      rm -rf "$HOME/.local/share/fish" 2>/dev/null || true
    fi

    # Uninstall fish package if installed
    if pacman -Q fish &>/dev/null; then
      log_info "Removing Fish shell package"
      sudo pacman -Rns fish --noconfirm 2>/dev/null || true
      log_success "Fish shell package removed"
    fi

    # Change shell to zsh
    if command -v zsh >/dev/null; then
      sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || true
      log_success "Changed default shell from Fish to ZSH"
    else
      log_error "ZSH not found. Please install it first."
      return 1
    fi

    # Show information about the conversion
    echo -e "${GREEN}✓ Shell conversion completed${RESET}"
    echo -e "${YELLOW}  Fish shell and all configurations completely removed${RESET}"
    echo -e "${YELLOW}  ZSH will be configured with your archinstaller settings${RESET}"
    echo -e "${CYAN}══════════════════════════════════════${RESET}\n"

    return 0
  elif [[ "${CACHYOS_SHELL_CHOICE:-}" == "fish" ]]; then
    echo -e "\n${YELLOW}═══ Keeping Fish Shell ═══${RESET}"
    echo -e "${CYAN}Preserving CachyOS Fish configuration, replacing fastfetch config only...${RESET}"

    replace_fastfetch_config_only
    return 0
  fi

  return 1  # No choice made
}

# Function to only replace fastfetch config for Fish users
replace_fastfetch_config_only() {
  log_info "Replacing fastfetch config with archinstaller version"

  # Copy fastfetch config if available (don't modify Fish config - CachyOS handles that)
  if [ -f "$CONFIGS_DIR/config.jsonc" ]; then
    mkdir -p "$HOME/.config/fastfetch"
    cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
    log_success "Fastfetch configuration replaced with archinstaller version"
  else
    log_warning "config.jsonc not found in configs directory"
  fi

  echo -e "${GREEN}✓ Fish shell configuration preserved${RESET}"
  echo -e "${YELLOW}  Replaced: fastfetch config with archinstaller version${RESET}"
  echo -e "${YELLOW}  Your CachyOS Fish configuration remains unchanged${RESET}"
  echo -e "${CYAN}═══════════════════════════════════════════════${RESET}\n"
}

# Function to check if a package is already installed and configured
is_package_configured() {
  local package="$1"

  if ! $IS_CACHYOS; then
    return 1  # Not CachyOS, proceed normally
  fi

  # Check if package is installed
  if ! pacman -Q "$package" &>/dev/null; then
    return 1  # Package not installed
  fi

  # Package is installed, check if it's a CachyOS default that might be configured
  case "$package" in
    "plymouth"|"plymouth-theme-"*)
      log_info "$package already configured by CachyOS, skipping"
      return 0  # Skip, it's configured
      ;;
    "fish")
      log_info "$package detected but we're completely removing it for ZSH"
      return 0  # Skip installing, we're removing it
      ;;
    *)
      log_info "$package already installed, checking if configured"
      return 1  # Let normal installation logic handle it
      ;;
  esac
}

# Function to completely purge Fish shell from the system
purge_fish_completely() {
  if ! $IS_CACHYOS; then
    return 0  # Not CachyOS, skip this function
  fi

  echo -e "\n${RED}═══ COMPLETELY REMOVING FISH SHELL ═══${RESET}"
  echo -e "${YELLOW}⚠️  Fish shell and ALL its data will be permanently deleted!${RESET}"

  # Remove fish package and all dependencies
  if pacman -Q fish &>/dev/null; then
    log_info "Uninstalling Fish shell package and orphaned dependencies"

    # Remove fish package with dependencies and clean up
    sudo pacman -Rns fish --noconfirm >/dev/null 2>&1 || {
      # If the above fails, try force removal
      sudo pacman -Rd fish --noconfirm >/dev/null 2>&1 || true
    }

    # Clean up any orphaned packages after fish removal
    sudo pacman -Rns $(pacman -Qtdq) --noconfirm >/dev/null 2>&1 || true

    log_success "Fish shell package completely removed"
  else
    log_info "Fish shell package not installed"
  fi

  # Remove all fish-related directories and files for current user
  local removed_items=()

  if [ -d "$HOME/.config/fish" ]; then
    rm -rf "$HOME/.config/fish" 2>/dev/null && removed_items+=("~/.config/fish")
  fi

  if [ -d "$HOME/.local/share/fish" ]; then
    rm -rf "$HOME/.local/share/fish" 2>/dev/null && removed_items+=("~/.local/share/fish")
  fi

  if [ -d "$HOME/.cache/fish" ]; then
    rm -rf "$HOME/.cache/fish" 2>/dev/null && removed_items+=("~/.cache/fish")
  fi

  if [ -f "$HOME/.fishrc" ]; then
    rm -f "$HOME/.fishrc" 2>/dev/null && removed_items+=("~/.fishrc")
  fi

  if [ -f "$HOME/.fish_history" ]; then
    rm -f "$HOME/.fish_history" 2>/dev/null && removed_items+=("~/.fish_history")
  fi

  # Remove any fish-related files in common locations
  local fish_files=(
    "$HOME/.fish"
    "$HOME/.fish_variables"
    "$HOME/.config/fish.backup"
    "$HOME/.local/share/omf"
    "$HOME/.config/omf"
  )

  for file in "${fish_files[@]}"; do
    if [ -e "$file" ]; then
      rm -rf "$file" 2>/dev/null && removed_items+=("$(basename "$file")")
    fi
  done

  # Show what was removed
  if [ ${#removed_items[@]} -gt 0 ]; then
    log_success "Removed Fish data: ${removed_items[*]}"
  else
    log_info "No Fish configuration files found to remove"
  fi

  # Ensure current shell is not fish
  current_shell=$(getent passwd "$USER" | cut -d: -f7)
  if [[ "$current_shell" == *"fish"* ]]; then
    log_info "Changing shell from Fish to Bash temporarily"
    sudo chsh -s /bin/bash "$USER" 2>/dev/null || true
  fi

  # Clear any fish-related environment variables that might be set
  unset FISH_VERSION 2>/dev/null || true
  unset fish_greeting 2>/dev/null || true

  # Remove fish from /etc/shells if present (system-wide cleanup)
  if grep -q fish /etc/shells 2>/dev/null; then
    sudo sed -i '/fish/d' /etc/shells 2>/dev/null || true
    log_info "Removed fish entries from /etc/shells"
  fi

  echo -e "${GREEN}✓ Fish shell completely purged from system${RESET}"
  echo -e "${YELLOW}  All Fish configurations, history, and data permanently deleted${RESET}"
  echo -e "${CYAN}════════════════════════════════════════════════${RESET}\n"
}

# Function to get CachyOS specific packages to avoid conflicts
get_cachyos_conflicting_packages() {
  local conflicts=()

  if $IS_CACHYOS; then
    # Add packages that might conflict with CachyOS defaults
    conflicts+=("linux" "linux-headers")  # CachyOS has its own kernels
    # Add more as needed
  fi

  printf '%s\n' "${conflicts[@]}"
}

# Function to modify system requirements check for CachyOS
check_cachyos_system_requirements() {
  if ! $IS_CACHYOS; then
    return 0  # Not CachyOS, use normal requirements
  fi

  echo -e "${CYAN}Checking CachyOS system requirements...${RESET}"

  # Check if running as root
  check_root_user

  # Check if we're on Arch Linux (CachyOS should pass this)
  if [[ ! -f /etc/arch-release ]] && [[ ! -f /etc/os-release ]]; then
    echo -e "${RED}❌ Error: This script is designed for Arch Linux based systems!${RESET}"
    echo -e "${YELLOW}   CachyOS is supported as an Arch Linux derivative.${RESET}"
    return 1
  fi

  # Check internet connection
  if ! ping -c 1 archlinux.org &>/dev/null; then
    echo -e "${RED}❌ Error: No internet connection detected!${RESET}"
    echo -e "${YELLOW}   Please check your network connection and try again.${RESET}"
    return 1
  fi

  # Check available disk space (at least 2GB)
  local available_space=$(df / | awk 'NR==2 {print $4}')
  if [[ $available_space -lt 2097152 ]]; then
    echo -e "${RED}❌ Error: Insufficient disk space!${RESET}"
    echo -e "${YELLOW}   At least 2GB free space is required.${RESET}"
    echo -e "${YELLOW}   Available: $((available_space / 1024 / 1024))GB${RESET}"
    return 1
  fi

  # CachyOS specific checks
  if command -v fish >/dev/null; then
    echo -e "${YELLOW}ℹ Fish shell detected - will be converted to ZSH${RESET}"
  fi

  if pacman -Q plymouth &>/dev/null; then
    echo -e "${YELLOW}ℹ Plymouth already installed - will skip Plymouth setup${RESET}"
  fi

  local cachyos_kernels=$(pacman -Q | grep -c "linux-cachyos" || echo "0")
  if [ "$cachyos_kernels" -gt 0 ]; then
    echo -e "${YELLOW}ℹ CachyOS kernels detected ($cachyos_kernels) - will skip kernel modifications${RESET}"
  fi

  echo -e "${GREEN}✓ CachyOS system requirements check passed${RESET}"
  return 0
}

# Function to check if a package is already configured by CachyOS
is_cachyos_package_configured() {
  local package="$1"

  if ! $IS_CACHYOS; then
    return 1  # Not CachyOS, package not configured
  fi

  # Package is installed, check if it's a CachyOS default that might be configured
  case "$package" in
    "plymouth"|"plymouth-theme-"*)
      # CachyOS often has Plymouth pre-configured
      if pacman -Q plymouth &>/dev/null; then
        log_info "$package already configured by CachyOS"
        return 0
      fi
      ;;
    "yay")
      # CachyOS includes yay by default
      if command -v yay &>/dev/null; then
        log_info "yay already available in CachyOS"
        return 0
      fi
      ;;
    "fish")
      # CachyOS uses fish by default
      if command -v fish &>/dev/null; then
        log_info "fish shell is CachyOS default"
        return 0
      fi
      ;;
    "grub"|"grub-btrfs")
      # CachyOS manages its own bootloader configuration
      if pacman -Q "$package" &>/dev/null; then
        log_info "$package managed by CachyOS"
        return 0
      fi
      ;;
    "linux-zen"|"linux-cachyos"*)
      # CachyOS has its own kernel management
      if pacman -Q "$package" &>/dev/null; then
        log_info "$package managed by CachyOS kernel system"
        return 0
      fi
      ;;
    *)
      # For other packages, just check if they're installed and likely pre-configured
      if pacman -Q "$package" &>/dev/null; then
        # Additional heuristic: if it's a core system package in CachyOS, consider it configured
        local cachyos_core_packages=("fastfetch" "starship" "zsh" "firefox" "kate" "konsole")
        for core_pkg in "${cachyos_core_packages[@]}"; do
          if [[ "$package" == "$core_pkg" ]]; then
            log_info "$package is pre-configured in CachyOS"
            return 0
          fi
        done
      fi
      ;;
  esac

  return 1  # Package not configured by CachyOS
}

# Function to enable essential services for CachyOS
enable_cachyos_services() {
  if ! $IS_CACHYOS; then
    return 0  # Not CachyOS, use standard service setup
  fi

  echo -e "\n${YELLOW}═══ Enabling Archinstaller Services for CachyOS ═══${RESET}"
  log_info "Enabling archinstaller services while preserving CachyOS configuration"

  # Enable SSH service (archinstaller feature)
  if command -v sshd >/dev/null 2>&1 || pacman -Q openssh &>/dev/null; then
    if ! systemctl is-enabled sshd &>/dev/null; then
      sudo systemctl enable sshd
      log_success "SSH service enabled"
    else
      log_info "SSH service already enabled"
    fi
  fi

  # Enable RustDesk service if installed
  if pacman -Q rustdesk-bin &>/dev/null || pacman -Q rustdesk &>/dev/null; then
    log_info "RustDesk detected, ensuring proper configuration"
    # RustDesk typically doesn't need systemd service, just desktop integration
  fi

  echo -e "${CYAN}══════════════════════════════════════════${RESET}\n"
}

# Function to handle desktop environment specific configurations for CachyOS
setup_cachyos_desktop_tweaks() {
  if ! $IS_CACHYOS; then
    return 0  # Not CachyOS, use standard desktop setup
  fi

  echo -e "\n${YELLOW}═══ CachyOS Desktop Environment Tweaks ═══${RESET}"
  log_info "Applying archinstaller desktop configurations for CachyOS"

  # Check if KDE Plasma is detected
  if [[ "$XDG_CURRENT_DESKTOP" == "KDE" ]] || command -v plasmashell >/dev/null 2>&1; then
    log_info "KDE Plasma detected on CachyOS"

    # Copy KDE global shortcuts if available
    local kde_shortcuts_source="$CONFIGS_DIR/kglobalshortcutsrc"
    local kde_shortcuts_dest="$HOME/.config/kglobalshortcutsrc"

    if [ -f "$kde_shortcuts_source" ]; then
      mkdir -p "$HOME/.config"
      cp "$kde_shortcuts_source" "$kde_shortcuts_dest"
      log_success "KDE global shortcuts configuration applied to CachyOS"
      log_info "KDE shortcuts will be active after next login or KDE restart"
    else
      log_warning "KDE shortcuts configuration file not found at $kde_shortcuts_source"
    fi

    # Enable KDE Connect ports in firewall if KDE Connect is installed
    if pacman -Q kdeconnect &>/dev/null; then
      log_info "KDE Connect detected, ensuring firewall configuration"
      # This will be handled by the main system_services.sh script
    fi
  else
    log_info "KDE Plasma not detected, skipping KDE-specific tweaks"
  fi

  echo -e "${CYAN}══════════════════════════════════════════${RESET}\n"
}

# Centralized function to ensure CachyOS detection is reliable across all scripts
ensure_cachyos_detection() {
  # If already detected and variable is set, return
  if $IS_CACHYOS; then
    return 0
  fi

  # Perform direct detection
  local cachyos_detected=false

  # Method 1: Check /etc/os-release
  if [ -f /etc/os-release ] && grep -qi "cachyos" /etc/os-release; then
    cachyos_detected=true
  fi

  # Method 2: Check for CachyOS packages
  if pacman -Q cachyos-keyring &>/dev/null || pacman -Q cachyos-mirrorlist &>/dev/null; then
    cachyos_detected=true
  fi

  # Method 3: Check CachyOS repositories in pacman.conf
  if grep -qi "cachyos" /etc/pacman.conf 2>/dev/null; then
    cachyos_detected=true
  fi

  # Update the global variable if detected
  if $cachyos_detected; then
    IS_CACHYOS=true
    export IS_CACHYOS
    return 0
  fi

  return 1
}

# Function to check if yay should be skipped on CachyOS
should_skip_yay_installation() {
  # Ensure reliable CachyOS detection
  ensure_cachyos_detection

  if $IS_CACHYOS; then
    if command -v yay &>/dev/null; then
      echo -e "${YELLOW}CachyOS detected - yay already installed, skipping installation.${RESET}"
      log_info "yay installation skipped (CachyOS compatibility) - yay already available"
      return 0  # Skip yay installation
    elif command -v paru &>/dev/null; then
      echo -e "${YELLOW}CachyOS detected with paru - removing paru and installing yay.${RESET}"
      echo -e "${CYAN}Replacing paru with yay for archinstaller compatibility.${RESET}"
      log_info "CachyOS uses paru, removing it and installing yay instead"
      # Remove paru
      if sudo pacman -Rns --noconfirm paru &>/dev/null; then
        log_success "paru removed successfully"
      else
        log_warning "Failed to remove paru, but continuing with yay installation"
      fi
      return 1  # Don't skip, install yay
    else
      echo -e "${YELLOW}CachyOS detected but no AUR helper found - will install yay.${RESET}"
      log_warning "CachyOS system detected but no AUR helper available, installing yay"
      return 1  # Don't skip, install yay
    fi
  fi

  return 1  # Not CachyOS, don't skip
}

# Function to check if pacman.conf should be skipped on CachyOS
should_skip_pacman_config() {
  # Ensure reliable CachyOS detection
  ensure_cachyos_detection

  if $IS_CACHYOS; then
    log_info "CachyOS detected - skipping pacman.conf modifications"
    log_info "Preserving CachyOS optimized configuration (architecture, repositories, settings)"
    return 0  # Skip pacman config
  fi

  return 1  # Not CachyOS, don't skip
}

# Export the IS_CACHYOS variable so other scripts can use it
export IS_CACHYOS
