#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$ARCHINSTALLER_ROOT/configs"
source "$SCRIPT_DIR/common.sh"

# Use different variable names to avoid conflicts
PLYMOUTH_ERRORS=()

# ======= Plymouth Setup Steps =======
enable_plymouth_hook() {
  step "Adding Plymouth hook to mkinitcpio.conf"

  local mkinitcpio_conf="/etc/mkinitcpio.conf"
  if ! grep -q "plymouth" "$mkinitcpio_conf"; then
    sudo sed -i 's/^HOOKS=\(.*\)keyboard \(.*\)/HOOKS=\1plymouth keyboard \2/' "$mkinitcpio_conf"
    log_success "Added plymouth hook to mkinitcpio.conf"
  else
    log_success "Plymouth hook already present in mkinitcpio.conf"
  fi
}

rebuild_initramfs() {
  step "Rebuilding initramfs for all kernels"

  local kernel_types
  kernel_types=($(get_installed_kernel_types))

  if [ "${#kernel_types[@]}" -eq 0 ]; then
    log_warning "No supported kernel types detected. Rebuilding only for 'linux'."
    sudo mkinitcpio -p linux
    return
  fi

  log_info "Detected kernels: ${kernel_types[*]}"

  local total=${#kernel_types[@]}
  local current=0

  for kernel in "${kernel_types[@]}"; do
    ((current++))
    print_progress "$current" "$total" "Rebuilding initramfs for $kernel"

    if sudo mkinitcpio -p "$kernel" >/dev/null 2>&1; then
      print_status " [OK]" "$GREEN"
      log_success "Rebuilt initramfs for $kernel"
    else
      print_status " [FAIL]" "$RED"
      log_error "Failed to rebuild initramfs for $kernel"
      PLYMOUTH_ERRORS+=("Failed to rebuild initramfs for $kernel")
    fi
  done

  echo -e "\n${GREEN}✓ Initramfs rebuild completed for all kernels${RESET}\n"
}

set_plymouth_theme() {
  step "Setting Plymouth theme"

  # List of preferred themes in order of preference
  local preferred_themes=("bgrt" "spinner" "details" "text")
  local selected_theme=""

  # Check available themes
  local available_themes=$(plymouth-set-default-theme -l 2>/dev/null)

  if [ -z "$available_themes" ]; then
    log_warning "No Plymouth themes found. Plymouth may not be properly installed."
    PLYMOUTH_ERRORS+=("No Plymouth themes available")
    return 1
  fi

  # Try to find and use the best available theme
  for theme in "${preferred_themes[@]}"; do
    if echo "$available_themes" | grep -qw "$theme"; then
      # Fix the double slash issue in bgrt theme if it exists
      if [ "$theme" = "bgrt" ]; then
        local bgrt_config="/usr/share/plymouth/themes/bgrt/bgrt.plymouth"
        if [ -f "$bgrt_config" ]; then
          # Fix the double slash in ImageDir path
          if grep -q "ImageDir=/usr/share/plymouth/themes//spinner" "$bgrt_config"; then
            sudo sed -i 's|ImageDir=/usr/share/plymouth/themes//spinner|ImageDir=/usr/share/plymouth/themes/spinner|g' "$bgrt_config"
            log_success "Fixed double slash in bgrt theme configuration"
          fi
        fi
      fi

      # Try to set the theme
      if sudo plymouth-set-default-theme -R "$theme" 2>/dev/null; then
        log_success "Set plymouth theme to '$theme'"
        selected_theme="$theme"
        return 0
      else
        log_warning "Failed to activate '$theme' theme, trying next option..."
        PLYMOUTH_ERRORS+=("Failed to activate '$theme' theme")
      fi
    fi
  done

  # If no preferred theme worked, use the first available theme
  local first_theme
  first_theme=$(echo "$available_themes" | head -n1)
  if [ -n "$first_theme" ]; then
    if sudo plymouth-set-default-theme -R "$first_theme" 2>/dev/null; then
      log_success "Set plymouth theme to first available theme: '$first_theme'"
    else
      log_error "Failed to set any plymouth theme"
      PLYMOUTH_ERRORS+=("Failed to set any plymouth theme")
      return 1
    fi
  else
    log_error "No plymouth themes available"
    PLYMOUTH_ERRORS+=("No plymouth themes available")
    return 1
  fi
}

add_kernel_parameters() {
  step "Adding 'splash' parameter to kernel command line"

  # Detect bootloader and add splash parameter
  if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
    # systemd-boot logic
    local boot_entries_dir="/boot/loader/entries"
    if [ ! -d "$boot_entries_dir" ]; then
      log_warning "Boot entries directory not found. Skipping kernel parameter addition"
      PLYMOUTH_ERRORS+=("Boot entries directory not found")
      return
    fi

    local boot_entries=()
    while IFS= read -r -d '' entry; do
      boot_entries+=("$entry")
    done < <(find "$boot_entries_dir" -name "*.conf" -print0 2>/dev/null)

    if [ ${#boot_entries[@]} -eq 0 ]; then
      log_warning "No boot entries found. Skipping kernel parameter addition"
      PLYMOUTH_ERRORS+=("No boot entries found")
      return
    fi

    log_info "Found ${#boot_entries[@]} boot entries"
    local total=${#boot_entries[@]}
    local current=0
    local modified_count=0

    for entry in "${boot_entries[@]}"; do
      ((current++))
      local entry_name=$(basename "$entry")
      print_progress "$current" "$total" "Adding splash to $entry_name"

      if ! grep -q "splash" "$entry"; then
        if sudo sed -i '/^options / s/$/ splash/' "$entry"; then
          print_status " [OK]" "$GREEN"
          log_success "Added 'splash' to $entry_name"
          ((modified_count++))
        else
          print_status " [FAIL]" "$RED"
          log_error "Failed to add 'splash' to $entry_name"
          PLYMOUTH_ERRORS+=("Failed to add 'splash' to $entry_name")
        fi
      else
        print_status " [SKIP] Already has splash" "$YELLOW"
        log_info "'splash' already set in $entry_name"
      fi
    done

    echo -e "\n${GREEN}✓ Kernel parameters updated for all boot entries (${modified_count} modified)${RESET}\n"

  elif [ -d /boot/grub ] || [ -f /etc/default/grub ]; then
    # GRUB logic
    if grep -q 'splash' /etc/default/grub; then
      log_success "'splash' already present in GRUB_CMDLINE_LINUX_DEFAULT"
    else
      sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="splash /' /etc/default/grub
      log_success "Added 'splash' to GRUB_CMDLINE_LINUX_DEFAULT"

      # Regenerate grub config
      sudo grub-mkconfig -o /boot/grub/grub.cfg
      log_success "Regenerated grub.cfg after adding 'splash'"
    fi
  else
    log_warning "No supported bootloader detected for kernel parameter addition"
    PLYMOUTH_ERRORS+=("No supported bootloader detected")
  fi
}

setup_fastfetch_config() {
  step "Setting up fastfetch configuration"

  if command -v fastfetch >/dev/null; then
    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
      log_success "fastfetch config already exists"
    else
      # Generate default config
      if fastfetch --gen-config >/dev/null 2>&1; then
        log_success "Generated default fastfetch config"
      else
        log_warning "Failed to generate fastfetch config"
        PLYMOUTH_ERRORS+=("Failed to generate fastfetch config")
      fi
    fi

    # Copy custom config if available
    if [ -f "$CONFIGS_DIR/config.jsonc" ]; then
      mkdir -p "$HOME/.config/fastfetch"
      cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
      log_success "Applied custom fastfetch configuration"
    else
      log_info "No custom fastfetch config found, using generated config"
    fi
  else
    log_warning "fastfetch not installed. Skipping config setup"
    PLYMOUTH_ERRORS+=("fastfetch not installed")
  fi
}

print_plymouth_summary() {
  echo -e "\n${CYAN}========= PLYMOUTH SETUP SUMMARY =========${RESET}"
  if [ ${#PLYMOUTH_ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ Plymouth boot screen configuration completed successfully!${RESET}"
    echo -e "${GREEN}✓ Beautiful boot animation is now enabled${RESET}"
  else
    echo -e "${YELLOW}⚠️  Plymouth configuration completed with some warnings:${RESET}"
    for err in "${PLYMOUTH_ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
    echo -e "${GREEN}✓ Core Plymouth functionality should still work${RESET}"
  fi
  echo -e "${CYAN}===========================================${RESET}"
}

# ======= Main =======
main() {
  echo -e "${CYAN}=== Plymouth Boot Screen Setup ===${RESET}"

  # Plymouth configuration steps
  enable_plymouth_hook
  rebuild_initramfs
  set_plymouth_theme
  add_kernel_parameters
  setup_fastfetch_config

  print_plymouth_summary
}

main "$@"
