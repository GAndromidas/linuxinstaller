#!/bin/bash
set -uo pipefail

# Get the directory where this script is located, resolving symlinks
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ARCHINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$ARCHINSTALLER_ROOT/configs"

source "$SCRIPT_DIR/common.sh"

export SUDO_ASKPASS= # Force sudo to prompt in terminal, not via GUI

# ===== Globals =====
PROGRAMS_ERRORS=()
PROGRAMS_INSTALLED=()
PROGRAMS_REMOVED=()
pacman_programs=()           # Holds base pacman packages for all modes
essential_programs=()        # Holds final list of pacman packages to install
yay_programs=()              # Holds final list of AUR packages to install
flatpak_programs=()          # Holds final list of flatpak packages to install
specific_install_programs=() # DE-specific installs
specific_remove_programs=() # DE-specific removals

# ===== YAML Parsing Functions =====

# Function to check if yq is available, install if not
ensure_yq() {
	if ! command -v yq &>/dev/null; then
		ui_info "yq is required for YAML parsing. Installing..."
		pacman_install "yq"
		if ! command -v yq &>/dev/null; then
			log_error "Failed to install yq. Please install it manually: sudo pacman -S yq"
			return 1
		fi
	fi
	return 0
}

# Function to read packages from YAML with descriptions
read_yaml_packages() {
	local yaml_file="$1"
	local yaml_path="$2"
	local -n packages_array="$3"
	local -n descriptions_array="$4"

	packages_array=()
	descriptions_array=()

	local yq_output
	yq_output=$(yq -r "$yaml_path[] | [.name, .description] | @tsv" "$yaml_file" 2>/dev/null)

	if [[ $? -eq 0 && -n "$yq_output" ]]; then
		while IFS=$'\t' read -r name description; do
			[[ -z "$name" ]] && continue
			packages_array+=("$name")
			descriptions_array+=("$description")
		done <<<"$yq_output"
	fi
}

# Function to read simple package lists (without descriptions)
read_yaml_simple_packages() {
	local yaml_file="$1"
	local yaml_path="$2"
	local -n packages_array="$3"

	packages_array=()

	local yq_output
	yq_output=$(yq -r "$yaml_path[]" "$yaml_file" 2>/dev/null)

	if [[ $? -eq 0 && -n "$yq_output" ]]; then
		while IFS= read -r package; do
			[[ -z "$package" ]] && continue
			packages_array+=("$package")
		done <<<"$yq_output"
	fi
}

# ===== Load All Package Lists from YAML =====

load_package_lists_from_yaml() {
	PROGRAMS_YAML="$CONFIGS_DIR/programs.yaml"
	if [[ ! -f "$PROGRAMS_YAML" ]]; then
		log_error "Programs configuration file not found: $PROGRAMS_YAML"
		return 1
	fi

	if ! ensure_yq; then
		return 1
	fi

	# Read base and mode-specific package lists
	read_yaml_packages "$PROGRAMS_YAML" ".pacman.packages" pacman_programs pacman_descriptions
	read_yaml_packages "$PROGRAMS_YAML" ".essential.default" essential_programs_default essential_descriptions_default
	read_yaml_packages "$PROGRAMS_YAML" ".essential.minimal" essential_programs_minimal essential_descriptions_minimal
	read_yaml_packages "$PROGRAMS_YAML" ".aur.default" yay_programs_default yay_descriptions_default
	read_yaml_packages "$PROGRAMS_YAML" ".aur.minimal" yay_programs_minimal yay_descriptions_minimal

	# Read desktop environment specific packages
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.kde.install" kde_install_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.kde.remove" kde_remove_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.gnome.install" gnome_install_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.gnome.remove" gnome_remove_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.cosmic.install" cosmic_install_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.cosmic.remove" cosmic_remove_programs

	# Read custom selectable package lists
	read_yaml_packages "$PROGRAMS_YAML" ".custom.essential" custom_selectable_essential_programs custom_selectable_essential_descriptions
	read_yaml_packages "$PROGRAMS_YAML" ".custom.aur" custom_selectable_yay_programs custom_selectable_yay_descriptions
}

# ===== Custom Selection Functions =====

