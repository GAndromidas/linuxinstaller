#!/bin/bash
set -uo pipefail

# Debian/Ubuntu Configuration Module for LinuxInstaller
# Based on debianinstaller best practices

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Ensure we're on Debian or Ubuntu
if [ "$DISTRO_ID" != "debian" ] && [ "$DISTRO_ID" != "ubuntu" ]; then
    log_error "This module is for Debian/Ubuntu only"
    exit 1
fi

# Debian/Ubuntu-specific variables
DEBIAN_SOURCES="/etc/apt/sources.list"
UBUNTU_SOURCES="/etc/apt/sources.list"
APT_CONF="/etc/apt/apt.conf.d/99linuxinstaller"

# Debian-specific configuration files
DEBIAN_CONFIGS_DIR="$SCRIPT_DIR/../configs/debian"
UBUNTU_CONFIGS_DIR="$SCRIPT_DIR/../configs/ubuntu"

# Debian/Ubuntu-specific package lists (centralized in this module)
DEBIAN_NATIVE_STANDARD=(
    android-tools
    bat
    bleachbit
    btop
    chromium
    cmatrix
    cpupower
    dosfstools
    duf
    expac
    firefox
    fwupd
    gnome-disk-utility
    hwinfo
    inxi
    mpv
    ncdu
    net-tools
    nmap
    noto-fonts-extra
    samba
    sl
    speedtest-cli
    sshfs
    ttf-hack-nerd
    ttf-liberation
    unrar
    wakeonlan
    xdg-desktop-portal-gtk
    apt-transport-https
    ca-certificates
    curl
    wget
    rsync
    bc
    flatpak
    zoxide
    fzf
    fastfetch
    eza
)

# Essential packages installed early (installed by the 'essential' package group).
# Keep this list intentionally small and cross-distro friendly so core user tooling
# (shell, prompt, fastfetch, and basic UX helpers) are available before later steps.
DEBIAN_ESSENTIALS=(
    "zsh"
    "starship"
    "zsh-autosuggestions"
    "zsh-syntax-highlighting"
    "fastfetch"
    "fzf"
    "eza"
    "git"
    "curl"
    "ca-certificates"
)

DEBIAN_FLATPAK_STANDARD=(
    com.spotify.Client
    com.dropbox.Client
    org.filezillaproject.Filezilla
    org.kde.kdenlive
    org.onlyoffice.desktopeditors
    com.github.RustRDP.RustDesk
)

DEBIAN_NATIVE_MINIMAL=(
    mpv
    curl
    git
)

DEBIAN_FLATPAK_MINIMAL=(
    com.github.RustRDP.RustDesk
)

DEBIAN_NATIVE_SERVER=(
    openssh-server
    ufw
    fail2ban
    btop
    nethogs
)

DEBIAN_DE_KDE_NATIVE=(
    gwenview
    kdeconnect
    kdenlive
    kwalletmanager
    kvantum
    okular
    python-pyqt5
    python-pyqt6
    qbittorrent
    spectacle
    smplayer
)

DEBIAN_DE_GNOME_NATIVE=(
    adw-gtk-theme
    celluloid
    dconf-editor
    gnome-tweaks
    gufw
    seahorse
    transmission-gtk
)

DEBIAN_GAMING_NATIVE=(
    steam
    wine
    mangohud
    gamemode
)

DEBIAN_GAMING_FLATPAK=(
    io.github.Faugus.faugus-launcher
    com.heroicgameslauncher.hgl
    com.vysp3r.ProtonPlus
)

