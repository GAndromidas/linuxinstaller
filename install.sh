#!/bin/bash
set -uo pipefail

# Check if running as root, re-exec with sudo if not
if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# =============================================================================
# LinuxInstaller v1.0 - Unified Post-Installation Script
# =============================================================================
#
# DESCRIPTION:
#   A comprehensive, cross-distribution Linux post-installation script that
#   automates system configuration, package installation, and optimization.
#
# SUPPORTED DISTRIBUTIONS:
#   • Arch Linux (with AUR support)
#   • Fedora (with COPR support)
#   • Debian & Ubuntu (with Snap support)
#
# INSTALLATION MODES:
#   • Standard: Complete setup with all recommended packages
#   • Minimal: Essential tools only for lightweight installations
#   • Server: Headless server configuration
#
# FEATURES:
#   • Distribution-specific optimizations
#   • Desktop environment configuration (KDE, GNOME)
#   • Security hardening (firewall, fail2ban)
#   • Performance tuning (CPU governor, filesystem optimization)
#   • Gaming suite (optional - Steam, Wine, GPU drivers)
#   • Development tools and shell customization (zsh, starship)
#
# USAGE:
#   ./install.sh [OPTIONS]
#   ./install.sh --dry-run     # Preview changes without applying
#   ./install.sh --verbose     # Show detailed output
#   ./install.sh --help        # Show help information
#
# REQUIREMENTS:
#   • Root privileges (sudo)
#   • Active internet connection
#   • Supported Linux distribution
#
# AUTHOR: George Andromidas
# LICENSE: See LICENSE file
# =============================================================================

