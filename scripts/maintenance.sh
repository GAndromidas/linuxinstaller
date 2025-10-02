#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cleanup_and_optimize() {
  step "Performing final cleanup and optimizations"
  # Check if lsblk is available for SSD detection
  if command_exists lsblk; then
    if lsblk -d -o rota | grep -q '^0$'; then
      run_step "Running fstrim on SSDs" sudo fstrim -v /
    fi
  else
    log_warning "lsblk not available. Skipping SSD optimization."
  fi
  run_step "Cleaning /tmp directory" sudo rm -rf /tmp/*
  run_step "Syncing disk writes" sync
}

setup_maintenance() {
  step "Performing comprehensive system cleanup"
  run_step "Cleaning pacman cache" sudo pacman -Sc --noconfirm
  run_step "Cleaning yay cache" yay -Sc --noconfirm

  # Flatpak cleanup - remove unused packages and runtimes
  if command -v flatpak >/dev/null 2>&1; then
    run_step "Removing unused flatpak packages" sudo flatpak uninstall --unused --noninteractive -y
    run_step "Removing unused flatpak runtimes" sudo flatpak uninstall --unused --noninteractive -y
    log_success "Flatpak cleanup completed"
  else
    log_info "Flatpak not installed, skipping flatpak cleanup"
  fi

  # Remove orphaned packages if any exist
  if pacman -Qtdq &>/dev/null; then
    run_step "Removing orphaned packages" sudo pacman -Rns $(pacman -Qtdq) --noconfirm
  else
    log_info "No orphaned packages found"
  fi

  # Only attempt to remove yay-debug if it's actually installed
  if pacman -Q yay-debug &>/dev/null; then
    run_step "Removing yay-debug package" yay -Rns yay-debug --noconfirm
  fi
}

cleanup_helpers() {
  run_step "Cleaning yay build dir" sudo rm -rf /tmp/yay
}

# Update mirrorlist using rate-mirrors if installed
update_mirrorlist_with_rate_mirrors() {
  step "Updating mirrorlist with rate-mirrors"
  if command -v rate-mirrors >/dev/null 2>&1; then
    run_step "Updating mirrorlist with fastest mirrors" sudo rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch
    log_success "Mirrorlist updated successfully with rate-mirrors"
  else
    log_warning "rate-mirrors not found. Mirrorlist update skipped."
  fi
}

# Check if system uses Btrfs filesystem
is_btrfs_system() {
  findmnt -no FSTYPE / | grep -q btrfs
}

# Detect bootloader type
detect_bootloader() {
  if [ -d "/boot/grub" ] || [ -d "/boot/grub2" ] || [ -d "/boot/efi/EFI/grub" ] || command -v grub-mkconfig &>/dev/null || pacman -Q grub &>/dev/null 2>&1; then
    echo "grub"
  elif [ -d "/boot/loader/entries" ] || [ -d "/efi/loader/entries" ] || command -v bootctl &>/dev/null; then
    echo "systemd-boot"
  else
    echo "unknown"
  fi
}

# Configure Snapper settings
configure_snapper() {
  step "Configuring Snapper for root filesystem"

  # Backup existing config if present
  if [ -f /etc/snapper/configs/root ]; then
    log_info "Snapper config already exists. Creating backup..."
    sudo cp /etc/snapper/configs/root /etc/snapper/configs/root.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    log_info "Updating existing Snapper configuration..."
  else
    log_info "Creating new Snapper configuration..."
    if ! sudo snapper -c root create-config / 2>/dev/null; then
      log_error "Failed to create Snapper configuration"
      return 1
    fi
  fi

  # Configure Snapper settings for reasonable snapshot retention
  sudo sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' /etc/snapper/configs/root
  sudo sed -i 's/^NUMBER_CLEANUP=.*/NUMBER_CLEANUP="yes"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root

  log_success "Snapper configuration completed (5 hourly, 7 daily snapshots)"
}

# Setup GRUB bootloader for snapshots
setup_grub_bootloader() {
  step "Configuring GRUB bootloader for snapshot support"

  # Install grub-btrfs for automatic snapshot boot entries
  if ! pacman -Q grub-btrfs &>/dev/null; then
    log_info "Installing grub-btrfs for snapshot support..."
    install_packages_quietly grub-btrfs
  else
    log_info "grub-btrfs already installed"
  fi

  # Enable grub-btrfsd daemon for automatic menu updates
  if command -v grub-btrfsd &>/dev/null; then
    log_info "Enabling grub-btrfsd service for automatic snapshot detection..."
    sudo systemctl enable --now grub-btrfsd.service 2>/dev/null || log_warning "Failed to enable grub-btrfsd service"
  fi

  # Regenerate GRUB configuration
  log_info "Regenerating GRUB configuration..."
  if sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null; then
    log_success "GRUB configuration complete - snapshots will appear in boot menu"
  else
    log_error "Failed to regenerate GRUB configuration"
    return 1
  fi
}

