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

  # Configure Snapper settings with optimized retention policy
  sudo sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' /etc/snapper/configs/root
  sudo sed -i 's/^NUMBER_CLEANUP=.*/NUMBER_CLEANUP="yes"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="2"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="2"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="1"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' /etc/snapper/configs/root
  sudo sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root
  sudo sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="50"/' /etc/snapper/configs/root
  sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="10"/' /etc/snapper/configs/root

  log_success "Snapper configuration completed (2 hourly, 2 daily, 1 weekly, max 50 snapshots)"
}

# Configure btrfs-assistant GUI settings
configure_btrfs_assistant_gui() {
  step "Configuring btrfs-assistant GUI settings"

  # btrfs-assistant uses /etc/btrfs-assistant.conf for system-wide config
  local BA_CONFIG="/etc/btrfs-assistant.conf"

  # Backup existing config if present
  if [ -f "$BA_CONFIG" ]; then
    sudo cp "$BA_CONFIG" "${BA_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  fi

  # Check if config exists and append or create
  if [ -f "$BA_CONFIG" ]; then
    log_info "Updating existing btrfs-assistant configuration..."
    # Append snapshot location if not already present
    if ! grep -q "snapshot_location_root" "$BA_CONFIG" 2>/dev/null; then
      echo "snapshot_location_root = /.snapshots" | sudo tee -a "$BA_CONFIG" >/dev/null
    fi
  else
    log_info "Creating new btrfs-assistant configuration..."
    # Create basic config with snapshot location
    echo "snapshot_location_root = /.snapshots" | sudo tee "$BA_CONFIG" >/dev/null
  fi

  log_success "btrfs-assistant configuration updated at $BA_CONFIG"
  log_info "Maintenance tab will read settings from /etc/default/btrfsmaintenance"
  log_info "After reboot, open btrfs-assistant to see maintenance schedule"
}

