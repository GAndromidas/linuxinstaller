#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# ===== Output Functions =====
step()   { echo -e "\n${CYAN}[$CURRENT_STEP] $1${RESET}"; ((CURRENT_STEP++)); }
log_success() { echo -e "${GREEN}[OK] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_error()   { echo -e "${RED}[FAIL] $1${RESET}"; PROGRAMS_ERRORS+=("$1"); }

# ===== Program Lists =====
pacman_programs_default=(android-tools bat bleachbit btop cmatrix dosfstools expac firefox fwupd gamemode gnome-disk-utility hwinfo inxi lib32-gamemode lib32-mangohud mangohud net-tools noto-fonts-extra ntfs-3g samba sl speedtest-cli sshfs ttf-hack-nerd ttf-liberation unrar xdg-desktop-portal-gtk)
essential_programs_default=(discord filezilla gimp kdenlive libreoffice-fresh lutris obs-studio steam timeshift vlc wine)
pacman_programs_minimal=(android-tools bat bleachbit btop cmatrix dosfstools expac firefox fwupd gamemode gnome-disk-utility hwinfo inxi lib32-gamemode net-tools noto-fonts-extra ntfs-3g samba sl speedtest-cli sshfs ttf-hack-nerd ttf-liberation unrar xdg-desktop-portal-gtk)
essential_programs_minimal=(libreoffice-fresh timeshift vlc)
kde_install_programs=(gwenview kdeconnect kwalletmanager kvantum okular power-profiles-daemon python-pyqt5 python-pyqt6 qbittorrent spectacle)
kde_remove_programs=(htop)
gnome_install_programs=(celluloid dconf-editor gnome-tweaks gufw seahorse transmission-gtk)
gnome_remove_programs=(epiphany gnome-contacts gnome-maps gnome-music gnome-tour htop snapshot totem)
cosmic_install_programs=(power-profiles-daemon transmission-gtk)
cosmic_remove_programs=(htop)
yay_programs_default=(heroic-games-launcher-bin megasync-bin spotify stremio via-bin)
yay_programs_minimal=(stremio)

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
print_programs_summary

show_menu
export INSTALL_MODE