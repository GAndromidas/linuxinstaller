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

# Fedora-specific package lists (base/common)
# These packages are installed in ALL modes (standard, minimal, server)
# Equivalent to Arch's ARCH_ESSENTIALS - core tools for all setups
FEDORA_ESSENTIALS=(
    bc
    cronie
    curl
    fastfetch
    flatpak
    fzf
    git
    openssh-server
    rsync
    zsh
    zsh-autosuggestions
    zsh-syntax-highlighting
    zoxide
)

# Fedora-specific package lists (centralized in this module)
# Mode-specific native packages
FEDORA_NATIVE_STANDARD=(
    android-tools
    bat
    bleachbit
    btop
    cmatrix
    filezilla
    hwinfo
    inxi
    python3-speedtest-cli
    sl
    unrar
    unzip
)

# Flatpak entries (Flathub IDs)
FEDORA_FLATPAK_STANDARD=(
    com.rustdesk.RustDesk
    it.mijorus.gearlever
)

# Minimal mode: lightweight desktop with essential tools only
FEDORA_NATIVE_MINIMAL=(
    bat
    btop
    cmatrix
    mpv
    ncdu
    sl
)

FEDORA_FLATPAK_MINIMAL=(
    com.rustdesk.RustDesk
    it.mijorus.gearlever
)

# Server mode: headless server with monitoring and security tools
FEDORA_NATIVE_SERVER=(
    bat
    btop
    cmatrix
    cpupower
    docker
    docker-compose
    dosfstools
    duf
    fail2ban
    htop
    hwinfo
    inxi
    nano
    ncdu
    net-tools
    nmap
    samba
    speedtest-cli
    sshfs
    tmux
    unrar
    wakeonlan
)

# COPR repositories
FEDORA_COPR_REPOS=(
    alternateved/eza
    atim/starship
)

# ---------------------------------------------------------------------------
# distro_get_packages() - small, distro-local API for the main installer
# Usage: distro_get_packages <section> <type>
# Prints one package name per line (suitable for mapfile usage)
# ---------------------------------------------------------------------------
distro_get_packages() {
    local section="$1"
    local type="$2"

    case "$section" in
        essential)
            case "$type" in
                native)  printf "%s\n" "${FEDORA_ESSENTIALS[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        standard)
            case "$type" in
                native)  printf "%s\n" "${FEDORA_NATIVE_STANDARD[@]}" ;;
                flatpak) printf "%s\n" "${FEDORA_FLATPAK_STANDARD[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        minimal)
            case "$type" in
                native)  printf "%s\n" "${FEDORA_NATIVE_MINIMAL[@]}" ;;
                flatpak) printf "%s\n" "${FEDORA_FLATPAK_MINIMAL[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        server)
            case "$type" in
                native) printf "%s\n" "${FEDORA_NATIVE_SERVER[@]}" ;;
                *) return 0 ;;
            esac
            ;;
# DE-specific packages moved to DE config files
# Gaming packages moved to gaming_config.sh
        *)
            # Unknown section; nothing to return
            return 0
            ;;
    esac
}
export -f distro_get_packages

# =============================================================================
# FEDORA CONFIGURATION FUNCTIONS
# =============================================================================

# Prepare Fedora system for configuration
fedora_system_preparation() {
    display_step "🔧" "Fedora System Preparation"

    # Enable RPM Fusion repositories
    fedora_enable_rpmfusion

    # Configure DNF for optimal performance
    fedora_configure_dnf

    # Update system
    if supports_gum; then
        if spin "Updating system"  dnf update -y >/dev/null 2>&1; then
            display_success "✓ System updated"
        fi
    else
        dnf update -y >/dev/null 2>&1 || true
    fi
}

# Enable RPM Fusion repositories for Fedora
fedora_enable_rpmfusion() {
    display_step "📦" "Enabling RPM Fusion Repositories"

    if ! dnf repolist | grep -q rpmfusion-free; then
        local fedora_version=$(rpm -E %fedora)

        if supports_gum; then
            if spin "Enabling RPM Fusion repositories"  dnf install -y \
                https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fedora_version.noarch.rpm \
                https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fedora_version.noarch.rpm >/dev/null 2>&1; then
                display_success "✓ RPM Fusion enabled"
            fi
        else
            dnf install -y \
                https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fedora_version.noarch.rpm \
                https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fedora_version.noarch.rpm >/dev/null 2>&1 || true
        fi
    fi
}

