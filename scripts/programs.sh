#!/bin/bash
set -uo pipefail

# Get the directory where this script is located, resolving symlinks
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ARCHINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROGRAM_LISTS_DIR="$ARCHINSTALLER_ROOT/program_lists"

source "$SCRIPT_DIR/common.sh"

export SUDO_ASKPASS=   # Force sudo to prompt in terminal, not via GUI

# ===== Globals =====
PROGRAMS_ERRORS=()
PROGRAMS_INSTALLED=()
PROGRAMS_REMOVED=()
WHIPTAIL_INSTALLED_BY_SCRIPT=false

# ===== Helper Functions for Package Lists =====

# Function to extract package name from "package|description" format
get_package_name() {
  local line="$1"
  echo "$line" | cut -d'|' -f1
}

# Function to extract description from "package|description" format
get_package_description() {
  local line="$1"
  echo "$line" | cut -d'|' -f2-
}

# Function to read package lists with descriptions
read_package_list() {
  local file="$1"
  local -n packages_array="$2"
  local -n descriptions_array="$3"
  
  packages_array=()
  descriptions_array=()
  
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    
    # Check if line contains description (has |)
    if [[ "$line" == *"|"* ]]; then
      packages_array+=("$(get_package_name "$line")")
      descriptions_array+=("$(get_package_description "$line")")
    else
      # Fallback for old format without descriptions
      packages_array+=("$line")
      descriptions_array+=("$line")
    fi
  done < "$file"
}

# ===== Program Lists (Loaded from program_lists) =====

# Check if program_lists directory exists
if [[ ! -d "$PROGRAM_LISTS_DIR" ]]; then
  log_error "Program lists directory not found: $PROGRAM_LISTS_DIR"
  log_error "Please ensure you have the complete archinstaller repository with program_lists folder."
  return 1
fi

# Check if required files exist
required_files=(
  "pacman_default.txt"
  "essential_default.txt"
  "pacman_minimal.txt"
  "essential_minimal.txt"
  "yay_default.txt"
  "yay_minimal.txt"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$PROGRAM_LISTS_DIR/$file" ]]; then
    log_error "Required file not found: $PROGRAM_LISTS_DIR/$file"
    log_error "Please ensure you have the complete archinstaller repository."
    return 1
  fi
done

# Read package lists with descriptions
read_package_list "$PROGRAM_LISTS_DIR/pacman_default.txt" pacman_programs_default pacman_descriptions_default
read_package_list "$PROGRAM_LISTS_DIR/essential_default.txt" essential_programs_default essential_descriptions_default
read_package_list "$PROGRAM_LISTS_DIR/pacman_minimal.txt" pacman_programs_minimal pacman_descriptions_minimal
read_package_list "$PROGRAM_LISTS_DIR/essential_minimal.txt" essential_programs_minimal essential_descriptions_minimal
read_package_list "$PROGRAM_LISTS_DIR/yay_default.txt" yay_programs_default yay_descriptions_default
read_package_list "$PROGRAM_LISTS_DIR/yay_minimal.txt" yay_programs_minimal yay_descriptions_minimal

# Read other package lists (keeping old format for now)
readarray -t kde_install_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/kde_install.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t kde_remove_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/kde_remove.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t gnome_install_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/gnome_install.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t gnome_remove_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/gnome_remove.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t cosmic_install_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/cosmic_install.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t cosmic_remove_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/cosmic_remove.txt" | grep -v '^\s*$' 2>/dev/null || echo "")

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

  # AUR packages
  all_pkgs=($(printf "%s\n" "${yay_programs_default[@]}" "${yay_programs_minimal[@]}" | sort -u))
  choices=()
  
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
    
    if [[ " ${yay_programs_minimal[*]} " == *" $pkg "* ]]; then
      choices+=("$pkg" "$display_text" "on")
    else
      choices+=("$pkg" "$display_text" "off")
    fi
  done
  
  selected=$(show_checklist "Select AUR packages to install (SPACE=select, ENTER=confirm):" "${choices[@]}")
  yay_programs=()
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    yay_programs+=("$pkg")
  done <<< "$selected"
}

# ===== Package Installation Functions =====

