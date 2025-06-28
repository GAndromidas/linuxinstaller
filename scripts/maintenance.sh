#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ======= Maintenance Steps =======
optimize_ssd() {
  step "Optimizing SSD (if detected)"
  if command -v lsblk >/dev/null; then
    # Check if root filesystem is on SSD
    local root_device=$(lsblk -no MOUNTPOINT,ROTA / | grep " /$" | awk '{print $2}')
    if [ "$root_device" = "0" ]; then
      # SSD detected, apply optimizations
      echo "noatime" | sudo tee -a /etc/fstab >/dev/null
      log_success "SSD optimizations applied"
    else
      log_warning "No SSD detected, skipping SSD optimizations"
    fi
  else
    log_warning "lsblk not available. Skipping SSD optimization."
  fi
}

update_system() {
  step "Updating system packages"
  fast_system_update
}

clean_package_cache() {
  step "Cleaning package cache"
  sudo pacman -Sc --noconfirm
  log_success "Package cache cleaned"
}

# ======= Main =======
main() {
  echo -e "${CYAN}=== System Maintenance ===${RESET}"

  optimize_ssd
  update_system
  clean_package_cache

  echo -e "\n${GREEN}System maintenance completed successfully!${RESET}"
}

main "$@" 