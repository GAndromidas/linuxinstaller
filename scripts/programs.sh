#!/bin/bash
set -uo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LINUXINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$LINUXINSTALLER_ROOT/configs"
PROGRAMS_FILE="$CONFIGS_DIR/programs.yaml"

source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

# Validate DISTRO_ID is set
if [ -z "${DISTRO_ID:-}" ]; then
    log_error "DISTRO_ID is not set. Cannot continue."
    exit 1
fi

# Ensure yq is available for reading YAML configuration
if ! command -v yq >/dev/null; then
    ui_info "Installing yq..."
    if [ -n "${PKG_INSTALL:-}" ]; then
        $PKG_INSTALL ${PKG_NOCONFIRM:-} yq >/dev/null 2>&1 || {
            log_warning "Failed to install yq via package manager. Trying alternative method..."
            # Try binary installation as fallback
            ARCH="amd64"; [[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"
            VER="latest"
            if sudo curl -L -s -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" >/dev/null 2>&1; then
                sudo chmod +x /usr/local/bin/yq
                log_success "yq installed via binary"
            else
                log_error "Failed to install yq. Package installation will not work."
                return 1
            fi
        }
    fi
fi

# Get packages for current distro, mode, and desktop environment
get_packages() {
    local mode="${1:-standard}"
    local category="${2:-native}"

    # Read packages from YAML using yq
    if [ -f "$PROGRAMS_FILE" ] && command -v yq >/dev/null; then
        yq -r ".${DISTRO_ID}.${mode}.${category}[]?" "$PROGRAMS_FILE" 2>/dev/null || echo ""
    else
        log_warning "Cannot read programs.yaml or yq not available"
        echo ""
    fi
}

# Get DE-specific packages to install
get_de_packages_install() {
    local mode="${1:-standard}"
    local de="${XDG_CURRENT_DESKTOP:-unknown}"

    # Normalize DE name
    case "$de" in
        KDE|PLASMA|plasma) de="kde" ;;
        GNOME|gnome) de="gnome" ;;
        COSMIC|cosmic) de="cosmic" ;;
        *) de="kde" ;; # Default fallback
    esac

    if [ -f "$PROGRAMS_FILE" ] && command -v yq >/dev/null; then
        yq -r ".${DISTRO_ID}.${mode}.${de}.install[]?" "$PROGRAMS_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Get DE-specific packages to remove
get_de_packages_remove() {
    local mode="${1:-standard}"
    local de="${XDG_CURRENT_DESKTOP:-unknown}"

    # Normalize DE name
    case "$de" in
        KDE|PLASMA|plasma) de="kde" ;;
        GNOME|gnome) de="gnome" ;;
        COSMIC|cosmic) de="cosmic" ;;
        *) de="kde" ;; # Default fallback
    esac

    if [ -f "$PROGRAMS_FILE" ] && command -v yq >/dev/null; then
        yq -r ".${DISTRO_ID}.${mode}.${de}.remove[]?" "$PROGRAMS_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Get AUR packages (Arch only)
