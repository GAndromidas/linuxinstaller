#!/bin/bash
# Common functions, variables, and helpers for the LinuxInstaller scripts

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

# GUM / color scheme (adopted from archinstaller style)
# - Primary: cyan accents for titles/headers (LinuxInstaller branding)
# - Body: white for standard text (keeps output readable, not all-blue)
# - Border: white borders per your request
# - Success / Error / Warning: green / red / yellow respectively
# Use cyan as the primary accent (default bright cyan for gum)
GUM_PRIMARY_FG=cyan
GUM_BODY_FG=15
GUM_BORDER_FG=15
GUM_SUCCESS_FG=46
GUM_ERROR_FG=196
GUM_WARNING_FG=11

# Backwards compatibility: keep the legacy variable name pointing to the primary accent
GUM_FG="$GUM_PRIMARY_FG"

# Cached path to an external gum binary (populated by supports_gum/find_gum_bin)
GUM_BIN=""

# Ensure we have fallback ANSI colors for systems without 'gum'
if ! supports_gum; then
    RESET='\033[0m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    WHITE='\033[1;37m'   # bright white for body text
    BLUE='\033[1;36m'    # bright cyan for headers/title
fi

# Wrapper around gum binary to enforce consistent borders and colors
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

        if [ "$arg" = "--border-foreground" ]; then
            new_args+=("$arg" "$GUM_BORDER_FG")
            skip_next=true
            continue
        fi

        new_args+=("$arg")
    done

    # Execute the external gum binary directly (avoid recursion / function masking)
    "$gum_bin" "${new_args[@]}"
}

# Print step header with consistent formatting
step() {
    local message="$1"
    if supports_gum; then
        # Add a top margin so each step is separated visually
        gum style --margin "1 2" --foreground "$GUM_BODY_FG" --bold "❯ $message"
    else
        # Make the arrow/title blue and the actual message bright white for readability
        # Prepend a newline so steps are spaced out in non-gum terminals too
        echo -e "\n${BLUE}❯ ${WHITE}$message${RESET}"
    fi
}

# Log informational message (only shows in verbose mode)
log_info() {
    local message="$1"
    # Quiet by default: only print info to console when verbose mode is enabled
    if [ "${VERBOSE:-false}" = "true" ]; then
        if supports_gum; then
            # Use white for common/info text so output isn't all blue
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "ℹ $message"
        else
            echo -e "${WHITE}[INFO] $message${RESET}"
        fi
    fi
}

# Log success message
log_success() {
    local message="$1"
    if supports_gum; then
        # Use green for success notifications
        gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" --bold "✔ $message"
        # Add a trailing blank line for readability between steps
        echo ""
    else
        echo -e "${GREEN}[SUCCESS] $message${RESET}"
        echo ""
    fi
}

# Log warning message
log_warn() {
    local message="$1"
    if supports_gum; then
        # Use yellow for warnings
        gum style --margin "0 2" --foreground "$GUM_WARNING_FG" --bold "⚠ $message"
        echo ""
    else
        echo -e "${YELLOW}[WARNING] $message${RESET}"
        echo ""
    fi
}

# Log error message
log_error() {
    local message="$1"
    if supports_gum; then
        # Use red for errors
        gum style --margin "0 2" --foreground "$GUM_ERROR_FG" --bold "✗ $message"
        echo ""
    else
        echo -e "${RED}[ERROR] $message${RESET}"
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

# Check if a package is already installed
is_package_installed() {
    local pkg="$1"
    local distro="${DISTRO_ID:-}"

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

# Check if a package exists in repository
package_exists() {
    local pkg="$1"
    local distro="${DISTRO_ID:-}"

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

# Install one or more packages silently
install_pkg() {
    if [ $# -eq 0 ]; then
        log_warn "install_pkg: No packages provided to install."
        return
    fi
    log_info "Installing package(s): $*"
    if ! $PKG_INSTALL $PKG_NOCONFIRM "$@"; then
        log_error "Failed to install package(s): $*."
        # Optionally, exit on failure: exit 1
    else
        log_success "Successfully installed: $*"
    fi
}

# Remove one or more packages silently
remove_pkg() {
    if [ $# -eq 0 ]; then
        log_warn "remove_pkg: No packages provided to remove."
        return
    fi
    log_info "Removing package(s): $*"
    if ! $PKG_REMOVE $PKG_NOCONFIRM "$@"; then
        log_error "Failed to remove package(s): $*."
    else
        log_success "Successfully removed: $*"
    fi
}

# Update system packages silently
update_system() {
    log_info "Updating system packages..."
    # The update command can be complex, so we handle it carefully
    # The PKG_UPDATE variable from distro_check.sh should already be sudo'd
    if ! $PKG_UPDATE $PKG_NOCONFIRM; then
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

# Check for active internet connection (exits if no connection)
check_internet() {
    if ! ping -c 1 -W 5 google.com &>/dev/null; then
        log_error "No internet connection detected. Aborting."
        exit 1
    fi
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

# Prompt user to reboot the system
prompt_reboot() {
    if supports_gum; then
        # Use gum styled header for a consistent UI
        gum style --border double --margin "0 2" --padding "1 2" --foreground "$GUM_PRIMARY_FG" --border-foreground "$GUM_BORDER_FG" --bold "Reboot System" 2>/dev/null || true
        if gum confirm --default=true "Reboot now to apply all changes?"; then
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
