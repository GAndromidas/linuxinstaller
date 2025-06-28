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
WHIPTAIL_INSTALLED_BY_SCRIPT=false

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

# Read package lists from YAML
read_yaml_packages "$PROGRAMS_YAML" ".pacman.default" pacman_programs_default pacman_descriptions_default
read_yaml_packages "$PROGRAMS_YAML" ".pacman.minimal" pacman_programs_minimal pacman_descriptions_minimal
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

# ===== Custom Selection Functions =====

# Helper: Show whiptail checklist for a package list
show_checklist() {
  local title="$1"
  shift
  local choices=("$@")
  # Echo the instruction to stderr so it doesn't interfere with the output
  echo -e "${YELLOW}Use the ARROW keys to move, SPACE to select/deselect, and ENTER to confirm your choices.${RESET}" >&2
  local selected
  selected=$(whiptail --separate-output --checklist "$title" 22 76 16 \
    "${choices[@]}" 3>&1 1>&2 2>&3 3>&-)
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo -e "${RED}Selection cancelled. Exiting.${RESET}" >&2
    [[ "$WHIPTAIL_INSTALLED_BY_SCRIPT" == "true" ]] && sudo pacman -Rns --noconfirm newt
    exit 1
  fi
  echo "$selected"
}

# Custom selection for Pacman/Essential
custom_package_selection() {
  # Combine and deduplicate pacman packages
  local all_pkgs=($(printf "%s\n" "${pacman_programs_default[@]}" "${pacman_programs_minimal[@]}" | sort -u))
  local choices=()
  
  for pkg in "${all_pkgs[@]}"; do
    [[ -z "$pkg" ]] && continue
    
    # Find description for this package
    local description="$pkg"
    for i in "${!pacman_programs_default[@]}"; do
      if [[ "${pacman_programs_default[$i]}" == "$pkg" ]]; then
        description="${pacman_descriptions_default[$i]}"
        break
      fi
    done
    for i in "${!pacman_programs_minimal[@]}"; do
      if [[ "${pacman_programs_minimal[$i]}" == "$pkg" ]]; then
        description="${pacman_descriptions_minimal[$i]}"
        break
      fi
    done
    
    # Create display text: "package_name - description"
    local display_text="$pkg - $description"
    
    # Only pre-select minimal packages, not default packages
    if [[ " ${pacman_programs_minimal[*]} " == *" $pkg "* ]]; then
      choices+=("$pkg" "$display_text" "on")
    else
      choices+=("$pkg" "$display_text" "off")
    fi
  done
  
  local selected
  selected=$(show_checklist "Select Pacman packages to install (SPACE=select, ENTER=confirm):" "${choices[@]}")
  pacman_programs=()
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    pacman_programs+=("$pkg")
  done <<< "$selected"

  # Essential packages
  all_pkgs=($(printf "%s\n" "${essential_programs_default[@]}" "${essential_programs_minimal[@]}" | sort -u))
  choices=()
  
  for pkg in "${all_pkgs[@]}"; do
    [[ -z "$pkg" ]] && continue
    
    # Find description for this package
    local description="$pkg"
    for i in "${!essential_programs_default[@]}"; do
      if [[ "${essential_programs_default[$i]}" == "$pkg" ]]; then
        description="${essential_descriptions_default[$i]}"
        break
      fi
    done
    for i in "${!essential_programs_minimal[@]}"; do
      if [[ "${essential_programs_minimal[$i]}" == "$pkg" ]]; then
        description="${essential_descriptions_minimal[$i]}"
        break
      fi
    done
    
    # Create display text: "package_name - description"
    local display_text="$pkg - $description"
    
    # Only pre-select minimal packages, not default packages
    if [[ " ${essential_programs_minimal[*]} " == *" $pkg "* ]]; then
      choices+=("$pkg" "$display_text" "on")
    else
      choices+=("$pkg" "$display_text" "off")
    fi
  done
  
  selected=$(show_checklist "Select Essential packages to install (SPACE=select, ENTER=confirm):" "${choices[@]}")
  essential_programs=()
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    essential_programs+=("$pkg")
  done <<< "$selected"
}

