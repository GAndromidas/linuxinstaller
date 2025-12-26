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
    "kwalletmanager"
    "kvantum"
    "okular"
    "spectacle"
    "plasma-nm"
    "plasma-pa"
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

# =============================================================================
# KDE CONFIGURATION FUNCTIONS
# =============================================================================

kde_install_packages() {
    step "Installing KDE Packages"

    log_info "Installing KDE essential packages..."
    for package in "${KDE_ESSENTIALS[@]}"; do
        if ! install_pkg "$package"; then
            log_warn "Failed to install KDE package: $package"
        else
            log_success "Installed KDE package: $package"
        fi
    done

    # Remove unnecessary KDE packages
    log_info "Removing unnecessary KDE packages..."
    for package in "${KDE_REMOVALS[@]}"; do
        if remove_pkg "$package"; then
            log_success "Removed KDE package: $package"
        else
            log_warn "Failed to remove KDE package: $package (may not be installed)"
        fi
    done
}

kde_configure_shortcuts() {
    step "Configuring KDE Shortcuts"

    local config_file="$HOME/.config/kglobalshortcutsrc"

    if ! command -v kwriteconfig5 >/dev/null 2>&1 && ! command -v kwriteconfig6 >/dev/null 2>&1; then
        log_error "kwriteconfig command not found. Cannot configure KDE shortcuts."
        return 1
    fi

    local kwrite="kwriteconfig5"
    if command -v kwriteconfig6 >/dev/null 2>&1; then kwrite="kwriteconfig6"; fi

    local kread="kreadconfig5"
    if command -v kreadconfig6 >/dev/null 2>&1; then kread="kreadconfig6"; fi

    # Setup Meta+Q to Close Window
    log_info "Setting up 'Meta+Q' to close windows..."
    local current_close_shortcut
    current_close_shortcut=$($kread --file "$config_file" --group kwin --key "Window Close" || echo "Alt+F4")
    if ! [[ "$current_close_shortcut" == *",Super+Q"* ]]; then
        $kwrite --file "$config_file" --group kwin --key "Window Close" "${current_close_shortcut},Super+Q" || true
        log_success "Shortcut 'Meta+Q' added for closing windows."
    else
        log_warn "Shortcut 'Meta+Q' for closing windows already seems to be set. Skipping."
    fi

    # Setup Meta+Enter to Launch Terminal (Konsole)
    log_info "Setting up 'Meta+Enter' to launch Konsole..."
    $kwrite --file "$config_file" --group "org.kde.konsole.desktop" --key "new-window" "Meta+Return,none,New Window" || true
    log_success "Attempted to set 'Meta+Enter' to launch Konsole. You may need to log out for this to apply."

    # Reload the shortcut daemon
    log_info "Reloading shortcut configuration..."
    dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /component/kwin org.kde.kglobalaccel.Component.reconfigure >/dev/null 2>&1 || true
    dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /component/org.kde.konsole.desktop org.kde.kglobalaccel.Component.reconfigure >/dev/null 2>&1 || true
}

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

kde_configure_network() {
    step "Configuring KDE Network Settings"

    # Enable NetworkManager integration
    if systemctl list-unit-files | grep -q NetworkManager; then
        if ! sudo systemctl is-enabled NetworkManager >/dev/null 2>&1; then
            sudo systemctl enable NetworkManager >/dev/null 2>&1
            sudo systemctl start NetworkManager >/dev/null 2>&1
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

kde_install_kdeconnect() {
    step "Installing and Configuring KDE Connect"

    # Install KDE Connect
    if ! install_pkg kdeconnect; then
        log_warn "Failed to install KDE Connect"
        return
    fi

    # Configure KDE Connect
    local kwrite="kwriteconfig5"
    if command -v kwriteconfig6 >/dev/null 2>&1; then kwrite="kwriteconfig6"; fi

    $kwrite --file kdeconnectrc --group "Daemon" --key "AutoAcceptPair" "true" || true
    $kwrite --file kdeconnectrc --group "Daemon" --key "RunDaemonOnStartup" "true" || true

    # Enable KDE Connect service
    if systemctl list-unit-files | grep -q kdeconnectd; then
        sudo systemctl enable kdeconnectd >/dev/null 2>&1
        sudo systemctl start kdeconnectd >/dev/null 2>&1
    fi

    log_success "KDE Connect installed and configured"
}

# =============================================================================
# MAIN KDE CONFIGURATION FUNCTION
# =============================================================================

kde_main_config() {
    log_info "Starting KDE configuration..."

    # Install KDE packages
    if ! is_step_complete "kde_install_packages"; then
        kde_install_packages
        mark_step_complete "kde_install_packages"
    fi

    # Configure shortcuts
    if ! is_step_complete "kde_configure_shortcuts"; then
        kde_configure_shortcuts
        mark_step_complete "kde_configure_shortcuts"
    fi

    # Configure wallpaper
    if ! is_step_complete "kde_configure_wallpaper"; then
        kde_configure_wallpaper
        mark_step_complete "kde_configure_wallpaper"
    fi

    # Configure theme
    if ! is_step_complete "kde_configure_theme"; then
        kde_configure_theme
        mark_step_complete "kde_configure_theme"
    fi

    # Configure network
    if ! is_step_complete "kde_configure_network"; then
        kde_configure_network
        mark_step_complete "kde_configure_network"
    fi

    # Setup Plasma
    if ! is_step_complete "kde_setup_plasma"; then
        kde_setup_plasma
        mark_step_complete "kde_setup_plasma"
    fi

    # Install KDE Connect
    if ! is_step_complete "kde_install_kdeconnect"; then
        kde_install_kdeconnect
        mark_step_complete "kde_install_kdeconnect"
    fi

    log_success "KDE configuration completed"
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
```
</tool_response>
