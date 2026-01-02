#!/bin/bash
set -uo pipefail

# Safety function to check if a variable is set
var_is_set() {
    local var_name="$1"
    [[ -n ${!var_name+x} ]]
}

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
# These packages are installed in ALL modes (standard, minimal, server)
# Equivalent to Arch's ARCH_ESSENTIALS - core tools for all setups
ARCH_ESSENTIALS=(
    base-devel
    bc
    bluez-utils
    cronie
    curl
    eza
    expac
    fastfetch
    flatpak
    fzf
    git
    openssh
    pacman-contrib
    plymouth
    reflector
    rsync
    starship
    ufw
    wget
    zsh
    zsh-autosuggestions
    zsh-syntax-highlighting
    zoxide
)

ARCH_OPTIMIZATION=(
    linux-lts
)

# ---------------------------------------------------------------------------
# Mode-specific, DE-specific and gaming package lists for Arch
# (defined here so distribution package lists live in the distro module
# and are easy to maintain; distro_get_packages() exposes a small API
# for the main installer to query these)
# ---------------------------------------------------------------------------

# Standard mode (native / pacman packages)
ARCH_NATIVE_STANDARD=(
    android-tools
    bat
    bleachbit
    btop
    chromium
    cmatrix
    cpupower
    dosfstools
    duf
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
)

# Standard mode (native essentials / pacman packages)
ARCH_NATIVE_STANDARD_ESSENTIALS=(
    filezilla
    kdenlive
    zed
)

# =============================================================================
# AUR PACKAGES FOR STANDARD MODE
# =============================================================================

# AUR packages for Standard
ARCH_AUR_STANDARD=(
    dropbox
    onlyoffice-bin
    rustdesk-bin
    spotify
    ventoy-bin
    via-bin
)
# Flatpaks for Standard (Flathub IDs)
ARCH_FLATPAK_STANDARD=(
    io.github.shiftey.Desktop
    it.mijorus.gearlever
)

# Minimal mode: lightweight desktop with essential tools only
ARCH_NATIVE_MINIMAL=(
    bat
    bleachbit
    btop
    chromium
    cmatrix
    cpupower
    dosfstools
    duf
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
)

ARCH_AUR_MINIMAL=(
    onlyoffice-bin
    rustdesk-bin
)

ARCH_FLATPAK_MINIMAL=(
    it.mijorus.gearlever
)

# Server mode: headless server with monitoring and security tools
ARCH_NATIVE_SERVER=(
    bat
    btop
    cmatrix
    cpupower
    docker
    docker-compose
    dosfstools
    duf
    fwupd
    hwinfo
    inxi
    nano
    ncdu
    net-tools
    nmap
    samba
    sl
    speedtest-cli
    sshfs
    ttf-hack-nerd
    ttf-liberation
    unrar
    wakeonlan
)

# Desktop environment specific packages
ARCH_DE_KDE_NATIVE=(
    gwenview
    kdeconnect
    kwalletmanager
    kvantum
    okular
    python-pyqt5
    python-pyqt6
    qbittorrent
    smplayer
    spectacle
)

ARCH_DE_GNOME_NATIVE=(
    adw-gtk-theme
    celluloid
    dconf-editor
    gnome-tweaks
    gufw
    seahorse
    transmission-gtk
)

ARCH_DE_KDE_FLATPAK=(
    it.mijorus.gearlever
)
ARCH_DE_GNOME_FLATPAK=(
    com.mattjakeman.ExtensionManager
    it.mijorus.gearlever
)

# Gaming packages
ARCH_GAMING_NATIVE=(
    gamemode
    goverlay
    lib32-gamemode
    lib32-glibc
    lib32-mangohud
    lib32-mesa
    lib32-vulkan-icd-loader
    mangohud
    mesa
    steam
    vulkan-icd-loader
    wine
)