show_checklist() {
	local title="$1"
	shift
	local whiptail_choices=("$@")

	local gum_options=()
	for ((i = 0; i < ${#whiptail_choices[@]}; i += 3)); do
		local display_description="${whiptail_choices[i + 1]}"
		gum_options+=("$display_description")
	done

	local selected_output
	selected_output=$(printf "%s\\n" "${gum_options[@]}" | gum filter \
		--no-limit \
		--height 15 \
		--placeholder "Filter packages..." \
		--prompt "Use space to select, enter to confirm:" \
		--header "$title")

	local status=$?
	if [[ $status -ne 0 ]]; then
		# User cancelled, return empty string
		echo ""
		return
	fi

	local final_selected_pkgs=()
	while IFS= read -r line; do
		if [[ -n "$line" ]]; then
			local pkg_from_display
			pkg_from_display=$(echo "$line" | cut -d' ' -f1)
			final_selected_pkgs+=("$pkg_from_display")
		fi
	done <<<"$selected_output"

	printf "%s\\n" "${final_selected_pkgs[@]}"
}

custom_essential_selection() {
	local all_selectable_pkgs=("${custom_selectable_essential_programs[@]}")
	local selectable_descriptions=("${custom_selectable_essential_descriptions[@]}")

	local choices=()
	for i in "${!all_selectable_pkgs[@]}"; do
		local pkg="${all_selectable_pkgs[$i]}"
		[[ -z "$pkg" ]] && continue
		local description="${selectable_descriptions[$i]}"
		local display_text="$pkg - $description"
		choices+=("$pkg" "$display_text" "off")
	done

	if [[ ${#choices[@]} -eq 0 ]]; then return; fi

	local selected
	selected=$(show_checklist "Select additional essential packages:" "${choices[@]}")

	while IFS= read -r pkg; do
		if [[ -n "$pkg" && ! " ${essential_programs[*]} " =~ " $pkg " ]]; then
			essential_programs+=("$pkg")
		fi
	done <<<"$selected"
}

custom_aur_selection() {
	local all_selectable_pkgs=("${custom_selectable_yay_programs[@]}")
	local selectable_descriptions=("${custom_selectable_yay_descriptions[@]}")

	local choices=()
	for i in "${!all_selectable_pkgs[@]}"; do
		local pkg="${all_selectable_pkgs[$i]}"
		[[ -z "$pkg" ]] && continue
		local description="${selectable_descriptions[$i]}"
		local display_text="$pkg - $description"
		choices+=("$pkg" "$display_text" "off")
	done

	if [[ ${#choices[@]} -eq 0 ]]; then return; fi

	local selected
	selected=$(show_checklist "Select AUR packages:" "${choices[@]}")

	while IFS= read -r pkg; do
		if [[ -n "$pkg" && ! " ${yay_programs[*]} " =~ " $pkg " ]]; then
			yay_programs+=("$pkg")
		fi
	done <<<"$selected"
}

custom_flatpak_selection() {
	local de_lower
	de_lower=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
	[[ -z "$de_lower" ]] && de_lower="generic"

	# Load custom Flatpak programs specific to the detected DE
	local de_flatpak_names=()
	local de_flatpak_descriptions=()
	read_yaml_packages "$PROGRAMS_YAML" ".custom.flatpak.$de_lower" de_flatpak_names de_flatpak_descriptions

	local choices=()
	for i in "${!de_flatpak_names[@]}"; do
		local pkg="${de_flatpak_names[$i]}"
		[[ -z "$pkg" ]] && continue
		local description="${de_flatpak_descriptions[$i]}"
		local display_text="$pkg - $description"
		choices+=("$pkg" "$display_text" "off")
	done

	if [[ ${#choices[@]} -eq 0 ]]; then return; fi

	local selected
	selected=$(show_checklist "Select Flatpak applications:" "${choices[@]}")

	while IFS= read -r pkg; do
		if [[ -n "$pkg" && ! " ${flatpak_programs[*]} " =~ " $pkg " ]]; then
			flatpak_programs+=("$pkg")
		fi
	done <<<"$selected"
}

# ===== Package List Determination =====

determine_package_lists() {
	ui_info "Determining package lists for '$INSTALL_MODE' mode..."

	# All modes start with the base pacman packages
	essential_programs=("${pacman_programs[@]}")

	case "$INSTALL_MODE" in
	"Standard")
		essential_programs+=("${essential_programs_default[@]}")
		yay_programs=("${yay_programs_default[@]}")
		# Add flatpak logic for standard mode if needed
		;;
	"Minimal")
		essential_programs+=("${essential_programs_minimal[@]}")
		yay_programs=("${yay_programs_minimal[@]}")
		# Add flatpak logic for minimal mode if needed
		;;
	"Custom")
        ui_info "Presenting menus for additional package selection..."
		custom_essential_selection
		custom_aur_selection
		custom_flatpak_selection
		;;
	*)
		log_error "Unknown installation mode: $INSTALL_MODE"
		return 1
		;;
	esac
}

handle_de_packages() {
	local de
	de=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')

	case "$de" in
	kde)
		specific_install_programs=("${kde_install_programs[@]}")
		specific_remove_programs=("${kde_remove_programs[@]}")
		;;
	gnome)
		specific_install_programs=("${gnome_install_programs[@]}")
		specific_remove_programs=("${gnome_remove_programs[@]}")
		;;
	cosmic)
		specific_install_programs=("${cosmic_install_programs[@]}")
		specific_remove_programs=("${cosmic_remove_programs[@]}")
		;;
	*)
		ui_warn "No specific package list for Desktop Environment: $XDG_CURRENT_DESKTOP"
		return
		;;
	esac

	if [[ ${#specific_install_programs[@]} -gt 0 ]]; then
		ui_info "Adding DE-specific packages for $de..."
		essential_programs+=("${specific_install_programs[@]}")
	fi
}

# ===== Installation Functions =====

install_pacman_packages() {
	local packages_to_install=("$@")
	if [[ ${#packages_to_install[@]} -eq 0 ]]; then
		ui_info "No pacman packages to install."
		return
	fi

	ui_info "Installing ${#packages_to_install[@]} pacman packages..."
	for pkg in "${packages_to_install[@]}"; do
		if pacman_install "$pkg"; then
			PROGRAMS_INSTALLED+=("$pkg")
		else
			PROGRAMS_ERRORS+=("$pkg (pacman)")
		fi
	done
}

install_aur_packages() {
	if ! command -v yay >/dev/null; then
		ui_warn "yay is not installed. Skipping AUR packages."
		return
	fi

	local packages_to_install=("$@")
	if [[ ${#packages_to_install[@]} -eq 0 ]]; then
		ui_info "No AUR packages to install."
		return
	fi

	ui_info "Installing ${#packages_to_install[@]} AUR packages with yay..."
	for pkg in "${packages_to_install[@]}"; do
		if yay_install "$pkg"; then
			PROGRAMS_INSTALLED+=("$pkg (AUR)")
		else
			PROGRAMS_ERRORS+=("$pkg (AUR)")
		fi
	done
}

install_flatpak_packages() {
	if ! command -v flatpak >/dev/null; then
		ui_warn "flatpak is not installed. Skipping Flatpak packages."
		return
	fi

	if ! flatpak remote-list | grep -q flathub; then
		step "Adding Flathub remote"
		flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	fi

	local packages_to_install=("$@")
	if [[ ${#packages_to_install[@]} -eq 0 ]]; then
		ui_info "No Flatpak applications to install."
		return
	fi

	ui_info "Installing ${#packages_to_install[@]} Flatpak applications..."
	for pkg in "${packages_to_install[@]}"; do
		if flatpak_install "$pkg"; then
			PROGRAMS_INSTALLED+=("$pkg (Flatpak)")
		else
			PROGRAMS_ERRORS+=("$pkg (Flatpak)")
		fi
	done
}

remove_pacman_packages() {
	local packages_to_remove=("$@")
	if [[ ${#packages_to_remove[@]} -eq 0 ]]; then
		return
	fi

	ui_info "Removing ${#packages_to_remove[@]} conflicting/unnecessary packages..."
	for pkg in "${packages_to_remove[@]}"; do
		if pacman_remove "$pkg"; then
			PROGRAMS_REMOVED+=("$pkg")
		else
			PROGRAMS_ERRORS+=("$pkg (removal)")
		fi
	done
}

print_programs_summary() {
	echo ""
	ui_header "Programs Installation Summary"
	if [[ ${#PROGRAMS_INSTALLED[@]} -gt 0 ]]; then
		echo -e "${GREEN}Installed:${RESET}"
		printf "  - %s\n" "${PROGRAMS_INSTALLED[@]}"
	fi
	if [[ ${#PROGRAMS_REMOVED[@]} -gt 0 ]]; then
		echo -e "${YELLOW}Removed:${RESET}"
		printf "  - %s\n" "${PROGRAMS_REMOVED[@]}"
	fi
	if [[ ${#PROGRAMS_ERRORS[@]} -gt 0 ]]; then
		echo -e "${RED}Errors:${RESET}"
		printf "  - %s\n" "${PROGRAMS_ERRORS[@]}"
	fi
	echo ""
}

# ===== Main Execution =====

main() {
	# 1. Load all package definitions from the YAML file
	load_package_lists_from_yaml

	# 2. Determine which packages to install based on the mode
	determine_package_lists

	# 3. Add DE-specific packages
	handle_de_packages

	# 4. Install Pacman packages
	install_pacman_packages "${essential_programs[@]}"

	# 5. Install AUR packages
	install_aur_packages "${yay_programs[@]}"

	# 6. Install Flatpak packages
	install_flatpak_packages "${flatpak_programs[@]}"

	# 7. Remove any conflicting packages
	remove_pacman_packages "${specific_remove_programs[@]}"

	ui_success "Program installation phase completed."
}

# Execute main function
main