# Setup systemd-boot bootloader for LTS kernel
setup_systemd_boot() {
  step "Configuring systemd-boot for LTS kernel fallback"

  local BOOT_DIR="/boot/loader/entries"

  # Find existing Arch Linux boot entry
  local TEMPLATE=$(find "$BOOT_DIR" -name "*arch*.conf" -o -name "*linux.conf" 2>/dev/null | grep -v lts | head -n1)

  if [ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ]; then
    local BASE=$(basename "$TEMPLATE" .conf)
    local LTS_ENTRY="$BOOT_DIR/${BASE}-lts.conf"

    if [ ! -f "$LTS_ENTRY" ]; then
      log_info "Creating systemd-boot entry for linux-lts kernel..."

      # Backup original template
      sudo cp "$TEMPLATE" "${TEMPLATE}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true

      sudo cp "$TEMPLATE" "$LTS_ENTRY"
      sudo sed -i 's/^title .*/title Arch Linux (LTS Kernel)/' "$LTS_ENTRY"
      sudo sed -i 's|vmlinuz-linux\>|vmlinuz-linux-lts|g' "$LTS_ENTRY"
      sudo sed -i 's|initramfs-linux\.img|initramfs-linux-lts.img|g' "$LTS_ENTRY"
      sudo sed -i 's|initramfs-linux-fallback\.img|initramfs-linux-lts-fallback.img|g' "$LTS_ENTRY"
      log_success "LTS kernel boot entry created: $LTS_ENTRY"
    else
      log_info "LTS kernel boot entry already exists"
    fi
  else
    log_warning "Could not find systemd-boot template. You may need to manually create LTS boot entry"
    return 1
  fi
}

# Setup pacman hook for snapshot notifications
setup_pacman_hook() {
  step "Installing pacman hook for snapshot notifications"

  sudo mkdir -p /etc/pacman.d/hooks

  # Backup existing hook if present
  if [ -f /etc/pacman.d/hooks/snapper-notify.hook ]; then
    sudo cp /etc/pacman.d/hooks/snapper-notify.hook /etc/pacman.d/hooks/snapper-notify.hook.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
  fi

  cat << 'EOF' | sudo tee /etc/pacman.d/hooks/snapper-notify.hook >/dev/null
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Snapshot notification
When = PostTransaction
Exec = /usr/bin/sh -c 'echo ""; echo "System snapshot created before package changes."; echo "View snapshots: sudo snapper list"; echo "Rollback if needed: sudo snapper rollback <number>"; echo ""'
EOF

  log_success "Pacman hook installed - you'll be notified after package operations"
}