# Configure btrfsmaintenance settings
configure_btrfsmaintenance() {
  step "Configuring btrfsmaintenance services"

  # Arch Linux uses /etc/default/btrfsmaintenance
  local BTRMAINT_CONFIG="/etc/default/btrfsmaintenance"

  # Backup existing config if present
  if [ -f "$BTRMAINT_CONFIG" ]; then
    sudo cp "$BTRMAINT_CONFIG" "${BTRMAINT_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  fi

  # Create comprehensive maintenance configuration
  cat << 'EOF' | sudo tee "$BTRMAINT_CONFIG" >/dev/null
## Path:        System/File systems/btrfs
## Type:        string(none,stdout,journal,syslog)
## Default:     "stdout"
#
# Output target for messages. Journal and syslog messages are tagged by the task name like
# 'btrfs-scrub' etc.
BTRFS_LOG_OUTPUT="stdout"

## Path:        System/File systems/btrfs
## Type:        string
## Default:     ""
#
# Run periodic defrag on selected paths. The files from a given path do not
# cross mount points or other subvolumes/snapshots. If you want to defragment
# nested subvolumes, all have to be listed in this variable.
# (Colon separated paths)
BTRFS_DEFRAG_PATHS="/:/home"

## Path:           System/File systems/btrfs
## Type:           string(none,daily,weekly,monthly)
## Default:        "none"
## ServiceRestart: btrfsmaintenance-refresh
#
# Frequency of defrag.
BTRFS_DEFRAG_PERIOD="weekly"

## Path:        System/File systems/btrfs
## Type:        string
## Default:     "+1M"
#
# Minimal file size to consider for defragmentation
BTRFS_DEFRAG_MIN_SIZE="+1M"

## Path:        System/File systems/btrfs
## Type:        string
## Default:     "/"
#
# Which mountpoints/filesystems to balance periodically. This may reclaim unused
# portions of the filesystem and make the rest more compact.
# (Colon separated paths)
# The special word/mountpoint "auto" will evaluate all mounted btrfs
# filesystems
BTRFS_BALANCE_MOUNTPOINTS="/:/home:/var/log"

## Path:           System/File systems/btrfs
## Type:           string(none,daily,weekly,monthly)
## Default:        "weekly"
## ServiceRestart: btrfsmaintenance-refresh
#
# Frequency of periodic balance.
#
# The frequency may be specified using one of the listed values or
# in the format documented in the "Calendar Events" section of systemd.time(7),
# if available.
BTRFS_BALANCE_PERIOD="weekly"

## Path:        System/File systems/btrfs
## Type:        string
## Default:     "5 10"
#
# The usage percent for balancing data block groups.
#
# Note: default values should not disturb normal work but may not reclaim
# enough block groups. If you observe that, add higher values but beware that
# this will increase IO load on the system.
BTRFS_BALANCE_DUSAGE="5 10"

## Path:        System/File systems/btrfs
## Type:        string
## Default:     "5"
#
# The usage percent for balancing metadata block groups. The values are also
# used in case the filesystem has mixed blockgroups.
#
# Note: default values should not disturb normal work but may not reclaim
# enough block groups. If you observe that, add higher values but beware that
# this will increase IO load on the system.
BTRFS_BALANCE_MUSAGE="5"

## Path:        System/File systems/btrfs
## Type:        string
## Default:     "/"
#
# Which mountpoints/filesystems to scrub periodically.
# (Colon separated paths)
# The special word/mountpoint "auto" will evaluate all mounted btrfs
# filesystems
BTRFS_SCRUB_MOUNTPOINTS="/:/home:/var/log"

## Path:        System/File systems/btrfs
## Type:        string(none,weekly,monthly)
## Default:     "monthly"
## ServiceRestart: btrfsmaintenance-refresh
#
# Frequency of periodic scrub.
#
# The frequency may be specified using one of the listed values or
# in the format documented in the "Calendar Events" section of systemd.time(7),
# if available.
BTRFS_SCRUB_PERIOD="monthly"

## Path:        System/File systems/btrfs
## Type:        string(idle,normal)
## Default:     "idle"
#
# Priority of IO at which the scrub process will run. Idle should not degrade
# performance but may take longer to finish.
BTRFS_SCRUB_PRIORITY="idle"

## Path:        System/File systems/btrfs
## Type:        boolean
## Default:     "false"
#
# Do read-only scrub and don't try to repair anything.
BTRFS_SCRUB_READ_ONLY="false"

## Path:           System/File systems/btrfs
## Description:    Configuration for periodic fstrim
## Type:           string(none,daily,weekly,monthly)
## Default:        "none"
## ServiceRestart: btrfsmaintenance-refresh
#
# Frequency of periodic trim. Off by default so it does not collide with
# fstrim.timer . If you do not use the timer, turn it on here. The recommended
# period is 'weekly'.
#
# The frequency may be specified using one of the listed values or
# in the format documented in the "Calendar Events" section of systemd.time(7),
# if available.
BTRFS_TRIM_PERIOD="none"

## Path:        System/File systems/btrfs
## Description: Configuration for periodic fstrim - mountpoints
## Type:        string
## Default:     "/"
#
# Which mountpoints/filesystems to trim periodically.
# (Colon separated paths)
# The special word/mountpoint "auto" will evaluate all mounted btrfs
# filesystems
BTRFS_TRIM_MOUNTPOINTS="/"

## Path:	System/File systems/btrfs
## Description:	Configuration to allow concurrent jobs
## Type: 	boolean
## Default:	"false"
#
# These maintenance tasks may compete for resources with each other, blocking
# out other tasks from using the file systems.  This option will force
# these jobs to run in FIFO order when scheduled at overlapping times.  This
# may include tasks scheduled to run when a system resumes or boots when
# the timer for these tasks(s) elapsed while the system was suspended
# or powered off.
BTRFS_ALLOW_CONCURRENCY="false"
EOF

  if sudo systemctl enable btrfs-scrub@var-log.timer 2>/dev/null; then
    log_success "btrfs-scrub timers enabled (monthly integrity checks)"
  else
    log_warning "Some btrfs-scrub timers failed to enable"
    timers_enabled=false
  fi

  if sudo systemctl enable btrfs-balance@-.timer 2>/dev/null && \
     sudo systemctl enable btrfs-balance@home.timer 2>/dev/null && \
     sudo systemctl enable btrfs-balance@var-log.timer 2>/dev/null; then
    log_success "btrfs-balance timers enabled (weekly space optimization)"
  else
    log_warning "Some btrfs-balance timers failed to enable"
    timers_enabled=false
  fi

  if sudo systemctl enable btrfs-defrag@-.timer 2>/dev/null && \
     sudo systemctl enable btrfs-defrag@home.timer 2>/dev/null; then
    log_success "btrfs-defrag timers enabled (weekly defragmentation)"
  else
    log_warning "Some btrfs-defrag timers failed to enable"
    timers_enabled=false
  fi

  if [ "$timers_enabled" = true ]; then
    log_success "All btrfsmaintenance timers are enabled"
  else
    log_warning "Some btrfsmaintenance timers failed to enable"
  fi

  # Display timer status
  echo ""
  log_info "Maintenance timer status:"
  systemctl list-timers 'btrfs-*' --no-pager 2>/dev/null | head -n 20 || true
  echo ""
}

