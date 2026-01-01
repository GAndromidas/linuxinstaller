#!/bin/bash
set -uo pipefail

# Gaming Configuration Module for LinuxInstaller
# Based on best practices from all installers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"



# =============================================================================
# GAMING CONFIGURATION FUNCTIONS
# =============================================================================

# Install gaming packages for current distribution
gaming_install_packages() {
    step "Installing Gaming Packages"

    log_info "Installing gaming packages for $DISTRO_ID..."

    if declare -f distro_get_packages >/dev/null 2>&1; then
        mapfile -t gaming_packages < <(distro_get_packages "gaming" "native" 2>/dev/null || true)

        if [ ${#gaming_packages[@]} -eq 0 ]; then
            log_warn "No gaming packages found for $DISTRO_ID"
            return
        fi

        for package in "${gaming_packages[@]}"; do
            if [ -n "$package" ]; then
                if ! install_pkg "$package"; then
                    log_warn "Failed to install gaming package: $package"
                else
                    log_success "Installed gaming package: $package"
                fi
            fi
        done
    else
        log_warn "distro_get_packages function not available. Gaming packages cannot be installed."
    fi
}

# Configure system settings for optimal gaming performance
gaming_configure_performance() {
    step "Configuring Gaming Performance"

    # Enable performance governor
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
        log_success "Set CPU governor to performance"
    fi

    # Configure swappiness for gaming
    if [ -f /proc/sys/vm/swappiness ]; then
        echo 10 | tee /proc/sys/vm/swappiness >/dev/null 2>&1
        log_success "Optimized swappiness for gaming (set to 10)"
    fi

    # Configure graphics settings
    if command -v nvidia-settings >/dev/null 2>&1; then
        log_info "Configuring NVIDIA settings for gaming..."
        nvidia-settings -a GPUPowerMizerMode=1 >/dev/null 2>&1 || true
        log_success "NVIDIA performance mode enabled"
    fi

    # Enable TRIM for SSDs
    local has_ssd=false
    for discard_file in /sys/block/*/queue/discard_max_bytes; do
        if [ -f "$discard_file" ]; then
            has_ssd=true
            break
        fi
    done
    if [ "$has_ssd" = true ]; then
        systemctl enable --now fstrim.timer >/dev/null 2>&1
        log_success "Enabled TRIM for SSD optimization"
    fi
}

# Configure MangoHud for gaming overlay statistics
gaming_configure_mangohud() {
    step "Configuring MangoHud"

    if ! command -v mangohud >/dev/null 2>&1; then
        log_warn "MangoHud not found. Install it via the distro's gaming packages."
        return
    fi

    log_info "MangoHud is installed and ready to use"
    log_info "To use MangoHud with games, run: mangohud <game_command>"
    log_success "MangoHud configured"
}

# Configure GameMode for performance optimization during gaming
gaming_configure_gamemode() {
    step "Configuring GameMode"

    if command -v gamemoded >/dev/null 2>&1; then
        log_info "GameMode already installed"

        # Enable and start GameMode service
        if systemctl enable --now gamemoded >/dev/null 2>&1; then
            log_success "GameMode service enabled and started"
        else
            log_warn "Failed to enable GameMode service"
        fi
    else
        log_warn "GameMode not found"
    fi
}

# Install and configure Steam gaming platform
gaming_configure_steam() {
    step "Configuring Steam"

    # Install Steam if not present
    if ! command -v steam >/dev/null 2>&1; then
        if ! install_pkg steam; then
            log_warn "Failed to install Steam"
            return
        fi
    fi

    # Configure Steam settings
    local steam_config_dir="$HOME/.steam"
    if [ -d "$steam_config_dir" ]; then
        log_info "Steam configuration directory found"

        # Enable Steam Play for all titles
        if [ -f "$steam_config_dir/config/config.vdf" ]; then
            sed -i 's/"bEnableSteamPlayForAllTitles" "0"/"bEnableSteamPlayForAllTitles" "1"/' "$steam_config_dir/config/config.vdf" 2>/dev/null || true
            log_success "Steam Play enabled for all titles"
        fi
    fi

    log_success "Steam configured"
}

# Install Faugus game launcher via Flatpak
gaming_install_faugus() {
    step "Installing Faugus (flatpak)"

    if ! command -v flatpak >/dev/null 2>&1; then
        log_warn "Flatpak not installed. Attempting to install flatpak..."
        if ! install_pkg flatpak; then
            log_warn "Failed to install flatpak; skipping Faugus installation"
            return
        fi
    fi

    # Ensure Flathub remote exists
    if ! flatpak remote-list | grep -q flathub; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
    fi

    # Install Faugus from Flathub if not present
    if flatpak list --app | grep -q "io.github.Faugus.faugus-launcher"; then
        log_info "Faugus (flatpak) already installed"
        return 0
    fi

    if flatpak install flathub -y io.github.Faugus.faugus-launcher; then
        log_success "Faugus (flatpak) installed"
    else
        log_warn "Failed to install Faugus (flatpak)"
    fi
}



# =============================================================================
# MAIN GAMING CONFIGURATION FUNCTION
# =============================================================================

gaming_main_config() {
    log_info "Starting gaming configuration..."

    # Check if gaming mode is enabled
    if [ "${INSTALL_GAMING:-false}" != "true" ]; then
        log_info "Gaming installation not requested. Skipping gaming configuration."
        return 0
    fi

    # Install gaming packages
    gaming_install_packages

    # Configure performance
    gaming_configure_performance

    # Configure MangoHud
    gaming_configure_mangohud

    # Configure GameMode
    gaming_configure_gamemode

    # Configure Steam
    gaming_configure_steam

    # Install Faugus (Flatpak)
    gaming_install_faugus



    log_success "Gaming configuration completed"
}

# Export functions for use by main installer
export -f gaming_main_config
export -f gaming_install_packages
export -f gaming_configure_performance
export -f gaming_configure_mangohud
export -f gaming_configure_gamemode
export -f gaming_configure_steam
export -f gaming_install_faugus
