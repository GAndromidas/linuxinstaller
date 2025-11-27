#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

add_systemd_boot_kernel_params() {
  local boot_entries_dir="/boot/loader/entries"
  if [ ! -d "$boot_entries_dir" ]; then
    log_warning "Boot entries directory not found. Skipping kernel parameter addition for systemd-boot."
    return 0 # Not an error that should stop the script
  fi

  local modified_count=0
  local entries_found=0

  # Find non-fallback .conf files and process them
  while IFS= read -r -d $'\0' entry; do
    ((entries_found++))
    local entry_name=$(basename "$entry")
    if ! grep -q "quiet loglevel=3" "$entry"; then # Check for existing parameters more generically
      if sudo sed -i '/^options / s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$entry"; then
        log_success "Added kernel parameters to $entry_name"
        ((modified_count++))
      else
        log_error "Failed to add kernel parameters to $entry_name"
        # Continue to try other entries, but log the error
      fi
    else
      log_info "Kernel parameters already present in $entry_name - skipping."
    fi
  done < <(find "$boot_entries_dir" -name "*.conf" ! -name "*fallback.conf" -print0)

  if [ "$entries_found" -eq 0 ]; then
    log_warning "No systemd-boot entries found to modify."
  elif [ "$modified_count" -gt 0 ]; then
    log_success "Kernel parameters updated for $modified_count systemd-boot entries."
  else
    log_info "No systemd-boot entries needed parameter updates."
  fi
  return 0
}

# --- systemd-boot ---
configure_boot() {
  run_step "Adding kernel parameters to systemd-boot entries" add_systemd_boot_kernel_params

  if [ -f "/boot/loader/loader.conf" ]; then
    sudo sed -i \
      -e '/^default /d' \
      -e '1i default @saved' \
      -e 's/^timeout.*/timeout 3/' \
      -e 's/^[#]*console-mode[[:space:]]\+.*/console-mode max/' \
      /boot/loader/loader.conf

    run_step "Ensuring timeout is set in loader.conf" \
        grep -q '^timeout' /boot/loader/loader.conf || echo "timeout 3" | sudo tee -a /boot/loader/loader.conf >/dev/null
    run_step "Ensuring console-mode is set in loader.conf" \
        grep -q '^console-mode' /boot/loader/loader.conf || echo "console-mode max" | sudo tee -a /boot/loader/loader.conf >/dev/null
  else
    log_warning "loader.conf not found. Skipping loader.conf configuration for systemd-boot."
  fi

  run_step "Removing systemd-boot fallback entries" sudo rm -f /boot/loader/entries/*fallback.conf
}

# --- Bootloader and Btrfs detection ---
BOOTLOADER=$(detect_bootloader)
IS_BTRFS=$(is_btrfs_system && echo "true" || echo "false")

# --- GRUB configuration ---
configure_grub() {
    step "Configuring GRUB: set default kernel to 'linux'"

    # /etc/default/grub settings
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub || echo 'GRUB_TIMEOUT=3' | sudo tee -a /etc/default/grub >/dev/null
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub || echo 'GRUB_DEFAULT=saved' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub && sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub || echo 'GRUB_SAVEDEFAULT=true' | sudo tee -a /etc/default/grub >/dev/null
    sudo sed -i 's@^GRUB_CMDLINE_LINUX_DEFAULT=.*@GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"@' /etc/default/grub || \
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"' | sudo tee -a /etc/default/grub >/dev/null

    # Enable submenu for additional kernels (linux-lts, linux-zen)
    grep -q '^GRUB_DISABLE_SUBMENU=' /etc/default/grub && sudo sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=notlinux/' /etc/default/grub || \
        echo 'GRUB_DISABLE_SUBMENU=notlinux' | sudo tee -a /etc/default/grub >/dev/null

    grep -q '^GRUB_GFXMODE=' /etc/default/grub || echo 'GRUB_GFXMODE=auto' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub || echo 'GRUB_GFXPAYLOAD_LINUX=keep' | sudo tee -a /etc/default/grub >/dev/null

    # Detect installed kernels
    KERNELS=($(ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||g'))
    if [[ ${#KERNELS[@]} -eq 0 ]]; then
        log_error "No kernels found in /boot."
        return 1
    fi

    # Determine main kernel and secondary kernels (logic kept for informational purposes, not used for default setting)
    MAIN_KERNEL=""
    SECONDARY_KERNELS=()
    for k in "${KERNELS[@]}"; do
        [[ "$k" == "linux" ]] && MAIN_KERNEL="$k"
        [[ "$k" != "linux" && "$k" != "fallback" && "$k" != "rescue" ]] && SECONDARY_KERNELS+=("$k")
    done
    [[ -z "$MAIN_KERNEL" ]] && MAIN_KERNEL="${KERNELS[0]}"

    # Remove fallback/recovery kernels
    sudo rm -f /boot/initramfs-*-fallback.img /boot/vmlinuz-*-fallback 2>/dev/null || true

    # Regenerate grub.cfg
    sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || { log_error "grub-mkconfig failed"; return 1; }

    log_success "GRUB configured to remember the last chosen boot entry."
}

# --- Console Font Setup ---
setup_console_font() {
    run_step "Installing console font" sudo pacman -S --noconfirm --needed terminus-font
    run_step "Configuring /etc/vconsole.conf" bash -c "(grep -q '^FONT=' /etc/vconsole.conf 2>/dev/null && sudo sed -i 's/^FONT=.*/FONT=ter-v16n/' /etc/vconsole.conf) || echo 'FONT=ter-v16n' | sudo tee -a /etc/vconsole.conf >/dev/null"
    run_step "Rebuilding initramfs" sudo mkinitcpio -P
}

