#!/bin/bash
set -uo pipefail

# Plymouth setup and configuration script
# Updated for modern Arch Linux (Silent Boot, correct hooks)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Minimal progress printer used for long loops
print_progress() {
  local current="$1"
  local total="$2"
  local description="$3"
  printf "\r\033[K${CYAN}%s...${RESET}" "$description"
}

# -------------------------------------------------------------------------
# Step 1: Configure Plymouth Hook
# -------------------------------------------------------------------------
configure_plymouth_hook() {
  local mkinitcpio_conf="/etc/mkinitcpio.conf"
  local hook_name="plymouth"

  # Check for systemd hook preference
  if grep -q "HOOKS=.*systemd" "$mkinitcpio_conf"; then
    if [ -f "/usr/lib/initcpio/install/sd-plymouth" ]; then
      hook_name="sd-plymouth"
    fi
  fi

  log_info "Configuring Plymouth hook ($hook_name)..."

  # Install plymouth if missing
  if ! command -v plymouthd >/dev/null; then
    log_info "Installing plymouth package..."
    sudo pacman -S --noconfirm plymouth || return 1
  fi

  # Add hook to mkinitcpio.conf if not present
  if ! grep -q "$hook_name" "$mkinitcpio_conf"; then
    # Placement logic:
    # 1. After 'systemd' (if present)
    # 2. After 'base' and 'udev' (standard)

    if grep -q "HOOKS=.*systemd" "$mkinitcpio_conf"; then
      sudo sed -i "s/systemd/systemd $hook_name/" "$mkinitcpio_conf"
    elif grep -q "HOOKS=.*udev" "$mkinitcpio_conf"; then
      sudo sed -i "s/udev/udev $hook_name/" "$mkinitcpio_conf"
    else
      # Fallback: append to beginning? No, usually after base.
      # Just inserting after base if udev missing (unlikely)
      sudo sed -i "s/base/base $hook_name/" "$mkinitcpio_conf"
    fi
    log_success "Added $hook_name to HOOKS."
  else
    log_info "Hook $hook_name already present."
  fi

  # Ensure sd-plymouth is used if systemd is present, replacing plymouth if necessary
  if grep -q "HOOKS=.*systemd" "$mkinitcpio_conf" && grep -q "HOOKS=.* plymouth " "$mkinitcpio_conf"; then
      if [ -f "/usr/lib/initcpio/install/sd-plymouth" ]; then
        log_info "Replacing 'plymouth' with 'sd-plymouth' for systemd initramfs..."
        sudo sed -i "s/ plymouth / sd-plymouth /" "$mkinitcpio_conf"
      fi
  fi

  return 0
}

# -------------------------------------------------------------------------
# Step 2: Set Theme (with Rebuild)
# -------------------------------------------------------------------------
set_plymouth_theme() {
  local theme_primary="bgrt" # Arch default/preferred (uses UEFI logo)
  local theme_fallback="spinner"

  log_info "Setting Plymouth theme..."

  # Check available themes
  local themes
  themes=$(plymouth-set-default-theme -l)

  local target_theme=""

  if echo "$themes" | grep -q "^$theme_primary$"; then
    target_theme="$theme_primary"
  elif echo "$themes" | grep -q "^$theme_fallback$"; then
    target_theme="$theme_fallback"
  else
    target_theme=$(echo "$themes" | head -n1)
  fi

  if [ -z "$target_theme" ]; then
    log_warning "No Plymouth themes found!"
    return 1
  fi

  log_info "Selected theme: $target_theme"

  # Workaround for BGRT image path bug in some versions
  if [ "$target_theme" == "bgrt" ]; then
      local bgrt_cfg="/usr/share/plymouth/themes/bgrt/bgrt.plymouth"
      if [ -f "$bgrt_cfg" ] && grep -q "ImageDir=.*//" "$bgrt_cfg"; then
          log_info "Fixing BGRT theme configuration bug..."
          sudo sed -i 's|//|/|g' "$bgrt_cfg"
      fi
  fi

  # Set theme and rebuild initramfs
  if [ "${SKIP_MKINITCPIO:-false}" = "true" ]; then
      log_info "Setting theme to '$target_theme' (initramfs rebuild skipped by env)..."
      sudo plymouth-set-default-theme "$target_theme"
  else
      log_info "Applying theme and rebuilding initramfs (this may take a moment)..."
      if sudo plymouth-set-default-theme -R "$target_theme"; then
        log_success "Theme set to '$target_theme' and initramfs rebuilt."
      else
        log_error "Failed to set theme via plymouth-set-default-theme -R."
        # Fallback: manual rebuild
        sudo plymouth-set-default-theme "$target_theme"
        sudo mkinitcpio -P
      fi
  fi
}

