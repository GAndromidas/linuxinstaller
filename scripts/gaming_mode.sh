#!/bin/bash
set -uo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LINUXINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$LINUXINSTALLER_ROOT/configs"
GAMING_YAML="$CONFIGS_DIR/gaming_mode.yaml"

source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

# Globals
pacman_gaming_programs=()
flatpak_gaming_programs=()
GAMING_INSTALLED=()
GAMING_ERRORS=()

# Load Lists
load_package_lists() {
    if [[ ! -f "$GAMING_YAML" ]]; then return 1; fi
    if ! command -v yq >/dev/null; then return 1; fi

    # Read into arrays
    mapfile -t pacman_gaming_programs < <(yq -r '.pacman.packages[].name' "$GAMING_YAML")
    mapfile -t flatpak_gaming_programs < <(yq -r '.flatpak.apps[].name' "$GAMING_YAML")
}

install_gaming_native() {
    if [[ ${#pacman_gaming_programs[@]} -eq 0 ]]; then return; fi
    ui_info "Installing Native Gaming Packages..."

    # Use smart installer which resolves names via package_map.yaml
    install_packages_quietly "${pacman_gaming_programs[@]}"

    # Note: install_packages_quietly suppresses output but logs to file.
    # We assume success if no critical error, tracking individual success is complex in batch.
    GAMING_INSTALLED+=("${pacman_gaming_programs[@]}")
}

install_gaming_flatpak() {
    if [[ ${#flatpak_gaming_programs[@]} -eq 0 ]]; then return; fi

    if ! command -v flatpak >/dev/null; then
        ui_warn "Flatpak not found. Skipping."
        return
    fi

    ui_info "Installing Flatpak Gaming Apps..."

    # Use optimized batch installation if available
    if command -v install_flatpak_quietly >/dev/null; then
        install_flatpak_quietly "${flatpak_gaming_programs[@]}"
        GAMING_INSTALLED+=("${flatpak_gaming_programs[@]}")
    else
        # Fallback manual batch install with Gum UI
        local pkg_list="${flatpak_gaming_programs[*]}"
        local title="Installing ${#flatpak_gaming_programs[@]} Flatpak gaming apps..."

        if command -v gum >/dev/null 2>&1; then
            if gum spin --spinner dot --title "$title" --show-output -- flatpak install -y flathub $pkg_list >> "$INSTALL_LOG" 2>&1; then
                ui_success "$title Done."
                GAMING_INSTALLED+=("${flatpak_gaming_programs[@]}")
            else
                ui_error "Failed to install some Flatpak gaming apps."
            fi
        else
            ui_info "$title"
            if flatpak install -y flathub $pkg_list >> "$INSTALL_LOG" 2>&1; then
                ui_success "Done."
                GAMING_INSTALLED+=("${flatpak_gaming_programs[@]}")
            else
                ui_error "Failed."
            fi
        fi
    fi
}

configure_mangohud() {
	local src="$CONFIGS_DIR/MangoHud.conf"
	local dest="$HOME/.config/MangoHud/MangoHud.conf"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
    fi
}

enable_gamemode() {
    # User service
    systemctl --user daemon-reload >/dev/null 2>&1
    systemctl --user enable --now gamemoded >/dev/null 2>&1
}

main() {
    step "Gaming Mode Setup"

    local description="Tools: Steam, Lutris, GameMode, MangoHud, etc."
    if ! gum_confirm "Enable Gaming Mode?" "$description"; then
        ui_info "Skipped."
        return 0
    fi

    load_package_lists
    install_gaming_native
    install_gaming_flatpak
    configure_mangohud
    enable_gamemode

    ui_success "Gaming Mode Configured."
}

main
