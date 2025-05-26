#!/bin/bash

# ===== Colors for output =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ===== Step/Log helpers =====
CURRENT_STEP=1
ERRORS=()
INSTALLED_PKGS=()
REMOVED_PKGS=()

step() {
  echo -e "\n${CYAN}[$CURRENT_STEP] $1${RESET}"
  ((CURRENT_STEP++))
}

log_success() { echo -e "${GREEN}[OK] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_error()   { echo -e "${RED}[FAIL] $1${RESET}"; ERRORS+=("$1"); }

# ===== Program Lists =====
pacman_programs_default=(
  android-tools bat bleachbit btop bluez-utils cmatrix dmidecode dosfstools expac
  firefox fwupd gamemode gnome-disk-utility hwinfo inxi lib32-gamemode lib32-mangohud
  mangohud net-tools noto-fonts-extra ntfs-3g samba sl speedtest-cli sshfs
  ttf-hack-nerd ttf-liberation unrar wget xdg-desktop-portal-gtk
)
essential_programs_default=(
  discord filezilla gimp kdenlive libreoffice-fresh lutris obs-studio steam
  telegram-desktop timeshift vlc wine
)

pacman_programs_minimal=(
  android-tools bat bleachbit btop bluez-utils cmatrix dmidecode dosfstools expac
  firefox fwupd gnome-disk-utility hwinfo inxi net-tools noto-fonts-extra ntfs-3g
  samba sl speedtest-cli sshfs ttf-hack-nerd ttf-liberation unrar wget xdg-desktop-portal-gtk
)
essential_programs_minimal=(
  libreoffice-fresh timeshift vlc
)

kde_install_programs=(gwenview kdeconnect kwalletmanager kvantum okular power-profiles-daemon python-pyqt5 python-pyqt6 qbittorrent spectacle)
kde_remove_programs=(htop)
gnome_install_programs=(celluloid dconf-editor gnome-tweaks gufw seahorse transmission-gtk)
gnome_remove_programs=(epiphany gnome-contacts gnome-maps gnome-music gnome-tour htop snapshot totem)
cosmic_install_programs=(power-profiles-daemon transmission-gtk)
cosmic_remove_programs=(htop)

yay_programs_default=(brave-bin heroic-games-launcher-bin megasync-bin spotify stacer-bin stremio teamviewer via-bin)

# ===== Main Menu =====
show_menu() {
  echo -e "${YELLOW}User Program Installer${RESET}"
  echo "Select installation mode:"
  echo "  1) Default (Recommended, full set)"
  echo "  2) Minimal (Smaller set)"
  echo "  3) Exit"
  while true; do
    read -p "Enter your choice [1-3]: " menu_choice
    case "$menu_choice" in
      1) INSTALL_MODE="default"; break ;;
      2) INSTALL_MODE="minimal"; break ;;
      3) echo -e "${CYAN}Exiting.${RESET}"; exit 0 ;;
      *) echo -e "${RED}Invalid choice! Please enter 1, 2, or 3.${RESET}" ;;
    esac
  done
  echo -e "${CYAN}Selected mode: $INSTALL_MODE${RESET}"
}

# ===== Helper functions =====
is_package_installed() { command -v "$1" &>/dev/null; }

handle_error() {
  if [ $? -ne 0 ]; then
    log_error "$1"
    return 1
  fi
  return 0
}

check_yay() {
  if ! command -v yay &>/dev/null; then
    log_error "yay (AUR helper) is not installed. Please install yay and rerun."
    exit 1
  fi
}

detect_desktop_environment() {
  case "$XDG_CURRENT_DESKTOP" in
    KDE)
      log_success "KDE detected."
      specific_install_programs=("${kde_install_programs[@]}")
      specific_remove_programs=("${kde_remove_programs[@]}")
      flatpak_install_function="install_flatpak_programs_kde"
      ;;
    GNOME)
      log_success "GNOME detected."
      specific_install_programs=("${gnome_install_programs[@]}")
      specific_remove_programs=("${gnome_remove_programs[@]}")
      flatpak_install_function="install_flatpak_programs_gnome"
      ;;
    COSMIC)
      log_success "Cosmic DE detected."
      specific_install_programs=("${cosmic_install_programs[@]}")
      specific_remove_programs=("${cosmic_remove_programs[@]}")
      flatpak_install_function="install_flatpak_programs_cosmic"
      ;;
    *)
      log_warning "No KDE, GNOME, or Cosmic detected."
      specific_install_programs=()
      specific_remove_programs=()
      # Fallback: if default chosen, switch program lists to minimal and use generic minimal flatpak
      if [[ "$INSTALL_MODE" == "default" ]]; then
        log_warning "Falling back to minimal set for unsupported DE/WM."
        pacman_programs=("${pacman_programs_minimal[@]}")
        essential_programs=("${essential_programs_minimal[@]}")
        flatpak_install_function="install_flatpak_minimal_generic"
      else
        flatpak_install_function="install_flatpak_minimal_generic"
      fi
      ;;
  esac
}

