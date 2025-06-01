#!/bin/bash
set -euo pipefail

# =========================
#  Arch Linux Installer
#  Automated setup script
# =========================

# --- Color variables for output formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# --- Global arrays and variables ---
ERRORS=()                # Collects error messages for summary
CURRENT_STEP=1           # Tracks current step for progress display
INSTALLED_PACKAGES=()    # Tracks installed packages
REMOVED_PACKAGES=()      # Tracks removed packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Script directory
CONFIGS_DIR="$SCRIPT_DIR/configs"                           # Config files directory
SCRIPTS_DIR="$SCRIPT_DIR/scripts"                           # Custom scripts directory

HELPER_UTILS=(base-devel curl eza fastfetch figlet flatpak fzf git openssh pacman-contrib reflector rsync zoxide)  # Helper utilities to install

INSTALL_MODE=""  # <-- Ensure this is always defined

# =========================
#  Utility/Helper Functions
# =========================

figlet_banner() {
  local title="$1"
  echo -e "${CYAN}\n============================================================${RESET}"
  if command -v figlet >/dev/null; then
    figlet "$title"
  else
    echo -e "${CYAN}========== $title ==========${RESET}"
  fi
}

arch_ascii() {
  echo -e "${CYAN}"
  cat << "EOF"
      _             _     ___           _        _ _
     / \   _ __ ___| |__ |_ _|_ __  ___| |_ __ _| | | ___ _ __
    / _ \ | '__/ __| '_ \ | || '_ \/ __| __/ _` | | |/ _ \ '__|
   / ___ \| | | (__| | | || || | | \__ \ || (_| | | |  __/ |
  /_/   \_\_|  \___|_| |_|___|_| |_|___/\__\__,_|_|_|\___|_|

EOF
  echo -e "${RESET}"
}

show_menu() {
  echo -e "${YELLOW}Welcome to the Arch Installer script!${RESET}"
  echo "Please select your installation mode:"
  echo "  1) Default (Full setup)"
  echo "  2) Minimal (Core utilities only)"
  echo "  3) Exit"

  while true; do
    read -r -p "Enter your choice [1-3]: " menu_choice
    case "$menu_choice" in
      1) 
        INSTALL_MODE="default"
        echo -e "${CYAN}Selected mode: $INSTALL_MODE${RESET}"
        break 
        ;;
      2) 
        INSTALL_MODE="minimal"
        echo -e "${CYAN}Selected mode: $INSTALL_MODE${RESET}"
        break 
        ;;
      3) 
        echo -e "${CYAN}Exiting the installer. Goodbye!${RESET}"
        exit 0 
        ;;
      *) 
        echo -e "${RED}Invalid choice! Please enter 1, 2, or 3.${RESET}" 
        ;;
    esac
  done
}

step() {
  echo -e "${CYAN}\n============================================================${RESET}"
  figlet_banner "$1"
  echo -e "\n${CYAN}[${CURRENT_STEP}] $1${RESET}"
  ((CURRENT_STEP++))
}

log_success() { echo -e "\n${GREEN}[OK] $1${RESET}\n"; }
log_warning() { echo -e "\n${YELLOW}[WARN] $1${RESET}\n"; }
log_error()   { echo -e "\n${RED}[FAIL] $1${RESET}\n"; ERRORS+=("$1"); }

run_step() {
  local description="$1"
  shift
  step "$description"
  "$@"
  local status=$?
  if [ $status -eq 0 ]; then
    log_success "$description"
    if [[ "$description" == "Installing helper utilities" ]]; then
      INSTALLED_PACKAGES+=("${HELPER_UTILS[@]}")
    elif [[ "$description" == "Installing UFW firewall" ]]; then
      INSTALLED_PACKAGES+=("ufw")
    elif [[ "$description" =~ ^Installing\  ]]; then
      local pkg
      pkg=$(echo "$description" | awk '{print $2}')
      INSTALLED_PACKAGES+=("$pkg")
    elif [[ "$description" == "Removing figlet" ]]; then
      REMOVED_PACKAGES+=("figlet")
    fi
  else
    log_error "$description"
  fi
}

# =========================
#  Main Installation Steps
# =========================

check_prerequisites() {
  step "Checking system prerequisites"
  if [[ $EUID -eq 0 ]]; then
    log_error "Do not run this script as root. Please run as a regular user with sudo privileges."
    exit 1
  fi
  if ! command -v pacman >/dev/null; then
    log_error "This script is intended for Arch Linux systems with pacman."
    exit 1
  fi
  log_success "Prerequisites OK."
}

