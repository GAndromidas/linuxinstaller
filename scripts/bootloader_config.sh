#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

add_systemd_boot_kernel_params() {
  local boot_entries_dir="/boot/loader/entries"
  if [ ! -d "$boot_entries_dir" ]; then
    log_warning "Boot entries directory not found. Skipping kernel parameter addition for systemd-boot."
    return 0 # Not an error that should stop the script
  fi

  local modified_count=0
  local entries_found=0

  # Helper function to process entries
  process_boot_entries() {
    while IFS= read -r -d $'\0' entry; do
      ((entries_found++))
      local entry_name=$(basename "$entry")

      # Extract current options line
      local current_line=$(grep "^options " "$entry" || true)

      if [ -n "$current_line" ]; then
          local current_opts=${current_line#options }

          # Define desired params
          local desired_params="quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"

          # Use awk to deduplicate existing options and append missing desired ones
          local new_opts=$(echo "$current_opts $desired_params" | awk '{
              for (i=1; i<=NF; i++) {
                  if (!seen[$i]++) {
                      printf "%s%s", (count++ ? " " : ""), $i
                  }
              }
              printf "\n"
          }')

          # Check if change is needed
          if [ "$current_opts" != "$new_opts" ]; then
               # Escape slashes and ampersands for sed replacement
               local esc_new_opts=$(echo "$new_opts" | sed 's/[\/&]/\\&/g')

               if sudo sed -i "s|^options .*|options $esc_new_opts|" "$entry"; then
                   log_success "Cleaned and updated kernel parameters in $entry_name"
                   ((modified_count++))
               else
                   log_error "Failed to update $entry_name"
               fi
          else
               log_info "Parameters already optimized in $entry_name"
          fi
      fi
    done
  }

  # First pass: Look for specific Linux entries (*linux*.conf) to correspond with archinstall naming
  process_boot_entries < <(find "$boot_entries_dir" -name "*linux*.conf" ! -name "*fallback.conf" -print0)

  # Fallback pass: If no entries found, check generic .conf files (e.g., custom naming)
  if [ "$entries_found" -eq 0 ]; then
    log_info "No standard *linux*.conf entries found. Searching all .conf files..."
    process_boot_entries < <(find "$boot_entries_dir" -name "*.conf" ! -name "*fallback.conf" -print0)
  fi

  if [ "$entries_found" -eq 0 ]; then
    log_warning "No systemd-boot entries found to modify."
  elif [ "$modified_count" -gt 0 ]; then
    log_success "Kernel parameters updated for $modified_count systemd-boot entries."
  else
    log_info "No systemd-boot entries needed parameter updates."
  fi
  return 0
}

# --- systemd-boot ---
configure_boot() {
  run_step "Adding kernel parameters to systemd-boot entries" add_systemd_boot_kernel_params

  if [ -f "/boot/loader/loader.conf" ]; then
    sudo sed -i \
      -e '/^default /d' \
      -e '1i default @saved' \
      -e 's/^timeout.*/timeout 3/' \
      -e 's/^[#]*console-mode[[:space:]]\+.*/console-mode max/' \
      /boot/loader/loader.conf

    run_step "Ensuring timeout is set in loader.conf" \
        grep -q '^timeout' /boot/loader/loader.conf || echo "timeout 3" | sudo tee -a /boot/loader/loader.conf >/dev/null
    run_step "Ensuring console-mode is set in loader.conf" \
        grep -q '^console-mode' /boot/loader/loader.conf || echo "console-mode max" | sudo tee -a /boot/loader/loader.conf >/dev/null

    # Verify configuration was applied
    if grep -q '^timeout' /boot/loader/loader.conf && grep -q '^console-mode' /boot/loader/loader.conf; then
      log_success "Systemd-boot configuration verified"
    else
      log_warning "Systemd-boot configuration may be incomplete"
    fi
  else
    log_warning "loader.conf not found. Skipping loader.conf configuration for systemd-boot."
  fi

  run_step "Removing systemd-boot fallback entries" sudo rm -f /boot/loader/entries/*fallback.conf

  # Check for fallback kernels (informational)
  local boot_mount=$(detect_boot_mount)
  local fallback_count=$(ls "$boot_mount"/*fallback* 2>/dev/null | wc -l)
  if [ "$fallback_count" -gt 0 ]; then
    log_info "Fallback kernels present: $fallback_count file(s)"
    log_info "These are useful for recovery but can be removed to save space"
  else
    log_success "No fallback kernels found (clean setup)"
  fi
}

# --- Bootloader and Btrfs detection ---
BOOTLOADER=$(detect_bootloader)
IS_BTRFS=$(is_btrfs_system && echo "true" || echo "false")

# --- Boot Partition Security ---

# Function to secure boot partition permissions
# This fixes the common issue where ESP (FAT32) partitions have insecure permissions
# Reference: Arch Linux Wiki - EFI System Partition security
secure_boot_permissions() {
  step "Securing boot partition permissions"

  local boot_mount=$(detect_boot_mount)

  if [ ! -d "$boot_mount" ]; then
    log_warning "Boot directory not accessible: $boot_mount"
    return 0  # Not a fatal error
  fi

  log_info "Boot partition detected at: $boot_mount"

  # Check current permissions
  local current_perm=$(stat -c "%a" "$boot_mount" 2>/dev/null || echo "unknown")
  log_info "Current permissions: $current_perm"

  # Check if already secure (700)
  if [ "$current_perm" = "700" ]; then
    log_success "Boot partition permissions are already secure (700)"
    return 0
  fi

  # Try standard chmod first (works for ext4, btrfs, etc.)
  log_info "Attempting to set permissions to 700..."
  if sudo chmod 700 "$boot_mount" 2>/dev/null; then
    # Verify it worked
    local new_perm=$(stat -c "%a" "$boot_mount" 2>/dev/null)
    if [ "$new_perm" = "700" ]; then
      log_success "Boot partition permissions set to 700"
      return 0
    fi
  fi

  # If chmod failed, likely FAT32 (ESP) - need mount options
  log_info "chmod failed (likely FAT32 filesystem). Using mount options..."

  # Get filesystem type
  local fstype=$(findmnt -no FSTYPE "$boot_mount" 2>/dev/null || echo "unknown")

  if [[ "$fstype" =~ ^(vfat|fat|msdos)$ ]]; then
    log_info "FAT32 filesystem detected - using mount options (fmask/dmask)"

    # Try remounting with secure permissions
    if sudo mount -o remount,fmask=0077,dmask=0077 "$boot_mount" 2>/dev/null; then
      log_success "Remounted with secure permissions (fmask=0077,dmask=0077)"
    elif sudo mount -o remount,umask=0077 "$boot_mount" 2>/dev/null; then
      log_success "Remounted with secure permissions (umask=0077)"
    else
      log_warning "Failed to remount with secure permissions"
      log_info "This may require manual intervention or a reboot"
      return 1
    fi

    # Update /etc/fstab for persistence
    if [ -f /etc/fstab ]; then
      log_info "Updating /etc/fstab to persist secure permissions..."

      # Escape mount point for sed
      local boot_esc=$(echo "$boot_mount" | sed 's/\//\\\//g')

      if grep -q "[[:space:]]$boot_mount[[:space:]]" /etc/fstab; then
        # Check if mask options already exist
        if grep "[[:space:]]$boot_mount[[:space:]]" /etc/fstab | grep -qE "mask="; then
          # Update existing masks
          sudo sed -i "/[[:space:]]$boot_esc[[:space:]]/ s/fmask=[0-9]\+/fmask=0077/g" /etc/fstab
          sudo sed -i "/[[:space:]]$boot_esc[[:space:]]/ s/dmask=[0-9]\+/dmask=0077/g" /etc/fstab
          sudo sed -i "/[[:space:]]$boot_esc[[:space:]]/ s/umask=[0-9]\+/umask=0077/g" /etc/fstab
          log_success "Updated existing mask options in /etc/fstab"
        else
          # Append masks to options column
          sudo sed -i "/[[:space:]]$boot_esc[[:space:]]/ s/\(vfat\|auto\|msdos\|fat\)\([[:space:]]\+\)\([^[:space:]]\+\)/\1\2\3,fmask=0077,dmask=0077/" /etc/fstab
          log_success "Added mask options to /etc/fstab"
        fi

        # Reload systemd to apply changes
        sudo systemctl daemon-reload 2>/dev/null || true
      else
        log_warning "$boot_mount not found in /etc/fstab"
        log_info "Permissions fix will be lost on reboot. Please add mount options manually."
      fi
    fi

    # Also fix random-seed permissions if it exists (systemd-boot)
    if [ -f "$boot_mount/loader/random-seed" ]; then
      local seed_perm=$(stat -c "%a" "$boot_mount/loader/random-seed" 2>/dev/null || echo "unknown")
      if [ "$seed_perm" != "600" ]; then
        log_info "Fixing random-seed permissions..."
        sudo chmod 600 "$boot_mount/loader/random-seed" 2>/dev/null || true
      fi
    fi

    log_success "Boot partition permissions secured"
    return 0
  else
    log_warning "Unknown filesystem type: $fstype"
    log_info "Cannot automatically fix permissions for this filesystem type"
    return 1
  fi
}

# --- GRUB configuration ---
configure_grub() {
    step "Configuring GRUB: set default kernel to 'linux'"

    # /etc/default/grub settings
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub || echo 'GRUB_TIMEOUT=3' | sudo tee -a /etc/default/grub >/dev/null
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub || echo 'GRUB_DEFAULT=saved' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub && sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub || echo 'GRUB_SAVEDEFAULT=true' | sudo tee -a /etc/default/grub >/dev/null
    sudo sed -i 's@^GRUB_CMDLINE_LINUX_DEFAULT=.*@GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"@' /etc/default/grub || \
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"' | sudo tee -a /etc/default/grub >/dev/null

    # Enable submenu for additional kernels (linux-lts, linux-zen)
    grep -q '^GRUB_DISABLE_SUBMENU=' /etc/default/grub && sudo sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=notlinux/' /etc/default/grub || \
        echo 'GRUB_DISABLE_SUBMENU=notlinux' | sudo tee -a /etc/default/grub >/dev/null

    grep -q '^GRUB_GFXMODE=' /etc/default/grub || echo 'GRUB_GFXMODE=auto' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub || echo 'GRUB_GFXPAYLOAD_LINUX=keep' | sudo tee -a /etc/default/grub >/dev/null

    # Detect installed kernels
    KERNELS=($(ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||g'))
    if [[ ${#KERNELS[@]} -eq 0 ]]; then
        log_error "No kernels found in /boot."
        return 1
    fi

    # Determine main kernel and secondary kernels (logic kept for informational purposes, not used for default setting)
    MAIN_KERNEL=""
    SECONDARY_KERNELS=()
    for k in "${KERNELS[@]}"; do
        [[ "$k" == "linux" ]] && MAIN_KERNEL="$k"
        [[ "$k" != "linux" && "$k" != "fallback" && "$k" != "rescue" ]] && SECONDARY_KERNELS+=("$k")
    done
    [[ -z "$MAIN_KERNEL" ]] && MAIN_KERNEL="${KERNELS[0]}"

    # Remove fallback/recovery kernels
    sudo rm -f /boot/initramfs-*-fallback.img /boot/vmlinuz-*-fallback 2>/dev/null || true

    # Check for remaining fallback kernels (informational)
    local fallback_count=$(ls /boot/*fallback* 2>/dev/null | wc -l)
    if [ "$fallback_count" -gt 0 ]; then
      log_info "Fallback kernels still present: $fallback_count file(s)"
      log_info "These are useful for recovery but can be removed to save space"
    else
      log_success "No fallback kernels found (clean setup)"
    fi

    # Regenerate grub.cfg
    run_step "Regenerating grub.cfg" sudo grub-mkconfig -o /boot/grub/grub.cfg || return 1

    # Verify GRUB configuration
    if grep -q '^GRUB_DEFAULT=saved' /etc/default/grub && grep -q '^GRUB_SAVEDEFAULT=true' /etc/default/grub; then
      log_success "GRUB configured to remember the last chosen boot entry"
    else
      log_warning "GRUB save default configuration may be incomplete"
    fi
}

# --- Secure Boot / UKI Configuration ---
configure_secure_boot() {
    step "Configuring Secure Boot (sbctl)"

    if ! command -v sbctl >/dev/null 2>&1; then
        run_step "Installing sbctl for Secure Boot management" sudo pacman -S --noconfirm --needed sbctl
    fi

    # Optimize Kernel Parameters in /etc/kernel/cmdline (Primarily for UKI)
    if [ -f "/etc/kernel/cmdline" ] && [ "$(detect_uki)" = "true" ]; then
        log_info "Checking kernel parameters in /etc/kernel/cmdline..."
        local current_cmdline=$(cat /etc/kernel/cmdline)
        local new_cmdline="$current_cmdline"
        local modified=false

        # Add parameters if missing
        if [[ ! "$new_cmdline" =~ "quiet" ]]; then
            new_cmdline="$new_cmdline quiet"
            modified=true
        fi
        if [[ ! "$new_cmdline" =~ "loglevel=3" ]]; then
            new_cmdline="$new_cmdline loglevel=3"
            modified=true
        fi
        if [[ ! "$new_cmdline" =~ "systemd.show_status=auto" ]]; then
            new_cmdline="$new_cmdline systemd.show_status=auto"
            modified=true
        fi
        if [[ ! "$new_cmdline" =~ "rd.udev.log_level=3" ]]; then
            new_cmdline="$new_cmdline rd.udev.log_level=3"
            modified=true
        fi

        if [ "$modified" = "true" ]; then
            echo "$new_cmdline" | sudo tee /etc/kernel/cmdline >/dev/null
            log_success "Updated /etc/kernel/cmdline with optimized parameters"
        else
            log_info "Kernel parameters already optimized."
        fi
    fi

    if [ "$(detect_uki)" = "true" ]; then
        log_info "UKI detected."
    else
        log_info "Standard bootloader detected. Secure Boot will sign existing binaries."
    fi

    log_info "Secure Boot can be managed with 'sbctl'."
    log_info "If you have Windows 11 dual-boot, ensure you enroll Microsoft keys."
    log_info "You can check status with: sudo sbctl status"

    # Check if secure boot is enabled (informational)
    if command -v sbctl >/dev/null 2>&1; then
        if sudo sbctl status 2>/dev/null | grep -q "Secure Boot:.*Enabled"; then
            log_success "Secure Boot is currently ENABLED."
        else
            log_warning "Secure Boot is currently DISABLED or in Setup Mode."
            log_info "To set up: sudo sbctl create-keys && sudo sbctl enroll-keys -m"
        fi

    fi
}

# --- GPU Driver Installation ---
detect_and_install_gpu_drivers() {
  step "Detecting and installing graphics drivers"
  local lspci_out
  lspci_out=$(lspci)

  if echo "$lspci_out" | grep -Eiq 'vga.*amd|3d.*amd|display.*amd'; then
    echo -e "${CYAN}AMD GPU detected. Installing AMD drivers and Vulkan support...${RESET}"
    install_packages_quietly mesa xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver
    log_success "AMD drivers and Vulkan support installed"
    log_info "AMD GPU will use AMDGPU driver after reboot"
  elif echo "$lspci_out" | grep -Eiq 'vga.*intel|3d.*intel|display.*intel'; then
    echo -e "${CYAN}Intel GPU detected. Installing Intel drivers and Vulkan support...${RESET}"
    install_packages_quietly mesa vulkan-intel lib32-vulkan-intel libva-mesa-driver lib32-libva-mesa-driver
    log_success "Intel drivers and Vulkan support installed"
    log_info "Intel GPU will use i915 or xe driver after reboot"
  elif echo "$lspci_out" | grep -qi nvidia; then
    echo -e "${YELLOW}NVIDIA GPU detected.${RESET}"

    # Get PCI ID and map to family
    nvidia_pciid=$(lspci -n -d ::0300 | grep -i nvidia | awk '{print $3}' | head -n1)
    nvidia_family=""
    nvidia_pkg=""
    nvidia_note=""

    # Map PCI ID to family (simplified, for full mapping see ArchWiki and Nouveau code names)
    if echo "$lspci_out" | grep -Eiq 'TU|GA|AD|Turing|Ampere|Lovelace'; then
      nvidia_family="Turing or newer"
      nvidia_pkg="nvidia-open-dkms nvidia-utils lib32-nvidia-utils"
      nvidia_note="(open kernel modules, recommended for Turing/Ampere/Lovelace)"
    elif echo "$lspci_out" | grep -Eiq 'GM|GP|Maxwell|Pascal'; then
      nvidia_family="Maxwell or newer"
      nvidia_pkg="nvidia nvidia-utils lib32-nvidia-utils"
      nvidia_note="(proprietary, recommended for Maxwell/Pascal)"
    else
      # All other older cards (Kepler, Fermi, Tesla) are considered legacy
      nvidia_family="Legacy (Kepler/Fermi/Tesla/Other)"
      nvidia_pkg="nouveau"
      nvidia_note="(legacy, utilizing Nouveau open-source drivers)"
    fi

    echo -e "${CYAN}Detected NVIDIA family: $nvidia_family $nvidia_note${RESET}"

    if [[ "$nvidia_pkg" == "nouveau" ]]; then
      echo -e "${YELLOW}Your NVIDIA GPU is legacy. Installing open-source Nouveau drivers...${RESET}"
      install_packages_quietly mesa xf86-video-nouveau vulkan-nouveau lib32-vulkan-nouveau
      log_success "Nouveau drivers installed."
    else
      echo -e "${CYAN}Installing: $nvidia_pkg${RESET}"
      install_packages_quietly $nvidia_pkg
      log_success "NVIDIA drivers installed."
    fi
    return
  else
    echo -e "${YELLOW}No AMD, Intel, or NVIDIA GPU detected. Installing basic Mesa drivers only.${RESET}"
    install_packages_quietly mesa
  fi

  # Verify GPU driver is loaded
  verify_gpu_driver
}

# Function to verify GPU driver is loaded correctly
verify_gpu_driver() {
  step "Verifying GPU driver installation"
  local lspci_k_out
  lspci_k_out=$(lspci -k)

  # Check which driver is in use
  if echo "$lspci_k_out" | grep -A 3 -iE 'vga|3d|display' | grep -iq 'Kernel driver in use'; then
    log_info "GPU driver status:"
    echo "$lspci_k_out" | grep -A 3 -iE 'vga|3d|display' | grep -E 'VGA|3D|Display|Kernel driver'
    log_success "GPU driver is loaded and in use"
  else
    log_warning "Could not verify GPU driver status"
    log_info "Run 'lspci -k | grep -A 3 -iE \"vga|3d|display\"' after reboot to check driver"
  fi

  # Check for Vulkan support
  if command -v vulkaninfo >/dev/null 2>&1; then
      if vulkaninfo --summary 2>/dev/null | grep -q "deviceName"; then
          log_success "Vulkan support detected"
      else
          log_warning "Vulkan support issues detected (vulkaninfo ran but no deviceName)"
      fi
  fi
}

# --- Early KMS Configuration ---
configure_early_kms() {
  log_info "Configuring Early KMS/GPU Drivers..."
  local mkinitcpio_conf="/etc/mkinitcpio.conf"
  local gpu_modules=""

  # Ensure lspci (pciutils) is installed
  if ! command -v lspci >/dev/null; then
    log_info "Installing pciutils for GPU detection..."
    if ! sudo pacman -S --noconfirm pciutils >/dev/null 2>&1; then
      log_error "Failed to install pciutils. Cannot detect GPU."
      return 1
    fi
  fi

  # Check for virtualization first to avoid loading physical drivers (like nvidia) in VMs
  local virt_type=""
  if command -v systemd-detect-virt >/dev/null; then
      virt_type=$(systemd-detect-virt || true)
  fi

  if [ -n "$virt_type" ] && [ "$virt_type" != "none" ]; then
      log_info "Virtualization detected ($virt_type). Checking for virtual GPU drivers..."
      if lspci | grep -i "VGA" | grep -i "Virtio" >/dev/null; then
          gpu_modules="virtio-gpu"
      elif lspci | grep -i "VGA" | grep -i "QXL" >/dev/null; then
          gpu_modules="qxl"
      elif lspci | grep -i "VGA" | grep -i "VMware" >/dev/null; then
          gpu_modules="vmwgfx"
      elif lspci | grep -i "VGA" | grep -i "InnoTek" >/dev/null; then
          gpu_modules="vboxvideo"
      else
          log_info "No specific virtual GPU detected. Skipping Early KMS modules for VM."
      fi
  else
      # Physical Hardware Detection
      log_info "Checking for physical GPU..."
      if lspci | grep -i "VGA" | grep -i "Intel" >/dev/null; then
        log_info "Detected Intel GPU."
        gpu_modules="i915"
      elif lspci | grep -i "VGA" | grep -i "AMD" >/dev/null || lspci | grep -i "VGA" | grep -i "ATI" >/dev/null; then
        log_info "Detected AMD GPU."
        gpu_modules="amdgpu"
      elif lspci | grep -i "VGA" | grep -i "NVIDIA" >/dev/null; then
        log_info "Detected NVIDIA GPU."
        gpu_modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
      fi
  fi

  if [ -n "$gpu_modules" ]; then
    log_info "Target modules: $gpu_modules"

    # Read current modules
    local current_modules
    current_modules=$(grep "^MODULES=" "$mkinitcpio_conf" | sed 's/MODULES=(\(.*\))/\1/')

    # Check if modules are already present
    local modules_to_add=""
    for mod in $gpu_modules; do
      if ! echo "$current_modules" | grep -q "$mod"; then
        modules_to_add="$modules_to_add $mod"
      fi
    done

    if [ -n "$modules_to_add" ]; then
      log_info "Adding modules to mkinitcpio.conf: $modules_to_add"
      # Cleanly insert modules into the array
      sudo sed -i "s/^MODULES=(\(.*\))/MODULES=(\1 $modules_to_add)/" "$mkinitcpio_conf"
      # Remove double spaces if any
      sudo sed -i "s/  / /g" "$mkinitcpio_conf"
      log_success "Early KMS modules configured."
      return 0
    else
      log_info "Early KMS modules already present in configuration."
    fi
  else
    log_info "No specific GPU modules detected to add."
  fi
  return 0
}

# --- Console Font Setup ---
setup_console_font() {
    run_step "Installing console font" sudo pacman -S --noconfirm --needed terminus-font
    run_step "Configuring /etc/vconsole.conf" bash -c "(grep -q '^FONT=' /etc/vconsole.conf 2>/dev/null && sudo sed -i 's/^FONT=.*/FONT=ter-v16n/' /etc/vconsole.conf) || echo 'FONT=ter-v16n' | sudo tee -a /etc/vconsole.conf >/dev/null"
}

# --- Main execution ---

# 1. Setup Configurations (Font, UKI Params, SBCTL)

# Install GPU drivers first so modules are available for Early KMS
detect_and_install_gpu_drivers

if ! run_step "Configuring Early KMS Modules" configure_early_kms; then
    log_warning "Early KMS configuration encountered issues."
fi

setup_console_font

if [ "$(detect_uki)" = "true" ] || [ "${SECURE_BOOT_SETUP:-false}" = "true" ]; then
    if [ "$(detect_uki)" = "true" ]; then
        log_info "Unified Kernel Image (UKI) setup detected."
    else
        log_info "Secure Boot setup requested via flag."
    fi
    configure_secure_boot
fi

# 2. Build Images (Consumes Font, Plymouth Config, UKI Params)
# This serves as the single source of truth for initramfs/UKI generation.
run_step "Rebuilding initramfs / Generating UKI" sudo mkinitcpio -P

# 3. Configure Bootloader Entries (GRUB/Systemd-boot)
# Runs after build to ensure it sees generated files (and cleans up fallbacks if configured to do so)
if [ "$BOOTLOADER" = "grub" ]; then
    configure_grub
elif [ "$BOOTLOADER" = "systemd-boot" ]; then
    configure_boot
elif [ "$(detect_uki)" != "true" ]; then
    log_warning "No bootloader detected or bootloader is unsupported. Defaulting to systemd-boot configuration."
    configure_boot
fi

# 4. Sign Boot Files (Must happen AFTER build)
if [ "$(detect_uki)" = "true" ] || [ "${SECURE_BOOT_SETUP:-false}" = "true" ]; then
    if command -v sbctl >/dev/null 2>&1; then
        if sudo sbctl verify 2>/dev/null | grep -q "not signed"; then
             log_warning "Files need signing."
             if [ -f /var/lib/sbctl/keys/db.key ] || [ -f /etc/secureboot/keys/db.key ]; then
                 run_step "Signing all boot files" sudo sbctl sign-all
             else
                 log_info "No keys found. Please generate keys manually: sudo sbctl create-keys && sudo sbctl enroll-keys -m"
             fi
        fi
    fi
fi

# 5. Secure Boot Partition Permissions (Lock down the partition last)
secure_boot_permissions
