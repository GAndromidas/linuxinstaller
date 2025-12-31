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

# Arch-specific package lists (base/common)
ARCH_ESSENTIALS=(
    "base-devel"
    "bc"
    "bluez-utils"
    "cronie"
    "curl"
    "eza"
    "expac"
    "fastfetch"
    "flatpak"
    "fzf"
    "git"
    "openssh"
    "pacman-contrib"
    "plymouth"
    "rsync"
    "starship"
    "ufw"
    "wget"
    "zsh"
    "zsh-autosuggestions"
    "zsh-syntax-highlighting"
    "zoxide"
)

ARCH_OPTIMIZATION=(
    "linux-lts"
    "linux-lts-headers"
    "btrfs-assistant"
    "btrfsmaintenance"
)

# ---------------------------------------------------------------------------
# Mode-specific, DE-specific and gaming package lists for Arch
# (defined here so distribution package lists live in the distro module
# and are easy to maintain; distro_get_packages() exposes a small API
# for the main installer to query these)
# ---------------------------------------------------------------------------

# Standard mode (native / pacman packages)
ARCH_NATIVE_STANDARD=(
    "android-tools"
    "bat"
    "bleachbit"
    "btop"
    "chromium"
    "cmatrix"
    "cpupower"
    "dosfstools"
    "duf"
    "firefox"
    "fwupd"
    "gnome-disk-utility"
    "hwinfo"
    "inxi"
    "mpv"
    "ncdu"
    "net-tools"
    "nmap"
    "noto-fonts-extra"
    "samba"
    "sl"
    "speedtest-cli"
    "sshfs"
    "ttf-hack-nerd"
    "ttf-liberation"
    "unrar"
    "wakeonlan"
    "xdg-desktop-portal-gtk"
)

# Standard mode (native essentials / pacman packages)
ARCH_NATIVE_STANDARD_ESSENTIALS=(
    "filezilla"
    "zed"
)

# AUR packages for Standard
ARCH_AUR_STANDARD=(
    "dropbox"
    "onlyoffice-bin"
    "rustdesk-bin"
    "spotify"
    "ventoy-bin"
    "via-bin"
)

# Flatpaks for Standard (Flathub IDs)
ARCH_FLATPAK_STANDARD=(
    "it.mijorus.gearlever"
    "io.github.shiftey.Desktop"
)

# Minimal mode (intentionally small)
ARCH_NATIVE_MINIMAL=(
    "mpv"
)

ARCH_AUR_MINIMAL=(
    "onlyoffice-bin"
    "rustdesk-bin"
)

ARCH_FLATPAK_MINIMAL=(
    "it.mijorus.gearlever"
)

# Server mode (headless / server-lean)
ARCH_NATIVE_SERVER=(
    "bat"
    "btop"
    "cmatrix"
    "cpupower"
    "docker"
    "docker-compose"
    "dosfstools"
    "duf"
    "expac"
    "fwupd"
    "hwinfo"
    "inxi"
    "nano"
    "ncdu"
    "net-tools"
    "nmap"
    "noto-fonts-extra"
    "samba"
    "sl"
    "speedtest-cli"
    "sshfs"
    "ttf-hack-nerd"
    "ttf-liberation"
    "unrar"
    "wakeonlan"
)

# Desktop environment specific packages
ARCH_DE_KDE_NATIVE=(
    "gwenview"
    "kdeconnect"
    "kdenlive"
    "kwalletmanager"
    "kvantum"
    "okular"
    "python-pyqt5"
    "python-pyqt6"
    "qbittorrent"
    "spectacle"
    "smplayer"
)

ARCH_DE_GNOME_NATIVE=(
    "adw-gtk-theme"
    "celluloid"
    "dconf-editor"
    "gnome-tweaks"
    "gufw"
    "seahorse"
    "transmission-gtk"
)

ARCH_DE_COSMIC_NATIVE=(
    "celluloid"
    "transmission-gtk"
)

ARCH_DE_KDE_FLATPAK=(
    "it.mijorus.gearlever"
)
ARCH_DE_GNOME_FLATPAK=(
    "com.mattjakeman.ExtensionManager"
    "it.mijorus.gearlever"
)
ARCH_DE_COSMIC_FLATPAK=(
    "it.mijorus.gearlever"
)

# Gaming packages
ARCH_GAMING_NATIVE=(
    "steam"
    "wine"
    "vulkan-icd-loader"
    "mesa"
    "lib32-vulkan-icd-loader"
    "lib32-mesa"
    "lib32-glibc"
    "mangohud"
    "lib32-mangohud"
    "gamemode"
    "lib32-gamemode"
    "goverlay"
)

ARCH_GAMING_FLATPAK=(
    "com.heroicgameslauncher.hgl"
    "com.vysp3r.ProtonPlus"
    "io.github.Faugus.faugus-launcher"
)

