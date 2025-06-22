#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

make_systemd_boot_silent() {
  step "Making Systemd-Boot silent for all installed kernels"
  local ENTRIES_DIR="/boot/loader/entries"
  local kernel_types
  kernel_types=($(get_installed_kernel_types))
  for kernel in "${kernel_types[@]}"; do
    local linux_entry
    linux_entry=$(find "$ENTRIES_DIR" -type f -name "*${kernel}.conf" ! -name '*fallback.conf' -print -quit)
    if [ -z "$linux_entry" ]; then
      log_warning "Linux entry not found for kernel: $kernel"
      continue
    fi
    if sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$linux_entry"; then
      log_success "Silent boot options added to Linux entry: $(basename "$linux_entry")."
    else
      log_error "Failed to modify Linux entry: $(basename "$linux_entry")."
    fi
  done
}

change_loader_conf() {
  step "Changing loader.conf"
  local LOADER_CONF="/boot/loader/loader.conf"
  if [ ! -f "$LOADER_CONF" ]; then
    log_warning "loader.conf not found at $LOADER_CONF"
    return
  fi

  sudo sed -i '/^default /d' "$LOADER_CONF"
  sudo sed -i '1i default @saved' "$LOADER_CONF"

  if grep -q '^timeout' "$LOADER_CONF"; then
    sudo sed -i 's/^timeout.*/timeout 3/' "$LOADER_CONF"
  else
    echo "timeout 3" | sudo tee -a "$LOADER_CONF" >/dev/null
  fi

  if grep -Eq '^[#]*console-mode[[:space:]]+keep' "$LOADER_CONF"; then
    sudo sed -i 's/^[#]*console-mode[[:space:]]\+keep/console-mode max/' "$LOADER_CONF"
  elif grep -Eq '^[#]*console-mode[[:space:]]+.*' "$LOADER_CONF"; then
    sudo sed -i 's/^[#]*console-mode[[:space:]]\+.*/console-mode max/' "$LOADER_CONF"
  else
    echo "console-mode max" | sudo tee -a "$LOADER_CONF" >/dev/null
  fi

  log_success "Loader configuration updated."
}

remove_fallback_entries() {
  step "Removing fallback entries from systemd-boot"
  local ENTRIES_DIR="/boot/loader/entries"
  local entries_removed=0

  # Check if directory exists
  if [ ! -d "$ENTRIES_DIR" ]; then
    log_warning "Entries directory $ENTRIES_DIR does not exist"
    return 0
  fi

  shopt -s nullglob
  for entry in "$ENTRIES_DIR"/*fallback.conf; do
    [ -f "$entry" ] || continue
    if sudo rm "$entry"; then
      log_success "Removed fallback entry: $(basename "$entry")"
      entries_removed=1
    else
      log_error "Failed to remove fallback entry: $(basename "$entry")"
    fi
  done
  shopt -u nullglob

  if [ $entries_removed -eq 0 ]; then
    log_warning "No fallback entries found to remove."
  fi

  return 0  # Explicitly return success
}

setup_fastfetch_config() {
  if command -v fastfetch >/dev/null; then
    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
      log_warning "fastfetch config already exists. Skipping generation."
    else
      run_step "Creating fastfetch config" bash -c 'fastfetch --gen-config'
    fi
    if [ -f "$CONFIGS_DIR/config.jsonc" ]; then
      mkdir -p "$HOME/.config/fastfetch"
      cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
    fi
  fi
}

# Execute boot configuration steps
make_systemd_boot_silent
change_loader_conf
remove_fallback_entries
setup_fastfetch_config 