# Configure DNF package manager settings for Fedora
fedora_configure_dnf() {
    log_info "Configuring DNF for optimal performance..."

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
            sed -i "s/^$key=.*/$opt/" "$FEDORA_REPOS_FILE"
        else
            echo "$opt" | tee -a "$FEDORA_REPOS_FILE" >/dev/null
        fi
    done

    # Enable PowerTools repository for additional packages
    if [ -f /etc/yum.repos.d/fedora-cisco-openh264.repo ]; then
        dnf config-manager --set-enabled fedora-cisco-openh264 >/dev/null 2>&1 || true
    fi

    log_success "DNF configured with optimizations"
}

# Install essential packages for Fedora
fedora_install_essentials() {
    display_step "📦" "Installing Fedora Essential Packages"

    log_info "Installing essential packages..."
    for package in "${FEDORA_ESSENTIALS[@]}"; do
        if ! install_pkg "$package" >/dev/null 2>&1; then
            log_warn "Failed to install essential package: $package"
        else
            log_success "Installed essential package: $package"
        fi
    done

    # Install desktop packages if not server mode
    if [ "$INSTALL_MODE" != "server" ]; then
        log_info "Installing desktop packages..."
        for package in "${FEDORA_DESKTOP[@]}"; do
        if ! install_pkg "$package" >/dev/null 2>&1; then
                log_warn "Failed to install desktop package: $package"
            else
                log_success "Installed desktop package: $package"
            fi
        done
    fi
}

# Configure bootloader (GRUB or systemd-boot) for Fedora
fedora_configure_bootloader() {
    display_step "🔄" "Configuring Fedora Bootloader"

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

# Configure GRUB bootloader settings for Fedora
configure_grub_fedora() {
    log_info "Configuring GRUB for Fedora..."

    if [ ! -f /etc/default/grub ]; then
        log_error "/etc/default/grub not found"
        return 1
    fi

    # Set timeout
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

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
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_params\"|" /etc/default/grub
        log_success "Updated GRUB kernel parameters"
    fi

    # Regenerate GRUB config
    log_info "Regenerating GRUB configuration..."
    if [ -d /sys/firmware/efi ]; then
        if ! grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg >/dev/null 2>&1; then
            log_error "Failed to regenerate GRUB config"
            return 1
        fi
    else
        if ! grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1; then
            log_error "Failed to regenerate GRUB config"
            return 1
        fi
    fi

    log_success "GRUB configured successfully"
}

# Configure systemd-boot bootloader settings for Fedora
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
                    sed -i "/^options/ s/$/ $fedora_params/" "$entry"
                    log_success "Updated $entry"
                    updated=true
                else
                    echo "options $fedora_params" | tee -a "$entry" >/dev/null
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

# Enable and configure essential systemd services for Fedora
fedora_enable_system_services() {
    display_step "⚙️" "Enabling Fedora System Services"

    # Essential services
    local services=(
        bluetooth
        cronie
        fstrim.timer
        sshd
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            if systemctl enable --now "$service" >/dev/null 2>&1; then
                log_success "Enabled and started $service"
            else
                log_warn "Failed to enable $service"
            fi
        fi
    done

    # Configure firewall (firewalld for Fedora)
    if ! install_pkg firewalld >/dev/null 2>&1; then
        log_warn "Failed to install firewalld"
        return
    fi

    # Configure firewalld
    if systemctl enable --now firewalld >/dev/null 2>&1; then
        firewall-cmd --set-default-zone=public >/dev/null 2>&1
        firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        log_success "firewalld enabled and configured"
    else
        log_warn "Failed to enable firewalld"
    fi
}

# Setup Flatpak and Flathub for Fedora
fedora_setup_flatpak() {
    display_step "📦" "Setting up Flatpak for Fedora"

    if ! command -v flatpak >/dev/null; then
        log_info "Installing Flatpak..."
        if ! install_pkg flatpak >/dev/null 2>&1; then
            log_warn "Failed to install Flatpak"
            return
        fi
    fi

    # Add Flathub
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
    log_success "Flatpak configured with Flathub"
}

# Additional Fedora helper setup functions
# Setup COPR repositories for Fedora
fedora_setup_copr() {
    display_step "📦" "Setting up COPR repositories"
    if [ "${#FEDORA_COPR_REPOS[@]}" -gt 0 ]; then
        # Ensure dnf-plugins-core is available (required for 'dnf copr')
        if ! install_pkg dnf-plugins-core >/dev/null 2>&1; then
            log_warn "Failed to install dnf-plugins-core; COPR setup may fail"
        fi

        for repo in "${FEDORA_COPR_REPOS[@]}"; do
            if [ -n "$repo" ]; then
                log_info "Enabling COPR repository: $repo"
                if ! dnf copr enable -y "$repo" >/dev/null 2>&1; then
                    log_warn "Failed to enable COPR repo: $repo"
                else
                    log_success "Enabled COPR repo: $repo"
                    # Install packages from this COPR repo
                    case "$repo" in
                        "atim/starship")
                            if ! install_pkg starship >/dev/null 2>&1; then
                                log_warn "Failed to install starship from COPR"
                            else
                                log_success "Installed starship from COPR"
                            fi
                            ;;
                        "alternateved/eza")
                            if ! install_pkg eza >/dev/null 2>&1; then
                                log_warn "Failed to install eza from COPR"
                            else
                                log_success "Installed eza from COPR"
                            fi
                            ;;
                    esac
                fi
            fi
        done
    else
        log_info "No COPR entries configured for Fedora"
    fi
}

