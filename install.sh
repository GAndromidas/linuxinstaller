#!/bin/bash
set -uo pipefail

# =============================================================================
# TESTING & VALIDATION FRAMEWORK
# =============================================================================

# Run comprehensive pre-installation tests
run_pre_install_checks() {
    log_info "Running pre-installation validation checks..."

    local checks_passed=0
    local total_checks=0

    # Test 1: Distribution detection
    ((total_checks++))
    if [ -n "${DISTRO_ID:-}" ]; then
        log_success "✓ Distribution detected: $DISTRO_ID"
        ((checks_passed++))
    else
        log_error "✗ Failed to detect distribution"
    fi

    # Test 2: Internet connectivity
    ((total_checks++))
    if check_internet; then
        log_success "✓ Internet connection confirmed"
        ((checks_passed++))
    else
        log_error "✗ No internet connection"
    fi

    # Test 3: Package manager availability
    ((total_checks++))
    # Extract just the command name from PKG_INSTALL (remove arguments)
    pkg_command=$(echo "$PKG_INSTALL" | awk '{print $1}')
    if command -v "$pkg_command" >/dev/null 2>&1; then
        log_success "✓ Package manager available: $PKG_INSTALL"
        ((checks_passed++))
    else
        log_error "✗ Package manager not found: $pkg_command"
    fi

    # Test 4: Root privileges
    ((total_checks++))
    if [ "$EUID" -eq 0 ]; then
        log_success "✓ Running with root privileges"
        ((checks_passed++))
    else
        log_error "✗ Root privileges required"
    fi

    # Test 5: Disk space check
    ((total_checks++))
    local available_space
    available_space=$(df / | tail -1 | awk '{print $4}')
    if [ "$available_space" -gt 1048576 ]; then  # 1GB in KB
        log_success "✓ Sufficient disk space available"
        ((checks_passed++))
    else
        log_error "✗ Insufficient disk space (need at least 1GB free)"
    fi



    # Summary
    log_info "Pre-installation checks: $checks_passed/$total_checks passed"

    if [ $checks_passed -eq $total_checks ]; then
        log_success "🎉 All pre-installation checks passed!"
        return 0
    else
        log_error "❌ Some pre-installation checks failed. Please resolve issues before continuing."
        return 1
    fi
}

# Check if running as root, re-exec with sudo if not
if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# LinuxInstaller v1.0 - Main installation script

# Show LinuxInstaller ASCII art banner (distribution-specific colors)
show_linuxinstaller_ascii() {
    clear

    # Set color based on detected distribution
    local ascii_color="${CYAN}"  # Default cyan
    if [ "${DISTRO_ID:-}" = "fedora" ] || [ "${DISTRO_ID:-}" = "arch" ]; then
        ascii_color="${BLUE}"  # Blue for Fedora and Arch
    elif [ "${DISTRO_ID:-}" = "debian" ]; then
        ascii_color="${RED}"   # Red for Debian
    elif [ "${DISTRO_ID:-}" = "ubuntu" ]; then
        ascii_color="\033[38;5;208m"  # Orange for Ubuntu (ANSI 208)
    fi

    echo -e "${ascii_color}"
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

    # Interactive menu for selection
    if [ -t 1 ]; then
        echo ""
        echo "Choose your preferred LinuxInstaller setup:"
        echo ""

        # Simple text menu with select
        select choice in "Standard - Complete setup" "Minimal - Essential tools" "Server - Headless config" "Exit"; do
            case "$choice" in
                "Standard - Complete setup")
                    export INSTALL_MODE="standard"
                    display_success "Standard mode selected"
                    break ;;
                "Minimal - Essential tools")
                    export INSTALL_MODE="minimal"
                    display_success "Minimal mode selected"
                    break ;;
                "Server - Headless config")
                    export INSTALL_MODE="server"
                    display_success "Server mode selected"
                    break ;;
                "Exit")
                    display_info "Goodbye! 👋"
                    exit 0 ;;
                *)
                    echo "Invalid choice, please select 1-4" ;;
            esac
        done
        export INSTALL_GAMING=false
    else
        # Non-interactive defaults
        export INSTALL_MODE="${INSTALL_MODE:-standard}"
        export INSTALL_GAMING=false
    fi

    friendly=""
    case "$INSTALL_MODE" in
        standard) friendly="Standard - Complete setup" ;;
        minimal)  friendly="Minimal - Essential tools" ;;
        server)   friendly="Server - Headless config" ;;
        *)        friendly="$INSTALL_MODE" ;;
    esac

    display_success "Selected: $friendly"
}