install_helper_utils() {
  local to_install=()
  for util in "${HELPER_UTILS[@]}"; do
    if ! command -v "$util" >/dev/null; then
      to_install+=("$util")
    else
      log_warning "$util is already installed. Skipping."
    fi
  done
  if [ "${#to_install[@]}" -gt 0 ]; then
    run_step "Installing helper utilities" sudo pacman -S --needed --noconfirm "${to_install[@]}"
    INSTALLED_PACKAGES+=("${to_install[@]}")
  fi
}

configure_pacman() {
  run_step "Configuring Pacman" sudo sed -i 's/^#Color/Color/; s/^#VerbosePkgLists/VerbosePkgLists/; s/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
  run_step "Enable ILoveCandy" bash -c "grep -q ILoveCandy /etc/pacman.conf || sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf"
  run_step "Enabling multilib repo" bash -c '
    if grep -q "^\[multilib\]" /etc/pacman.conf; then
      exit 0
    elif grep -q "^#\[multilib\]" /etc/pacman.conf; then
      sudo sed -i "/^#\\[multilib\\]/,/^#Include/s/^#//" /etc/pacman.conf
    else
      echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
    fi
  '
}

update_mirrors_and_system() {
  run_step "Updating mirrorlist" sudo reflector --verbose --protocol https --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
  run_step "System update" sudo pacman -Syyu --noconfirm
}

set_sudo_pwfeedback() {
  if ! sudo grep -q '^Defaults.*pwfeedback' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    run_step "Enabling sudo password feedback" bash -c "echo 'Defaults env_reset,pwfeedback' | sudo EDITOR='tee -a' visudo"
  else
    log_warning "sudo pwfeedback already enabled. Skipping."
  fi
}

install_cpu_microcode() {
  step "Detecting CPU and installing appropriate microcode"
  local pkg=""
  if grep -q "Intel" /proc/cpuinfo; then
    log_success "Intel CPU detected. Installing intel-ucode."
    pkg="intel-ucode"
  elif grep -q "AMD" /proc/cpuinfo; then
    log_success "AMD CPU detected. Installing amd-ucode."
    pkg="amd-ucode"
  else
    log_warning "Unable to determine CPU type. No microcode package will be installed."
  fi

  if [ -n "$pkg" ]; then
    if pacman -Q "$pkg" &>/dev/null; then
      log_warning "$pkg is already installed. Skipping."
    else
      if sudo pacman -S --needed --noconfirm "$pkg"; then
        log_success "$pkg installed successfully."
        INSTALLED_PACKAGES+=("$pkg")
      else
        log_error "Failed to install $pkg."
      fi
    fi
  fi
}

get_installed_kernel_types() {
  local kernel_types=()
  pacman -Q linux &>/dev/null && kernel_types+=("linux")
  pacman -Q linux-lts &>/dev/null && kernel_types+=("linux-lts")
  pacman -Q linux-zen &>/dev/null && kernel_types+=("linux-zen")
  pacman -Q linux-hardened &>/dev/null && kernel_types+=("linux-hardened")
  echo "${kernel_types[@]}"
}

install_kernel_headers_for_all() {
  step "Installing kernel headers for all installed kernels"
  local kernel_types
  kernel_types=($(get_installed_kernel_types))
  if [ "${#kernel_types[@]}" -eq 0 ]; then
    log_warning "No supported kernel types detected. Please check your system configuration."
    return
  fi
  for kernel in "${kernel_types[@]}"; do
    local headers_package="${kernel}-headers"
    if sudo pacman -S --needed --noconfirm "$headers_package"; then
      log_success "$headers_package installed successfully."
      INSTALLED_PACKAGES+=("$headers_package")
    else
      log_error "Error: Failed to install $headers_package."
    fi
  done
}

generate_locales() {
  run_step "Generating locales" bash -c "sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen && sudo locale-gen"
}

setup_zsh() {
  if ! command -v zsh >/dev/null; then
    run_step "Installing ZSH and plugins" sudo pacman -S --needed --noconfirm zsh zsh-autosuggestions zsh-syntax-highlighting
    INSTALLED_PACKAGES+=("zsh" "zsh-autosuggestions" "zsh-syntax-highlighting")
  else
    log_warning "zsh is already installed. Skipping."
  fi
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    run_step "Installing Oh-My-Zsh" bash -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
  else
    log_warning "Oh-My-Zsh is already installed. Skipping."
  fi
  run_step "Changing shell to ZSH" sudo chsh -s "$(command -v zsh)" "$USER"
  if [ -f "$CONFIGS_DIR/.zshrc" ]; then
    run_step "Configuring .zshrc" cp "$CONFIGS_DIR/.zshrc" "$HOME/"
  fi
}

