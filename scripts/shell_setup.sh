#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR"
source "$SCRIPTS_DIR/common.sh"
source "$SCRIPTS_DIR/cachyos_support.sh"

setup_shell() {
  # Handle CachyOS fish/ZSH choice using already-set choice from install.sh
  if $IS_CACHYOS && is_fish_shell; then
    if [[ "${CACHYOS_SHELL_CHOICE:-}" == "zsh" ]]; then
      echo -e "\n${CYAN}═══ Converting Fish to ZSH ═══${RESET}"
      echo -e "${YELLOW}Removing Fish and installing ZSH configuration...${RESET}"

      # Remove Fish completely and install ZSH
      handle_shell_conversion
      install_zsh_setup
      return 0

    elif [[ "${CACHYOS_SHELL_CHOICE:-}" == "fish" ]]; then
      echo -e "\n${CYAN}═══ Keeping Fish Shell ═══${RESET}"
      echo -e "${YELLOW}Preserving Fish configuration, replacing fastfetch config only...${RESET}"

      # Only replace fastfetch config
      replace_fastfetch_config_only
      return 0  # Skip ZSH setup entirely
    fi
  fi

  # Install ZSH setup for non-CachyOS systems or CachyOS users who chose ZSH
  install_zsh_setup
}

install_zsh_setup() {
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
  if $IS_CACHYOS && [[ "${CACHYOS_SHELL_CHOICE:-}" == "zsh" ]]; then
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
