#!/bin/bash
set -uo pipefail

# Get the directory where this script is located, resolving symlinks
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/common.sh"

export SUDO_ASKPASS=   # Force sudo to prompt in terminal, not via GUI

# ===== Colors for output =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
RESET='\033[0m'

# ===== Globals =====
CURRENT_STEP=1
PROGRAMS_ERRORS=()
PROGRAMS_INSTALLED=()
PROGRAMS_REMOVED=()
DIALOG_INSTALLED_BY_SCRIPT=false

# ===== Output Functions =====
step()   { echo -e "\n${CYAN}[$CURRENT_STEP] $1${RESET}"; ((CURRENT_STEP++)); }
log_success() { echo -e "${GREEN}[OK] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_error()   { echo -e "${RED}[FAIL] $1${RESET}"; PROGRAMS_ERRORS+=("$1"); }

# ===== Program Lists (Loaded from program_lists) =====
# Get the archinstaller root directory (parent of scripts directory)
ARCHINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROGRAM_LISTS_DIR="$ARCHINSTALLER_ROOT/program_lists"

echo "DEBUG: SCRIPT_PATH=$SCRIPT_PATH"
echo "DEBUG: SCRIPT_DIR=$SCRIPT_DIR"
echo "DEBUG: ARCHINSTALLER_ROOT=$ARCHINSTALLER_ROOT"
echo "DEBUG: PROGRAM_LISTS_DIR=$PROGRAM_LISTS_DIR"
ls -l "$PROGRAM_LISTS_DIR"

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

readarray -t pacman_programs_default < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/pacman_default.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t essential_programs_default < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/essential_default.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t pacman_programs_minimal < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/pacman_minimal.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t essential_programs_minimal < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/essential_minimal.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t kde_install_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/kde_install.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t kde_remove_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/kde_remove.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t gnome_install_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/gnome_install.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t gnome_remove_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/gnome_remove.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t cosmic_install_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/cosmic_install.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t cosmic_remove_programs < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/cosmic_remove.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t yay_programs_default < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/yay_default.txt" | grep -v '^\s*$' 2>/dev/null || echo "")
readarray -t yay_programs_minimal < <(grep -v '^\s*#' "$PROGRAM_LISTS_DIR/yay_minimal.txt" | grep -v '^\s*$' 2>/dev/null || echo "")

# ===== Custom Selection Functions =====

# Helper: Show dialog checklist for a package list
show_dialog_checklist() {
  local title="$1"
  shift
  local choices=("$@")
  echo -e "${YELLOW}Use the ARROW keys to move, SPACE to select/deselect, and ENTER to confirm your choices.${RESET}"
  local selected
  selected=$(dialog --separate-output --checklist "$title" 22 76 16 \
    "${choices[@]}" 3>&1 1>&2 2>&3 3>&-)
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo -e "${RED}Selection cancelled. Exiting.${RESET}"
    [[ "$DIALOG_INSTALLED_BY_SCRIPT" == "true" ]] && sudo pacman -Rns --noconfirm dialog
    exit 1
  fi
  echo "$selected"
}

# Custom selection for Pacman/Essential
custom_package_selection() {
  # Combine and deduplicate
  local all_pkgs=($(printf "%s\n" "${pacman_programs_default[@]}" "${pacman_programs_minimal[@]}" | sort -u))
  local choices=()
  for pkg in "${all_pkgs[@]}"; do
    if [[ " ${pacman_programs_minimal[*]} " == *" $pkg "* ]]; then
      choices+=("$pkg" "$pkg" "on")
    else
      choices+=("$pkg" "$pkg" "off")
    fi
  done
  local selected
  selected=$(show_dialog_checklist "Select Pacman packages to install (SPACE=select, ENTER=confirm):" "${choices[@]}")
  pacman_programs=()
  for pkg in $selected; do
    pkg="${pkg%\"}"; pkg="${pkg#\"}"
    pacman_programs+=("$pkg")
  done

  # Essential packages
  all_pkgs=($(printf "%s\n" "${essential_programs_default[@]}" "${essential_programs_minimal[@]}" | sort -u))
  choices=()
  for pkg in "${all_pkgs[@]}"; do
    if [[ " ${essential_programs_minimal[*]} " == *" $pkg "* ]]; then
      choices+=("$pkg" "$pkg" "on")
    else
      choices+=("$pkg" "$pkg" "off")
    fi
  done
  selected=$(show_dialog_checklist "Select Essential packages to install (SPACE=select, ENTER=confirm):" "${choices[@]}")
  essential_programs=()
  for pkg in $selected; do
    pkg="${pkg%\"}"; pkg="${pkg#\"}"
    essential_programs+=("$pkg")
  done
}

# Custom selection for AUR
custom_aur_selection() {
  local all_pkgs=($(printf "%s\n" "${yay_programs_default[@]}" "${yay_programs_minimal[@]}" | sort -u))
  local choices=()
  for pkg in "${all_pkgs[@]}"; do
    if [[ " ${yay_programs_minimal[*]} " == *" $pkg "* ]]; then
      choices+=("$pkg" "$pkg" "on")
    else
      choices+=("$pkg" "$pkg" "off")
    fi
  done
  local selected
  selected=$(show_dialog_checklist "Select AUR packages to install (SPACE=select, ENTER=confirm):" "${choices[@]}")
  yay_programs=()
  for pkg in $selected; do
    pkg="${pkg%\"}"; pkg="${pkg#\"}"
    yay_programs+=("$pkg")
  done
}

# Custom selection for Flatpaks
custom_flatpak_selection() {
  # You should load all possible flatpak lists into arrays at the top of your script, or from files
  local all_flatpaks=(
    io.github.shiftey.Desktop
    it.mijorus.gearlever
    net.davidotek.pupgui2
    com.mattjakeman.ExtensionManager
    com.vysp3r.ProtonPlus
    dev.edfloreshz.CosmicTweaks
  )
  local minimal_flatpaks=(
    it.mijorus.gearlever
    com.mattjakeman.ExtensionManager
    dev.edfloreshz.CosmicTweaks
  )
  # Deduplicate
  local unique_flatpaks=($(printf "%s\n" "${all_flatpaks[@]}" | sort -u))
  local choices=()
  for pkg in "${unique_flatpaks[@]}"; do
    if [[ " ${minimal_flatpaks[*]} " == *" $pkg "* ]]; then
      choices+=("$pkg" "$pkg" "on")
    else
      choices+=("$pkg" "$pkg" "off")
    fi
  done
  local selected
  selected=$(show_dialog_checklist "Select Flatpak apps to install (SPACE=select, ENTER=confirm):" "${choices[@]}")
  flatpak_programs=()
  for pkg in $selected; do
    pkg="${pkg%\"}"; pkg="${pkg#\"}"
    flatpak_programs+=("$pkg")
  done
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

install_flatpak_programs_kde() {
  step "Installing Flatpak programs for KDE"
  local flatpaks=(
    io.github.shiftey.Desktop
    it.mijorus.gearlever
    net.davidotek.pupgui2
  )
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_programs_gnome() {
  step "Installing Flatpak programs for GNOME"
  local flatpaks=(
    com.mattjakeman.ExtensionManager
    io.github.shiftey.Desktop
    it.mijorus.gearlever
    com.vysp3r.ProtonPlus
  )
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_programs_cosmic() {
  step "Installing Flatpak programs for Cosmic"
  local flatpaks=(
    io.github.shiftey.Desktop
    it.mijorus.gearlever
    com.vysp3r.ProtonPlus
    dev.edfloreshz.CosmicTweaks
  )
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_minimal_kde() {
  step "Installing minimal Flatpak programs for KDE"
  local flatpaks=(
    it.mijorus.gearlever
  )
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_minimal_gnome() {
  step "Installing minimal Flatpak programs for GNOME"
  local flatpaks=(
    com.mattjakeman.ExtensionManager
    it.mijorus.gearlever
  )
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_minimal_cosmic() {
  step "Installing minimal Flatpak programs for Cosmic"
  local flatpaks=(
    it.mijorus.gearlever
    dev.edfloreshz.CosmicTweaks
  )
  install_flatpak_programs_list "${flatpaks[@]}"
}

install_flatpak_minimal_generic() {
  step "Installing minimal Flatpak programs (generic DE/WM)"
  local flatpaks=(
    it.mijorus.gearlever
  )
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
  if ! command -v dialog &>/dev/null; then
    echo -e "${YELLOW}The 'dialog' package is required for custom selection. Installing...${RESET}"
    sudo pacman -S --noconfirm dialog
    DIALOG_INSTALLED_BY_SCRIPT=true
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
else
  if [ -n "$flatpak_minimal_function" ]; then
    $flatpak_minimal_function
  else
    install_flatpak_minimal_generic
  fi
fi

install_aur_packages

if [[ "$DIALOG_INSTALLED_BY_SCRIPT" == "true" ]]; then
  echo -e "${YELLOW}Removing 'dialog' package as it is no longer needed...${RESET}"
  sudo pacman -Rns --noconfirm dialog
fi