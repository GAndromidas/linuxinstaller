#!/bin/bash

# Colors for output
CYAN='\033[0;36m'
RESET='\033[0m'

ERRORS=()
CURRENT_STEP=1
TOTAL_STEPS=32  # Adjust if you add/remove steps

INSTALLED_PACKAGES=()
REMOVED_PACKAGES=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
LOG_FILE="$SCRIPT_DIR/install.log"

HELPER_UTILS=(base-devel curl eza fastfetch figlet flatpak fzf git openssh pacman-contrib reflector rsync zoxide)
REMOVE_AFTER_INSTALL=()

show_progress_bar() {
  local width=40
  local filled=$(( width * (CURRENT_STEP-1) / TOTAL_STEPS ))
  local empty=$(( width - filled ))
  local percent=$(( 100 * (CURRENT_STEP-1) / TOTAL_STEPS ))
  printf "\r${CYAN}["
  for ((i=0; i<filled; i++)); do printf "#"; done
  for ((i=0; i<empty; i++)); do printf " "; done
  printf "] %3d%%${RESET}" "$percent"
  if (( CURRENT_STEP > TOTAL_STEPS )); then
    echo
  fi
}

run_step() {
  local description="$1"
  shift
  show_progress_bar
  { "$@"; } >>"$LOG_FILE" 2>&1
  ((CURRENT_STEP++))
}

arch_ascii() {
  if command -v figlet >/dev/null; then
    figlet "Arch Installer"
  fi
}

show_menu() {
  run_step "Show menu" _show_menu
}
_show_menu() {
  echo "Welcome to the Arch Installer script!" >>"$LOG_FILE"
  echo "Please select your installation mode:" >>"$LOG_FILE"
  echo "  1) Default (Full setup)" >>"$LOG_FILE"
  echo "  2) Minimal (Core utilities only)" >>"$LOG_FILE"
  echo "  3) Exit" >>"$LOG_FILE"
  while true; do
    read -p "Enter your choice [1-3]: " menu_choice
    case "$menu_choice" in
      1) INSTALL_MODE="default"; break ;;
      2) INSTALL_MODE="minimal"; break ;;
      3) exit 0 ;;
      *) ;;
    esac
  done
}