# Color variables (cyan theme)
CYAN='\033[0;36m'
LIGHT_CYAN='\033[1;36m'
BLUE='\033[0;34m'
RESET='\033[0m'

# --- Configuration & Paths ---
# Determine script location and derive important directories
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"  # Absolute path to this script
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd || echo "/tmp")"  # Directory containing this script
CONFIGS_DIR="$SCRIPT_DIR/configs"    # Distribution-specific configuration files
SCRIPTS_DIR="$SCRIPT_DIR/scripts"    # Modular script components

# Detect if we're running as a one-liner (script content piped to bash)
# Skip detection if NO_ONELINER env var is set (for downloaded instances)
if [ "${NO_ONELINER:-}" != "true" ] && ([ ! -f "$SCRIPT_PATH" ] || [ ! -d "$SCRIPTS_DIR" ] || [ ! -d "$CONFIGS_DIR" ]); then
    echo "🔄 Detected one-liner installation. Downloading full LinuxInstaller repository..."

    # Create temporary directory for download
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # Try git first
    if command -v git >/dev/null 2>&1; then
        if git clone --depth 1 https://github.com/GAndromidas/linuxinstaller.git . >/dev/null 2>&1; then
            echo "✓ Repository downloaded successfully"
            NO_ONELINER=true exec bash "$TEMP_DIR/install.sh" "$@"
        fi
    fi

    # Fallback: download as tarball
    echo "⚠️  Git not available or failed, trying tarball download..."
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL https://github.com/GAndromidas/linuxinstaller/archive/main.tar.gz -o "$TEMP_DIR/repo.tar.gz" 2>/dev/null; then
            if tar -xzf "$TEMP_DIR/repo.tar.gz" --strip-components=1 -C "$TEMP_DIR" 2>/dev/null; then
                rm "$TEMP_DIR/repo.tar.gz"
                echo "✓ Repository downloaded successfully"
                NO_ONELINER=true exec bash "$TEMP_DIR/install.sh" "$@"
            fi
        fi
    fi

    echo "❌ Failed to download LinuxInstaller repository"
    echo "Please try: git clone https://github.com/GAndromidas/linuxinstaller.git"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"  # Directory containing this script
CONFIGS_DIR="$SCRIPT_DIR/configs"    # Distribution-specific configuration files
SCRIPTS_DIR="$SCRIPT_DIR/scripts"    # Modular script components

# Verify we have the required directory structure
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "FATAL ERROR: Scripts directory not found in $SCRIPT_DIR"
    echo "This indicates a corrupted or incomplete installation."
    echo "Please re-download LinuxInstaller from the official repository:"
    echo "  git clone https://github.com/GAndromidas/linuxinstaller.git"
    exit 1
fi

# --- Source Helpers ---
# We need distro detection and common utilities immediately
# Source required helper scripts with better error handling
if [ -f "$SCRIPTS_DIR/common.sh" ]; then
    source "$SCRIPTS_DIR/common.sh"
else
    echo "FATAL ERROR: Required file 'common.sh' not found in $SCRIPTS_DIR"
    echo "This indicates a corrupted or incomplete installation."
    echo "Please re-download LinuxInstaller from the official repository:"
    echo "  git clone https://github.com/GAndromidas/linuxinstaller.git"
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

