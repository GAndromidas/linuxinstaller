#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Use different variable names to avoid conflicts
PLYMOUTH_ERRORS=()

# ======= Plymouth Setup Steps =======
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
  local kernel_types
  kernel_types=($(get_installed_kernel_types))

  if [ "${#kernel_types[@]}" -eq 0 ]; then
    log_warning "No supported kernel types detected. Rebuilding only for 'linux'."
    sudo mkinitcpio -p linux
    return
  fi

  echo -e "${CYAN}Detected kernels: ${kernel_types[*]}${RESET}"

  local total=${#kernel_types[@]}
  local current=0

  for kernel in "${kernel_types[@]}"; do
    ((current++))
    print_progress "$current" "$total" "Rebuilding initramfs for $kernel"

    if sudo mkinitcpio -p "$kernel" >/dev/null 2>&1; then
      print_status " [OK]" "$GREEN"
      log_success "Rebuilt initramfs for $kernel"
    else
      print_status " [FAIL]" "$RED"
      log_error "Failed to rebuild initramfs for $kernel"
    fi
  done

  echo -e "\n${GREEN}✓ Initramfs rebuild completed for all kernels${RESET}\n"
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
  # Detect bootloader
  if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
    # systemd-boot logic (existing)
    local boot_entries_dir="/boot/loader/entries"
    if [ ! -d "$boot_entries_dir" ]; then
      log_warning "Boot entries directory not found. Skipping kernel parameter addition."
      return
    fi
    local boot_entries=()
    while IFS= read -r -d '' entry; do
      boot_entries+=("$entry")
    done < <(find "$boot_entries_dir" -name "*.conf" -print0 2>/dev/null)
    if [ ${#boot_entries[@]} -eq 0 ]; then
      log_warning "No boot entries found. Skipping kernel parameter addition."
      return
    fi
    echo -e "${CYAN}Found ${#boot_entries[@]} boot entries${RESET}"
    local total=${#boot_entries[@]}
    local current=0
    local modified_count=0
    for entry in "${boot_entries[@]}"; do
      ((current++))
      local entry_name=$(basename "$entry")
      print_progress "$current" "$total" "Adding splash to $entry_name"
      if ! grep -q "splash" "$entry"; then
        if sudo sed -i '/^options / s/$/ splash/' "$entry"; then
          print_status " [OK]" "$GREEN"
          log_success "Added 'splash' to $entry_name"
          ((modified_count++))
        else
          print_status " [FAIL]" "$RED"
          log_error "Failed to add 'splash' to $entry_name"
        fi
      else
        print_status " [SKIP] Already has splash" "$YELLOW"
        log_warning "'splash' already set in $entry_name"
      fi
    done
    echo -e "\n${GREEN}✓ Kernel parameters updated for all boot entries (${modified_count} modified)${RESET}\n"
  elif [ -d /boot/grub ] || [ -f /etc/default/grub ]; then
    # GRUB logic
    if grep -q 'splash' /etc/default/grub; then
      log_warning "'splash' already present in GRUB_CMDLINE_LINUX_DEFAULT."
    else
      sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="splash /' /etc/default/grub
      log_success "Added 'splash' to GRUB_CMDLINE_LINUX_DEFAULT."
      sudo grub-mkconfig -o /boot/grub/grub.cfg
      log_success "Regenerated grub.cfg after adding 'splash'."
    fi
  else
    log_warning "No supported bootloader detected for kernel parameter addition."
  fi
}

# ======= Bootloader Configuration Functions =======

# Apply all boot configurations at once
configure_boot() {
  # Make systemd-boot silent
  find /boot/loader/entries -name "*.conf" ! -name "*fallback.conf" -exec \
    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' {} \; 2>/dev/null || true

  # Configure loader.conf
  if [ -f "/boot/loader/loader.conf" ]; then
    sudo sed -i \
      -e '/^default /d' \
      -e '1i default @saved' \
      -e 's/^timeout.*/timeout 3/' \
      -e 's/^[#]*console-mode[[:space:]]\+.*/console-mode max/' \
      /boot/loader/loader.conf

    # Add missing lines
    grep -q '^timeout' /boot/loader/loader.conf || echo "timeout 3" | sudo tee -a /boot/loader/loader.conf >/dev/null
    grep -q '^console-mode' /boot/loader/loader.conf || echo "console-mode max" | sudo tee -a /boot/loader/loader.conf >/dev/null
  fi

  # Remove fallback entries
  sudo rm -f /boot/loader/entries/*fallback.conf 2>/dev/null || true
}

setup_fastfetch_config() {
  if command -v fastfetch >/dev/null; then
    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
      log_warning "fastfetch config already exists. Skipping generation."
    else
      run_step "Creating fastfetch config" bash -c 'fastfetch --gen-config'
    fi

    # Safe config file copy
    if [ -f "$CONFIGS_DIR/config.jsonc" ]; then
      mkdir -p "$HOME/.config/fastfetch"
      cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
      log_success "fastfetch config copied from configs directory."
    else
      log_warning "config.jsonc not found in configs directory. Using generated config."
    fi
  else
    log_warning "fastfetch not installed. Skipping config setup."
  fi
}

# --- Bootloader and Btrfs detection ---
detect_bootloader_and_filesystem() {
  if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
      BOOTLOADER="systemd-boot"
  elif [ -d /boot/grub ] || [ -f /etc/default/grub ]; then
      BOOTLOADER="grub"
  else
      BOOTLOADER="unknown"
  fi

  if findmnt -n -o FSTYPE / | grep -q btrfs; then
      IS_BTRFS=true
  else
      IS_BTRFS=false
  fi
}

# --- GRUB configuration ---
configure_grub() {
    # Set kernel parameters for Plymouth and quiet boot
    sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"/' /etc/default/grub

    # Set default entry to saved and enable save default
    if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
    else
        echo 'GRUB_DEFAULT=saved' | sudo tee -a /etc/default/grub
    fi
    if grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub
    else
        echo 'GRUB_SAVEDEFAULT=true' | sudo tee -a /etc/default/grub
    fi

    # Set timeout to 3 seconds
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

    # Set console mode (gfxmode)
    grep -q '^GRUB_GFXMODE=' /etc/default/grub || echo 'GRUB_GFXMODE=auto' | sudo tee -a /etc/default/grub
    grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub || echo 'GRUB_GFXPAYLOAD_LINUX=keep' | sudo tee -a /etc/default/grub

    # Remove all fallback initramfs images
    sudo rm -f /boot/initramfs-*-fallback.img

    # Show all kernels and fallback entries in main menu
    if grep -q '^GRUB_DISABLE_SUBMENU=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub
    else
        echo 'GRUB_DISABLE_SUBMENU=y' | sudo tee -a /etc/default/grub
    fi

    # Show Btrfs snapshots in main menu if grub-btrfs is installed
    if pacman -Q grub-btrfs &>/dev/null; then
        if grep -q '^GRUB_BTRFS_SUBMENU=' /etc/default/grub; then
            sudo sed -i 's/^GRUB_BTRFS_SUBMENU=.*/GRUB_BTRFS_SUBMENU=n/' /etc/default/grub
        else
            echo 'GRUB_BTRFS_SUBMENU=n' | sudo tee -a /etc/default/grub
        fi
    fi

    # Regenerate grub config
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    # Set default to preferred kernel on first run only (if grubenv doesn't exist yet)
    if [ ! -f /boot/grub/grubenv ]; then
        # Look for linux-zen first, then fallback to standard linux
        default_entry=$(grep -P "menuentry 'Arch Linux.*zen'" /boot/grub/grub.cfg | grep -v "fallback" | head -n1 | sed "s/menuentry '\([^']*\)'.*/\1/")
        if [ -z "$default_entry" ]; then
            default_entry=$(grep -P "menuentry 'Arch Linux'" /boot/grub/grub.cfg | grep -v "fallback" | head -n1 | sed "s/menuentry '\([^']*\)'.*/\1/")
        fi
        if [ -n "$default_entry" ]; then
            sudo grub-set-default "$default_entry"
            echo "Set GRUB default to: $default_entry"
        fi
    else
        echo "GRUB environment exists, preserving @saved configuration"
    fi
}

# --- grub-btrfs installation if needed ---
install_grub_btrfs_if_needed() {
    if [ "$BOOTLOADER" = "grub" ] && [ "$IS_BTRFS" = true ]; then
        if ! pacman -Q grub-btrfs &>/dev/null; then
            yay -S --noconfirm grub-btrfs
        fi
        # Add Timeshift post-snapshot hook for grub-btrfs
        sudo mkdir -p /etc/timeshift/scripts
        sudo tee /etc/timeshift/scripts/post-snapshot > /dev/null <<'EOF'
#!/bin/bash
# Timeshift post-snapshot hook to update GRUB menu with new Btrfs snapshots
if command -v grub-btrfsd &>/dev/null; then
    sudo grub-btrfsd --syslog --once /boot/grub
fi
EOF
        sudo chmod +x /etc/timeshift/scripts/post-snapshot
    fi
}

# --- Windows Dual-Boot Detection and Configuration ---

detect_windows() {
    # Check for Windows EFI bootloader
    if [ -d /boot/efi/EFI/Microsoft ] || [ -d /boot/EFI/Microsoft ]; then
        return 0
    fi
    # Check for NTFS partitions (Windows)
    if lsblk -f | grep -qi ntfs; then
        return 0
    fi
    return 1
}

add_windows_to_grub() {
    sudo pacman -S --noconfirm os-prober
    # Ensure GRUB_DISABLE_OS_PROBER is not set to true
    if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    else
        echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub
    fi
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo "Windows entry added to GRUB (if detected by os-prober)."
}

find_windows_efi_partition() {
    local partitions=($(lsblk -n -o NAME,TYPE | grep "part" | awk '{print "/dev/"$1}'))
    for partition in "${partitions[@]}"; do
        local temp_mount="/tmp/windows_efi_check"
        mkdir -p "$temp_mount"
        if mount "$partition" "$temp_mount" 2>/dev/null; then
            if [ -d "$temp_mount/EFI/Microsoft" ]; then
                umount "$temp_mount"
                rm -rf "$temp_mount"
                echo "$partition"
                return 0
            fi
            umount "$temp_mount"
        fi
        rm -rf "$temp_mount"
    done
    return 1
}

add_windows_to_systemdboot() {
    # Only copy EFI files if not already present
    if [ ! -d "/boot/EFI/Microsoft" ]; then
        local windows_partition
        windows_partition=$(find_windows_efi_partition)
        if [ -z "$windows_partition" ]; then
            echo "Error: Could not find Windows EFI partition"
            return 1
        fi
        local mount_point="/mnt/winefi"
        mkdir -p "$mount_point"
        if mount "$windows_partition" "$mount_point"; then
            if [ -d "$mount_point/EFI/Microsoft" ]; then
                cp -R "$mount_point/EFI/Microsoft" /boot/EFI/
                echo "Copied Microsoft EFI files to /boot/EFI/Microsoft."
            else
                echo "Error: Microsoft EFI files not found in $windows_partition"
            fi
            umount "$mount_point"
        else
            echo "Error: Failed to mount Windows EFI partition"
        fi
        rm -rf "$mount_point"
    else
        echo "Microsoft EFI files already present in /boot/EFI/Microsoft."
    fi

    # Create loader entry if not present
    local entry="/boot/loader/entries/windows.conf"
    if [ ! -f "$entry" ]; then
        cat <<EOF | sudo tee "$entry"
title   Windows
efi     /EFI/Microsoft/Boot/bootmgfw.efi
EOF
        echo "Added Windows entry to systemd-boot."
    else
        echo "Windows entry already exists in systemd-boot."
    fi
}

set_localtime_for_windows() {
    sudo timedatectl set-local-rtc 1 --adjust-system-clock
    echo "Set hardware clock to local time for Windows compatibility."
}

print_summary() {
  echo -e "\n${CYAN}========= BOOT SETUP SUMMARY =========${RESET}"
  if [ ${#PLYMOUTH_ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}Boot configuration completed successfully!${RESET}"
  else
    echo -e "${RED}Some configuration steps failed:${RESET}"
    for err in "${PLYMOUTH_ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  fi
  echo -e "${CYAN}=======================================${RESET}"
}

# ======= Main =======
main() {
  # Print simple banner (no figlet)
  echo -e "${CYAN}=== Boot Setup Configuration ===${RESET}"

  # Plymouth configuration
  run_step "Adding plymouth hook to mkinitcpio.conf" enable_plymouth_hook
  run_step "Rebuilding initramfs for all kernels" rebuild_initramfs
  run_step "Setting Plymouth theme" set_plymouth_theme
  run_step "Adding 'splash' to all kernel parameters" add_kernel_parameters

  # Bootloader configuration
  detect_bootloader_and_filesystem

  # Execute ultra-fast boot configuration
  if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
      configure_boot
  fi
  setup_fastfetch_config

  # Apply GRUB config if needed
  if [ "$BOOTLOADER" = "grub" ]; then
      configure_grub
      install_grub_btrfs_if_needed
  fi

  # Windows dual-boot configuration
  if detect_windows; then
      echo "Windows installation detected. Configuring dual-boot..."
      # Always install ntfs-3g for NTFS access
      sudo pacman -S --noconfirm ntfs-3g

      if [ "$BOOTLOADER" = "grub" ]; then
          add_windows_to_grub
      elif [ "$BOOTLOADER" = "systemd-boot" ]; then
          add_windows_to_systemdboot
      fi
      set_localtime_for_windows
  fi

  print_summary
}

main "$@"
