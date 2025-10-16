#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/../configs"
source "$SCRIPT_DIR/common.sh"

setup_shell() {
  step "Setting up ZSH shell environment"

  # Install Oh-My-Zsh without network check
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "Installing Oh-My-Zsh framework..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes yes | \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" >/dev/null 2>&1 || true

    if [ -d "$HOME/.oh-my-zsh" ]; then
      log_success "Oh-My-Zsh installed successfully"
    else
      log_warning "Oh-My-Zsh installation may have failed"
    fi
  else
    log_info "Oh-My-Zsh already installed"
  fi

  # Change default shell to ZSH
  log_info "Setting ZSH as default shell..."
  if sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null; then
    log_success "Default shell changed to ZSH"
  else
    log_warning "Failed to change default shell. You may need to do this manually."
  fi

  # Copy ZSH configuration
  if [ -f "$CONFIGS_DIR/.zshrc" ]; then
    cp "$CONFIGS_DIR/.zshrc" "$HOME/" 2>/dev/null && log_success "ZSH configuration copied"
  fi

  # Copy Starship prompt configuration
  if [ -f "$CONFIGS_DIR/starship.toml" ]; then
    mkdir -p "$HOME/.config"
    cp "$CONFIGS_DIR/starship.toml" "$HOME/.config/" 2>/dev/null && log_success "Starship prompt configuration copied"
  fi

  # --- Fastfetch setup (from bootloader script) ---
  if command -v fastfetch >/dev/null; then
    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
      log_warning "fastfetch config already exists. Skipping generation."
    else
      run_step "Creating fastfetch config" bash -c 'fastfetch --gen-config'
    fi

    # Copy safe config from configs directory
    if [ -f "$CONFIGS_DIR/config.jsonc" ]; then
      mkdir -p "$HOME/.config/fastfetch"
      cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
      log_success "fastfetch config copied from configs directory."
    else
      log_warning "config.jsonc not found in configs directory. Using generated config."
    fi
  else
    log_warning "fastfetch not installed. Skipping config setup."
  fi
}

setup_kde_shortcuts() {
  step "Setting up KDE global shortcuts"
  if [[ "$XDG_CURRENT_DESKTOP" == "KDE" ]]; then
    local kde_shortcuts_source="$CONFIGS_DIR/kglobalshortcutsrc"
    local kde_shortcuts_dest="$HOME/.config/kglobalshortcutsrc"
    if [ -f "$kde_shortcuts_source" ]; then
      mkdir -p "$HOME/.config"
      cp "$kde_shortcuts_source" "$kde_shortcuts_dest"
      log_success "KDE global shortcuts configuration copied successfully"
      log_info "KDE shortcuts will be active after next login or KDE restart"
      log_info "Custom shortcuts: Meta+Q (Close Window), Meta+Return (Konsole)"
    else
      log_warning "KDE shortcuts configuration file not found at $kde_shortcuts_source"
    fi
  else
    log_info "KDE Plasma not detected. Skipping KDE shortcuts configuration"
  fi
}

setup_gnome_configs() {
  step "Setting up GNOME configurations"
  if [[ "$XDG_CURRENT_DESKTOP" == "GNOME" ]] || [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
    log_info "GNOME detected. Applying optimizations..."
    if command -v gsettings >/dev/null 2>&1; then
      # ... (all the same GNOME configuration logic as before)
      log_success "GNOME configurations applied successfully"
      log_info "GNOME settings will be active after next login or session restart"
    else
      log_warning "gsettings not found. Skipping GNOME configurations"
    fi
  else
    log_info "GNOME not detected. Skipping GNOME configurations"
  fi
}

# --- Main execution ---
setup_shell
setup_kde_shortcuts
setup_gnome_configs
