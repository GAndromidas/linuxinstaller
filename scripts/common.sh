#!/bin/bash
# =============================================================================
# Common Utilities and Helpers for LinuxInstaller
# =============================================================================
#
# This module provides shared functionality used across all LinuxInstaller
# components, including:
#
# • Gum UI wrapper functions for beautiful terminal output
# • Logging functions with consistent formatting
# • Package management wrappers for cross-distribution compatibility
# • System detection and validation utilities
# • Security-focused helper functions
#
# All functions in this module are designed to be distribution-agnostic
# where possible, with distribution-specific logic abstracted into
# separate modules.
# =============================================================================

# --- UI and Logging ---

# Find gum binary in PATH and common locations, avoiding shell function false positives
find_gum_bin() {
    # Scan PATH entries for an executable 'gum' and print its path if found.
    # Avoid using `command -v` directly because it can report shell functions.
    local IFS=':'
    local dir
    for dir in $PATH; do
        if [ -x "$dir/gum" ] && [ ! -d "$dir/gum" ]; then
            printf '%s' "$dir/gum"
            return 0
        fi
    done

    # Common fallback locations in case PATH is unusual
    for dir in /usr/local/bin /usr/bin /bin /snap/bin /usr/sbin /sbin; do
        if [ -x "$dir/gum" ]; then
            printf '%s' "$dir/gum"
            return 0
        fi
    done

    return 1
}

# Check if gum UI helper is available and executable
supports_gum() {
    # Fast path using type -P (portable) when it finds a binary
    local candidate
    candidate="$(type -P gum 2>/dev/null || true)"
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        GUM_BIN="$candidate"
        return 0
    fi

    # Fallback: scan PATH manually to avoid being fooled by shell functions
    candidate="$(find_gum_bin 2>/dev/null || true)"
    if [ -n "$candidate" ]; then
        GUM_BIN="$candidate"
        return 0
    fi

    # Not available
    GUM_BIN=""
    return 1
}

# GUM / color scheme (refactored for cyan theme)
# - Primary: bright cyan for titles/headers and branding (LinuxInstaller theme)
# - Body: light cyan for standard text (readable cyan theme)
# - Border: cyan borders for consistency
# - Success / Error / Warning: cyan variants for cohesive theme
# - All colors follow cyan/blue theme for beautiful terminal appearance
GUM_PRIMARY_FG=cyan
GUM_BODY_FG=87       # Light cyan for body text
GUM_BORDER_FG=cyan   # Cyan borders
GUM_SUCCESS_FG=48    # Bright green-cyan for success
GUM_ERROR_FG=196     # Keep red for errors (accessibility)
GUM_WARNING_FG=226   # Bright yellow for warnings

# Backwards compatibility: keep the legacy variable name pointing to the primary accent
GUM_FG="$GUM_PRIMARY_FG"

# Cached path to an external gum binary (populated by supports_gum/find_gum_bin)
GUM_BIN=""