install_starship() {
  if ! command -v starship >/dev/null; then
    run_step "Installing starship prompt" sudo pacman -S --needed --noconfirm starship
  else
    log_warning "starship is already installed. Skipping installation."
  fi

  mkdir -p "$HOME/.config"

  if [ -f "$HOME/.config/starship.toml" ]; then
    log_warning "starship.toml already exists in $HOME/.config/, skipping move."
  elif [ -f "$CONFIGS_DIR/starship.toml" ]; then
    mv "$CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml"
    log_success "starship.toml moved to $HOME/.config/"
  else
    log_warning "starship.toml not found in $CONFIGS_DIR/"
  fi
}

run_custom_scripts() {
  if [ -f "$SCRIPTS_DIR/setup_plymouth.sh" ]; then
    chmod +x "$SCRIPTS_DIR/setup_plymouth.sh"
    run_step "Setting up Plymouth boot splash" "$SCRIPTS_DIR/setup_plymouth.sh"
  fi

  if [ -f "$SCRIPTS_DIR/install_yay.sh" ]; then
    chmod +x "$SCRIPTS_DIR/install_yay.sh"
    run_step "Installing yay (AUR helper)" "$SCRIPTS_DIR/install_yay.sh"
  fi

  if [ -f "$SCRIPTS_DIR/programs.sh" ]; then
    chmod +x "$SCRIPTS_DIR/programs.sh"
    if [[ "$INSTALL_MODE" == "minimal" ]]; then
      run_step "Installing minimal user programs" "$SCRIPTS_DIR/programs.sh" -m
    else
      run_step "Installing default user programs" "$SCRIPTS_DIR/programs.sh" -d
    fi
  fi

  if [ -f "$SCRIPTS_DIR/fail2ban.sh" ]; then
    figlet_banner "Fail2ban"
    chmod +x "$SCRIPTS_DIR/fail2ban.sh"
    run_step "Configuring fail2ban" "$SCRIPTS_DIR/fail2ban.sh"
  fi
}

make_systemd_boot_silent() {
  step "Making Systemd-Boot silent for all installed kernels"
  local ENTRIES_DIR="/boot/loader/entries"
  local kernel_types
  kernel_types=($(get_installed_kernel_types))
  for kernel in "${kernel_types[@]}"; do
    local linux_entry
    linux_entry=$(find "$ENTRIES_DIR" -type f -name "*${kernel}.conf" ! -name '*fallback.conf' -print -quit)
    if [ -z "$linux_entry" ]; then
      log_warning "Linux entry not found for kernel: $kernel"
      continue
    fi
    if sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$linux_entry"; then
      log_success "Silent boot options added to Linux entry: $(basename "$linux_entry")."
    else
      log_error "Failed to modify Linux entry: $(basename "$linux_entry")."
    fi
  done
}

change_loader_conf() {
  step "Changing loader.conf"
  local LOADER_CONF="/boot/loader/loader.conf"
  if [ ! -f "$LOADER_CONF" ]; then
    log_warning "loader.conf not found at $LOADER_CONF"
    return
  fi

  sudo sed -i '/^default /d' "$LOADER_CONF"
  sudo sed -i '1i default @saved' "$LOADER_CONF"

  if grep -q '^timeout' "$LOADER_CONF"; then
    sudo sed -i 's/^timeout.*/timeout 3/' "$LOADER_CONF"
  else
    echo "timeout 3" | sudo tee -a "$LOADER_CONF" >/dev/null
  fi

  if grep -Eq '^[#]*console-mode[[:space:]]+keep' "$LOADER_CONF"; then
    sudo sed -i 's/^[#]*console-mode[[:space:]]\+keep/console-mode max/' "$LOADER_CONF"
  elif grep -Eq '^[#]*console-mode[[:space:]]+.*' "$LOADER_CONF"; then
    sudo sed -i 's/^[#]*console-mode[[:space:]]\+.*/console-mode max/' "$LOADER_CONF"
  else
    echo "console-mode max" | sudo tee -a "$LOADER_CONF" >/dev/null
  fi

  log_success "Loader configuration updated."
}