# Setup ZSH shell environment and configuration files for Fedora
fedora_setup_shell() {
    display_step "🐚" "Setting up ZSH shell environment"

    if [ "$SHELL" != "$(command -v zsh)" ]; then
        log_info "Changing default shell to ZSH..."
        if chsh -s "$(command -v zsh)" "$USER" 2>/dev/null; then
            log_success "Default shell changed to ZSH"
        else
            log_warning "Failed to change shell. You may need to do this manually."
        fi
    fi

    mkdir -p "$HOME/.config"

    if [ -f "$FEDORA_CONFIGS_DIR/.zshrc" ]; then
        cp "$FEDORA_CONFIGS_DIR/.zshrc" "$HOME/.zshrc" && log_success "Updated config: .zshrc"
    fi

    if [ -f "$FEDORA_CONFIGS_DIR/starship.toml" ]; then
        cp "$FEDORA_CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml" && log_success "Updated config: starship.toml"
    fi

    if command -v fastfetch >/dev/null 2>&1; then
        mkdir -p "$HOME/.config/fastfetch"
        local dest_config="$HOME/.config/fastfetch/config.jsonc"
        if [ -f "$FEDORA_CONFIGS_DIR/config.jsonc" ]; then
            cp "$FEDORA_CONFIGS_DIR/config.jsonc" "$dest_config"
            log_success "Applied custom fastfetch config"
        else
            if [ ! -f "$dest_config" ]; then
                fastfetch --gen-config &>/dev/null
            fi
        fi
    fi
}

# Setup Solaar for Logitech hardware management on Fedora
fedora_setup_solaar() {
    # Mirror existing solaar setup from other modules
    display_step "🖱️" "Setting up Logitech Hardware Support for Fedora"

    if [ "$INSTALL_MODE" == "server" ]; then
        log_info "Server mode selected, skipping solaar installation"
        return 0
    fi

    if [ -z "${XDG_CURRENT_DESKTOP:-}" ]; then
        log_info "No desktop environment detected, skipping solaar installation"
        return 0
    fi

    local has_logitech=false

    # Check for Logitech USB devices with timeout
    if timeout 5 lsusb | grep -i logitech >/dev/null 2>&1; then
        has_logitech=true
        log_info "Logitech hardware detected via USB"
    fi

    # Check for Logitech Bluetooth devices with timeout and better error handling
    if command -v bluetoothctl >/dev/null 2>&1; then
        # Use timeout to prevent hanging on Bluetooth issues
        if timeout 10 bash -c "bluetoothctl --timeout 5 devices 2>/dev/null | grep -i logitech >/dev/null 2>&1"; then
            has_logitech=true
            log_info "Logitech Bluetooth device detected"
        fi
    fi

    if [ "$has_logitech" = true ]; then
        log_info "Installing solaar for Logitech hardware management..."
        install_packages_with_progress "solaar"
        if systemctl enable --now solaar.service >/dev/null 2>&1; then
            log_success "Solaar service enabled and started"
        else
            log_warn "Failed to enable solaar service"
        fi
    else
        log_info "No Logitech hardware detected, skipping solaar installation"
    fi
}

# Configure system locales for Greek and US English on Fedora
fedora_configure_locale() {
    display_step "🌍" "Configuring Fedora Locales (Greek and US)"

    # Install language packs for Greek and US English
    log_info "Installing language packs..."
    if install_packages_with_progress glibc-langpack-el glibc-langpack-en; then
        log_success "Language packs installed"
    else
        log_warn "Failed to install language packs"
    fi

    local locale_conf="/etc/locale.conf"

    if [ ! -f "$locale_conf" ]; then
        touch "$locale_conf"
    fi

    # Set LANG to Greek
    log_info "Setting default locale to Greek (el_GR.UTF-8)..."
    if bash -c "echo 'LANG=el_GR.UTF-8' > '$locale_conf'"; then
        log_success "Default locale set to el_GR.UTF-8"
    else
        log_warn "Failed to set default locale"
    fi

    log_info "Locale configuration completed"
    log_info "To change system locale, edit /etc/locale.conf"
    log_info "Available locales: el_GR.UTF-8 (Greek), en_US.UTF-8 (US English)"
}

