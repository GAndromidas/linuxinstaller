#!/bin/bash
set -uo pipefail

# Fedora Configuration Module for LinuxInstaller
# Based on fedorainstaller best practices

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Ensure we're on Fedora
if [ "$DISTRO_ID" != "fedora" ]; then
    log_error "This module is for Fedora only"
    exit 1
fi

# Fedora-specific variables
FEDORA_REPOS_FILE="/etc/dnf/dnf.conf"
FEDORA_MIRRORLIST="/etc/yum.repos.d/fedora.repo"
FEDORA_MODULAR="/etc/yum.repos.d/fedora-modular.repo"

# Fedora-specific configuration files
FEDORA_CONFIGS_DIR="$SCRIPT_DIR/../configs/fedora"

# Fedora-specific package lists
FEDORA_ESSENTIALS=(
    "dnf-plugins-core"
    "git"
    "curl"
    "wget"
    "rsync"
    "bc"
    "openssh-server"
    "cronie"
    "bluez"
    "plymouth"
    "flatpak"
    "zoxide"
    "fzf"
    "fastfetch"
    "eza"
)

FEDORA_DESKTOP=(
    "gnome-tweaks"
    "dconf-editor"
    "gdm"
    "NetworkManager"
)

FEDORA_GAMING=(
    "steam"
    "lutris"
    "mesa-libGL"
    "mesa-libGLU"
    "vulkan"
    "vulkan-loader"
)

# =============================================================================
# FEDORA CONFIGURATION FUNCTIONS
# =============================================================================

fedora_system_preparation() {
    step "Fedora System Preparation"

    # Enable RPM Fusion repositories
    enable_rpmfusion_repos

    # Configure DNF for optimal performance
    configure_dnf_fedora

    # Update system
    log_info "Updating Fedora system..."
    if ! sudo dnf update -y >/dev/null 2>&1; then
        log_error "System update failed"
        return 1
    fi

    log_success "Fedora system preparation completed"
}

enable_rpmfusion_repos() {
    step "Enabling RPM Fusion Repositories"

    # Check if already enabled
    if ! dnf repolist | grep -q rpmfusion-free; then
        log_info "Installing RPM Fusion Free & Non-Free..."
        local fedora_version=$(rpm -E %fedora)

        if ! sudo dnf install -y \
            https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fedora_version.noarch.rpm \
            https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fedora_version.noarch.rpm >/dev/null 2>&1; then
            log_error "Failed to install RPM Fusion repositories"
            return 1
        fi

        log_success "RPM Fusion repositories enabled"
    else
        log_info "RPM Fusion repositories already enabled"
    fi
}

configure_dnf_fedora() {
    log_info "Configuring DNF for optimal performance..."

    # Backup original config
    if [ -f "$FEDORA_REPOS_FILE" ] && [ ! -f "${FEDORA_REPOS_FILE}.backup" ]; then
        sudo cp "$FEDORA_REPOS_FILE" "${FEDORA_REPOS_FILE}.backup"
    fi

    # Optimize DNF configuration
    local optimizations=(
        "max_parallel_downloads=10"
        "fastestmirror=True"
        "defaultyes=True"
        "keepcache=True"
        "install_weak_deps=False"
    )

    for opt in "${optimizations[@]}"; do
        local key=$(echo "$opt" | cut -d= -f1)
        if grep -q "^$key" "$FEDORA_REPOS_FILE"; then
            sudo sed -i "s/^$key=.*/$opt/" "$FEDORA_REPOS_FILE"
        else
            echo "$opt" | sudo tee -a "$FEDORA_REPOS_FILE" >/dev/null
        fi
    done

    # Enable PowerTools repository for additional packages
    if [ -f /etc/yum.repos.d/fedora-cisco-openh264.repo ]; then
        sudo dnf config-manager --set-enabled fedora-cisco-openh264 >/dev/null 2>&1 || true
    fi

    log_success "DNF configured with optimizations"
}

