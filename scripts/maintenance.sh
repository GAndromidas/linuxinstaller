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

  if command -v paru >/dev/null 2>&1; then
    run_step "Cleaning paru cache" paru -Sc --noconfirm
    run_step "Cleaning paru build directory" sudo rm -rf /tmp/paru*
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

  # System optimization
  run_step "Cleaning temporary files" sudo rm -rf /tmp/* /var/tmp/*

  # SSD optimization
  if command_exists lsblk && lsblk -d -o rota | grep -q '^0$'; then
    run_step "Running fstrim on SSDs" sudo fstrim -v /
  fi

  run_step "Syncing filesystem" sync
}

# Clean up installer-specific utilities
cleanup_installer_utilities() {
  step "Cleaning up installer utilities"

  # Remove installer-specific packages that are no longer needed
  local installer_utils=("gum" "figlet")
  local to_remove=()

  for util in "${installer_utils[@]}"; do
    if pacman -Q "$util" >/dev/null 2>&1; then
      to_remove+=("$util")
    fi
  done

  if [ ${#to_remove[@]} -gt 0 ]; then
    run_step "Removing installer utilities: ${to_remove[*]}" sudo pacman -R "${to_remove[@]}" --noconfirm
  else
    log_success "No installer utilities to remove"
  fi
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
