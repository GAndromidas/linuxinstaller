#!/bin/bash
set -uo pipefail

# GNOME Configuration Module for LinuxInstaller
# Based on best practices from all installers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Ensure we're on a GNOME system
if [[ "${XDG_CURRENT_DESKTOP:-}" != *"GNOME"* ]]; then
    log_error "This module is for GNOME only"
    exit 1
fi

# GNOME-specific package lists
GNOME_ESSENTIALS=(
    "adw-gtk-theme"
    "celluloid"
    "dconf-editor"
    "gnome-tweaks"
    "gufw"
    "seahorse"
    "transmission-gtk"
)

GNOME_OPTIONAL=(
    "gnome-music"
    "gnome-weather"
    "gnome-clocks"
    "gnome-photos"
    "epiphany-browser"
)

GNOME_REMOVALS=(
    "htop"
    "rhythmbox"
    "totem"
    "gnome-tour"
    "epiphany"
    "simple-scan"
)

# GNOME-specific configuration files
GNOME_CONFIGS_DIR="$SCRIPT_DIR/../configs"

# =============================================================================
# GNOME CONFIGURATION FUNCTIONS
# =============================================================================

# Install essential GNOME packages and remove unnecessary ones
gnome_install_packages() {
    step "Installing GNOME Packages"

    log_info "Installing GNOME essential packages..."
    for package in "${GNOME_ESSENTIALS[@]}"; do
        if ! install_pkg "$package"; then
            log_warn "Failed to install GNOME package: $package"
        else
            log_success "Installed GNOME package: $package"
        fi
    done

    # Remove unnecessary GNOME packages
    log_info "Removing unnecessary GNOME packages..."
    for package in "${GNOME_REMOVALS[@]}"; do
        if remove_pkg "$package"; then
            log_success "Removed GNOME package: $package"
        else
            log_warn "Failed to remove GNOME package: $package (may not be installed)"
        fi
    done
}

# Configure GNOME shell extensions
gnome_configure_extensions() {
    step "Configuring GNOME Extensions"

    if ! command -v gnome-extensions >/dev/null 2>&1; then
        log_warn "GNOME extensions command not found"
        return
    fi

    # Enable useful extensions
    local extensions=(
        "dash-to-dock@micxgx.gmail.com"
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "apps-menu@gnome-shell-extensions.gcampax.github.com"
        "places-menu@gnome-shell-extensions.gcampax.github.com"
        "launch-new-instance@gnome-shell-extensions.gcampax.github.com"
    )

    log_info "Enabling GNOME extensions..."
    for extension in "${extensions[@]}"; do
        if gnome-extensions list | grep -q "$extension"; then
            if ! gnome-extensions enable "$extension" 2>/dev/null; then
                log_warn "Failed to enable extension: $extension"
            else
                log_success "Enabled extension: $extension"
            fi
        else
            log_warn "Extension not found: $extension"
        fi
    done
}

# Configure GNOME desktop theme and appearance settings
gnome_configure_theme() {
    step "Configuring GNOME Theme"

    if ! command -v gsettings >/dev/null 2>&1; then
        log_error "gsettings command not found. Cannot configure GNOME theme."
        return 1
    fi

    # Set theme to Adwaita-dark
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme 'Adwaita' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita' 2>/dev/null || true

    # Configure font settings
    gsettings set org.gnome.desktop.interface font-name 'Cantarell 11' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface document-font-name 'Sans 11' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface monospace-font-name 'Monospace 11' 2>/dev/null || true

    # Configure shell theme
    gsettings set org.gnome.shell.extensions.user-theme name 'Adwaita' 2>/dev/null || true

    log_success "GNOME theme configured"
}

