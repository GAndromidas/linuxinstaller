#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

setup_zsh() {
  if ! command -v zsh >/dev/null; then
    step "Installing ZSH and plugins"
    install_packages_quietly zsh zsh-autosuggestions zsh-syntax-highlighting
  else
    log_warning "zsh is already installed. Skipping."
  fi
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    run_step "Installing Oh-My-Zsh" bash -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
  else
    log_warning "Oh-My-Zsh is already installed. Skipping."
  fi
  run_step "Changing shell to ZSH" sudo chsh -s "$(command -v zsh)" "$USER"
  if [ -f "$CONFIGS_DIR/.zshrc" ]; then
    run_step "Configuring .zshrc" cp "$CONFIGS_DIR/.zshrc" "$HOME/"
  fi
}

install_starship() {
  if ! command -v starship >/dev/null; then
    step "Installing starship prompt"
    install_packages_quietly starship
  else
    log_warning "starship is already installed. Skipping installation."
  fi

  mkdir -p "$HOME/.config"

  if [ -f "$HOME/.config/starship.toml" ]; then
    log_warning "starship.toml already exists in $HOME/.config/, skipping move."
  elif [ -f "$CONFIGS_DIR/starship.toml" ]; then
    mv "$CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml"
    log_success "starship.toml moved to $HOME/.config/"
  else
    log_warning "starship.toml not found in $CONFIGS_DIR/"
  fi
}

# Execute shell setup steps
setup_zsh
install_starship 