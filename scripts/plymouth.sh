#!/bin/bash
set -uo pipefail

# Plymouth setup and configuration script
# This implementation is adapted from archinstaller-4.2 and integrated
# with the project's common helpers (run_step, log_info, log_success, etc).
#
# Goals:
#  - Ensure mkinitcpio contains a plymouth hook (sd-plymouth preferred)
#  - Rebuild initramfs for all installed kernels when necessary
#  - Set a suitable Plymouth theme (prefer 'bgrt', fallback to 'spinner' or first available)
#  - Add recommended kernel parameters to systemd-boot or GRUB entries
#  - Be robust to common ESP mountpoints and restrictive /boot permissions

# Get script directory and load common helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Minimal progress printer used for long loops
print_progress() {
  local current="$1"
  local total="$2"
  local description="$3"
  printf "\r\033[K${CYAN}%s...${RESET}" "$description"
}

# Try to set a plymouth theme, with helpful logging
set_plymouth_theme() {
  local theme_primary="bgrt"
  local theme_fallback="spinner"

  # If bgrt has a double-slash ImageDir bug, try to fix it first
  local bgrt_cfg="/usr/share/plymouth/themes/bgrt/bgrt.plymouth"
  if [ -f "$bgrt_cfg" ]; then
    if grep -q "ImageDir=/usr/share/plymouth/themes//" "$bgrt_cfg" 2>/dev/null; then
      if sudo sed -i 's|/usr/share/plymouth/themes//|/usr/share/plymouth/themes/|g' "$bgrt_cfg" 2>/dev/null; then
        log_success "Fixed double-slash ImageDir in bgrt plymouth config"
      else
        log_warning "Could not fix bgrt ImageDir automatically"
      fi
    fi
  fi

  # Helper: try to set a single theme (returns 0 on success)
  try_set_theme() {
    local t="$1"
    if plymouth-set-default-theme -l 2>/dev/null | grep -qw "$t"; then
      if sudo plymouth-set-default-theme -R "$t" >/dev/null 2>&1; then
        log_success "Set Plymouth theme to '$t'"
        return 0
      else
        log_warning "plymouth-set-default-theme failed for '$t'"
        return 1
      fi
    else
      return 2
    fi
  }

  # 1) Try primary theme
  if try_set_theme "$theme_primary"; then
    return 0
  fi

  # 2) Try fallback spinner
  if try_set_theme "$theme_fallback"; then
    return 0
  fi

  # 3) Last resort: first available theme from plymouth-set-default-theme -l
  local first_theme
  first_theme=$(plymouth-set-default-theme -l 2>/dev/null | head -n1 || true)
  if [ -n "$first_theme" ]; then
    if try_set_theme "$first_theme"; then
      return 0
    fi
  fi

  log_error "No suitable Plymouth theme could be set."
  return 1
}