# Main Btrfs snapshot setup function
setup_btrfs_snapshots() {
  # Check if system uses Btrfs
  if ! is_btrfs_system; then
    log_info "Root filesystem is not Btrfs. Snapshot setup skipped."
    return 0
  fi

  log_info "Btrfs filesystem detected on root partition"

  # Check available disk space
  local AVAILABLE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
  if [ "$AVAILABLE_SPACE" -lt 20 ]; then
    log_warning "Low disk space detected: ${AVAILABLE_SPACE}GB available (20GB+ recommended)"
  else
    log_success "Sufficient disk space available: ${AVAILABLE_SPACE}GB"
  fi

  # Ask user if they want to set up snapshots
  local setup_snapshots=false
  if command -v gum >/dev/null 2>&1; then
    echo ""
    gum style --foreground 226 "Btrfs snapshot setup available:"
    gum style --margin "0 2" --foreground 15 "• Automatic snapshots before/after package operations"
    gum style --margin "0 2" --foreground 15 "• Retention: 5 hourly, 7 daily snapshots"
    gum style --margin "0 2" --foreground 15 "• LTS kernel fallback for recovery"
    gum style --margin "0 2" --foreground 15 "• GUI tool (btrfs-assistant) for snapshot management"
    echo ""
    if gum confirm --default=false "Would you like to set up automatic Btrfs snapshots?"; then
      setup_snapshots=true
    fi
  else
    echo ""
    echo -e "${YELLOW}Btrfs snapshot setup available:${RESET}"
    echo -e "  • Automatic snapshots before/after package operations"
    echo -e "  • Retention: 5 hourly, 7 daily snapshots"
    echo -e "  • LTS kernel fallback for recovery"
    echo -e "  • GUI tool (btrfs-assistant) for snapshot management"
    echo ""
    read -r -p "Would you like to set up automatic Btrfs snapshots? [y/N]: " response
    response=${response,,}
    if [[ "$response" == "y" || "$response" == "yes" ]]; then
      setup_snapshots=true
    fi
  fi

  if [ "$setup_snapshots" = false ]; then
    log_info "Btrfs snapshot setup skipped by user"
    return 0
  fi

  # Detect bootloader
  local BOOTLOADER=$(detect_bootloader)
  log_info "Detected bootloader: $BOOTLOADER"

  step "Setting up Btrfs snapshots system"

  # Remove Timeshift if installed (conflicts with Snapper)
  if pacman -Q timeshift &>/dev/null; then
    log_warning "Timeshift detected - removing to avoid conflicts with Snapper"
    sudo pacman -Rns --noconfirm timeshift 2>/dev/null || log_warning "Could not remove Timeshift cleanly"
  fi

  # Clean up Timeshift snapshots if they exist
  if [ -d "/timeshift-btrfs" ]; then
    log_info "Cleaning up Timeshift snapshot directory..."
    sudo rm -rf /timeshift-btrfs 2>/dev/null || log_warning "Could not remove Timeshift directory"
  fi

  # Install required packages
  step "Installing snapshot management packages"
  log_info "Installing: snapper, snap-pac, btrfs-assistant, linux-lts"

  # Update package database first
  sudo pacman -Sy >/dev/null 2>&1 || log_warning "Failed to update package database"

  # Install packages
  install_packages_quietly snapper snap-pac btrfs-assistant linux-lts linux-lts-headers

  # Configure Snapper
  configure_snapper || { log_error "Snapper configuration failed"; return 1; }

  # Enable Snapper timers
  step "Enabling Snapper automatic snapshot timers"
  if sudo systemctl enable --now snapper-timeline.timer 2>/dev/null && \
     sudo systemctl enable --now snapper-cleanup.timer 2>/dev/null; then
    log_success "Snapper timers enabled and started"
  else
    log_error "Failed to enable Snapper timers"
    return 1
  fi

  # Configure bootloader
  case "$BOOTLOADER" in
    grub)
      setup_grub_bootloader || log_warning "GRUB configuration had issues but continuing"
      ;;
    systemd-boot)
      setup_systemd_boot || log_warning "systemd-boot configuration had issues but continuing"
      ;;
    *)
      log_warning "Could not detect GRUB or systemd-boot. Bootloader configuration skipped."
      log_info "Snapper will still work, but you may need to manually configure boot entries."
      ;;
  esac

  # Setup pacman hook
  setup_pacman_hook || log_warning "Pacman hook setup had issues but continuing"

  # Create initial snapshot
  step "Creating initial snapshot"
  if sudo snapper -c root create -d "Initial snapshot after setup" 2>/dev/null; then
    log_success "Initial snapshot created"
  else
    log_warning "Failed to create initial snapshot (non-critical)"
  fi

  # Verify installation
  step "Verifying Btrfs snapshot setup"
  local verification_passed=true

  if sudo snapper list &>/dev/null; then
    log_success "Snapper is working correctly"
  else
    log_error "Snapper verification failed"
    verification_passed=false
  fi

  if systemctl is-active --quiet snapper-timeline.timer && systemctl is-active --quiet snapper-cleanup.timer; then
    log_success "Snapper timers are active"
  else
    log_warning "Some Snapper timers may not be running correctly"
    verification_passed=false
  fi

  # Display current snapshots
  echo ""
  log_info "Current snapshots:"
  sudo snapper list 2>/dev/null || echo "  (No snapshots yet)"
  echo ""

  # Summary
  if [ "$verification_passed" = true ]; then
    log_success "Btrfs snapshot setup completed successfully!"
    echo ""
    echo -e "${CYAN}Snapshot system configured:${RESET}"
    echo -e "  • Automatic snapshots before/after package operations"
    echo -e "  • Retention: 5 hourly, 7 daily snapshots"
    echo -e "  • LTS kernel fallback: Available in boot menu"
    echo -e "  • GUI management: Launch 'btrfs-assistant' from your menu"
    echo ""
    echo -e "${CYAN}How to use:${RESET}"
    echo -e "  • View snapshots: ${YELLOW}sudo snapper list${RESET}"
    if [ "$BOOTLOADER" = "grub" ]; then
      echo -e "  • Boot snapshots: Select 'Arch Linux snapshots' in GRUB menu"
      echo -e "  • GRUB auto-updates when new snapshots are created"
    fi
    echo -e "  • Restore via GUI: Launch 'btrfs-assistant'"
    echo -e "  • Emergency fallback: Boot 'Arch Linux (LTS Kernel)'"
    echo -e "  • Snapshots stored in: ${YELLOW}/.snapshots/${RESET}"
    echo ""
  else
    log_warning "Btrfs snapshot setup completed with some warnings"
    log_info "Most functionality should still work. Review errors above."
  fi
}

# Execute all maintenance and snapshot steps
cleanup_and_optimize
setup_maintenance
cleanup_helpers
update_mirrorlist_with_rate_mirrors
setup_btrfs_snapshots

# Final message
echo ""
log_success "Maintenance and optimization completed"
log_info "System is ready for use"
