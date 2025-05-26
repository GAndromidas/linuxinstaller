#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

ERRORS=()
CURRENT_STEP=1
TOTAL_STEPS=27

INSTALLED_PACKAGES=()
REMOVED_PACKAGES=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

HELPER_UTILS=(figlet fastfetch fzf reflector rsync git curl base-devel zoxide eza)
REMOVE_AFTER_INSTALL=()

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
    read -p "Enter your choice [1-3]: " menu_choice
    case "$menu_choice" in
      1) INSTALL_MODE="default"; break ;;
      2) INSTALL_MODE="minimal"; break ;;
      3) echo -e "${CYAN}Exiting the installer. Goodbye!${RESET}"; exit 0 ;;
      *) echo -e "${RED}Invalid choice! Please enter 1, 2, or 3.${RESET}" ;;
    esac
  done
  echo -e "${CYAN}Selected mode: $INSTALL_MODE${RESET}"
}

step() {
  echo -e "\n${CYAN}[$CURRENT_STEP/$TOTAL_STEPS] $1${RESET}"
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
      local pkg=$(echo "$description" | awk '{print $2}')
      INSTALLED_PACKAGES+=("$pkg")
    elif [[ "$description" == "Removing figlet" ]]; then
      REMOVED_PACKAGES+=("figlet")
    fi
  else
    log_error "$description"
  fi
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
  if [ ${#to_install[@]} -gt 0 ]; then
    run_step "Installing helper utilities" sudo pacman -S --needed --noconfirm "${to_install[@]}"
    INSTALLED_PACKAGES+=("${to_install[@]}")
  fi
}

configure_pacman() {
  run_step "Configuring Pacman" sudo sed -i 's/^#Color/Color/; s/^#VerbosePkgLists/VerbosePkgLists/; s/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
  run_step "Enable ILoveCandy" bash -c "grep -q ILoveCandy /etc/pacman.conf || sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf"
  run_step "Enabling multilib repo" bash -c \
    "if ! grep -q '^\[multilib\]' /etc/pacman.conf; then \
      echo -e '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' | sudo tee -a /etc/pacman.conf >/dev/null ; \
     elif grep -q '^#\[multilib\]' /etc/pacman.conf; then \
      sudo sed -i '/^#\[multilib\]/,/^#Include/s/^#//' /etc/pacman.conf ; \
     fi"
}

update_mirrors_and_system() {
  run_step "Updating mirrorlist" sudo reflector --verbose --protocol https --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
  run_step "System update" sudo pacman -Syyu --noconfirm
}

install_yay() {
  if ! command -v yay >/dev/null; then
    run_step "Installing yay (AUR helper)" bash -c 'cd /tmp && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm && cd .. && rm -rf yay'
    INSTALLED_PACKAGES+=(yay)
  else
    log_warning "yay is already installed. Skipping."
  fi
}

setup_zsh() {
  if ! command -v zsh >/dev/null; then
    run_step "Installing ZSH and plugins" sudo pacman -S --needed --noconfirm zsh zsh-autosuggestions zsh-syntax-highlighting
    INSTALLED_PACKAGES+=(zsh zsh-autosuggestions zsh-syntax-highlighting)
  else
    log_warning "zsh is already installed. Skipping."
  fi
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    run_step "Installing Oh-My-Zsh" bash -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
  else
    log_warning "Oh-My-Zsh is already installed. Skipping."
  fi
  run_step "Changing shell to ZSH" sudo chsh -s "$(which zsh)" "$USER"
  if [ -f "$CONFIGS_DIR/.zshrc" ]; then
    run_step "Configuring .zshrc" cp "$CONFIGS_DIR/.zshrc" "$HOME/"
  fi
}

install_starship() {
    # Install starship prompt if not already installed
    if ! command -v starship >/dev/null; then
        run_step "Installing starship prompt" sudo pacman -S --needed --noconfirm starship
    else
        log_warning "starship is already installed. Skipping installation."
    fi

    mkdir -p "$HOME/.config"

    # Only move config if it doesn't already exist
    if [ -f "$HOME/.config/starship.toml" ]; then
        log_warning "starship.toml already exists in $HOME/.config/, skipping move."
    elif [ -f "$CONFIGS_DIR/starship.toml" ]; then
        mv "$CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml"
        log_success "starship.toml moved to $HOME/.config/"
    else
        log_warning "starship.toml not found in $CONFIGS_DIR/"
    fi
}

generate_locales() {
  run_step "Generating locales" bash -c "sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen && sudo locale-gen"
}

run_custom_scripts() {
  echo "SCRIPTS_DIR: $SCRIPTS_DIR"
  ls -l "$SCRIPTS_DIR"
  if [ -f "$SCRIPTS_DIR/setup_plymouth.sh" ]; then
    chmod +x "$SCRIPTS_DIR/setup_plymouth.sh"
    run_step "Setting up Plymouth boot splash" "$SCRIPTS_DIR/setup_plymouth.sh"
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
    if command -v figlet >/dev/null; then
      figlet "Fail2ban"
    else
      echo -e "${YELLOW}========== Fail2ban ==========${RESET}"
    fi
    while true; do
      read -rp "$(echo -e "${YELLOW}Install & configure Fail2ban? [Y/n]: ${RESET}")" fail2ban_ans
      fail2ban_ans=${fail2ban_ans,,}
      case "$fail2ban_ans" in
        ""|y|yes)
          chmod +x "$SCRIPTS_DIR/fail2ban.sh"
          run_step "Configuring fail2ban" "$SCRIPTS_DIR/fail2ban.sh"
          break
          ;;
        n|no)
          log_warning "Skipped Fail2ban installation."
          break
          ;;
        *)
          echo -e "${RED}Please answer Y (yes) or N (no).${RESET}"
          ;;
      esac
    done
  fi
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

  # List of services (systemd units)
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
    # Only enable if the systemd unit file exists in standard locations
    if [ -f "/usr/lib/systemd/system/$service" ] || [ -f "/etc/systemd/system/$service" ]; then
      run_step "Enabling $service" sudo systemctl enable --now "$service"
    else
      log_warning "$service is not installed or not available as a systemd service. Skipping."
    fi
  done
}