ARCH_GAMING_FLATPAK=(
    com.heroicgameslauncher.hgl
    com.vysp3r.ProtonPlus
    io.github.Faugus.faugus-launcher
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
             optimization)
                 case "$type" in
                     native) printf "%s\n" "${ARCH_OPTIMIZATION[@]}" ;;
                     *) return 0 ;;
                 esac
                 ;;
            standard)
                case "$type" in
                native)
                    # Standard native should include# main standard list plus
                    # additional standard-specific essentials.
                    printf "%s\n" "${ARCH_NATIVE_STANDARD[@]}"
                    printf "%s\n" "${ARCH_NATIVE_STANDARD_ESSENTIALS[@]}"
                    ;;
                aur)    printf "%s\n" "${ARCH_AUR_STANDARD[@]}" ;;
                flatpak) printf "%s\n" "${ARCH_FLATPAK_STANDARD[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        minimal)
            case "$type" in
                 native)
                     # Minimal mode: lightweight desktop with essential tools only
                     printf "%s\n" "${ARCH_NATIVE_MINIMAL[@]}"
                     ;;
                 aur)    printf "%s\n" "${ARCH_AUR_MINIMAL[@]}" ;;
                 flatpak) printf "%s\n" "${ARCH_FLATPAK_MINIMAL[@]}" ;;
                 *) return 0 ;;
            esac
            ;;
        server)
            case "$type" in
                 native)
                     # Server mode: headless server with monitoring and security tools
                     printf "%s\n" "${ARCH_NATIVE_SERVER[@]}"
                     ;;
                 aur)    printf "%s\n" "${ARCH_AUR_SERVER[@]}" ;;
                 flatpak) printf "%s\n" "${ARCH_FLATPAK_SERVER[@]}" ;;
                 *) return 0 ;;
            esac
            ;;
        kde)
            case "$type" in
                native) printf "%s\n" "${ARCH_DE_KDE_NATIVE[@]}" ;;
                flatpak) printf "%s\n" "${ARCH_DE_KDE_FLATPAK[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        gnome)
            case "$type" in
                native) printf "%s\n" "${ARCH_DE_GNOME_NATIVE[@]}" ;;
                flatpak) printf "%s\n" "${ARCH_DE_GNOME_FLATPAK[@]}" ;;
                *) return 0 ;;
            esac
            ;;
        gaming)
            case "$type" in
                native) printf "%s\n" "${ARCH_GAMING_NATIVE[@]}" ;;
                aur)    printf "%s\n" "${ARCH_GAMING_AUR[@]}" ;;
                flatpak) printf "%s\n" "${ARCH_GAMING_FLATPAK[@]}" ;;
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

