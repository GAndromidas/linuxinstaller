#!/bin/bash
set -uo pipefail

# Get the directory where this script is located, resolving symlinks
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ARCHINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$ARCHINSTALLER_ROOT/configs"

source "$SCRIPT_DIR/common.sh"

export SUDO_ASKPASS=   # Force sudo to prompt in terminal, not via GUI

# ===== Globals =====
CURRENT_STEP=1
PROGRAMS_ERRORS=()
PROGRAMS_INSTALLED=()
PROGRAMS_REMOVED=()
essential_programs=()           # Initialize to prevent unbound variable errors
yay_programs=()                 # Initialize to prevent unbound variable errors
flatpak_programs=()             # Initialize to prevent unbound variable errors
specific_install_programs=()   # Initialize to prevent unbound variable errors
specific_remove_programs=()    # Initialize to prevent unbound variable errors

# ===== YAML Parsing Functions =====

# Function to check if yq is available, install if not
ensure_yq() {
  if ! command -v yq &>/dev/null; then
    echo -e "${YELLOW}yq is required for YAML parsing. Installing...${RESET}"
    sudo pacman -S --noconfirm yq
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

  # Use yq to extract packages and descriptions
  local yq_output
  yq_output=$(yq -r "$yaml_path[] | [.name, .description] | @tsv" "$yaml_file" 2>/dev/null)

  if [[ $? -eq 0 && -n "$yq_output" ]]; then
    while IFS=$'\t' read -r name description; do
      [[ -z "$name" ]] && continue
      packages_array+=("$name")
      descriptions_array+=("$description")
    done <<< "$yq_output"
  fi
}

# Function to read simple package lists (without descriptions)
read_yaml_simple_packages() {
  local yaml_file="$1"
  local yaml_path="$2"
  local -n packages_array="$3"

  packages_array=()

  # Use yq to extract simple package names
  local yq_output
  yq_output=$(yq -r "$yaml_path[]" "$yaml_file" 2>/dev/null)

  if [[ $? -eq 0 && -n "$yq_output" ]]; then
    while IFS= read -r package; do
      [[ -z "$package" ]] && continue
      packages_array+=("$package")
    done <<< "$yq_output"
  fi
}

# ===== Program Lists (Loaded from YAML) =====

# Check if programs.yaml exists
PROGRAMS_YAML="$CONFIGS_DIR/programs.yaml"
if [[ ! -f "$PROGRAMS_YAML" ]]; then
  log_error "Programs configuration file not found: $PROGRAMS_YAML"
  log_error "Please ensure you have the complete archinstaller repository with configs/programs.yaml."
  return 1
fi

# Ensure yq is available
if ! ensure_yq; then
  return 1
fi

# Read base package lists from YAML
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
read_yaml_packages "$PROGRAMS_YAML" ".custom.flatpak" custom_selectable_flatpak_programs custom_selectable_flatpak_descriptions

# ===== Custom Selection Functions =====

