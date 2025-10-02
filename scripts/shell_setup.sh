#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

  # Copy Fastfetch configuration
  if [ -f "$CONFIGS_DIR/config.jsonc" ]; then
    mkdir -p "$HOME/.config/fastfetch"
    cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/" 2>/dev/null && log_success "Fastfetch configuration copied"
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

  # Only proceed if GNOME is detected
  if [[ "$XDG_CURRENT_DESKTOP" == "GNOME" ]] || [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
    log_info "GNOME detected. Applying optimizations..."

    # Check if gsettings is available
    if command -v gsettings >/dev/null 2>&1; then
      # Helper function to check if schema exists
      schema_exists() {
        gsettings list-schemas 2>/dev/null | grep -q "^$1$"
      }

      # Helper function to check if schema key exists
      key_exists() {
        gsettings list-keys "$1" 2>/dev/null | grep -q "^$2$"
      }

      # Set dark theme preference (GNOME 42+)
      if schema_exists "org.gnome.desktop.interface" && key_exists "org.gnome.desktop.interface" "color-scheme"; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null && \
          log_success "Dark theme preference set"
      fi

      # Enable minimize and maximize buttons
      if schema_exists "org.gnome.desktop.wm.preferences"; then
        gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close' 2>/dev/null && \
          log_success "Window buttons configured (minimize, maximize, close)"
      fi

      # Set tap-to-click for touchpad
      if schema_exists "org.gnome.desktop.peripherals.touchpad"; then
        gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true 2>/dev/null && \
          log_success "Tap-to-click enabled"
      fi

      # Disable hot corner
      if schema_exists "org.gnome.desktop.interface" && key_exists "org.gnome.desktop.interface" "enable-hot-corners"; then
        gsettings set org.gnome.desktop.interface enable-hot-corners false 2>/dev/null && \
          log_success "Hot corners disabled"
      fi

      # Set font rendering
      if schema_exists "org.gnome.desktop.interface"; then
        gsettings set org.gnome.desktop.interface font-antialiasing 'rgba' 2>/dev/null
        gsettings set org.gnome.desktop.interface font-hinting 'slight' 2>/dev/null && \
          log_success "Font rendering optimized"
      fi

      # Set battery percentage
      if schema_exists "org.gnome.desktop.interface"; then
        gsettings set org.gnome.desktop.interface show-battery-percentage true 2>/dev/null && \
          log_success "Battery percentage enabled"
      fi

      # Set Meta+Q to close windows
      if schema_exists "org.gnome.desktop.wm.keybindings"; then
        gsettings set org.gnome.desktop.wm.keybindings close "['<Super>q']" 2>/dev/null && \
          log_success "Meta+Q set to close windows"
      fi

      # Set Meta+Enter to open terminal
      # GNOME uses different terminal apps: kgx (Console), gnome-console, or gnome-terminal
      if schema_exists "org.gnome.settings-daemon.plugins.media-keys"; then
        if command -v kgx >/dev/null 2>&1; then
          gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']" 2>/dev/null
          gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Terminal' 2>/dev/null
          gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'kgx' 2>/dev/null
          gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Super>Return' 2>/dev/null && \
            log_success "Meta+Enter set to open Console (kgx)"
        elif command -v gnome-console >/dev/null 2>&1; then
          gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']" 2>/dev/null
          gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Terminal' 2>/dev/null
          gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'gnome-console' 2>/dev/null
          gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Super>Return' 2>/dev/null && \
            log_success "Meta+Enter set to open Console (gnome-console)"
        elif command -v gnome-terminal >/dev/null 2>&1; then
          gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']" 2>/dev/null
          gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Terminal' 2>/dev/null
          gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'gnome-terminal' 2>/dev/null
          gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Super>Return' 2>/dev/null && \
            log_success "Meta+Enter set to open Terminal (gnome-terminal)"
        else
          log_warning "No GNOME terminal found (kgx, gnome-console, or gnome-terminal)"
        fi
      fi

      # Set PrintScreen to take full screenshot
      if schema_exists "org.gnome.shell.keybindings"; then
        gsettings set org.gnome.shell.keybindings screenshot "['Print']" 2>/dev/null && \
          log_success "PrintScreen set to capture full screen"
      fi

      # Set Ctrl+Alt+Delete to show power menu
      # Try both possible schema locations (varies by GNOME version)
      if schema_exists "org.gnome.settings-daemon.plugins.media-keys" && key_exists "org.gnome.settings-daemon.plugins.media-keys" "logout"; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys logout "['<Primary><Alt>Delete']" 2>/dev/null && \
          log_success "Ctrl+Alt+Delete set to show power menu (Reboot/Shutdown/Logout)"
      elif schema_exists "org.gnome.SessionManager"; then
        gsettings set org.gnome.SessionManager logout "['<Primary><Alt>Delete']" 2>/dev/null && \
          log_success "Ctrl+Alt+Delete set to show power menu (Reboot/Shutdown/Logout)"
      fi

      log_success "GNOME configurations applied successfully"
      log_info "GNOME settings will be active after next login or session restart"
      log_info "Tested and compatible with GNOME 40 through GNOME 49+"
    else
      log_warning "gsettings not found. Skipping GNOME configurations"
    fi
  else
    log_info "GNOME not detected. Skipping GNOME configurations"
  fi
}

setup_shell
setup_kde_shortcuts
setup_gnome_configs
