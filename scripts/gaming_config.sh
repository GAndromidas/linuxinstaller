#!/bin/bash
set -uo pipefail

# Gaming Configuration Module for LinuxInstaller
# Based on best practices from all installers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# GPU Vendor IDs
GPU_AMD="0x1002"
GPU_INTEL="0x8086"
GPU_NVIDIA="0x10de"

# =============================================================================
# GPU DETECTION FUNCTIONS
# =============================================================================

detect_gpu() {
    step "Detecting GPU Hardware"

    local detected_gpus=()
    local gpu_info

    # Use lspci to detect GPUs
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local vendor_id=$(echo "$line" | grep -oP '\[\K[0-9a-fA-F]{4}(?=:)' | head -1)
            local device_name=$(echo "$line" | grep -oP '(?<=\]: ).*(?= \[\d{4}:)' | sed 's/^ *//')
            
            case "$vendor_id" in
                1002)
                    detected_gpus+=("AMD: $device_name")
                    ;;
                8086)
                    detected_gpus+=("Intel: $device_name")
                    ;;
                10de)
                    detected_gpus+=("NVIDIA: $device_name")
                    ;;
            esac
        fi
    done < <(lspci -nn | grep -iE "vga|3d|display")

    if [ ${#detected_gpus[@]} -eq 0 ]; then
        log_warn "No GPU detected"
        return 1
    fi

    log_success "Detected ${#detected_gpus[@]} GPU(s):"
    for gpu in "${detected_gpus[@]}"; do
        log_info "  - $gpu"
    done

    return 0
}

has_amd_gpu() {
    lspci -nn | grep -qi "vga.*1002\|3d.*1002\|display.*1002"
}

has_intel_gpu() {
    lspci -nn | grep -qi "vga.*8086\|3d.*8086\|display.*8086"
}

has_nvidia_gpu() {
    lspci -nn | grep -qi "vga.*10de\|3d.*10de\|display.*10de"
}

has_virtual_gpu() {
    # Detect virtual GPUs (Virtio, VMware, VirtualBox, etc.)
    lspci -nn | grep -qi "vga.*1af4\|3d.*1af4\|display.*1af4" ||  # Virtio
    lspci -nn | grep -qi "vga.*15ad\|3d.*15ad\|display.*15ad" ||  # VMware
    lspci -nn | grep -qi "vga.*80ee\|3d.*80ee\|display.*80ee" ||  # VirtualBox
    lspci -nn | grep -qi "vga.*1234\|3d.*1234\|display.*1234"     # Bochs/QEMU standard VGA
}

is_virtual_machine() {
    # Detect if running in a virtual machine
    if [ -f /proc/cpuinfo ]; then
        grep -qi "hypervisor\|vmware\|virtualbox\|kvm\|qemu\|xen" /proc/cpuinfo && return 0
    fi
    if [ -f /sys/class/dmi/id/product_name ]; then
        grep -qi "virtual\|vmware\|virtualbox\|kvm\|qemu\|xen" /sys/class/dmi/id/product_name && return 0
    fi
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        systemd-detect-virt --quiet && return 0
    fi
    return 1
}

# Robust Flatpak package installation function (same as main installer)
install_flatpak_packages() {
    local install_cmd="$1"
    local -n packages_ref="$2" installed_ref="$3" skipped_ref="$4" failed_ref="$5"

    for pkg in "${packages_ref[@]}"; do
        pkg="$(echo "$pkg" | xargs)"

        # Check if flatpak is already installed
        if flatpak list 2>/dev/null | grep -q "^${pkg}\s"; then
            skipped_ref+=("$pkg")
            continue
        fi

        if supports_gum; then
            if gum spin --spinner dot --title "" -- $install_cmd "$pkg" >/dev/null 2>&1; then
                installed_ref+=("$pkg")
            else
                failed_ref+=("$pkg")
            fi
        else
            if $install_cmd "$pkg" >/dev/null 2>&1; then
                installed_ref+=("$pkg")
            else
                failed_ref+=("$pkg")
            fi
        fi
    done
}

install_gpu_drivers() {
    step "Installing GPU Drivers"

    local amd_detected=false
    local intel_detected=false
    local nvidia_detected=false
    local virtual_detected=false

    has_amd_gpu && amd_detected=true
    has_intel_gpu && intel_detected=true
    has_nvidia_gpu && nvidia_detected=true
    has_virtual_gpu && virtual_detected=true

    # Skip GPU driver installation in virtual machines
    if is_virtual_machine; then
        log_info "Virtual machine detected - skipping physical GPU driver installation"
        log_info "Virtual GPU drivers are handled by the hypervisor"
        return 0
    fi

    if [ "$amd_detected" = true ]; then
        log_info "AMD GPU detected - installing AMD drivers"
        case "$DISTRO_ID" in
            arch|manjaro)
                install_pkg mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon 2>/dev/null || true
                log_success "AMD drivers installed (Mesa + Vulkan)"
                ;;
            fedora)
                install_pkg mesa-vulkan-drivers mesa-vulkan-drivers.i686 2>/dev/null || true
                log_success "AMD drivers installed (Mesa + Vulkan)"
                ;;
            debian|ubuntu)
                install_pkg mesa-vulkan-drivers:amd64 mesa-vulkan-drivers:i386 2>/dev/null || true
                log_success "AMD drivers installed (Mesa + Vulkan)"
                ;;
        esac
    fi

    if [ "$intel_detected" = true ]; then
        log_info "Intel GPU detected - installing Intel drivers"
        case "$DISTRO_ID" in
            arch|manjaro)
                install_pkg mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver 2>/dev/null || true
                log_success "Intel drivers installed (Mesa + Vulkan + Media Driver)"
                ;;
            fedora)
                install_pkg mesa-vulkan-drivers intel-media-driver 2>/dev/null || true
                log_success "Intel drivers installed (Mesa + Vulkan + Media Driver)"
                ;;
            debian|ubuntu)
                install_pkg mesa-vulkan-drivers:amd64 mesa-vulkan-drivers:i386 intel-media-va-driver:i386 2>/dev/null || true
                log_success "Intel drivers installed (Mesa + Vulkan + Media Driver)"
                ;;
        esac
    fi

    if [ "$nvidia_detected" = true ]; then
        log_warn "NVIDIA GPU detected"
        log_warn "================================"
        log_warn "NVIDIA proprietary drivers are NOT installed automatically by this script."
        log_warn ""
        log_warn "Please install NVIDIA drivers manually:"
        log_warn "  Arch/Manjaro: sudo pacman -S nvidia nvidia-utils"
        log_warn "  Fedora: sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda"
        log_warn "  Debian/Ubuntu: sudo apt install nvidia-driver"
        log_warn ""
        log_warn "After installing NVIDIA drivers, restart your system."
        log_warn "================================"
    fi
}

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