remove_fallback_entries() {
  step "Removing fallback entries from systemd-boot"
  local ENTRIES_DIR="/boot/loader/entries"
  local entries_removed=0

  # Check if directory exists
  if [ ! -d "$ENTRIES_DIR" ]; then
    log_warning "Entries directory $ENTRIES_DIR does not exist"
    return 0
  fi

  shopt -s nullglob
  for entry in "$ENTRIES_DIR"/*fallback.conf; do
    [ -f "$entry" ] || continue
    if sudo rm "$entry"; then
      log_success "Removed fallback entry: $(basename "$entry")"
      entries_removed=1
    else
      log_error "Failed to remove fallback entry: $(basename "$entry")"
    fi
  done
  shopt -u nullglob

  if [ $entries_removed -eq 0 ]; then
    log_warning "No fallback entries found to remove."
  fi

  return 0  # Explicitly return success
}

setup_fastfetch_config() {
  if command -v fastfetch >/dev/null; then
    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
      log_warning "fastfetch config already exists. Skipping generation."
    else
      run_step "Creating fastfetch config" bash -c 'fastfetch --gen-config'
    fi
    if [ -f "$CONFIGS_DIR/config.jsonc" ]; then
      mkdir -p "$HOME/.config/fastfetch"
      cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
    fi
  fi
}

setup_firewall_and_services() {
  run_step "Installing UFW firewall" sudo pacman -S --needed --noconfirm ufw
  run_step "Enabling firewall" sudo ufw enable

  local services=(
    "bluetooth"
    "cronie"
    "ufw"
    "fstrim.timer"
    "paccache.timer"
    "reflector.service"
    "reflector.timer"
    "sshd"
    "teamviewerd.service"
    "power-profiles-daemon.service"
  )

  for service in "${services[@]}"; do
    if [ -f "/usr/lib/systemd/system/$service" ] || [ -f "/etc/systemd/system/$service" ]; then
      run_step "Enabling $service" sudo systemctl enable --now "$service"
    else
      log_warning "$service is not installed or not available as a systemd service. Skipping."
    fi
  done
}

cleanup_helpers() {
  run_step "Cleaning yay build dir" sudo rm -rf /tmp/yay
}

detect_and_install_gpu_drivers() {
  step "Detecting GPU and installing appropriate drivers"
  local GPU_INFO
  GPU_INFO=$(lspci | grep -E "VGA|3D")
  if echo "$GPU_INFO" | grep -qi nvidia; then
    echo -e "${YELLOW}NVIDIA GPU detected!${RESET}"
    echo "Choose a driver to install:"
    echo "  1) Latest proprietary (nvidia-dkms)"
    echo "  2) Legacy 390xx (AUR, very old cards)"
    echo "  3) Legacy 340xx (AUR, ancient cards)"
    echo "  4) Open-source Nouveau (recommended for unsupported/old cards)"
    echo "  5) Skip GPU driver installation"
    read -r -p "Enter your choice [1-5, default 4]: " nvidia_choice
    case "$nvidia_choice" in
      1)
        run_step "Installing NVIDIA DKMS driver" sudo pacman -S --noconfirm nvidia-dkms nvidia-utils
        ;;
      2)
        run_step "Installing NVIDIA 390xx legacy DKMS driver" yay -S --noconfirm --needed nvidia-390xx-dkms nvidia-390xx-utils lib32-nvidia-390xx-utils
        ;;
      3)
        run_step "Installing NVIDIA 340xx legacy DKMS driver" yay -S --noconfirm --needed nvidia-340xx-dkms nvidia-340xx-utils lib32-nvidia-340xx-utils
        ;;
      5)
        echo -e "${YELLOW}Skipping NVIDIA driver installation.${RESET}"
        ;;
      ""|4|*)
        run_step "Installing open-source Nouveau driver for NVIDIA" sudo pacman -S --noconfirm xf86-video-nouveau mesa
        ;;
    esac
  elif echo "$GPU_INFO" | grep -qi amd; then
    run_step "Installing AMDGPU drivers" sudo pacman -S --noconfirm xf86-video-amdgpu mesa
  elif echo "$GPU_INFO" | grep -qi intel; then
    run_step "Installing Intel graphics drivers" sudo pacman -S --noconfirm mesa xf86-video-intel
  else
    log_warning "No supported GPU detected or unable to determine GPU vendor."
  fi
}

remove_orphans() {
  orphans=$(pacman -Qtdq 2>/dev/null || true)
  if [[ -n "$orphans" ]]; then
    sudo pacman -Rns --noconfirm $orphans
  else
    echo "No orphaned packages to remove."
  fi
}

setup_maintenance() {
  if command -v paccache >/dev/null; then
    run_step "Cleaning pacman cache (keep last 3 packages)" sudo paccache -r
  else
    log_warning "paccache not found. Skipping paccache cache cleaning."
  fi
  run_step "Removing orphaned packages" remove_orphans
  run_step "System update" sudo pacman -Syu --noconfirm
  if command -v yay >/dev/null; then
    run_step "AUR update (yay)" yay -Syu --noconfirm
  fi
}

cleanup_and_optimize() {
  step "Performing final cleanup and optimizations"
  if lsblk -d -o rota | grep -q '^0$'; then
    run_step "Running fstrim on SSDs" sudo fstrim -v /
  fi
  run_step "Cleaning /tmp directory" sudo rm -rf /tmp/*

  if [[ -d "$SCRIPT_DIR" ]]; then
    if [ "${#ERRORS[@]}" -eq 0 ]; then
      cd "$HOME"
      run_step "Deleting installer directory" rm -rf "$SCRIPT_DIR"
    else
      echo -e "\n${YELLOW}Issues detected during installation. The installer folder and install.log will NOT be deleted.${RESET}\n"
      echo -e "${RED}ERROR: One or more steps failed. Please check the log for details:${RESET}"
      echo -e "${CYAN}$SCRIPT_DIR/install.log${RESET}\n"
    fi
  fi

  run_step "Syncing disk writes" sync
}

print_summary() {
  figlet_banner "Install Summary"
  echo -e "${CYAN}========= INSTALL SUMMARY =========${RESET}"
  if [ "${#INSTALLED_PACKAGES[@]}" -gt 0 ]; then
    echo -e "${GREEN}Installed:${RESET} ${INSTALLED_PACKAGES[*]}"
  else
    echo -e "${YELLOW}No new packages were installed.${RESET}"
  fi
  if [ "${#REMOVED_PACKAGES[@]}" -gt 0 ]; then
    echo -e "${RED}Removed:${RESET} ${REMOVED_PACKAGES[*]}"
  else
    echo -e "${GREEN}No packages were removed.${RESET}"
  fi
  echo -e "${CYAN}===================================${RESET}"
  if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo -e "\n${RED}The following steps failed:${RESET}\n"
    for err in "${ERRORS[@]}"; do
      echo -e "${YELLOW}  - $err${RESET}"
    done
    echo -e "\n${YELLOW}Check the install log for more details: ${CYAN}$SCRIPT_DIR/install.log${RESET}\n"
  else
    echo -e "\n${GREEN}All steps completed successfully!${RESET}\n"
  fi
}

prompt_reboot() {
  figlet_banner "Reboot System"
  echo -e "${YELLOW}Setup is complete. It's strongly recommended to reboot your system now."
  echo -e "If you encounter issues, review the install log: ${CYAN}$SCRIPT_DIR/install.log${RESET}\n"
  while true; do
    read -r -p "$(echo -e "${YELLOW}Reboot now? [Y/n]: ${RESET}")" reboot_ans
    reboot_ans=${reboot_ans,,}
    case "$reboot_ans" in
      ""|y|yes)
        echo -e "\n${CYAN}Rebooting...${RESET}\n"
        sudo reboot
        break
        ;;
      n|no)
        echo -e "\n${YELLOW}Reboot skipped. You can reboot manually at any time using \`sudo reboot\`.${RESET}\n"
        break
        ;;
      *)
        echo -e "\n${RED}Please answer Y (yes) or N (no).${RESET}\n"
        ;;
    esac
  done
}

# =========================
#  Main Function
# =========================

main() {
  clear
  arch_ascii
  show_menu

  # Reset current step counter
  CURRENT_STEP=1

  # Ask for sudo password up front
  echo -e "\n${YELLOW}Please enter your sudo password to begin the installation (it will not be echoed):${RESET}"
  sudo -v
  if [ $? -ne 0 ]; then
    echo -e "${RED}Incorrect password or sudo privileges required. Exiting.${RESET}"
    exit 1
  fi

  # Keep sudo alive and trap to kill it on exit
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

  # Log all output to install.log
  exec > >(tee -a "$SCRIPT_DIR/install.log") 2>&1

  echo -e "\n${GREEN}Starting installation with mode: $INSTALL_MODE${RESET}\n"

  # --- Main installation steps in recommended order ---
  check_prerequisites
  install_helper_utils
  configure_pacman
  update_mirrors_and_system
  set_sudo_pwfeedback
  install_cpu_microcode
  install_kernel_headers_for_all
  generate_locales
  setup_zsh
  install_starship
  run_custom_scripts
  make_systemd_boot_silent
  change_loader_conf
  remove_fallback_entries
  setup_fastfetch_config
  setup_firewall_and_services
  cleanup_helpers
  detect_and_install_gpu_drivers
  setup_maintenance
  cleanup_and_optimize
  print_summary
  prompt_reboot
}

main "$@"