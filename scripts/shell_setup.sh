#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup_shell() {
  # Install Oh-My-Zsh without network check
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes yes | \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" >/dev/null 2>&1 || true
  fi
  
  # Change shell
  sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || true
  
  # Copy config files
  [ -f "$CONFIGS_DIR/.zshrc" ] && cp "$CONFIGS_DIR/.zshrc" "$HOME/" 2>/dev/null || true
  [ -f "$CONFIGS_DIR/starship.toml" ] && mkdir -p "$HOME/.config" && cp "$CONFIGS_DIR/starship.toml" "$HOME/.config/" 2>/dev/null || true
}

setup_shell 