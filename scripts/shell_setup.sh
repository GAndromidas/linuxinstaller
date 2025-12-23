#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/../configs"
source "$SCRIPT_DIR/common.sh"
# Ensure distro info is available
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

setup_shell() {
  step "Setting up ZSH shell environment"

  # Clean legacy
  if [ -d "$HOME/.oh-my-zsh" ]; then
    rm -rf "$HOME/.oh-my-zsh" && log_success "Removed legacy Oh-My-Zsh"
  fi

  # Set ZSH as default
  if [ "$SHELL" != "$(command -v zsh)" ]; then
    log_info "Changing default shell to ZSH..."
    if sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null; then
      log_success "Default shell changed to ZSH"
    else
      log_warning "Failed to change shell. You may need to do this manually."
    fi
  fi

  # Deploy config files (DRY loop)
  local configs=(
    ".zshrc:$HOME/.zshrc"
    "starship.toml:$HOME/.config/starship.toml"
  )

  mkdir -p "$HOME/.config"

  for cfg in "${configs[@]}"; do
    local src="${cfg%%:*}"
    local dest="${cfg##*:}"

    if [ -f "$CONFIGS_DIR/$src" ]; then
      cp "$CONFIGS_DIR/$src" "$dest" && log_success "Updated config: $src"
    fi
  done

  # Fastfetch setup
  if command -v fastfetch >/dev/null; then
    mkdir -p "$HOME/.config/fastfetch"
    
    local dest_config="$HOME/.config/fastfetch/config.jsonc"

    # Overwrite with custom if available
    if [ -f "$CONFIGS_DIR/config.jsonc" ]; then
      cp "$CONFIGS_DIR/config.jsonc" "$dest_config"
      
      # Smart Icon Replacement
      # Default in file is Arch: " "
      local os_icon=" " # Default/Arch
      
      case "$DISTRO_ID" in
          fedora) os_icon=" " ;;
          debian) os_icon=" " ;;
          ubuntu) os_icon=" " ;;
      esac
      
      # Replace the icon in the file
      # We look for the line containing "key": " " and substitute.
      # Using specific regex to match the exact Arch icon  in the key value.
      sed -i "s/\"key\": \" \"/\"key\": \"$os_icon\"/" "$dest_config"
      
      log_success "Applied custom fastfetch config with $DISTRO_ID icon"
    else
       # Generate default if completely missing
       if [ ! -f "$dest_config" ]; then
         fastfetch --gen-config &>/dev/null
       fi
    fi
  fi
}

setup_kde_shortcuts() {
  [[ "${XDG_CURRENT_DESKTOP:-}" != "KDE" ]] && return

  step "Setting up KDE global shortcuts"
  local src="$CONFIGS_DIR/kglobalshortcutsrc"
  local dest="$HOME/.config/kglobalshortcutsrc"

  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    log_success "Applied KDE shortcuts (Meta+Q: Close, Meta+Ret: Terminal)"
    log_info "Changes take effect after re-login"
  else
    log_warning "KDE shortcuts config missing"
  fi
}

setup_gnome_configs() {
  # GNOME check (covers standard GNOME, Ubuntu, Pop_OS, etc)
  [[ "${XDG_CURRENT_DESKTOP:-}" != *"GNOME"* ]] && return

  step "Setting up GNOME configurations"

  if ! command -v gsettings >/dev/null; then
    log_warning "gsettings missing, skipping GNOME setup"
    return
  fi

  # Helper function to reduce boilerplate
  set_gnome_key() {
    local schema="$1"
    local key="$2"
    local val="$3"
    local msg="${4:-}"

    # Verify schema and key exist to prevent errors
    if gsettings list-keys "$schema" 2>/dev/null | grep -q "^$key$"; then
      if gsettings set "$schema" "$key" "$val"; then
        [[ -n "$msg" ]] && log_success "$msg"
      fi
    fi
  }

  log_info "Applying GNOME optimizations..."

  # array of settings: schema | key | value | success_message
  local settings=(
    "org.gnome.desktop.interface|color-scheme|'prefer-dark'|Dark theme enabled"
    "org.gnome.desktop.wm.preferences|button-layout|'appmenu:minimize,maximize,close'|Window controls enabled"
    "org.gnome.desktop.peripherals.touchpad|tap-to-click|true|Tap-to-click enabled"
    "org.gnome.desktop.interface|enable-hot-corners|false|Hot corners disabled"
    "org.gnome.desktop.interface|show-battery-percentage|true|Battery % shown"
    "org.gnome.desktop.interface|font-antialiasing|'rgba'|"
    "org.gnome.desktop.interface|font-hinting|'slight'|Font rendering optimized"
    "org.gnome.desktop.wm.keybindings|close|['<Super>q']|Bind: Meta+Q closes windows"
    "org.gnome.shell.keybindings|screenshot|['Print']|Bind: PrintScreen for screenshot"
  )

  for setting in "${settings[@]}"; do
    IFS='|' read -r schema key val msg <<< "$setting"
    set_gnome_key "$schema" "$key" "$val" "$msg"
  done

  # Power Menu (Ctrl+Alt+Del) - Handle version differences
  local power_schema="org.gnome.settings-daemon.plugins.media-keys"
  if gsettings list-schemas | grep -q "org.gnome.SessionManager"; then
    power_schema="org.gnome.SessionManager"
  fi
  set_gnome_key "$power_schema" "logout" "['<Primary><Alt>Delete']" "Bind: Ctrl+Alt+Del for Power Menu"

  # Terminal Shortcut (Meta+Enter) logic
  # Detect installed terminal (preference order: Console -> Gnome Console -> Gnome Terminal)
  local term_cmd=""
  for term in kgx gnome-console gnome-terminal; do
    if command -v "$term" >/dev/null; then
      term_cmd="$term"
      break
    fi
  done

  if [[ -n "$term_cmd" ]]; then
    # Custom keybinding setup requires relocatable schemas
    local schema="org.gnome.settings-daemon.plugins.media-keys"
    local path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
    local binding_schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$path"

    set_gnome_key "$schema" "custom-keybindings" "['$path']"

    # Apply binding details directly since we constructed the specific schema path
    gsettings set "$binding_schema" name 'Terminal' 2>/dev/null
    gsettings set "$binding_schema" command "$term_cmd" 2>/dev/null
    gsettings set "$binding_schema" binding '<Super>Return' 2>/dev/null

    log_success "Bind: Meta+Enter opens $term_cmd"
  else
    log_warning "No supported terminal found for Meta+Enter shortcut"
  fi

  log_info "GNOME settings will be active after session restart"
}

# Main execution
setup_shell
setup_kde_shortcuts
setup_gnome_configs
