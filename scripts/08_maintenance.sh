#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Function to perform general system cleanup
cleanup_and_optimize() {
  step "Performing final cleanup and optimizations"
  run_step "Cleaning /tmp directory" sudo rm -rf /tmp/*
  run_step "Syncing disk writes" sync
}

# Function to run package manager cleanups
setup_maintenance() {
  step "Performing comprehensive system cleanup"

  # Use the PKG_CLEAN variable from distro_check.sh
  log_info "Cleaning package manager cache..."
  if ! $PKG_CLEAN >> "$INSTALL_LOG" 2>&1; then
    log_warn "Package manager cache clean command failed. Check log."
  else
    log_success "Package manager cache cleaned."
  fi

  if command -v yay >/dev/null 2>&1; then
    log_info "Cleaning yay cache..."
    if ! yay -Yc --noconfirm >> "$INSTALL_LOG" 2>&1; then
        log_warn "yay cache clean failed."
    else
        log_success "Yay cache cleaned."
    fi
  fi

  if command -v flatpak >/dev/null 2>&1; then
    log_info "Removing unused flatpak packages..."
    flatpak uninstall --unused -y >> "$INSTALL_LOG" 2>&1
    log_success "Flatpak cleanup complete."
  fi

  # Remove orphaned packages (distro-specific)
  if [[ "$DISTRO_ID" == "arch" ]]; then
    log_info "Checking for orphaned packages..."
    orphans=$(pacman -Qtdq)
    if [ -n "$orphans" ]; then
      # Use the silent install_pkg wrapper for removal
      remove_pkg $orphans
    else
      log_success "No orphaned packages to remove."
    fi
  fi
}

# Function to set up Btrfs snapshots with Snapper
setup_btrfs_snapshots_system() {
  # This setup is complex and primarily designed for Arch Linux at the moment
  if [[ "$DISTRO_ID" != "arch" ]]; then
    return
  fi

  if ! is_btrfs_system; then
    log_info "System is not on a Btrfs root filesystem. Skipping snapshot setup."
    return
  fi

  if gum confirm "Would you like to set up automatic Btrfs snapshots with Snapper?"; then
    step "Setting up Btrfs snapshots system"
    local bootloader
    bootloader=$(detect_bootloader)
    log_info "Detected bootloader: $bootloader"

    step "Installing snapshot management packages"
    local packages=()
    # Define packages based on bootloader
    if [[ "$bootloader" == "grub" ]]; then
      packages=(snapper snap-pac grub-btrfs btrfsmaintenance linux-lts linux-lts-headers btrfs-assistant)
    else # Default to systemd-boot compatible packages
      packages=(snapper snap-pac btrfsmaintenance linux-lts linux-lts-headers btrfs-assistant)
    fi

    # THIS IS THE FIX: Use the silent install_pkg helper from common.sh
    install_pkg "${packages[@]}"

    if [ $? -ne 0 ]; then
      log_error "Failed to install snapshot management packages. Btrfs snapshot setup aborted."
      return 1
    fi

    # Configure Snapper, timers, and GRUB if applicable
    log_info "Configuring Snapper..."
    sudo snapper -c root create-config / >> "$INSTALL_LOG" 2>&1
    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer >> "$INSTALL_LOG" 2>&1
    sudo systemctl enable --now btrfs-scrub@-.timer btrfs-balance@-.timer btrfs-defrag@-.timer >> "$INSTALL_LOG" 2>&1

    if [[ "$bootloader" == "grub" ]]; then
        log_info "Updating GRUB for Btrfs snapshots..."
        sudo grub-mkconfig -o /boot/grub/grub.cfg >> "$INSTALL_LOG" 2>&1
    fi

    log_success "Btrfs snapshot setup completed successfully!"
  else
    log_info "Skipping Btrfs snapshot setup."
  fi
}

# Function to secure the boot partition
secure_boot_partition() {
    step "Securing boot partition permissions"
    local boot_mount
    boot_mount=$(detect_boot_mount)

    if [ -z "$boot_mount" ]; then
        log_warn "Could not determine boot mount point. Skipping permission hardening."
        return
    fi

    log_info "Boot partition detected at: $boot_mount"

    # Try chmod first
    if sudo chmod 700 "$boot_mount"; then
        log_success "Set boot partition permissions to 700."
    else
        log_info "chmod failed (likely FAT32). Using mount options..."
        # Fallback for FAT32
        if grep -q "$boot_mount" /etc/fstab; then
            if grep -q "fmask=0077,dmask=0077" /etc/fstab; then
                log_info "Secure mount options already present in /etc/fstab."
            else
                sudo sed -i "s|\($boot_mount.*defaults\)|\\1,fmask=0077,dmask=0077|" /etc/fstab
                sudo mount -o remount "$boot_mount"
                log_success "Updated /etc/fstab and remounted with secure permissions."
            fi
        else
            log_error "Could not find boot partition in /etc/fstab to apply secure mount options."
        fi
    fi
}


# --- Main Execution ---
cleanup_and_optimize
setup_maintenance
setup_btrfs_snapshots_system
secure_boot_partition

log_success "Maintenance and optimization completed."