# Custom selection for AUR
custom_aur_selection() {
  local all_pkgs=($(printf "%s\n" "${yay_programs_default[@]}" "${yay_programs_minimal[@]}" | sort -u))
  local choices=()
  
  for pkg in "${all_pkgs[@]}"; do
    [[ -z "$pkg" ]] && continue
    
    # Find description for this package
    local description="$pkg"
    for i in "${!yay_programs_default[@]}"; do
      if [[ "${yay_programs_default[$i]}" == "$pkg" ]]; then
        description="${yay_descriptions_default[$i]}"
        break
      fi
    done
    for i in "${!yay_programs_minimal[@]}"; do
      if [[ "${yay_programs_minimal[$i]}" == "$pkg" ]]; then
        description="${yay_descriptions_minimal[$i]}"
        break
      fi
    done
    
    # Create display text: "package_name - description"
    local display_text="$pkg - $description"
    
    # Set all packages to "off" by default - no pre-selection
    choices+=("$pkg" "$display_text" "off")
  done
  
  local selected
  selected=$(show_checklist "Select AUR packages to install (SPACE=select, ENTER=confirm):" "${choices[@]}")
  yay_programs=()
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    yay_programs+=("$pkg")
  done <<< "$selected"
}

# Custom selection for Flatpaks
custom_flatpak_selection() {
  # Get flatpak packages from YAML based on detected DE
  local flatpak_data=()
  local de_lower=""
  
  case "$XDG_CURRENT_DESKTOP" in
    KDE) de_lower="kde" ;;
    GNOME) de_lower="gnome" ;;
    COSMIC) de_lower="cosmic" ;;
    *) de_lower="generic" ;;
  esac
  
  echo -e "${CYAN}Detected DE: $XDG_CURRENT_DESKTOP (using $de_lower flatpaks)${RESET}"
  
  # Read flatpak packages from YAML
  local yq_output
  yq_output=$(yq -r ".flatpak.$de_lower.default[] | [.name, .description] | @tsv" "$PROGRAMS_YAML" 2>/dev/null)
  
  if [[ $? -eq 0 && -n "$yq_output" ]]; then
    while IFS=$'\t' read -r name description; do
      [[ -z "$name" ]] && continue
      flatpak_data+=("$name|$description")
    done <<< "$yq_output"
  fi
  
  echo -e "${CYAN}Available flatpak packages: ${#flatpak_data[@]}${RESET}"
  
  local choices=()
  for flatpak_entry in "${flatpak_data[@]}"; do
    [[ -z "$flatpak_entry" ]] && continue
    
    # Extract package name and description
    local pkg=$(echo "$flatpak_entry" | cut -d'|' -f1)
    local description=$(echo "$flatpak_entry" | cut -d'|' -f2-)
    
    # Create display text: "package_name - description"
    local display_text="$pkg - $description"
    
    # Set all packages to "off" by default - no pre-selection
    choices+=("$pkg" "$display_text" "off")
  done
  
  local selected
  selected=$(show_checklist "Select Flatpak apps to install (SPACE=select, ENTER=confirm):" "${choices[@]}")
  flatpak_programs=()
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    flatpak_programs+=("$pkg")
  done <<< "$selected"
  
  echo -e "${CYAN}User selected flatpak packages: ${flatpak_programs[*]}${RESET}"
}

# ===== Helper Functions =====

is_package_installed() { command -v "$1" &>/dev/null || pacman -Q "$1" &>/dev/null; }

handle_error() { if [ $? -ne 0 ]; then log_error "$1"; return 1; fi; return 0; }

check_yay() { 
  if ! command -v yay &>/dev/null; then 
    log_warning "yay (AUR helper) is not installed. AUR packages will be skipped."; 
    return 1; 
  fi; 
  return 0;
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
  local total=${#pkgs[@]}
  local current=0
  
  if [ $total -eq 0 ]; then
    echo -e "${YELLOW}No Pacman packages to install${RESET}"
    return
  fi
  
  echo -e "${CYAN}Installing ${total} packages via Pacman...${RESET}"
  
  for pkg in "${pkgs[@]}"; do
    ((current++))
    if pacman -Q "$pkg" &>/dev/null; then
      print_progress "$current" "$total" "$pkg"
      print_status " [SKIP] Already installed" "$YELLOW"
      continue
    fi
    
    print_progress "$current" "$total" "$pkg"
    if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
      print_status " [OK]" "$GREEN"
      PROGRAMS_INSTALLED+=("$pkg")
    else
      print_status " [FAIL]" "$RED"
      log_error "Failed to install $pkg"
      PROGRAMS_ERRORS+=("Failed to install $pkg")
    fi
  done
  
  echo -e "\n${GREEN}✓ Pacman installation completed (${current}/${total} packages processed)${RESET}\n"
}

install_flatpak_quietly() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local current=0
  
  if [ $total -eq 0 ]; then
    echo -e "${YELLOW}No Flatpak packages to install${RESET}"
    return
  fi
  
  echo -e "${CYAN}Installing ${total} packages via Flatpak...${RESET}"
  
  for pkg in "${pkgs[@]}"; do
    ((current++))
    if flatpak list --app | grep -qw "$pkg"; then
      print_progress "$current" "$total" "$pkg"
      print_status " [SKIP] Already installed" "$YELLOW"
      continue
    fi
    
    print_progress "$current" "$total" "$pkg"
    if flatpak install -y --noninteractive flathub "$pkg" >/dev/null 2>&1; then
      print_status " [OK]" "$GREEN"
      PROGRAMS_INSTALLED+=("$pkg (flatpak)")
    else
      print_status " [FAIL]" "$RED"
      log_error "Failed to install Flatpak $pkg"
      PROGRAMS_ERRORS+=("Failed to install Flatpak $pkg")
    fi
  done
  
  echo -e "\n${GREEN}✓ Flatpak installation completed (${current}/${total} packages processed)${RESET}\n"
}