# -------------------------------------------------------------------------
# Step 3: Silent Boot Parameters
# -------------------------------------------------------------------------
add_silent_boot_params() {
  log_info "Configuring kernel parameters for silent boot..."

  # Comprehensive silent boot parameters
  local params=(
    "quiet"
    "splash"
    "loglevel=3"
    "rd.udev.log_level=3"
    "vt.global_cursor_default=0"
    "systemd.show_status=auto"
    "rd.systemd.show_status=auto"
    "udev.log_priority=3"
  )

  # Detect Bootloader
  local bootloader="unknown"
  if [ -d "/boot/loader/entries" ]; then
    bootloader="systemd-boot"
  elif [ -f "/etc/default/grub" ]; then
    bootloader="grub"
  fi

  if [ "$bootloader" == "systemd-boot" ]; then
    # find all conf files
    local entries=$(find /boot/loader/entries -name "*.conf")
    for entry in $entries; do
      log_info "Checking $entry..."
      local current_options=$(grep "^options" "$entry" | sed 's/^options //')
      local new_options="$current_options"
      local modified=false

      for p in "${params[@]}"; do
        if ! echo "$current_options" | grep -q "$p"; then
          new_options="$new_options $p"
          modified=true
        fi
      done

      if [ "$modified" = true ]; then
        sudo sed -i "s|^options .*|options $new_options|" "$entry"
        log_success "Updated kernel parameters in $entry"
      fi
    done

  elif [ "$bootloader" == "grub" ]; then
    log_info "Updating GRUB config..."
    local grub_cfg="/etc/default/grub"
    local needs_update=false

    # Read current command line
    local current_cmdline
    current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_cfg" | cut -d'"' -f2)

    local new_cmdline="$current_cmdline"
    for p in "${params[@]}"; do
        if ! echo "$current_cmdline" | grep -q "$p"; then
            new_cmdline="$new_cmdline $p"
            needs_update=true
        fi
    done

    if [ "$needs_update" = true ]; then
        sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" "$grub_cfg"
        log_info "Regenerating GRUB configuration..."
        if command -v grub-mkconfig >/dev/null; then
            sudo grub-mkconfig -o /boot/grub/grub.cfg
        else
            log_warning "grub-mkconfig not found!"
        fi
        log_success "GRUB updated."
    else
        log_info "GRUB already has silent boot parameters."
    fi
  else
    log_warning "Unsupported bootloader or unable to detect. Please add parameters manually: ${params[*]}"
  fi
}

# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------
main() {
  if command -v ui_header >/dev/null; then
    ui_header "Plymouth Configuration (Silent Boot)"
  else
    echo -e "${CYAN}=== Plymouth Configuration (Silent Boot) ===${RESET}"
  fi

  # 1. Configure Hook
  if ! run_step "Configuring Plymouth Initcpio Hook" configure_plymouth_hook; then
    log_error "Failed to configure plymouth hook."
    return 1
  fi

  # 2. Set Theme (Rebuilds initramfs)
  if ! run_step "Setting Plymouth Theme" set_plymouth_theme; then
    log_warning "Theme setting failed."
  fi

  # 3. Silent Boot Params
  if ! run_step "Adding Silent Boot Parameters" add_silent_boot_params; then
    log_warning "Kernel parameter configuration had issues."
  fi

  echo ""
  log_success "Plymouth configuration complete. Reboot to see changes."
}

main "$@"
