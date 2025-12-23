#!/bin/bash
# Common functions, variables, and helpers for the LinuxInstaller scripts

# --- UI and Logging ---

# Check if gum is available for styling, otherwise use basic echo
supports_gum() {
  command -v gum >/dev/null 2>&1
}

# Colors for logging (fallback if gum is not available)
if ! supports_gum; then
    RESET='\033[0m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;36m' # Cyan/Blue for steps
fi

# A standardized way to print step headers
step() {
    local message="$1"
    if supports_gum; then
        gum style --foreground 212 "❯ $message"
    else
        echo -e "${BLUE}> $message${RESET}"
    fi
    echo "STEP: $message" >> "$INSTALL_LOG"
}

# Standardized logging functions
log_info() {
    local message="$1"
    if supports_gum; then
        gum log --level info "$message"
    else
        echo -e "[INFO] $message"
    fi
    echo "[INFO] $message" >> "$INSTALL_LOG"
}

log_success() {
    local message="$1"
    if supports_gum; then
        gum log --level info "✔ $message"
    else
        echo -e "${GREEN}[SUCCESS] $message${RESET}"
    fi
    echo "[SUCCESS] $message" >> "$INSTALL_LOG"
}

log_warn() {
    local message="$1"
    if supports_gum; then
        gum log --level warn "$message"
    else
        echo -e "${YELLOW}[WARNING] $message${RESET}"
    fi
    echo "[WARNING] $message" >> "$INSTALL_LOG"
}

log_error() {
    local message="$1"
    if supports_gum; then
        gum log --level error "$message"
    else
        echo -e "${RED}[ERROR] $message${RESET}"
    fi
    echo "[ERROR] $message" >> "$INSTALL_LOG"
}


# --- Package Management Wrappers (ENFORCES NON-INTERACTIVE) ---

# Wrapper to install one or more packages silently
install_pkg() {
    if [ $# -eq 0 ]; then
        log_warn "install_pkg: No packages provided to install."
        return
    fi
    log_info "Installing package(s): $*"
    if ! sudo $PKG_INSTALL $PKG_NOCONFIRM "$@" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to install package(s): $*. Check log for details."
        # Optionally, exit on failure: exit 1
    else
        log_success "Successfully installed: $*"
    fi
}

# Wrapper to remove one or more packages silently
remove_pkg() {
    if [ $# -eq 0 ]; then
        log_warn "remove_pkg: No packages provided to remove."
        return
    fi
    log_info "Removing package(s): $*"
    if ! sudo $PKG_REMOVE $PKG_NOCONFIRM "$@" >> "$INSTALL_LOG" 2>&1; then
        log_error "Failed to remove package(s): $*."
    else
        log_success "Successfully removed: $*"
    fi
}

# Wrapper to update the system silently
update_system() {
    log_info "Updating system packages..."
    # The update command can be complex, so we handle it carefully
    # The PKG_UPDATE variable from distro_check.sh should already be sudo'd
    if ! $PKG_UPDATE $PKG_NOCONFIRM >> "$INSTALL_LOG" 2>&1; then
        log_error "System update failed. Check log for details."
    else
        log_success "System updated successfully."
    fi
}


# --- System & Hardware Checks ---

# Check if the system is running in UEFI mode
is_uefi() {
    [ -d /sys/firmware/efi/efivars ]
}

# Check for an active internet connection
check_internet() {
    if ! ping -c 1 -W 5 google.com &>/dev/null; then
        log_error "No internet connection detected. Aborting."
        exit 1
    fi
}


# --- Finalization ---

# Standardized reboot prompt
prompt_reboot() {
    if supports_gum; then
        figlet "Reboot System" | gum style --foreground 5
        if gum confirm "Reboot now to apply all changes?"; then
            log_warn "Rebooting system..."
            sudo reboot
        else
            log_info "Please reboot your system later to apply all changes."
        fi
    else
        echo ""
        read -r -p "Reboot now to apply all changes? [Y/n]: " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ || -z "$response" ]]; then
            echo "Rebooting system..."
            sudo reboot
        else
            echo "Please reboot your system later to apply all changes."
        fi
    fi
}