fedora_install_essentials() {
    step "Installing Fedora Essential Packages"

    log_info "Installing essential packages..."
    for package in "${FEDORA_ESSENTIALS[@]}"; do
        if ! sudo dnf install -y "$package" >/dev/null 2>&1; then
            log_warn "Failed to install essential package: $package"
        else
            log_success "Installed essential package: $package"
        fi
    done

    # Install desktop packages if not server mode
    if [ "$INSTALL_MODE" != "server" ]; then
        log_info "Installing desktop packages..."
        for package in "${FEDORA_DESKTOP[@]}"; do
            if ! sudo dnf install -y "$package" >/dev/null 2>&1; then
                log_warn "Failed to install desktop package: $package"
            else
                log_success "Installed desktop package: $package"
            fi
        done
    fi
}

fedora_configure_bootloader() {
    step "Configuring Fedora Bootloader"

    local bootloader
    bootloader=$(detect_bootloader)

    case "$bootloader" in
        "grub")
            configure_grub_fedora
            ;;
        "systemd-boot")
            configure_systemd_boot_fedora
            ;;
        *)
            log_warn "Unknown bootloader: $bootloader"
            log_info "Please manually add 'quiet splash' to your kernel parameters"
            ;;
    esac
}

configure_grub_fedora() {
    log_info "Configuring GRUB for Fedora..."

    if [ ! -f /etc/default/grub ]; then
        log_error "/etc/default/grub not found"
        return 1
    fi

    # Set timeout
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

    # Add Fedora-specific kernel parameters
    local fedora_params="quiet splash"
    local current_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub)
    local current_params=""

    if [ -n "$current_line" ]; then
        current_params=$(echo "$current_line" | cut -d'=' -f2- | sed "s/^['\"]//;s/['\"]$//")
    fi

    local new_params="$current_params"
    local changed=false

    for param in $fedora_params; do
        if [[ ! "$new_params" == *"$param"* ]]; then
            new_params="$new_params $param"
            changed=true
        fi
    done

    if [ "$changed" = true ]; then
        sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_params\"|" /etc/default/grub
        log_success "Updated GRUB kernel parameters"
    fi

    # Regenerate GRUB config
    log_info "Regenerating GRUB configuration..."
    if [ -d /sys/firmware/efi ]; then
        if ! sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg >/dev/null 2>&1; then
            log_error "Failed to regenerate GRUB config"
            return 1
        fi
    else
        if ! sudo grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1; then
            log_error "Failed to regenerate GRUB config"
            return 1
        fi
    fi

    log_success "GRUB configured successfully"
}