# Prepare Arch Linux system for configuration
arch_system_preparation() {
    step "Arch Linux System Preparation"

    # Initialize keyring if needed
    if [ ! -d "$ARCH_KEYRING" ]; then
        if ! pacman-key --init >/dev/null 2>&1; then
            return 1
        fi
        if ! pacman-key --populate archlinux >/dev/null 2>&1; then
            return 1
        fi
    fi

    # Configure pacman for optimal performance
    configure_pacman_arch

    # Enable multilib repository
    check_and_enable_multilib

    # Install essential packages early
    log_info "Installing essential Arch Linux packages..."
    for pkg in "${ARCH_ESSENTIALS[@]}"; do
        if ! pacman -Q "$pkg" >/dev/null 2>&1; then
            log_info "Installing $pkg..."
            if ! pacman -S --needed --noconfirm "$pkg" >/dev/null 2>&1; then
                log_warn "Failed to install $pkg"
            fi
        else
            log_info "$pkg already installed"
        fi
    done

    # Setup AUR helper and mirror optimization
    if ! "$SCRIPT_DIR/arch_aur_setup.sh"; then
        log_error "Failed to setup AUR and mirrors"
        return 1
    fi

    # Configure reflector for automatic mirror updates
    if command -v reflector >/dev/null 2>&1; then
        log_info "Configuring reflector for automatic mirror updates..."
        mkdir -p /etc/xdg/reflector
        cat << EOF > /etc/xdg/reflector/reflector.conf
--save /etc/pacman.d/mirrorlist
--protocol https,http
--latest 20
--sort rate
--age 24
--delay 1
EOF
        # Try to detect country for faster mirrors
        country=$(curl -s --max-time 5 https://ipinfo.io/country 2>/dev/null | tr -d '"\n\r')
        if [ -n "$country" ] && [ "$country" != "null" ]; then
            echo "--country $country" >> /etc/xdg/reflector/reflector.conf
            log_info "Configured reflector with country: $country"
        fi
        if systemctl enable --now reflector.timer >/dev/null 2>&1; then
            log_success "Reflector timer enabled for automatic weekly mirror updates"
        else
            log_warn "Failed to enable reflector timer"
        fi
    fi

    # Update system
    if supports_gum; then
        if spin "Updating system"  pacman -Syu --noconfirm >/dev/null 2>&1; then
            gum style "✓ System updated" --margin "0 2" --foreground "$GUM_SUCCESS_FG"
        fi
    else
        pacman -Syu --noconfirm >/dev/null 2>&1 || true
    fi
}

# Configure pacman package manager settings for Arch Linux
configure_pacman_arch() {
    log_info "Configuring pacman for optimal performance..."

    # Enable Color output
    if grep -q "^#Color" "$ARCH_REPOS_FILE"; then
        sed -i 's/^#Color/Color/' "$ARCH_REPOS_FILE"
    fi

    # Enable ParallelDownloads
    if grep -q "^#ParallelDownloads" "$ARCH_REPOS_FILE"; then
        sed -i "s/^#ParallelDownloads.*/ParallelDownloads = $PARALLEL_DOWNLOADS/" "$ARCH_REPOS_FILE"
    elif grep -q "^ParallelDownloads" "$ARCH_REPOS_FILE"; then
        sed -i "s/^ParallelDownloads.*/ParallelDownloads = $PARALLEL_DOWNLOADS/" "$ARCH_REPOS_FILE"
    else
        sed -i "/^\[options\]/a ParallelDownloads = $PARALLEL_DOWNLOADS" "$ARCH_REPOS_FILE"
    fi

    # Enable ILoveCandy
    if grep -q "^#ILoveCandy" "$ARCH_REPOS_FILE"; then
        sed -i 's/^#ILoveCandy/ILoveCandy/' "$ARCH_REPOS_FILE"
    fi

    # Enable VerbosePkgLists
    if grep -q "^#VerbosePkgLists" "$ARCH_REPOS_FILE"; then
        sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' "$ARCH_REPOS_FILE"
    fi

    # Clean old package cache to free up disk space
    if [ -d "/var/cache/pacman/pkg" ]; then
        local cache_dir="/var/cache/pacman/pkg"
        local cache_before=0
        local cache_after=0

        # Calculate cache size before cleaning
        if [ -d "$cache_dir" ]; then
            cache_before=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
        fi

        if supports_gum; then
            spin "Cleaning old package cache"  paccache -r -k 3 >/dev/null 2>&1
            gum style "✓ Old packages cleaned (keeping last 3 versions)" --margin "0 2" --foreground "$GUM_SUCCESS_FG"
        else
            paccache -r -k 3 >/dev/null 2>&1
            log_success "Old packages cleaned (keeping last 3 versions)"
        fi

        # Clean uninstalled packages cache
        if supports_gum; then
            spin "Removing cache for uninstalled packages"  paccache -r -u -k 0 >/dev/null 2>&1
            gum style "✓ Cache for uninstalled packages removed" --margin "0 2" --foreground "$GUM_SUCCESS_FG"
        else
            paccache -r -u -k 0 >/dev/null 2>&1
            log_success "Cache for uninstalled packages removed"
        fi

        # Calculate cache size after cleaning
        if [ -d "$cache_dir" ]; then
            cache_after=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
        fi

        # Show cache size reduction
        if [ "$cache_before" != "$cache_after" ]; then
            if supports_gum; then
                gum style "Cache size: $cache_before → $cache_after" --margin "0 2" --foreground "$GUM_BODY_FG"
            else
                log_info "Cache size reduced from $cache_before to $cache_after"
            fi
        fi
    fi

    log_success "pacman configured with optimizations"
}

# Enable multilib repository for 32-bit software support
check_and_enable_multilib() {
    log_info "Checking and enabling multilib repository..."

    if ! grep -q "^\[multilib\]" "$ARCH_REPOS_FILE"; then
        log_info "Enabling multilib repository..."
        sed -i '/\[options\]/a # Multilib repository\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' "$ARCH_REPOS_FILE"
        log_success "multilib repository enabled"
    else
        log_info "multilib repository already enabled"
    fi
}


# Enable and configure essential systemd services for Arch Linux
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
            if systemctl enable --now "$service" >/dev/null 2>&1; then
                log_success "Enabled and started $service"
            else
                log_warn "Failed to enable $service"
            fi
        fi
    done
}

