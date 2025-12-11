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

    # Verify configuration was applied
    if grep -q '^timeout' /boot/loader/loader.conf && grep -q '^console-mode' /boot/loader/loader.conf; then
      log_success "Systemd-boot configuration verified"
    else
      log_warning "Systemd-boot configuration may be incomplete"
    fi
  else
    log_warning "loader.conf not found. Skipping loader.conf configuration for systemd-boot."
  fi

  run_step "Removing systemd-boot fallback entries" sudo rm -f /boot/loader/entries/*fallback.conf

  # Check for fallback kernels (informational)
  local boot_mount=$(detect_boot_mount)
  local fallback_count=$(ls "$boot_mount"/*fallback* 2>/dev/null | wc -l)
  if [ "$fallback_count" -gt 0 ]; then
    log_info "Fallback kernels present: $fallback_count file(s)"
    log_info "These are useful for recovery but can be removed to save space"
  else
    log_success "No fallback kernels found (clean setup)"
  fi
}

# --- Bootloader and Btrfs detection ---
BOOTLOADER=$(detect_bootloader)
IS_BTRFS=$(is_btrfs_system && echo "true" || echo "false")

# --- Boot Partition Security ---
# Function to detect boot mount point
detect_boot_mount() {
  local boot_mount="/boot"

  # Try to detect ESP for systemd-boot
  if command -v bootctl >/dev/null 2>&1; then
    local esp_path=$(bootctl -p 2>/dev/null)
    if [ -n "$esp_path" ] && [ -d "$esp_path" ]; then
      boot_mount="$esp_path"
    fi
  fi

  # Fallback checks
  if [ ! -d "$boot_mount" ] && [ -d "/efi" ]; then
    boot_mount="/efi"
  elif [ ! -d "$boot_mount" ] && [ -d "/boot/efi" ]; then
    boot_mount="/boot/efi"
  fi

  echo "$boot_mount"
}

# Function to secure boot partition permissions
# This fixes the common issue where ESP (FAT32) partitions have insecure permissions
# Reference: Arch Linux Wiki - EFI System Partition security
secure_boot_permissions() {
  step "Securing boot partition permissions"

  local boot_mount=$(detect_boot_mount)

  if [ ! -d "$boot_mount" ]; then
    log_warning "Boot directory not accessible: $boot_mount"
    return 0  # Not a fatal error
  fi

  log_info "Boot partition detected at: $boot_mount"

  # Check current permissions
  local current_perm=$(stat -c "%a" "$boot_mount" 2>/dev/null || echo "unknown")
  log_info "Current permissions: $current_perm"

  # Check if already secure (700)
  if [ "$current_perm" = "700" ]; then
    log_success "Boot partition permissions are already secure (700)"
    return 0
  fi

  # Try standard chmod first (works for ext4, btrfs, etc.)
  log_info "Attempting to set permissions to 700..."
  if sudo chmod 700 "$boot_mount" 2>/dev/null; then
    # Verify it worked
    local new_perm=$(stat -c "%a" "$boot_mount" 2>/dev/null)
    if [ "$new_perm" = "700" ]; then
      log_success "Boot partition permissions set to 700"
      return 0
    fi
  fi

  # If chmod failed, likely FAT32 (ESP) - need mount options
  log_info "chmod failed (likely FAT32 filesystem). Using mount options..."

  # Get filesystem type
  local fstype=$(findmnt -no FSTYPE "$boot_mount" 2>/dev/null || echo "unknown")

  if [[ "$fstype" =~ ^(vfat|fat|msdos)$ ]]; then
    log_info "FAT32 filesystem detected - using mount options (fmask/dmask)"

    # Try remounting with secure permissions
    if sudo mount -o remount,fmask=0077,dmask=0077 "$boot_mount" 2>/dev/null; then
      log_success "Remounted with secure permissions (fmask=0077,dmask=0077)"
    elif sudo mount -o remount,umask=0077 "$boot_mount" 2>/dev/null; then
      log_success "Remounted with secure permissions (umask=0077)"
    else
      log_warning "Failed to remount with secure permissions"
      log_info "This may require manual intervention or a reboot"
      return 1
    fi

    # Update /etc/fstab for persistence
    if [ -f /etc/fstab ]; then
      log_info "Updating /etc/fstab to persist secure permissions..."

      # Escape mount point for sed
      local boot_esc=$(echo "$boot_mount" | sed 's/\//\\\//g')

      if grep -q "[[:space:]]$boot_mount[[:space:]]" /etc/fstab; then
        # Check if mask options already exist
        if grep "[[:space:]]$boot_mount[[:space:]]" /etc/fstab | grep -qE "mask="; then
          # Update existing masks
          sudo sed -i "/[[:space:]]$boot_esc[[:space:]]/ s/fmask=[0-9]\+/fmask=0077/g" /etc/fstab
          sudo sed -i "/[[:space:]]$boot_esc[[:space:]]/ s/dmask=[0-9]\+/dmask=0077/g" /etc/fstab
          sudo sed -i "/[[:space:]]$boot_esc[[:space:]]/ s/umask=[0-9]\+/umask=0077/g" /etc/fstab
          log_success "Updated existing mask options in /etc/fstab"
        else
          # Append masks to options column
          sudo sed -i "/[[:space:]]$boot_esc[[:space:]]/ s/\(vfat\|auto\|msdos\|fat\)\([[:space:]]\+\)\([^[:space:]]\+\)/\1\2\3,fmask=0077,dmask=0077/" /etc/fstab
          log_success "Added mask options to /etc/fstab"
        fi

        # Reload systemd to apply changes
        sudo systemctl daemon-reload 2>/dev/null || true
      else
        log_warning "$boot_mount not found in /etc/fstab"
        log_info "Permissions fix will be lost on reboot. Please add mount options manually."
      fi
    fi

    # Also fix random-seed permissions if it exists (systemd-boot)
    if [ -f "$boot_mount/loader/random-seed" ]; then
      local seed_perm=$(stat -c "%a" "$boot_mount/loader/random-seed" 2>/dev/null || echo "unknown")
      if [ "$seed_perm" != "600" ]; then
        log_info "Fixing random-seed permissions..."
        sudo chmod 600 "$boot_mount/loader/random-seed" 2>/dev/null || true
      fi
    fi

    log_success "Boot partition permissions secured"
    return 0
  else
    log_warning "Unknown filesystem type: $fstype"
    log_info "Cannot automatically fix permissions for this filesystem type"
    return 1
  fi
}

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

    # Check for remaining fallback kernels (informational)
    local fallback_count=$(ls /boot/*fallback* 2>/dev/null | wc -l)
    if [ "$fallback_count" -gt 0 ]; then
      log_info "Fallback kernels still present: $fallback_count file(s)"
      log_info "These are useful for recovery but can be removed to save space"
    else
      log_success "No fallback kernels found (clean setup)"
    fi

    # Regenerate grub.cfg
    sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || { log_error "grub-mkconfig failed"; return 1; }

    # Verify GRUB configuration
    if grep -q '^GRUB_DEFAULT=saved' /etc/default/grub && grep -q '^GRUB_SAVEDEFAULT=true' /etc/default/grub; then
      log_success "GRUB configured to remember the last chosen boot entry"
    else
      log_warning "GRUB save default configuration may be incomplete"
    fi
}

# --- Console Font Setup ---
setup_console_font() {
    run_step "Installing console font" sudo pacman -S --noconfirm --needed terminus-font
    run_step "Configuring /etc/vconsole.conf" bash -c "(grep -q '^FONT=' /etc/vconsole.conf 2>/dev/null && sudo sed -i 's/^FONT=.*/FONT=ter-v16n/' /etc/vconsole.conf) || echo 'FONT=ter-v16n' | sudo tee -a /etc/vconsole.conf >/dev/null"
    run_step "Rebuilding initramfs" sudo mkinitcpio -P
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

# Secure boot partition permissions (important for ESP/FAT32 security)
secure_boot_permissions

setup_console_font