# Install gaming Flatpak packages (Heroic Launcher, ProtonPlus, Faugus)
gaming_install_flatpak_packages() {
    step "Installing Gaming Flatpak Applications"

    log_info "Installing gaming Flatpak applications for $DISTRO_ID..."

    if declare -f distro_get_packages >/dev/null 2>&1; then
        mapfile -t gaming_flatpak_packages < <(distro_get_packages "gaming" "flatpak" 2>/dev/null || true)

        if [ ${#gaming_flatpak_packages[@]} -eq 0 ]; then
            log_warn "No gaming Flatpak packages found for $DISTRO_ID"
            return
        fi

        local installed=()
        local skipped=()
        local failed=()

        # Use the same robust installation logic as the main installer
        install_flatpak_packages "flatpak install flathub -y" gaming_flatpak_packages installed skipped failed

        # Report results
        if [ ${#installed[@]} -gt 0 ]; then
            log_success "Installed gaming Flatpak applications: ${installed[*]}"
        fi
        if [ ${#skipped[@]} -gt 0 ]; then
            log_info "Gaming Flatpak applications already installed: ${skipped[*]}"
        fi
        if [ ${#failed[@]} -gt 0 ]; then
            log_warn "Failed to install gaming Flatpak applications: ${failed[*]}"
        fi
    else
        log_warn "distro_get_packages function not available. Gaming Flatpak packages cannot be installed."
    fi
}

# Install Faugus game launcher via Flatpak (robust implementation)
install_faugus_flatpak() {
    step "Installing Faugus (flatpak)"

    # Ensure Flatpak is available
    if ! command -v flatpak >/dev/null 2>&1; then
        log_info "Installing Flatpak package manager..."
        if ! install_pkg flatpak; then
            log_error "Failed to install Flatpak - cannot install Faugus"
            return 1
        fi
    fi

    # Ensure Flathub remote is configured
    if ! flatpak remote-list 2>/dev/null | grep -q flathub; then
        log_info "Adding Flathub remote..."
        if ! flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1; then
            log_error "Failed to add Flathub remote"
            return 1
        fi
        log_success "Flathub remote added"
    fi

    # Define the Flatpak package to install
    local faugus_packages=("io.github.Faugus.faugus-launcher")
    local installed=()
    local skipped=()
    local failed=()

    # Use the same robust installation logic as the main installer
    install_flatpak_packages "flatpak install flathub -y" faugus_packages installed skipped failed

    # Check results
    if [ ${#installed[@]} -gt 0 ]; then
        log_success "Faugus game launcher installed successfully"
        return 0
    elif [ ${#skipped[@]} -gt 0 ]; then
        log_info "Faugus game launcher already installed"
        return 0
    else
        log_error "Failed to install Faugus game launcher"
        if [ ${#failed[@]} -gt 0 ]; then
            log_error "Failed packages: ${failed[*]}"
        fi
        return 1
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

    # Detect GPU hardware
    detect_gpu

    # Install GPU drivers based on detected hardware
    install_gpu_drivers

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

    # Install gaming Flatpak packages (Heroic Launcher, ProtonPlus, Faugus)
    gaming_install_flatpak_packages

    # Install Faugus (Flatpak) - kept for backwards compatibility
    install_faugus_flatpak

    log_success "Gaming configuration completed"
}

# Export functions for use by main installer
export -f gaming_main_config
export -f detect_gpu
export -f has_amd_gpu
export -f has_intel_gpu
export -f has_nvidia_gpu
export -f has_virtual_gpu
export -f is_virtual_machine
export -f install_gpu_drivers
export -f install_flatpak_packages
export -f gaming_install_packages
export -f gaming_install_flatpak_packages
export -f gaming_configure_performance
export -f gaming_configure_mangohud
export -f gaming_configure_gamemode
export -f gaming_configure_steam
export -f install_faugus_flatpak