# Configure system locales for Greek and US English on Arch Linux
arch_configure_locale() {
    step "Configuring Arch Linux Locales (Greek and US)"

    local locale_file="/etc/locale.gen"

    if [ ! -f "$locale_file" ]; then
        log_error "locale.gen file not found"
        return 1
    fi

    # Uncomment Greek locale (el_GR.UTF-8)
    if grep -q "^#el_GR.UTF-8 UTF-8" "$locale_file"; then
        log_info "Enabling Greek locale (el_GR.UTF-8)..."
        sed -i 's/^#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' "$locale_file"
        log_success "Greek locale enabled"
    elif grep -q "^el_GR.UTF-8 UTF-8" "$locale_file"; then
        log_info "Greek locale already enabled"
    else
        log_warn "Greek locale not found in locale.gen"
    fi

    # Uncomment US English locale (en_US.UTF-8)
    if grep -q "^#en_US.UTF-8 UTF-8" "$locale_file"; then
        log_info "Enabling US English locale (en_US.UTF-8)..."
        sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$locale_file"
        log_success "US English locale enabled"
    elif grep -q "^en_US.UTF-8 UTF-8" "$locale_file"; then
        log_info "US English locale already enabled"
    else
        log_warn "US English locale not found in locale.gen"
    fi

    # Generate locales
    log_info "Generating locales..."
    if locale-gen >/dev/null 2>&1; then
        log_success "Locales generated successfully"
    else
        log_error "Failed to generate locales"
        return 1
    fi

    # Set default locale to Greek (can be changed by user)
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

# Install kernel headers for all installed kernels
arch_install_kernel_headers() {
    step "Installing kernel headers for installed kernels"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would detect installed kernels and install corresponding headers"
        return 0
    fi

    # Get list of installed kernels (excluding headers, docs, firmware, etc.)
    local installed_kernels
    installed_kernels=$(pacman -Q | grep '^linux-' | grep -v 'headers' | grep -v 'docs' | grep -v 'firmware' | cut -d' ' -f1)

    if [ -z "$installed_kernels" ]; then
        log_warn "No linux kernels found installed"
        return 1
    fi

    local headers_to_install=""
    for kernel in $installed_kernels; do
        local header_pkg="${kernel}-headers"
        if ! pacman -Q "$header_pkg" >/dev/null 2>&1; then
            headers_to_install="$headers_to_install $header_pkg"
        fi
    done

    if [ -n "$headers_to_install" ]; then
        log_info "Installing kernel headers: $headers_to_install"
        if install_pkg $headers_to_install; then
            log_success "Kernel headers installed successfully"
        else
            log_error "Failed to install kernel headers"
            return 1
        fi
    else
        log_info "All kernel headers are already installed"
    fi
}

# =============================================================================
# MAIN ARCH CONFIGURATION FUNCTION
# =============================================================================

arch_main_config() {
    log_info "Starting Arch Linux configuration..."

    # System preparation already done early, proceed with configuration
    log_info "System preparation completed, proceeding with configuration..."

    # Install kernel headers for installed kernels
    arch_install_kernel_headers

    # AUR helper and mirrors are already configured
    log_success "AUR helper (yay) and mirrors are ready"

    arch_configure_bootloader

    arch_configure_plymouth

    arch_setup_shell

    # Ensure AUR packages are installed
    log_info "Ensuring AUR packages are installed..."
    case "$INSTALL_MODE" in
        standard)
            for pkg in "${ARCH_AUR_STANDARD[@]}"; do
                if ! is_package_installed "$pkg"; then
                    log_info "Installing missing AUR package: $pkg"
                    if yay -S --noconfirm "$pkg" >/dev/null 2>&1; then
                        log_success "Installed $pkg"
                    else
                        log_error "Failed to install $pkg"
                    fi
                fi
            done
            ;;
        minimal)
            for pkg in "${ARCH_AUR_MINIMAL[@]}"; do
                if ! is_package_installed "$pkg"; then
                    log_info "Installing missing AUR package: $pkg"
                    if yay -S --noconfirm "$pkg" >/dev/null 2>&1; then
                        log_success "Installed $pkg"
                    else
                        log_error "Failed to install $pkg"
                    fi
                fi
            done
            ;;
    esac

    arch_setup_kde_shortcuts

    arch_setup_solaar

    arch_enable_system_services

    arch_configure_locale

    # Show final summary
    if supports_gum; then
        echo ""
        gum style "Arch Linux Configuration Complete" \
                  --margin "1 2" --border double --border-foreground "$GUM_PRIMARY_FG" --padding "1 2"
        gum style "Your Arch Linux system has been optimized:" \
                  --margin "0 2" --foreground "$GUM_BODY_FG"
        gum style "✓ pacman: Optimized with parallel downloads and ILoveCandy" \
                  --margin "0 2" --foreground "$GUM_SUCCESS_FG"
        gum style "✓ cache: Cleaned old packages (keeping last 3 versions)" \
                  --margin "0 2" --foreground "$GUM_SUCCESS_FG"
        gum style "✓ mirrors: Optimized for faster downloads" \
                  --margin "0 2" --foreground "$GUM_SUCCESS_FG"
        gum style "✓ shell: ZSH configured with starship prompt" \
                  --margin "0 2" --foreground "$GUM_SUCCESS_FG"
        gum style "✓ locales: Greek (el_GR.UTF-8) and US English enabled" \
                  --margin "0 2" --foreground "$GUM_SUCCESS_FG"
        gum style "• Log out and back in to apply shell changes" \
                  --margin "0 2" --foreground "$GUM_BODY_FG"
        echo ""
    fi

    log_success "Arch Linux configuration completed"
}

