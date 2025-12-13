#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Override progress bar to be minimalist
print_progress() {
  local current="$1"
  local total="$2"
  local description="$3"

  # Use printf to avoid a newline, allowing print_status to append to it.
  # \r and \033[K ensure the line is overwritten on each update.
  printf "\r\033[K${CYAN}%s...${RESET}" "$description"
}

# Use different variable names to avoid conflicts
PLYMOUTH_ERRORS=()

# Custom run_step to capture errors and output details on failure
run_plymouth_step() {
  local description="$1"
  shift

  print_unified_substep "$description"

  # Create a temporary file to capture output
  local temp_log
  temp_log=$(mktemp)

  # Run command, redirecting both stdout and stderr to temp log
  if "$@" > "$temp_log" 2>&1; then
      # Success: Append log to main log file (hidden from user)
      cat "$temp_log" >> "$INSTALL_LOG"
      print_unified_success "$description"
      rm -f "$temp_log"
      return 0
  else
      # Failure: Append to main log and SHOW to user
      local exit_code=$?
      cat "$temp_log" >> "$INSTALL_LOG"
      print_unified_error "$description failed"

      echo -e "${RED}Command output:${RESET}"
      cat "$temp_log" | sed 's/^/  /' # Indent output

      PLYMOUTH_ERRORS+=("$description failed")
      rm -f "$temp_log"
      return $exit_code
  fi
}

# ======= Plymouth Setup Steps =======

set_plymouth_theme() {
  local theme="bgrt"

  # Fix the double slash issue in bgrt theme if it exists
  local bgrt_config="/usr/share/plymouth/themes/bgrt/bgrt.plymouth"
  if [ -f "$bgrt_config" ]; then
    # Fix the double slash in ImageDir path
    if grep -q "ImageDir=/usr/share/plymouth/themes//spinner" "$bgrt_config"; then
      sudo sed -i 's|ImageDir=/usr/share/plymouth/themes//spinner|ImageDir=/usr/share/plymouth/themes/spinner|g' "$bgrt_config"
      log_success "Fixed double slash in bgrt theme configuration"
    fi
  fi

  # Helper function to try setting a theme
  try_set_theme() {
    local target="$1"
    local desc="$2"

    if plymouth-set-default-theme -l | grep -qw "$target"; then
      local output
      if output=$(sudo plymouth-set-default-theme -R "$target" 2>&1); then
        log_success "Set plymouth theme to '$target' ($desc)."
        return 0
      else
        log_warning "Failed to set '$target' theme. Output: $output"
        return 1
      fi
    else
      # Only warn if it's the primary theme we really wanted
      if [[ "$desc" == "primary" ]]; then
         log_warning "Theme '$target' not found in available themes."
      fi
      return 2
    fi
  }

  # 1. Try bgrt (primary)
  if try_set_theme "$theme" "primary"; then
    return 0
  fi

  # 2. Try spinner (fallback)
  local fallback_theme="spinner"
  if try_set_theme "$fallback_theme" "fallback"; then
    return 0
  fi

  # 3. Last resort: use the first available theme
  local first_theme
  first_theme=$(plymouth-set-default-theme -l | head -n1)
  if [ -n "$first_theme" ]; then
    if try_set_theme "$first_theme" "last resort"; then
      return 0
    fi
  fi

  log_error "No suitable Plymouth theme could be set."
  return 1
}