configure_systemd_boot_fedora() {
    log_info "Configuring systemd-boot for Fedora..."

    local entries_dir=""
    if [ -d "/boot/loader/entries" ]; then
        entries_dir="/boot/loader/entries"
    elif [ -d "/efi/loader/entries" ]; then
        entries_dir="/efi/loader/entries"
    elif [ -d "/boot/efi/loader/entries" ]; then
        entries_dir="/boot/efi/loader/entries"
    fi

    if [ -z "$entries_dir" ]; then
        log_error "Could not find systemd-boot entries directory"
        return 1
    fi

    local fedora_params="quiet splash"
    local updated=false

    for entry in "$entries_dir"/*.conf; do
        [ -e "$entry" ] || continue
        if [ -f "$entry" ]; then
            if ! grep -q "splash" "$entry"; then
                if grep -q "^options" "$entry"; then
                    sudo sed -i "/^options/ s/$/ $fedora_params/" "$entry"
                    log_success "Updated $entry"
                    updated=true
                else
                    echo "options $fedora_params" | sudo tee -a "$entry" >/dev/null
                    log_success "Updated $entry (added options)"
                    updated=true
                fi
            fi
        fi
    done

    if [ "$updated" = true ]; then
        log_success "systemd-boot entries updated"
    else
        log_info "systemd-boot entries already configured"
    fi
}

fedora_enable_system_services() {
    step "Enabling Fedora System Services"

    # Essential services
    local services=(
        "cronie"
        "bluetooth"
        "sshd"
        "fstrim.timer"
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            if sudo systemctl enable --now "$service" >/dev/null 2>&1; then
                log_success "Enabled and started $service"
            else
                log_warn "Failed to enable $service"
            fi
        fi
    done

    # Configure firewall (firewalld for Fedora)
    if ! sudo dnf install -y firewalld >/dev/null 2>&1; then
        log_warn "Failed to install firewalld"
        return
    fi

    # Configure firewalld
    if sudo systemctl enable --now firewalld >/dev/null 2>&1; then
        sudo firewall-cmd --set-default-zone=public >/dev/null 2>&1
        sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
        sudo firewall-cmd --reload >/dev/null 2>&1
        log_success "firewalld enabled and configured"
    else
        log_warn "Failed to enable firewalld"
    fi
}

fedora_setup_flatpak() {
    step "Setting up Flatpak for Fedora"

    if ! command -v flatpak >/dev/null; then
        log_info "Installing Flatpak..."
        if ! sudo dnf install -y flatpak >/dev/null 2>&1; then
            log_warn "Failed to install Flatpak"
            return
        fi
    fi

    # Add Flathub
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
    log_success "Flatpak configured with Flathub"
}

# =============================================================================
# MAIN FEDORA CONFIGURATION FUNCTION
# =============================================================================

fedora_main_config() {
    log_info "Starting Fedora configuration..."

    # System Preparation
    if ! is_step_complete "fedora_system_preparation"; then
        fedora_system_preparation
        mark_step_complete "fedora_system_preparation"
    fi

    # DNF Configuration
    if ! is_step_complete "fedora_dnf_config"; then
        fedora_configure_dnf
        mark_step_complete "fedora_dnf_config"
    fi

    # Enable RPM Fusion
    if ! is_step_complete "fedora_rpmfusion"; then
        fedora_enable_rpmfusion
        mark_step_complete "fedora_rpmfusion"
    fi

    # Setup COPR repositories
    if ! is_step_complete "fedora_copr"; then
        fedora_setup_copr
        mark_step_complete "fedora_copr"
    fi

    # Install Essentials
    if ! is_step_complete "fedora_install_essentials"; then
        fedora_install_essentials
        mark_step_complete "fedora_install_essentials"
    fi

    # Bootloader Configuration
    if ! is_step_complete "fedora_bootloader"; then
        fedora_configure_bootloader
        mark_step_complete "fedora_bootloader"
    fi

    # System Services
    if ! is_step_complete "fedora_system_services"; then
        fedora_enable_system_services
        mark_step_complete "fedora_system_services"
    fi

    # Flatpak Setup
    if ! is_step_complete "fedora_flatpak"; then
        fedora_setup_flatpak
        mark_step_complete "fedora_flatpak"
    fi

    # Shell Setup
    if ! is_step_complete "fedora_shell_setup"; then
        fedora_setup_shell
        mark_step_complete "fedora_shell_setup"
    fi

    # Logitech Hardware Support
    if ! is_step_complete "fedora_solaar_setup"; then
        fedora_setup_solaar
        mark_step_complete "fedora_solaar_setup"
    fi

    log_success "Fedora configuration completed"
}

fedora_setup_shell() {
    step "Setting up ZSH shell environment"

    # Set ZSH as default
    if [ "$SHELL" != "$(command -v zsh)" ]; then
        log_info "Changing default shell to ZSH..."
        if sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null; then
            log_success "Default shell changed to ZSH"
        else
            log_warning "Failed to change shell. You may need to do this manually."
        fi
    fi

    # Deploy config files
    mkdir -p "$HOME/.config"

    # Copy distro-specific .zshrc
    if [ -f "$FEDORA_CONFIGS_DIR/.zshrc" ]; then
        cp "$FEDORA_CONFIGS_DIR/.zshrc" "$HOME/.zshrc" && log_success "Updated config: .zshrc"
    fi

    # Copy starship config
    if [ -f "$FEDORA_CONFIGS_DIR/starship.toml" ]; then
        cp "$FEDORA_CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml" && log_success "Updated config: starship.toml"
    fi

    # Fastfetch setup
    if command -v fastfetch >/dev/null; then
        mkdir -p "$HOME/.config/fastfetch"

        local dest_config="$HOME/.config/fastfetch/config.jsonc"

        # Overwrite with custom if available
        if [ -f "$FEDORA_CONFIGS_DIR/config.jsonc" ]; then
            cp "$FEDORA_CONFIGS_DIR/config.jsonc" "$dest_config"

            # Smart Icon Replacement
            # Default in file is Arch: " "
            local os_icon=" " # Fedora icon

            # Replace the icon in the file
            # We look for the line containing "key": " " and substitute.
            # Using specific regex to match the exact Arch icon  in the key value.
            sed -i "s/\"key\": \" \"/\"key\": \"$os_icon\"/" "$dest_config"

            log_success "Applied custom fastfetch config with Fedora icon"
        else
           # Generate default if completely missing
           if [ ! -f "$dest_config" ]; then
             fastfetch --gen-config &>/dev/null
           fi
        fi
    fi
}

# =============================================================================
# DNF OPTIMIZATION AND REPOSITORY CONFIGURATION
# =============================================================================

fedora_configure_dnf() {
    step "Configuring DNF for optimal performance"

    # Create or update dnf.conf
    if [ ! -f "$FEDORA_REPOS_FILE" ]; then
        sudo touch "$FEDORA_REPOS_FILE"
    fi

    # Add DNF optimizations
    log_info "Adding DNF optimizations..."

    # Enable fastestmirror
    if ! grep -q "^fastestmirror=true" "$FEDORA_REPOS_FILE"; then
        echo "fastestmirror=true" | sudo tee -a "$FEDORA_REPOS_FILE" >/dev/null
        log_success "Enabled fastestmirror"
    else
        log_info "fastestmirror already enabled"
    fi

    # Set parallel downloads
    if ! grep -q "^max_parallel_downloads" "$FEDORA_REPOS_FILE"; then
        echo "max_parallel_downloads=10" | sudo tee -a "$FEDORA_REPOS_FILE" >/dev/null
        log_success "Set max_parallel_downloads=10"
    else
        sudo sed -i 's/^max_parallel_downloads=.*/max_parallel_downloads=10/' "$FEDORA_REPOS_FILE"
        log_info "Updated max_parallel_downloads=10"
    fi

    # Enable default yes (assume yes for all prompts)
    if ! grep -q "^assumeyes" "$FEDORA_REPOS_FILE"; then
        echo "assumeyes=True" | sudo tee -a "$FEDORA_REPOS_FILE" >/dev/null
        log_success "Enabled assumeyes=True"
    else
        sudo sed -i 's/^assumeyes=.*/assumeyes=True/' "$FEDORA_REPOS_FILE"
        log_info "Updated assumeyes=True"
    fi

    # Enable color output
    if ! grep -q "^color" "$FEDORA_REPOS_FILE"; then
        echo "color=always" | sudo tee -a "$FEDORA_REPOS_FILE" >/dev/null
        log_success "Enabled color output"
    else
        sudo sed -i 's/^color=.*/color=always/' "$FEDORA_REPOS_FILE"
        log_info "Updated color setting"
    fi

    # Enable delta RPMs for faster downloads
    if ! grep -q "^deltarpm" "$FEDORA_REPOS_FILE"; then
        echo "deltarpm=True" | sudo tee -a "$FEDORA_REPOS_FILE" >/dev/null
        log_success "Enabled delta RPMs"
    else
        sudo sed -i 's/^deltarpm=.*/deltarpm=True/' "$FEDORA_REPOS_FILE"
        log_info "Updated delta RPM setting"
    fi

    log_success "DNF configuration completed"
}

