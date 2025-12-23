#!/bin/bash
set -uo pipefail

# Plymouth setup and configuration script
# Improved for performance and Arch Linux bootloader support

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

# Kernel parameters for silent boot
PLYMOUTH_PARAMS="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"

# -------------------------------------------------------------------------
# Step 1: Install Plymouth
# -------------------------------------------------------------------------
install_plymouth() {
    if ! command_exists plymouthd; then
        if [ "$DISTRO_ID" == "arch" ]; then
             log_info "Installing plymouth..."
             $PKG_INSTALL $PKG_NOCONFIRM plymouth >/dev/null 2>&1 || log_error "Failed to install plymouth"
        else
             # Generic installation fallback
             log_info "Installing plymouth..."
             $PKG_INSTALL $PKG_NOCONFIRM plymouth >/dev/null 2>&1
        fi
    fi
}

# -------------------------------------------------------------------------
# Step 2: Configure Bootloader (Arch Specific)
# -------------------------------------------------------------------------
configure_bootloader_arch() {
    if [ "$DISTRO_ID" != "arch" ]; then
        return 0
    fi

    log_info "Configuring bootloader entries for Plymouth..."
    
    local bootloader
    bootloader=$(detect_bootloader)
    
    if [[ "$bootloader" == "systemd-boot" ]]; then
        configure_systemd_boot
    elif [[ "$bootloader" == "grub" ]]; then
        configure_grub_arch
    else
        log_warning "Unknown bootloader. Please add '$PLYMOUTH_PARAMS' to your kernel parameters manually."
    fi
}

configure_systemd_boot() {
    log_info "Detected systemd-boot. Updating entries..."
    
    local entries_dir=""
    if [ -d "/boot/loader/entries" ]; then
        entries_dir="/boot/loader/entries"
    elif [ -d "/efi/loader/entries" ]; then
        entries_dir="/efi/loader/entries"
    elif [ -d "/boot/efi/loader/entries" ]; then
        entries_dir="/boot/efi/loader/entries"
    fi

    if [ -z "$entries_dir" ]; then
        log_warning "Could not find systemd-boot entries directory."
        return
    fi

    local updated=false
    # Loop safely handling no files
    for entry in "$entries_dir"/*.conf; do
        [ -e "$entry" ] || continue
        if [ -f "$entry" ]; then
            if ! grep -q "splash" "$entry"; then
                # Append options to the options line
                if grep -q "^options" "$entry"; then
                    sudo sed -i "/^options/ s/$/ $PLYMOUTH_PARAMS/" "$entry"
                    log_success "Updated $entry"
                    updated=true
                else
                    # Try to add options line if missing
                    echo "options $PLYMOUTH_PARAMS" | sudo tee -a "$entry" >/dev/null
                    log_success "Updated $entry (added options)"
                    updated=true
                fi
            fi
        fi
    done
    
    if [ "$updated" = true ]; then
        log_success "systemd-boot entries updated."
    else
        log_info "systemd-boot entries already configured."
    fi
}

configure_grub_arch() {
    log_info "Detected GRUB. Updating /etc/default/grub..."
    
    if [ ! -f /etc/default/grub ]; then
        log_error "/etc/default/grub not found."
        return
    fi

    local current_line
    current_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub)
    local current_params=""
    if [ -n "$current_line" ]; then
        # Remove variable name and surrounding quotes (single or double)
        current_params=$(echo "$current_line" | cut -d'=' -f2- | sed "s/^['\"]//;s/['\"]$//")
    fi
    
    # Construct new params
    local new_params="$current_params"
    local changed=false
    
    for param in $PLYMOUTH_PARAMS; do
        if [[ ! "$new_params" == *"$param"* ]]; then
            new_params="$new_params $param"
            changed=true
        fi
    done
    
    if [ "$changed" = true ]; then
        # Replace line using sed, forcing double quotes
        sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_params\"|" /etc/default/grub
        log_success "Updated /etc/default/grub kernel parameters."
        
        log_info "Regenerating GRUB config..."
        sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || log_error "Failed to regenerate GRUB config"
    else
        log_info "GRUB already configured."
    fi
}

# -------------------------------------------------------------------------
# Step 3: Set Theme
# -------------------------------------------------------------------------
set_plymouth_theme() {
  local theme="bgrt" # Arch prefers bgrt
  [ "$DISTRO_ID" == "arch" ] || theme="spinner" 

  # Check if theme exists
  if ! plymouth-set-default-theme -l 2>/dev/null | grep -q "$theme"; then
     local first_theme
     first_theme=$(plymouth-set-default-theme -l 2>/dev/null | head -n1)
     if [ -n "$first_theme" ]; then
         theme="$first_theme"
     fi
  fi

  log_info "Setting Plymouth theme to $theme..."
  
  if [ "${SKIP_MKINITCPIO:-false}" = "true" ]; then
      sudo plymouth-set-default-theme "$theme"
      log_success "Theme set to $theme (rebuild skipped)"
  else
       # plymouth-set-default-theme -R rebuilds initrd
       if sudo plymouth-set-default-theme -R "$theme"; then
           log_success "Theme set and initramfs rebuilt."
       else
           log_warning "Theme set command returned error, attempting manual rebuild..."
           if [ "$DISTRO_ID" == "arch" ]; then
               sudo mkinitcpio -P >/dev/null 2>&1 && log_success "Initramfs rebuilt manually."
           fi
       fi
  fi
}

main() {
  run_step "Installing Plymouth" install_plymouth
  
  if [ "$DISTRO_ID" == "arch" ]; then
      if declare -f configure_plymouth_hook_and_initramfs >/dev/null; then
           # Skip rebuild here, will happen at end of theme set or handled by caller
           export SKIP_MKINITCPIO=true
           configure_plymouth_hook_and_initramfs
           unset SKIP_MKINITCPIO
      fi
  fi
  
  run_step "Configuring Bootloader for Plymouth" configure_bootloader_arch
  
  run_step "Setting Plymouth Theme" set_plymouth_theme
}

main "$@"
