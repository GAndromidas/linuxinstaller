#!/bin/bash
set -uo pipefail

# Gaming Configuration Module for LinuxInstaller
# Based on best practices from all installers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Gaming-specific package lists
GAMING_ESSENTIALS=(
    "steam"
    "lutris"
    "wine"
    "vulkan-icd-loader"
    "mesa"
)

GAMING_ARCH=(
    "lib32-vulkan-icd-loader"
    "lib32-mesa"
    "lib32-glibc"
    "protontricks"
    "mangohud"
    "gamemode"
)

GAMING_FEDORA=(
    "lib32-vulkan"
    "lib32-mesa-libGL"
    "lib32-glibc"
    "protontricks"
    "mangohud"
    "gamemode"
)

GAMING_DEBIAN=(
    "lib32-vulkan1"
    "lib32-mesa-libgl1"
    "lib32-glibc"
    "protontricks"
    "mangohud"
    "gamemode"
)

# =============================================================================
# GAMING CONFIGURATION FUNCTIONS
# =============================================================================

gaming_install_packages() {
    step "Installing Gaming Packages"

    log_info "Installing gaming essential packages..."
    for package in "${GAMING_ESSENTIALS[@]}"; do
        if ! install_pkg "$package"; then
            log_warn "Failed to install gaming package: $package"
        else
            log_success "Installed gaming package: $package"
        fi
    done

    # Install distribution-specific gaming packages
    case "$DISTRO_ID" in
        "arch")
            log_info "Installing Arch-specific gaming packages..."
            for package in "${GAMING_ARCH[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Arch gaming package: $package"
                else
                    log_success "Installed Arch gaming package: $package"
                fi
            done
            ;;
        "fedora")
            log_info "Installing Fedora-specific gaming packages..."
            for package in "${GAMING_FEDORA[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Fedora gaming package: $package"
                else
                    log_success "Installed Fedora gaming package: $package"
                fi
            done
            ;;
        "debian"|"ubuntu")
            log_info "Installing Debian/Ubuntu-specific gaming packages..."
            for package in "${GAMING_DEBIAN[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Debian gaming package: $package"
                else
                    log_success "Installed Debian gaming package: $package"
                fi
            done
            ;;
    esac
}