# --- Boot Permission Fix ---
fix_boot_permissions() {
  log_info "Fixing Boot Partition permissions..."

  # Detect boot mount point
  local BOOT_MOUNT="/boot"
  if command -v bootctl >/dev/null 2>&1; then
      local ESP_PATH
      ESP_PATH=$(bootctl -p 2>/dev/null)
      if [ -n "$ESP_PATH" ] && [ -d "$ESP_PATH" ]; then
          BOOT_MOUNT="$ESP_PATH"
      fi
  fi

  # Fallback checks
  if [ ! -d "$BOOT_MOUNT" ] && [ -d "/efi" ]; then
      BOOT_MOUNT="/efi"
  elif [ ! -d "$BOOT_MOUNT" ] && [ -d "/boot/efi" ]; then
      BOOT_MOUNT="/boot/efi"
  fi

  log_info "Detected Boot Mount: $BOOT_MOUNT"

  if [ -d "$BOOT_MOUNT" ]; then
      log_info "Securing $BOOT_MOUNT..."

      # Ensure ownership is root:root
      sudo chown root:root "$BOOT_MOUNT" 2>/dev/null

      # Try chmod first
      sudo chmod 700 "$BOOT_MOUNT" 2>/dev/null

      # Check if permissions are correct
      local CURRENT_PERM
      CURRENT_PERM=$(stat -c "%a" "$BOOT_MOUNT")

      if [ "$CURRENT_PERM" != "700" ]; then
          log_warning "Permissions are $CURRENT_PERM (wanted 700). Checking /etc/fstab..."

          # Backup fstab
          sudo cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"

          # Prepare mount point for regex (escape slashes)
          local BOOT_ESC
          BOOT_ESC=$(echo "$BOOT_MOUNT" | sed 's/\//\\\//g')

          # Update fstab for BOOT_MOUNT if it exists
          if grep -q "[[:space:]]$BOOT_MOUNT[[:space:]]" /etc/fstab; then
              log_info "Checking permissions in /etc/fstab..."

              # Check for existing insecure masks and fix them
              if grep "[[:space:]]$BOOT_MOUNT[[:space:]]" /etc/fstab | grep -qE "fmask=|dmask=|umask="; then
                  log_info "Updating existing masks to 0077..."
                  sudo sed -i "/[[:space:]]$BOOT_ESC[[:space:]]/ s/fmask=[0-9]\+/fmask=0077/g" /etc/fstab
                  sudo sed -i "/[[:space:]]$BOOT_ESC[[:space:]]/ s/dmask=[0-9]\+/dmask=0077/g" /etc/fstab
                  sudo sed -i "/[[:space:]]$BOOT_ESC[[:space:]]/ s/umask=[0-9]\+/umask=0077/g" /etc/fstab
              else
                  log_info "Adding umask=0077 to $BOOT_MOUNT entry in /etc/fstab..."
                  # Attempt to append umask=0077 to the options field (4th column usually)
                  if grep -q "[[:space:]]$BOOT_ESC[[:space:]]\+vfat" /etc/fstab; then
                      sudo sed -i "/[[:space:]]$BOOT_ESC[[:space:]]\+vfat/ s/\(vfat[[:space:]]\+\)\([^[:space:]]\+\)/\1\2,umask=0077,fmask=0077,dmask=0077/" /etc/fstab
                  else
                      # Generic attempt to append to options (4th column)
                      sudo sed -i "/[[:space:]]$BOOT_ESC[[:space:]]/ s/\([[:space:]]\+\)\([^[:space:]]\+\)\([[:space:]]\+\)\([^[:space:]]\+\)/\1\2\3\4,umask=0077,fmask=0077,dmask=0077/" /etc/fstab
                  fi
              fi

              log_info "Reloading systemd..."
              sudo systemctl daemon-reload
          fi

          log_info "Remounting $BOOT_MOUNT with secure permissions..."
          sudo mount -o remount,umask=0077,fmask=0077,dmask=0077 "$BOOT_MOUNT"
      fi

      # Ensure ownership again (just in case)
      sudo chown root:root "$BOOT_MOUNT" 2>/dev/null

      # Check again
      CURRENT_PERM=$(stat -c "%a" "$BOOT_MOUNT")
      if [ "$CURRENT_PERM" == "700" ]; then
          log_success "$BOOT_MOUNT permissions secured."
      else
          log_error "Could not secure $BOOT_MOUNT permissions (Current: $CURRENT_PERM). Please check /etc/fstab manually."
      fi

      if [ -f "$BOOT_MOUNT/loader/random-seed" ]; then
          log_info "Setting permissions on $BOOT_MOUNT/loader/random-seed to 600..."
          sudo chmod 600 "$BOOT_MOUNT/loader/random-seed" || log_warning "Failed to chmod random-seed"
      fi
  fi
}

# --- Main execution ---
if [ "$BOOTLOADER" = "grub" ]; then
    configure_grub
elif [ "$BOOTLOADER" = "systemd-boot" ]; then
    configure_boot
else
    log_warning "No bootloader detected or bootloader is unsupported. Defaulting to systemd-boot configuration."
    configure_boot
fi

setup_console_font
fix_boot_permissions
