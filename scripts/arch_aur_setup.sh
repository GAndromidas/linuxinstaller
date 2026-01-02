#!/bin/bash
set -uo pipefail

# Arch Linux AUR Setup Script
# Handles installation of yay AUR helper and mirror optimization with reflector

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Ensure we're on Arch Linux
if [ "$DISTRO_ID" != "arch" ]; then
    log_error "This script is for Arch Linux only"
    exit 1
fi

# Install yay AUR helper
arch_install_aur_helper() {
    step "Installing AUR Helper (yay)"

    if command -v yay >/dev/null 2>&1; then
        return 0
    fi

    if ! pacman -S --noconfirm --needed base-devel git >/dev/null 2>&1; then
        return 1
    fi

    local temp_dir=$(mktemp -d)
    # Set secure permissions for temporary directory (owner read/write/execute only)
    chmod 700 "$temp_dir"

    # Determine which user to run AUR build as (never as root)
    local build_user=""
    if [ "$EUID" -eq 0 ]; then
        if [ -n "${SUDO_USER:-}" ]; then
            build_user="$SUDO_USER"
        else
            # Fallback to first real user if SUDO_USER not set
            build_user=$(getent passwd 1000 | cut -d: -f1)
        fi
        if [ -z "${build_user:-}" ]; then
            log_error "Cannot determine user for AUR build"
            rm -rf "$temp_dir"
            return 1
        fi
        # Change ownership to build user while maintaining secure permissions
        chown "$build_user:$build_user" "$temp_dir"
        chmod 755 "$temp_dir"  # Allow build user to read/execute, owner full access
    else
        build_user="$USER"
    fi

    cd "$temp_dir" || return 1

    if sudo -u "$build_user" git clone https://aur.archlinux.org/yay.git . >/dev/null 2>&1; then
        if sudo -u "$build_user" makepkg -si --noconfirm --needed >/dev/null 2>&1; then
            if supports_gum; then
                display_success "✓ yay installed"
            fi

            # Clean up /tmp directory that yay uses for building
            log_info "Cleaning up temporary build files..."
            if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
                # Clean up build user's temp files if we're running as root
                sudo -u "$build_user" rm -rf "/tmp/yay"* "/tmp/makepkg"*
            fi
            # Also clean any root-owned temp files
            rm -rf /tmp/yay* /tmp/makepkg* 2>/dev/null || true
            log_info "Temporary build files cleaned up"
        else
            cd - >/dev/null
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log_error "Failed to clone yay repository"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 1
    fi

    cd - >/dev/null
    rm -rf "$temp_dir"
}

# Clean up after yay setup (remove yay-debug and temp files, keep yay)
uninstall_yay() {
    log_info "Cleaning up yay setup..."

    # Remove yay-debug if installed
    if pacman -Q yay-debug >/dev/null 2>&1; then
        if pacman -Rns --noconfirm yay-debug >/dev/null 2>&1; then
            log_success "Successfully removed yay-debug"
        else
            log_warn "Failed to remove yay-debug"
        fi
    else
        log_info "yay-debug not installed"
    fi

    # Clean up any remaining yay temp directories
    log_info "Cleaning up yay temporary files..."
    rm -rf /tmp/yay* /tmp/makepkg* 2>/dev/null || true
    log_success "Temporary files cleaned up"
}

# Update mirrors using reflector
update_mirrors_with_reflector() {
    step "Updating mirrors with reflector"

    if ! command -v reflector >/dev/null 2>&1; then
        log_error "reflector not found. Cannot update mirrors."
        log_info "reflector should be installed as part of ARCH_ESSENTIALS"
        return 1
    fi

    log_info "Finding fastest Arch Linux mirrors based on your location..."

    # Always ensure pacman database is updated, regardless of mirror status
    log_info "Ensuring pacman package database is up to date..."

    # First, try to update mirrors with reflector if internet is available
    log_info "Checking internet connectivity for mirror optimization..."
    if ping -c 1 -W 5 archlinux.org >/dev/null 2>&1; then
        log_info "Internet available, attempting mirror optimization..."
        local reflector_output
        # Detect country for better mirror selection
        local country=""
        if country=$(curl -s --max-time 5 https://ipinfo.io/country 2>/dev/null | tr -d '\n' | tr -d '\r'); then
            if [ -n "$country" ] && [ "$country" != "null" ]; then
                log_info "Detected country: $country"
                reflector_output=$(reflector --latest 10 --sort rate --age 24 --country "$country" --save /etc/pacman.d/mirrorlist --protocol https,http 2>&1)
            else
                log_info "Could not detect country, using global mirror selection"
                reflector_output=$(reflector --latest 10 --sort rate --age 24 --save /etc/pacman.d/mirrorlist --protocol https,http 2>&1)
            fi
        else
            log_info "Country detection failed, using global mirror selection"
            reflector_output=$(reflector --latest 10 --sort rate --age 24 --save /etc/pacman.d/mirrorlist --protocol https,http 2>&1)
        fi

        if [ $? -eq 0 ]; then
            log_success "Mirrorlist updated with fastest mirrors"
        else
            log_warn "Reflector failed, using existing mirrorlist"
            log_info "reflector output: $reflector_output"
        fi
    else
        log_info "No internet connectivity, using existing mirror configuration"
    fi

    # Always update pacman database, even with potentially stale mirrors
    log_info "Updating pacman package database..."
    local sync_attempts=0
    local max_attempts=3
    while [ $sync_attempts -lt $max_attempts ]; do
        if pacman -Syy; then
            log_success "Pacman database successfully synchronized"
            return 0
        else
            sync_attempts=$((sync_attempts + 1))
            log_warn "Pacman sync attempt $sync_attempts failed, retrying..."
            sleep 2
        fi
    done

    log_error "Failed to synchronize pacman database after $max_attempts attempts"
    log_error "This may cause package installation failures"
    log_info "You may need to manually run: pacman -Syy"
    return 1
}

# Main execution
main() {
    # Install yay first
    if ! arch_install_aur_helper; then
        log_error "Failed to install yay AUR helper"
        exit 1
    fi

    # Update mirrors using reflector
    if ! update_mirrors_with_reflector; then
        log_error "Failed to update mirrors with reflector"
        exit 1
    fi

    # Clean up yay after successful setup
    uninstall_yay

    log_success "AUR setup completed successfully"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