# Add recommended kernel parameters to boot entries (systemd-boot or GRUB)
add_kernel_parameters() {
  # Recommended params for a smooth plymouth boot
  local params=(quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles)
  local params_str="${params[*]}"

  # Determine systemd-boot entries directory robustly:
  # try bootctl -p, then common mountpoints
  local boot_entries_dir=""
  if command -v bootctl >/dev/null 2>&1; then
    # bootctl -p prints the ESP path on systemd systems; suppress errors
    local esp
    esp=$(bootctl -p 2>/dev/null || true)
    if [ -n "$esp" ] && [ -d "$esp/loader/entries" ]; then
      boot_entries_dir="$esp/loader/entries"
    fi
  fi

  for cand in "/boot/loader/entries" "/efi/loader/entries" "/boot/efi/loader/entries" "/boot/EFI/loader/entries" "/efi/EFI/loader/entries"; do
    if [ -z "$boot_entries_dir" ] && [ -d "$cand" ]; then
      boot_entries_dir="$cand"
      break
    fi
  done

  # If we have systemd-boot entries, update them (use sudo for reading/editing)
  if [ -n "$boot_entries_dir" ]; then
    # Gather entries with sudo to handle restrictive permissions
    local -a entries=()
    while IFS= read -r -d '' e; do
      entries+=("$e")
    done < <(sudo find "$boot_entries_dir" -maxdepth 1 -name "*.conf" -print0 2>/dev/null || true)

    if [ ${#entries[@]} -eq 0 ]; then
      log_warning "No boot entries found under $boot_entries_dir; skipping kernel param addition"
    else
      local total=${#entries[@]}
      local count_mod=0
      local i=0
      for e in "${entries[@]}"; do
        ((i++))
        local name
        name=$(basename "$e")
        print_progress "$i" "$total" "Ensuring kernel params for $name"

        # read and update with sudo safely
        if sudo test -f "$e"; then
          local changed=false
          for p in "${params[@]}"; do
            # word-boundary aware check
            if ! sudo grep -q -E "(^|[[:space:]])$p($|[[:space:]])" "$e" 2>/dev/null; then
              if sudo sed -i "/^options / s/$/ $p/" "$e" 2>/dev/null; then
                changed=true
              else
                log_warning "Failed to append '$p' into $name"
              fi
            fi
          done

          if [ "$changed" = true ]; then
            print_status " [OK]" "$GREEN"
            log_success "Updated kernel params in $name"
            ((count_mod++))
          else
            print_status " [SKIP]" "$YELLOW"
            log_info "Kernel params already present in $name"
          fi
        else
          print_status " [FAIL]" "$RED"
          log_warning "Entry $name not accessible"
        fi
      done
      echo -e "\n${GREEN}Kernel parameters updated for systemd-boot entries (${count_mod} modified)${RESET}\n"
    fi

    return 0
  fi

  # If no systemd-boot, attempt GRUB update
  if [ -f /etc/default/grub ]; then
    # Read current value
    local current_line
    current_line=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub 2>/dev/null || true)
    local quoted=""
    if [ -n "$current_line" ]; then
      # extract quoted contents
      quoted=$(echo "$current_line" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT=(.*)/\1/' | sed -E 's/^"(.*)"$/\1/')
    fi

    local new_cmdline="$quoted"
    for p in "${params[@]}"; do
      if ! echo "$quoted" | grep -q -E "(^|[[:space:]])$p($|[[:space:]])"; then
        new_cmdline="$new_cmdline $p"
      fi
    done

    if [ "$new_cmdline" != "$quoted" ]; then
      sudo sed -i "s@^GRUB_CMDLINE_LINUX_DEFAULT=.*@GRUB_CMDLINE_LINUX_DEFAULT=\"${new_cmdline}\"@" /etc/default/grub
      log_success "Updated GRUB_CMDLINE_LINUX_DEFAULT with recommended kernel params"
      if sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
        log_success "Regenerated grub.cfg after updating kernel params."
      else
        log_warning "Failed to regenerate grub.cfg; please run 'sudo grub-mkconfig -o /boot/grub/grub.cfg' manually."
      fi
    else
      log_info "GRUB_CMDLINE_LINUX_DEFAULT already contains the recommended kernel params"
    fi

    return 0
  fi

  log_warning "No supported bootloader detected for kernel parameter addition."
  return 0
}

# Check whether plymouth is already configured end-to-end
is_plymouth_configured() {
  local hook_present=false
  local theme_set=false
  local splash_present=false

  if grep -q "plymouth" /etc/mkinitcpio.conf 2>/dev/null; then
    hook_present=true
  fi

  # If plymouth-set-default-theme prints anything, consider theme available/set
  if plymouth-set-default-theme 2>/dev/null | grep -qv "^$"; then
    theme_set=true
  fi

  # Check splash param in systemd-boot or GRUB
  if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
    if grep -q "splash" /boot/loader/entries/*.conf 2>/dev/null; then
      splash_present=true
    fi
  elif [ -f /etc/default/grub ]; then
    if grep -q 'splash' /etc/default/grub 2>/dev/null; then
      splash_present=true
    fi
  fi

  if [ "$hook_present" = true ] && [ "$theme_set" = true ] && [ "$splash_present" = true ]; then
    return 0
  fi
  return 1
}

# Main entry - orchestrates steps and uses run_step from common.sh
main() {
  echo -e "${CYAN}=== Plymouth Configuration ===${RESET}"

  # If everything already configured, skip
  if is_plymouth_configured; then
    log_success "Plymouth is already configured - skipping setup."
    echo -e "${GREEN}Plymouth configuration detected:${RESET}"
    echo -e "  ✓ Plymouth hook present in /etc/mkinitcpio.conf"
    echo -e "  ✓ Plymouth theme available"
    echo -e "  ✓ Splash kernel parameter set in bootloader"
    echo -e "${CYAN}To force reconfiguration, edit /etc/mkinitcpio.conf or run this script with sudo to inspect logs.${RESET}"
    return 0
  fi

  # 1) Configure mkinitcpio hook and rebuild initramfs (uses function from common.sh)
  if ! run_step "Configuring Plymouth hook and rebuilding initramfs" configure_plymouth_hook_and_initramfs; then
    log_warning "configure_plymouth_hook_and_initramfs reported problems; continuing to other steps"
  fi

  # 2) Set theme
  if ! run_step "Setting Plymouth theme" set_plymouth_theme; then
    log_warning "Plymouth theme configuration failed or no themes available"
  fi

  # 3) Add kernel parameters
  if ! run_step "Adding 'splash' and recommended kernel parameters to boot entries" add_kernel_parameters; then
    log_warning "Kernel parameter addition had issues"
  fi

  # Final summary
  echo ""
  if is_plymouth_configured; then
    log_success "Plymouth configured successfully."
  else
    log_warning "Plymouth setup completed with warnings. Inspect the installer log for details."
  fi
}

main "$@"
