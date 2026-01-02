#!/bin/bash
set -uo pipefail

# KDE Configuration Module for LinuxInstaller
# Based on best practices from all installers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Ensure we're on a KDE system
if [ "${XDG_CURRENT_DESKTOP:-}" != "KDE" ]; then
    log_error "This module is for KDE only"
    exit 1
fi

# KDE-specific package lists
KDE_ESSENTIALS=(
    "gwenview"
    "kdeconnect"
    "kdenlive"
    "kwalletmanager"
    "kvantum"
    "okular"
    "python-pyqt5"
    "python-pyqt6"
    "spectacle"
    "smplayer"
)

KDE_OPTIONAL=(
    "kdenlive"
    "kate"
    "dolphin"
    "konsole"
    "ark"
    "gwenview"
)

KDE_REMOVALS=(
    "akregator"
    "digikam"
    "dragon"
    "elisa-player"
    "htop"
    "k3b"
    "kaddressbook"
    "kamoso"
    "kdebugsettings"
    "kmahjongg"
    "kmail"
    "kmines"
    "kmouth"
    "kolourpaint"
    "korganizer"
    "kpat"
    "krfb"
    "krdc"
    "krusader"
    "ktorren"
    "ktnef"
    "neochat"
    "pim-sieve-editor"
    "qrca"
    "showfoto"
    "skanpage"
)

# KDE-specific configuration files
KDE_CONFIGS_DIR="$SCRIPT_DIR/../configs"

KDE_CONFIGS_DIR="$SCRIPT_DIR/../configs"

# =============================================================================
# KDE CONFIGURATION FUNCTIONS
# =============================================================================