add_kernel_parameters() {
  # Recommended kernel parameters for a clean plymouth boot:
  # - quiet: reduce kernel messages on console
  # - splash: enable splash screen
  # - loglevel=3: reduce kernel verbosity
  # - systemd.show_status=auto: nicer systemd status behavior
  # - rd.udev.log_level=3: reduce udev verbose logs during early boot
  # - plymouth.ignore-serial-consoles: avoid plymouth trying to use serial consoles
  local params="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"

  # systemd-boot (bootctl) handling
  # Robust systemd-boot detection: check common ESP mount locations and use sudo checks.
  # This handles cases where /boot is root-only (700) or the ESP is mounted at /efi or /boot/efi.
  local boot_entries_dir=""
  # First try bootctl if available (it returns the ESP path)
  if command -v bootctl >/dev/null 2>&1; then
    local esp_path
    esp_path=$(bootctl -p 2>/dev/null || true)
    if [ -n "$esp_path" ] && sudo test -d "$esp_path/loader/entries" 2>/dev/null; then
      boot_entries_dir="$esp_path/loader/entries"
    fi
  fi

  # Common candidate locations (check with sudo to handle restrictive /boot perms)
  for candidate in "/boot/loader/entries" "/efi/loader/entries" "/boot/efi/loader/entries" "/boot/EFI/loader/entries" "/efi/EFI/loader/entries"; do
    if [ -z "$boot_entries_dir" ] && sudo test -d "$candidate" 2>/dev/null; then
      boot_entries_dir="$candidate"
      break
    fi
  done

  # If we still don't have entries, skip gracefully
  if [ -z "$boot_entries_dir" ]; then
    log_warning "Boot entries directory not found in common locations. Skipping kernel parameter addition."
    return
  fi

  # Collect boot entries using sudo (entries may be root-only)
  local boot_entries=()
  while IFS= read -r -d '' entry; do
    boot_entries+=("$entry")
  done < <(sudo find "$boot_entries_dir" -maxdepth 1 -name "*.conf" -print0 2>/dev/null)

  if [ ${#boot_entries[@]} -eq 0 ]; then
    log_warning "No boot entries found under $boot_entries_dir. Skipping kernel parameter addition."
    return
  fi

  echo -e "${CYAN}Found ${#boot_entries[@]} boot entries (${boot_entries_dir})${RESET}"
  local total=${#boot_entries[@]}
  local current=0
  local modified_count=0

  for entry in "${boot_entries[@]}"; do
    ((current++))
    local entry_name
    entry_name=$(basename "$entry")
    print_progress "$current" "$total" "Ensuring kernel params for $entry_name"

    # Use sudo for reads and edits because the ESP/entries may be root-only
    if sudo test -f "$entry" 2>/dev/null; then
      local changed=false
      for p in $params; do
        if ! sudo grep -q -E "(^|[[:space:]])$p($|[[:space:]])" "$entry" 2>/dev/null; then
          if sudo sed -i "/^options / s/$/ $p/" "$entry"; then
            changed=true
          else
            log_error "Failed to add '$p' to $entry_name"
          fi
        fi
      done

      if [ "$changed" = true ]; then
        print_status " [OK]" "$GREEN"
        log_success "Updated kernel params in $entry_name"
        ((modified_count++))
      else
        print_status " [SKIP] Already configured" "$YELLOW"
        log_info "Kernel params already present in $entry_name"
      fi
    else
      print_status " [FAIL]" "$RED"
      log_error "Entry $entry_name not readable (permission or missing)"
    fi
  done

  echo -e "\\n${GREEN}Kernel parameters updated for systemd-boot entries (${modified_count} modified)${RESET}\\n"
  return

  # GRUB handling
  if [ -f /etc/default/grub ]; then
    # Read current GRUB_CMDLINE_LINUX_DEFAULT
    local current_line
    current_line=$(grep -E "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub 2>/dev/null || true)

    # If no line exists, create one
    if [ -z "$current_line" ]; then
      sudo bash -c "echo 'GRUB_CMDLINE_LINUX_DEFAULT=\"${params}\"' >> /etc/default/grub"
      log_success "Added GRUB_CMDLINE_LINUX_DEFAULT with recommended kernel params"
      sudo grub-mkconfig -o /boot/grub/grub.cfg
      log_success "Regenerated grub.cfg after adding kernel params."
      return
    fi

    # If line exists, ensure each recommended param is present inside the quotes
    local new_cmdline
    # Extract the quoted content
    local quoted
    quoted=$(echo "$current_line" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT=(.*)/\1/' | sed -E 's/^"(.*)"$/\1/')

    # Add missing params
    new_cmdline="$quoted"
    for p in $params; do
      if ! echo "$quoted" | grep -q -E "(^|[[:space:]])$p($|[[:space:]])"; then
        new_cmdline="$new_cmdline $p"
      fi
    done

    # Update only if changes were made
    if [ "$new_cmdline" != "$quoted" ]; then
      sudo sed -i "s@^GRUB_CMDLINE_LINUX_DEFAULT=.*@GRUB_CMDLINE_LINUX_DEFAULT=\"${new_cmdline}\"@" /etc/default/grub
      log_success "Updated GRUB_CMDLINE_LINUX_DEFAULT with recommended kernel params"
      sudo grub-mkconfig -o /boot/grub/grub.cfg
      log_success "Regenerated grub.cfg after updating kernel params."
    else
      log_info "GRUB_CMDLINE_LINUX_DEFAULT already contains the recommended kernel params"
    fi
    return
  fi

  log_warning "No supported bootloader detected for kernel parameter addition."
}

print_plymouth_summary() {
  echo -e "\\n${CYAN}========= PLYMOUTH SUMMARY =========${RESET}"
  if [ ${#PLYMOUTH_ERRORS[@]} -eq 0 ]; then
    echo -e "${GREEN}Plymouth configured successfully!${RESET}"
  else
    echo -e "${RED}Some configuration steps failed:${RESET}"
    for err in "${PLYMOUTH_ERRORS[@]}"; do
      echo -e "  - ${YELLOW}$err${RESET}"
    done
  fi
  echo -e "${CYAN}====================================${RESET}"
}

# ======= Check if Plymouth is already configured =======
is_plymouth_configured() {
  local plymouth_hook_present=false
  local plymouth_theme_set=false
  local splash_parameter_set=false

  # Check if plymouth hook is in mkinitcpio.conf
  if grep -q "plymouth" /etc/mkinitcpio.conf 2>/dev/null; then
    plymouth_hook_present=true
  fi

  # Check if a plymouth theme is set
  if plymouth-set-default-theme 2>/dev/null | grep -qv "^$"; then
    plymouth_theme_set=true
  fi

  # Check if splash parameter is set in bootloader config
  if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
    # systemd-boot
    if grep -q "splash" /boot/loader/entries/*.conf 2>/dev/null; then
      splash_parameter_set=true
    fi
  elif [ -f /etc/default/grub ]; then
    # GRUB
    if grep -q 'splash' /etc/default/grub 2>/dev/null; then
      splash_parameter_set=true
    fi
  fi

  # Return true if all components are configured
  if [ "$plymouth_hook_present" = true ] && [ "$plymouth_theme_set" = true ] && [ "$splash_parameter_set" = true ]; then
    return 0
  else
    return 1
  fi
}

# ======= Main =======
main() {
  # Print simple banner (no figlet)
  echo -e "${CYAN}=== Plymouth Configuration ===${RESET}"

  # Check if plymouth is already fully configured
  if is_plymouth_configured; then
    log_success "Plymouth is already configured - skipping setup to save time"
    echo -e "${GREEN}Plymouth configuration detected:${RESET}"
    echo -e "  ✓ Plymouth hook present in mkinitcpio.conf"
    echo -e "  ✓ Plymouth theme is set"
    echo -e "  ✓ Splash parameter configured in bootloader"
    echo -e "${CYAN}To reconfigure Plymouth, edit /etc/mkinitcpio.conf manually${RESET}"
    return 0
  fi

  # Use the centralized function from common.sh, but our overridden run_step handles it
  run_plymouth_step "Configuring Plymouth hook and rebuilding initramfs" configure_plymouth_hook_and_initramfs
  run_plymouth_step "Setting Plymouth theme" set_plymouth_theme
  run_plymouth_step "Adding 'splash' to all kernel parameters" add_kernel_parameters

  print_plymouth_summary
}

main "$@"