# distro_get_packages function used by the main installer
distro_get_packages() {
    local section="$1"
    local type="$2"

    case "$section" in
        essential)
            case "$type" in
                native) printf "%s\n" "${DEBIAN_ESSENTIALS[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        standard)
            case "$type" in
                native) printf "%s\n" "${DEBIAN_NATIVE_STANDARD[@]}" ;;
                flatpak) printf "%s\n" "${DEBIAN_FLATPAK_STANDARD[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        minimal)
            case "$type" in
                native) printf "%s\n" "${DEBIAN_NATIVE_MINIMAL[@]}" ;;
                flatpak) printf "%s\n" "${DEBIAN_FLATPAK_MINIMAL[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        server)
            case "$type" in
                native) printf "%s\n" "${DEBIAN_NATIVE_SERVER[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        kde)
            case "$type" in
                native) printf "%s\n" "${DEBIAN_DE_KDE_NATIVE[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        gnome)
            case "$type" in
                native) printf "%s\n" "${DEBIAN_DE_GNOME_NATIVE[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        gaming)
            case "$type" in
                native) printf "%s\n" "${DEBIAN_GAMING_NATIVE[@]}" ;;
                flatpak) printf "%s\n" "${DEBIAN_GAMING_FLATPAK[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        *)
            return 0
            ;;
    esac
}
export -f distro_get_packages

# =============================================================================
# DEBIAN/UBUNTU CONFIGURATION FUNCTIONS
# =============================================================================

# Prepare Debian/Ubuntu system for configuration
debian_system_preparation() {
    step "Debian/Ubuntu System Preparation"

    # Update package lists
    log_info "Updating package lists..."
    if ! sudo apt-get update >/dev/null 2>&1; then
        log_error "Failed to update package lists"
        return 1
    fi

    # Upgrade system
    log_info "Upgrading system packages..."
    if ! sudo apt-get upgrade -y >/dev/null 2>&1; then
        log_error "System upgrade failed"
        return 1
    fi

    # Configure APT for optimal performance
    configure_apt_debian

    log_success "Debian/Ubuntu system preparation completed"
}

# Configure APT package manager settings for Debian/Ubuntu
configure_apt_debian() {
    log_info "Configuring APT for optimal performance..."

    # Create APT configuration for performance
    sudo tee "$APT_CONF" > /dev/null << EOF
// LinuxInstaller APT Configuration
APT::Get::Assume-Yes "true";
APT::Get::Fix-Broken "true";
APT::Get::Fix-Missing "true";
APT::Acquire::Retries "3";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
DPkg::Options::="--force-confdef";
DPkg::Options::="--force-confold";
EOF

    # Configure APT sources for faster downloads
    if [ "$DISTRO_ID" == "ubuntu" ]; then
        # Enable universe and multiverse repositories
        sudo add-apt-repository universe >/dev/null 2>&1 || true
        sudo add-apt-repository multiverse >/dev/null 2>&1 || true

        # Set fastest mirror
        if command -v netselect-apt >/dev/null 2>&1; then
            sudo netselect-apt -n ubuntu >/dev/null 2>&1 || true
        fi
    fi

    log_success "APT configured with optimizations"
}

# Install essential packages for Debian/Ubuntu
debian_install_essentials() {
    step "Installing Debian/Ubuntu Essential Packages"

    log_info "Installing essential packages..."
    for package in "${DEBIAN_ESSENTIALS[@]}"; do
        if ! install_pkg "$package"; then
            log_warn "Failed to install essential package: $package"
        else
            log_success "Installed essential package: $package"
        fi
    done

    # Install desktop packages if not server mode
    if [ "$INSTALL_MODE" != "server" ]; then
        log_info "Installing desktop packages..."
        for package in "${DEBIAN_DESKTOP[@]}"; do
            if ! install_pkg "$package"; then
                log_warn "Failed to install desktop package: $package"
            else
                log_success "Installed desktop package: $package"
            fi
        done
    else
        # Install server packages
        log_info "Installing server packages..."
        for package in "${DEBIAN_SERVER[@]}"; do
            if ! install_pkg "$package"; then
                log_warn "Failed to install server package: $package"
            else
                log_success "Installed server package: $package"
            fi
        done
    fi
}

# Configure bootloader (GRUB or systemd-boot) for Debian/Ubuntu
debian_configure_bootloader() {
    step "Configuring Debian/Ubuntu Bootloader"

    local bootloader
    bootloader=$(detect_bootloader)

    case "$bootloader" in
        "grub")
            configure_grub_debian
            ;;
        "systemd-boot")
            configure_systemd_boot_debian
            ;;
        *)
            log_warn "Unknown bootloader: $bootloader"
            log_info "Please manually add 'quiet splash' to your kernel parameters"
            ;;
    esac
}