install_aur_quietly() {
  local pkgs=("$@")
  local total=${#pkgs[@]}
  local current=0
  
  if [ $total -eq 0 ]; then
    echo -e "${YELLOW}No AUR packages to install${RESET}"
    return
  fi
  
  echo -e "${CYAN}Installing ${total} packages via AUR (yay)...${RESET}"
  
  for pkg in "${pkgs[@]}"; do
    ((current++))
    if pacman -Q "$pkg" &>/dev/null; then
      print_progress "$current" "$total" "$pkg"
      print_status " [SKIP] Already installed" "$YELLOW"
      continue
    fi
    
    print_progress "$current" "$total" "$pkg"
    if yay -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
      print_status " [OK]" "$GREEN"
      PROGRAMS_INSTALLED+=("$pkg (AUR)")
    else
      print_status " [FAIL]" "$RED"
      log_error "Failed to install AUR $pkg"
      PROGRAMS_ERRORS+=("Failed to install AUR $pkg")
    fi
  done
  
  echo -e "\n${GREEN}✓ AUR installation completed (${current}/${total} packages processed)${RESET}\n"
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
      pacman_programs=("${pacman_programs_minimal[@]}")
      essential_programs=("${essential_programs_minimal[@]}")
      flatpak_install_function="install_flatpak_minimal_generic"
      flatpak_minimal_function="install_flatpak_minimal_generic"
      ;;
  esac
}

print_total_packages() {
  step "Calculating total packages to install"
  
  # Calculate Pacman packages
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
      *) flatpak_total=1 ;;
    esac
  else
    case "$XDG_CURRENT_DESKTOP" in
      KDE) flatpak_total=1 ;;
      GNOME) flatpak_total=2 ;;
      COSMIC) flatpak_total=2 ;;
      *) flatpak_total=1 ;;
    esac
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
  
  echo -e "\n${GREEN}✓ Program removal completed (${current}/${total} programs processed)${RESET}\n"
}

install_pacman_programs() {
  step "Installing Pacman programs"
  echo -e "${CYAN}=== Programs Installing ===${RESET}"

  local pkgs=("${pacman_programs[@]}" "${essential_programs[@]}")
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
  echo -e "\n${CYAN}======= PROGRAMS SUMMARY =======${RESET}"
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
  pacman_programs=("${pacman_programs_default[@]}")
  essential_programs=("${essential_programs_default[@]}")
  yay_programs=("${yay_programs_default[@]}")
elif [[ "$INSTALL_MODE" == "minimal" ]]; then
  pacman_programs=("${pacman_programs_minimal[@]}")
  essential_programs=("${essential_programs_minimal[@]}")
  yay_programs=("${yay_programs_minimal[@]}")
elif [[ "$INSTALL_MODE" == "custom" ]]; then
  if ! command -v whiptail &>/dev/null; then
    echo -e "${YELLOW}The 'whiptail' package is required for custom selection. Installing...${RESET}"
    sudo pacman -S --noconfirm newt
    WHIPTAIL_INSTALLED_BY_SCRIPT=true
  fi
  custom_package_selection
  custom_aur_selection
  custom_flatpak_selection
else
  log_error "INSTALL_MODE not set. Please run the installer from the main menu."
  return 1
fi

if ! check_flatpak; then
  log_warning "Flatpak packages will be skipped."
fi

detect_desktop_environment
print_total_packages
remove_programs
install_pacman_programs

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
  # Use user's custom flatpak selections
  if [ ${#flatpak_programs[@]} -gt 0 ]; then
    step "Installing custom selected Flatpak programs"
    echo -e "${CYAN}Selected flatpak packages: ${flatpak_programs[*]}${RESET}"
    install_flatpak_quietly "${flatpak_programs[@]}"
  else
    log_success "No Flatpak packages selected for installation."
  fi
fi

install_aur_packages

if [[ "$WHIPTAIL_INSTALLED_BY_SCRIPT" == "true" ]]; then
  echo -e "${YELLOW}Removing 'whiptail' (newt) package as it is no longer needed...${RESET}"
  sudo pacman -Rns --noconfirm newt
fi