# Enable Btrfs quotas if beneficial
enable_btrfs_quotas() {
  step "Configuring Btrfs quotas"

  # Check if quotas are already enabled
  if sudo btrfs qgroup show / &>/dev/null; then
    log_info "Btrfs quotas already enabled"
    return 0
  fi

  log_info "Enabling Btrfs quotas for snapshot space tracking..."

  if sudo btrfs quota enable / 2>/dev/null; then
    log_success "Btrfs quotas enabled successfully"
    log_info "Quotas allow tracking snapshot space usage via snapper and btrfs-assistant"
  else
    log_warning "Failed to enable Btrfs quotas (non-critical)"
    log_info "Snapshots will still work, but space tracking may be limited"
  fi
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
    gum style --margin "0 2" --foreground 15 "• Retention: 2 hourly, 2 daily, 1 weekly (max 50 total)"
    gum style --margin "0 2" --foreground 15 "• LTS kernel fallback for recovery"
    gum style --margin "0 2" --foreground 15 "• Automated maintenance: scrub, balance, defrag"
    gum style --margin "0 2" --foreground 15 "• GUI tool (btrfs-assistant) for snapshot management"
    echo ""
    if gum confirm --default=false "Would you like to set up automatic Btrfs snapshots?"; then
      setup_snapshots=true
    fi
  else
    echo ""
    echo -e "${YELLOW}Btrfs snapshot setup available:${RESET}"
    echo -e "  • Automatic snapshots before/after package operations"
    echo -e "  • Retention: 2 hourly, 2 daily, 1 weekly (max 50 total)"
    echo -e "  • LTS kernel fallback for recovery"
    echo -e "  • Automated maintenance: scrub, balance, defrag"
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
  log_info "Installing: snapper, snap-pac, btrfs-assistant, btrfsmaintenance, linux-lts"

  # Update package database first
  sudo pacman -Sy >/dev/null 2>&1 || log_warning "Failed to update package database"

  # Install packages including btrfsmaintenance
  install_packages_quietly snapper snap-pac btrfs-assistant btrfsmaintenance linux-lts linux-lts-headers

  # Configure Snapper
  configure_snapper || { log_error "Snapper configuration failed"; return 1; }

  # Enable Snapper timers
  step "Enabling Snapper automatic snapshot timers"
  if sudo systemctl enable --now snapper-timeline.timer 2>/dev/null && sudo systemctl enable --now snapper-cleanup.timer 2>/dev/null; then
    log_success "Snapper timers enabled and started"
  else
    log_error "Failed to enable Snapper timers"
    return 1
  fi

  # Configure btrfsmaintenance
  configure_btrfsmaintenance || log_warning "btrfsmaintenance configuration had issues but continuing"

  # Configure btrfs-assistant GUI
  configure_btrfs_assistant_gui || log_warning "btrfs-assistant GUI configuration had issues but continuing"

  # Enable Btrfs quotas
  enable_btrfs_quotas || log_warning "Quota setup had issues but continuing"

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

  if systemctl is-active --quiet btrfs-scrub@-.timer && systemctl is-active --quiet btrfs-balance@-.timer; then
    log_success "Btrfs maintenance timers are active"
  else
    log_warning "Some btrfs maintenance timers may not be running correctly"
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
    echo -e "  • Retention: 2 hourly, 2 daily, 1 weekly (max 50 snapshots)"
    echo -e "  • LTS kernel fallback: Available in boot menu"
    echo -e "  • Automated maintenance:"
    echo -e "    - Scrub (monthly): /, /home, /var/log"
    echo -e "    - Balance (weekly): /, /home, /var/log"
    echo -e "    - Defrag (weekly): /, /home"
    echo -e "  • Quotas enabled for space tracking"
    echo -e "  • GUI management: Launch 'btrfs-assistant' from your menu"
    echo ""
    echo -e "${CYAN}How to use:${RESET}"
    echo -e "  • View snapshots: ${YELLOW}sudo snapper list${RESET}"
    if [ "$BOOTLOADER" = "grub" ]; then
      echo -e "  • Boot snapshots: Select 'Arch Linux snapshots' in GRUB menu"
      echo -e "  • GRUB auto-updates when new snapshots are created"
    fi
    echo -e "  • Restore via GUI: Launch 'btrfs-assistant'"
    echo -e "  • Check maintenance timers: ${YELLOW}systemctl list-timers 'btrfs-*'${RESET}"
    echo -e "  • View maintenance config: ${YELLOW}cat /etc/default/btrfsmaintenance${RESET}"
    echo -e "  • Emergency fallback: Boot 'Arch Linux (LTS Kernel)'"
    echo -e "  • Snapshots stored in: ${YELLOW}/.snapshots/${RESET}"
    echo ""
    echo -e "${CYAN}btrfs-assistant Maintenance tab:${RESET}"
    echo -e "  • The Maintenance tab shows enabled timers (checkboxes)"
    echo -e "  • If unchecked, click them to enable - this will activate the timers"
    echo -e "  • Configuration is stored in ${YELLOW}/etc/default/btrfsmaintenance${RESET}"
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
