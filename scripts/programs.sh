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

    local resolved_packages=()
    for pkg in "${packages[@]}"; do
        local target
        target=$(resolve_native "$pkg")
        if [ -n "$target" ]; then
            # target might contain multiple space-separated packages
            for sub_pkg in $target; do
                [ -n "$sub_pkg" ] && resolved_packages+=("$sub_pkg")
            done
        fi
    done

    if [ ${#resolved_packages[@]} -gt 0 ]; then
        # Use common.sh optimized batch installer
        install_packages_quietly "${resolved_packages[@]}"
    else
        ui_info "No native packages to install."
    fi
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

        # Check if Flatpak version exists (prefer for packages that might hang in AUR)
        local flatpak_id=$(resolve_universal "$clean_name" "flatpak")
        local snap_id=$(resolve_universal "$clean_name" "snap")

        # For packages with Flatpak versions, prefer Flatpak on Arch to avoid AUR build hangs
        # This is especially important for rustdesk-bin which can hang during AUR builds
        if [ "$DISTRO_ID" == "arch" ] && [ -n "$flatpak_id" ] && [ "$flatpak_id" != "null" ] && command -v flatpak >/dev/null 2>&1; then
            if flatpak install -y flathub "$flatpak_id" >> "$INSTALL_LOG" 2>&1; then
                ui_success "$display_name (Flatpak)"
                installed=true
            fi
        fi

        # 1. Try Native/AUR (if Flatpak didn't work or isn't available)
        if [ "$installed" == "false" ]; then
            if [ "$DISTRO_ID" == "arch" ] && command -v yay >/dev/null 2>&1; then
             # Arch: Use yay (handles Repo + AUR)
                 local install_log="${INSTALL_LOG:-$HOME/.linuxinstaller.log}"
                 if timeout 600 yay -S --noconfirm --needed --batchinstall --provides "$native_target" >> "$install_log" 2>&1; then
                     ui_success "$display_name (Native/AUR)"
                     installed=true
                 fi
            elif [ -n "${PKG_INSTALL:-}" ]; then
             # Non-Arch: Try native package manager
                 if $PKG_INSTALL ${PKG_NOCONFIRM:-} "$native_target" >> "$INSTALL_LOG" 2>&1; then
                     ui_success "$display_name (Native)"
                     installed=true
                 fi
             fi
        fi

        # 2. Universal Fallback (only if native failed)
        if [ "$installed" == "false" ]; then
            # Heuristics
            [ -z "$snap_id" ] && snap_id="$clean_name"
            [ -z "$flatpak_id" ] && flatpak_id="$clean_name"

            # Helper to try install
            try_install_universal() {
                local type="$1"
                local id="$2"
                if [ "$type" == "snap" ] && [ -n "$id" ]; then
                     sudo snap install "$id" >> "$INSTALL_LOG" 2>&1 && return 0
                elif [ "$type" == "flatpak" ] && [ -n "$id" ]; then
                     flatpak install -y flathub "$id" >> "$INSTALL_LOG" 2>&1 && return 0
                fi
                return 1
            }

            # Priority Logic
            if try_install_universal "$PRIMARY_UNIVERSAL_PKG" "$( [ "$PRIMARY_UNIVERSAL_PKG" == "snap" ] && echo "$snap_id" || echo "$flatpak_id" )"; then
                ui_success "$display_name ($PRIMARY_UNIVERSAL_PKG)"
                installed=true
            # Backup Logic
            elif try_install_universal "$BACKUP_UNIVERSAL_PKG" "$( [ "$BACKUP_UNIVERSAL_PKG" == "snap" ] && echo "$snap_id" || echo "$flatpak_id" )"; then
                 ui_success "$display_name ($BACKUP_UNIVERSAL_PKG)"
                 installed=true
            fi
        fi

        if [ "$installed" == "false" ]; then
            ui_error "$display_name (Failed)"
        fi
    done
}

flatpak_install_list() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then return; fi

    # Skip Flatpak on Ubuntu if not installed (Snap-only preference)
    if [ "$DISTRO_ID" == "ubuntu" ] && ! command -v flatpak >/dev/null 2>&1; then
        return
    fi

    step "Installing Flatpak Apps"

    if command -v install_flatpak_quietly >/dev/null; then
        # Use common.sh optimized batch installer if available
        install_flatpak_quietly "${packages[@]}"
    else
        # Fallback batch implementation
        local pkg_list="${packages[*]}"
        local title="Installing ${#packages[@]} Flatpak apps..."

        if ! command -v flatpak >/dev/null; then ui_error "Flatpak not found"; return; fi

        if command -v gum >/dev/null 2>&1; then
            if gum spin --spinner dot --title "$title" --show-output -- flatpak install -y flathub $pkg_list >> "$INSTALL_LOG" 2>&1; then
                 ui_success "$title Done."
            else
                 ui_error "Failed to install some Flatpak apps."
            fi
        else
            ui_info "$title"
            if flatpak install -y flathub $pkg_list >> "$INSTALL_LOG" 2>&1; then
                 ui_success "Done."
            else
                 ui_error "Failed."
            fi
        fi
    fi
}