# =============================================================================
# MAIN FEDORA CONFIGURATION FUNCTION
# =============================================================================

# Configure system hostname for Fedora
fedora_configure_hostname() {
    display_step "🏠" "Configuring System Hostname"

    local current_hostname
    current_hostname=$(hostname)

    if supports_gum; then
        display_step "🏠" "Current hostname: $current_hostname"
        display_info "Do you want to change the hostname?" "Hostname identifies your system on the network.\nChoose wisely as it will be used by:"

        if gum confirm "Change hostname?" --default=false; then
            echo ""
            local new_hostname
            new_hostname=$(gum input --placeholder "my-fedora" --prompt "Enter new hostname: " --width 40)

            if [ -n "$new_hostname" ] && [ "$new_hostname" != "$current_hostname" ]; then
                display_warning "You are about to change hostname to: $new_hostname" "This will:\n• Update /etc/hostname\n• Require a reboot to take effect"
                display_step "❓" "Are you sure you want to proceed?"
                echo ""

                if gum confirm "Yes, change hostname to: $new_hostname"; then
                    if echo "$new_hostname" | tee /etc/hostname >/dev/null; then
                        hostnamectl set-hostname "$new_hostname"
                        log_success "Hostname changed to: $new_hostname"
                        log_info "Reboot required for changes to take effect"
                    else
                        log_error "Failed to change hostname"
                    fi
                else
                    log_info "Hostname change cancelled by user"
                fi
            else
                log_info "Hostname unchanged (empty or same as current)"
            fi
        else
            log_info "Hostname change skipped by user"
        fi
    else
        display_info "Current hostname: $current_hostname" "Hostname identifies your system on the network.\nChoose wisely as it will be used by:\n  • SSH connections\n  • Network identification\n  • System logs"
        echo ""
        read -r -p "Change hostname? [y/N]: " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            read -r -p "Enter new hostname: " new_hostname
            if [ -n "$new_hostname" ] && [ "$new_hostname" != "$current_hostname" ]; then
                display_warning "You are about to change hostname to: $new_hostname" "This will:\n  • Update /etc/hostname\n  • Require a reboot to take effect"
                read -r -p "Yes, change hostname to: $new_hostname? [y/N]: " confirm
                if [[ "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    if echo "$new_hostname" | tee /etc/hostname >/dev/null; then
                        hostnamectl set-hostname "$new_hostname"
                        log_success "Hostname changed to: $new_hostname"
                        log_info "Reboot required for changes to take effect"
                    else
                        log_error "Failed to change hostname"
                    fi
                else
                    log_info "Hostname change cancelled by user"
                fi
            else
                log_info "Hostname unchanged (empty or same as current)"
            fi
        else
            log_info "Hostname change skipped by user"
        fi
    fi
}

# =============================================================================
# MAIN FEDORA CONFIGURATION FUNCTION
# =============================================================================

fedora_main_config() {
    log_info "Starting Fedora configuration..."

    fedora_configure_hostname

    fedora_system_preparation

    fedora_configure_dnf

    fedora_enable_rpmfusion

    fedora_setup_copr

    if [ "$INSTALL_MODE" != "server" ]; then
        fedora_install_essentials
    fi

    fedora_configure_bootloader

    fedora_enable_system_services

    if [ "$INSTALL_MODE" != "server" ]; then
        fedora_setup_flatpak
    fi

    fedora_setup_shell

    fedora_setup_solaar

    if [ "$INSTALL_MODE" != "server" ]; then
        fedora_configure_locale
    fi

    log_success "Fedora configuration completed"
}

# Export functions for use by main installer
export -f fedora_main_config
export -f fedora_system_preparation
export -f fedora_configure_dnf
export -f fedora_enable_rpmfusion
export -f fedora_install_essentials
export -f fedora_configure_bootloader
export -f fedora_enable_system_services
export -f fedora_setup_flatpak
export -f fedora_setup_copr
export -f fedora_setup_shell
export -f fedora_setup_solaar
export -f fedora_configure_locale
export -f fedora_configure_hostname