# Install essential KDE packages and remove unnecessary ones
kde_install_packages() {
    step "Installing KDE Packages"

    # Install KDE essential packages
    if [ ${#KDE_ESSENTIALS[@]} -gt 0 ]; then
        install_packages_with_progress "${KDE_ESSENTIALS[@]}"
    fi

    # Remove unnecessary KDE packages
    log_info "Removing unnecessary KDE packages..."
    # Remove unnecessary KDE packages
    log_info "Removing unnecessary KDE packages..."
    for package in "${KDE_REMOVALS[@]}"; do
        if ! is_package_installed "$package"; then
            log_info "Package '$package' not installed, skipping removal"
            continue
        fi
        
        if remove_pkg "$package"; then
            log_success "Removed KDE package: $package"
        else
            log_warn "Failed to remove KDE package: $package"
        fi
    done
}

# Configure KDE global keyboard shortcuts (Plasma 6.5+ compatible)
kde_configure_shortcuts() {
    step "Configuring KDE Shortcuts"

    # Determine target user for shortcuts
    local target_user="${SUDO_USER:-$USER}"
    local user_home

    # Get the target user's home directory
    if [ "$target_user" = "root" ]; then
        user_home="/root"
    else
        user_home=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
        if [ -z "$user_home" ]; then
            user_home="/home/$target_user"
        fi
    fi

    local config_file="$user_home/.config/kglobalshortcutsrc"

    # Detect KDE/Plasma version for compatibility
    local plasma_version=""
    local plasma_major=""
    local plasma_minor=""

    if command -v plasmashell >/dev/null 2>&1; then
        # Try multiple methods to detect Plasma version
        plasma_version=$(plasmashell --version 2>/dev/null | grep -oP 'Plasma \K[0-9]+\.[0-9]+' || echo "")
        if [ -z "$plasma_version" ]; then
            # Fallback: check package version
            plasma_version=$(pacman -Q plasma-desktop 2>/dev/null | grep -oP '\d+\.\d+' || echo "")
        fi
        if [ -z "$plasma_version" ]; then
            # Another fallback: check kf6 or kf5 packages
            if pacman -Q kf6 2>/dev/null >/dev/null; then
                plasma_version="6.x"
            elif pacman -Q kf5 2>/dev/null >/dev/null; then
                plasma_version="5.x"
            fi
        fi
    fi

    # Parse version components
    if [[ "$plasma_version" =~ ([0-9]+)\.([0-9]+) ]]; then
        plasma_major="${BASH_REMATCH[1]}"
        plasma_minor="${BASH_REMATCH[2]}"
    fi

    log_info "Detected KDE Plasma version: ${plasma_version:-unknown} (major: ${plasma_major:-?}, minor: ${plasma_minor:-?})"

    if ! command -v kwriteconfig5 >/dev/null 2>&1 && ! command -v kwriteconfig6 >/dev/null 2>&1; then
        log_error "kwriteconfig command not found. Cannot configure KDE shortcuts."
        log_info "Make sure KDE Plasma is properly installed."
        return 1
    fi

    local kwrite="kwriteconfig5"
    local kread="kreadconfig5"
    local kbuild="kbuildsycoca5"

    # Use KDE 6 tools if available (Plasma 6.0+)
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwrite="kwriteconfig6"
        kread="kreadconfig6"
        kbuild="kbuildsycoca6"
        log_info "Using KDE 6 configuration tools"
    fi

    # Ensure config directory exists
    mkdir -p "$(dirname "$config_file")" || {
        log_warn "Failed to create KDE config directory"
        return 1
    }

    # For Plasma 6.5+, use different shortcut configuration approach
    if [[ "$plasma_major" -eq 6 && "$plasma_minor" -ge 5 ]] || [[ "$plasma_version" == "unknown" && "$plasma_major" == "6" ]]; then
        log_info "Configuring shortcuts for Plasma 6.5+..."

        # Create a comprehensive shortcuts configuration
        cat > "$config_file" << 'EOF'
[$Version]
update_info=kded.upd:replace-home-shortcuts

[data]
Version=2

[kdeglobals]
Version=2

[kwin]
Window Close=Alt+F4,Super+Q

[org.kde.kglobalaccel]
component=krunner
interface=org.kde.krunner.App
method=activate
path=/MainApplication

[services]
Launch Konsole=Meta+Return,dbus-send,dbus-send --session --dest=org.kde.krunner --type=method_call /org/kde/krunner/SingleRunner org.kde.krunner.SingleRunner.RunCommand string:'konsole',Launch Konsole
EOF

        log_success "Applied Plasma 6.5+ compatible shortcuts configuration"
    else
        # Legacy Plasma configuration for versions < 6.5
        log_info "Configuring shortcuts for Plasma < 6.5..."

        # Setup Meta+Q to Close Window
        log_info "Setting up 'Meta+Q' to close windows..."
        local current_close_shortcut
        current_close_shortcut=$($kread --file "$config_file" --group kwin --key "Window Close" 2>/dev/null || echo "Alt+F4")
        if ! [[ "$current_close_shortcut" == *",Super+Q"* ]] && ! [[ "$current_close_shortcut" == *"Super+Q"* ]]; then
            $kwrite --file "$config_file" --group kwin --key "Window Close" "${current_close_shortcut},Super+Q" 2>/dev/null || true
            log_success "Shortcut 'Meta+Q' added for closing windows."
        else
            log_info "Shortcut 'Meta+Q' for closing windows already set."
        fi

        # Setup Meta+Enter to Launch Terminal (Konsole for KDE)
        log_info "Setting up 'Meta+Enter' to launch Konsole..."
        $kwrite --file "$config_file" --group services --key "krunner" "Meta+Return,none,Run Command,Run Command" 2>/dev/null || true
        $kwrite --file "$config_file" --group services --key "Launch Terminal" "Meta+Return,dbus-send,dbus-send --session --dest=org.kde.krunner --type=method_call /org/kde/krunner/SingleRunner org.kde.krunner.SingleRunner.RunCommand string:'konsole',Launch Konsole" 2>/dev/null || true
        log_success "Shortcut 'Meta+Enter' set to launch Konsole."
    fi

    # Set proper ownership
    chown "$target_user:$target_user" "$config_file" 2>/dev/null || true

    # Reload the configuration and shortcut daemon as the target user
    log_info "Reloading KDE shortcut configuration..."
    if [ "$target_user" != "root" ]; then
        # Run KDE commands as the target user
        su - "$target_user" -c "$kbuild >/dev/null 2>&1" 2>/dev/null || true

        # Try different D-Bus methods for different Plasma versions
        if [[ "$plasma_major" -eq 6 && "$plasma_minor" -ge 5 ]] || [[ "$plasma_version" == "unknown" && "$plasma_major" == "6" ]]; then
            # Plasma 6.5+ specific reload
            su - "$target_user" -c "dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /kglobalaccel org.kde.kglobalaccel.reconfigure >/dev/null 2>&1" 2>/dev/null || \
            su - "$target_user" -c "kquitapp6 kglobalaccel 2>/dev/null && kstart6 kglobalaccel 2>/dev/null" 2>/dev/null || \
            su - "$target_user" -c "systemctl --user restart plasma-kglobalaccel.service" 2>/dev/null || true
        else
            # Legacy Plasma reload
            su - "$target_user" -c "dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /component/kwin org.kde.kglobalaccel.Component.reconfigure >/dev/null 2>&1" 2>/dev/null || true
        fi
    fi

    log_success "KDE shortcuts configured and reloaded."

    if [[ "$plasma_major" -eq 6 && "$plasma_minor" -ge 5 ]]; then
        log_info "Plasma 6.5+ detected - shortcuts configured using modern method."
        log_info "May require logout/login for all shortcuts to take effect."
    else
        log_info "Plasma ${plasma_version:-legacy} detected - shortcuts applied using standard method."
    fi

    log_info "Test shortcuts: Meta+Q (close window), Meta+Enter (launch Konsole)"
    log_info "If shortcuts don't work, try: System Settings → Shortcuts → Global Shortcuts"
}

# Configure KDE desktop wallpaper
kde_configure_wallpaper() {
    step "Configuring KDE Wallpaper"

    if [ -f "$KDE_CONFIGS_DIR/kde_wallpaper.jpg" ]; then
        log_info "Setting KDE wallpaper..."
        local kwrite="kwriteconfig5"
        if command -v kwriteconfig6 >/dev/null 2>&1; then kwrite="kwriteconfig6"; fi

        $kwrite --file kscreenlockerrc --group "Greeter" --key "WallpaperPlugin" "org.kde.image" || true
        $kwrite --file plasmarc --group "Theme" --key "name" "breeze" || true

        log_success "KDE wallpaper configured"
    else
        log_info "KDE wallpaper file not found, skipping wallpaper configuration"
    fi
}

# Configure KDE desktop theme and appearance settings
kde_configure_theme() {
    step "Configuring KDE Theme"

    local kwrite="kwriteconfig5"
    if command -v kwriteconfig6 >/dev/null 2>&1; then kwrite="kwriteconfig6"; fi

    # Set theme to Breeze
    $kwrite --file kdeglobals --group "General" --key "ColorScheme" "Breeze" || true
    $kwrite --file kdeglobals --group "General" --key "Name" "Breeze" || true

    # Configure font settings
    $kwrite --file kdeglobals --group "General" --key "fixed" "DejaVu Sans Mono,10,-1,5,50,0,0,0,0,0" || true
    $kwrite --file kdeglobals --group "General" --key "font" "DejaVu Sans,10,-1,5,50,0,0,0,0,0" || true

    # Configure window behavior
    $kwrite --file kwinrc --group "Windows" --key "RollOverDesktopSwitching" "true" || true
    $kwrite --file kwinrc --group "Windows" --key "AutoRaise" "false" || true
    $kwrite --file kwinrc --group "Windows" --key "AutoRaiseInterval" "300" || true

    log_success "KDE theme configured"
}

# Configure KDE network settings and NetworkManager integration
kde_configure_network() {
    step "Configuring KDE Network Settings"

    # Enable NetworkManager integration
    if systemctl list-unit-files | grep -q NetworkManager; then
        if ! systemctl is-enabled NetworkManager >/dev/null 2>&1; then
            systemctl enable NetworkManager >/dev/null 2>&1
            systemctl start NetworkManager >/dev/null 2>&1
            log_success "NetworkManager enabled and started"
        fi
    fi

    # Configure plasma-nm
    local kwrite="kwriteconfig5"
    if command -v kwriteconfig6 >/dev/null 2>&1; then kwrite="kwriteconfig6"; fi

    $kwrite --file plasma-nm --group "General" --key "RememberPasswords" "true" || true
    $kwrite --file plasma-nm --group "General" --key "EnableOfflineMode" "true" || true

    log_success "KDE network settings configured"
}

# Configure KDE Plasma desktop environment settings
kde_setup_plasma() {
    step "Setting up KDE Plasma Desktop"

    # Configure Plasma desktop settings
    local kwrite="kwriteconfig5"
    if command -v kwriteconfig6 >/dev/null 2>&1; then kwrite="kwriteconfig6"; fi

    # Disable desktop effects for better performance
    $kwrite --file kwinrc --group "Compositing" --key "Enabled" "true" || true
    $kwrite --file kwinrc --group "Compositing" --key "OpenGLIsUnsafe" "false" || true

    # Configure desktop behavior
    $kwrite --file kwinrc --group "Windows" --key "FocusPolicy" "ClickToFocus" || true
    $kwrite --file kwinrc --group "Windows" --key "FocusStealingPreventionLevel" "1" || true

    # Configure taskbar
    $kwrite --file plasmarc --group "PlasmaViews" --key "TaskbarPosition" "Bottom" || true

    log_success "KDE Plasma desktop configured"
}

# Install and configure KDE Connect for device integration
kde_install_kdeconnect() {
    step "Installing and Configuring KDE Connect"

    # Install KDE Connect
    install_packages_with_progress "kdeconnect" || log_warn "Failed to install KDE Connect"

    # Configure KDE Connect
    local kwrite="kwriteconfig5"
    if command -v kwriteconfig6 >/dev/null 2>&1; then kwrite="kwriteconfig6"; fi

    $kwrite --file kdeconnectrc --group "Daemon" --key "AutoAcceptPair" "true" || true
    $kwrite --file kdeconnectrc --group "Daemon" --key "RunDaemonOnStartup" "true" || true

    # Enable KDE Connect service
    if systemctl list-unit-files | grep -q kdeconnectd; then
        systemctl enable kdeconnectd >/dev/null 2>&1
        systemctl start kdeconnectd >/dev/null 2>&1
    fi

    log_success "KDE Connect installed and configured"
}

# =============================================================================
# MAIN KDE CONFIGURATION FUNCTION
# =============================================================================

kde_main_config() {
    log_info "Starting KDE configuration..."

    kde_install_packages

    kde_configure_shortcuts

    kde_configure_wallpaper

    kde_configure_theme

    kde_configure_network

    kde_setup_plasma

    kde_install_kdeconnect

    log_success "KDE configuration completed"
    # Cleanup redundant Arch-specific config files (now configured via scripts)
    if [ -f "$SCRIPT_DIR/../configs/arch/MangoHud.conf" ]; then
        rm -f "$SCRIPT_DIR/../configs/arch/MangoHud.conf"
        log_info "Removed Arch MangoHud config (migrated to script-based setup)"
    fi
    # Note: KDE shortcuts are now handled dynamically by kde_configure_shortcuts
    # The static kglobalshortcutsrc file is no longer used
}

# Export functions for use by main installer
export -f kde_main_config
export -f kde_install_packages
export -f kde_configure_shortcuts
export -f kde_configure_wallpaper
export -f kde_configure_theme
export -f kde_configure_network
export -f kde_setup_plasma
export -f kde_install_kdeconnect
# Check if a package is installed (distro-agnostic)
is_package_installed() {
    local pkg="$1"
    
    case "$DISTRO_ID" in
        "arch")
            pacman -Qq "$pkg" >/dev/null 2>&1
            ;;
        "fedora")
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
        "debian"|"ubuntu")
            dpkg -l | grep -q "^ii  $pkg"
            ;;
        *)
            # Fallback: try to query package manager
            if command -v pacman >/dev/null 2>&1; then
                pacman -Qq "$pkg" >/dev/null 2>&1
            elif command -v rpm >/dev/null 2>&1; then
                rpm -q "$pkg" >/dev/null 2>&1
            elif command -v dpkg >/dev/null 2>&1; then
                dpkg -l | grep -q "^ii  $pkg"
            else
                return 1
            fi
            ;;
    esac
}