get_aur_packages() {
    local mode="${1:-standard}"

    if [ "$DISTRO_ID" != "arch" ]; then
        echo ""
        return
    fi

    if [ -f "$PROGRAMS_FILE" ] && command -v yq >/dev/null; then
        yq -r ".${DISTRO_ID}.${mode}.aur[]?" "$PROGRAMS_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Get Flatpak packages
get_flatpak_packages() {
    local mode="${1:-standard}"

    if [ -f "$PROGRAMS_FILE" ] && command -v yq >/dev/null; then
        yq -r ".${DISTRO_ID}.${mode}.flatpak[]?" "$PROGRAMS_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Get Snap packages (Ubuntu only)
get_snap_packages() {
    local mode="${1:-standard}"

    if [ "$DISTRO_ID" != "ubuntu" ]; then
        echo ""
        return
    fi

    if [ -f "$PROGRAMS_FILE" ] && command -v yq >/dev/null; then
        yq -r ".${DISTRO_ID}.${mode}.snap[]?" "$PROGRAMS_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Install packages quietly with error handling
install_packages_quietly() {
    local packages=("$@")
    local -a successful=()
    local -a failed=()

    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi

    ui_info "Installing ${#packages[@]} packages..."

    # Filter out empty packages
    local -a filtered_packages=()
    for pkg in "${packages[@]}"; do
        if [ -n "$pkg" ] && [ "$pkg" != "null" ]; then
            filtered_packages+=("$pkg")
        fi
    done

    if [ ${#filtered_packages[@]} -eq 0 ]; then
        return 0
    fi

    # Install packages
    if [ -n "${PKG_INSTALL:-}" ]; then
        if $PKG_INSTALL ${PKG_NOCONFIRM:-} "${filtered_packages[@]}" >> "$INSTALL_LOG" 2>&1; then
            log_success "Installed ${#filtered_packages[@]} packages"
            INSTALLED_PACKAGES+=("${filtered_packages[@]}")
            return 0
        else
            log_warning "Some packages failed to install"
            return 1
        fi
    else
        log_error "No package manager command available"
        return 1
    fi
}

# Remove packages quietly
remove_packages_quietly() {
    local packages=("$@")

    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi

    ui_info "Removing ${#packages[@]} packages..."

    # Filter out empty packages
    local -a filtered_packages=()
    for pkg in "${packages[@]}"; do
        if [ -n "$pkg" ] && [ "$pkg" != "null" ]; then
            filtered_packages+=("$pkg")
        fi
    done

    if [ ${#filtered_packages[@]} -eq 0 ]; then
        return 0
    fi

    # Remove packages
    if [ -n "${PKG_REMOVE:-}" ]; then
        if $PKG_REMOVE ${PKG_NOCONFIRM:-} "${filtered_packages[@]}" >> "$INSTALL_LOG" 2>&1; then
            log_success "Removed ${#filtered_packages[@]} packages"
            REMOVED_PACKAGES+=("${filtered_packages[@]}")
            return 0
        else
            log_warning "Some packages failed to remove"
            return 1
        fi
    else
        log_warning "No package removal command available"
        return 1
    fi
}

# Install AUR packages using yay (Arch only)
install_aur_packages() {
    local packages=("$@")

    if [ "$DISTRO_ID" != "arch" ]; then
        return 0
    fi

    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi

    # Filter out empty packages
    local -a filtered_packages=()
    for pkg in "${packages[@]}"; do
        if [ -n "$pkg" ] && [ "$pkg" != "null" ]; then
            filtered_packages+=("$pkg")
        fi
    done

    if [ ${#filtered_packages[@]} -eq 0 ]; then
        return 0
    fi

    ui_info "Installing ${#filtered_packages[@]} AUR packages..."

    # Ensure yay is installed
    if ! command -v yay >/dev/null 2>&1; then
        log_info "Installing yay AUR helper..."
        if ! command -v git >/dev/null 2>&1; then
            $PKG_INSTALL ${PKG_NOCONFIRM:-} git >> "$INSTALL_LOG" 2>&1
        fi

        cd /tmp
        git clone https://aur.archlinux.org/yay.git >> "$INSTALL_LOG" 2>&1
        cd yay
        makepkg -si --noconfirm >> "$INSTALL_LOG" 2>&1
        cd /tmp
        rm -rf yay
        log_success "yay installed"
    fi

    # Install AUR packages
    if yay -S --needed --noconfirm "${filtered_packages[@]}" >> "$INSTALL_LOG" 2>&1; then
        log_success "Installed ${#filtered_packages[@]} AUR packages"
        INSTALLED_PACKAGES+=("${filtered_packages[@]}")
        return 0
    else
        log_warning "Some AUR packages failed to install"
        return 1
    fi
}

# Install Flatpak packages
install_flatpak_packages() {
    local packages=("$@")

    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi

    # Filter out empty packages
    local -a filtered_packages=()
    for pkg in "${packages[@]}"; do
        if [ -n "$pkg" ] && [ "$pkg" != "null" ]; then
            filtered_packages+=("$pkg")
        fi
    done

    if [ ${#filtered_packages[@]} -eq 0 ]; then
        return 0
    fi

    # Skip Flatpak on Ubuntu server mode if not installed
    if [ "${DISTRO_ID:-}" == "ubuntu" ] && [ "${INSTALL_MODE:-}" == "server" ] && ! command -v flatpak >/dev/null 2>&1; then
        return 0
    fi

    if ! command -v flatpak >/dev/null; then
        ui_warn "Flatpak not found. Skipping Flatpak packages."
        return 1
    fi

    ui_info "Installing ${#filtered_packages[@]} Flatpak packages..."

    # Install Flatpak packages
    if flatpak install -y flathub "${filtered_packages[@]}" >> "$INSTALL_LOG" 2>&1; then
        log_success "Installed ${#filtered_packages[@]} Flatpak packages"
        INSTALLED_PACKAGES+=("${filtered_packages[@]}")
        return 0
    else
        log_warning "Some Flatpak packages failed to install"
        return 1
    fi
}

# Install Snap packages (Ubuntu only)
install_snap_packages() {
    local packages=("$@")

    if [ "$DISTRO_ID" != "ubuntu" ]; then
        return 0
    fi

    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi

    # Filter out empty packages
    local -a filtered_packages=()
    for pkg in "${packages[@]}"; do
        if [ -n "$pkg" ] && [ "$pkg" != "null" ]; then
            filtered_packages+=("$pkg")
        fi
    done

    if [ ${#filtered_packages[@]} -eq 0 ]; then
        return 0
    fi

    if ! command -v snap >/dev/null; then
        ui_warn "Snap not found. Installing snapd..."
        $PKG_INSTALL ${PKG_NOCONFIRM:-} snapd >> "$INSTALL_LOG" 2>&1
    fi

    ui_info "Installing ${#filtered_packages[@]} Snap packages..."

    # Install Snap packages
    local failed=0
    for pkg in "${filtered_packages[@]}"; do
        if snap install "$pkg" >> "$INSTALL_LOG" 2>&1; then
            INSTALLED_PACKAGES+=("$pkg")
        else
            log_warning "Failed to install Snap package: $pkg"
            failed=$((failed + 1))
        fi
    done

    if [ $failed -eq 0 ]; then
        log_success "Installed ${#filtered_packages[@]} Snap packages"
        return 0
    else
        log_warning "$failed Snap packages failed to install"
        return 1
    fi
}

# Main installation function
install_programs() {
    local mode="${INSTALL_MODE:-standard}"

    step "Installing programs for $DISTRO_ID ($mode mode)"

    # Read native packages
    local native_packages=()
    mapfile -t native_packages < <(get_packages "$mode" "native")

    # Install native packages
    if [ ${#native_packages[@]} -gt 0 ]; then
        install_packages_quietly "${native_packages[@]}"
    fi

    # Install AUR packages (Arch only)
    if [ "$DISTRO_ID" == "arch" ]; then
        local aur_packages=()
        mapfile -t aur_packages < <(get_aur_packages "$mode")
        if [ ${#aur_packages[@]} -gt 0 ]; then
            install_aur_packages "${aur_packages[@]}"
        fi
    fi

    # Install Flatpak packages (all distros except Ubuntu server)
    if [ ! "${INSTALL_MODE:-}" == "server" ] || [ "${DISTRO_ID:-}" != "ubuntu" ]; then
        local flatpak_packages=()
        mapfile -t flatpak_packages < <(get_flatpak_packages "$mode")
        if [ ${#flatpak_packages[@]} -gt 0 ]; then
            install_flatpak_packages "${flatpak_packages[@]}"
        fi
    fi

    # Install Snap packages (Ubuntu only)
    if [ "$DISTRO_ID" == "ubuntu" ]; then
        local snap_packages=()
        mapfile -t snap_packages < <(get_snap_packages "$mode")
        if [ ${#snap_packages[@]} -gt 0 ]; then
            install_snap_packages "${snap_packages[@]}"
        fi
    fi

    log_success "Package installation completed"
}

# Desktop environment package management
handle_desktop_environment_packages() {
    local mode="${INSTALL_MODE:-standard}"

    step "Configuring desktop environment packages"

    # Get DE packages to install
    local de_install=()
    mapfile -t de_install < <(get_de_packages_install "$mode")

    if [ ${#de_install[@]} -gt 0 ]; then
        ui_info "Installing ${#de_install[@]} DE-specific packages..."
        install_packages_quietly "${de_install[@]}"
    fi

    # Get DE packages to remove
    local de_remove=()
    mapfile -t de_remove < <(get_de_packages_remove "$mode")

    if [ ${#de_remove[@]} -gt 0 ]; then
        remove_packages_quietly "${de_remove[@]}"
    fi

    log_success "Desktop environment configuration completed"
}

# Gaming packages installation
install_gaming_packages() {
    if [ ! -f "$PROGRAMS_FILE" ] || ! command -v yq >/dev/null; then
        log_warning "Cannot read gaming packages configuration"
        return 1
    fi

    step "Installing gaming packages"

    # Read gaming packages for current distro
    local gaming_native=()
    mapfile -t gaming_native < <(yq -r ".gaming.${DISTRO_ID}.native[]?" "$PROGRAMS_FILE" 2>/dev/null || echo "")

    if [ ${#gaming_native[@]} -gt 0 ]; then
        install_packages_quietly "${gaming_native[@]}"
    fi

    # Install AUR gaming packages (Arch only)
    if [ "$DISTRO_ID" == "arch" ]; then
        local gaming_aur=()
        mapfile -t gaming_aur < <(yq -r ".gaming.${DISTRO_ID}.aur[]?" "$PROGRAMS_FILE" 2>/dev/null || echo "")
        if [ ${#gaming_aur[@]} -gt 0 ]; then
            install_aur_packages "${gaming_aur[@]}"
        fi
    fi

    # Install Flatpak gaming packages
    local gaming_flatpak=()
    mapfile -t gaming_flatpak < <(yq -r ".gaming.${DISTRO_ID}.flatpak[]?" "$PROGRAMS_FILE" 2>/dev/null || echo "")
    if [ ${#gaming_flatpak[@]} -gt 0 ]; then
        install_flatpak_packages "${gaming_flatpak[@]}"
    fi

    # Install Snap gaming packages (Ubuntu only)
    if [ "$DISTRO_ID" == "ubuntu" ]; then
        local gaming_snap=()
        mapfile -t gaming_snap < <(yq -r ".gaming.${DISTRO_ID}.snap[]?" "$PROGRAMS_FILE" 2>/dev/null || echo "")
        if [ ${#gaming_snap[@]} -gt 0 ]; then
            install_snap_packages "${gaming_snap[@]}"
        fi
    fi

    log_success "Gaming packages installation completed"
}

# Export functions for use in other scripts
export -f install_programs
export -f handle_desktop_environment_packages
export -f install_gaming_packages
export -f install_packages_quietly
export -f remove_packages_quietly
export -f install_aur_packages
export -f install_flatpak_packages
export -f install_snap_packages
