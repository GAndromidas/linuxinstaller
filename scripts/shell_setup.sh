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

setup_kde_shortcuts() {
  step "Setting up KDE global shortcuts"

  # Only proceed if KDE Plasma is detected
  if [[ "$XDG_CURRENT_DESKTOP" == "KDE" ]]; then
    local kde_shortcuts_source="$CONFIGS_DIR/kglobalshortcutsrc"
    local kde_shortcuts_dest="$HOME/.config/kglobalshortcutsrc"

    if [ -f "$kde_shortcuts_source" ]; then
      # Create .config directory if it doesn't exist
      mkdir -p "$HOME/.config"

      # Copy the KDE global shortcuts configuration, replacing the old one
      cp "$kde_shortcuts_source" "$kde_shortcuts_dest"
      log_success "KDE global shortcuts configuration copied successfully."
      log_info "KDE shortcuts will be active after next login or KDE restart."
    else
      log_warning "KDE shortcuts configuration file not found at $kde_shortcuts_source"
    fi
  else
    log_info "KDE Plasma not detected. Skipping KDE shortcuts configuration."
  fi
}

setup_shell
setup_kde_shortcuts