gaming_configure_performance() {
    step "Configuring Gaming Performance"

    # Enable performance governor
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
        log_success "Set CPU governor to performance"
    fi

    # Configure swappiness for gaming
    if [ -f /proc/sys/vm/swappiness ]; then
        echo 10 | sudo tee /proc/sys/vm/swappiness >/dev/null 2>&1
        log_success "Optimized swappiness for gaming (set to 10)"
    fi

    # Configure graphics settings
    if command -v nvidia-settings >/dev/null 2>&1; then
        log_info "Configuring NVIDIA settings for gaming..."
        sudo nvidia-settings -a GPUPowerMizerMode=1 >/dev/null 2>&1 || true
        log_success "NVIDIA performance mode enabled"
    fi

    # Enable TRIM for SSDs
    if [ -f /sys/block/*/queue/discard_max_bytes ]; then
        sudo systemctl enable --now fstrim.timer >/dev/null 2>&1
        log_success "Enabled TRIM for SSD optimization"
    fi
}

gaming_configure_mangohud() {
    step "Configuring MangoHud"

    if command -v mangohud >/dev/null 2>&1; then
        log_info "MangoHud already installed"
        return 0
    fi

    # Install MangoHud
    case "$DISTRO_ID" in
        "arch")
            if command -v yay >/dev/null 2>&1; then
                if ! yay -S --noconfirm mangohud >/dev/null 2>&1; then
                    log_warn "Failed to install MangoHud via yay"
                else
                    log_success "MangoHud installed via yay"
                fi
            elif command -v paru >/dev/null 2>&1; then
                if ! paru -S --noconfirm mangohud >/dev/null 2>&1; then
                    log_warn "Failed to install MangoHud via paru"
                else
                    log_success "MangoHud installed via paru"
                fi
            fi
            ;;
        "fedora")
            if ! sudo dnf install -y mangohud >/dev/null 2>&1; then
                log_warn "Failed to install MangoHud"
            else
                log_success "MangoHud installed"
            fi
            ;;
        "debian"|"ubuntu")
            if ! sudo apt-get install -y mangohud >/dev/null 2>&1; then
                log_warn "Failed to install MangoHud"
            else
                log_success "MangoHud installed"
            fi
            ;;
    esac

    # Configure MangoHud
    if [ -f "$HOME/.config/MangoHud/MangoHud.conf" ]; then
        log_info "MangoHud configuration already exists"
    else
        mkdir -p "$HOME/.config/MangoHud"
        cat > "$HOME/.config/MangoHud/MangoHud.conf" << EOF
# MangoHud Configuration
fps_limit=0
cpu_stats
gpu_stats
vram
ram
io
core_load
gpu_core_clock
gpu_mem_clock
gpu_temp
gpu_power
EOF
        log_success "MangoHud configured"
    fi
}

gaming_configure_gamemode() {
    step "Configuring GameMode"

    if command -v gamemoded >/dev/null 2>&1; then
        log_info "GameMode already installed"

        # Enable and start GameMode service
        if sudo systemctl enable --now gamemoded >/dev/null 2>&1; then
            log_success "GameMode service enabled and started"
        else
            log_warn "Failed to enable GameMode service"
        fi
    else
        log_warn "GameMode not found"
    fi
}

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

gaming_configure_lutris() {
    step "Configuring Lutris"

    # Install Lutris if not present
    if ! command -v lutris >/dev/null 2>&1; then
        if ! install_pkg lutris; then
            log_warn "Failed to install Lutris"
            return
        fi
    fi

    # Configure Lutris settings
    local lutris_config_dir="$HOME/.config/lutris"
    if [ -d "$lutris_config_dir" ]; then
        log_info "Lutris configuration directory found"
    else
        mkdir -p "$lutris_config_dir"
        log_success "Lutris configuration directory created"
    fi

    log_success "Lutris configured"
}

gaming_setup_protontricks() {
    step "Setting up Protontricks"

    if command -v protontricks >/dev/null 2>&1; then
        log_info "Protontricks already installed"
    else
        # Install Protontricks
        case "$DISTRO_ID" in
            "arch")
                if command -v yay >/dev/null 2>&1; then
                    if ! yay -S --noconfirm protontricks >/dev/null 2>&1; then
                        log_warn "Failed to install Protontricks via yay"
                    else
                        log_success "Protontricks installed via yay"
                    fi
                fi
                ;;
            "fedora")
                if ! sudo dnf install -y protontricks >/dev/null 2>&1; then
                    log_warn "Failed to install Protontricks"
                else
                    log_success "Protontricks installed"
                fi
                ;;
            "debian"|"ubuntu")
                if ! sudo apt-get install -y protontricks >/dev/null 2>&1; then
                    log_warn "Failed to install Protontricks"
                else
                    log_success "Protontricks installed"
                fi
                ;;
        esac
    fi
}

# =============================================================================
# MAIN GAMING CONFIGURATION FUNCTION
# =============================================================================

gaming_main_config() {
    log_info "Starting gaming configuration..."

    # Check if gaming mode is enabled
    if [ "$INSTALL_MODE" != "standard" ] && [ "$INSTALL_MODE" != "gaming" ]; then
        log_info "Gaming mode not selected for this installation mode"
        return 0
    fi

    # Install gaming packages
    if ! is_step_complete "gaming_install_packages"; then
        gaming_install_packages
        mark_step_complete "gaming_install_packages"
    fi

    # Configure performance
    if ! is_step_complete "gaming_configure_performance"; then
        gaming_configure_performance
        mark_step_complete "gaming_configure_performance"
    fi

    # Configure MangoHud
    if ! is_step_complete "gaming_configure_mangohud"; then
        gaming_configure_mangohud
        mark_step_complete "gaming_configure_mangohud"
    fi

    # Configure GameMode
    if ! is_step_complete "gaming_configure_gamemode"; then
        gaming_configure_gamemode
        mark_step_complete "gaming_configure_gamemode"
    fi

    # Configure Steam
    if ! is_step_complete "gaming_configure_steam"; then
        gaming_configure_steam
        mark_step_complete "gaming_configure_steam"
    fi

    # Configure Lutris
    if ! is_step_complete "gaming_configure_lutris"; then
        gaming_configure_lutris
        mark_step_complete "gaming_configure_lutris"
    fi

    # Setup Protontricks
    if ! is_step_complete "gaming_setup_protontricks"; then
        gaming_setup_protontricks
        mark_step_complete "gaming_setup_protontricks"
    fi

    log_success "Gaming configuration completed"
}

# Export functions for use by main installer
export -f gaming_main_config
export -f gaming_install_packages
export -f gaming_configure_performance
export -f gaming_configure_mangohud
export -f gaming_configure_gamemode
export -f gaming_configure_steam
export -f gaming_configure_lutris
export -f gaming_setup_protontricks


