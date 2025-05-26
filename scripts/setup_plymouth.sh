#!/bin/bash

# ======= Colors and Step/Log Helpers =======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

CURRENT_STEP=1
ERRORS=()

step() {
  echo -e "\n${CYAN}[$CURRENT_STEP] $1${RESET}"
  ((CURRENT_STEP++))
}

log_success() { echo -e "${GREEN}[OK] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_error()   { echo -e "${RED}[FAIL] $1${RESET}"; ERRORS+=("$1"); }

run_step() {
  local description="$1"
  shift
  step "$description"
  "$@"
  local status=$?
  if [ $status -eq 0 ]; then
    log_success "$description"
  else
    log_error "$description"
  fi
  return $status
}

# ======= Plymouth Setup Steps =======

install_plymouth() {
  if pacman -Q plymouth >/dev/null 2>&1; then
    log_warning "Plymouth is already installed. Skipping."
    return 0
  fi
  sudo pacman -S --needed --noconfirm plymouth
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
  if plymouth-set-default-theme -l | grep -qw "$theme"; then
    sudo plymouth-set-default-theme -R "$theme"
    log_success "Set plymouth theme to '$theme'."
  else
    log_warning "Theme '$theme' not found. Using default theme."
    sudo plymouth-set-default-theme -R $(plymouth-set-default-theme)
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
  if [ ${#ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}Plymouth installed and configured successfully!${RESET}"
  else
    echo -e "${RED}Some steps failed:${RESET}"
    for err in "${ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  fi
  echo -e "${CYAN}====================================${RESET}"
}

# ======= Main =======
main() {
  run_step "Installing Plymouth" install_plymouth
  run_step "Adding plymouth hook to mkinitcpio.conf" enable_plymouth_hook
  run_step "Rebuilding initramfs" rebuild_initramfs
  run_step "Setting Plymouth theme" set_plymouth_theme
  run_step "Adding 'splash' to kernel parameters" add_kernel_parameters

  print_summary
}

main "$@"
