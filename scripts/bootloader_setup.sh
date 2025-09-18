#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Bootloader configuration variables
BOOTLOADER=""
IS_BTRFS=false

# --- Bootloader and Btrfs detection ---
detect_bootloader_and_filesystem() {
  step "Detecting bootloader and filesystem"

  if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
    BOOTLOADER="systemd-boot"
    log_success "Detected systemd-boot bootloader"
  elif [ -d /boot/grub ] || [ -f /etc/default/grub ]; then
    BOOTLOADER="grub"
    log_success "Detected GRUB bootloader"
  else
    BOOTLOADER="unknown"
    log_warning "Unknown bootloader detected"
  fi

  if findmnt -n -o FSTYPE / | grep -q btrfs; then
    IS_BTRFS=true
    log_success "Detected Btrfs filesystem"
  else
    IS_BTRFS=false
    log_success "Detected non-Btrfs filesystem"
  fi
}

# --- systemd-boot configuration ---
configure_systemd_boot() {
  step "Configuring systemd-boot"

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

    log_success "Configured systemd-boot loader settings"
  else
    log_warning "systemd-boot loader.conf not found"
  fi

  # Remove fallback entries
  sudo rm -f /boot/loader/entries/*fallback.conf 2>/dev/null || true
  log_success "Removed fallback boot entries"
}

# --- GRUB configuration ---
configure_grub() {
  step "Configuring GRUB bootloader"

  # Set kernel parameters for quiet boot
  sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3"/' /etc/default/grub

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

  # Show all kernels in main menu
  if grep -q '^GRUB_DISABLE_SUBMENU=' /etc/default/grub; then
    sudo sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub
  else
    echo 'GRUB_DISABLE_SUBMENU=y' | sudo tee -a /etc/default/grub
  fi

  # Regenerate grub config
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  log_success "Regenerated GRUB configuration"

  # Set default to preferred kernel on first run only (if grubenv doesn't exist yet)
  if [ ! -f /boot/grub/grubenv ]; then
    # Look for linux-zen first, then fallback to standard linux
    local default_entry=$(grep -P "menuentry 'Arch Linux.*zen'" /boot/grub/grub.cfg | grep -v "fallback" | head -n1 | sed "s/menuentry '\([^']*\)'.*/\1/")
    if [ -z "$default_entry" ]; then
      default_entry=$(grep -P "menuentry 'Arch Linux'" /boot/grub/grub.cfg | grep -v "fallback" | head -n1 | sed "s/menuentry '\([^']*\)'.*/\1/")
    fi
    if [ -n "$default_entry" ]; then
      sudo grub-set-default "$default_entry"
      log_success "Set GRUB default to: $default_entry"
    fi
  else
    log_success "GRUB environment exists, preserving @saved configuration"
  fi
}

