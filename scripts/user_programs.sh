#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# Run custom scripts in order, if present
for custom_script in "plymouth.sh" "yay.sh" "programs.sh" "fail2ban.sh"; do
  if [ -f "$(dirname "$0")/$custom_script" ]; then
    chmod +x "$(dirname "$0")/$custom_script"
    # Pass install mode to programs.sh if needed
    if [[ "$custom_script" == "programs.sh" ]]; then
      if [[ "$INSTALL_MODE" == "minimal" ]]; then
        run_step "Installing minimal user programs" "$(dirname "$0")/$custom_script" -m
      else
        run_step "Installing default user programs" "$(dirname "$0")/$custom_script" -d
      fi
    else
      run_step "Running $custom_script" "$(dirname "$0")/$custom_script"
    fi
  fi
done 