# Helper: Show gum checklist for a package list
show_checklist() {
  local title="$1"
  shift
  local whiptail_choices=("$@") # Original choices in pkg, desc, status format

  local gum_options=()
  local pre_selected_options=()

  local i=0
  while [[ $i -lt ${#whiptail_choices[@]} ]]; do
    local pkg_name="${whiptail_choices[$i]}"
    local display_description="${whiptail_choices[$((i+1))]}"
    local status="${whiptail_choices[$((i+2))]}"

    # Gum displays the description, we want to pass the full display text
    gum_options+=("$display_description")

    if [[ "$status" == "on" ]]; then
      pre_selected_options+=("$display_description")
    fi
    i=$((i+3))
  done

  local selected_output
  local gum_command=(gum filter \
    --no-limit \
    --height 15 \
    --placeholder "Filter packages..." \
    --prompt "Use space to select, enter to confirm:" \
    --header "$title")

  if [[ ${#pre_selected_options[@]} -gt 0 ]]; then
    gum_command+=(--selected "$(printf "%s," "${pre_selected_options[@]}" | sed 's/,$//')")
  fi

  # Pass options as separate arguments
  selected_output=$(printf "%s\\n" "${gum_options[@]}" | "${gum_command[@]}")

  local status=$?
  if [[ $status -ne 0 ]]; then
    # User cancelled or gum failed
    echo -e "${RED}Selection cancelled. Exiting.${RESET}" >&2
    exit 1
  fi

  # Gum filter returns the selected items as displayed.
  # We need to extract the original package name (first word before ' - ')
  local final_selected_pkgs=()
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      # Extract the package name from the "package_name - description" format
      local pkg_from_display=$(echo "$line" | cut -d' ' -f1)
      final_selected_pkgs+=("$pkg_from_display")
    fi
  done <<< "$selected_output"

  # Output the raw package names, similar to whiptail's output
  printf "%s\\n" "${final_selected_pkgs[@]}"
}

# Custom selection for Essential packages (additional to minimal)
custom_essential_selection() {
  # Base essential packages (from minimal mode) are automatically included.
  # Here we offer additional essential packages for user selection.
  essential_programs=("${essential_programs_minimal[@]}")

  local all_selectable_pkgs=("${custom_selectable_essential_programs[@]}")
  local selectable_descriptions=("${custom_selectable_essential_descriptions[@]}")

  local choices=()
  for pkg in "${all_selectable_pkgs[@]}"; do
    [[ -z "$pkg" ]] && continue

    local description="$pkg"
    for i in "${!all_selectable_pkgs[@]}"; do
      if [[ "${all_selectable_pkgs[$i]}" == "$pkg" ]]; then
        description="${selectable_descriptions[$i]}"
        break
      fi
    done

    local display_text="$pkg - $description"
    choices+=("$pkg" "$display_text" "off") # All custom options start as off
  done

  local selected
  selected=$(show_checklist "Select ADDITIONAL Essential packages to install (SPACE=select, ENTER=confirm):" "${choices[@]}")

  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    essential_programs+=("$pkg") # Add selected custom essential packages
  done <<< "$selected"
}

# Custom selection for AUR packages (additional to minimal's defaults if any)
custom_aur_selection() {
  # Base AUR packages (from minimal mode) are automatically included.
  # Here we offer additional AUR packages for user selection.
  yay_programs=("${yay_programs_minimal[@]}")

  local all_selectable_pkgs=("${custom_selectable_yay_programs[@]}")
  local selectable_descriptions=("${custom_selectable_yay_descriptions[@]}")

  local choices=()
  for pkg in "${all_selectable_pkgs[@]}"; do
    [[ -z "$pkg" ]] && continue

    local description="$pkg"
    for i in "${!all_selectable_pkgs[@]}"; do
      if [[ "${all_selectable_pkgs[$i]}" == "$pkg" ]]; then
        description="${selectable_descriptions[$i]}"
        break
      fi
    done

    local display_text="$pkg - $description"
    choices+=("$pkg" "$display_text" "off") # All custom options start as off
  done

  local selected
  selected=$(show_checklist "Select ADDITIONAL AUR packages to install (SPACE=select, ENTER=confirm):" "${choices[@]}")

  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    yay_programs+=("$pkg") # Add selected custom AUR packages
  done <<< "$selected"
}

# Custom selection for Flatpaks (additional to minimal's defaults if any)
custom_flatpak_selection() {
  # Base Flatpak packages (from minimal mode for the detected DE) are automatically included.
  # Here we offer additional Flatpak apps for user selection.
  local de_lower=""
  case "$XDG_CURRENT_DESKTOP" in
    KDE) de_lower="kde" ;;
    GNOME) de_lower="gnome" ;;
    COSMIC) de_lower="cosmic" ;;
    *) de_lower="generic" ;;
  esac

  local base_flatpaks=()
  get_flatpak_packages "$de_lower" "minimal" base_flatpaks # Load minimal Flatpaks for the detected DE
  flatpak_programs=("${base_flatpaks[@]}")


  echo -e "${CYAN}Detected DE: $XDG_CURRENT_DESKTOP (using $de_lower flatpaks)${RESET}"

  local de_flatpak_names=()
  local de_flatpak_descriptions=()
  local yq_path=".custom.flatpak.$de_lower"

  # Load custom Flatpak programs specific to the detected DE
  local yq_output
  yq_output=$(yq -r "${yq_path}[].name" "$PROGRAMS_YAML" 2>/dev/null)
  if [[ -n "$yq_output" ]]; then
    mapfile -t de_flatpak_names <<< "$yq_output"
  fi

  yq_output=$(yq -r "${yq_path}[].description" "$PROGRAMS_YAML" 2>/dev/null)
  if [[ -n "$yq_output" ]]; then
    mapfile -t de_flatpak_descriptions <<< "$yq_output"
  fi

  local all_selectable_pkgs=("${de_flatpak_names[@]}")
  local selectable_descriptions=("${de_flatpak_descriptions[@]}")

  local choices=()
  for flatpak_entry in "${all_selectable_pkgs[@]}"; do
    [[ -z "$flatpak_entry" ]] && continue

    local pkg="$flatpak_entry"
    local description=""
    for i in "${!all_selectable_pkgs[@]}"; do
      if [[ "${all_selectable_pkgs[$i]}" == "$pkg" ]]; then
        description="${selectable_descriptions[$i]}"
        break
      fi
    done

    local display_text="$pkg - $description"
    choices+=("$pkg" "$display_text" "off") # All custom options start as off
  done

  local selected
  selected=$(show_checklist "Select ADDITIONAL Flatpak apps to install (SPACE=select, ENTER=confirm):" "${choices[@]}")

  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    flatpak_programs+=("$pkg") # Add selected custom Flatpak apps
  done <<< "$selected"

  echo -e "${CYAN}User selected flatpak packages: ${flatpak_programs[*]}${RESET}"
}

# ===== Helper Functions =====

is_package_installed() { command -v "$1" &>/dev/null || pacman -Q "$1" &>/dev/null; }

handle_error() { if [ $? -ne 0 ]; then log_error "$1"; return 1; fi; return 0; }

check_yay() {
  if ! command -v yay &>/dev/null; then
    log_warning "yay (AUR helper) is not installed. AUR packages will be skipped."
    return 1
  fi
  return 0
}

check_flatpak() {
  if ! command -v flatpak &>/dev/null; then
    log_warning "flatpak is not installed. Flatpak packages will be skipped."
    return 1
  fi
  if ! flatpak remote-list | grep -q flathub; then
    step "Adding Flathub remote"
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    handle_error "Failed to add Flathub remote."
  fi
  step "Updating Flatpak remotes"
  flatpak update -y

  # Update desktop database to ensure Flatpak apps appear in menus
  step "Updating desktop database for Flatpak integration"
  if command -v update-desktop-database &>/dev/null; then
    # Update system-wide desktop database
    sudo update-desktop-database /usr/share/applications/ 2>/dev/null || true

    # Update user-specific desktop database
    if [[ -d "$HOME/.local/share/applications" ]]; then
      update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    # Update Flatpak-specific desktop databases
    if [[ -d "/var/lib/flatpak/exports/share/applications" ]]; then
      sudo update-desktop-database /var/lib/flatpak/exports/share/applications 2>/dev/null || true
    fi
    if [[ -d "$HOME/.local/share/flatpak/exports/share/applications" ]]; then
      update-desktop-database "$HOME/.local/share/flatpak/exports/share/applications" 2>/dev/null || true
    fi

    log_success "Desktop database updated for Flatpak integration"
  else
    log_warning "update-desktop-database not found. Flatpak apps may not appear in menus until session restart."
  fi

  return 0
}

# ===== Improved Quiet Install Functions =====

install_pacman_quietly() {
  local pkgs=("$@")
  local to_install=()
  for pkg in "${pkgs[@]}"; do
    pacman -Q "$pkg" &>/dev/null || to_install+=("$pkg")
  done
  local total=${#to_install[@]}
  if [ $total -eq 0 ]; then
    echo -e "${YELLOW}All Pacman packages are already installed.${RESET}"
    return
  fi
  echo -e "${CYAN}Installing ${total} packages via Pacman (batch)...${RESET}"
  echo -e "${CYAN}Packages:${RESET} ${to_install[*]}"
  if sudo pacman -S --noconfirm --needed "${to_install[@]}"; then
    for pkg in "${to_install[@]}"; do
      pacman -Q "$pkg" &>/dev/null && PROGRAMS_INSTALLED+=("$pkg")
    done
    echo -e "${GREEN}Pacman batch installation completed.${RESET}"
  else
    echo -e "${RED}Some Pacman packages failed to install.${RESET}"
    for pkg in "${to_install[@]}"; do
      pacman -Q "$pkg" &>/dev/null || PROGRAMS_ERRORS+=("Failed to install $pkg")
    done
  fi
}

install_flatpak_quietly() {
  local pkgs=("$@")
  local to_install=()
  for pkg in "${pkgs[@]}"; do
    flatpak list --app | grep -qw "$pkg" || to_install+=("$pkg")
  done
  local total=${#to_install[@]}
  if [ $total -eq 0 ]; then
    echo -e "${YELLOW}All Flatpak packages are already installed.${RESET}"
    return
  fi
  echo -e "${CYAN}Installing ${total} packages via Flatpak (batch)...${RESET}"
  echo -e "${CYAN}Packages:${RESET} ${to_install[*]}"
  if flatpak install -y --noninteractive flathub "${to_install[@]}"; then
    for pkg in "${to_install[@]}"; do
      flatpak list --app | grep -qw "$pkg" && PROGRAMS_INSTALLED+=("$pkg (flatpak)")
    done
    echo -e "${GREEN}Flatpak batch installation completed.${RESET}"
  else
    echo -e "${RED}Some Flatpak packages failed to install.${RESET}"
    for pkg in "${to_install[@]}"; do
      flatpak list --app | grep -qw "$pkg" || PROGRAMS_ERRORS+=("Failed to install Flatpak $pkg")
    done
  fi
}

install_aur_quietly() {
  local pkgs=("$@")
  local to_install=()
  for pkg in "${pkgs[@]}"; do
    pacman -Q "$pkg" &>/dev/null || to_install+=("$pkg")
  done
  local total=${#to_install[@]}
  if [ $total -eq 0 ]; then
    echo -e "${YELLOW}All AUR packages are already installed.${RESET}"
    return
  fi
  echo -e "${CYAN}Installing ${total} packages via AUR (yay, batch)...${RESET}"
  echo -e "${CYAN}Packages:${RESET} ${to_install[*]}"
  if yay -S --noconfirm --needed "${to_install[@]}"; then
    for pkg in "${to_install[@]}"; do
      pacman -Q "$pkg" &>/dev/null && PROGRAMS_INSTALLED+=("$pkg (AUR)")
    done
    echo -e "${GREEN}AUR batch installation completed.${RESET}"
  else
    echo -e "${RED}Some AUR packages failed to install.${RESET}"
    for pkg in "${to_install[@]}"; do
      pacman -Q "$pkg" &>/dev/null || PROGRAMS_ERRORS+=("Failed to install AUR $pkg")
    done
  fi
}

detect_desktop_environment() {
  case "$XDG_CURRENT_DESKTOP" in
    KDE)
      log_success "KDE detected."
      specific_install_programs=("${kde_install_programs[@]}")
      specific_remove_programs=("${kde_remove_programs[@]}")
      flatpak_install_function="install_flatpak_programs_kde"
      flatpak_minimal_function="install_flatpak_minimal_kde"
      ;;
    GNOME)
      log_success "GNOME detected."
      specific_install_programs=("${gnome_install_programs[@]}")
      specific_remove_programs=("${gnome_remove_programs[@]}")
      flatpak_install_function="install_flatpak_programs_gnome"
      flatpak_minimal_function="install_flatpak_minimal_gnome"
      ;;
    COSMIC)
      log_success "Cosmic DE detected."
      specific_install_programs=("${cosmic_install_programs[@]}")
      specific_remove_programs=("${cosmic_remove_programs[@]}")
      flatpak_install_function="install_flatpak_programs_cosmic"
      flatpak_minimal_function="install_flatpak_minimal_cosmic"
      ;;
    *)
      log_warning "No KDE, GNOME, or Cosmic detected."
      specific_install_programs=()
      specific_remove_programs=()
      log_warning "Falling back to minimal set for unsupported DE/WM."
      # These variables should be set by the main logic based on INSTALL_MODE
      # For generic, we might not have a specific 'default' or 'minimal' flatpak function
      flatpak_install_function="install_flatpak_minimal_generic"
      flatpak_minimal_function="install_flatpak_minimal_generic"
      ;;
  esac
}

print_total_packages() {
  step "Calculating total packages to install"

  # Calculate Pacman packages
  # In custom mode, pacman_programs are determined interactively, essential_programs are for additional custom essential packages
  local pacman_total=$((${#pacman_programs[@]} + ${#essential_programs[@]} + ${#specific_install_programs[@]}))

  # Calculate AUR packages
  local aur_total=${#yay_programs[@]}

  # Calculate Flatpak packages (approximate based on DE)
  local flatpak_total=0
  if [[ "$INSTALL_MODE" == "default" ]]; then
    case "$XDG_CURRENT_DESKTOP" in
      KDE) flatpak_total=3 ;;
      GNOME) flatpak_total=4 ;;
      COSMIC) flatpak_total=4 ;;
      *) flatpak_total=1 ;; # generic
    esac
  elif [[ "$INSTALL_MODE" == "minimal" ]]; then
    case "$XDG_CURRENT_DESKTOP" in
      KDE) flatpak_total=1 ;;
      GNOME) flatpak_total=2 ;;
      COSMIC) flatpak_total=2 ;;
      *) flatpak_total=1 ;; # generic
    esac
  elif [[ "$INSTALL_MODE" == "custom" ]]; then
    flatpak_total=${#flatpak_programs[@]} # Use the actual count from custom selection
  fi

  # Calculate total
  local total_packages=$((pacman_total + aur_total + flatpak_total))

  echo -e "${CYAN}Total packages to install: ${total_packages}${RESET}"
  echo -e "  ${GREEN}Pacman: ${pacman_total}${RESET}"
  echo -e "  ${YELLOW}AUR: ${aur_total}${RESET}"
  echo -e "  ${BLUE}Flatpak: ${flatpak_total}${RESET}"
  echo ""
}