# ---------------------------------------------------------------------------
# Simple query API used by the main installer to fetch package lists.
# The function prints one package per line (suitable for mapfile usage).
# ---------------------------------------------------------------------------
distro_get_packages() {
    local section="$1"
    local type="$2"

    case "$section" in
            essential)
                case "$type" in
                    native) printf "%s\n" "${ARCH_ESSENTIALS[@]}" ;;
                    *) return 0 ;;
                esac
                ;;
            standard)
                case "$type" in
                native)
                    # Standard native should include the main standard list plus
                    # the additional standard-specific essentials.
                    printf "%s\n" "${ARCH_NATIVE_STANDARD[@]}"
                    printf "%s\n" "${ARCH_NATIVE_STANDARD_ESSENTIALS[@]:-}"
                    ;;
                aur)    printf "%s\n" "${ARCH_AUR_STANDARD[@]}" ;;
                flatpak) printf "%s\n" "${ARCH_FLATPAK_STANDARD[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        minimal)
            case "$type" in
                native)
                    # Minimal should still install the broader standard native set
                    # plus the minimal-specific additions to ensure base tooling is present.
                    printf "%s\n" "${ARCH_NATIVE_STANDARD[@]}"
                    printf "%s\n" "${ARCH_NATIVE_MINIMAL[@]:-}"
                    ;;
                aur)    printf "%s\n" "${ARCH_AUR_MINIMAL[@]:-}" ;;
                flatpak) printf "%s\n" "${ARCH_FLATPAK_MINIMAL[@]:-}" ;;
                *) return 0 ;;
            esac
            ;;
        server)
            case "$type" in
                native)
                    # Server should include the standard native base set in addition
                    # to server-specific packages for a reliable headless setup.
                    printf "%s\n" "${ARCH_NATIVE_STANDARD[@]}"
                    printf "%s\n" "${ARCH_NATIVE_SERVER[@]:-}"
                    ;;
                aur)    printf "%s\n" "${ARCH_AUR_SERVER[@]:-}" ;;
                flatpak) printf "%s\n" "${ARCH_FLATPAK_SERVER[@]:-}" ;;
                *) return 0 ;;
            esac
            ;;
        kde)
            case "$type" in
                native) printf "%s\n" "${ARCH_DE_KDE_NATIVE[@]}" ;;
                flatpak) printf "%s\n" "${ARCH_DE_KDE_FLATPAK[@]:-}" ;;
                *) return 0 ;;
            esac
            ;;
        gnome)
            case "$type" in
                native) printf "%s\n" "${ARCH_DE_GNOME_NATIVE[@]}" ;;
                flatpak) printf "%s\n" "${ARCH_DE_GNOME_FLATPAK[@]:-}" ;;
                *) return 0 ;;
            esac
            ;;
        cosmic)
            case "$type" in
                native) printf "%s\n" "${ARCH_DE_COSMIC_NATIVE[@]}" ;;
                flatpak) printf "%s\n" "${ARCH_DE_COSMIC_FLATPAK[@]:-}" ;;
                *) return 0 ;;
            esac
            ;;
        gaming)
            case "$type" in
                native) printf "%s\n" "${ARCH_GAMING_NATIVE[@]}" ;;
                aur)    printf "%s\n" "${ARCH_GAMING_AUR[@]}" ;;
                flatpak) printf "%s\n" "${ARCH_GAMING_FLATPAK[@]:-}" ;;
                *) return 0 ;;
            esac
            ;;
        *)
            # Unknown section -> return nothing
            return 0
            ;;
    esac
}
export -f distro_get_packages

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

    # Install AUR helper (yay) first so AUR-only utilities (e.g., rate-mirrors) can be installed
    if ! arch_install_aur_helper; then
        log_warn "AUR helper installation reported issues; some AUR packages may fail"
    fi

    # Optimize mirrorlist using rate-mirrors (installed via AUR helper if necessary)
    optimize_mirrors_arch

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

