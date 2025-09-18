#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Comprehensive system cleanup and optimization
perform_system_cleanup() {
  step "Performing comprehensive system cleanup and optimization"

  # Package cache cleanup
  run_step "Cleaning pacman cache" sudo pacman -Sc --noconfirm

  if command -v yay >/dev/null 2>&1; then
    run_step "Cleaning yay cache" yay -Sc --noconfirm
    run_step "Cleaning yay build directory" sudo rm -rf /tmp/yay* "$HOME/.cache/yay"
  fi

  # Flatpak cleanup
  if command -v flatpak >/dev/null 2>&1; then
    run_step "Removing unused flatpak packages" flatpak uninstall --unused --noninteractive -y
  fi

  # Orphaned packages cleanup
  local orphans=$(pacman -Qtdq 2>/dev/null)
  if [ -n "$orphans" ]; then
    run_step "Removing orphaned packages" sudo pacman -Rns $orphans --noconfirm
  else
    log_success "No orphaned packages found"
  fi

  # Remove yay-debug if it exists
  if pacman -Q yay-debug &>/dev/null; then
    run_step "Removing yay-debug package" sudo pacman -Rns yay-debug --noconfirm
  else
    log_success "yay-debug not found or already removed"
  fi

  # System optimization
  run_step "Cleaning temporary files" sudo rm -rf /tmp/* /var/tmp/*

  # SSD optimization
  if command_exists lsblk && lsblk -d -o rota | grep -q '^0$'; then
    run_step "Running fstrim on SSDs" sudo fstrim -v /
  fi

  run_step "Syncing filesystem" sync
}

# Clean up installer-specific utilities (gum and figlet will be removed at reboot)
cleanup_installer_utilities() {
  step "Cleaning up installer utilities"

  # Don't remove gum and figlet here - they're needed until the very end
  # They will be removed by prompt_reboot() right before the system reboots
  log_success "Installer utilities (gum, figlet) will be cleaned up before reboot"
}

# Update mirrorlist using rate-mirrors if available
update_mirrorlist_with_rate_mirrors() {
  step "Updating mirrorlist with rate-mirrors"
  if command -v rate-mirrors >/dev/null 2>&1; then
    run_step "Updating mirrorlist with fastest mirrors" sudo rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch
  else
    log_info "rate-mirrors not installed. Skipping mirrorlist update."
  fi
}

# Main execution
main() {
  perform_system_cleanup
  cleanup_installer_utilities
  update_mirrorlist_with_rate_mirrors
  log_success "System maintenance completed successfully"
}

# Run main function
main
