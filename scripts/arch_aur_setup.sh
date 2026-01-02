#!/bin/bash
set -uo pipefail

# Arch Linux AUR Setup Script
# Handles installation of yay AUR helper and rate-mirrors-bin for mirror optimization

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
                gum style "✓ yay installed" --margin "0 2" --foreground "$GUM_SUCCESS_FG"
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

# Install rate-mirrors-bin and update mirrors
install_rate_mirrors_and_update() {
    step "Installing rate-mirrors-bin for mirror optimization"

    if command -v rate-mirrors >/dev/null 2>&1; then
        log_info "rate-mirrors is already available"
        return 0
    fi

    if ! command -v yay >/dev/null 2>&1; then
        log_error "yay not found. Cannot install rate-mirrors-bin."
        log_info "Please install yay first"
        return 1
    fi

    # Determine which user to run yay as
    local yay_user=""
    if [ "$EUID" -eq 0 ]; then
        if [ -n "${SUDO_USER:-}" ]; then
            yay_user="$SUDO_USER"
        else
            # Try to find the user who invoked sudo
            yay_user=$(logname 2>/dev/null || who am i | awk '{print $1}' | head -1)
            if [ -z "${yay_user:-}" ] || [ "${yay_user:-}" = "root" ]; then
                # Fallback to first real user
                yay_user=$(getent passwd 1000 | cut -d: -f1 2>/dev/null)
            fi
        fi
        if [ -z "${yay_user:-}" ] || [ "${yay_user:-}" = "root" ]; then
            log_error "Cannot determine non-root user to run yay as"
            log_error "Please run this script as a regular user, not root"
            return 1
        fi
        # Verify the user exists and can run yay
        if ! getent passwd "$yay_user" >/dev/null 2>&1; then
            log_error "User '$yay_user' does not exist"
            return 1
        fi
    else
        yay_user="${USER:-$(whoami)}"
    fi

    # Final safety check for yay_user
    if [ -z "${yay_user:-}" ]; then
        log_error "Failed to determine user for yay installation"
        return 1
    fi

    log_info "Installing rate-mirrors-bin as user: $yay_user"

    # Validate yay_user exists and is not root
    if [ -z "$yay_user" ] || [ "$yay_user" = "root" ]; then
        log_error "Cannot install rate-mirrors-bin: no suitable user found"
        log_info "Please install rate-mirrors-bin manually: yay -S rate-mirrors-bin"
        return 1
    fi

    # Try to install rate-mirrors-bin with better error handling
    local install_output=""
    local exit_code=0

    # Build rate-mirrors-bin as regular user (not root) to avoid makepkg security restrictions
    log_info "Building rate-mirrors-bin as user $yay_user..."
    local pkg_dir="/tmp/rate-mirrors-build-$yay_user"
    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir"
    chown "$yay_user:$yay_user" "$pkg_dir"

    if install_output=$(su - "$yay_user" -c "cd '$pkg_dir' && git clone https://aur.archlinux.org/rate-mirrors-bin.git . && makepkg --noconfirm --syncdeps --needed" 2>&1); then
        # Install the built package as root
        if pacman -U "$pkg_dir"/*.pkg.tar.zst --noconfirm >/dev/null 2>&1; then
            log_success "rate-mirrors-bin installed successfully"
        else
            log_error "Failed to install built rate-mirrors-bin package"
            log_info "Built packages: $(ls "$pkg_dir"/*.pkg.tar.zst 2>/dev/null || echo 'none')"
            return 1
        fi
    else
        exit_code=$?
        log_error "Failed to build rate-mirrors-bin (exit code: $exit_code)"
        log_error "Build output: $install_output"
        log_info "rate-mirrors-bin is required for Arch mirror optimization"
        log_info "Troubleshooting steps:"
        log_info "  1. Check internet connection: ping -c 3 google.com"
        log_info "  2. Update package databases: sudo pacman -Syy"
        log_info "  3. Switch to regular user and try: yay -S rate-mirrors-bin"
        log_info "  4. Or install manually as $yay_user: su - $yay_user -c 'git clone https://aur.archlinux.org/rate-mirrors-bin.git && cd rate-mirrors-bin && makepkg -si'"
        log_info "  5. Check yay is working: yay --version"
        return 1
    fi

    # Clean up build directory
    rm -rf "$pkg_dir"

    # Clean up any temp files from the installation
    rm -rf "/tmp/yay"* "/tmp/makepkg"* 2>/dev/null || true

    # Optimize mirrorlist using rate-mirrors
    if command -v rate-mirrors >/dev/null 2>&1; then
        log_info "Updating mirrorlist with optimized mirrors..."

        # Check if we can write to the mirrorlist file
        if [ ! -w /etc/pacman.d/mirrorlist ]; then
            log_error "Cannot write to /etc/pacman.d/mirrorlist - insufficient permissions"
            log_info "You can manually update mirrors later with: sudo rate-mirrors --save /etc/pacman.d/mirrorlist arch"
            return 1
        fi

        local rate_mirrors_output
        if rate_mirrors_output=$(rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch 2>&1); then
            log_success "Mirrorlist updated successfully"
            # Sync pacman DB to make sure we use the updated mirrors
            if pacman -Syy >/dev/null 2>&1; then
                log_success "Refreshed pacman package database (pacman -Syy)"
            else
                log_warn "Failed to refresh pacman package database after updating mirrors"
            fi
        else
            log_error "Failed to update mirrorlist automatically"
            log_error "rate-mirrors output: $rate_mirrors_output"
            log_info "You can manually update mirrors later with: rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch"
            log_info "Common issues:"
            log_info "  - No internet connection"
            log_info "  - DNS resolution problems"
            log_info "  - Firewall blocking connections"
        fi
    fi
}

# Main execution
main() {
    # Install yay first
    if ! arch_install_aur_helper; then
        log_error "Failed to install yay AUR helper"
        exit 1
    fi

    # Install rate-mirrors-bin and update mirrors
    if ! install_rate_mirrors_and_update; then
        log_error "Failed to install rate-mirrors-bin and update mirrors"
        exit 1
    fi

    log_success "AUR setup completed successfully"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
