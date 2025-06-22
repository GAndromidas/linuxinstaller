#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/common.sh"

step "Installing user programs"

# Run ALL custom scripts in parallel
for script in "plymouth.sh" "yay.sh" "programs.sh" "fail2ban.sh"; do
  if [ -f "$(dirname "$0")/$script" ]; then
    chmod +x "$(dirname "$0")/$script"
    if [[ "$script" == "programs.sh" ]]; then
      "$(dirname "$0")/$script" "$INSTALL_MODE" &
    else
      "$(dirname "$0")/$script" &
    fi
  fi
done

wait  # Wait for all to complete 