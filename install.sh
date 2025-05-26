#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Step tracking
ERRORS=()
CURRENT_STEP=1
TOTAL_STEPS=26  # Adjust as needed

# Summary arrays
INSTALLED_PACKAGES=()
REMOVED_PACKAGES=()

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# Helper utilities
HELPER_UTILS=(figlet fastfetch fzf reflector rsync git curl base-devel zoxide eza)
REMOVE_AFTER_INSTALL=(figlet)

# ========== ASCII Art ==========
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

# ========== Menu ==========
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

# ========== Utility Functions ==========

spinner() {
  local pid=$!
  local spinstr='|/-\'
  local delay=0.09
  while ps -p $pid &>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "      \b\b\b\b\b\b"
}

step() {
  echo -e "${CYAN}[$CURRENT_STEP/$TOTAL_STEPS] $1${RESET}"
  ((CURRENT_STEP++))
}

log_success() { echo -e "${GREEN}[OK] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_error()   { echo -e "${RED}[FAIL] $1${RESET}"; ERRORS+=("$1"); }

run_step() {
  local description="$1"
  shift
  step "$description"
  # If the command includes sudo, do NOT use spinner or backgrounding
  if [[ "$*" == *"sudo "* ]]; then
    "$@"
  else
    "$@" &
    spinner
    wait $!
  fi
  local status=$?
  if [ $status -eq 0 ]; then
    log_success "$description"
    # Track installed/removed for summary
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

# ========== Modular Setup Functions ==========

install_helper_utils() {
  run_step "Installing helper utilities" sudo pacman -S --needed --noconfirm "${HELPER_UTILS[@]}"
}

configure_pacman() {
  run_step "Configuring Pacman" sudo sed -i 's/^#Color/Color/; s/^#VerbosePkgLists/VerbosePkgLists/; s/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
  run_step "Enable ILoveCandy" bash -c "grep -q ILoveCandy /etc/pacman.conf || sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf"
}

update_mirrors_and_system() {
  run_step "Updating mirrorlist" sudo reflector --verbose --protocol https --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
  run_step "System update" sudo pacman -Syyu --noconfirm
}

install_yay() {
  run_step "Installing yay (AUR helper)" bash -c 'cd /tmp && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm && cd .. && rm -rf yay'
}

setup_zsh() {
  run_step "Installing ZSH and plugins" sudo pacman -S --needed --noconfirm zsh zsh-autosuggestions zsh-syntax-highlighting
  run_step "Installing Oh-My-Zsh" bash -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
  run_step "Changing shell to ZSH" sudo chsh -s "$(which zsh)" "$USER"
  if [ -f "$CONFIGS_DIR/.zshrc" ]; then
    run_step "Configuring .zshrc" cp "$CONFIGS_DIR/.zshrc" "$HOME/"
  fi
}

install_starship() {
  run_step "Installing starship prompt" sudo pacman -S --needed --noconfirm starship
  run_step "Configuring starship prompt" bash -c 'mkdir -p "$HOME/.config" && [ -f "$CONFIGS_DIR/starship.toml" ] && cp "$CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml"'
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
    chmod +x "$SCRIPTS_DIR/fail2ban.sh"
    run_step "Configuring fail2ban" "$SCRIPTS_DIR/fail2ban.sh"
  fi
}

setup_fastfetch_config() {
  if command -v fastfetch >/dev/null; then
    run_step "Creating fastfetch config" bash -c '
      fastfetch --gen-config
      [[ -f "$CONFIGS_DIR/config.jsonc" ]] && mkdir -p "$HOME/.config/fastfetch" && cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
    '
  fi
}

setup_firewall_and_services() {
  run_step "Installing UFW firewall" sudo pacman -S --needed --noconfirm ufw
  run_step "Enabling firewall" sudo ufw enable
  for service in bluetooth cronie ufw fstrim.timer sshd; do
    run_step "Enabling $service" sudo systemctl enable --now "$service"
  done
}

cleanup_helpers() {
  run_step "Removing figlet" sudo pacman -Rns --noconfirm "${REMOVE_AFTER_INSTALL[@]}"
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
  run_step "Cleaning pacman cache (keep last 3 packages)" sudo paccache -r
  run_step "Removing orphaned packages" bash -c 'orphans=$(pacman -Qtdq); if [[ -n "$orphans" ]]; then sudo pacman -Rns --noconfirm $orphans; fi'
  run_step "System update" sudo pacman -Syu --noconfirm
  if command -v yay >/dev/null; then
    run_step "AUR update (yay)" yay -Syu --noconfirm
  fi
  # Optionally, add systemd timer for routine maintenance here
}

cleanup_and_optimize() {
  echo -e "${CYAN}Performing final cleanup and optimizations...${RESET}"

  # 1. SSD Optimization
  if lsblk -d -o rota | grep -q '^0$'; then
    run_step "Running fstrim on SSDs" sudo fstrim -v /
  fi

  # 2. Remove temp files
  run_step "Cleaning /tmp directory" sudo rm -rf /tmp/*

  # 3. Optionally clear shell/user history
  # run_step "Clearing user shell history" bash -c "cat /dev/null > ~/.bash_history; history -c"

  # 4. Remove installer directory
  if [[ -d "$SCRIPT_DIR" ]]; then
    cd ~
    run_step "Deleting installer directory" rm -rf "$SCRIPT_DIR"
  fi

  # 5. Sync disks before reboot
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
    echo -e "\n${RED}The following steps failed:${RESET}"
    for err in "${ERRORS[@]}"; do
      echo -e "  - $err"
    done
    echo -e "${YELLOW}Check the install log for more details: ${CYAN}$SCRIPT_DIR/install.log${RESET}"
  else
    echo -e "\n${GREEN}All steps completed successfully!${RESET}"
  fi
}

prompt_reboot() {
  echo
  echo -e "${YELLOW}Setup is complete. It's strongly recommended to reboot your system now."
  echo -e "If you encounter issues, review the install log: ${CYAN}$SCRIPT_DIR/install.log${RESET}"
  while true; do
    read -rp "$(echo -e "${CYAN}Reboot now? [Y/n]: ${RESET}")" reboot_ans
    reboot_ans=${reboot_ans,,}  # lowercase
    case "$reboot_ans" in
      ""|y|yes)
        echo -e "${CYAN}Rebooting...${RESET}"
        sudo reboot
        break
        ;;
      n|no)
        echo -e "${YELLOW}Reboot skipped. You can reboot manually at any time using \`sudo reboot\`.${RESET}"
        break
        ;;
      *)
        echo -e "${RED}Please answer Y (yes) or N (no).${RESET}"
        ;;
    esac
  done
}

# ========== Main Script Logic ==========

main() {
  clear
  arch_ascii
  show_menu

  # Prompt for sudo password up front in a clear way
  echo -e "${YELLOW}Please enter your sudo password to begin the installation (it will not be echoed):${RESET}"
  sudo -v
  if [ $? -ne 0 ]; then
    echo -e "${RED}Incorrect password or sudo privileges required. Exiting.${RESET}"
    exit 1
  fi

  # Keep sudo alive in background
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

  # Log to file as well
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
  cleanup_helpers
  detect_and_install_gpu_drivers
  setup_maintenance
  cleanup_and_optimize
  print_summary
  prompt_reboot
}

main "$@"
