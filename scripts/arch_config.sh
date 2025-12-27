#!/bin/bash
set -uo pipefail

# Arch Linux Configuration Module for LinuxInstaller
# Based on archinstaller best practices

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Ensure we're on Arch Linux
if [ "$DISTRO_ID" != "arch" ]; then
    log_error "This module is for Arch Linux only"
    exit 1
fi

# Arch-specific variables
ARCH_REPOS_FILE="/etc/pacman.conf"
ARCH_MIRRORLIST="/etc/pacman.d/mirrorlist"
ARCH_KEYRING="/etc/pacman.d/gnupg"
AUR_HELPER="yay"
PARALLEL_DOWNLOADS=10

# Arch-specific package lists
ARCH_ESSENTIALS=(
    "base-devel"
    "pacman-contrib"
    "expac"
    "git"
    "curl"
    "wget"
    "rsync"
    "bc"
    "openssh"
    "cronie"
    "bluez-utils"
    "plymouth"
    "flatpak"
    "zoxide"
    "fzf"
    "fastfetch"
    "eza"
)

ARCH_OPTIMIZATION=(
    "linux-lts"
    "linux-lts-headers"
    "btrfs-assistant"
    "btrfsmaintenance"
)

# =============================================================================
# ARCH LINUX CONFIGURATION FUNCTIONS
# =============================================================================

arch_system_preparation() {
    step "Arch Linux System Preparation"

    # Initialize keyring if needed
    if [ ! -d "$ARCH_KEYRING" ]; then
        log_info "Initializing Arch Linux keyring..."
        if ! sudo pacman-key --init >/dev/null 2>&1; then
            log_error "Failed to initialize keyring"
            return 1
        fi
        if ! sudo pacman-key --populate archlinux >/dev/null 2>&1; then
            log_error "Failed to populate keyring"
            return 1
        fi
    fi

    # Configure pacman for optimal performance
    configure_pacman_arch

    # Enable multilib repository
    check_and_enable_multilib

    # Optimize mirrorlist based on network speed
    optimize_mirrors_arch

    # Install AUR helper (yay) for package installation
    install_aur_helper_arch

    # Update system
    log_info "Updating Arch Linux system..."
    if ! sudo pacman -Syu --noconfirm >/dev/null 2>&1; then
        log_error "System update failed"
        return 1
    fi

    log_success "Arch system preparation completed"
}

configure_pacman_arch() {
    log_info "Configuring pacman for optimal performance..."

    # Backup original config
    if [ -f "$ARCH_REPOS_FILE" ] && [ ! -f "${ARCH_REPOS_FILE}.backup" ]; then
        sudo cp "$ARCH_REPOS_FILE" "${ARCH_REPOS_FILE}.backup"
    fi

    # Enable Color output
    if grep -q "^#Color" "$ARCH_REPOS_FILE"; then
        sudo sed -i 's/^#Color/Color/' "$ARCH_REPOS_FILE"
    fi

    # Enable ParallelDownloads
    if grep -q "^#ParallelDownloads" "$ARCH_REPOS_FILE"; then
        sudo sed -i "s/^#ParallelDownloads.*/ParallelDownloads = $PARALLEL_DOWNLOADS/" "$ARCH_REPOS_FILE"
    elif grep -q "^ParallelDownloads" "$ARCH_REPOS_FILE"; then
        sudo sed -i "s/^ParallelDownloads.*/ParallelDownloads = $PARALLEL_DOWNLOADS/" "$ARCH_REPOS_FILE"
    else
        sudo sed -i "/^\[options\]/a ParallelDownloads = $PARALLEL_DOWNLOADS" "$ARCH_REPOS_FILE"
    fi

    # Enable ILoveCandy
    if grep -q "^#ILoveCandy" "$ARCH_REPOS_FILE"; then
        sudo sed -i 's/^#ILoveCandy/ILoveCandy/' "$ARCH_REPOS_FILE"
    fi

    log_success "pacman configured with optimizations"
}

check_and_enable_multilib() {
    log_info "Checking and enabling multilib repository..."

    if ! grep -q "^\[multilib\]" "$ARCH_REPOS_FILE"; then
        log_info "Enabling multilib repository..."
        sudo sed -i '/\[options\]/a # Multilib repository\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' "$ARCH_REPOS_FILE"
        log_success "multilib repository enabled"
    else
        log_info "multilib repository already enabled"
    fi
}

