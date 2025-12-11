#!/bin/bash
set -uo pipefail

# Gaming and performance tweaks installation for Arch Linux
# Get the directory where this script is located, resolving symlinks
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ARCHINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$ARCHINSTALLER_ROOT/configs"
GAMING_YAML="$CONFIGS_DIR/gaming_mode.yaml"

source "$SCRIPT_DIR/common.sh"

# ===== Globals =====
pacman_gaming_programs=()
flatpak_gaming_programs=()

# ===== YAML Parsing Functions =====

ensure_yq() {
	if ! command -v yq &>/dev/null; then
		ui_info "yq is required for YAML parsing. Installing..."
		if ! install_packages_quietly "yq"; then
			log_error "Failed to install yq. Please install it manually: sudo pacman -S yq"
			return 1
		fi
	fi
	return 0
}

read_yaml_packages() {
	local yaml_file="$1"
	local yaml_path="$2"
	local -n packages_array="$3"

	packages_array=()

	local yq_output
	yq_output=$(yq -r "$yaml_path[] | [.name] | @tsv" "$yaml_file" 2>/dev/null)

	if [[ $? -eq 0 && -n "$yq_output" ]]; then
		while IFS=$'\t' read -r name; do
			[[ -z "$name" ]] && continue
			packages_array+=("$name")
		done <<<"$yq_output"
	fi
}

# ===== Load All Package Lists from YAML =====
load_package_lists() {
	if [[ ! -f "$GAMING_YAML" ]]; then
		log_error "Gaming mode configuration file not found: $GAMING_YAML"
		return 1
	fi

	if ! ensure_yq; then
		return 1
	fi

	read_yaml_packages "$GAMING_YAML" ".pacman.packages" pacman_gaming_programs
	read_yaml_packages "$GAMING_YAML" ".flatpak.apps" flatpak_gaming_programs
	return 0
}

# ===== Installation Functions =====
install_gaming_pacman_packages() {
	if [[ ${#pacman_gaming_programs[@]} -eq 0 ]]; then
		ui_info "No pacman packages for gaming mode to install."
		return
	fi
	ui_info "Installing ${#pacman_gaming_programs[@]} pacman packages for gaming..."

    # leverage common.sh optimized batch installer
    install_packages_quietly "${pacman_gaming_programs[@]}"
}

install_gaming_flatpak_packages() {
	if ! command -v flatpak >/dev/null; then ui_warn "flatpak is not installed. Skipping gaming Flatpaks."; return; fi

	# Ensure flathub remote exists (system-wide)
	if ! flatpak remote-list | grep -q flathub; then
		step "Adding Flathub remote"
		flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	fi

	if [[ ${#flatpak_gaming_programs[@]} -eq 0 ]]; then
		ui_info "No Flatpak applications for gaming mode to install."
		return
	fi
	ui_info "Installing ${#flatpak_gaming_programs[@]} Flatpak applications for gaming..."

    # leverage common.sh optimized batch installer (if supported by flatpak installer in common.sh)
    install_flatpak_quietly "${flatpak_gaming_programs[@]}"
}

# ===== Configuration Functions =====
configure_mangohud() {
	step "Configuring MangoHud"
	local mangohud_config_dir="$HOME/.config/MangoHud"
	local mangohud_config_source="$CONFIGS_DIR/MangoHud.conf"

	mkdir -p "$mangohud_config_dir"

	if [ -f "$mangohud_config_source" ]; then
		cp "$mangohud_config_source" "$mangohud_config_dir/MangoHud.conf"
		log_success "MangoHud configuration copied successfully."
	else
		log_warning "MangoHud configuration file not found at $mangohud_config_source"
	fi
}

enable_gamemode() {
	step "Enabling GameMode service"
	# GameMode is a user service
	if systemctl --user daemon-reload &>/dev/null && systemctl --user enable --now gamemoded &>/dev/null; then
		log_success "GameMode service enabled and started successfully."
	else
		log_warning "Failed to enable or start GameMode service. It may require manual configuration."
	fi
}

# ===== Main Execution =====
main() {
	step "Gaming Mode Setup"
	figlet_banner "Gaming Mode"

	local description="This includes popular tools like Discord, Steam, Wine, GameMode, MangoHud, Goverlay, Heroic Games Launcher, and more."
	if ! gum_confirm "Enable Gaming Mode?" "$description"; then
		ui_info "Gaming Mode skipped."
		return 0
	fi

	if ! load_package_lists; then
		return 1
	fi

	# Crucial: Ensure multilib is actually working before attempting to install steam/wine
    # This function is now in common.sh
	check_and_enable_multilib

	install_gaming_pacman_packages
	install_gaming_flatpak_packages
	configure_mangohud
	enable_gamemode
	ui_success "Gaming Mode setup completed."
}

main