remove_programs() {
  step "Removing DE-specific programs"
  if [ ${#specific_remove_programs[@]} -eq 0 ]; then
    log_success "No specific programs to remove."
    return
  fi

  local total=${#specific_remove_programs[@]}
  local current=0

  echo -e "${CYAN}Removing ${total} DE-specific programs...${RESET}"

  for program in "${specific_remove_programs[@]}"; do
    ((current++))
    print_progress "$current" "$total" "$program"

    if is_package_installed "$program"; then
      if sudo pacman -Rns --noconfirm "$program" >/dev/null 2>&1; then
        print_status " [OK]" "$GREEN"
        PROGRAMS_REMOVED+=("$program")
      else
        print_status " [FAIL]" "$RED"
        log_error "Failed to remove $program"
      fi
    else
      print_status " [SKIP] Not installed" "$YELLOW"
    fi
  done

  echo -e "\\n${GREEN}Program removal completed (${current}/${total} programs processed)${RESET}\\n"
}

install_pacman_programs() {
  step "Installing Pacman programs"
  echo -e "${CYAN}=== Programs Installing ===${RESET}"

  local pkgs=("${pacman_programs[@]}")

  # For default/minimal modes, also include essential packages here.
  # For custom mode, essential_programs are populated by custom_essential_selection.
  if [[ "$INSTALL_MODE" != "custom" ]]; then
    pkgs+=("${essential_programs[@]}")
  fi

  # Always include DE-specific install programs
  if [ "${#specific_install_programs[@]}" -gt 0 ]; then
    pkgs+=("${specific_install_programs[@]}")
  fi

  install_pacman_quietly "${pkgs[@]}"
}

install_aur_packages() {
  step "Installing AUR packages"
  if [ ${#yay_programs[@]} -eq 0 ]; then
    log_success "No AUR packages to install."
    return
  fi

  if ! check_yay; then
    log_warning "Skipping AUR package installation due to missing yay."
    return
  fi

  echo -e "${CYAN}=== AUR Installing ===${RESET}"
  install_aur_quietly "${yay_programs[@]}"
}

install_flatpak_programs_list() {
  local flatpaks=("$@")
  install_flatpak_quietly "${flatpaks[@]}"
}

# Function to get flatpak packages from YAML
get_flatpak_packages() {
  local de="$1"
  local mode="$2"
  local -n packages_array="$3"

  packages_array=()

  # Use yq to extract flatpak package names
  local yq_output
  # In custom mode, this function will primarily be used to get base minimal flatpaks
  yq_output=$(yq -r ".flatpak.$de.$mode[].name" "$PROGRAMS_YAML" 2>/dev/null)

  if [[ $? -eq 0 && -n "$yq_output" ]]; then
    while IFS= read -r package; do
      [[ -z "$package" ]] && continue
      packages_array+=("$package")
    done <<< "$yq_output"
  fi
}

install_flatpak_programs_kde() {
  step "Installing Flatpak programs for KDE"
  local flatpaks
  get_flatpak_packages "kde" "default" flatpaks
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_programs_gnome() {
  step "Installing Flatpak programs for GNOME"
  local flatpaks
  get_flatpak_packages "gnome" "default" flatpaks
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_programs_cosmic() {
  step "Installing Flatpak programs for Cosmic"
  local flatpaks
  get_flatpak_packages "cosmic" "default" flatpaks
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_minimal_kde() {
  step "Installing minimal Flatpak programs for KDE"
  local flatpaks
  get_flatpak_packages "kde" "minimal" flatpaks
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_minimal_gnome() {
  step "Installing minimal Flatpak programs for GNOME"
  local flatpaks
  get_flatpak_packages "gnome" "minimal" flatpaks
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_minimal_cosmic() {
  step "Installing minimal Flatpak programs for Cosmic"
  local flatpaks
  get_flatpak_packages "cosmic" "minimal" flatpaks
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_minimal_generic() {
  step "Installing minimal Flatpak programs (generic DE/WM)"
  local flatpaks
  get_flatpak_packages "generic" "minimal" flatpaks
  install_flatpak_programs_list "${flatpaks[@]}"
}

print_programs_summary() {
  echo -e "\\n${CYAN}======= PROGRAMS SUMMARY =======${RESET}"
  if [ ${#PROGRAMS_INSTALLED[@]} -gt 0 ]; then
    echo -e "${GREEN}Installed:${RESET} ${PROGRAMS_INSTALLED[*]}"
  else
    echo -e "${YELLOW}No new packages were installed.${RESET}"
  fi
  if [ ${#PROGRAMS_REMOVED[@]} -gt 0 ]; then
    echo -e "${RED}Removed:${RESET} ${PROGRAMS_REMOVED[*]}"
  else
    echo -e "${GREEN}No packages were removed.${RESET}"
  fi
  if [ ${#PROGRAMS_ERRORS[@]} -gt 0 ]; then
    echo -e "${RED}Errors:${RESET}"
    for err in "${PROGRAMS_ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  else
    echo -e "${GREEN}All steps completed successfully!${RESET}"
  fi
  echo -e "${CYAN}===============================${RESET}"
}

# ===== MAIN LOGIC =====

# Use INSTALL_MODE from menu instead of command-line flags
if [[ "$INSTALL_MODE" == "default" ]]; then
  # For default mode, use default essential and AUR packages
  essential_programs=("${essential_programs_default[@]}")
  yay_programs=("${yay_programs_default[@]}")
elif [[ "$INSTALL_MODE" == "minimal" ]]; then
  # For minimal mode, use minimal essential and AUR packages
  essential_programs=("${essential_programs_minimal[@]}")
  yay_programs=("${yay_programs_minimal[@]}")
elif [[ "$INSTALL_MODE" == "custom" ]]; then
  # Detect desktop environment first to populate specific_install_programs
  detect_desktop_environment

  # Pacman programs are always from the main pacman.packages section, no custom pacman
  # essential_programs and yay_programs are initially minimal, then added to by custom selection
  essential_programs=("${essential_programs_minimal[@]}")
  yay_programs=("${yay_programs_minimal[@]}")

  # Install Pacman packages (including DE-specific ones) unconditionally first
  step "Installing Base Pacman Programs (Unified for all modes)"
  install_pacman_programs
  log_success "Base Pacman programs installed."

  # Now, proceed with interactive selections for ADDITIONAL Essential, AUR, and Flatpak

  # Custom Essential Selection (adds to minimal set)
  if gum confirm "Select ADDITIONAL Essential packages?"; then
    custom_essential_selection
  fi

  gum confirm "Continue to ADDITIONAL AUR package selection?" || exit 1
  custom_aur_selection

  gum confirm "Continue to ADDITIONAL Flatpak app selection?" || exit 1
  custom_flatpak_selection

  ui_success "Custom package selection complete. Proceeding with remaining installation steps."
else
  log_error "INSTALL_MODE not set. Please run the installer from the main menu."
  return 1
fi

if ! check_flatpak; then
  log_warning "Flatpak packages will be skipped."
fi

# Detect DE for non-custom modes (already done for custom mode)
if [[ "$INSTALL_MODE" != "custom" ]]; then
  detect_desktop_environment
fi

print_total_packages
remove_programs

# Pacman programs (including essential & DE-specific) are installed here for default/minimal modes
# For custom mode, base pacman packages are already installed above.
# Additional essential packages selected in custom mode are installed here.
if [[ "$INSTALL_MODE" != "custom" ]]; then
  install_pacman_programs
fi

if [[ "$INSTALL_MODE" == "default" ]]; then
  if [ -n "$flatpak_install_function" ]; then
    $flatpak_install_function
  else
    log_warning "No Flatpak install function for your DE."
  fi
elif [[ "$INSTALL_MODE" == "minimal" ]]; then
  if [ -n "$flatpak_minimal_function" ]; then
    $flatpak_minimal_function
  else
    install_flatpak_minimal_generic
  fi
elif [[ "$INSTALL_MODE" == "custom" ]]; then
  # Use user's custom flatpak selections (which already include minimal base + additions)
  if [ ${#flatpak_programs[@]} -gt 0 ]; then
    step "Installing custom selected Flatpak programs"
    echo -e "${CYAN}Selected flatpak packages: ${flatpak_programs[*]}${RESET}"
    install_flatpak_quietly "${flatpak_programs[@]}"
  else
    log_success "No additional Flatpak packages selected for installation."
  fi
fi

install_aur_packages