# --- Load Config ---
NATIVE_PACKAGES=()
UNIVERSAL_PACKAGES=()
FLATPAK_PACKAGES=()
REMOVE_PACKAGES=()

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

    # 1. Native Packages (Always install base system utilities)
    while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && NATIVE_PACKAGES+=("$line"); done < <(yq -r '.pacman.packages[].name' "$config_file" 2>/dev/null || true)

    local mode="${INSTALL_MODE:-default}"

    if [[ "$mode" == "custom" ]]; then
        if command -v gum >/dev/null; then
            ui_info "Entering interactive package selection..."

            # Essential (Native)
            local options_essential=()
            while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && options_essential+=("$line"); done < <(yq -r '.custom.essential[] | "\(.name) | \(.description)"' "$config_file" 2>/dev/null || true)

            if [ ${#options_essential[@]} -gt 0 ]; then
                 local selected
                 selected=$(gum choose --no-limit --height 15 --header "Select Essential Packages" "${options_essential[@]}")
                 if [ -n "$selected" ]; then
                    while IFS= read -r item; do
                        local pkg_name="${item%% | *}"
                        [ -n "$pkg_name" ] && NATIVE_PACKAGES+=("$pkg_name")
                    done <<< "$selected"
                 fi
            fi

            # AUR / Universal
            local options_aur=()
            while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && options_aur+=("$line"); done < <(yq -r '.custom.aur[] | "\(.name) | \(.description)"' "$config_file" 2>/dev/null || true)

            if [ ${#options_aur[@]} -gt 0 ]; then
                 local selected
                 selected=$(gum choose --no-limit --height 15 --header "Select Universal/AUR Packages" "${options_aur[@]}")
                 if [ -n "$selected" ]; then
                    while IFS= read -r item; do
                        local pkg_name="${item%% | *}"
                        [ -n "$pkg_name" ] && UNIVERSAL_PACKAGES+=("$pkg_name")
                    done <<< "$selected"
                 fi
            fi

            # Flatpak (Desktop Environment Specific)
            if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
                local de_key=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
                if [[ "$de_key" == *"gnome"* ]]; then de_key="gnome"; fi
                if [[ "$de_key" == *"kde"* ]]; then de_key="kde"; fi
                if [[ "$de_key" == *"cosmic"* ]]; then de_key="cosmic"; fi

                local options_flatpak=()
                while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && options_flatpak+=("$line"); done < <(yq -r ".custom.flatpak.$de_key[] | \"\(.name) | \(.description)\"" "$config_file" 2>/dev/null || true)

                if [ ${#options_flatpak[@]} -gt 0 ]; then
                    local selected
                    selected=$(gum choose --no-limit --height 15 --header "Select Flatpak Apps ($de_key)" "${options_flatpak[@]}")
                    if [ -n "$selected" ]; then
                        while IFS= read -r item; do
                            local pkg_name="${item%% | *}"
                            [ -n "$pkg_name" ] && FLATPAK_PACKAGES+=("$pkg_name")
                        done <<< "$selected"
                    fi
                fi
            fi
        else
            log_warning "Gum not found, skipping interactive selection in custom mode."
        fi
    else
        # 2. Essential
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && NATIVE_PACKAGES+=("$line"); done < <(yq -r ".essential.$mode[].name" "$config_file" 2>/dev/null || true)

        # 3. Universal
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && UNIVERSAL_PACKAGES+=("$line"); done < <(yq -r ".aur.$mode[].name" "$config_file" 2>/dev/null || true)
    fi

    # 4. Desktop Environment (Native)
    if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
        local de_key=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
        if [[ "$de_key" == *"gnome"* ]]; then de_key="gnome"; fi
        if [[ "$de_key" == *"kde"* ]]; then de_key="kde"; fi
        if [[ "$de_key" == *"cosmic"* ]]; then de_key="cosmic"; fi

        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && NATIVE_PACKAGES+=("$line"); done < <(yq -r ".desktop_environments.$de_key.install[]" "$config_file" 2>/dev/null || true)
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && REMOVE_PACKAGES+=("$line"); done < <(yq -r ".desktop_environments.$de_key.remove[]" "$config_file" 2>/dev/null || true)
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && FLATPAK_PACKAGES+=("$line"); done < <(yq -r ".flatpak.$de_key.$mode[].name" "$config_file" 2>/dev/null || true)
        while IFS= read -r line; do [[ -n "$line" && "$line" != "null" ]] && FLATPAK_PACKAGES+=("$line"); done < <(yq -r ".flatpak.generic.$mode[].name" "$config_file" 2>/dev/null || true)
    fi
}

# --- Remove Packages ---
remove_packages() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then return; fi

    step "Removing Unnecessary Packages"

    local to_remove=()
    for pkg in "${packages[@]}"; do
        local target="$pkg"
        local is_installed=false

        if [ "$DISTRO_ID" == "arch" ] && command -v pacman >/dev/null 2>&1; then
            pacman -Q "$target" >/dev/null 2>&1 && is_installed=true
        elif [ "$DISTRO_ID" == "fedora" ] && command -v rpm >/dev/null 2>&1; then
            rpm -q "$target" >/dev/null 2>&1 && is_installed=true
        elif [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
            if command -v dpkg >/dev/null 2>&1; then
                dpkg -l | grep -q "^ii.*$target" && is_installed=true
            fi
        fi

        if [ "$is_installed" = true ]; then
            to_remove+=("$target")
        fi
    done

    if [ ${#to_remove[@]} -gt 0 ]; then
        local count=${#to_remove[@]}
        local pkg_list="${to_remove[*]}"
        local title="Removing $count packages..."

        if [ -n "${PKG_REMOVE:-}" ]; then
            local remove_cmd="$PKG_REMOVE ${PKG_NOCONFIRM:-} $pkg_list"

            if command -v gum >/dev/null 2>&1; then
                if gum spin --spinner dot --title "$title" --show-output -- sh -c "$remove_cmd" >> "$INSTALL_LOG" 2>&1; then
                     ui_success "Removed $count packages."
                else
                     ui_warn "Failed to remove some packages."
                fi
            else
                ui_info "$title"
                if eval "$remove_cmd" >> "$INSTALL_LOG" 2>&1; then
                     ui_success "Removed."
                else
                     ui_warn "Failed to remove some packages."
                fi
            fi
        else
            ui_warn "PKG_REMOVE not defined, skipping removal."
        fi
    else
        ui_info "No unnecessary packages found."
    fi
}

# --- Main ---
if ! load_config; then
    log_error "Failed to load configuration. Exiting."
    exit 1
fi

# Remove packages first (before installing new ones)
remove_packages "${REMOVE_PACKAGES[@]}"

# Then install packages
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