# Configure GRUB bootloader settings for Debian/Ubuntu
configure_grub_debian() {
    log_info "Configuring GRUB for Debian/Ubuntu..."

    if [ ! -f /etc/default/grub ]; then
        log_error "/etc/default/grub not found"
        return 1
    fi

    # Set timeout
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

    # Add Debian/Ubuntu-specific kernel parameters
    local debian_params="quiet splash"
    local current_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub)
    local current_params=""

    if [ -n "$current_line" ]; then
        current_params=$(echo "$current_line" | cut -d'=' -f2- | sed "s/^['\"]//;s/['\"]$//")
    fi

    local new_params="$current_params"
    local changed=false

    for param in $debian_params; do
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
    if ! sudo update-grub >/dev/null 2>&1; then
        log_error "Failed to regenerate GRUB config"
        return 1
    fi

    log_success "GRUB configured successfully"
}

# Configure systemd-boot bootloader settings for Debian/Ubuntu
configure_systemd_boot_debian() {
    log_info "Configuring systemd-boot for Debian/Ubuntu..."

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

    local debian_params="quiet splash"
    local updated=false

    for entry in "$entries_dir"/*.conf; do
        [ -e "$entry" ] || continue
        if [ -f "$entry" ]; then
            if ! grep -q "splash" "$entry"; then
                if grep -q "^options" "$entry"; then
                    sudo sed -i "/^options/ s/$/ $debian_params/" "$entry"
                    log_success "Updated $entry"
                    updated=true
                else
                    echo "options $debian_params" | sudo tee -a "$entry" >/dev/null
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

# Enable and configure essential systemd services for Debian/Ubuntu
debian_enable_system_services() {
    step "Enabling Debian/Ubuntu System Services"

    # Essential services
    local services=(
        "cron"
        "bluetooth"
        "ssh"
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

    # Configure firewall (UFW for Debian/Ubuntu)
    if ! install_pkg ufw; then
        log_warn "Failed to install UFW"
        return
    fi

    # Configure UFW
    sudo ufw default deny incoming >/dev/null 2>&1
    sudo ufw default allow outgoing >/dev/null 2>&1
    sudo ufw limit ssh >/dev/null 2>&1
    echo "y" | sudo ufw enable >/dev/null 2>&1
    log_success "UFW configured and enabled"
}

# Setup Flatpak and Flathub for Debian/Ubuntu
debian_setup_flatpak() {
    step "Setting up Flatpak for Debian/Ubuntu"

    if ! command -v flatpak >/dev/null; then
        log_info "Installing Flatpak..."
        if ! install_pkg flatpak; then
            log_warn "Failed to install Flatpak"
            return
        fi
    fi

    # Add Flathub
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
    log_success "Flatpak configured with Flathub"
}

# Setup Snap package manager for Ubuntu
debian_setup_snap() {
    step "Setting up Snap for Ubuntu"

    if [ "$DISTRO_ID" != "ubuntu" ]; then
        return 0
    fi

    if ! command -v snap >/dev/null; then
        log_info "Installing Snap..."
        if ! install_pkg snapd; then
            log_warn "Failed to install Snap"
            return
        fi

        # Enable snapd service
        sudo systemctl enable --now snapd >/dev/null 2>&1
        sudo systemctl enable --now snapd.socket >/dev/null 2>&1

        log_success "Snap configured"
    else
        log_info "Snap already installed"
    fi
}

# Setup ZSH shell environment and configuration files for Debian/Ubuntu
debian_setup_shell() {
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
    if [ "$DISTRO_ID" == "ubuntu" ] && [ -f "$UBUNTU_CONFIGS_DIR/.zshrc" ]; then
        cp "$UBUNTU_CONFIGS_DIR/.zshrc" "$HOME/.zshrc" && log_success "Updated config: .zshrc (Ubuntu)"
    elif [ -f "$DEBIAN_CONFIGS_DIR/.zshrc" ]; then
        cp "$DEBIAN_CONFIGS_DIR/.zshrc" "$HOME/.zshrc" && log_success "Updated config: .zshrc"
    fi

    # Copy Ubuntu-specific .zshrc if exists
    if [ -f "$DEBIAN_CONFIGS_DIR/.zshrc.ubuntu" ] && [ "$DISTRO_ID" == "ubuntu" ]; then
        cp "$DEBIAN_CONFIGS_DIR/.zshrc.ubuntu" "$HOME/.zshrc" && log_success "Updated config: .zshrc (Ubuntu)"
    fi

    # Copy starship config
    if [ "$DISTRO_ID" == "ubuntu" ] && [ -f "$UBUNTU_CONFIGS_DIR/starship.toml" ]; then
        cp "$UBUNTU_CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml" && log_success "Updated config: starship.toml (Ubuntu)"
    elif [ -f "$DEBIAN_CONFIGS_DIR/starship.toml" ]; then
        cp "$DEBIAN_CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml" && log_success "Updated config: starship.toml"
    fi

    # Fastfetch setup
    if command -v fastfetch >/dev/null; then
        mkdir -p "$HOME/.config/fastfetch"

        local dest_config="$HOME/.config/fastfetch/config.jsonc"

        # Overwrite with custom if available
        if [ "$DISTRO_ID" == "ubuntu" ] && [ -f "$UBUNTU_CONFIGS_DIR/config.jsonc" ]; then
            cp "$UBUNTU_CONFIGS_DIR/config.jsonc" "$dest_config"

            # Smart Icon Replacement
            # Default in file is Arch: " "
            local os_icon=" " # Ubuntu icon

            # Replace the icon in the file
            sed -i "s/\"key\": \" \"/\"key\": \"$os_icon\"/" "$dest_config"
            log_success "Applied custom fastfetch config with Ubuntu icon"
        elif [ -f "$DEBIAN_CONFIGS_DIR/config.jsonc" ]; then
            cp "$DEBIAN_CONFIGS_DIR/config.jsonc" "$dest_config"

            # Smart Icon Replacement
            # Default in file is Arch: " "
            local os_icon=" " # Debian icon

            # Replace the icon in the file
            sed -i "s/\"key\": \" \"/\"key\": \"$os_icon\"/" "$dest_config"
            log_success "Applied custom fastfetch config with Debian icon"
        else
           # Generate default if completely missing
           if [ ! -f "$dest_config" ]; then
             fastfetch --gen-config &>/dev/null
             log_info "Fastfetch config generated (default)"
           else
             log_info "Using existing fastfetch configuration"
           fi
        fi
    fi
}

# Setup Solaar for Logitech hardware management on Debian/Ubuntu
debian_setup_solaar() {
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

    # Check for Logitech hardware (use safe, non-blocking checks)
    local has_logitech=false

    # Check USB devices for Logitech (if lsusb available)
    if command -v lsusb >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            if timeout 3s lsusb 2>/dev/null | grep -i logitech >/dev/null 2>&1; then
                has_logitech=true
                log_info "Logitech hardware detected via USB"
            fi
        else
            if lsusb 2>/dev/null | grep -i logitech >/dev/null 2>&1; then
                has_logitech=true
                log_info "Logitech hardware detected via USB"
            fi
        fi
    fi

    # Check Bluetooth devices for Logitech (if bluetoothctl available)
    if command -v bluetoothctl >/dev/null 2>&1; then
        # ensure the call cannot hang by using timeout where available and redirecting stdin
        if command -v timeout >/dev/null 2>&1; then
            if timeout 3s bluetoothctl devices </dev/null | grep -i logitech >/dev/null 2>&1; then
                has_logitech=true
                log_info "Logitech Bluetooth device detected"
            fi
        else
            if bluetoothctl devices </dev/null | grep -i logitech >/dev/null 2>&1; then
                has_logitech=true
                log_info "Logitech Bluetooth device detected"
            fi
        fi
    fi

    # Check for Logitech HID devices safely (loop avoids xargs pitfalls)
    for hid in /dev/hidraw*; do
        [ -e "$hid" ] || continue
        hid_base=$(basename "$hid")
        if grep -qi logitech "/sys/class/hidraw/$hid_base/device/uevent" 2>/dev/null; then
            has_logitech=true
            log_info "Logitech HID device detected: $hid"
            break
        fi
    done

    if [ "$has_logitech" = true ]; then
        log_info "Installing solaar for Logitech hardware management..."
        if install_pkg solaar; then
            log_success "Solaar installed successfully"

            # Enable solaar service if present
            if sudo systemctl enable --now solaar.service >/dev/null 2>&1; then
                log_success "Solaar service enabled and started"
            else
                log_warn "Failed to enable solaar service (may not exist on all systems)"
            fi
        else
            log_warn "Failed to install solaar"
        fi
    else
        log_info "No Logitech hardware detected, skipping solaar installation"
    fi
}

# Configure system locales for Greek and US English on Debian/Ubuntu
debian_configure_locale() {
    step "Configuring Debian/Ubuntu Locales (Greek and US)"

    # Install language packs
    log_info "Installing language packs..."
    if [ "$DISTRO_ID" == "ubuntu" ]; then
        if ! sudo apt-get install -y language-pack-el language-pack-en >/dev/null 2>&1; then
            log_warn "Failed to install language packs"
        else
            log_success "Language packs installed"
        fi
    else
        # Debian uses locale packages
        if ! sudo apt-get install -y locales >/dev/null 2>&1; then
            log_warn "Failed to install locales package"
        else
            log_success "Locales package installed"
        fi
    fi

    local locale_file="/etc/locale.gen"

    if [ -f "$locale_file" ]; then
        sudo cp "$locale_file" "${locale_file}.backup"

        # Uncomment Greek locale
        if grep -q "^#el_GR.UTF-8 UTF-8" "$locale_file"; then
            log_info "Enabling Greek locale (el_GR.UTF-8)..."
            sudo sed -i 's/^#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' "$locale_file"
            log_success "Greek locale enabled"
        elif grep -q "^el_GR.UTF-8 UTF-8" "$locale_file"; then
            log_info "Greek locale already enabled"
        fi

        # Uncomment US English locale
        if grep -q "^#en_US.UTF-8 UTF-8" "$locale_file"; then
            log_info "Enabling US English locale (en_US.UTF-8)..."
            sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$locale_file"
            log_success "US English locale enabled"
        elif grep -q "^en_US.UTF-8 UTF-8" "$locale_file"; then
            log_info "US English locale already enabled"
        fi

        # Generate locales
        log_info "Generating locales..."
        if sudo locale-gen >/dev/null 2>&1; then
            log_success "Locales generated successfully"
        else
            log_warn "Failed to generate locales"
        fi
    fi

    local locale_conf="/etc/default/locale"

    if [ ! -f "$locale_conf" ]; then
        sudo touch "$locale_conf"
    fi

    # Set LANG to Greek
    log_info "Setting default locale to Greek (el_GR.UTF-8)..."
    if sudo bash -c "echo 'LANG=el_GR.UTF-8' > '$locale_conf'"; then
        log_success "Default locale set to el_GR.UTF-8"
    else
        log_warn "Failed to set default locale"
    fi

    log_info "Locale configuration completed"
    log_info "To change system locale, edit /etc/default/locale (Debian) or /etc/locale.conf (Ubuntu)"
    log_info "Available locales: el_GR.UTF-8 (Greek), en_US.UTF-8 (US English)"
}

# =============================================================================
# MAIN DEBIAN CONFIGURATION FUNCTION
# =============================================================================

debian_main_config() {
    log_info "Starting Debian/Ubuntu configuration..."

    debian_system_preparation

    debian_install_essentials

    debian_configure_bootloader

    debian_enable_system_services

    debian_setup_flatpak

    debian_setup_snap

    debian_setup_shell

    debian_setup_solaar

    debian_configure_locale

    log_success "Debian/Ubuntu configuration completed"
}

# Export functions for use by main installer
export -f debian_main_config
export -f debian_system_preparation
export -f debian_install_essentials
export -f debian_configure_bootloader
export -f debian_enable_system_services
export -f debian_setup_flatpak
export -f debian_setup_snap
export -f debian_setup_shell
export -f debian_setup_solaar
export -f debian_configure_locale