set_sudo_pwfeedback() {
  run_step "Enabling sudo password feedback" bash -c "echo 'Defaults env_reset,pwfeedback' | sudo EDITOR='tee -a' visudo"
}

cleanup_helpers() {
  run_step "Cleaning yay build dir" sudo rm -rf /tmp/yay
}

detect_and_install_gpu_drivers() {
  echo -e "${CYAN}Detecting GPU and installing appropriate drivers...${RESET}"
  GPU_INFO=$(lspci | grep -E "VGA|3D")
  if echo "$GPU_INFO" | grep -qi nvidia; then
    echo -e "${YELLOW}NVIDIA GPU detected!${RESET}"
    echo "Choose a driver to install:"
    echo "  1) Latest proprietary (nvidia-dkms)"
    echo "  2) Legacy 390xx (AUR, very old cards)"
    echo "  3) Legacy 340xx (AUR, ancient cards)"
    echo "  4) Open-source Nouveau (recommended for unsupported/old cards)"
    echo "  5) Skip GPU driver installation"
    read -p "Enter your choice [1-5, default 4]: " nvidia_choice
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

setup_maintenance() {
  if command -v paccache >/dev/null; then
    run_step "Cleaning pacman cache (keep last 3 packages)" sudo paccache -r
  else
    log_warning "paccache not found. Skipping paccache cache cleaning."
  fi
  run_step "Removing orphaned packages" bash -c 'orphans=$(pacman -Qtdq); if [[ -n "$orphans" ]]; then sudo pacman -Rns --noconfirm $orphans; fi'
  run_step "System update" sudo pacman -Syu --noconfirm
  if command -v yay >/dev/null; then
    run_step "AUR update (yay)" yay -Syu --noconfirm
  fi
}

cleanup_and_optimize() {
  echo -e "${CYAN}Performing final cleanup and optimizations...${RESET}"

  if lsblk -d -o rota | grep -q '^0$'; then
    run_step "Running fstrim on SSDs" sudo fstrim -v /
  fi
  run_step "Cleaning /tmp directory" sudo rm -rf /tmp/*

  if [[ -d "$SCRIPT_DIR" ]]; then
    if [ ${#ERRORS[@]} -eq 0 ]; then
      cd ~
      run_step "Deleting installer directory" rm -rf "$SCRIPT_DIR"
    else
      echo -e "\n${YELLOW}Issues detected during installation. The installer folder and install.log will NOT be deleted."
      echo -e "Please review $SCRIPT_DIR/install.log for troubleshooting.${RESET}\n"
    fi
  fi

  run_step "Syncing disk writes" sync
}

print_summary() {
  echo -e "\n${CYAN}========= INSTALL SUMMARY =========${RESET}"
  if [ ${#INSTALLED_PACKAGES[@]} -gt 0 ]; then
    echo -e "${GREEN}Installed:${RESET} ${INSTALLED_PACKAGES[*]}"
  else
    echo -e "${YELLOW}No new packages were installed.${RESET}"
  fi
  if [ ${#REMOVED_PACKAGES[@]} -gt 0 ]; then
    echo -e "${RED}Removed:${RESET} ${REMOVED_PACKAGES[*]}"
  else
    echo -e "${GREEN}No packages were removed.${RESET}"
  fi
  echo -e "${CYAN}===================================${RESET}"
  if [ ${#ERRORS[@]} -gt 0 ]; then
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
  echo
  if command -v figlet >/dev/null; then
    figlet "Reboot System"
  else
    echo -e "${YELLOW}========== Reboot System ==========${RESET}"
  fi
  echo -e "${YELLOW}Setup is complete. It's strongly recommended to reboot your system now."
  echo -e "If you encounter issues, review the install log: ${CYAN}$SCRIPT_DIR/install.log${RESET}\n"
  while true; do
    read -rp "$(echo -e "${YELLOW}Reboot now? [Y/n]: ${RESET}")" reboot_ans
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

main() {
  clear
  arch_ascii
  show_menu

  echo -e "${YELLOW}Please enter your sudo password to begin the installation (it will not be echoed):${RESET}"
  sudo -v
  if [ $? -ne 0 ]; then
    echo -e "${RED}Incorrect password or sudo privileges required. Exiting.${RESET}"
    exit 1
  fi

  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

  exec > >(tee -a "$SCRIPT_DIR/install.log") 2>&1

  install_helper_utils
  configure_pacman
  update_mirrors_and_system
  install_yay
  setup_zsh
  install_starship
  generate_locales
  run_custom_scripts
  setup_fastfetch_config
  setup_firewall_and_services
  set_sudo_pwfeedback
  cleanup_helpers
  detect_and_install_gpu_drivers
  setup_maintenance
  cleanup_and_optimize
  print_summary
  prompt_reboot
}

main "$@"