fedora_enable_rpmfusion() {
    step "Enabling RPM Fusion repositories"

    # Enable RPM Fusion Free
    log_info "Enabling RPM Fusion Free repository..."
    if ! sudo dnf install -y rpmfusion-free-release; then
        log_error "Failed to enable RPM Fusion Free"
        return 1
    fi

    # Enable RPM Fusion Non-Free
    log_info "Enabling RPM Fusion Non-Free repository..."
    if ! sudo dnf install -y rpmfusion-nonfree-release; then
        log_error "Failed to enable RPM Fusion Non-Free"
        return 1
    fi

    # Update package cache
    log_info "Updating package cache..."
    if ! sudo dnf makecache -y; then
        log_error "Failed to update package cache"
        return 1
    fi

    log_success "RPM Fusion repositories enabled"
}

fedora_setup_copr() {
    step "Setting up COPR repositories"

    # Install dnf-plugins-core if not already installed
    if ! sudo dnf install -y dnf-plugins-core; then
        log_error "Failed to install dnf-plugins-core"
        return 1
    fi

    # Add COPR repositories from programs.yaml
    # For now, we'll add the eza repository manually
    log_info "Adding COPR repository for eza..."
    if ! sudo dnf copr enable -y alternateved/eza; then
        log_error "Failed to enable COPR repository for eza"
        return 1
    fi

    # Update package cache after COPR
    log_info "Updating package cache after COPR..."
    if ! sudo dnf makecache -y; then
        log_error "Failed to update package cache after COPR"
        return 1
    fi

    log_success "COPR repositories configured"
}