# --- grub-btrfs installation if needed ---
install_grub_btrfs_if_needed() {
  if [ "$BOOTLOADER" = "grub" ] && [ "$IS_BTRFS" = true ]; then
    step "Installing grub-btrfs for Btrfs snapshots"

    if ! pacman -Q grub-btrfs &>/dev/null; then
      ensure_yay_installed
      yay -S --noconfirm grub-btrfs
      log_success "Installed grub-btrfs"
    else
      log_success "grub-btrfs already installed"
    fi

    # Show Btrfs snapshots in main menu
    if grep -q '^GRUB_BTRFS_SUBMENU=' /etc/default/grub; then
      sudo sed -i 's/^GRUB_BTRFS_SUBMENU=.*/GRUB_BTRFS_SUBMENU=n/' /etc/default/grub
    else
      echo 'GRUB_BTRFS_SUBMENU=n' | sudo tee -a /etc/default/grub
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
    log_success "Configured grub-btrfs with Timeshift integration"
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
  step "Adding Windows to GRUB menu"

  # Install os-prober for Windows detection
  install_packages_quietly os-prober

  # Ensure GRUB_DISABLE_OS_PROBER is not set to true
  if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
    sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
  else
    echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub
  fi

  # Regenerate GRUB config to include Windows
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  log_success "Added Windows entry to GRUB (if detected by os-prober)"
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
  step "Adding Windows to systemd-boot menu"

  # Only copy EFI files if not already present
  if [ ! -d "/boot/EFI/Microsoft" ]; then
    local windows_partition
    windows_partition=$(find_windows_efi_partition)
    if [ -z "$windows_partition" ]; then
      log_error "Could not find Windows EFI partition"
      return 1
    fi
    local mount_point="/mnt/winefi"
    mkdir -p "$mount_point"
    if mount "$windows_partition" "$mount_point"; then
      if [ -d "$mount_point/EFI/Microsoft" ]; then
        sudo cp -R "$mount_point/EFI/Microsoft" /boot/EFI/
        log_success "Copied Microsoft EFI files to /boot/EFI/Microsoft"
      else
        log_error "Microsoft EFI files not found in $windows_partition"
      fi
      umount "$mount_point"
    else
      log_error "Failed to mount Windows EFI partition"
    fi
    rm -rf "$mount_point"
  else
    log_success "Microsoft EFI files already present in /boot/EFI/Microsoft"
  fi

  # Create loader entry if not present
  local entry="/boot/loader/entries/windows.conf"
  if [ ! -f "$entry" ]; then
    cat <<EOF | sudo tee "$entry"
title   Windows
efi     /EFI/Microsoft/Boot/bootmgfw.efi
EOF
    log_success "Added Windows entry to systemd-boot"
  else
    log_success "Windows entry already exists in systemd-boot"
  fi
}

set_localtime_for_windows() {
  step "Setting hardware clock to local time for Windows compatibility"
  sudo timedatectl set-local-rtc 1 --adjust-system-clock
  log_success "Set hardware clock to local time for Windows compatibility"
}

configure_dual_boot() {
  if detect_windows; then
    log_info "Windows installation detected. Configuring dual-boot..."

    # Always install ntfs-3g for NTFS access
    install_packages_quietly ntfs-3g

    if [ "$BOOTLOADER" = "grub" ]; then
      add_windows_to_grub
    elif [ "$BOOTLOADER" = "systemd-boot" ]; then
      add_windows_to_systemdboot
    fi
    set_localtime_for_windows

    log_success "Dual-boot configuration completed"
  else
    log_info "No Windows installation detected, skipping dual-boot setup"
  fi
}

print_bootloader_summary() {
  echo -e "\n${CYAN}========= BOOTLOADER SETUP SUMMARY =========${RESET}"
  echo -e "${GREEN}✓ Bootloader: $BOOTLOADER${RESET}"
  echo -e "${GREEN}✓ Filesystem: $([ "$IS_BTRFS" = true ] && echo "Btrfs" || echo "Non-Btrfs")${RESET}"
  if detect_windows; then
    echo -e "${GREEN}✓ Windows dual-boot: Configured${RESET}"
  else
    echo -e "${YELLOW}✓ Windows dual-boot: Not needed${RESET}"
  fi
  echo -e "${CYAN}=============================================${RESET}"
}

# ======= Main =======
main() {
  echo -e "${CYAN}=== Bootloader and Kernel Configuration ===${RESET}"

  # Detect what we're working with
  detect_bootloader_and_filesystem

  # Configure bootloader based on what's detected
  if [ "$BOOTLOADER" = "systemd-boot" ]; then
    configure_systemd_boot
  elif [ "$BOOTLOADER" = "grub" ]; then
    configure_grub
    install_grub_btrfs_if_needed
  else
    log_warning "Unknown bootloader, skipping bootloader configuration"
  fi

  # Set up Windows dual-boot if needed
  configure_dual_boot

  print_bootloader_summary
}

main "$@"