# Configure GNOME keyboard shortcuts
gnome_configure_shortcuts() {
    step "Configuring GNOME Shortcuts"

    if ! command -v gsettings >/dev/null 2>&1; then
        log_error "gsettings command not found. Cannot configure GNOME shortcuts."
        return 1
    fi

    # Setup Meta+Q to Close Window
    log_info "Setting up 'Meta+Q' to close windows..."
    local close_key="org.gnome.desktop.wm.keybindings close"
    local current_close_bindings
    current_close_bindings=$(gsettings get $close_key 2>/dev/null || echo "['<Alt>F4']")
    if [[ "$current_close_bindings" != *"'<Super>q'"* ]]; then
        local new_bindings
        new_bindings=$(echo "$current_close_bindings" | sed "s/]$/, '<Super>q']/")
        gsettings set $close_key "$new_bindings" || true
        log_success "Shortcut 'Meta+Q' added for closing windows."
    else
        log_warn "Shortcut 'Meta+Q' for closing windows already seems to be set. Skipping."
    fi

    # Setup Meta+Enter to Launch Terminal
    log_info "Setting up 'Meta+Enter' to launch GNOME Terminal..."
    local keybinding_path="org.gnome.settings-daemon.plugins.media-keys.custom-keybindings"
    local custom_key="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom_terminal/"

    # Get current custom bindings
    local current_bindings_str
    current_bindings_str=$(gsettings get "$keybinding_path" custom-keybindings || echo "[]")

    # Add our new binding if it doesn't exist in the list
    if [[ "$current_bindings_str" != *"$custom_key"* ]]; then
        # Append to the list
        local new_list
        if [[ "$current_bindings_str" == "[]" || "$current_bindings_str" == "@as []" ]]; then
            new_list="['$custom_key']"
        else
            new_list=$(echo "$current_bindings_str" | sed "s/]$/, '$custom_key']/")
        fi
        gsettings set "$keybinding_path" custom-keybindings "$new_list" || true
    fi

    # Set the properties for our custom binding
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${custom_key}" name "Launch Terminal (linuxinstaller)" || true
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${custom_key}" command "gnome-terminal" || true
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${custom_key}" binding "<Super>Return" || true
    log_success "Shortcut 'Meta+Enter' created for GNOME Terminal."
}

# Configure GNOME desktop environment settings
gnome_configure_desktop() {
    step "Configuring GNOME Desktop"

    if ! command -v gsettings >/dev/null 2>&1; then
        log_error "gsettings command not found. Cannot configure GNOME desktop."
        return 1
    fi

    # Configure desktop behavior
    gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true
    gsettings set org.gnome.desktop.interface clock-show-date true 2>/dev/null || true
    gsettings set org.gnome.desktop.interface clock-show-weekday true 2>/dev/null || true
    gsettings set org.gnome.desktop.interface clock-format '12h' 2>/dev/null || true

    # Configure workspace behavior
    gsettings set org.gnome.desktop.wm.preferences num-workspaces 4 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.preferences workspace-names "['Work', 'Dev', 'Web', 'Media']" 2>/dev/null || true

    # Configure touchpad
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true 2>/dev/null || true
    gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true 2>/dev/null || true

    # Configure power settings
    gsettings set org.gnome.desktop.session idle-delay 600 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'suspend' 2>/dev/null || true

    log_success "GNOME desktop configured"
}

# Configure GNOME network settings
gnome_configure_network() {
    step "Configuring GNOME Network Settings"

    # Enable NetworkManager
    if systemctl list-unit-files | grep -q NetworkManager; then
        if ! sudo systemctl is-enabled NetworkManager >/dev/null 2>&1; then
            sudo systemctl enable NetworkManager >/dev/null 2>&1
            sudo systemctl start NetworkManager >/dev/null 2>&1
            log_success "NetworkManager enabled and started"
        fi
    fi

    # Configure network settings
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null || true
        gsettings set org.gnome.system.proxy ignore-hosts "['localhost', '127.0.0.0/8', '::1']" 2>/dev/null || true
    fi

    log_success "GNOME network settings configured"
}

# Install and configure GNOME Software application
gnome_install_gnome_software() {
    step "Installing and Configuring GNOME Software"

    # Install GNOME Software if not present
    if ! command -v gnome-software >/dev/null 2>&1; then
        if ! install_pkg gnome-software; then
            log_warn "Failed to install GNOME Software"
            return
        fi
    fi

    # Configure GNOME Software
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.software allow-updates true 2>/dev/null || true
        gsettings set org.gnome.software install-bundles-system-wide true 2>/dev/null || true
        gsettings set org.gnome.software download-updates true 2>/dev/null || true
    fi

    log_success "GNOME Software installed and configured"
}

# =============================================================================
# MAIN GNOME CONFIGURATION FUNCTION
# =============================================================================

gnome_main_config() {
    log_info "Starting GNOME configuration..."

    gnome_install_packages

    gnome_configure_extensions

    gnome_configure_theme

    gnome_configure_shortcuts

    gnome_configure_desktop

    gnome_configure_network

    gnome_install_gnome_software

    log_success "GNOME configuration completed"
}

# Export functions for use by main installer
export -f gnome_main_config
export -f gnome_install_packages
export -f gnome_configure_extensions
export -f gnome_configure_theme
export -f gnome_configure_shortcuts
export -f gnome_configure_desktop
export -f gnome_configure_network
export -f gnome_install_gnome_software