fedora_setup_solaar() {
    # Skip solaar for server mode
    if [ "$INSTALL_MODE" == "server" ]; then
        log_info "Server mode selected, skipping solaar installation"
        return 0
    fi

    # Skip solaar if no desktop environment
    if [ -z "${XDG_CURRENT_DESKTOP:-}" ]; then
        log_info "No desktop environment detected, skipping solaar installation"
        return 0
    fi

    step "Setting up Logitech Hardware Support"

    # Check for Logitech hardware
    local has_logitech=false

    # Check USB devices for Logitech
    if lsusb | grep -i logitech >/dev/null 2>&1; then
        has_logitech=true
        log_info "Logitech hardware detected via USB"
    fi

    # Check Bluetooth devices for Logitech
    if command -v bluetoothctl >/dev/null 2>&1; then
        if bluetoothctl devices | grep -i logitech >/dev/null 2>&1; then
            has_logitech=true
            log_info "Logitech Bluetooth device detected"
        fi
    fi

    # Check for Logitech HID devices
    if ls /dev/hidraw* 2>/dev/null | xargs -I {} sh -c 'cat /sys/class/hidraw/{}/device/uevent 2>/dev/null | grep -i logitech' >/dev/null 2>&1; then
        has_logitech=true
        log_info "Logitech HID device detected"
    fi

    if [ "$has_logitech" = true ]; then
        log_info "Installing solaar for Logitech hardware management..."
        if install_pkg solaar; then
            log_success "Solaar installed successfully"

            # Enable solaar service
            if sudo systemctl enable --now solaar.service >/dev/null 2>&1; then
                log_success "Solaar service enabled and started"
            else
                log_warn "Failed to enable solaar service"
            fi
        else
            log_warn "Failed to install solaar"
        fi
    else
        log_info "No Logitech hardware detected, skipping solaar installation"
    fi
}

# Export functions for use by main installer
export -f fedora_main_config
export -f fedora_system_preparation
export -f fedora_configure_dnf
export -f fedora_enable_rpmfusion
export -f fedora_setup_copr
export -f fedora_install_essentials
export -f fedora_configure_bootloader
export -f fedora_enable_system_services
export -f fedora_setup_flatpak
export -f fedora_setup_shell
export -f fedora_setup_solaar