arch_install_aur_helper() {
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

    # Ensure base-devel group is installed; required for makepkg and building AUR packages
    if ! sudo pacman -S --noconfirm --needed base-devel >/dev/null 2>&1; then
        log_error "Failed to install base-devel (required to build AUR packages)"
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

    # Ensure rate-mirrors is installed - prefer any available AUR helper (yay/paru) since it is typically an AUR package
    if ! command -v rate-mirrors >/dev/null 2>&1; then
        log_info "Installing rate-mirrors (rate-mirrors-bin) for mirror optimization..."
    local rate_mirrors_installed=false


        if command -v yay >/dev/null 2>&1; then
            if ! yay -S --noconfirm --needed rate-mirrors-bin >/dev/null 2>&1; then
                log_warn "Failed to install rate-mirrors-bin via yay"
                return 1
            fi
        elif command -v paru >/dev/null 2>&1; then
            if ! paru -S --noconfirm --needed rate-mirrors-bin >/dev/null 2>&1; then
                log_warn "Failed to install rate-mirrors-bin via paru"
                return 1
            fi
        else
            log_info "No AUR helper found; attempting to install with pacman as a fallback..."
            if ! sudo pacman -S --noconfirm --needed rate-mirrors-bin >/dev/null 2>&1; then
                log_warn "Failed to install rate-mirrors-bin; mirror optimization may be skipped"
                return 1
            fi
        fi
    fi

    # Speed-based detection removed; using default parallel downloads set in PARALLEL_DOWNLOADS (10)
    # Skip mirror update if rate-mirrors-bin installation failed
    if [ "$rate_mirrors_installed" = false ]; then
        log_warn "Skipping mirror update due to rate-mirrors-bin installation failure"
        return 0
    fi
    # No dynamic adjustments based on speed; mirrorlist update follows below.

    # Update mirrorlist using rate-mirrors and refresh pacman DB
    log_info "Updating mirrorlist with optimized mirrors..."
    if sudo rate-mirrors --allow-root --save "$ARCH_MIRRORLIST" arch >/dev/null 2>&1; then
        log_success "Mirrorlist updated successfully"
        # Refresh pacman DB to make sure we use the updated mirrors
        if sudo pacman -Syy >/dev/null 2>&1; then
            log_success "Refreshed pacman package database (pacman -Syy)"
        else
            log_warn "Failed to refresh pacman package database after updating mirrors"
        fi
    else
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
            log_warning "Failed to change shell automatically"
            log_info "Please run this command manually to change your shell:"
            log_info "  sudo chsh -s $(command -v zsh) $USER"
            log_info "After changing your shell, log out and log back in for changes to take effect."
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

# Shortcuts are now configured via kde_config.sh for all distros
    log_info "KDE shortcuts will be configured via kde_config.sh"

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

# Configure UFW as the default firewall for Arch (adds a distro-local override)
# Arch firewall configuration is handled by security_configure_firewall() in security_config.sh

# Export functions for use by main installer
export -f arch_main_config
export -f arch_system_preparation
export -f arch_setup_aur_helper
export -f arch_install_aur_helper
export -f arch_configure_bootloader
# arch firewall is configured via security_configure_firewall() in security_config.sh
arch_configure_plymouth() {
    step "Configuring Plymouth boot splash"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure Plymouth (install package, update initramfs, adjust bootloader kernel params)"
        return 0
    fi

    # Ensure plymouth package is installed
    if ! command -v plymouth >/dev/null 2>&1; then
        log_info "Installing 'plymouth' package..."
        if ! install_pkg plymouth; then
            log_warn "Failed to install 'plymouth' - continuing but configuration may be incomplete"
        fi
    else
        log_info "Plymouth already installed"
    fi

    # Add plymouth hook to mkinitcpio if absent
    if [ -f /etc/mkinitcpio.conf ]; then
        if ! grep -q 'plymouth' /etc/mkinitcpio.conf && ! grep -q 'sd-plymouth' /etc/mkinitcpio.conf; then
            log_info "Adding 'plymouth' hook to /etc/mkinitcpio.conf"
            sudo sed -i '/^HOOKS=/ s/)/ plymouth)/' /etc/mkinitcpio.conf || true
            log_info "Regenerating initramfs..."
            if sudo mkinitcpio -P >/dev/null 2>&1; then
                log_success "Initramfs regenerated with plymouth hook"
            else
                log_warn "Failed to regenerate initramfs; please run 'sudo mkinitcpio -P' manually"
            fi
        else
            log_info "mkinitcpio already contains plymouth hook"
        fi
    fi

    # Configure GRUB to include splash if needed
    if [ -f /etc/default/grub ]; then
        if ! grep -q 'splash' /etc/default/grub; then
            log_info "Adding 'splash' to GRUB kernel parameters"
            sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/& splash/' /etc/default/grub || true
            if sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
                log_success "GRUB configuration updated with splash"
            else
                log_warn "Failed to regenerate GRUB config; please run 'sudo grub-mkconfig -o /boot/grub/grub.cfg' manually"
            fi
        else
            log_info "GRUB already contains 'splash' parameter"
        fi
    fi

    # For systemd-boot, add splash to entries if applicable
    local entries_dir=""
    if [ -d "/boot/loader/entries" ]; then
        entries_dir="/boot/loader/entries"
    elif [ -d "/efi/loader/entries" ]; then
        entries_dir="/efi/loader/entries"
    elif [ -d "/boot/efi/loader/entries" ]; then
        entries_dir="/boot/efi/loader/entries"
    fi

    if [ -n "$entries_dir" ]; then
        for entry in "$entries_dir"/*.conf; do
            [ -e "$entry" ] || continue
            if [ -f "$entry" ] && grep -q '^options' "$entry" && ! grep -q 'splash' "$entry"; then
                if sudo sed -i "/^options/ s/$/ splash/" "$entry" >/dev/null 2>&1; then
                    log_success "Added 'splash' to $entry"
                else
                    log_warn "Failed to add 'splash' to $entry"
                fi
            fi
        done
    fi

    # Optionally set a default theme if plymouth provides a helper
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        log_info "Setting a default plymouth theme if not already set..."
        # Do not force a theme; only set if command succeeds and a default is known
        if plymouth-set-default-theme --list | grep -q default >/dev/null 2>&1; then
            plymouth-set-default-theme default >/dev/null 2>&1 || true
        fi
    fi

    log_success "Plymouth configuration completed"
}

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