# Show LinuxInstaller ASCII art banner (beautiful cyan theme)
show_linuxinstaller_ascii() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
      _     _                  ___           _        _ _
     | |   (_)_ __  _   ___  _|_ _|_ __  ___| |_ __ _| | | ___ _ __
     | |   | | '_ \| | | \ \/ /| || '_ \/ __| __/ _` | | |/ _ \ '__|
     | |___| | | | | |_| |>  < | || | | \__ \ || (_| | | |  __/ |
     |_____|_|_| |_|\__,_/_/\_\___|_| |_|___/\__\__,_|_|_|\___|_|
EOF
    echo -e "${LIGHT_CYAN}           Cross-Distribution Linux Post-Installation Script${RESET}"
    echo ""
}

# Enhanced Menu Function
show_menu() {
    show_linuxinstaller_ascii

    if ! supports_gum; then
        echo -e "${LIGHT_CYAN}Note: gum not detected, using enhanced text menu${RESET}"
    fi

    echo ""

    # If gum is available and we have an interactive TTY, try gum-based UI
    if supports_gum && [ -t 0 ]; then
        local choice
        choice=$(gum choose \
            "Standard - Complete setup with all recommended packages" \
            "Minimal - Essential tools only for lightweight installations" \
            "Server - Headless server configuration" \
            "Exit" \
            --cursor.foreground "$GUM_PRIMARY_FG" --cursor "→" \
            --selected.foreground "$GUM_PRIMARY_FG")

        case "$choice" in
            "Standard - Complete setup with all recommended packages")
                export INSTALL_MODE="standard" ;;
            "Minimal - Essential tools only for lightweight installations")
                export INSTALL_MODE="minimal" ;;
            "Server - Headless server configuration")
                export INSTALL_MODE="server" ;;
            "Exit")
                gum style "Goodbye! 👋" --margin "0 2" --foreground "$GUM_BODY_FG"
                exit 0 ;;
        esac

        echo ""
        gum style "✓ Selected: $choice" --margin "0 2" --foreground "$GUM_SUCCESS_FG" --bold
        echo ""

        if [ "$INSTALL_MODE" == "standard" ] || [ "$INSTALL_MODE" == "minimal" ]; then
            echo ""
            gum style "🎮 Would you like to install the Gaming Package Suite?" \
                     --margin "0 2" --foreground "$GUM_BODY_FG" 2>/dev/null || true
            gum style "This includes Steam, Wine, and gaming optimizations." \
                     --margin "0 2" --foreground "$GUM_BODY_FG" 2>/dev/null || true
            echo ""
            if gum confirm "Install Gaming Package Suite?" --default=true; then
                export INSTALL_GAMING=true
                gum style "✓ Gaming packages will be installed" \
                         --margin "0 2" --foreground "$GUM_SUCCESS_FG" 2>/dev/null || true
            else
                export INSTALL_GAMING=false
                gum style "→ Skipping gaming packages" \
                         --margin "0 2" --foreground "$GUM_BODY_FG" 2>/dev/null || true
            fi
        else
            export INSTALL_GAMING=false
        fi
        return
    fi

    # Fallback plain-text menu
    local text_choice
    while true; do
        echo "Please select an installation mode:"
        echo "  1) Standard - Complete setup with all recommended packages"
        echo "  2) Minimal - Essential tools only for lightweight installations"
        echo "  3) Server - Headless server configuration"
        echo "  4) Exit"
        read -r -t 300 -p "Enter choice [1-4]: " text_choice 2>/dev/null || {
            echo "No input received. Using default: Standard"
            text_choice="1"
            break
        }

         case "$text_choice" in
             1) export INSTALL_MODE="standard" ; break ;;
             2) export INSTALL_MODE="minimal" ; break ;;
             3) export INSTALL_MODE="server" ; break ;;
             4) echo -e "${LIGHT_CYAN}Goodbye! 👋${RESET}"; exit 0 ;;
             *) echo -e "${YELLOW}Invalid choice, please try again.${RESET}" ;;
         esac
    done

    echo ""

    local friendly
    case "$INSTALL_MODE" in
        standard) friendly="Standard - Complete setup with all recommended packages" ;;
        minimal)  friendly="Minimal - Essential tools only for lightweight installations" ;;
        server)   friendly="Server - Headless server configuration" ;;
        *)        friendly="$INSTALL_MODE" ;;
    esac

    echo -e "${CYAN}✓ You selected: ${LIGHT_CYAN}$friendly${RESET}"

    if { [ "$INSTALL_MODE" == "standard" ] || [ "$INSTALL_MODE" == "minimal" ]; } && [ -z "${CUSTOM_GROUPS:-}" ]; then
        if [ -t 0 ]; then
            read -r -p "Install Gaming Package Suite? [Y/n]: " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ || -z "$response" ]]; then
                export INSTALL_GAMING=true
            else
                export INSTALL_GAMING=false
            fi
        else
            export INSTALL_GAMING=false
        fi
    else
        if [[ "${CUSTOM_GROUPS:-}" == *"Gaming"* ]]; then
            export INSTALL_GAMING=true
        fi
    fi

    echo ""
}

# Color variables (cyan theme)
CYAN='\033[0;36m'
LIGHT_CYAN='\033[1;36m'
BLUE='\033[0;34m'
RESET='\033[0m'

# --- Configuration & Paths ---
# Determine script location and derive important directories
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"  # Absolute path to this script
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"  # Directory containing this script
CONFIGS_DIR="$SCRIPT_DIR/configs"    # Distribution-specific configuration files
SCRIPTS_DIR="$SCRIPT_DIR/scripts"    # Modular script components

# --- Source Helpers ---
# We need distro detection and common utilities immediately
# Source required helper scripts with better error handling
if [ -f "$SCRIPTS_DIR/common.sh" ]; then
    source "$SCRIPTS_DIR/common.sh"
else
    echo "FATAL ERROR: Required file 'common.sh' not found in $SCRIPTS_DIR"
    echo "This indicates a corrupted or incomplete installation."
    echo "Please re-download LinuxInstaller from the official repository."
    exit 1
fi

if [ -f "$SCRIPTS_DIR/distro_check.sh" ]; then
    source "$SCRIPTS_DIR/distro_check.sh"
else
    echo "FATAL ERROR: Required file 'distro_check.sh' not found in $SCRIPTS_DIR"
    echo "This indicates a corrupted or incomplete installation."
    echo "Please re-download LinuxInstaller from the official repository."
    exit 1
fi

# Optional Wake-on-LAN integration (sourced if present).
# The module integrates the wakeonlan helper so LinuxInstaller can auto-configure WoL.
if [ -f "$SCRIPTS_DIR/wakeonlan_config.sh" ]; then
  source "$SCRIPTS_DIR/wakeonlan_config.sh"
fi

# Optional power management helper (detection + configuration).
# This module provides `detect_system_info`, `show_system_info`, and
# `configure_power_management` to auto-detect CPU/GPU/RAM and configure
# power-profiles-daemon / cpupower / tuned as appropriate.
if [ -f "$SCRIPTS_DIR/power_config.sh" ]; then
  source "$SCRIPTS_DIR/power_config.sh"
fi

# --- Global Variables ---
# Runtime flags and configuration
VERBOSE=false           # Enable detailed logging output
DRY_RUN=false          # Preview mode - show what would be done without changes
TOTAL_STEPS=0          # Total number of installation steps
CURRENT_STEP=0         # Current step counter for progress tracking
INSTALL_MODE="standard" # Installation mode: standard, minimal, or server

# Helper tracking
GUM_INSTALLED_BY_SCRIPT=false  # Track if we installed gum to clean it up later

# --- Helper Functions ---
# Utility functions for script operation and user interaction

# Display help message and usage information
# Shows command-line options, installation modes, and examples
show_help() {
  cat << EOF
LinuxInstaller - Unified Post-Install Script

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Show detailed output
    -d, --dry-run   Simulate installation (no changes made)

 DESCRIPTION:
     A smart, cross-distribution installer that configures your system,
     installs packages, and applies tweaks.
     Supports Arch, Fedora, Debian, and Ubuntu.

 INSTALLATION MODES:
     Standard        Complete setup with all recommended packages
     Minimal         Essential tools only for lightweight installations
     Server          Headless server configuration

 EXAMPLES:
     ./install.sh                Run with interactive prompts
     ./install.sh --verbose      Run with detailed output
     ./install.sh --dry-run      Preview changes without applying them

EOF
  exit 0
}

# Bootstrap essential tools required for the installer
# Installs gum UI helper if not present, ensuring beautiful terminal output
bootstrap_tools() {
    log_info "Bootstrapping installer tools..."

    # Verify internet connectivity before attempting installations
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connection detected!"
        log_error "Internet access is required for package installation."
        log_error "Please connect to the internet and try again."
        if [ "$DRY_RUN" = false ]; then
            exit 1
        fi
    fi

    # Install gum UI helper for enhanced terminal interface
    # Gum provides beautiful menus, progress bars, and styled output
    if ! supports_gum; then
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would install gum UI helper"
            return
        fi

        log_info "Installing gum UI helper for enhanced terminal interface..."

        # Try package manager first (different for Arch vs others)
        if [ "$DISTRO_ID" == "arch" ]; then
            if pacman -S --noconfirm gum >/dev/null 2>&1; then
                GUM_INSTALLED_BY_SCRIPT=true
                supports_gum >/dev/null 2>&1 || true
                log_success "Gum UI helper installed successfully"
            else
                log_warn "Failed to install gum via pacman"
            fi
        else
            if install_pkg gum >/dev/null 2>&1; then
                GUM_INSTALLED_BY_SCRIPT=true
                supports_gum >/dev/null 2>&1 || true
                log_success "Gum UI helper installed successfully"
            else
                log_warn "Failed to install gum via package manager"
                log_info "Continuing with text-based interface"
            fi
        fi
    fi
}




# =============================================================================
# PACKAGE INSTALLATION SYSTEM - Refactored for better maintainability
# =============================================================================

# Determine available package types for current distribution
determine_package_types() {
    local requested_type="${1:-}"

    # If specific package type requested, only return that type
    if [ -n "$requested_type" ]; then
        echo "$requested_type"
        return
    fi

    # Determine package types available for this distro
    case "$DISTRO_ID" in
        arch)   echo "native aur flatpak" ;;
        ubuntu) echo "native snap flatpak" ;;
        *)      echo "native flatpak" ;; # fedora, debian
    esac
}

# Get packages for a specific section and package type from distro module
get_packages_for_type() {
    local section_path="$1"
    local pkg_type="$2"

    # Try distro-provided package function first (preferred)
    if declare -f distro_get_packages >/dev/null 2>&1; then
        # distro_get_packages should print one package per line; capture and normalize
        mapfile -t tmp < <(distro_get_packages "$section_path" "$pkg_type" 2>/dev/null || true)
        mapfile -t packages < <(printf "%s\n" "${tmp[@]}" | sed '/^[[:space:]]*null[[:space:]]*$/d' | sed '/^[[:space:]]*$/d')
        printf "%s\n" "${packages[@]}"
    fi
}

# Remove duplicate packages while preserving order
deduplicate_packages() {
    local -a packages=("$@")
    if [ ${#packages[@]} -gt 1 ]; then
        declare -A _seen_pkgs
        local _deduped=()
        for pkg in "${packages[@]}"; do
            if [ -n "$pkg" ] && [ -z "${_seen_pkgs[$pkg]:-}" ]; then
                _deduped+=("$pkg")
                _seen_pkgs[$pkg]=1
            fi
        done
        # Replace packages with deduplicated list
        printf "%s\n" "${_deduped[@]}"
        unset _seen_pkgs
    else
        printf "%s\n" "${packages[@]}"
    fi
}

# Install a group of packages based on mode and package type (native, aur, flatpak, snap)
install_package_group() {
    local section_path="$1"
    local title="$2"
    local pkg_type="${3:-}"  # Optional: install only specific package type

    log_info "Processing package group: $title ($section_path)"

    # Get available package types for this distribution
    local pkg_types
    pkg_types=$(determine_package_types "$pkg_type")

    for type in $pkg_types; do
        # Get packages for this type using the refactored function
        local packages_str
        packages_str=$(get_packages_for_type "$section_path" "$type")
        mapfile -t packages <<< "$packages_str"

        if [ ${#packages[@]} -eq 0 ]; then
            continue
        fi

        # Deduplicate package list while preserving order
        packages_str=$(deduplicate_packages "${packages[@]}")
        mapfile -t packages <<< "$packages_str"

        if [ "$DRY_RUN" = true ]; then
            continue
        fi

        # Get installation command for this package type
        local install_cmd
        install_cmd=$(get_install_command "$type")
        if [ -z "$install_cmd" ]; then
            continue
        fi

        # Install packages based on type and track results
        local installed=() skipped=() failed=()
        case "$type" in
            flatpak)
                install_flatpak_packages "$install_cmd" packages installed skipped failed
                ;;
            native)
                install_native_packages "$install_cmd" packages installed skipped failed
                ;;
            *)
                install_other_packages "$install_cmd" packages installed failed
                ;;
        esac

        # Show installation summary for this package type
        show_package_summary "$title ($type)" installed failed
    done
}

# Install Flatpak packages with individual tracking
install_flatpak_packages() {
    local install_cmd="$1"
    local -n packages_ref="$2" installed_ref="$3" skipped_ref="$4" failed_ref="$5"

    for pkg in "${packages_ref[@]}"; do
        pkg="$(echo "$pkg" | xargs)"

        # Check if flatpak is already installed
        if flatpak list 2>/dev/null | grep -q "^${pkg}\s"; then
            skipped_ref+=("$pkg")
            continue
        fi

        if supports_gum; then
            if gum spin --spinner dot --title "" -- $install_cmd "$pkg" >/dev/null 2>&1; then
                installed_ref+=("$pkg")
            else
                failed_ref+=("$pkg")
            fi
        else
            if $install_cmd "$pkg" >/dev/null 2>&1; then
                installed_ref+=("$pkg")
            else
                failed_ref+=("$pkg")
            fi
        fi
    done
}

# Get installation command for specific package type
get_install_command() {
    local type="$1"
    local install_cmd=""

    case "$type" in
        native)
            if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
                install_cmd="DEBIAN_FRONTEND=noninteractive $PKG_INSTALL $PKG_NOCONFIRM"
            else
                install_cmd="$PKG_INSTALL $PKG_NOCONFIRM"
            fi
            ;;
        aur)
            if command -v yay >/dev/null 2>&1; then
                install_cmd="yay -S --noconfirm --removemake --nocleanafter"
            else
                log_error "yay not found. Please install yay first."
                return 1
            fi
            ;;
        flatpak)
            if ! command -v flatpak >/dev/null 2>&1; then
                if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
                    DEBIAN_FRONTEND=noninteractive $PKG_INSTALL $PKG_NOCONFIRM flatpak >/dev/null 2>&1 || true
                else
                    $PKG_INSTALL $PKG_NOCONFIRM flatpak >/dev/null 2>&1 || true
                fi
            fi
            # Add Flathub remote if not exists
            if command -v flatpak >/dev/null 2>&1; then
                flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
            fi
            install_cmd="flatpak install flathub -y"
            ;;
        snap)
            install_cmd="snap install"
            ;;
    esac

    echo "$install_cmd"
}

# Enable password asterisks for sudo prompts (visible feedback when typing)
enable_password_feedback() {
    log_info "Enabling password asterisks for sudo prompts..."

    # Check if already enabled
    if grep -q "Defaults pwfeedback" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
        log_info "Password feedback already enabled"
        return 0
    fi

    # Try to add to sudoers.d directory (safer than modifying main sudoers file)
    local sudoers_d_file="/etc/sudoers.d/linuxinstaller-pwfeedback"

    if [ -d "/etc/sudoers.d" ]; then
        echo "# Enable password feedback for better UX" > "$sudoers_d_file"
        echo "Defaults pwfeedback" >> "$sudoers_d_file"
        chmod 0440 "$sudoers_d_file"

        # Validate the sudoers file
        if visudo -c "$sudoers_d_file" >/dev/null 2>&1; then
            log_success "Password asterisks enabled via sudoers.d"
            log_info "Password feedback will show asterisks (*) when typing passwords"
            return 0
        else
            # Clean up invalid file
            rm -f "$sudoers_d_file"
            log_warn "Generated sudoers file failed validation"
        fi
    fi

    # Fallback: try to modify main sudoers file (riskier)
    log_warn "Attempting to modify main sudoers file (use with caution)..."
    if [ -f "/etc/sudoers" ] && ! grep -q "Defaults pwfeedback" "/etc/sudoers"; then
        # Create backup
        cp "/etc/sudoers" "/etc/sudoers.backup.$(date +%Y%m%d_%H%M%S)"

        echo "" >> "/etc/sudoers"
        echo "# Enable password feedback for better UX" >> "/etc/sudoers"
        echo "Defaults pwfeedback" >> "/etc/sudoers"

        # Validate the modified sudoers file
        if visudo -c "/etc/sudoers" >/dev/null 2>&1; then
            log_success "Password asterisks enabled via main sudoers file"
            log_info "Password feedback will show asterisks (*) when typing passwords"
        else
            # Restore backup
            mv "/etc/sudoers.backup.$(date +%Y%m%d_%H%M%S)" "/etc/sudoers"
            log_error "Failed to modify sudoers file - backup restored"
            log_error "Password feedback not enabled"
            return 1
        fi
    else
        log_warn "Could not enable password feedback"
        log_info "You can manually enable it by adding 'Defaults pwfeedback' to /etc/sudoers"
        return 1
    fi
}

# Install native packages in batch for better dependency handling
install_native_packages() {
    local install_cmd="$1"
    local -n packages_ref="$2" installed_ref="$3" skipped_ref="$4" failed_ref="$5"

    # Collect all packages to install (batch installation)
    local packages_to_install=()

    for pkg in "${packages_ref[@]}"; do
        pkg="$(echo "$pkg" | xargs)"

        # Resolve package name for current distro
        local resolved_pkg
        resolved_pkg="$(resolve_package_name "$pkg")"

        # If resolved_pkg is empty, skip this package (removed for this distro)
        if [ -z "$resolved_pkg" ]; then
            continue
        fi

        # Check if all resolved packages are installed
        local all_installed=true
        local check_pkg
        for check_pkg in $resolved_pkg; do
            if ! is_package_installed "$check_pkg"; then
                all_installed=false
                break
            fi
        done

        if [ "$all_installed" = true ]; then
            skipped_ref+=("$pkg")
            continue
        fi

        # Add to batch installation list
        packages_to_install+=("$resolved_pkg")
    done

    # Check if any packages need to be installed
    if [ ${#packages_to_install[@]} -eq 0 ]; then
        return
    fi

    # Install all packages in one batch (better for dependencies like adb/fastboot)
    local install_status=0
    local batch_title="Installing ${#packages_to_install[@]} package(s)"

    if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
        if supports_gum; then
            if ! gum spin --spinner dot --title "$batch_title" -- \
                 DEBIAN_FRONTEND=noninteractive $PKG_INSTALL $PKG_NOCONFIRM ${packages_to_install[@]} >/dev/null 2>&1; then
                install_status=1
            fi
        else
            if ! DEBIAN_FRONTEND=noninteractive $PKG_INSTALL $PKG_NOCONFIRM ${packages_to_install[@]} >/dev/null 2>&1; then
                install_status=1
            fi
        fi
    else
        if supports_gum; then
            if ! gum spin --spinner dot --title "$batch_title" -- $install_cmd ${packages_to_install[@]} >/dev/null 2>&1; then
                install_status=1
            fi
        else
            if ! $install_cmd ${packages_to_install[@]} >/dev/null 2>&1; then
                install_status=1
            fi
        fi
    fi

    # Track which packages succeeded/failed
    for pkg in "${packages_ref[@]}"; do
        pkg="$(echo "$pkg" | xargs)"
        local resolved_pkg
        resolved_pkg="$(resolve_package_name "$pkg")"
        if [ -n "$resolved_pkg" ]; then
            if [ $install_status -eq 0 ]; then
                installed_ref+=("$pkg")
            else
                failed_ref+=("$pkg")
            fi
        fi
    done
}

# Install non-native packages (AUR, Snap) individually
install_other_packages() {
    local install_cmd="$1"
    local -n packages_ref="$2" installed_ref="$3" failed_ref="$4"

    for pkg in "${packages_ref[@]}"; do
        pkg="$(echo "$pkg" | xargs)"

        if supports_gum; then
            if gum spin --spinner dot --title "" -- $install_cmd "$pkg" >/dev/null 2>&1; then
                installed_ref+=("$pkg")
            else
                failed_ref+=("$pkg")
            fi
        else
            if $install_cmd "$pkg" >/dev/null 2>&1; then
                installed_ref+=("$pkg")
            else
                failed_ref+=("$pkg")
            fi
        fi
    done
}

# Show package installation summary
show_package_summary() {
    local title="$1"
    local -n installed_ref="$2" failed_ref="$3"

    if [ ${#installed_ref[@]} -gt 0 ] || [ ${#failed_ref[@]} -gt 0 ]; then
        if supports_gum; then
            gum style "$title" --margin "0 2" --foreground "$GUM_BODY_FG" --bold
        else
            echo -e "\n${WHITE}$title${RESET}"
        fi

        if [ ${#installed_ref[@]} -gt 0 ]; then
            if supports_gum; then
                gum style "✓ ${installed_ref[*]}" --margin "0 4" --foreground "$GUM_SUCCESS_FG"
            else
                echo -e "${GREEN}✓ ${installed[*]}${RESET}"
            fi

            if [ ${#failed_ref[@]} -gt 0 ]; then
                if supports_gum; then
                    gum style "✗ Failed: ${failed_ref[*]}" --margin "0 4" --foreground "$GUM_ERROR_FG"
                else
                    echo -e "${RED}✗ Failed: ${failed_ref[*]}${RESET}"
                fi
            fi
        fi
    fi
}

# --- User Shell & Config Setup ---
# Configure user's shell environment and dotfiles

# Configure zsh shell and user config files (zshrc, starship, fastfetch)
# This function sets up a modern, productive shell environment with:
# - Zsh as the default shell with autosuggestions and syntax highlighting
# - Starship prompt for beautiful, informative command prompts
# - Fastfetch for system information display
configure_user_shell_and_configs() {
    step "Configuring Zsh and user-level configs (zsh, starship, fastfetch)"

    # Determine target user and their home directory
    local target_user="${SUDO_USER:-$USER}"
    local home_dir

    # Safely get user's home directory without using eval
    if [ "$target_user" = "root" ]; then
        home_dir="/root"
    else
        # Use getent to safely get user information
        home_dir=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
        if [ -z "$home_dir" ] || [ ! -d "$home_dir" ]; then
            # Fallback: try to get home from environment
            home_dir="${HOME:-/home/$target_user}"
            if [ ! -d "$home_dir" ]; then
                log_warn "Could not determine home directory for user $target_user"
                log_warn "Shell configuration will be skipped"
                return 1
            fi
        fi
    fi
    local cfg_dir="$CONFIGS_DIR/$DISTRO_ID"

    local zsh_packages=(zsh zsh-autosuggestions zsh-syntax-highlighting starship fastfetch)
    local installed=()
    local skipped=()
    local failed=()

    for pkg in "${zsh_packages[@]}"; do
        if is_package_installed "$pkg"; then
            skipped+=("$pkg")
            continue
        fi

        if ! package_exists "$pkg"; then
            failed+=("$pkg")
            continue
        fi

        if supports_gum; then
            if gum spin --spinner dot --title "" -- install_pkg "$pkg" >/dev/null 2>&1; then
                installed+=("$pkg")
            else
                failed+=("$pkg")
            fi
        else
            if install_pkg "$pkg" >/dev/null 2>&1; then
                installed+=("$pkg")
            else
                failed+=("$pkg")
            fi
        fi
    done

    # Deploy configuration files with proper ownership
    # .zshrc - Zsh shell configuration with aliases, functions, and settings
    if [ -f "$cfg_dir/.zshrc" ]; then
        log_info "Installing .zshrc configuration..."
        cp -a "$cfg_dir/.zshrc" "$home_dir/.zshrc" || {
            log_warn "Failed to copy .zshrc"
            return 1
        }
        chown "$target_user:$target_user" "$home_dir/.zshrc" || {
            log_warn "Failed to set ownership on .zshrc"
        }
        log_success "Zsh configuration deployed"
    fi

    # starship.toml - Modern, fast, and customizable prompt
    if [ -f "$cfg_dir/starship.toml" ]; then
        log_info "Installing Starship prompt configuration..."
        mkdir -p "$home_dir/.config"
        cp -a "$cfg_dir/starship.toml" "$home_dir/.config/starship.toml" || {
            log_warn "Failed to copy starship.toml"
            return 1
        }
        chown "$target_user:$target_user" "$home_dir/.config/starship.toml" || {
            log_warn "Failed to set ownership on starship.toml"
        }
        log_success "Starship prompt configuration deployed"
    fi

    # config.jsonc - Fastfetch system information display configuration
    if [ -f "$cfg_dir/config.jsonc" ]; then
        log_info "Installing Fastfetch configuration..."
        mkdir -p "$home_dir/.config/fastfetch"
        cp -a "$cfg_dir/config.jsonc" "$home_dir/.config/fastfetch/config.jsonc" || {
            log_warn "Failed to copy fastfetch config"
            return 1
        }
        chown -R "$target_user:$target_user" "$home_dir/.config/fastfetch" || {
            log_warn "Failed to set ownership on fastfetch config"
        }
        log_success "Fastfetch configuration deployed"
    fi

    log_success "Shell configuration completed successfully"
    return 0
}

# --- Final Cleanup ---

# Clean up temporary helper packages (gum) installed by the script
final_cleanup() {
    step "Final cleanup and optional helper removal"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Final cleanup skipped."
        return
    fi

    local remove_list=()
    [ "${GUM_INSTALLED_BY_SCRIPT:-false}" = true ] && remove_list+=("gum")

    if [ ${#remove_list[@]} -eq 0 ]; then
        log_info "No temporary helper packages were installed by the script."
        return
    fi

    # Prompt the user whether to remove them (interactive)
    if supports_gum; then
        gum style "Temporary helper packages detected:" \
                 --margin "0 2" --foreground "$GUM_PRIMARY_FG" --bold
        gum style "${remove_list[*]}" --margin "0 4" --foreground "$GUM_BODY_FG"
            if gum confirm --default=false "Remove these helper packages now?"; then
            for pkg in "${remove_list[@]}"; do
                log_info "Removing $pkg..."
                if remove_pkg "$pkg"; then
                    log_success "Removed $pkg via package manager"
                else
                    # Fallback: try removing binary placed under /usr/local/bin
                    if [ -f "/usr/local/bin/$pkg" ]; then
                        rm -f "/usr/local/bin/$pkg" && log_success "Removed /usr/local/bin/$pkg" || log_warn "Failed to remove /usr/local/bin/$pkg"
                    else
                        log_warn "Failed to remove $pkg via package manager"
                    fi
                fi
            done
        else
            log_info "Keeping helper packages as requested by the user."
        fi
    else
        echo "Temporary helper packages detected: ${remove_list[*]}"
        read -r -p "Remove these helper packages now? [y/N]: " resp
        if [[ "$resp" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            for pkg in "${remove_list[@]}"; do
                log_info "Removing $pkg..."
                if remove_pkg "$pkg"; then
                    log_success "Removed $pkg via package manager"
                else
                    if [ -f "/usr/local/bin/$pkg" ]; then
                        rm -f "/usr/local/bin/$pkg" && log_success "Removed /usr/local/bin/$pkg" || log_warn "Failed to remove /usr/local/bin/$pkg"
                    else
                        log_warn "Failed to remove $pkg via package manager"
                    fi
                fi
            done
        fi
    fi
}
# --- Main Execution Flow ---
# The main installation workflow with clear phases

# Phase 1: Parse command-line arguments and validate environment
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--help) show_help ;;
    -v|--verbose) VERBOSE=true ;;
    -d|--dry-run) DRY_RUN=true ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# 2. Environment Setup
# We must detect distro first to know how to install prerequisites
# Detect distribution and desktop environment with error handling
if ! detect_distro; then
    log_error "Failed to detect your Linux distribution!"
    log_error "LinuxInstaller supports: Arch Linux, Fedora, Debian, and Ubuntu."
    log_error "Please check that you're running a supported distribution."
    log_error "You can check your distribution with: cat /etc/os-release"
    exit 1
fi

if ! detect_de; then
    log_warn "Could not detect desktop environment - some features may not work optimally."
    log_info "You can continue, but desktop-specific configurations may be skipped."
fi

# Source distro module early so it can provide package lists via `distro_get_packages()`
# Source distro-specific configuration with error handling
case "$DISTRO_ID" in
    "arch")
        if [ -f "$SCRIPTS_DIR/arch_config.sh" ]; then
            source "$SCRIPTS_DIR/arch_config.sh"
        else
            log_error "Arch Linux configuration module not found!"
            log_error "Please ensure all files are present in the scripts/ directory."
            exit 1
        fi
        ;;
    "fedora")
        if [ -f "$SCRIPTS_DIR/fedora_config.sh" ]; then
            source "$SCRIPTS_DIR/fedora_config.sh"
        else
            log_error "Fedora configuration module not found!"
            log_error "Please ensure all files are present in the scripts/ directory."
            exit 1
        fi
        ;;
    "debian"|"ubuntu")
        if [ -f "$SCRIPTS_DIR/debian_config.sh" ]; then
            source "$SCRIPTS_DIR/debian_config.sh"
        else
            log_error "Debian/Ubuntu configuration module not found!"
            log_error "Please ensure all files are present in the scripts/ directory."
            exit 1
        fi
        ;;
    *)
        log_error "Unsupported distribution: $DISTRO_ID"
        log_error "LinuxInstaller currently supports: Arch Linux, Fedora, Debian, Ubuntu."
        exit 1
        ;;
esac

# programs.yaml fallback removed; package lists are provided by distro modules (via distro_get_packages())

# Bootstrap UI tools
bootstrap_tools

# Phase 3: Installation Mode Selection
# Determine installation mode based on user interaction or defaults
clear
if [ -t 0 ]; then
    # Interactive terminal - show beautiful menu
    if [ "$DRY_RUN" = false ]; then
        show_menu
    else
        log_warn "Dry-Run Mode Active: No changes will be applied."
        log_info "Showing menu for preview purposes only."
        show_menu
    fi
else
    # Non-interactive mode (CI, scripts, pipes)
    # Only set a default mode if none exists to avoid overriding explicit settings
    if [ -z "${INSTALL_MODE:-}" ]; then
        export INSTALL_MODE="${INSTALL_MODE:-standard}"
        log_info "Non-interactive: defaulting to install mode: $INSTALL_MODE"
    fi
fi

# Phase 4: Core Installation Execution
# Execute the main installation workflow in logical steps

# Step: System Update
step "Updating System Repositories"
if [ "$DRY_RUN" = false ]; then
    update_system
fi

# Step: Enable password feedback for better UX
step "Enabling password feedback"
if [ "$DRY_RUN" = false ]; then
    enable_password_feedback
fi

# Step: Run Distro System Preparation (install essentials, etc.)
# Run distro-specific system preparation early so essential helpers are present
# before package installation and mark the step complete to avoid duplication.
# Note: For Arch, this includes pacman configuration via configure_pacman_arch
DSTR_PREP_FUNC="${DISTRO_ID}_system_preparation"
DSTR_PREP_STEP="${DSTR_PREP_FUNC}"
if declare -f "$DSTR_PREP_FUNC" >/dev/null 2>&1; then
    step "Running system preparation for $DISTRO_ID"
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would run $DSTR_PREP_FUNC"
    else
        if ! "$DSTR_PREP_FUNC"; then
            log_warn "$DSTR_PREP_FUNC reported issues"
        fi
    fi
fi

# Step: Install Packages based on Mode
step "Installing Packages ($INSTALL_MODE)"

# Install Base packages (native only) - Standard/Minimal/Server
install_package_group "$INSTALL_MODE" "Base System" "native"

# Install distro-provided 'essential' group (native only)
install_package_group "essential" "Essential Packages" "native"

# Install Desktop Environment Specific Packages (native only)
if [[ -n "${XDG_CURRENT_DESKTOP:-}" && "$INSTALL_MODE" != "server" ]]; then
    DE_KEY=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
    if [[ "$DE_KEY" == *"kde"* ]]; then DE_KEY="kde"; fi
    if [[ "$DE_KEY" == *"gnome"* ]]; then DE_KEY="gnome"; fi

    step "Installing Desktop Environment Packages ($DE_KEY)"
    install_package_group "$DE_KEY" "$XDG_CURRENT_DESKTOP Environment" "native"
fi

# Install AUR packages for Arch Linux
if [ "$DISTRO_ID" == "arch" ]; then
    install_package_group "$INSTALL_MODE" "AUR Packages" "aur"
fi

# Install COPR/eza package for Fedora
if [ "$DISTRO_ID" == "fedora" ]; then
    step "Installing COPR/eza Package"
    if [ "$DRY_RUN" = false ]; then
        if command -v dnf >/dev/null; then
            # Install eza from COPR
            if dnf copr enable -y eza-community/eza >/dev/null 2>&1; then
                install_pkg eza
                log_success "Enabled eza COPR repository and installed eza"
            else
                log_warn "Failed to enable eza COPR repository"
            fi
        else
            log_warn "dnf not found, skipping eza installation"
        fi
    fi
fi

# Install Flatpak packages for all sections (Base, Desktop, Gaming)
install_package_group "$INSTALL_MODE" "Flatpak Packages" "flatpak"

if [[ -n "${XDG_CURRENT_DESKTOP:-}" && "$INSTALL_MODE" != "server" ]]; then
    install_package_group "$DE_KEY" "Flatpak Packages" "flatpak"
fi

# Handle Custom Addons if any (rudimentary handling)
if [[ "${CUSTOM_GROUPS:-}" == *"Gaming"* ]]; then
    install_package_group "gaming" "Gaming Suite" "native"
    install_package_group "gaming" "Gaming Suite" "flatpak"
fi

# Use to gaming decision made at menu time (if applicable)
if { [ "$INSTALL_MODE" == "standard" ] || [ "$INSTALL_MODE" == "minimal" ]; } && [ -z "${CUSTOM_GROUPS:-}" ]; then
    if [ "${INSTALL_GAMING:-false}" = "true" ]; then
        # Gaming packages already installed above (native and flatpak)
        log_info "Gaming packages already installed in previous steps"
    fi
fi

# ------------------------------------------------------------------
# Wake-on-LAN auto-configuration step
#
# If wakeonlan integration module was sourced above (wakeonlan_main_config),
# run it now (unless we're in DRY_RUN). In DRY_RUN show status instead.
# This keeps the step idempotent and consistent with the installer flow.
# ------------------------------------------------------------------
if declare -f wakeonlan_main_config >/dev/null 2>&1; then
    step "Configuring Wake-on-LAN (Ethernet)"

    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "[DRY-RUN] Would auto-configure Wake-on-LAN for wired interfaces"

        # Try to show what would be done by printing helper status output (if present)
        WOL_HELPER="$(cd "$SCRIPT_DIR/.." && pwd)/Scripts/wakeonlan.sh"
        if [ -x "$WOL_HELPER" ]; then
            bash "$WOL_HELPER" --status 2>&1 | sed 's/^/  /'
        else
            log_warn "Wake-on-LAN helper not found at $WOL_HELPER"
        fi
    else
        # Non-dry run: call the integration entrypoint which handles enabling
        wakeonlan_main_config || log_warn "wakeonlan_main_config reported issues"
    fi
fi

# Step: Run Distribution-Specific Configuration
# This replaces the numbered scripts with unified distribution-specific modules
# Note: Distro configs were already sourced earlier for package lists
if [ "$DRY_RUN" = false ]; then
    step "Running Distribution-Specific Configuration"

    case "$DISTRO_ID" in
        "arch")
            if declare -f arch_main_config >/dev/null 2>&1; then
                arch_main_config
            else
                log_warn "Arch configuration module not found"
            fi
            ;;
        "fedora")
            if declare -f fedora_main_config >/dev/null 2>&1; then
                fedora_main_config
            else
                log_warn "Fedora configuration module not found"
            fi
            ;;
        "debian"|"ubuntu")
            if declare -f debian_main_config >/dev/null 2>&1; then
                debian_main_config
            else
                log_warn "Debian/Ubuntu configuration module not found"
            fi
            ;;
        *)
            log_warn "No specific configuration module for $DISTRO_ID"
            ;;
    esac

    # Step: Configure user shell and config files (universal)
    step "Configuring User Shell and Configuration Files"
    if [ "$DRY_RUN" = false ]; then
        configure_user_shell_and_configs
    fi
fi

# Step: Run Desktop Environment Configuration
if [ "$INSTALL_MODE" != "server" ]; then
    step "Configuring Desktop Environment"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure desktop environment: ${XDG_CURRENT_DESKTOP:-None}"
    else
        case "${XDG_CURRENT_DESKTOP:-}" in
            *"KDE"*)
                if [ -f "$SCRIPTS_DIR/kde_config.sh" ]; then
                    source "$SCRIPTS_DIR/kde_config.sh"
                    kde_main_config
                else
                    log_warn "KDE configuration module not found"
                fi
                ;;
            *"GNOME"*)
                if [ -f "$SCRIPTS_DIR/gnome_config.sh" ]; then
                    source "$SCRIPTS_DIR/gnome_config.sh"
                    gnome_main_config
                else
                    log_warn "GNOME configuration module not found"
                fi
                ;;
            *)
                log_info "No specific desktop environment configuration for ${XDG_CURRENT_DESKTOP:-None}"
                ;;
        esac
    fi
fi

# Step: Run Security Configuration
step "Configuring Security Features"

if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would configure security features"
else
    if [ -f "$SCRIPTS_DIR/security_config.sh" ]; then
        source "$SCRIPTS_DIR/security_config.sh"
        security_main_config
    else
        log_warn "Security configuration module not found"
    fi
fi

# Step: Run Performance Optimization
step "Applying Performance Optimizations"

if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would apply performance optimizations"
else
    if [ -f "$SCRIPTS_DIR/performance_config.sh" ]; then
        source "$SCRIPTS_DIR/performance_config.sh"
        performance_main_config
    else
        log_warn "Performance configuration module not found"
    fi
fi

# Step: Run Maintenance Setup
step "Setting up Maintenance Tools"

if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would set up maintenance tools"
else
    if [ -f "$SCRIPTS_DIR/maintenance_config.sh" ]; then
        source "$SCRIPTS_DIR/maintenance_config.sh"
        maintenance_main_config
    else
        log_warn "Maintenance configuration module not found"
    fi
fi

# Step: Run Gaming Configuration (if applicable)
if [ "$INSTALL_MODE" != "server" ] && [ "${INSTALL_GAMING:-false}" = "true" ]; then
    step "Configuring Gaming Environment"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure gaming environment"
    else
        if [ -f "$SCRIPTS_DIR/gaming_config.sh" ]; then
            source "$SCRIPTS_DIR/gaming_config.sh"
            gaming_main_config
        else
            log_warn "Gaming configuration module not found"
        fi
    fi
fi

# Phase 5: Installation Finalization and Cleanup
step "Finalizing Installation"

if [ "$DRY_RUN" = false ]; then
    # Clean up temporary files and helpers
    final_cleanup
fi

# Detect system info for installation summary (if power_config available)
if declare -f detect_system_info >/dev/null 2>&1; then
    detect_system_info
fi

# Source and show installation summary with reboot prompt
if [ -f "$SCRIPTS_DIR/installation_summary.sh" ]; then
    source "$SCRIPTS_DIR/installation_summary.sh"
    # Show comprehensive installation summary
    show_installation_summary
else
    prompt_reboot
fi
