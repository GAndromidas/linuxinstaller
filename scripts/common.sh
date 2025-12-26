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

# --- Compatibility Aliases ---
ui_info() { log_info "$@"; }
ui_success() { log_success "$@"; }
ui_warn() { log_warn "$@"; }
ui_error() { log_error "$@"; }
log_warning() { log_warn "$@"; }
log_to_file() { echo "$@" >> "$INSTALL_LOG"; }


# --- State Management ---

STATE_FILE="$HOME/.linuxinstaller.state"

# Initialize state file directory if needed
mkdir -p "$(dirname "$STATE_FILE")"

# Function to mark step as completed
mark_step_complete() {
    local step_name="$1"
    if ! grep -q "^$step_name$" "$STATE_FILE" 2>/dev/null; then
        echo "$step_name" >> "$STATE_FILE"
    fi
}

# Function to check if step was completed
is_step_complete() {
    local step_name="$1"
    [ -f "$STATE_FILE" ] && grep -q "^$step_name$" "$STATE_FILE"
}

# Function to clear state
clear_state() {
    rm -f "$STATE_FILE"
}

# Resume menu
show_resume_menu() {
    if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
        log_info "Previous installation detected. The following steps were completed:"

        if supports_gum; then
            echo ""
            gum style --margin "0 2" --foreground 15 "Completed steps:"
            while IFS= read -r step; do
                 gum style --margin "0 4" --foreground 10 "✓ $step"
            done < "$STATE_FILE"
            echo ""

            if gum confirm --default=true "Resume installation from where you left off?"; then
                log_success "Resuming installation..."
                return 0
            else
                if gum confirm --default=false "Start fresh installation (this will clear previous progress)?"; then
                    clear_state
                    log_info "Starting fresh installation..."
                    return 0
                else
                    log_info "Installation cancelled by user."
                    exit 0
                fi
            fi
        else
            while IFS= read -r step; do
                 echo -e "  [DONE] $step"
            done < "$STATE_FILE"

            read -r -p "Resume installation? [Y/n]: " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ || -z "$response" ]]; then
                log_success "Resuming installation..."
                return 0
            else
                read -r -p "Start fresh installation? [y/N]: " response
                if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    clear_state
                    log_info "Starting fresh installation..."
                    return 0
                else
                    log_info "Installation cancelled by user."
                    exit 0
                fi
            fi
        fi
    fi
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

# Arch-specific helper functions
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

is_btrfs_system() {
    if [ -f /proc/mounts ]; then
        grep -q " btrfs " /proc/mounts
    else
        false
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