# Install packages via pacman
install_pacman_packages() {
  step "Installing Pacman packages"
  if [ ${#pacman_programs[@]} -gt 0 ]; then
    install_packages_quietly "${pacman_programs[@]}"
  else
    log_warning "No Pacman packages selected for installation"
  fi
}

# Install essential packages
install_essential_packages() {
  step "Installing Essential packages"
  if [ ${#essential_programs[@]} -gt 0 ]; then
    install_packages_quietly "${essential_programs[@]}"
  else
    log_warning "No Essential packages selected for installation"
  fi
}

# Install AUR packages via yay
install_aur_packages() {
  step "Installing AUR packages"
  if [ ${#yay_programs[@]} -gt 0 ]; then
    if command -v yay >/dev/null; then
      for pkg in "${yay_programs[@]}"; do
        if yay -Q "$pkg" &>/dev/null; then
          echo -e "${YELLOW}[SKIP] $pkg (already installed)${RESET}"
          continue
        fi
        echo -ne "${CYAN}Installing: $pkg ...${RESET} "
        if yay -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
          echo -e "${GREEN}[OK]${RESET}"
          PROGRAMS_INSTALLED+=("$pkg")
        else
          echo -e "${RED}[FAIL]${RESET}"
          log_error "Failed to install $pkg"
        fi
      done
    else
      log_error "yay (AUR helper) is not installed. Cannot install AUR packages."
    fi
  else
    log_warning "No AUR packages selected for installation"
  fi
}

# ===== Desktop Environment Functions =====

# Install KDE packages
install_kde_packages() {
  step "Installing KDE packages"
  if [ ${#kde_install_programs[@]} -gt 0 ]; then
    install_packages_quietly "${kde_install_programs[@]}"
  fi
}

# Remove KDE packages
remove_kde_packages() {
  step "Removing KDE packages"
  if [ ${#kde_remove_programs[@]} -gt 0 ]; then
    for pkg in "${kde_remove_programs[@]}"; do
      if pacman -Q "$pkg" &>/dev/null; then
        echo -ne "${CYAN}Removing: $pkg ...${RESET} "
        if sudo pacman -Rns --noconfirm "$pkg" >/dev/null 2>&1; then
          echo -e "${GREEN}[OK]${RESET}"
          PROGRAMS_REMOVED+=("$pkg")
        else
          echo -e "${RED}[FAIL]${RESET}"
          log_error "Failed to remove $pkg"
        fi
      else
        echo -e "${YELLOW}[SKIP] $pkg (not installed)${RESET}"
      fi
    done
  fi
}

# Install GNOME packages
install_gnome_packages() {
  step "Installing GNOME packages"
  if [ ${#gnome_install_programs[@]} -gt 0 ]; then
    install_packages_quietly "${gnome_install_programs[@]}"
  fi
}

# Remove GNOME packages
remove_gnome_packages() {
  step "Removing GNOME packages"
  if [ ${#gnome_remove_programs[@]} -gt 0 ]; then
    for pkg in "${gnome_remove_programs[@]}"; do
      if pacman -Q "$pkg" &>/dev/null; then
        echo -ne "${CYAN}Removing: $pkg ...${RESET} "
        if sudo pacman -Rns --noconfirm "$pkg" >/dev/null 2>&1; then
          echo -e "${GREEN}[OK]${RESET}"
          PROGRAMS_REMOVED+=("$pkg")
        else
          echo -e "${RED}[FAIL]${RESET}"
          log_error "Failed to remove $pkg"
        fi
      else
        echo -e "${YELLOW}[SKIP] $pkg (not installed)${RESET}"
      fi
    done
  fi
}

# Install COSMIC packages
install_cosmic_packages() {
  step "Installing COSMIC packages"
  if [ ${#cosmic_install_programs[@]} -gt 0 ]; then
    install_packages_quietly "${cosmic_install_programs[@]}"
  fi
}

# Remove COSMIC packages
remove_cosmic_packages() {
  step "Removing COSMIC packages"
  if [ ${#cosmic_remove_programs[@]} -gt 0 ]; then
    for pkg in "${cosmic_remove_programs[@]}"; do
      if pacman -Q "$pkg" &>/dev/null; then
        echo -ne "${CYAN}Removing: $pkg ...${RESET} "
        if sudo pacman -Rns --noconfirm "$pkg" >/dev/null 2>&1; then
          echo -e "${GREEN}[OK]${RESET}"
          PROGRAMS_REMOVED+=("$pkg")
        else
          echo -e "${RED}[FAIL]${RESET}"
          log_error "Failed to remove $pkg"
        fi
      else
        echo -e "${YELLOW}[SKIP] $pkg (not installed)${RESET}"
      fi
    done
  fi
}

# ===== Main Installation Logic =====

# Set package lists based on installation mode
set_package_lists() {
  case "$INSTALL_MODE" in
    "default")
      pacman_programs=("${pacman_programs_default[@]}")
      essential_programs=("${essential_programs_default[@]}")
      yay_programs=("${yay_programs_default[@]}")
      ;;
    "minimal")
      pacman_programs=("${pacman_programs_minimal[@]}")
      essential_programs=("${essential_programs_minimal[@]}")
      yay_programs=("${yay_programs_minimal[@]}")
      ;;
    "custom")
      custom_package_selection
      ;;
    *)
      log_error "Invalid installation mode: $INSTALL_MODE"
      return 1
      ;;
  esac
}

# Install whiptail for custom selection
install_whiptail() {
  if [ "$INSTALL_MODE" = "custom" ]; then
    if ! command -v whiptail >/dev/null; then
      step "Installing whiptail for package selection"
      sudo pacman -S --noconfirm newt
      WHIPTAIL_INSTALLED_BY_SCRIPT=true
    fi
  fi
}

# Main installation function
main() {
  echo -e "${CYAN}=== Programs Installation ===${RESET}"
  
  install_whiptail
  set_package_lists
  
  install_pacman_packages
  install_essential_packages
  install_aur_packages
  
  # Desktop environment packages (if any)
  install_kde_packages
  remove_kde_packages
  install_gnome_packages
  remove_gnome_packages
  install_cosmic_packages
  remove_cosmic_packages
  
  # Clean up whiptail if installed by script
  if [ "$WHIPTAIL_INSTALLED_BY_SCRIPT" = "true" ]; then
    sudo pacman -Rns --noconfirm newt
  fi
  
  # Print summary
  echo -e "\n${CYAN}=== PROGRAMS SUMMARY ===${RESET}"
  if [ ${#PROGRAMS_INSTALLED[@]} -gt 0 ]; then
    echo -e "${GREEN}Installed:${RESET} ${PROGRAMS_INSTALLED[*]}"
  fi
  if [ ${#PROGRAMS_REMOVED[@]} -gt 0 ]; then
    echo -e "${RED}Removed:${RESET} ${PROGRAMS_REMOVED[*]}"
  fi
  if [ ${#PROGRAMS_ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}Programs installation completed successfully!${RESET}"
  else
    echo -e "${RED}Some errors occurred:${RESET}"
    for err in "${PROGRAMS_ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  fi
  echo -e "${CYAN}===========================${RESET}"
}

main "$@"