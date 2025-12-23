#!/bin/bash
set -uo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LINUXINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$LINUXINSTALLER_ROOT/configs"
PROGRAMS_FILE="$CONFIGS_DIR/programs.yaml"

source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

# Source programs.sh for installation functions
if [ -f "$SCRIPT_DIR/programs.sh" ]; then
    source "$SCRIPT_DIR/programs.sh"
fi

# Gaming packages installation using new structure
install_gaming_packages() {
    if [ ! -f "$PROGRAMS_FILE" ] || ! command -v yq >/dev/null; then
        log_warning "Cannot read gaming packages configuration"
        return 1
    fi

    step "Installing gaming packages"

    # Read gaming packages for current distro
    local gaming_native=()
    mapfile -t gaming_native < <(yq -r ".gaming.${DISTRO_ID}.native[]?" "$PROGRAMS_FILE" 2>/dev/null || echo "")

    if [ ${#gaming_native[@]} -gt 0 ]; then
        install_packages_quietly "${gaming_native[@]}"
    fi

    # Install AUR gaming packages (Arch only)
    if [ "$DISTRO_ID" == "arch" ]; then
        local gaming_aur=()
        mapfile -t gaming_aur < <(yq -r ".gaming.${DISTRO_ID}.aur[]?" "$PROGRAMS_FILE" 2>/dev/null || echo "")
        if [ ${#gaming_aur[@]} -gt 0 ]; then
            install_aur_packages "${gaming_aur[@]}"
        fi
    fi

    # Install Flatpak gaming packages
    local gaming_flatpak=()
    mapfile -t gaming_flatpak < <(yq -r ".gaming.${DISTRO_ID}.flatpak[]?" "$PROGRAMS_FILE" 2>/dev/null || echo "")
    if [ ${#gaming_flatpak[@]} -gt 0 ]; then
        install_flatpak_packages "${gaming_flatpak[@]}"
    fi

    # Install Snap gaming packages (Ubuntu only)
    if [ "$DISTRO_ID" == "ubuntu" ]; then
        local gaming_snap=()
        mapfile -t gaming_snap < <(yq -r ".gaming.${DISTRO_ID}.snap[]?" "$PROGRAMS_FILE" 2>/dev/null || echo "")
        if [ ${#gaming_snap[@]} -gt 0 ]; then
            install_snap_packages "${gaming_snap[@]}"
        fi
    fi

    log_success "Gaming packages installation completed"
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

    # Main execution
    install_gaming_packages
    configure_mangohud
    enable_gamemode

    ui_success "Gaming Mode Configured."
}

main
