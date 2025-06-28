#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Use different variable names to avoid conflicts
PLYMOUTH_INSTALLED=()
PLYMOUTH_ERRORS=()

# ======= Pacman Quiet Install Function =======
install_pacman_quietly() {
  local pkgs=("$@")
  for pkg in "${pkgs[@]}"; do
    if pacman -Q "$pkg" &>/dev/null; then
      echo -e "${YELLOW}Installing: $pkg ... [SKIP] Already installed${RESET}"
      continue
    fi
    echo -ne "${CYAN}Installing: $pkg ...${RESET} "
    if sudo pacman -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
      echo -e "${GREEN}[OK]${RESET}"
      PLYMOUTH_INSTALLED+=("$pkg")
    else
      echo -e "${RED}[FAIL]${RESET}"
      log_error "Failed to install $pkg"
    fi
  done
}

# ======= Plymouth Setup Steps =======
install_plymouth() {
  install_pacman_quietly plymouth
}

enable_plymouth_hook() {
  local mkinitcpio_conf="/etc/mkinitcpio.conf"
  if ! grep -q "plymouth" "$mkinitcpio_conf"; then
    sudo sed -i 's/^HOOKS=\(.*\)keyboard \(.*\)/HOOKS=\1plymouth keyboard \2/' "$mkinitcpio_conf"
    log_success "Added plymouth hook to mkinitcpio.conf."
  else
    log_warning "Plymouth hook already present in mkinitcpio.conf."
  fi
}

rebuild_initramfs() {
  sudo mkinitcpio -p linux
}

set_plymouth_theme() {
  local theme="bgrt"
  
  # Fix the double slash issue in bgrt theme if it exists
  local bgrt_config="/usr/share/plymouth/themes/bgrt/bgrt.plymouth"
  if [ -f "$bgrt_config" ]; then
    # Fix the double slash in ImageDir path
    if grep -q "ImageDir=/usr/share/plymouth/themes//spinner" "$bgrt_config"; then
      sudo sed -i 's|ImageDir=/usr/share/plymouth/themes//spinner|ImageDir=/usr/share/plymouth/themes/spinner|g' "$bgrt_config"
      log_success "Fixed double slash in bgrt theme configuration"
    fi
  fi
  
  # Try to set the bgrt theme
  if plymouth-set-default-theme -l | grep -qw "$theme"; then
    if sudo plymouth-set-default-theme -R "$theme" 2>/dev/null; then
    log_success "Set plymouth theme to '$theme'."
      return 0
  else
      log_warning "Failed to set '$theme' theme. Trying fallback themes..."
    fi
  else
    log_warning "Theme '$theme' not found in available themes."
  fi
  
  # Fallback to spinner theme (which bgrt depends on anyway)
  local fallback_theme="spinner"
  if plymouth-set-default-theme -l | grep -qw "$fallback_theme"; then
    if sudo plymouth-set-default-theme -R "$fallback_theme" 2>/dev/null; then
      log_success "Set plymouth theme to fallback '$fallback_theme'."
      return 0
    fi
  fi
  
  # Last resort: use the first available theme
  local first_theme
  first_theme=$(plymouth-set-default-theme -l | head -n1)
  if [ -n "$first_theme" ]; then
    if sudo plymouth-set-default-theme -R "$first_theme" 2>/dev/null; then
      log_success "Set plymouth theme to first available theme: '$first_theme'."
    else
      log_error "Failed to set any plymouth theme"
      return 1
    fi
  else
    log_error "No plymouth themes available"
    return 1
  fi
}

add_kernel_parameters() {
  local loader_conf="/boot/loader/entries/$(ls /boot/loader/entries | grep -m1 linux | head -n1)"
  if [ -f "$loader_conf" ]; then
    if ! grep -q "splash" "$loader_conf"; then
      sudo sed -i '/^options / s/$/ splash/' "$loader_conf"
      log_success "Added 'splash' to kernel parameters."
    else
      log_warning "'splash' already set in kernel parameters."
    fi
  else
    log_warning "Could not find loader entry for kernel to add 'splash' parameter."
  fi
}

print_summary() {
  echo -e "\n${CYAN}========= PLYMOUTH SUMMARY =========${RESET}"
  if [ ${#PLYMOUTH_INSTALLED[@]} -gt 0 ]; then
    echo -e "${GREEN}Installed:${RESET} ${PLYMOUTH_INSTALLED[*]}"
  fi
  if [ ${#PLYMOUTH_ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}Plymouth installed and configured successfully!${RESET}"
  else
    echo -e "${RED}Some steps failed:${RESET}"
    for err in "${PLYMOUTH_ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  fi
  echo -e "${CYAN}====================================${RESET}"
}

# ======= Main =======
main() {
  # Print simple banner (no figlet)
  echo -e "${CYAN}=== Plymouth Setup ===${RESET}"

  run_step "Installing Plymouth" install_plymouth
  run_step "Adding plymouth hook to mkinitcpio.conf" enable_plymouth_hook
  run_step "Rebuilding initramfs" rebuild_initramfs
  run_step "Setting Plymouth theme" set_plymouth_theme
  run_step "Adding 'splash' to kernel parameters" add_kernel_parameters

  print_summary
}

main "$@"