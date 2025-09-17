#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/cachyos_support.sh"

setup_shell() {
  # Check if we're on CachyOS and handle complete fish removal
  if $IS_CACHYOS; then
    log_info "CachyOS detected - completely removing Fish and setting up ZSH"

    # Check current shell
    current_shell=$(get_current_shell)
    if [[ "$current_shell" == "fish" ]]; then
      log_info "Completely removing Fish shell and replacing with ZSH"

      # Remove fish config completely - no backups
      if [ -d "$HOME/.config/fish" ]; then
        log_info "Removing Fish configuration directory"
        rm -rf "$HOME/.config/fish" 2>/dev/null || true
      fi

      # Remove any other fish-related files
      if [ -f "$HOME/.fishrc" ]; then
        rm -f "$HOME/.fishrc" 2>/dev/null || true
      fi

      if [ -d "$HOME/.local/share/fish" ]; then
        log_info "Removing Fish local data directory"
        rm -rf "$HOME/.local/share/fish" 2>/dev/null || true
      fi

      # Remove fish package completely
      if pacman -Q fish &>/dev/null; then
        log_info "Uninstalling Fish shell package"
        sudo pacman -Rns fish --noconfirm >/dev/null 2>&1 || true
        log_success "Fish shell completely removed from system"
      fi
    fi
  fi

  # Install Oh-My-Zsh without network check
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "Installing Oh-My-Zsh"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes yes | \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" >/dev/null 2>&1 || true
  else
    log_info "Oh-My-Zsh already installed, skipping"
  fi

  # Change shell to ZSH (especially important for CachyOS fish users)
  current_user_shell=$(getent passwd "$USER" | cut -d: -f7)
  if [[ "$current_user_shell" != "$(command -v zsh)" ]]; then
    log_info "Changing default shell to ZSH"
    sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || true

    if $IS_CACHYOS; then
      log_success "Successfully replaced Fish with ZSH as default shell"
    fi
  else
    log_info "ZSH is already the default shell"
  fi

  # Copy config files
  if [ -f "$CONFIGS_DIR/.zshrc" ]; then
    cp "$CONFIGS_DIR/.zshrc" "$HOME/" 2>/dev/null || true
    log_success "ZSH configuration copied"
  else
    log_warning "ZSH config file not found at $CONFIGS_DIR/.zshrc"
  fi

  if [ -f "$CONFIGS_DIR/starship.toml" ]; then
    mkdir -p "$HOME/.config"
    cp "$CONFIGS_DIR/starship.toml" "$HOME/.config/" 2>/dev/null || true
    log_success "Starship configuration copied"
  else
    log_warning "Starship config file not found at $CONFIGS_DIR/starship.toml"
  fi

  # CachyOS specific shell setup completion message
  if $IS_CACHYOS; then
    echo -e "\n${GREEN}═══ CachyOS Shell Replacement Complete ═══${RESET}"
    echo -e "${YELLOW}Fish shell has been completely removed and replaced with ZSH.${RESET}"
    echo -e "${YELLOW}You may need to log out and back in for changes to take full effect.${RESET}"
    echo -e "${CYAN}ZSH is now configured with your archinstaller settings.${RESET}"
    echo -e "${GREEN}═════════════════════════════════════════${RESET}\n"
  fi
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