# --- Configuration Validation ---
# Validate configuration files now that helpers are sourced
config_valid=true
for config_file in "$SCRIPTS_DIR"/*.sh; do
    if [ -f "$config_file" ]; then
        if ! validate_config "$config_file" "bash"; then
            config_valid=false
            break
        fi
    fi
done

if [ "${config_valid:-true}" = false ]; then
    log_error "✗ Configuration file validation failed"
    exit 1
fi

# --- Global Variables ---
# Runtime flags and configuration
VERBOSE=false           # Enable detailed logging output
DRY_RUN=false          # Preview mode - show what would be done without changes
TOTAL_STEPS=0          # Total number of installation steps
CURRENT_STEP=0         # Current step counter for progress tracking
INSTALL_MODE="standard" # Installation mode: standard, minimal, or server
IS_VIRTUAL_MACHINE=false # Whether we're running in a virtual machine

# Helper tracking
GUM_INSTALLED_BY_SCRIPT=false  # Track if we installed gum to clean it up later

# --- State Management ---
# Track installation progress and state for rollback capabilities
declare -A INSTALL_STATE
INSTALL_STATE_FILE="/tmp/linuxinstaller.state"
LOG_FILE="/var/log/linuxinstaller.log"

# --- Progress Tracking ---
# Track installation progress with visual indicators
PROGRESS_TOTAL=13
PROGRESS_CURRENT=0

# --- Helper Functions ---
# Utility functions for script operation and user interaction

# Detect if running in a virtual machine
detect_virtual_machine() {
    if [ -f /proc/cpuinfo ]; then
        grep -qi "hypervisor\|vmware\|virtualbox\|kvm\|qemu\|xen" /proc/cpuinfo && return 0
    fi
    if [ -f /sys/class/dmi/id/product_name ]; then
        grep -qi "virtual\|vmware\|virtualbox\|kvm\|qemu\|xen" /sys/class/dmi/id/product_name && return 0
    fi
    if [ -f /sys/class/dmi/id/sys_vendor ]; then
        grep -qi "vmware\|virtualbox\|kvm\|qemu\|xen\|innotek" /sys/class/dmi/id/sys_vendor && return 0
    fi
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        systemd-detect-virt --quiet && return 0
    fi
    return 1
}

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
        if [ "$DISTRO_ID" = "arch" ]; then
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
    local group_name="$1"
    local description="$2"
    local package_type="$3"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would install $group_name ($package_type)"
        return 0
    fi

    log_info "Installing $description..."

    # Get packages for this group and type
    local packages
    mapfile -t packages < <(distro_get_packages "$group_name" "$package_type")

    if [ ${#packages[@]} -eq 0 ]; then
        log_info "No packages to install for $group_name ($package_type)"
        return 0
    fi

    # Check dependencies before installation (for native packages)
    if [ "$package_type" = "native" ]; then
        if ! check_dependencies "${packages[@]}"; then
            log_warn "Dependency check failed for $group_name, but continuing..."
        fi
    fi

    # Deduplicate package list while preserving order
    packages_str=$(deduplicate_packages "${packages[@]}")
    mapfile -t packages <<< "$packages_str"

    if [ "$DRY_RUN" = true ]; then
        return 0
    fi

    # Get installation command for this package type
    local install_cmd
    install_cmd=$(get_install_command "$package_type")
    if [ -z "$install_cmd" ]; then
        return 1
    fi

    # Install packages based on type and track results
    local installed=() skipped=() failed=()
    case "$package_type" in
        flatpak)
            install_flatpak_packages "$install_cmd" packages installed skipped failed
            ;;
        native|aur|snap)
            install_native_packages "$install_cmd" packages installed skipped failed
            ;;
        *)
            install_other_packages "$install_cmd" packages installed failed
            ;;
    esac

    # Show installation summary for this package type
    show_package_summary "$description ($package_type)" installed failed
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

        echo "• Installing $pkg"
        if $install_cmd "$pkg" >/dev/null 2>&1; then
            installed_ref+=("$pkg")
        else
            failed_ref+=("$pkg")
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
                install_cmd="yay -S --noconfirm --removemake"
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

# Smart service enabling for installed packages
enable_installed_services() {
    step "Enabling Services for Installed Packages"

    local services_enabled=0
    local services_skipped=0

    # Bluetooth service
    if is_package_installed "bluez" 2>/dev/null || is_package_installed "bluez-utils" 2>/dev/null; then
        if systemctl enable --now bluetooth >/dev/null 2>&1; then
            log_success "Bluetooth service enabled"
            ((services_enabled++))
        else
            log_warn "Failed to enable bluetooth service"
        fi
    else
        ((services_skipped++))
    fi

    # SSH service
    if is_package_installed "openssh" 2>/dev/null; then
        if systemctl enable --now sshd >/dev/null 2>&1; then
            log_success "SSH service enabled"
            ((services_enabled++))
        elif systemctl enable --now ssh >/dev/null 2>&1; then
            log_success "SSH service enabled"
            ((services_enabled++))
        else
            log_warn "Failed to enable SSH service"
        fi
    else
        ((services_skipped++))
    fi

    # KDE Connect service
    if is_package_installed "kdeconnect" 2>/dev/null; then
        if systemctl enable --now kdeconnectd >/dev/null 2>&1; then
            log_success "KDE Connect service enabled"
            ((services_enabled++))
        else
            log_warn "Failed to enable KDE Connect service"
        fi
    else
        ((services_skipped++))
    fi

    # RustDesk service (if installed)
    if is_package_installed "rustdesk" 2>/dev/null; then
        # RustDesk might not have a systemd service, check for it
        if systemctl list-unit-files | grep -q rustdesk; then
            if systemctl enable --now rustdesk >/dev/null 2>&1; then
                log_success "RustDesk service enabled"
                ((services_enabled++))
            else
                log_warn "Failed to enable RustDesk service"
            fi
        else
            log_info "RustDesk installed but no systemd service found"
            ((services_skipped++))
        fi
    else
        ((services_skipped++))
    fi

    # NetworkManager (if installed and not already enabled)
    if is_package_installed "networkmanager" 2>/dev/null || is_package_installed "network-manager" 2>/dev/null; then
        if ! systemctl is-enabled NetworkManager >/dev/null 2>&1; then
            if systemctl enable NetworkManager >/dev/null 2>&1; then
                log_success "NetworkManager service enabled"
                ((services_enabled++))
            else
                log_warn "Failed to enable NetworkManager service"
            fi
        else
            log_info "NetworkManager already enabled"
        fi
    fi

    # Snap service (for Ubuntu/Snap packages)
    if is_package_installed "snapd" 2>/dev/null; then
        if systemctl enable --now snapd >/dev/null 2>&1; then
            log_success "Snap service enabled"
            ((services_enabled++))
        fi
        if systemctl enable --now snapd.socket >/dev/null 2>&1; then
            log_success "Snap socket enabled"
        fi
    fi

    # Docker service
    if is_package_installed "docker" 2>/dev/null || is_package_installed "docker.io" 2>/dev/null; then
        if systemctl enable --now docker >/dev/null 2>&1; then
            log_success "Docker service enabled"
            ((services_enabled++))
        else
            log_warn "Failed to enable Docker service"
        fi
    fi

    # Flatpak service (if available)
    if command -v flatpak >/dev/null 2>&1; then
        # Flatpak doesn't typically need systemd services, but check for any
        if systemctl list-unit-files | grep -q flatpak; then
            if systemctl enable --now flatpak >/dev/null 2>&1; then
                log_success "Flatpak service enabled"
                ((services_enabled++))
            fi
        fi
    fi

    # Report results
    if [ $services_enabled -gt 0 ]; then
        log_success "Enabled $services_enabled services for installed packages"
    fi

    if [ $services_skipped -gt 0 ]; then
        log_info "Skipped $services_skipped services (packages not installed)"
    fi

    return 0
}

# Install native packages individually for clean output
install_native_packages() {
    local install_cmd="$1"
    local -n packages_ref="$2" installed_ref="$3" skipped_ref="$4" failed_ref="$5"

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

        # Show individual installation
        echo "• Installing $pkg"
        if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
            if DEBIAN_FRONTEND=noninteractive $PKG_INSTALL $PKG_NOCONFIRM "$resolved_pkg" >/dev/null 2>&1; then
                installed_ref+=("$pkg")
            else
                failed_ref+=("$pkg")
            fi
        else
            if $install_cmd "$resolved_pkg" >/dev/null 2>&1; then
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

        echo "• Installing $pkg"
        if $install_cmd "$pkg" >/dev/null 2>&1; then
            installed_ref+=("$pkg")
        else
            failed_ref+=("$pkg")
        fi
    done
}

# Show package installation summary
show_package_summary() {
    local title="$1"
    local -n installed_ref="$2" failed_ref="$3"

    if [ ${#installed_ref[@]} -gt 0 ]; then
        echo ""
        display_success "Successfully installed $title: ${installed_ref[*]}"
    fi
    if [ ${#failed_ref[@]} -gt 0 ]; then
        echo ""
        display_error "Failed $title: ${failed_ref[*]}"
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

    # Validate and backup existing configurations
    local config_files=("$HOME/.zshrc" "$HOME/.config/starship.toml" "$HOME/.config/fastfetch/config.jsonc")

    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            backup_config "$config_file"
            state_update "configs_modified" "${INSTALL_STATE["configs_modified"]}$config_file "
        fi
    done

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
            if spin "Installing package"  install_pkg "$pkg" >/dev/null 2>&1; then
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
        display_info "Temporary helper packages detected: ${remove_list[*]}"
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
# =============================================================================
# MAIN EXECUTION FLOW
# =============================================================================

# Trap function for cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    state_update "stage" "exiting"
    state_update "exit_code" "$exit_code"

    # Finalize state
    state_finalize

    # Show rollback information on failure
    if [ $exit_code -ne 0 ]; then
        echo ""
        log_error "Installation failed with exit code $exit_code"
        log_info "To attempt rollback:"
        log_info "  • Packages: Run the suggested removal commands above"
        log_info "  • Configs: Check $INSTALL_STATE_FILE for backup locations"
        log_info "  • Logs: Check $LOG_FILE for detailed error information"
    fi

    # Clean up state file on success
    if [ $exit_code -eq 0 ] && [ -f "$INSTALL_STATE_FILE" ]; then
        rm -f "$INSTALL_STATE_FILE"
    fi
}

# Set trap for cleanup
trap cleanup_on_exit EXIT

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

# Detect if running in a virtual machine
if detect_virtual_machine; then
    IS_VIRTUAL_MACHINE=true
    log_info "Virtual machine detected - optimizing configuration for VM environment"
else
    IS_VIRTUAL_MACHINE=false
    log_info "Physical hardware detected - full configuration available"
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

# Update display theme based on detected distro
update_distro_theme

# Initialize state management
state_init

# Bootstrap UI tools
bootstrap_tools

# Phase 2.5: Pre-Installation Validation
if [ "$DRY_RUN" = false ]; then
    if ! run_pre_install_checks; then
        if supports_gum; then
            display_error "Pre-installation checks failed" "Please resolve the issues above and try again"
        fi
        exit 1
    fi
fi

# Phase 3: Installation Mode Selection
# Determine installation mode based on user interaction or defaults
clear
if [ -t 1 ] && [ "$DRY_RUN" = false ]; then
    # Interactive terminal - always show menu for user selection
    show_menu
elif [ -t 1 ] && [ "$DRY_RUN" = true ]; then
    log_warn "Dry-Run Mode Active: No changes will be applied."
    log_info "Showing menu for preview purposes only."
    show_menu
else
    # Non-interactive mode (CI, scripts, pipes)
    # Only set a default mode if none exists to avoid overriding explicit settings
    if [ -z "${INSTALL_MODE:-}" ]; then
        export INSTALL_MODE="${INSTALL_MODE:-standard}"
        log_info "Non-interactive: defaulting to install mode: $INSTALL_MODE"
    fi
    if [ -z "${INSTALL_GAMING:-}" ]; then
        export INSTALL_GAMING=false
        log_info "Non-interactive: gaming packages disabled by default"
    fi
fi

# Phase 4: Core Installation Execution
# Execute the main installation workflow in logical steps

# Initialize progress tracking (estimate total steps)
progress_init 15

# Step: System Update
step "Updating System Repositories"
if [ "$DRY_RUN" = false ]; then
    time_start "system_update"
    update_system
    time_end "system_update"
fi
progress_update "System update"

# Step: Enable password feedback for better UX
step "Enabling password feedback"
if [ "$DRY_RUN" = false ]; then
    enable_password_feedback
fi
progress_update "Password feedback setup"

# Step: Run Distro System Preparation (install essentials, etc.)
# Run distro-specific system preparation early so essential helpers are present
# before package installation and mark the step complete to avoid duplication.
# Note: For Arch, this includes pacman configuration via configure_pacman_arch
DSTR_PREP_FUNC="${DISTRO_ID}_system_preparation"
DSTR_PREP_STEP="${DSTR_PREP_FUNC}"
    step "Running system preparation for $DISTRO_ID"
if [ "$DRY_RUN" = false ]; then
    source "$SCRIPTS_DIR/distro_check.sh"
    if declare -f "$DSTR_PREP_FUNC" >/dev/null 2>&1; then
        time_start "distro_prep"
        source "$SCRIPTS_DIR/${DISTRO_ID}_config.sh"
        "$DSTR_PREP_FUNC"
        time_end "distro_prep"
    else
        log_error "System preparation function not found for $DISTRO_ID"
    fi
fi
progress_update "System preparation"

# Step: Install Packages based on Mode
    display_step "📦" "Installing Packages ($INSTALL_MODE)"

# Setup Docker repo for server mode on Debian/Ubuntu
if [ "$INSTALL_MODE" = "server" ] && [[ "$DISTRO_ID" = "debian" || "$DISTRO_ID" = "ubuntu" ]]; then
    debian_setup_docker_repo
fi

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
 if [ "$DISTRO_ID" = "arch" ]; then
    install_package_group "$INSTALL_MODE" "AUR Packages" "aur"
fi

# Install COPR/eza package for Fedora
 if [ "$DISTRO_ID" = "fedora" ]; then
    step "Installing COPR/eza Package"
    if [ "$DRY_RUN" = false ]; then
        if command -v dnf >/dev/null; then
            # Install eza from COPR
            if dnf copr enable -y eza-community/eza >/dev/null 2>&1; then
                install_packages_with_progress "eza"
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
if [ "$INSTALL_MODE" = "standard" ] || [ "$INSTALL_MODE" = "minimal" ] && [ -z "${CUSTOM_GROUPS:-}" ]; then
    if [ "${INSTALL_GAMING:-false}" = "true" ]; then
        # Gaming packages already installed above (native and flatpak)
        log_info "Gaming packages already installed in previous steps"
    fi
fi

time_end "package_installation"
progress_update "Package installation"
progress_update "Wake-on-LAN configuration"
progress_update "Distribution configuration"
progress_update "User configuration"
progress_update "Desktop configuration"
progress_update "Security configuration"
progress_update "Performance optimization"
progress_update "Gaming configuration"
progress_update "Maintenance setup"
progress_update "Finalization"

# ------------------------------------------------------------------
# Wake-on-LAN auto-configuration step
#
# If wakeonlan integration module was sourced above (wakeonlan_main_config),
# run it now (unless we're in DRY_RUN). In DRY_RUN show status instead.
# This keeps the step idempotent and consistent with the installer flow.
# ------------------------------------------------------------------
if [ "$INSTALL_MODE" != "server" ] && declare -f wakeonlan_main_config >/dev/null 2>&1; then
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
    display_step "🔧" "Running Distribution-Specific Configuration"

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
    display_step "🐚" "Configuring User Shell and Configuration Files"
    if [ "$DRY_RUN" = false ]; then
        configure_user_shell_and_configs
    fi
fi

# Step: Run Desktop Environment Configuration
if [ "$INSTALL_MODE" != "server" ]; then
    display_step "🖼️" "Configuring Desktop Environment"

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
if [ "$INSTALL_MODE" != "server" ]; then
    display_step "🔒" "Configuring Security Features"

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
fi

# Step: Run Performance Optimization
if [ "$INSTALL_MODE" != "server" ]; then
    display_step "⚡" "Applying Performance Optimizations"

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
fi

# Step: Run Gaming Configuration (if applicable)
if [ "$INSTALL_MODE" != "server" ] && [ "${INSTALL_GAMING:-false}" = "true" ]; then
    display_step "🎮" "Configuring Gaming Environment"

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

# Step: Run Maintenance Setup
if [ "$INSTALL_MODE" != "server" ]; then
    display_step "🛠️" "Setting up Maintenance Tools"

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
fi

# Phase 5: Installation Finalization and Cleanup
    display_step "🎉" "Finalizing Installation"

if [ "$DRY_RUN" = false ]; then
    # Enable services for installed packages
    enable_installed_services

    # Clean up temporary files and helpers
    final_cleanup

    # Generate performance report
    performance_report

    # Show final progress summary
    install_duration=$(( $(date +%s) - ${INSTALL_STATE["start_time"]:-$(date +%s)} ))
    progress_summary "$install_duration"
fi

# Detect system info for installation summary (if power_config available)
if declare -f detect_system_info >/dev/null 2>&1; then
    detect_system_info
fi

# Installation completed
prompt_reboot
