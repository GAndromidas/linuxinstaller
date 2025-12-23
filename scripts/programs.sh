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

# Validate DISTRO_ID is set
if [ -z "${DISTRO_ID:-}" ]; then
    log_error "DISTRO_ID is not set. Cannot continue."
    exit 1
fi

# Ensure yq is available
if ! command -v yq >/dev/null; then
    ui_info "Installing yq..."
    if [ -n "${PKG_INSTALL:-}" ]; then
        $PKG_INSTALL ${PKG_NOCONFIRM:-} yq >/dev/null 2>&1 || {
            log_warning "Failed to install yq via package manager. Trying alternative method..."
            # Try binary installation as fallback
            ARCH="amd64"; [[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"
            VER="latest"
            if curl -L -s -o /tmp/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" 2>/dev/null; then
                sudo mv /tmp/yq /usr/local/bin/yq
                sudo chmod +x /usr/local/bin/yq
            else
                log_error "Failed to install yq. Cannot continue without yq."
                exit 1
            fi
        }
    else
        log_error "PKG_INSTALL not set. Cannot install yq."
        exit 1
    fi
fi

# Validate MAP_FILE exists
if [ ! -f "$MAP_FILE" ]; then
    log_warning "Package map file not found: $MAP_FILE. Package resolution may be limited."
fi

# --- Resolvers ---

resolve_native() {
    local key="$1"
    local distro="${DISTRO_ID:-}"
    local val=""
    
    if [ -z "$distro" ]; then
        echo "$key"
        return
    fi
    
    # Try YAML lookup if MAP_FILE exists
    if [ -f "$MAP_FILE" ] && command -v yq >/dev/null; then
        val=$(yq -r ".mappings[\"$key\"].$distro // .mappings[\"$key\"].common" "$MAP_FILE" 2>/dev/null)
    fi
    
    # Fallback to hardcoded resolver if yq failed or MAP_FILE missing
    if [ "$val" == "null" ] || [ -z "$val" ]; then
        # Use resolve_package_name from distro_check.sh if available
        if command -v resolve_package_name >/dev/null; then
            val=$(resolve_package_name "$key")
        else
            val="$key"
        fi
    fi
    
    echo "$val"
}

resolve_universal() {
    local key="$1"
    local type="$2" # flatpak or snap
    
    if [ ! -f "$MAP_FILE" ] || ! command -v yq >/dev/null; then
        echo ""
        return
    fi
    
    local val=$(yq -r ".mappings[\"$key\"].$type" "$MAP_FILE" 2>/dev/null)
    
    if [ "$val" != "null" ] && [ -n "$val" ]; then
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
                    printf "%-40s" "$sub_pkg"
                    if $PKG_INSTALL $PKG_NOCONFIRM "$sub_pkg" >/dev/null 2>&1; then
                        printf "${GREEN}OK${RESET}\n"
                    else
                        printf "${RED}FAIL${RESET}\n"
                    fi
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
        local installed=false
        local display_name="$pkg"
        
        # Print package name once at the start
        printf "%-40s" "$display_name"
        
        # 1. Try Native First
        if [ "$DISTRO_ID" == "arch" ] && command -v yay >/dev/null 2>&1; then
             # Arch: Use yay (handles Repo + AUR)
             if yay -S --noconfirm --needed "$native_target" >/dev/null 2>&1; then
                 printf "${GREEN}OK${RESET}\n"
                 installed=true
             fi
        elif [ -n "${PKG_INSTALL:-}" ]; then
             # Non-Arch: Try native package manager
             if $PKG_INSTALL ${PKG_NOCONFIRM:-} "$native_target" >/dev/null 2>&1; then
                 printf "${GREEN}OK${RESET}\n"
                 installed=true
             fi
        fi
        
        # 2. Universal Fallback (only if native failed)
        if [ "$installed" == "false" ]; then
            local snap_id=$(resolve_universal "$clean_name" "snap")
            local flatpak_id=$(resolve_universal "$clean_name" "flatpak")
            
            # Heuristics
            [ -z "$snap_id" ] && snap_id="$clean_name"
            [ -z "$flatpak_id" ] && flatpak_id="$clean_name"
            
            # Priority Logic
            if [ "$PRIMARY_UNIVERSAL_PKG" == "snap" ] && [ -n "$snap_id" ]; then
                 if sudo snap install "$snap_id" >/dev/null 2>&1; then
                     printf "${GREEN}OK${RESET}\n"
                     installed=true
                 fi
            elif [ "$PRIMARY_UNIVERSAL_PKG" == "flatpak" ]; then
                 if flatpak install -y flathub "$flatpak_id" >/dev/null 2>&1; then
                     printf "${GREEN}OK${RESET}\n"
                     installed=true
                 fi
            fi
            
            # Backup Logic
            if [ "$installed" == "false" ]; then
                 if [ "$BACKUP_UNIVERSAL_PKG" == "snap" ] && [ -n "$snap_id" ]; then
                      if sudo snap install "$snap_id" >/dev/null 2>&1; then
                          printf "${GREEN}OK${RESET}\n"
                          installed=true
                      fi
                 elif [ "$BACKUP_UNIVERSAL_PKG" == "flatpak" ]; then
                      if flatpak install -y flathub "$flatpak_id" >/dev/null 2>&1; then
                          printf "${GREEN}OK${RESET}\n"
                          installed=true
                      fi
                 fi
            fi
        fi
        
        if [ "$installed" == "false" ]; then
            printf "${RED}FAIL${RESET}\n"
        fi
    done
}

flatpak_install_list() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then return; fi

    step "Installing Flatpak Apps"
    for pkg in "${packages[@]}"; do
        printf "%-40s" "$pkg"
        if flatpak install -y flathub "$pkg" >/dev/null 2>&1; then
            printf "${GREEN}OK${RESET}\n"
        else
            printf "${RED}FAIL${RESET}\n"
        fi
    done
}

# --- Load Config ---
NATIVE_PACKAGES=()
UNIVERSAL_PACKAGES=()
FLATPAK_PACKAGES=()

load_config() {
    local config_file="$CONFIGS_DIR/programs.yaml"
    
    # Validate config file exists
    if [ ! -f "$config_file" ]; then
        log_error "Programs configuration file not found: $config_file"
        return 1
    fi
    
    # Validate yq is available
    if ! command -v yq >/dev/null; then
        log_error "yq is required but not found. Cannot load configuration."
        return 1
    fi
    
    # 1. Native Packages
    while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && NATIVE_PACKAGES+=("$line"); done < <(yq -r '.pacman.packages[].name' "$config_file" 2>/dev/null || true)
    
    # 2. Essential
    local mode="${INSTALL_MODE:-default}"
    while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && NATIVE_PACKAGES+=("$line"); done < <(yq -r ".essential.$mode[].name" "$config_file" 2>/dev/null || true)
    
    # 3. Universal
    while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && UNIVERSAL_PACKAGES+=("$line"); done < <(yq -r ".aur.$mode[].name" "$config_file" 2>/dev/null || true)
    
    # 4. Desktop Environment (Native)
    if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
        local de_key=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
        if [[ "$de_key" == *"gnome"* ]]; then de_key="gnome"; fi
        if [[ "$de_key" == *"kde"* ]]; then de_key="kde"; fi
        if [[ "$de_key" == *"cosmic"* ]]; then de_key="cosmic"; fi
        
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && NATIVE_PACKAGES+=("$line"); done < <(yq -r ".desktop_environments.$de_key.install[]" "$config_file" 2>/dev/null || true)
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && FLATPAK_PACKAGES+=("$line"); done < <(yq -r ".flatpak.$de_key.$mode[].name" "$config_file" 2>/dev/null || true)
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && FLATPAK_PACKAGES+=("$line"); done < <(yq -r ".flatpak.generic.$mode[].name" "$config_file" 2>/dev/null || true)
    fi
}

# --- Main ---
if ! load_config; then
    log_error "Failed to load configuration. Exiting."
    exit 1
fi

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
