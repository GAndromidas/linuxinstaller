#!/bin/bash
set -uo pipefail

# Plymouth setup and configuration script
# Updated for modern Linux systems

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

# -------------------------------------------------------------------------
# Step 1: Install & Configure Hooks
# -------------------------------------------------------------------------
configure_plymouth() {
  # Skip for non-Arch distros to respect upstream defaults
  if [ "$DISTRO_ID" != "arch" ]; then
      log_info "Skipping Plymouth configuration for $DISTRO_ID (using upstream defaults)."
      return 0
  fi

  log_info "Configuring Plymouth for $DISTRO_ID..."

  # --- Arch Logic ---
  local mkinitcpio_conf="/etc/mkinitcpio.conf"
  local hook_name="plymouth"

  if grep -q "HOOKS=.*systemd" "$mkinitcpio_conf" && [ -f "/usr/lib/initcpio/install/sd-plymouth" ]; then
    hook_name="sd-plymouth"
  fi

  if ! command -v plymouthd >/dev/null; then
    sudo pacman -S --noconfirm plymouth
  fi

  if ! grep -q "$hook_name" "$mkinitcpio_conf"; then
    if grep -q "HOOKS=.*systemd" "$mkinitcpio_conf"; then
      sudo sed -i "s/systemd/systemd $hook_name/" "$mkinitcpio_conf"
    elif grep -q "HOOKS=.*udev" "$mkinitcpio_conf"; then
      sudo sed -i "s/udev/udev $hook_name/" "$mkinitcpio_conf"
    else
      sudo sed -i "s/base/base $hook_name/" "$mkinitcpio_conf"
    fi
    log_success "Added $hook_name to HOOKS."
  fi
}

# -------------------------------------------------------------------------
# Step 2: Set Theme
# -------------------------------------------------------------------------
set_plymouth_theme() {
  # Skip for non-Arch distros
  if [ "$DISTRO_ID" != "arch" ]; then
      return 0
  fi

  local theme="bgrt" # Arch prefers bgrt

  log_info "Setting Plymouth theme to $theme..."

  # Check available themes
  if ! plymouth-set-default-theme -l | grep -q "$theme"; then
     theme=$(plymouth-set-default-theme -l | head -n1)
     log_warning "Preferred theme not found, falling back to $theme"
  fi

  # Apply
  if [ "${SKIP_MKINITCPIO:-false}" = "true" ]; then
      sudo plymouth-set-default-theme "$theme"
      log_success "Theme set to $theme (rebuild skipped)"
  else
       if sudo plymouth-set-default-theme -R "$theme"; then
           log_success "Theme set and initramfs rebuilt."
       else
           sudo mkinitcpio -P
       fi
  fi
}

main() {
  run_step "Configuring Plymouth" configure_plymouth
  run_step "Setting Plymouth Theme" set_plymouth_theme
}

main "$@"