install_helper_utils() {
  run_step "Install helper utils" _install_helper_utils
}
_install_helper_utils() {
  local to_install=()
  for util in "${HELPER_UTILS[@]}"; do
    if ! command -v "$util" >/dev/null; then
      to_install+=("$util")
    fi
  done
  if [ ${#to_install[@]} -gt 0 ]; then
    sudo pacman -S --needed --noconfirm "${to_install[@]}"
    INSTALLED_PACKAGES+=("${to_install[@]}")
  fi
}

configure_pacman() {
  run_step "Config pacman" _configure_pacman
}
_configure_pacman() {
  sudo sed -i 's/^#Color/Color/; s/^#VerbosePkgLists/VerbosePkgLists/; s/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
  grep -q ILoveCandy /etc/pacman.conf || sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
  if grep -q "^#\[multilib\]" /etc/pacman.conf; then
    sudo sed -i "/^#\\[multilib\\]/,/^#Include/s/^#//" /etc/pacman.conf
  else
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
  fi
}

update_mirrors_and_system() {
  run_step "Update mirrors" sudo reflector --verbose --protocol https --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
  run_step "System update" sudo pacman -Syyu --noconfirm
}

setup_zsh() {
  run_step "Setup zsh" _setup_zsh
}
_setup_zsh() {
  if ! command -v zsh >/dev/null; then
    sudo pacman -S --needed --noconfirm zsh zsh-autosuggestions zsh-syntax-highlighting
    INSTALLED_PACKAGES+=("zsh" "zsh-autosuggestions" "zsh-syntax-highlighting")
  fi
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi
  sudo chsh -s "$(which zsh)" "$USER"
  if [ -f "$CONFIGS_DIR/.zshrc" ]; then
    cp "$CONFIGS_DIR/.zshrc" "$HOME/"
  fi
}

install_starship() {
  run_step "Install starship" _install_starship
}
_install_starship() {
  if ! command -v starship >/dev/null; then
    sudo pacman -S --needed --noconfirm starship
  fi
  mkdir -p "$HOME/.config"
  if [ -f "$CONFIGS_DIR/starship.toml" ]; then
    mv "$CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml"
  fi
}

generate_locales() {
  run_step "Gen locales" bash -c "sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen && sudo locale-gen"
}

run_custom_scripts() {
  run_step "Custom scripts" _run_custom_scripts
}
_run_custom_scripts() {
  [ -f "$SCRIPTS_DIR/setup_plymouth.sh" ] && chmod +x "$SCRIPTS_DIR/setup_plymouth.sh" && "$SCRIPTS_DIR/setup_plymouth.sh"
  [ -f "$SCRIPTS_DIR/install_yay.sh" ] && chmod +x "$SCRIPTS_DIR/install_yay.sh" && "$SCRIPTS_DIR/install_yay.sh"
  if [ -f "$SCRIPTS_DIR/programs.sh" ]; then
    chmod +x "$SCRIPTS_DIR/programs.sh"
    if [[ "$INSTALL_MODE" == "minimal" ]]; then
      "$SCRIPTS_DIR/programs.sh" -m
    else
      "$SCRIPTS_DIR/programs.sh" -d
    fi
  fi
  # NO PROMPT: Always install fail2ban.sh if it exists
  if [ -f "$SCRIPTS_DIR/fail2ban.sh" ]; then
    chmod +x "$SCRIPTS_DIR/fail2ban.sh"
    "$SCRIPTS_DIR/fail2ban.sh"
  fi
}

setup_fastfetch_config() {
  run_step "Fastfetch config" _setup_fastfetch_config
}
_setup_fastfetch_config() {
  if command -v fastfetch >/dev/null; then
    [ ! -f "$HOME/.config/fastfetch/config.jsonc" ] && fastfetch --gen-config
    [ -f "$CONFIGS_DIR/config.jsonc" ] && mkdir -p "$HOME/.config/fastfetch" && cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
  fi
}

setup_firewall_and_services() {
  run_step "Setup ufw" sudo pacman -S --needed --noconfirm ufw
  run_step "Enable ufw" sudo ufw enable
  local services=(bluetooth cronie ufw fstrim.timer paccache.timer reflector.service reflector.timer sshd teamviewerd.service power-profiles-daemon.service)
  for service in "${services[@]}"; do
    if [ -f "/usr/lib/systemd/system/$service" ] || [ -f "/etc/systemd/system/$service" ]; then
      run_step "Enable $service" sudo systemctl enable --now "$service"
    fi
  done
}

set_sudo_pwfeedback() {
  run_step "Enable pwfeedback" bash -c "echo 'Defaults env_reset,pwfeedback' | sudo EDITOR='tee -a' visudo"
}

cleanup_helpers() {
  run_step "Cleanup yay" sudo rm -rf /tmp/yay
}

detect_and_install_gpu_drivers() {
  run_step "Detect GPU" _detect_and_install_gpu_drivers
}
_detect_and_install_gpu_drivers() {
  GPU_INFO=$(lspci | grep -E "VGA|3D")
  if echo "$GPU_INFO" | grep -qi nvidia; then
    run_step "Install nouveau" sudo pacman -S --noconfirm xf86-video-nouveau mesa
  elif echo "$GPU_INFO" | grep -qi amd; then
    run_step "Install amdgpu" sudo pacman -S --noconfirm xf86-video-amdgpu mesa
  elif echo "$GPU_INFO" | grep -qi intel; then
    run_step "Install intel" sudo pacman -S --noconfirm mesa xf86-video-intel
  fi
}

install_cpu_microcode() {
  run_step "Install microcode" _install_cpu_microcode
}
_install_cpu_microcode() {
  local pkg=""
  if grep -q "Intel" /proc/cpuinfo; then
    pkg="intel-ucode"
  elif grep -q "AMD" /proc/cpuinfo; then
    pkg="amd-ucode"
  fi
  [ -n "$pkg" ] && ! pacman -Q "$pkg" &>/dev/null && sudo pacman -S --needed --noconfirm "$pkg"
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
  run_step "Install kernel headers" _install_kernel_headers_for_all
}
_install_kernel_headers_for_all() {
  local kernel_types
  kernel_types=($(get_installed_kernel_types))
  for kernel in "${kernel_types[@]}"; do
    local headers_package="${kernel}-headers"
    sudo pacman -S --needed --noconfirm "$headers_package"
  done
}

make_systemd_boot_silent() {
  run_step "Silent systemd-boot" _make_systemd_boot_silent
}
_make_systemd_boot_silent() {
  local ENTRIES_DIR="/boot/loader/entries"
  local kernel_types
  kernel_types=($(get_installed_kernel_types))
  for kernel in "${kernel_types[@]}"; do
    local linux_entry
    linux_entry=$(find "$ENTRIES_DIR" -type f -name "*${kernel}.conf" ! -name '*fallback.conf' -print -quit)
    [ -z "$linux_entry" ] && continue
    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$linux_entry"
  done
}

change_loader_conf() {
  run_step "loader.conf" _change_loader_conf
}
_change_loader_conf() {
  local LOADER_CONF="/boot/loader/loader.conf"
  [ ! -f "$LOADER_CONF" ] && return
  sudo sed -i '1{/^default @saved/!i default @saved}' "$LOADER_CONF"
  sudo sed -i 's/^timeout.*/timeout 3/' "$LOADER_CONF"
  sudo sed -i 's/^#console-mode.*/console-mode max/' "$LOADER_CONF"
}

remove_fallback_entries() {
  run_step "Remove fallback" _remove_fallback_entries
}
_remove_fallback_entries() {
  local ENTRIES_DIR="/boot/loader/entries"
  for entry in "$ENTRIES_DIR"/*fallback.conf; do
    [ -f "$entry" ] && sudo rm "$entry"
  done
}

setup_maintenance() {
  run_step "Setup maintenance" _setup_maintenance
}
_setup_maintenance() {
  command -v paccache >/dev/null && sudo paccache -r
  orphans=$(pacman -Qtdq); if [[ -n "$orphans" ]]; then sudo pacman -Rns --noconfirm $orphans; fi
  sudo pacman -Syu --noconfirm
  command -v yay >/dev/null && yay -Syu --noconfirm
}

cleanup_and_optimize() {
  run_step "Final cleanup" _cleanup_and_optimize
}
_cleanup_and_optimize() {
  lsblk -d -o rota | grep -q '^0$' && sudo fstrim -v /
  sudo rm -rf /tmp/*
  cd ~
  sudo rm -rf "$SCRIPT_DIR"
  sync
}

print_summary() {
  run_step "Summary" _print_summary
}
_print_summary() {
  echo "See $LOG_FILE for install details."
}

prompt_reboot() {
  run_step "Prompt reboot" _prompt_reboot
}
_prompt_reboot() {
  if command -v figlet >/dev/null; then
    figlet "Reboot System"
  fi
  while true; do
    read -rp "Reboot now? [Y/n]: " reboot_ans
    reboot_ans=${reboot_ans,,}
    case "$reboot_ans" in
      ""|y|yes)
        sudo reboot
        break
        ;;
      n|no)
        break
        ;;
      *)
        ;;
    esac
  done
}

main() {
  clear
  arch_ascii
  show_menu

  : >"$LOG_FILE"

  sudo -v
  if [ $? -ne 0 ]; then
    exit 1
  fi

  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

  install_helper_utils
  configure_pacman
  update_mirrors_and_system
  setup_zsh
  install_starship
  generate_locales
  run_custom_scripts
  setup_fastfetch_config
  setup_firewall_and_services
  set_sudo_pwfeedback
  cleanup_helpers
  detect_and_install_gpu_drivers
  install_cpu_microcode
  install_kernel_headers_for_all
  make_systemd_boot_silent
  change_loader_conf
  remove_fallback_entries
  setup_maintenance
  cleanup_and_optimize
  print_summary
  prompt_reboot
  echo -e "\n${CYAN}Installation complete. See $LOG_FILE for full output.${RESET}"
}

main "$@"
