#!/bin/bash

# This script configures universal keyboard shortcuts for GNOME and KDE Plasma.
# It sets Meta+Enter to launch a terminal and Meta+Q to close a window.

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
# Ensure we have DE detection
if [ -z "${XDG_CURRENT_DESKTOP:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_de
fi

# --- GNOME Shortcut Configuration ---
setup_gnome_shortcuts() {
    log_info "Detected GNOME. Configuring shortcuts..."
    if ! command -v gsettings >/dev/null 2>&1; then
        log_error "'gsettings' command not found. Cannot configure GNOME shortcuts."
        return
    fi

    # --- Setup Meta+Q to Close Window ---
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

    # --- Setup Meta+Enter to Launch Terminal ---
    log_info "Detecting available terminal..."
    local terminal_cmd=""
    local terminals_to_check=("gnome-terminal" "kgx" "ptyxis" "x-terminal-emulator")
    for term in "${terminals_to_check[@]}"; do
        if command -v "$term" >/dev/null 2>&1; then
            terminal_cmd="$term"
            log_success "Found terminal: $terminal_cmd"
            break
        fi
    done

    if [ -z "$terminal_cmd" ]; then
        log_error "Could not find a compatible terminal to assign a shortcut."
        return
    fi

    log_info "Setting up 'Meta+Enter' to launch '$terminal_cmd'..."
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
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${custom_key}" command "$terminal_cmd" || true
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${custom_key}" binding "<Super>Return" || true
    log_success "Shortcut 'Meta+Enter' created for '$terminal_cmd'."
}


# --- KDE Plasma Shortcut Configuration ---
setup_kde_shortcuts() {
    log_info "Detected KDE Plasma. Configuring shortcuts..."
    local config_file="$HOME/.config/kglobalshortcutsrc"

    if ! command -v kwriteconfig5 >/dev/null 2>&1 && ! command -v kwriteconfig6 >/dev/null 2>&1; then
        log_error "kwriteconfig command not found. Cannot configure KDE shortcuts."
        return
    fi
    
    local kwrite="kwriteconfig5"
    if command -v kwriteconfig6 >/dev/null 2>&1; then kwrite="kwriteconfig6"; fi
    
    local kread="kreadconfig5"
    if command -v kreadconfig6 >/dev/null 2>&1; then kread="kreadconfig6"; fi

    # --- Setup Meta+Q to Close Window ---
    log_info "Setting up 'Meta+Q' to close windows..."
    local current_close_shortcut
    current_close_shortcut=$($kread --file "$config_file" --group kwin --key "Window Close" || echo "Alt+F4")
    if ! [[ "$current_close_shortcut" == *",Super+Q"* ]]; then
        $kwrite --file "$config_file" --group kwin --key "Window Close" "${current_close_shortcut},Super+Q" || true
        log_success "Shortcut 'Meta+Q' added for closing windows."
    else
        log_warn "Shortcut 'Meta+Q' for closing windows already seems to be set. Skipping."
    fi

    # --- Setup Meta+Enter to Launch Terminal (Konsole) ---
    log_info "Setting up 'Meta+Enter' to launch Konsole..."
    $kwrite --file "$config_file" --group "org.kde.konsole.desktop" --key "new-window" "Meta+Return,none,New Window" || true
    log_success "Attempted to set 'Meta+Enter' to launch Konsole. You may need to log out for this to apply."

    # Reload the shortcut daemon
    log_info "Reloading shortcut configuration..."
    dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /component/kwin org.kde.kglobalaccel.Component.reconfigure >/dev/null 2>&1 || true
    dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /component/org.kde.konsole.desktop org.kde.kglobalaccel.Component.reconfigure >/dev/null 2>&1 || true
}

# --- Main Execution ---

if [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]]; then
    setup_gnome_shortcuts
elif [[ "${XDG_CURRENT_DESKTOP:-}" == *"KDE"* ]]; then
    setup_kde_shortcuts
else
    log_info "No compatible desktop environment (GNOME or KDE) was detected for shortcuts."
fi
