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

# Default log file location (can be overridden by calling script)
LOG_FILE="${LOG_FILE:-/var/log/linuxinstaller.log}"

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
GUM_INFO_FG=cyan     # Cyan for informational messages

# Backwards compatibility: keep the legacy variable name pointing to the primary accent
GUM_FG="$GUM_PRIMARY_FG"

# Cached path to an external gum binary (populated by supports_gum/find_gum_bin)
GUM_BIN=""

# Define ANSI color variables (always available for logging functions)
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'     # bright white for body text
BLUE='\033[1;36m'      # bright cyan for headers/title (primary theme color)
CYAN='\033[0;36m'      # standard cyan for accents
LIGHT_CYAN='\033[1;36m' # light cyan for secondary text

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

# Execute command with spinner for user feedback during long operations
# Usage: spin "Description of operation" command args...
spin() {
    local title="$1"
    shift

    if supports_gum; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        echo -e "${YELLOW}⏳ $title...${RESET}"
        "$@"
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}✓ $title completed${RESET}"
        else
            echo -e "${RED}✗ $title failed${RESET}"
        fi
        return $exit_code
    fi
}

# Install packages with cool progress indicators (like gaming packages)
# Usage: install_packages_with_progress package1 package2 ...
install_packages_with_progress() {
    local packages=("$@")
    local installed_packages=()
    local failed_packages=()

    if supports_gum; then
        for package in "${packages[@]}"; do
            if [ -n "$package" ]; then
                echo "• Installing $package"
                if install_pkg "$package" >/dev/null 2>&1; then
                    installed_packages+=("$package")
                else
                    failed_packages+=("$package")
                fi
            fi
        done

        # Show summary
        if [ ${#installed_packages[@]} -gt 0 ]; then
            echo ""
            gum style "✓ Packages installed: ${installed_packages[*]}" --margin "0 2" --foreground "$GUM_SUCCESS_FG"
        fi
        if [ ${#failed_packages[@]} -gt 0 ]; then
            echo ""
            gum style "✗ Failed packages: ${failed_packages[*]}" --margin "0 2" --foreground "$GUM_ERROR_FG"
        fi
    else
        # Plain text mode - install quietly
        for package in "${packages[@]}"; do
            if [ -n "$package" ]; then
                if install_pkg "$package" >/dev/null 2>&1; then
                    installed_packages+=("$package")
                else
                    failed_packages+=("$package")
                fi
            fi
        done

        # Show summary
        if [ ${#installed_packages[@]} -gt 0 ]; then
            echo "✓ Packages installed: ${installed_packages[*]}"
        fi
        if [ ${#failed_packages[@]} -gt 0 ]; then
            echo "✗ Failed packages: ${failed_packages[*]}"
        fi
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

# =============================================================================
# STATE MANAGEMENT SYSTEM
# =============================================================================

# Initialize installation state tracking
state_init() {
    # Create state file with metadata
    cat > "$INSTALL_STATE_FILE" << EOF
# LinuxInstaller State File
# Generated: $(date)
# PID: $$
# User: $(whoami)
# Distribution: ${DISTRO_ID:-unknown}
# Mode: ${INSTALL_MODE:-unknown}
EOF

    # Initialize state variables
    INSTALL_STATE["stage"]="initialized"
    INSTALL_STATE["start_time"]="$(date +%s)"
    INSTALL_STATE["packages_installed"]=""
    INSTALL_STATE["services_enabled"]=""
    INSTALL_STATE["configs_modified"]=""
}

# Update installation state
state_update() {
    local key="$1"
    local value="$2"

    INSTALL_STATE["$key"]="$value"
    echo "$key=$value" >> "$INSTALL_STATE_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [STATE] $key=$value" >> "$LOG_FILE"
}

# Check if a component was already installed
state_check() {
    local key="$1"
    # Use parameter expansion with default to avoid unbound variable error
    local value="${INSTALL_STATE[$key]:-}"
    [[ -n "$value" ]]
}

# Save installation summary
state_finalize() {
    local end_time=$(date +%s)
    local duration=$((end_time - ${INSTALL_STATE["start_time"]:-$end_time}))

    cat >> "$INSTALL_STATE_FILE" << EOF

# Installation Summary
# Completed: $(date)
# Duration: ${duration} seconds
# Final Stage: ${INSTALL_STATE["stage"]}
# Exit Code: $?

# Installed Packages:
${INSTALL_STATE["packages_installed"]}

# Enabled Services:
${INSTALL_STATE["services_enabled"]}

# Modified Configs:
${INSTALL_STATE["configs_modified"]}
EOF
}

# =============================================================================
# ENHANCED LOGGING SYSTEM
# =============================================================================

# Log error message
log_error() {
    echo -e "${RED}❌ $1${RESET}" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >> "$LOG_FILE"
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

    # Check if packages are already tracked as installed
    local packages_to_install=()
    for pkg in "$@"; do
        if state_check "pkg_$pkg"; then
            log_info "Package $pkg already tracked as installed, skipping"
            continue
        fi
        packages_to_install+=("$pkg")
    done

    if [ ${#packages_to_install[@]} -eq 0 ]; then
        log_info "All packages already installed"
        return 0
    fi

    # Validate all package names to prevent command injection
    local valid_packages=()
    for pkg in "${packages_to_install[@]}"; do
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
            log_info "Installing native Arch packages: ${native_packages[*]}"
            if ! pacman -S --needed --noconfirm "${native_packages[@]}"; then
                log_error "Failed to install native packages: ${native_packages[*]}"
                install_status=1
            else
                log_success "Successfully installed native packages: ${native_packages[*]}"
            fi
        fi

        # Install AUR packages with improved method (build and install as root)
        if [ ${#aur_packages[@]} -gt 0 ]; then
            log_info "Installing AUR packages..."
            # Install each AUR package individually
            for aur_pkg in "${aur_packages[@]}"; do
                local pkg_dir="/tmp/aur-build-$aur_pkg"
                rm -rf "$pkg_dir"
                mkdir -p "$pkg_dir"

                log_info "Building AUR package: $aur_pkg"
                # Build package as root (necessary for --syncdeps to work without password prompts)
                local build_output
                if build_output=$(cd "$pkg_dir" && git clone https://aur.archlinux.org/"$aur_pkg".git . && makepkg --noconfirm --syncdeps --needed 2>&1); then
                    log_info "Build successful for $aur_pkg"
                    # Install built package as root
                    if pacman -U "$pkg_dir"/*.pkg.tar.zst --noconfirm >/dev/null 2>&1; then
                        log_success "Successfully installed AUR package: $aur_pkg"
                    else
                        log_error "Failed to install built AUR package: $aur_pkg"
                        log_error "pacman -U failed for built package"
                        install_status=1
                    fi
                else
                    log_error "Failed to build AUR package: $aur_pkg"
                    log_error "Build output: $build_output"
                    install_status=1
                fi

                # Clean up build directory
                rm -rf "$pkg_dir"
            done
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
        # Track installed packages in state
        for pkg in "${valid_packages[@]}"; do
            state_update "pkg_$pkg" "installed"
            state_update "packages_installed" "${INSTALL_STATE["packages_installed"]}$pkg "
        done
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

# =============================================================================
# CONFIGURATION VALIDATION SYSTEM
# =============================================================================

# Validate configuration file syntax
validate_config() {
    local config_file="$1"
    local config_type="${2:-bash}"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    case "$config_type" in
        "bash")
            if ! bash -n "$config_file" 2>/dev/null; then
                log_error "Configuration file has syntax errors: $config_file"
                return 1
            fi
            ;;
        "json")
            if command -v jq >/dev/null 2>&1; then
                if ! jq empty "$config_file" 2>/dev/null; then
                    log_error "Configuration file has invalid JSON: $config_file"
                    return 1
                fi
            else
                log_warn "jq not available, skipping JSON validation for $config_file"
            fi
            ;;
        "yaml")
            if command -v yamllint >/dev/null 2>&1; then
                if ! yamllint "$config_file" >/dev/null 2>&1; then
                    log_error "Configuration file has YAML issues: $config_file"
                    return 1
                fi
            else
                log_warn "yamllint not available, skipping YAML validation for $config_file"
            fi
            ;;
    esac

    log_success "Configuration file validated: $config_file"
    return 0
}

# Backup configuration file before modification
backup_config() {
    local config_file="$1"
    local backup_suffix="${2:-$(date +%Y%m%d_%H%M%S)}"

    if [ -f "$config_file" ]; then
        local backup_file="${config_file}.backup.${backup_suffix}"
        if cp "$config_file" "$backup_file"; then
            log_success "Configuration backed up: $backup_file"
            state_update "backup_$config_file" "$backup_file"
            return 0
        else
            log_error "Failed to backup configuration: $config_file"
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# ROLLBACK SYSTEM
# =============================================================================

# Rollback package installation
rollback_packages() {
    log_warn "Attempting to rollback package installations..."

    local packages_to_remove=""
    IFS=' ' read -ra packages_array <<< "${INSTALL_STATE["packages_installed"]}"

    for pkg in "${packages_array[@]}"; do
        if [ -n "$pkg" ]; then
            log_info "Would rollback package: $pkg"
            packages_to_remove="$packages_to_remove $pkg"
        fi
    done

    if [ -n "$packages_to_remove" ]; then
        log_warn "To manually rollback, run: $PKG_REMOVE $packages_to_remove"
        log_warn "Note: This may remove dependencies required by other packages"
    fi
}

# Rollback configuration changes
rollback_configs() {
    log_warn "Attempting to rollback configuration changes..."

    for key in "${!INSTALL_STATE[@]}"; do
        if [[ "$key" =~ ^backup_ ]]; then
            local config_file="${key#backup_}"
            local backup_file="${INSTALL_STATE[$key]}"

            if [ -f "$backup_file" ]; then
                if cp "$backup_file" "$config_file"; then
                    log_success "Restored configuration: $config_file"
                else
                    log_error "Failed to restore configuration: $config_file"
                fi
            fi
        fi
    done
}

# =============================================================================
# DEPENDENCY RESOLUTION SYSTEM
# =============================================================================

# Check for package dependencies before installation
check_dependencies() {
    local packages=("$@")
    local missing_deps=()

    for pkg in "${packages[@]}"; do
        # Check if package exists in repositories
        if ! package_exists "$pkg"; then
            missing_deps+=("$pkg")
            continue
        fi

        # For Arch, check for AUR dependencies
        if [ "$DISTRO_ID" = "arch" ]; then
            # This is a simplified check - in reality you'd need to parse PKGBUILD
            local aur_deps=""
            if ! pacman -Si "$pkg" >/dev/null 2>&1; then
                # Check for common AUR dependency patterns
                case "$pkg" in
                    *-bin|*-git|*-svn|*-hg)
                        aur_deps="git"
                        ;;
                    *-qt5|*-qt6)
                        aur_deps="qt5-base qt6-base"
                        ;;
                esac

                if [ -n "$aur_deps" ]; then
                    for dep in $aur_deps; do
                        if ! pacman -Q "$dep" >/dev/null 2>&1 && ! pacman -Si "$dep" >/dev/null 2>&1; then
                            missing_deps+=("$dep (dependency of $pkg)")
                        fi
                    done
                fi
            fi
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "Missing dependencies detected: ${missing_deps[*]}"
        return 1
    fi

    return 0
}

# =============================================================================
# PROGRESS TRACKING SYSTEM
# =============================================================================

# Initialize progress tracking
progress_init() {
    PROGRESS_TOTAL="$1"
    PROGRESS_CURRENT=0

    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_INFO_FG" "📊 Progress: 0/$PROGRESS_TOTAL steps completed"
    else
        echo "Progress: 0/$PROGRESS_TOTAL steps completed"
    fi
}

# Update progress
progress_update() {
    local step_name="${1:-Step}"
    ((PROGRESS_CURRENT++))

    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✅ $step_name completed ($PROGRESS_CURRENT/$PROGRESS_TOTAL)"
    else
        echo "✅ $step_name completed ($PROGRESS_CURRENT/$PROGRESS_TOTAL)"
    fi

    # Update state
    state_update "progress" "$PROGRESS_CURRENT/$PROGRESS_TOTAL"
    state_update "last_step" "$step_name"
}

# Show final progress summary
progress_summary() {
    local duration="$1"

    if supports_gum; then
        echo ""
        gum style --margin "1 2" --border double --border-foreground "$GUM_SUCCESS_FG" --padding "1 2" "🎉 Installation Complete!"
        gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✅ All $PROGRESS_CURRENT steps completed successfully"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "⏱️  Total time: ${duration} seconds"
        echo ""
    else
        echo ""
        echo "🎉 Installation Complete!"
        echo "✅ All $PROGRESS_CURRENT steps completed successfully"
        echo "⏱️  Total time: ${duration} seconds"
        echo ""
    fi
}

# =============================================================================
# PERFORMANCE MONITORING
# =============================================================================

# Track execution time for performance analysis
time_start() {
    local operation="$1"
    echo "$(date +%s.%N):$operation:start" >> "/tmp/linuxinstaller.timing"
}

time_end() {
    local operation="$1"
    echo "$(date +%s.%N):$operation:end" >> "/tmp/linuxinstaller.timing"
}

# Analyze performance bottlenecks
performance_report() {
    if [ -f "/tmp/linuxinstaller.timing" ]; then
        log_info "Performance analysis available in /tmp/linuxinstaller.timing"
        # Could add analysis logic here in the future
    fi
}

# Beautiful prompt to reboot the system with enhanced UI
prompt_reboot() {
    local message="${1:-Reboot your system to apply all changes}"

    if supports_gum; then
        echo ""
        gum style --margin "0 2" --foreground "$GUM_PRIMARY_FG" --bold "🔄 System Reboot Required"
        echo ""
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "$message"
        echo ""
        gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "⚠️  Important: Save your work before rebooting"
        echo ""

        if gum confirm --default=true "Reboot now?"; then
            gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Reboot confirmed. System will reboot in 5 seconds..."
            gum style --margin "0 4" --foreground "$GUM_BODY_FG" "Press Ctrl+C to cancel"
            sleep 5
            systemctl reboot
        else
            gum style --margin "0 2" --foreground "$GUM_INFO_FG" "○ Reboot cancelled. Remember to reboot later to apply changes"
        fi
    else
        echo ""
        echo "🔄 System Reboot Required"
        echo ""
        echo "$message"
        echo ""
        echo "⚠️  Important: Save your work before rebooting"
        echo ""
        read -r -p "Reboot now? [Y/n]: " response
        if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
            echo "System will reboot in 5 seconds... (Ctrl+C to cancel)"
            sleep 5
            systemctl reboot
        else
            echo "Reboot cancelled. Remember to reboot later to apply changes"
        fi
    fi
}

# Export functions that may be called from subshells
export -f install_pkg
export -f install_packages_with_progress
export -f spin
export -f supports_gum
export -f package_exists
export -f log_info
export -f log_success
export -f log_error
export -f log_warn
