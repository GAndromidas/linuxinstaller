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
essential_programs_server=() # Holds server-specific pacman packages
yay_programs=()              # Holds final list of AUR packages to install
flatpak_programs=()          # Holds final list of flatpak packages to install
specific_install_programs=() # DE-specific installs
specific_remove_programs=() # DE-specific removals

# ===== Local Helper Functions =====

pacman_install() {
	local pkg="$1"
	printf "${CYAN}Installing Pacman package:${RESET} %-30s" "$pkg"
	if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
		printf "${GREEN} ✓ Success${RESET}\n"
		return 0
	else
		printf "${RED} ✗ Failed${RESET}\n"
		return 1
	fi
}

yay_install() {
	local pkg="$1"
	printf "${CYAN}Installing AUR package:${RESET} %-30s" "$pkg"
	if yay -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
		printf "${GREEN} ✓ Success${RESET}\n"
		return 0
	else
		printf "${RED} ✗ Failed${RESET}\n"
		return 1
	fi
}

flatpak_install() {
	local pkg="$1"
	printf "${CYAN}Installing Flatpak app:${RESET} %-30s" "$pkg"
	if flatpak install -y --noninteractive flathub "$pkg" >/dev/null 2>&1; then
		printf "${GREEN} ✓ Success${RESET}\n"
		return 0
	else
		printf "${RED} ✗ Failed${RESET}\n"
		return 1
	fi
}

pacman_remove() {
	local pkg="$1"
	printf "${YELLOW}Removing Pacman package:${RESET} %-30s" "$pkg"
	if sudo pacman -Rns --noconfirm "$pkg" >/dev/null 2>&1; then
		printf "${GREEN} ✓ Success${RESET}\n"
		return 0
	else
		printf "${RED} ✗ Failed${RESET}\n"
		return 1
	fi
}

# ===== YAML Parsing Functions =====

ensure_yq() {
	if ! command -v yq &>/dev/null; then
		log_error "yq is required but not installed. Please install 'yq'."
		return 1
	fi
	return 0
}

# Function: validate_programs_yaml
# Description: Validates YAML file structure and syntax
# Parameters: $1 - YAML file path
# Returns: 0 if valid, 1 if invalid
validate_programs_yaml() {
	local yaml_file="$1"

	if [ ! -f "$yaml_file" ]; then
		log_error "Programs YAML file not found: $yaml_file"
		return 1
	fi

	# Validate YAML syntax
	if ! yq '.' "$yaml_file" &>/dev/null; then
		log_error "Invalid YAML syntax in $yaml_file"
		return 1
	fi

	# Validate required sections exist
	local required_sections=("pacman" "essential")
	for section in "${required_sections[@]}"; do
		if ! yq ".$section" "$yaml_file" &>/dev/null; then
			log_error "Missing required section in YAML: $section"
			return 1
		fi
	done

	return 0
}

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

	if ! ensure_yq; then
		return 1
	fi

	if ! validate_programs_yaml "$PROGRAMS_YAML"; then
		return 1
	fi

	read_yaml_packages "$PROGRAMS_YAML" ".pacman.packages" pacman_programs pacman_descriptions
	read_yaml_packages "$PROGRAMS_YAML" ".essential.default" essential_programs_default essential_descriptions_default
	read_yaml_packages "$PROGRAMS_YAML" ".essential.minimal" essential_programs_minimal essential_descriptions_minimal
	read_yaml_packages "$PROGRAMS_YAML" ".essential.server" essential_programs_server essential_descriptions_server
	read_yaml_packages "$PROGRAMS_YAML" ".aur.default" yay_programs_default yay_descriptions_default
	read_yaml_packages "$PROGRAMS_YAML" ".aur.minimal" yay_programs_minimal yay_descriptions_minimal
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.kde.install" kde_install_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.kde.remove" kde_remove_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.gnome.install" gnome_install_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.gnome.remove" gnome_remove_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.cosmic.install" cosmic_install_programs
	read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.cosmic.remove" cosmic_remove_programs
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
		gum_options+=("${whiptail_choices[i + 1]}")
	done

	local selected_output
	selected_output=$(printf "%s\\n" "${gum_options[@]}" | gum filter \
		--no-limit \
		--height 15 \
		--placeholder "Filter packages..." \
		--prompt "Use space to select, enter to confirm:" \
		--header "$title")

	if [[ $? -ne 0 ]]; then
		echo ""
		return
	fi

	local final_selected_pkgs=()
	while IFS= read -r line; do
		if [[ -n "$line" ]]; then
			final_selected_pkgs+=("$(echo "$line" | cut -d' ' -f1)")
		fi
	done <<<"$selected_output"

	printf "%s\\n" "${final_selected_pkgs[@]}"
}

