#!/bin/bash
set -uo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LINUXINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$LINUXINSTALLER_ROOT/configs"
MAP_FILE="$CONFIGS_DIR/package_map.yaml"

source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

# Ensure yq
if ! command -v yq >/dev/null; then
    ui_info "Installing yq..."
    install_tool_silently yq # Helper from common.sh/install.sh context
fi

# --- Resolvers ---

resolve_native() {
    local key="$1"
    local distro="$DISTRO_ID"
    local val=$(yq -r ".mappings[\"$key\"].$distro // .mappings[\"$key\"].common" "$MAP_FILE" 2>/dev/null)
    
    if [ "$val" == "null" ] || [ -z "$val" ]; then
        echo "$key"
    else
        echo "$val"
    fi
}

resolve_universal() {
    local key="$1"
    local type="$2" # flatpak or snap
    local val=$(yq -r ".mappings[\"$key\"].$type" "$MAP_FILE" 2>/dev/null)
    
    if [ "$val" != "null" ]; then
        echo "$val"
    else
        echo ""
    fi
}

# --- Installers ---

native_install() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then return; fi
    
    step "Installing Native Packages"
    
    for pkg in "${packages[@]}"; do
        local target=$(resolve_native "$pkg")
        if [ -n "$target" ]; then
            for sub_pkg in $target; do
                if [ -n "$sub_pkg" ]; then
                    $PKG_INSTALL $PKG_NOCONFIRM "$sub_pkg" || log_warning "Failed to install $sub_pkg"
                fi
            done
        fi
    done
}

universal_install() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then return; fi
    
    step "Installing Universal/Extra Packages"
    
    for pkg in "${packages[@]}"; do
        local clean_name="${pkg%-bin}"
        clean_name="${clean_name%-git}"
        
        # Resolve native name first (e.g. vscode -> code)
        local native_target=$(resolve_native "$clean_name")
        
        # 1. Try Native First
        if [ "$DISTRO_ID" == "arch" ]; then
             # Arch: Use yay (handles Repo + AUR)
             if yay -S --noconfirm "$native_target"; then
                 ui_success "Installed $native_target via AUR/Pacman"
                 continue
             fi
        else
             # Non-Arch: Try native package manager
             if $PKG_INSTALL $PKG_NOCONFIRM "$native_target" >/dev/null 2>&1; then
                 ui_success "Installed $native_target natively"
                 continue
             fi
        fi
        
        # 2. Universal Fallback
        local snap_id=$(resolve_universal "$clean_name" "snap")
        local flatpak_id=$(resolve_universal "$clean_name" "flatpak")
        
        # Heuristics
        [ -z "$snap_id" ] && snap_id="$clean_name"
        [ -z "$flatpak_id" ] && flatpak_id="$clean_name"
        
        local installed=false
        
        # Priority Logic
        if [ "$PRIMARY_UNIVERSAL_PKG" == "snap" ]; then
             if [ -n "$snap_id" ] && sudo snap install "$snap_id"; then installed=true; fi
        elif [ "$PRIMARY_UNIVERSAL_PKG" == "flatpak" ]; then
             # Use resolver result if strict, or try heuristics if resolved name matches clean name (meaning unmapped)
             local try_fp="$flatpak_id"
             # If resolved id looks like a real ID (com.x.y) use it, else search flathub? 
             # flatpak install flathub NAME usually works.
             if flatpak install -y flathub "$try_fp"; then installed=true; fi
        fi
        
        # Backup Logic
        if [ "$installed" == "false" ]; then
             if [ "$BACKUP_UNIVERSAL_PKG" == "snap" ]; then
                  if [ -n "$snap_id" ] && sudo snap install "$snap_id"; then installed=true; fi
             elif [ "$BACKUP_UNIVERSAL_PKG" == "flatpak" ]; then
                  if flatpak install -y flathub "$flatpak_id"; then installed=true; fi
             fi
        fi
        
        if [ "$installed" == "false" ]; then
            log_warning "Could not find universal package for: $pkg"
        fi
    done
}

flatpak_install_list() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then return; fi

    step "Installing Flatpak Apps"
    for pkg in "${packages[@]}"; do
        flatpak install -y flathub "$pkg" || log_warning "Failed to install Flatpak $pkg"
    done
}

# --- Load Config ---
NATIVE_PACKAGES=()
UNIVERSAL_PACKAGES=()
FLATPAK_PACKAGES=()

load_config() {
    local config_file="$CONFIGS_DIR/programs.yaml"
    
    # 1. Native Packages
    while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && NATIVE_PACKAGES+=("$line"); done < <(yq -r '.pacman.packages[].name' "$config_file")
    
    # 2. Essential
    local mode="${INSTALL_MODE:-default}"
    while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && NATIVE_PACKAGES+=("$line"); done < <(yq -r ".essential.$mode[].name" "$config_file")
    
    # 3. Universal
    while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && UNIVERSAL_PACKAGES+=("$line"); done < <(yq -r ".aur.$mode[].name" "$config_file")
    
    # 4. Desktop Environment (Native)
    if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
        local de_key=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
        if [[ "$de_key" == *"gnome"* ]]; then de_key="gnome"; fi
        if [[ "$de_key" == *"kde"* ]]; then de_key="kde"; fi
        if [[ "$de_key" == *"cosmic"* ]]; then de_key="cosmic"; fi
        
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && NATIVE_PACKAGES+=("$line"); done < <(yq -r ".desktop_environments.$de_key.install[]" "$config_file")
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && FLATPAK_PACKAGES+=("$line"); done < <(yq -r ".flatpak.$de_key.$mode[].name" "$config_file")
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && FLATPAK_PACKAGES+=("$line"); done < <(yq -r ".flatpak.generic.$mode[].name" "$config_file")
    fi
}

# --- Main ---
load_config
native_install "${NATIVE_PACKAGES[@]}"
universal_install "${UNIVERSAL_PACKAGES[@]}"
flatpak_install_list "${FLATPAK_PACKAGES[@]}"

# Server Config
if [ "${INSTALL_MODE:-}" == "server" ] && command -v docker >/dev/null; then
    step "Configuring Server Apps"
    sudo systemctl enable --now docker.service
    sudo usermod -aG docker "$USER" || true
    
    # Watchtower
    sudo docker stop watchtower >/dev/null 2>&1 || true
    sudo docker rm watchtower >/dev/null 2>&1 || true
    if sudo docker run -d --name=watchtower --restart=always -v /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower; then
        log_success "Watchtower running."
    fi
fi
