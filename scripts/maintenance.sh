#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup_maintenance() {
  # All maintenance in one command
  {
    sudo paccache -r 2>/dev/null || true
    sudo pacman -Rns $(pacman -Qtdq 2>/dev/null) --noconfirm 2>/dev/null || true
    sudo pacman -Syu --noconfirm
    yay -Syu --noconfirm 2>/dev/null || true
  } >/dev/null 2>&1
}

setup_maintenance 