# ===== Install/Remove Functions =====
remove_programs() {
  step "Removing DE-specific programs"
  if [ ${#specific_remove_programs[@]} -eq 0 ]; then
    log_success "No specific programs to remove."
    return
  fi
  for program in "${specific_remove_programs[@]}"; do
    if is_package_installed "$program"; then
      sudo pacman -Rns --noconfirm "$program"
      if handle_error "Failed to remove $program."; then
        log_success "$program removed."
        REMOVED_PKGS+=("$program")
      fi
    else
      log_warning "$program not found. Skipping removal."
    fi
  done
}

install_pacman_programs() {
  step "Installing Pacman programs"
  local pkgs=("${pacman_programs[@]}" "${essential_programs[@]}" "${specific_install_programs[@]}")
  for program in "${pkgs[@]}"; do
    if ! is_package_installed "$program"; then
      sudo pacman -S --needed --noconfirm "$program"
      if handle_error "Failed to install $program."; then
        log_success "$program installed."
        INSTALLED_PKGS+=("$program")
      fi
    else
      log_warning "$program is already installed."
    fi
  done
}

install_flatpak_programs_kde() {
  step "Installing Flatpak programs for KDE"
  local flatpaks=(io.github.shiftey.Desktop it.mijorus.gearlever net.davidotek.pupgui2)
  for pkg in "${flatpaks[@]}"; do
    flatpak install -y flathub "$pkg"
    if handle_error "Failed to install Flatpak $pkg."; then
      log_success "$pkg (Flatpak) installed."
      INSTALLED_PKGS+=("$pkg (flatpak)")
    fi
  done
}
install_flatpak_programs_gnome() {
  step "Installing Flatpak programs for GNOME"
  local flatpaks=(com.mattjakeman.ExtensionManager io.github.shiftey.Desktop it.mijorus.gearlever com.vysp3r.ProtonPlus)
  for pkg in "${flatpaks[@]}"; do
    flatpak install -y flathub "$pkg"
    if handle_error "Failed to install Flatpak $pkg."; then
      log_success "$pkg (Flatpak) installed."
      INSTALLED_PKGS+=("$pkg (flatpak)")
    fi
  done
}
install_flatpak_programs_cosmic() {
  step "Installing Flatpak programs for Cosmic"
  local flatpaks=(io.github.shiftey.Desktop it.mijorus.gearlever com.vysp3r.ProtonPlus dev.edfloreshz.CosmicTweaks)
  for pkg in "${flatpaks[@]}"; do
    flatpak install -y flathub "$pkg"
    if handle_error "Failed to install Flatpak $pkg."; then
      log_success "$pkg (Flatpak) installed."
      INSTALLED_PKGS+=("$pkg (flatpak)")
    fi
  done
}

install_flatpak_minimal_kde() {
  step "Installing minimal Flatpak programs for KDE"
  local flatpaks=(it.mijorus.gearlever)
  for pkg in "${flatpaks[@]}"; do
    flatpak install -y flathub "$pkg"
    if handle_error "Failed to install Flatpak $pkg."; then
      log_success "$pkg (Flatpak) installed."
      INSTALLED_PKGS+=("$pkg (flatpak)")
    fi
  done
}
install_flatpak_minimal_gnome() {
  step "Installing minimal Flatpak programs for GNOME"
  local flatpaks=(com.mattjakeman.ExtensionManager it.mijorus.gearlever)
  for pkg in "${flatpaks[@]}"; do
    flatpak install -y flathub "$pkg"
    if handle_error "Failed to install Flatpak $pkg."; then
      log_success "$pkg (Flatpak) installed."
      INSTALLED_PKGS+=("$pkg (flatpak)")
    fi
  done
}
install_flatpak_minimal_cosmic() {
  step "Installing minimal Flatpak programs for Cosmic"
  local flatpaks=(it.mijorus.gearlever dev.edfloreshz.CosmicTweaks)
  for pkg in "${flatpaks[@]}"; do
    flatpak install -y flathub "$pkg"
    if handle_error "Failed to install Flatpak $pkg."; then
      log_success "$pkg (Flatpak) installed."
      INSTALLED_PKGS+=("$pkg (flatpak)")
    fi
  done
}
install_flatpak_minimal_generic() {
  step "Installing minimal Flatpak programs (generic DE/WM)"
  local flatpaks=(it.mijorus.gearlever)
  for pkg in "${flatpaks[@]}"; do
    flatpak install -y flathub "$pkg"
    if handle_error "Failed to install Flatpak $pkg."; then
      log_success "$pkg (Flatpak) installed."
      INSTALLED_PKGS+=("$pkg (flatpak)")
    fi
  done
}

install_aur_packages() {
  step "Installing AUR packages"
  for pkg in "${yay_programs[@]}"; do
    if ! is_package_installed "$pkg"; then
      yay -S --noconfirm "$pkg"
      if handle_error "Failed to install AUR $pkg."; then
        log_success "$pkg (AUR) installed."
        INSTALLED_PKGS+=("$pkg (AUR)")
      fi
    else
      log_warning "$pkg is already installed."
    fi
  done
}

install_amd_drivers() {
  step "Checking for AMD GPU (and drivers)"
  if lspci | grep -i "amd" &>/dev/null; then
    log_success "AMD GPU detected. Installing drivers..."
    local amd_drivers=(xf86-video-amdgpu mesa vulkan-radeon lib32-vulkan-radeon vulkan-icd-loader lib32-mesa)
    for pkg in "${amd_drivers[@]}"; do
      if ! is_package_installed "$pkg"; then
        sudo pacman -S --needed --noconfirm "$pkg"
        if handle_error "Failed to install $pkg."; then
          log_success "$pkg (AMD driver) installed."
          INSTALLED_PKGS+=("$pkg (driver)")
        fi
      else
        log_warning "$pkg is already installed."
      fi
    done
  else
    log_warning "No AMD GPU found. Skipping AMD drivers."
  fi
}

# ===== Summary =====
print_summary() {
  echo -e "\n${CYAN}======= PROGRAMS SUMMARY =======${RESET}"
  if [ ${#INSTALLED_PKGS[@]} -gt 0 ]; then
    echo -e "${GREEN}Installed:${RESET} ${INSTALLED_PKGS[*]}"
  else
    echo -e "${YELLOW}No new packages were installed.${RESET}"
  fi
  if [ ${#REMOVED_PKGS[@]} -gt 0 ]; then
    echo -e "${RED}Removed:${RESET} ${REMOVED_PKGS[*]}"
  else
    echo -e "${GREEN}No packages were removed.${RESET}"
  fi
  if [ ${#ERRORS[@]} -gt 0 ]; then
    echo -e "${RED}Errors:${RESET}"
    for err in "${ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  else
    echo -e "${GREEN}All steps completed successfully!${RESET}"
  fi
  echo -e "${CYAN}===============================${RESET}"
}

# ===== Main Run Function =====
run() {
  show_menu

  # Set program arrays based on mode
  case "$INSTALL_MODE" in
    default)
      pacman_programs=("${pacman_programs_default[@]}")
      essential_programs=("${essential_programs_default[@]}")
      yay_programs=()
      read -p "Install AUR packages? (y/n, default y): " install_yay
      install_yay=${install_yay:-y}
      if [[ "$install_yay" =~ ^[Yy]$ ]]; then
        yay_programs=("${yay_programs_default[@]}")
      fi
      ;;
    minimal)
      pacman_programs=("${pacman_programs_minimal[@]}")
      essential_programs=("${essential_programs_minimal[@]}")
      yay_programs=()
      ;;
  esac

  check_yay
  detect_desktop_environment
  remove_programs
  install_pacman_programs

  # Flatpak handling
  if [[ "$INSTALL_MODE" == "default" ]]; then
    if [ -n "$flatpak_install_function" ]; then
      $flatpak_install_function
    else
      log_warning "No Flatpak install function for your DE."
    fi
  else
    case "$XDG_CURRENT_DESKTOP" in
      KDE) install_flatpak_minimal_kde ;;
      GNOME) install_flatpak_minimal_gnome ;;
      COSMIC) install_flatpak_minimal_cosmic ;;
      *) install_flatpak_minimal_generic ;;
    esac
  fi

  if [ ${#yay_programs[@]} -gt 0 ]; then
    install_aur_packages
  fi

  install_amd_drivers

  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run
fi
