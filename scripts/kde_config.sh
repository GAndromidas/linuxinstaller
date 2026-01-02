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

# KDE-specific package lists by distribution
ARCH_KDE=(
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

DEBIAN_KDE=(
    gwenview
    kdeconnect
    kdenlive
    kwalletmanager
    okular
    qbittorrent
    smplayer
)

FEDORA_KDE=(
    kvantum
    qbittorrent
    smplayer
)

KDE_REMOVALS=(
    akregator
    digikam
    dragon
    elisa-player
    htop
    k3b
    kaddressbook
    kamoso
    kdebugsettings
    kmahjongg
    kmail
    kmines
    kmouth
    kolourpaint
    korganizer
    kpat
    krfb
    krdc
    krusader
    ktorrent
    ktnef
    neochat
    pim-sieve-editor
    qrca
    showfoto
    skanpage
)

# KDE-specific configuration files
KDE_CONFIGS_DIR="$SCRIPT_DIR/../configs"

KDE_CONFIGS_DIR="$SCRIPT_DIR/../configs"

# =============================================================================
# KDE CONFIGURATION FUNCTIONS
# =============================================================================

# Install essential KDE packages and remove unnecessary ones
kde_install_packages() {
    display_step "🖥️" "Installing KDE Packages"

    # Install KDE packages based on distribution
    local kde_packages=()
    case "$DISTRO_ID" in
        arch)
            kde_packages=("${ARCH_KDE[@]}")
            ;;
        debian|ubuntu)
            kde_packages=("${DEBIAN_KDE[@]}")
            ;;
        fedora)
            kde_packages=("${FEDORA_KDE[@]}")
            ;;
        *)
            log_warn "Unsupported distribution for KDE packages: $DISTRO_ID"
            return 1
            ;;
    esac

    if [ ${#kde_packages[@]} -gt 0 ]; then
        install_packages_with_progress "${kde_packages[@]}"
    fi

    # Remove unnecessary KDE packages
    log_info "Removing unnecessary KDE packages..."
    for package in "${KDE_REMOVALS[@]}"; do
        if remove_pkg "$package"; then
            log_success "Removed KDE package: $package"
        else
            log_warn "Failed to remove KDE package: $package"
        fi
    done
}

# Configure KDE global keyboard shortcuts (Plasma 6.5+ compatible)
kde_configure_shortcuts() {
    display_step "⌨️" "Configuring KDE Shortcuts"

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
        plasma_version=$(plasmashell --version 2>/dev/null | grep -oP 'plasmashell \K[0-9]+\.[0-9]+' || echo "")
        if [ -z "$plasma_version" ]; then
            plasma_version=$(pacman -Q plasma-desktop 2>/dev/null | grep -oP '\d+\.\d+' || echo "")
        fi
        if [ -z "$plasma_version" ]; then
            if pacman -Q kf6 2>/dev/null >/dev/null; then
                plasma_version="6.0"
            elif pacman -Q kf5 2>/dev/null >/dev/null; then
                plasma_version="5.27"
            fi
        fi
    fi

    # Parse version components
    if [[ "$plasma_version" =~ ([0-9]+)\.([0-9]+) ]]; then
        plasma_major="${BASH_REMATCH[1]}"
        plasma_minor="${BASH_REMATCH[2]}"
    fi

    log_info "Detected KDE Plasma version: ${plasma_version:-unknown} (major: ${plasma_major:-?}, minor: ${plasma_minor:-?})"

    # Check for KDE config tools
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

    # Backup existing config
    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        log_info "Backed up existing shortcuts configuration"
    fi

    # Configure Meta+Q to close windows
    log_info "Setting up 'Meta+Q' to close windows..."

    # For kwin, the shortcut format in Plasma 6 is: "Shortcut,DefaultShortcut,Action"
    if [[ "$plasma_major" -ge 6 ]]; then
        # Plasma 6+ format
        $kwrite --file "$config_file" --group kwin --key "Window Close" "Meta+Q\tAlt+F4,Alt+F4,Close Window" || true
    else
        # Plasma 5 format
        local current_close_shortcut
        current_close_shortcut=$($kread --file "$config_file" --group kwin --key "Window Close" 2>/dev/null || echo "Alt+F4,Alt+F4,Close Window")

        # Add Meta+Q if not already present
        if ! [[ "$current_close_shortcut" =~ Meta\+Q ]]; then
            $kwrite --file "$config_file" --group kwin --key "Window Close" "Meta+Q\tAlt+F4,Alt+F4,Close Window" || true
        fi
    fi

    log_success "Shortcut 'Meta+Q' configured for closing windows."

    # Configure Meta+Enter to launch Konsole
    log_info "Setting up 'Meta+Enter' to launch Konsole..."

    # Create custom shortcut for launching Konsole
    # The proper way is to use the org_kde_konsole component
    if [[ "$plasma_major" -ge 6 ]]; then
        # Plasma 6+ uses a different structure for custom commands

        # Method 1: Use kwin's Launch Konsole action if available
        $kwrite --file "$config_file" --group org.kde.konsole.desktop --key "_launch" "Meta+Return,none,Launch Konsole" || true

        # Method 2: Configure a custom shortcut using khotkeys
        cat >> "$config_file" << 'EOF'

[org.kde.konsole.desktop]
_launch=Meta+Return,none,Launch Konsole

[plasmashell.desktop]
_k_friendly_name=Plasma

EOF

        # Method 3: Create a khotkeys configuration for custom command
        local khotkeys_file="$user_home/.config/khotkeysrc"

        # Backup khotkeys if exists
        if [ -f "$khotkeys_file" ]; then
            cp "$khotkeys_file" "${khotkeys_file}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi

        # Add custom shortcut group for Konsole launch
        cat >> "$khotkeys_file" << 'EOF'

[Data_1]
Comment=Launch Konsole with Meta+Return
DataCount=1
Enabled=true
Name=Launch Konsole
SystemGroup=0
Type=ACTION_DATA_GROUP

[Data_1Conditions]
Comment=
ConditionsCount=0

[Data_1_1]
Comment=Launch Konsole terminal
Enabled=true
Name=Launch Konsole
Type=SIMPLE_ACTION_DATA

[Data_1_1Actions]
ActionsCount=1

[Data_1_1Actions0]
CommandURL=konsole
Type=COMMAND_URL

[Data_1_1Conditions]
Comment=
ConditionsCount=0

[Data_1_1Triggers]
Comment=Simple_action
TriggersCount=1

[Data_1_1Triggers0]
Key=Meta+Return
Type=SHORTCUT
Uuid={12345678-1234-1234-1234-123456789abc}

EOF

    else
        # Plasma 5 format
        # Use standard krunner or custom command approach
        $kwrite --file "$config_file" --group "org.kde.konsole.desktop" --key "_launch" "Meta+Return,none,Launch Konsole" || true

        # Alternative: use khotkeys for Plasma 5
        local khotkeys_file="$user_home/.config/khotkeysrc"

        if [ -f "$khotkeys_file" ]; then
            cp "$khotkeys_file" "${khotkeys_file}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi

        # Append Konsole shortcut to khotkeys
        cat >> "$khotkeys_file" << 'EOF'

[Data_1]
Comment=Launch Konsole
DataCount=1
Enabled=true
Name=Konsole Shortcut
SystemGroup=0
Type=ACTION_DATA_GROUP

[Data_1_1]
Comment=Launch Konsole
Enabled=true
Name=Launch Konsole
Type=SIMPLE_ACTION_DATA

[Data_1_1Actions]
ActionsCount=1

[Data_1_1Actions0]
CommandURL=konsole
Type=COMMAND_URL

[Data_1_1Conditions]
Comment=
ConditionsCount=0

[Data_1_1Triggers]
Comment=
TriggersCount=1

[Data_1_1Triggers0]
Key=Meta+Return
Type=SHORTCUT
Uuid={abcd1234-5678-90ab-cdef-1234567890ab}

EOF
    fi

    log_success "Shortcut 'Meta+Return' configured to launch Konsole."

    # Set proper ownership for all config files
    chown -R "$target_user:$target_user" "$user_home/.config" 2>/dev/null || true

    # Reload the configuration as the target user
    log_info "Reloading KDE configuration..."

    if [ "$target_user" != "root" ]; then
        # Rebuild system configuration cache
        su - "$target_user" -c "$kbuild --noincremental >/dev/null 2>&1" 2>/dev/null || true

        # Restart kglobalaccel to reload shortcuts
        if [[ "$plasma_major" -ge 6 ]]; then
            # Plasma 6+ methods
            su - "$target_user" -c "kquitapp6 kglobalaccel5 2>/dev/null; sleep 1" 2>/dev/null || true
            su - "$target_user" -c "kglobalaccel6 2>/dev/null &" 2>/dev/null || true

            # Reconfigure kwin
            su - "$target_user" -c "qdbus org.kde.KWin /KWin reconfigure 2>/dev/null" 2>/dev/null || true

            # Restart khotkeys if exists
            su - "$target_user" -c "kquitapp6 khotkeys 2>/dev/null; sleep 1; kstart6 khotkeys 2>/dev/null &" 2>/dev/null || true
        else
            # Plasma 5 methods
            su - "$target_user" -c "kquitapp5 kglobalaccel 2>/dev/null; sleep 1" 2>/dev/null || true
            su - "$target_user" -c "kglobalaccel5 2>/dev/null &" 2>/dev/null || true

            # Reconfigure kwin
            su - "$target_user" -c "qdbus org.kde.KWin /KWin reconfigure 2>/dev/null" 2>/dev/null || true

            # Restart khotkeys
            su - "$target_user" -c "kquitapp5 khotkeys 2>/dev/null; sleep 1; kstart5 khotkeys 2>/dev/null &" 2>/dev/null || true
        fi
    fi

    log_success "KDE shortcuts configured and reloaded."
    log_info "═══════════════════════════════════════════════════════════"
    log_info "Configured shortcuts:"
    log_info "  • Meta+Q       → Close active window"
    log_info "  • Meta+Return  → Launch Konsole terminal"
    log_info "═══════════════════════════════════════════════════════════"
    log_info "Note: You may need to log out and log back in for shortcuts to fully activate."
    log_info "If shortcuts don't work after logout, check: System Settings → Shortcuts"
}

# Configure KDE desktop wallpaper
kde_configure_wallpaper() {
    display_step "🖼️" "Configuring KDE Wallpaper"

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
    display_step "🎨" "Configuring KDE Theme"

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
    display_step "🌐" "Configuring KDE Network Settings"

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
    display_step "🖥️" "Setting up KDE Plasma Desktop"

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
    display_step "📱" "Installing and Configuring KDE Connect"

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
# is_package_installed() function is available from common.sh