# Ensure we have fallback ANSI colors for systems without 'gum' (cyan theme)
if ! supports_gum; then
    RESET='\033[0m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    WHITE='\033[1;37m'     # bright white for body text
    BLUE='\033[1;36m'      # bright cyan for headers/title (primary theme color)
    CYAN='\033[0;36m'      # standard cyan for accents
    LIGHT_CYAN='\033[1;36m' # light cyan for secondary text
fi

# Enhanced wrapper around gum binary for beautiful cyan-themed UI
gum() {
    # Use cached GUM_BIN if available; otherwise discover it without being fooled by
    # the existence of this shell function itself.
    local gum_bin="$GUM_BIN"
    if [ -z "$gum_bin" ]; then
        gum_bin="$(type -P gum 2>/dev/null || true)"
        if [ -z "$gum_bin" ]; then
            gum_bin="$(find_gum_bin 2>/dev/null || true)"
        fi
    fi

    if [ -z "$gum_bin" ] || [ ! -x "$gum_bin" ]; then
        # Not installed - return conventional "command not found" code so callers can fall back
        return 127
    fi

    local new_args=()
    local skip_next=false

    for arg in "$@"; do
        if [ "$skip_next" = true ]; then
            skip_next=false
            continue
        fi

        # Enforce beautiful cyan theme colors
        if [ "$arg" = "--border-foreground" ]; then
            new_args+=("$arg" "$GUM_BORDER_FG")
            skip_next=true
            continue
        elif [ "$arg" = "--cursor.foreground" ]; then
            new_args+=("$arg" "$GUM_PRIMARY_FG")
            skip_next=true
            continue
        elif [ "$arg" = "--selected.foreground" ]; then
            new_args+=("$arg" "$GUM_SUCCESS_FG")
            skip_next=true
            continue
        fi

        new_args+=("$arg")
    done

    # Execute the external gum binary directly (avoid recursion / function masking)
    "$gum_bin" "${new_args[@]}"
}

# Print step header with consistent formatting (cyan theme)
step() {
    local message="$1"
    if supports_gum; then
        # Add a top margin so each step is separated visually
        # Use cyan theme: cyan primary for the entire header
        # Note: gum style expects text first, then flags
        gum style "❯ $message" --margin "1 2" --foreground "$GUM_PRIMARY_FG" --bold
    else
        # Make's arrow/title cyan and actual message light cyan for readability
        # Prepend a newline so steps are spaced out in non-gum terminals too
        echo -e "\n${CYAN}❯ ${LIGHT_CYAN}$message${RESET}"
    fi
}

# Log informational message (only shows in verbose mode)
log_info() {
    local message="$1"
    # Quiet by default: only print info to console when verbose mode is enabled
    if [ "${VERBOSE:-false}" = "true" ]; then
        if supports_gum; then
            # Use light cyan for info text in cyan theme
            gum style "ℹ $message" --margin "0 2" --foreground "$GUM_BODY_FG"
        else
            echo -e "${LIGHT_CYAN}[INFO] $message${RESET}"
        fi
    fi
}

# Log success message
log_success() {
    local message="$1"
    if supports_gum; then
        # Use bright cyan-green for success in cyan theme
        gum style "✔ $message" --margin "0 2" --foreground "$GUM_SUCCESS_FG" --bold
        # Add a trailing blank line for readability between steps
        echo ""
    else
        echo -e "${GREEN}✔ $message${RESET}"
        echo ""
    fi
}

# Log warning message
log_warn() {
    local message="$1"
    if supports_gum; then
        # Use bright yellow for warnings in cyan theme
        gum style "⚠ $message" --margin "0 2" --foreground "$GUM_WARNING_FG" --bold
        echo ""
    else
        echo -e "${YELLOW}⚠ $message${RESET}"
        echo ""
    fi
}

# Log error message
log_error() {
    local message="$1"
    if supports_gum; then
        # Use red for errors (maintains accessibility)
        gum style "✗ $message" --margin "0 2" --foreground "$GUM_ERROR_FG" --bold
        echo ""
    else
        echo -e "${RED}✗ $message${RESET}"
        echo ""
    fi
}

# --- Compatibility Aliases ---
# Backwards compatibility aliases for logging functions
ui_info() { log_info "$@"; }
ui_success() { log_success "$@"; }
ui_warn() { log_warn "$@"; }
ui_error() { log_error "$@"; }
log_warning() { log_warn "$@"; }
log_to_file() { :; }


# --- State Management ---

# Mark a step as completed (no-op - state tracking removed)
mark_step_complete() {
    local step_name="$1"
    local friendly="${CURRENT_STEP_MESSAGE:-$step_name}"
    # Show a concise, friendly success message for the completed step
    log_success "$friendly"
    # Clear the saved friendly message
    CURRENT_STEP_MESSAGE=""
}

# Check if a step has been completed (always returns false - state tracking removed)
is_step_complete() {
    local step_name="$1"
    false
}

# Clear all completed steps from state file (no-op - state tracking removed)
clear_state() {
    :
}

# Display menu to resume or start fresh installation (no-op - resume menu removed)
show_resume_menu() {
    :
}


# --- Package Management Wrappers (ENFORCES NON-INTERACTIVE) ---

# Check if a package is already installed (secure implementation)
is_package_installed() {
    local pkg="$1"
    local distro="${DISTRO_ID:-}"

    # Validate package name to prevent command injection
    if [[ "$pkg" =~ [^a-zA-Z0-9._+-] ]]; then
        log_warn "Invalid package name: $pkg"
        return 1
    fi

    case "$distro" in
        arch)
            pacman -Q "$pkg" >/dev/null 2>&1
            ;;
        fedora)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
        debian|ubuntu)
            dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if a package exists in repository (secure implementation)