install_aur_helper_arch() {
    step "Installing AUR Helper (yay)"

    # Check if yay is already installed
    if command -v yay >/dev/null 2>&1; then
        log_success "yay is already installed"
        return 0
    fi

    # Install base-devel first (required for building AUR packages)
    log_info "Installing base-devel for AUR package building..."
    if ! sudo pacman -S --noconfirm --needed base-devel >/dev/null 2>&1; then
        log_error "Failed to install base-devel"
        return 1
    fi

    # Install git if not already installed (needed for cloning yay)
    if ! sudo pacman -S --noconfirm --needed git >/dev/null 2>&1; then
        log_error "Failed to install git"
        return 1
    fi

    # Clone and build yay manually
    log_info "Building yay AUR helper from source..."
    local temp_dir=$(mktemp -d)
    chmod 777 "$temp_dir"

    local run_as_user=""
    if [ "$EUID" -eq 0 ]; then
         if [ -n "${SUDO_USER:-}" ]; then
             run_as_user="sudo -u $SUDO_USER"
             chown "$SUDO_USER:$SUDO_USER" "$temp_dir"
         else
             run_as_user="sudo -u nobody"
             chown nobody:nobody "$temp_dir"
         fi
    fi

    cd "$temp_dir" || return 1

    if $run_as_user git clone https://aur.archlinux.org/yay.git . >/dev/null 2>&1; then
        if $run_as_user makepkg -si --noconfirm --needed >/dev/null 2>&1; then
            log_success "yay AUR helper installed successfully"
        else
            log_error "Failed to build yay"
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

optimize_mirrors_arch() {
    step "Optimizing Arch Linux mirrors"

    # Check if rate-mirrors is available
    if ! command -v rate-mirrors >/dev/null 2>&1; then
        log_info "Installing rate-mirrors for mirror optimization..."
        if ! sudo pacman -S --noconfirm --needed rate-mirrors-bin >/dev/null 2>&1; then
            log_warn "Failed to install rate-mirrors-bin"
            return
        fi
    fi

    # Test network speed and optimize mirrors
    local speed_test_output=""
    if command -v speedtest-cli >/dev/null 2>&1; then
        log_info "Testing network speed for mirror optimization..."
        speed_test_output=$(timeout 30s speedtest-cli --simple 2>/dev/null || echo "")
    fi

    if [ -n "$speed_test_output" ]; then
        local download_speed=$(echo "$speed_test_output" | grep "Download:" | awk '{print $2}')
        if [ -n "$download_speed" ]; then
            local speed_int=$(echo "$download_speed" | cut -d. -f1)

            if [ "$speed_int" -lt 5 ]; then
                log_warn "Slow connection detected (< 5 Mbit/s)"
                PARALLEL_DOWNLOADS=3
                sudo sed -i "s/^ParallelDownloads.*/ParallelDownloads = 3/" "$ARCH_REPOS_FILE"
            elif [ "$speed_int" -lt 20 ]; then
                log_info "Moderate connection detected"
                PARALLEL_DOWNLOADS=6
                sudo sed -i "s/^ParallelDownloads.*/ParallelDownloads = 6/" "$ARCH_REPOS_FILE"
            else
                log_success "Fast connection detected, using maximum parallel downloads"
                PARALLEL_DOWNLOADS=10
            fi
        fi
    fi

    # Update mirrorlist
    log_info "Updating mirrorlist with optimized mirrors..."
    if ! sudo rate-mirrors --allow-root --save "$ARCH_MIRRORLIST" arch >/dev/null 2>&1; then
        log_warn "Failed to update mirrorlist automatically"
    fi
}

arch_setup_aur_helper() {
    # Simple wrapper that calls the new function
    arch_install_aur_helper
}

arch_configure_bootloader() {
    step "Configuring Arch Linux Bootloader"

    local bootloader
    bootloader=$(detect_bootloader)

    case "$bootloader" in
        "grub")
            configure_grub_arch
            ;;
        "systemd-boot")
            configure_systemd_boot_arch
            ;;
        *)
            log_warn "Unknown bootloader: $bootloader"
            log_info "Please manually add 'quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0' to your kernel parameters"
            ;;
    esac
}

configure_grub_arch() {
    log_info "Configuring GRUB for Arch Linux..."

    if [ ! -f /etc/default/grub ]; then
        log_error "/etc/default/grub not found"
        return 1
    fi

    # Set timeout
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

    # Add Arch-specific kernel parameters
    local arch_params="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
    local current_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub)
    local current_params=""

    if [ -n "$current_line" ]; then
        current_params=$(echo "$current_line" | cut -d'=' -f2- | sed "s/^['\"]//;s/['\"]$//")
    fi

    local new_params="$current_params"
    local changed=false

    for param in $arch_params; do
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
    if ! sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
        log_error "Failed to regenerate GRUB config"
        return 1
    fi

    log_success "GRUB configured successfully"
}