# Arch-specific configuration files
ARCH_CONFIGS_DIR="$SCRIPT_DIR/../configs/arch"

# KDE configuration is now handled dynamically by kde_config.sh

# Setup ZSH shell environment for Arch Linux
# Note: Configuration file deployment is handled by the main configure_user_shell_and_configs function
arch_setup_shell() {
    step "Setting up ZSH shell environment"

    # Determine target user for shell change
    local target_user="${SUDO_USER:-$USER}"

    # Set ZSH as default shell for the target user (not root)
    if [ "$target_user" != "root" ]; then
        local current_shell
        current_shell=$(getent passwd "$target_user" | cut -d: -f7)
        local zsh_path
        zsh_path=$(command -v zsh 2>/dev/null)

        if [ -n "$zsh_path" ] && [ "$current_shell" != "$zsh_path" ]; then
            log_info "Changing default shell to ZSH for user $target_user..."
            if chsh -s "$zsh_path" "$target_user" 2>/dev/null; then
                log_success "Default shell changed to ZSH for $target_user"
                log_info "Shell change will take effect after logout/login"
            else
                log_warning "Failed to change shell automatically for $target_user"
                log_info "Please run this command manually:"
                log_info "  sudo chsh -s $zsh_path $target_user"
            fi
        elif [ "$current_shell" = "$zsh_path" ]; then
            log_info "ZSH is already the default shell for $target_user"
        fi
    else
        log_info "Running as root - shell configuration handled by main function"
    fi
}

# Shortcuts are now configured via kde_config.sh for all distros
    log_info "KDE shortcuts will be configured via kde_config.sh"

# Setup KDE global keyboard shortcuts for Arch Linux
# Note: KDE shortcuts are now handled by kde_config.sh for all distributions
arch_setup_kde_shortcuts() {
    [[ "${XDG_CURRENT_DESKTOP:-}" != "KDE" ]] && return

    log_info "KDE shortcuts will be configured via kde_config.sh for all distributions"
    # KDE shortcuts are now handled centrally by kde_config.sh
    # This prevents conflicts and ensures consistent configuration
}

# Setup Solaar for Logitech hardware management on Arch Linux
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
            if systemctl enable --now solaar.service >/dev/null 2>&1; then
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
# arch firewall is configured via security_configure_firewall() in security_config.sh
# Configure Plymouth boot splash screen for Arch Linux
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
            sed -i '/^HOOKS=/ s/)/ plymouth)/' /etc/mkinitcpio.conf || true
            log_info "Regenerating initramfs..."
            if mkinitcpio -P >/dev/null 2>&1; then
                log_success "Initramfs regenerated with plymouth hook"
            else
                log_warn "Failed to regenerate initramfs; please run 'mkinitcpio -P' manually"
            fi
        else
            log_info "mkinitcpio already contains plymouth hook"
        fi
    fi

    # Configure GRUB to include splash if needed
    if [ -f /etc/default/grub ]; then
        if ! grep -q 'splash' /etc/default/grub; then
            log_info "Adding 'splash' to GRUB kernel parameters"
            sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/& splash/' /etc/default/grub || true
            if grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
                log_success "GRUB configuration updated with splash"
            else
                log_warn "Failed to regenerate GRUB config; please run 'grub-mkconfig -o /boot/grub/grub.cfg' manually"
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
                if sed -i "/^options/ s/$/ splash/" "$entry" >/dev/null 2>&1; then
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
 export -f arch_configure_plymouth

# Configure systemd-boot for Arch Linux
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
                    sed -i "/^options/ s/$/ $arch_params/" "$entry"
                    log_success "Updated $entry"
                    updated=true
                else
                    echo "options $arch_params" | tee -a "$entry" >/dev/null
                    log_success "Updated $entry (added options)"
                    updated=true
                fi
            fi
        fi
    done
}

# Configure bootloader (GRUB or systemd-boot) for Arch Linux
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



configure_grub_arch() {
    log_info "Configuring GRUB for Arch Linux..."

    if [ ! -f /etc/default/grub ]; then
        log_error "/etc/default/grub not found"
        return 1
    fi

    # Set timeout
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

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
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_params\"|" /etc/default/grub
        log_success "Updated GRUB kernel parameters"
    fi

    # Regenerate GRUB config
    log_info "Regenerating GRUB configuration..."
    if ! grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
        log_error "Failed to regenerate GRUB config"
        return 1
    fi

    log_success "GRUB configured successfully"
}

export -f arch_system_preparation
export -f arch_configure_bootloader
export -f arch_configure_locale
export -f arch_install_kernel_headers
export -f arch_main_config