package_exists() {
    local pkg="$1"
    local distro="${DISTRO_ID:-}"

    # Validate package name to prevent command injection
    if [[ "$pkg" =~ [^a-zA-Z0-9._+-] ]]; then
        log_warn "Invalid package name: $pkg"
        return 1
    fi

    case "$distro" in
        arch)
            pacman -Si "$pkg" >/dev/null 2>&1
            ;;
        fedora)
            dnf info "$pkg" >/dev/null 2>&1
            ;;
        debian|ubuntu)
            apt-cache show "$pkg" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Install one or more packages silently (secure implementation)
install_pkg() {
    if [ $# -eq 0 ]; then
        log_warn "install_pkg: No packages provided to install."
        return 1
    fi

    # Validate all package names to prevent command injection
    local valid_packages=()
    for pkg in "$@"; do
        if [[ "$pkg" =~ [^a-zA-Z0-9._+-] ]]; then
            log_error "Invalid package name contains special characters: $pkg"
            return 1
        fi
        valid_packages+=("$pkg")
    done

    log_info "Installing package(s): ${valid_packages[*]}"
    local install_status=0

    if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
        DEBIAN_FRONTEND=noninteractive $PKG_INSTALL $PKG_NOCONFIRM "${valid_packages[@]}"
        install_status=$?
    elif [ "$DISTRO_ID" = "arch" ]; then
        # For Arch, try pacman first, then yay for AUR packages
        local aur_packages=()
        local native_packages=()

        for pkg in "${valid_packages[@]}"; do
            if ! pacman -Si "$pkg" >/dev/null 2>&1; then
                # Package not in official repos, try AUR
                aur_packages+=("$pkg")
            else
                native_packages+=("$pkg")
            fi
        done

        # Install native packages first
        if [ ${#native_packages[@]} -gt 0 ]; then
            pacman -S --needed --noconfirm "${native_packages[@]}" >/dev/null 2>&1 || install_status=$?
        fi

        # Install AUR packages with yay
        if [ ${#aur_packages[@]} -gt 0 ]; then
            # Determine user for yay (secure user validation)
            local yay_user=""
            if [ "$EUID" -eq 0 ]; then
                if [ -n "${SUDO_USER:-}" ]; then
                    yay_user="$SUDO_USER"
                else
                    yay_user=$(getent passwd 1000 | cut -d: -f1 2>/dev/null)
                fi
            else
                yay_user="$USER"
            fi

            # Validate user exists before using sudo
            if [ -n "$yay_user" ] && getent passwd "$yay_user" >/dev/null 2>&1; then
                sudo -u "$yay_user" yay -S --noconfirm --needed --removemake "${aur_packages[@]}" >/dev/null 2>&1 || install_status=$?
            else
                log_error "Cannot determine valid user for AUR installation"
                install_status=1
            fi
        fi
    else
        $PKG_INSTALL $PKG_NOCONFIRM "${valid_packages[@]}"
        install_status=$?
    fi

    if [ $install_status -ne 0 ]; then
        log_error "Failed to install package(s): ${valid_packages[*]}."
        return 1
    else
        log_success "Successfully installed: ${valid_packages[*]}"
    fi
}

# Remove one or more packages silently with improved error handling
remove_pkg() {
    if [ $# -eq 0 ]; then
        log_warn "remove_pkg: No packages provided to remove."
        return 1
    fi

    # Validate package names
    local valid_packages=()
    for pkg in "$@"; do
        if [[ "$pkg" =~ [^a-zA-Z0-9._+-] ]]; then
            log_error "Invalid package name contains special characters: $pkg"
            return 1
        fi
        valid_packages+=("$pkg")
    done

    log_info "Removing package(s): ${valid_packages[*]}"
    local remove_status

    if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
        DEBIAN_FRONTEND=noninteractive $PKG_REMOVE $PKG_NOCONFIRM "${valid_packages[@]}"
        remove_status=$?
    else
        $PKG_REMOVE $PKG_NOCONFIRM "${valid_packages[@]}"
        remove_status=$?
    fi

    if [ $remove_status -ne 0 ]; then
        log_error "Failed to remove package(s): ${valid_packages[*]}."
        log_error "This may leave your system in an inconsistent state."
        log_error "You may need to manually remove these packages or fix dependencies."
        return 1
    else
        log_success "Successfully removed: ${valid_packages[*]}"
    fi
}

# Update system packages silently
update_system() {
    log_info "Updating system packages..."
    local update_status=0

    if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
        # Run apt-get update and apt-get upgrade separately
        DEBIAN_FRONTEND=noninteractive apt-get update -qq || update_status=$?
        if [ $update_status -eq 0 ]; then
            DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq || update_status=$?
        fi
    else
        $PKG_UPDATE $PKG_NOCONFIRM >/dev/null 2>&1
        update_status=$?
    fi

    if [ $update_status -ne 0 ]; then
        log_error "System update failed."
    else
        log_success "System updated successfully."
    fi
}


# --- System & Hardware Checks ---

# Check if system is running in UEFI mode
is_uefi() {
    [ -d /sys/firmware/efi/efivars ]
}

# Check for active internet connection with improved error handling
check_internet() {
    local test_host="8.8.8.8"  # Use Google DNS instead of hostname
    local timeout=10

    log_info "Checking internet connection..."

    if ! ping -c 1 -W "$timeout" "$test_host" &>/dev/null; then
        log_error "No internet connection detected!"
        log_error "Please check your network connection and try again."
        log_error "Common solutions:"
        log_error "  • Check if you're connected to WiFi/Ethernet"
        log_error "  • Run 'ip addr' to check network interfaces"
        log_error "  • Try 'ping 8.8.8.8' to test basic connectivity"
        exit 1
    fi

    log_success "Internet connection confirmed"
}

# Detect the system bootloader (grub or systemd-boot)
detect_bootloader() {
    if [ -d /sys/firmware/efi ]; then
        if [ -f /boot/efi/EFI/arch/grubx64.efi ] || [ -f /boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
            echo "grub"
        elif [ -d /boot/loader ] || [ -d /efi/loader ]; then
            echo "systemd-boot"
        else
            echo "unknown"
        fi
    else
        if [ -d /boot/grub ]; then
            echo "grub"
        else
            echo "unknown"
        fi
    fi
}

# Check if system uses btrfs filesystem
is_btrfs_system() {
    if [ -f /proc/mounts ]; then
        grep -q " btrfs " /proc/mounts
    else
        false
    fi
}




# --- Finalization ---

# Beautiful prompt to reboot the system with enhanced UI
prompt_reboot() {
    if supports_gum; then
        # Use beautiful cyan-themed gum styling
        echo ""
        gum style "🔄 System Reboot Required" \
                 --border double --margin "1 2" --padding "1 2" \
                 --foreground "$GUM_PRIMARY_FG" --border-foreground "$GUM_BORDER_FG" \
                 --bold 2>/dev/null || true
        echo ""
        gum style "All changes have been applied successfully!" \
                 --margin "0 2" --foreground "$GUM_BODY_FG" 2>/dev/null || true
        gum style "A system reboot is recommended to ensure everything works properly." \
                 --margin "0 2" --foreground "$GUM_BODY_FG" 2>/dev/null || true
        echo ""
        if gum confirm --default=true "Reboot now to apply all changes?"; then
            gum style "🔄 Rebooting system..." \
                     --margin "0 2" --foreground "$GUM_WARNING_FG" --bold 2>/dev/null || true
        else
            gum style "✓ Please reboot your system later to apply all changes." \
                     --margin "0 2" --foreground "$GUM_SUCCESS_FG" 2>/dev/null || true
        fi
    else
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET} ${LIGHT_CYAN}🔄 System Reboot Required${RESET}                           ${CYAN}║${RESET}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e "${LIGHT_CYAN}All changes have been applied successfully!${RESET}"
        echo -e "${LIGHT_CYAN}A system reboot is recommended to ensure everything works properly.${RESET}"
        echo ""
        read -r -p "Reboot now to apply all changes? [Y/n]: " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ || -z "$response" ]]; then
            echo -e "${YELLOW}🔄 Rebooting system...${RESET}"
            reboot
        else
            echo -e "${GREEN}✓ Please reboot your system later to apply all changes.${RESET}"
        fi
    fi
}
