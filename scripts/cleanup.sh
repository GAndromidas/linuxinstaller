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

  if [[ -d "$SCRIPT_DIR" ]]; then
    if [ "${#ERRORS[@]}" -eq 0 ]; then
      cd "$HOME"
      run_step "Deleting installer directory" rm -rf "$SCRIPT_DIR"
    else
      echo -e "\n${YELLOW}Issues detected during installation. The installer folder and install.log will NOT be deleted.${RESET}\n"
      echo -e "${RED}ERROR: One or more steps failed. Please check the log for details:${RESET}"
      echo -e "${CYAN}$SCRIPT_DIR/install.log${RESET}\n"
    fi
  fi

  run_step "Syncing disk writes" sync
}

cleanup_and_optimize 