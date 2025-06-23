#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

maintenance_and_cleanup() {
  step "Performing system maintenance"
  {
    sudo paccache -r 2>/dev/null || true
    sudo pacman -Rns $(pacman -Qtdq 2>/dev/null) --noconfirm 2>/dev/null || true
    sudo pacman -Syu --noconfirm
    yay -Syu --noconfirm 2>/dev/null || true
  } >/dev/null 2>&1

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

maintenance_and_cleanup 