configure_systemd_boot_arch() {
    log_info "Configuring systemd-boot for Arch Linux..."

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

    local arch_params="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
    local updated=false

    for entry in "$entries_dir"/*.conf; do
        [ -e "$entry" ] || continue
        if [ -f "$entry" ]; then
            if ! grep -q "splash" "$entry"; then
                if grep -q "^options" "$entry"; then
                    sudo sed -i "/^options/ s/$/ $arch_params/" "$entry"
                    log_success "Updated $entry"
                    updated=true
                else
                    echo "options $arch_params" | sudo tee -a "$entry" >/dev/null
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

arch_enable_system_services() {
    step "Enabling Arch Linux System Services"

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

    # ZRAM configuration for Arch
    arch_configure_zram
}

arch_configure_zram() {
    step "Configuring ZRAM for Arch Linux"

    if ! command -v zramctl >/dev/null; then
        log_warn "zramctl not found, skipping ZRAM configuration"
        return
    fi

    if [ ! -f /etc/systemd/zram-generator.conf ]; then
        log_info "Creating ZRAM configuration..."
        sudo tee /etc/systemd/zram-generator.conf > /dev/null << EOF
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
EOF
        sudo systemctl daemon-reload
        if sudo systemctl start systemd-zram-setup@zram0.service >/dev/null 2>&1; then
            log_success "ZRAM configured and started"
        else
            log_warn "Failed to start ZRAM service"
        fi
    else
        log_info "ZRAM configuration already exists"
    fi
}

# =============================================================================
# MAIN ARCH CONFIGURATION FUNCTION
# =============================================================================

arch_main_config() {
    log_info "Starting Arch Linux configuration..."

    # System Preparation
    if ! is_step_complete "arch_system_preparation"; then
        arch_system_preparation
        mark_step_complete "arch_system_preparation"
    fi

    # AUR Helper Setup (already done in system preparation)
    if ! is_step_complete "arch_aur_helper"; then
        # AUR helper is already installed in system preparation
        log_success "AUR helper (yay) is ready"
        mark_step_complete "arch_aur_helper"
    fi

    # Mirror Configuration (after AUR helper is installed)
    if ! is_step_complete "arch_mirrors"; then
        arch_configure_mirrors
        mark_step_complete "arch_mirrors"
    fi

    # Bootloader Configuration
    if ! is_step_complete "arch_bootloader"; then
        arch_configure_bootloader
        mark_step_complete "arch_bootloader"
    fi

    # Plymouth Configuration (Arch Linux only)
    if ! is_step_complete "arch_plymouth"; then
        arch_configure_plymouth
        mark_step_complete "arch_plymouth"
    fi

    # Shell Setup
    if ! is_step_complete "arch_shell_setup"; then
        arch_setup_shell
        mark_step_complete "arch_shell_setup"
    fi

    # KDE Shortcuts (Arch Linux only)
    if ! is_step_complete "arch_kde_shortcuts"; then
        arch_setup_kde_shortcuts
        mark_step_complete "arch_kde_shortcuts"
    fi

    # Logitech Hardware Support
    if ! is_step_complete "arch_solaar_setup"; then
        arch_setup_solaar
        mark_step_complete "arch_solaar_setup"
    fi

    # System Services
    if ! is_step_complete "arch_system_services"; then
        arch_enable_system_services
        mark_step_complete "arch_system_services"
    fi

    log_success "Arch Linux configuration completed"
}

# Arch-specific configuration files
ARCH_CONFIGS_DIR="$SCRIPT_DIR/../configs/arch"

# KDE-specific configuration files
KDE_CONFIGS_DIR="$SCRIPT_DIR/../configs/arch"

arch_setup_shell() {
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
    if [ -f "$ARCH_CONFIGS_DIR/.zshrc" ]; then
        cp "$ARCH_CONFIGS_DIR/.zshrc" "$HOME/.zshrc" && log_success "Updated config: .zshrc"
    fi

    # Copy starship config
    if [ -f "$ARCH_CONFIGS_DIR/starship.toml" ]; then
        cp "$ARCH_CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml" && log_success "Updated config: starship.toml"
    fi

    # Fastfetch setup
    if command -v fastfetch >/dev/null; then
        mkdir -p "$HOME/.config/fastfetch"

        local dest_config="$HOME/.config/fastfetch/config.jsonc"

        # Overwrite with custom if available
        if [ -f "$ARCH_CONFIGS_DIR/config.jsonc" ]; then
            cp "$ARCH_CONFIGS_DIR/config.jsonc" "$dest_config"

            # Smart Icon Replacement
            # Default in file is Arch: " "
            local os_icon=" " # Default/Arch

            # Replace the icon in the file
            # We look for the line containing "key": " " and substitute.
            # Using specific regex to match the exact Arch icon  in the key value.
            sed -i "s/\"key\": \" \"/\"key\": \"$os_icon\"/" "$dest_config"

            log_success "Applied custom fastfetch config with Arch icon"
        else
           # Generate default if completely missing
           if [ ! -f "$dest_config" ]; then
             fastfetch --gen-config &>/dev/null
           fi
        fi
    fi
}

arch_setup_kde_shortcuts() {
    [[ "${XDG_CURRENT_DESKTOP:-}" != "KDE" ]] && return

    step "Setting up KDE global shortcuts"
    local src="$KDE_CONFIGS_DIR/kglobalshortcutsrc"
    local dest="$HOME/.config/kglobalshortcutsrc"

    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
        log_success "Applied KDE shortcuts (Meta+Q: Close, Meta+Ret: Terminal)"
        log_info "Changes take effect after re-login"
    else
        log_warning "KDE shortcuts config missing"
    fi
}

arch_setup_solaar() {
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
export -f arch_main_config
export -f arch_system_preparation
export -f arch_setup_aur_helper
export -f arch_configure_mirrors
export -f arch_configure_bootloader
export -f arch_enable_system_services
export -f arch_configure_zram
export -f arch_configure_plymouth

arch_configure_bootloader() {
    step "Configuring Arch Linux Bootloader"

    local bootloader
    bootloader=$(detect_bootloader)

    case "$bootloader" in
        "grub")
            configure_grub_arch
            ;;
        "systemd-boot")
            configure_systemd_boot_arch
            ;;
        *)
            log_warn "Unknown bootloader: $bootloader"
            log_info "Please manually add 'quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0' to your kernel parameters"
            ;;
    esac
}

# =============================================================================
# AUR HELPER INSTALLATION AND MIRROR CONFIGURATION
# =============================================================================

arch_configure_mirrors() {
    step "Configuring Arch Linux Mirrors"

    # Backup original mirrorlist
    if [ -f "$ARCH_MIRRORLIST" ]; then
        sudo cp "$ARCH_MIRRORLIST" "$ARCH_MIRRORLIST.backup"
        log_info "Backed up original mirrorlist to ${ARCH_MIRRORLIST}.backup"
    fi

    # Update mirrors using rate-mirrors
    log_info "Updating mirror list with rate-mirrors..."
    if sudo rate-mirrors --allow-root --save "$ARCH_MIRRORLIST" arch; then
        log_success "Mirror list updated successfully"
    else
        log_error "Failed to update mirror list"
        return 1
    fi

    # Sync package databases
    log_info "Synchronizing package databases..."
    if sudo pacman -Syy; then
        log_success "Package databases synchronized"
    else
        log_error "Failed to synchronize package databases"
        return 1
    fi
}

configure_grub_arch() {
    log_info "Configuring GRUB for Arch Linux..."

    if [ ! -f /etc/default/grub ]; then
        log_error "/etc/default/grub not found"
        return 1
    fi

    # Set timeout
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

    # Add Arch-specific kernel parameters including plymouth
    local arch_params="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
    local current_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub)
    local current_params=""

    if [ -n "$current_line" ]; then
        current_params=$(echo "$current_line" | cut -d'=' -f2- | sed "s/^['\"]//;s/['\"]$//")
    fi

    local new_params="$current_params"
    local changed=false

    for param in $arch_params; do
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
    if ! sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
        log_error "Failed to regenerate GRUB config"
        return 1
    fi

    log_success "GRUB configured successfully"
}

configure_systemd_boot_arch() {
    log_info "Configuring systemd-boot for Arch Linux..."

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

    local arch_params="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
    local updated=false

    for entry in "$entries_dir"/*.conf; do
        [ -e "$entry" ] || continue
        if [ -f "$entry" ]; then
            if ! grep -q "splash" "$entry"; then
                if grep -q "^options" "$entry"; then
                    sudo sed -i "/^options/ s/$/ $arch_params/" "$entry"
                    log_success "Updated $entry"
                    updated=true
                else
                    echo "options $arch_params" | sudo tee -a "$entry" >/dev/null
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



export -f arch_system_preparation
export -f arch_setup_aur_helper
export -f arch_configure_bootloader
export -f arch_enable_system_services
export -f arch_configure_zram
export -f arch_install_aur_helper
export -f arch_configure_mirrors

export -f arch_configure_plymouth