custom_essential_selection() {
	local choices=()
	for i in "${!custom_selectable_essential_programs[@]}"; do
		local pkg="${custom_selectable_essential_programs[$i]}"
		[[ -z "$pkg" ]] && continue
		choices+=("$pkg" "$pkg - ${custom_selectable_essential_descriptions[$i]}" "off")
	done

	if [[ ${#choices[@]} -eq 0 ]]; then return; fi
	local selected=$(show_checklist "Select additional essential packages:" "${choices[@]}")

	while IFS= read -r pkg; do
		if [[ -n "$pkg" && ! " ${essential_programs[*]} " =~ " $pkg " ]]; then
			essential_programs+=("$pkg")
		fi
	done <<<"$selected"
}

custom_aur_selection() {
	local choices=()
	for i in "${!custom_selectable_yay_programs[@]}"; do
		local pkg="${custom_selectable_yay_programs[$i]}"
		[[ -z "$pkg" ]] && continue
		choices+=("$pkg" "$pkg - ${custom_selectable_yay_descriptions[$i]}" "off")
	done

	if [[ ${#choices[@]} -eq 0 ]]; then return; fi
	local selected=$(show_checklist "Select AUR packages:" "${choices[@]}")

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

	local de_flatpak_names=()
	local de_flatpak_descriptions=()
	read_yaml_packages "$PROGRAMS_YAML" ".custom.flatpak.$de_lower" de_flatpak_names de_flatpak_descriptions

	local choices=()
	for i in "${!de_flatpak_names[@]}"; do
		local pkg="${de_flatpak_names[$i]}"
		[[ -z "$pkg" ]] && continue
		choices+=("$pkg" "$pkg - ${de_flatpak_descriptions[$i]}" "off")
	done

	if [[ ${#choices[@]} -eq 0 ]]; then return; fi
	local selected=$(show_checklist "Select Flatpak applications:" "${choices[@]}")

	while IFS= read -r pkg; do
		if [[ -n "$pkg" && ! " ${flatpak_programs[*]} " =~ " $pkg " ]]; then
			flatpak_programs+=("$pkg")
		fi
	done <<<"$selected"
}

# ===== Package List Determination =====

detect_logitech_devices() {
	if grep -qi "Logitech" /sys/bus/usb/devices/*/manufacturer 2>/dev/null; then
		ui_info "Logitech device detected. Adding 'solaar' to installation list."
		if [[ ! " ${essential_programs[*]} " =~ " solaar " ]]; then
			essential_programs+=("solaar")
		fi
	fi
}

determine_package_lists() {
	ui_info "Determining package lists for '$INSTALL_MODE' mode..."
	essential_programs=("${pacman_programs[@]}")

	case "$INSTALL_MODE" in
	"default")
		essential_programs+=("${essential_programs_default[@]}")
		yay_programs=("${yay_programs_default[@]}")
		detect_logitech_devices
		;;
	"minimal")
		essential_programs+=("${essential_programs_minimal[@]}")
		yay_programs=("${yay_programs_minimal[@]}")
		;;
	"server")
		essential_programs=("${essential_programs_server[@]}")
		# No AUR or Flatpak packages for server mode by default
		;;
	"custom")
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
	if [[ "$INSTALL_MODE" == "server" ]]; then
		ui_info "Server mode selected, skipping desktop environment packages."
		return
	fi

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

handle_flatpak_packages() {
	if [[ "$INSTALL_MODE" == "server" || "$INSTALL_MODE" == "custom" ]]; then
		return
	fi

	local de
	de=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
	[[ -z "$de" ]] && de="generic"

	local de_flatpaks=()
	local de_descriptions=()

	read_yaml_packages "$PROGRAMS_YAML" ".flatpak.$de.$INSTALL_MODE" de_flatpaks de_descriptions

	if [[ ${#de_flatpaks[@]} -eq 0 && "$de" != "generic" ]]; then
		read_yaml_packages "$PROGRAMS_YAML" ".flatpak.generic.$INSTALL_MODE" de_flatpaks de_descriptions
	fi

	if [[ ${#de_flatpaks[@]} -gt 0 ]]; then
		ui_info "Adding Flatpak packages for $de ($INSTALL_MODE)..."
		flatpak_programs+=("${de_flatpaks[@]}")
	fi
}

# ===== Server Configuration Functions =====
configure_server_applications() {
	ui_info "Configuring server applications..."

	# Configure Docker
	if command -v docker >/dev/null; then
		step "Configuring Docker"
		if sudo systemctl enable --now docker >/dev/null 2>&1; then
			log_success "Docker service enabled and started."
		else
			log_error "Failed to enable or start Docker service."
			PROGRAMS_ERRORS+=("Docker service setup")
		fi

		step "Adding user to the docker group"
		if sudo usermod -aG docker "$USER"; then
			log_success "User '$USER' added to the docker group. Please log out and back in to apply changes."
		else
			log_error "Failed to add user to the docker group."
			PROGRAMS_ERRORS+=("docker group add")
		fi
	fi

	# Interactively install Portainer
	if command -v docker >/dev/null; then
		if gum_confirm "Install Portainer for Docker management?"; then
			step "Installing Portainer"
			if sudo docker volume create portainer_data >/dev/null 2>&1; then
				log_success "Created Docker volume for Portainer data."
			else
				log_warning "Could not create Portainer Docker volume (it might already exist)."
			fi

			step "Pulling Portainer image and starting container"
			# Stop and remove existing container to ensure a clean start
			sudo docker stop portainer >/dev/null 2>&1 || true
			sudo docker rm portainer >/dev/null 2>&1 || true

			if sudo docker run -d -p 8000:8000 -p 9443:9443 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest >/dev/null 2>&1; then
				log_success "Portainer container is running."
				ui_info "You can access Portainer at https://<your-server-ip>:9443"
			else
				log_error "Failed to start the Portainer container."
				PROGRAMS_ERRORS+=("Portainer container start")
			fi
		else
			ui_info "Portainer installation skipped."
		fi
	fi

	# Interactively install Watchtower
	if command -v docker >/dev/null; then
		if gum_confirm "Install Watchtower for automatic container updates?"; then
			step "Installing Watchtower"
			# Stop and remove existing container to ensure a clean start
			sudo docker stop watchtower >/dev/null 2>&1 || true
			sudo docker rm watchtower >/dev/null 2>&1 || true

			if sudo docker run -d --name=watchtower --restart=always -v /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower >/dev/null 2>&1; then
				log_success "Watchtower container is running."
				ui_info "Watchtower will now monitor your running containers and update them automatically."
			else
				log_error "Failed to start the Watchtower container."
				PROGRAMS_ERRORS+=("Watchtower container start")
			fi
		else
			ui_info "Watchtower installation skipped."
		fi
	fi
}

# ===== Installation Functions =====

install_pacman_packages() {
	if [[ ${#essential_programs[@]} -eq 0 ]]; then
		ui_info "No pacman packages to install."
		return
	fi
	ui_info "Installing ${#essential_programs[@]} pacman packages..."

	# Try batch install first for speed
	printf "${CYAN}Attempting batch installation...${RESET}\n"
	if sudo pacman -S --noconfirm --needed "${essential_programs[@]}" >/dev/null 2>&1; then
		printf "${GREEN} ✓ Batch installation successful${RESET}\n"
		PROGRAMS_INSTALLED+=("${essential_programs[@]}")
		return
	fi

	printf "${YELLOW} ! Batch installation failed. Falling back to individual installation...${RESET}\n"
	for pkg in "${essential_programs[@]}"; do
		if pacman_install "$pkg"; then PROGRAMS_INSTALLED+=("$pkg"); else PROGRAMS_ERRORS+=("$pkg (pacman)"); fi
	done
}

install_aur_packages() {
	if ! command -v yay >/dev/null; then ui_warn "yay is not installed. Skipping AUR packages."; return; fi
	if [[ ${#yay_programs[@]} -eq 0 ]]; then ui_info "No AUR packages to install."; return; fi
	ui_info "Installing ${#yay_programs[@]} AUR packages with yay..."

	# Try batch install first
	printf "${CYAN}Attempting batch installation...${RESET}\n"
	if yay -S --noconfirm --needed "${yay_programs[@]}" >/dev/null 2>&1; then
		printf "${GREEN} ✓ Batch installation successful${RESET}\n"
		for pkg in "${yay_programs[@]}"; do
			PROGRAMS_INSTALLED+=("$pkg (AUR)")
		done
		return
	fi

	printf "${YELLOW} ! Batch installation failed. Falling back to individual installation...${RESET}\n"
	for pkg in "${yay_programs[@]}"; do
		if yay_install "$pkg"; then PROGRAMS_INSTALLED+=("$pkg (AUR)"); else PROGRAMS_ERRORS+=("$pkg (AUR)"); fi
	done
}

install_flatpak_packages() {
	if ! command -v flatpak >/dev/null; then ui_warn "flatpak is not installed. Skipping Flatpak packages."; return; fi
	if ! flatpak remote-list | grep -q flathub; then
		step "Adding Flathub remote"
		flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	fi
	if [[ ${#flatpak_programs[@]} -eq 0 ]]; then ui_info "No Flatpak applications to install."; return; fi
	ui_info "Installing ${#flatpak_programs[@]} Flatpak applications..."

	for pkg in "${flatpak_programs[@]}"; do
		if flatpak_install "$pkg"; then PROGRAMS_INSTALLED+=("$pkg (Flatpak)"); else PROGRAMS_ERRORS+=("$pkg (Flatpak)"); fi
	done
}

remove_pacman_packages() {
	if [[ ${#specific_remove_programs[@]} -eq 0 ]]; then return; fi
	ui_info "Removing ${#specific_remove_programs[@]} conflicting/unnecessary packages..."
	for pkg in "${specific_remove_programs[@]}"; do
		if pacman_remove "$pkg"; then PROGRAMS_REMOVED+=("$pkg"); else PROGRAMS_ERRORS+=("$pkg (removal)"); fi
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
	if ! load_package_lists_from_yaml; then
		return 1
	fi
	determine_package_lists
	handle_de_packages
	handle_flatpak_packages
	install_pacman_packages "${essential_programs[@]}"
	install_aur_packages "${yay_programs[@]}"
	install_flatpak_packages "${flatpak_programs[@]}"
	remove_pacman_packages "${specific_remove_programs[@]}"

	if [[ "$INSTALL_MODE" == "server" ]]; then
		configure_server_applications
	fi

	ui_success "Program installation phase completed."
}

main
