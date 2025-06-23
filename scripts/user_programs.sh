#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Installing user programs"

# Install yay first (required for AUR packages in programs.sh)
if [ -f "$(dirname "$0")/yay.sh" ]; then
  chmod +x "$(dirname "$0")/yay.sh"
  log_info "Installing yay (AUR helper)..."
  "$(dirname "$0")/yay.sh"
  if [ $? -eq 0 ]; then
    log_success "yay installed successfully"
  else
    log_warning "yay installation failed, AUR packages may not install"
  fi
fi

# Run remaining scripts in parallel
for script in "plymouth.sh" "programs.sh" "fail2ban.sh"; do
  if [ -f "$(dirname "$0")/$script" ]; then
    chmod +x "$(dirname "$0")/$script"
    if [[ "$script" == "programs.sh" ]]; then
      source "$(dirname "$0")/$script" &
    else
      "$(dirname "$0")/$script" &
    fi
  fi
done

wait  # Wait for all to complete 