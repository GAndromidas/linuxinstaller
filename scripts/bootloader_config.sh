#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/../configs" # Assuming configs are in archinstaller/configs
source "$SCRIPT_DIR/common.sh" # Source common functions like detect_bootloader and is_btrfs_system

# Apply all boot configurations at once for systemd-boot
configure_boot() {
  # Make systemd-boot silent
  find /boot/loader/entries -name "*.conf" ! -name "*fallback.conf" -exec \
    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' {} \; 2>/dev/null || true

  # Configure loader.conf
  if [ -f "/boot/loader/loader.conf" ]; then
    sudo sed -i \
      -e '/^default /d' \
      -e '1i default @saved' \
      -e 's/^timeout.*/timeout 3/' \
      -e 's/^[#]*console-mode[[:space:]]\+.*/console-mode max/' \
      /boot/loader/loader.conf

    # Add missing lines
    grep -q '^timeout' /boot/loader/loader.conf || echo "timeout 3" | sudo tee -a /boot/loader/loader.conf >/dev/null
    grep -q '^console-mode' /boot/loader/loader.conf || echo "console-mode max" | sudo tee -a /boot/loader/loader.conf >/dev/null
  fi

  # Remove fallback entries
  sudo rm -f /boot/loader/entries/*fallback.conf 2>/dev/null || true
}

setup_fastfetch_config() {
  if command -v fastfetch >/dev/null; then
    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
      log_warning "fastfetch config already exists. Skipping generation."
    else
      run_step "Creating fastfetch config" bash -c 'fastfetch --gen-config'
    fi

    # Safe config file copy
    if [ -f "$CONFIGS_DIR/config.jsonc" ]; then
      mkdir -p "$HOME/.config/fastfetch"
      cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
      log_success "fastfetch config copied from configs directory."
    else
      log_warning "config.jsonc not found in configs directory. Using generated config."
    fi
  else
    log_warning "fastfetch not installed. Skipping config setup."
  fi
}

# Execute ultra-fast boot configuration (for systemd-boot)
if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
    configure_boot
fi
setup_fastfetch_config

# --- Bootloader and Btrfs detection variables (using centralized functions) ---
BOOTLOADER=$(detect_bootloader)
IS_BTRFS=$(is_btrfs_system && echo "true" || echo "false") # Store as "true" or "false" for easier scripting


# --- GRUB configuration ---
configure_grub() {
    step "Configuring GRUB for default kernel priority (Visual Reorder)"

    # 1. Configure /etc/default/grub
    log_info "Updating /etc/default/grub settings for visual reordering..."
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
    # Fix: Correct GRUB_SAVEDAFAULT typo and ensure it's set to false
    sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=false/' /etc/default/grub || sudo sed -i 's/^GRUB_SAVEDAFAULT=.*/GRUB_SAVEDEFAULT=false/' /etc/default/grub

    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
    sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"/' /etc/default/grub

    # Ensure other common GRUB settings are present or updated
    grep -q '^GRUB_GFXMODE=' /etc/default/grub || echo 'GRUB_GFXMODE=auto' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub || echo 'GRUB_GFXPAYLOAD_LINUX=keep' | sudo tee -a /etc/default/grub >/dev/null

    if grep -q '^GRUB_DISABLE_SUBMENU=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub
    else
        echo 'GRUB_DISABLE_SUBMENU=y' | sudo tee -a /etc/default/grub >/dev/null
    fi

    if pacman -Q grub-btrfs &>/dev/null; then
        if grep -q '^GRUB_BTRFS_SUBMENU=' /etc/default/grub; then
            sudo sed -i 's/^GRUB_BTRFS_SUBMENU=.*/GRUB_BTRFS_SUBMENU=n/' /etc/default/grub
        else
            echo 'GRUB_BTRFS_SUBMENU=n' | sudo tee -a /etc/default/grub >/dev/null
        fi
    fi
    log_success "Updated /etc/default/grub."

    # Remove all fallback initramfs images from /boot (this makes grub.cfg cleaner as well)
    log_info "Removing fallback initramfs images from /boot..."
    sudo rm -f /boot/initramfs-*-fallback.img 2>/dev/null || true
    log_success "Fallback initramfs images removed."

    # 2. Extract necessary information for custom menuentry
    log_info "Extracting system information for custom GRUB entry..."
    local ROOT_UUID=$(findmnt -no UUID /)
    if [ -z "$ROOT_UUID" ]; then
        log_error "Failed to determine root partition UUID. Cannot create custom GRUB entry for ordering."
        return 1
    fi
    log_success "Root UUID: $ROOT_UUID"

    local ROOT_DEV_FULL=$(findmnt -no SOURCE /) # e.g., /dev/vda2[/@]
    log_info "Full root device path: $ROOT_DEV_FULL"

    # Fix: Correctly strip [/@] or any [...] suffix from Btrfs paths
    local ROOT_DEV_STRIPPED=$(echo "$ROOT_DEV_FULL" | cut -d '[' -f1) # e.g., /dev/vda2
    log_info "Stripped root device path: $ROOT_DEV_STRIPPED"

    local ROOT_PART_DEV=$(basename "$ROOT_DEV_STRIPPED") # e.g., vda2
    log_info "Root partition device name: $ROOT_PART_DEV"

    local ROOT_PART_NUM
    # Handle different partition naming schemes (e.g., sda1, vda1, nvme0n1p1, mmcblk0p1)
    if [[ "$ROOT_PART_DEV" =~ ^(sd[a-z]|hd[a-z]|vd[a-z])[0-9]+$ ]]; then
        ROOT_PART_NUM=$(echo "$ROOT_PART_DEV" | grep -o '[0-9]*$')
    elif [[ "$ROOT_PART_DEV" =~ ^nvme[0-9]n[0-9]p[0-9]+$ ]]; then
        ROOT_PART_NUM=$(echo "$ROOT_PART_DEV" | grep -o 'p[0-9]*$' | sed 's/p//')
    elif [[ "$ROOT_PART_DEV" =~ ^mmcblk[0-9]p[0-9]+$ ]]; then # Added eMMC support
        ROOT_PART_NUM=$(echo "$ROOT_PART_DEV" | grep -o 'p[0-9]*$' | sed 's/p//')
    else
        log_error "Could not determine root partition number from \"$ROOT_PART_DEV\". Cannot create custom GRUB entry."
        return 1
    fi
    log_success "Root Partition Number: $ROOT_PART_NUM"

    local ROOT_DISK # e.g., sda or nvme0n1 or vda or mmcblk0
    if [[ "$ROOT_PART_DEV" =~ ^(sd[a-z]|hd[a-z]|vd[a-z])[0-9]+$ ]]; then
        ROOT_DISK=$(echo "$ROOT_PART_DEV" | sed 's/[0-9]*$//')
    elif [[ "$ROOT_PART_DEV" =~ ^nvme[0-9]n[0-9]p[0-9]+$ ]]; then
        ROOT_DISK=$(echo "$ROOT_PART_DEV" | sed 's/p[0-9]*$//')
    elif [[ "$ROOT_PART_DEV" =~ ^(mmcblk[0-9])p[0-9]+$ ]]; then # Added eMMC support
        ROOT_DISK=$(echo "$ROOT_PART_DEV" | sed 's/p[0-9]*$//')
    else
        log_error "Could not determine root disk from \"$ROOT_PART_DEV\". Cannot create custom GRUB entry."
        return 1
    fi
    log_success "Root Disk (device prefix): $ROOT_DISK"

    local GRUB_DISK_NUM=-1
    # Loop through detected disks to find matching device for GRUB's hdX naming
    local DISK_DEVS=()
    mapfile -t DISK_DEVS < <(lsblk -o KNAME,TYPE | awk '$2=="disk" {print $1}')

    for i in "${!DISK_DEVS[@]}"; do
        if [[ "${DISK_DEVS[$i]}" == "$ROOT_DISK" ]]; then
            GRUB_DISK_NUM="$i"
            break
        fi
    done

    if [ "$GRUB_DISK_NUM" -eq -1 ]; then
        log_error "Failed to determine GRUB disk number for \"$ROOT_DISK\". Cannot create custom GRUB entry."
        return 1
    fi
    log_success "GRUB Disk Number (hdX): $GRUB_DISK_NUM"

    local FSTYPE=$(findmnt -no FSTYPE /)
    local GRUB_FSM="" # Initialize, will build with insmod commands
    local PART_TABLE_TYPE="gpt" # Default partition table type

    # Use parted to check partition table type
    if sudo parted -s "$ROOT_DEV_STRIPPED" print | grep -q "Partition Table: msdos"; then
        GRUB_FSM="insmod part_msdos"
        PART_TABLE_TYPE="msdos"
    else
        GRUB_FSM="insmod part_gpt" # Assume GPT if not msdos
    fi

    # Add filesystem specific insmod
    if [ "$FSTYPE" = "btrfs" ]; then
        GRUB_FSM="$GRUB_FSM insmod btrfs"
    elif [ "$FSTYPE" = "ext4" ] || [ "$FSTYPE" = "ext3" ] || [ "$FSTYPE" = "ext2" ]; then
        GRUB_FSM="$GRUB_FSM insmod ext2"
    elif [ "$FSTYPE" = "xfs" ]; then
        GRUB_FSM="$GRUB_FSM insmod xfs"
    elif [ "$FSTYPE" = "vfat" ]; then # For EFI system partition, unlikely to be root
        GRUB_FSM="$GRUB_FSM insmod fat"
    else
        log_warning "Unsupported root filesystem type '$FSTYPE'. Defaulting to basic GRUB filesystem modules."
        GRUB_FSM="$GRUB_FSM insmod linux" # Generic for other types
    fi
    GRUB_FSM=$(echo "$GRUB_FSM" | xargs) # Trim whitespace and multiple spaces
    log_success "GRUB Filesystem Modules: $GRUB_FSM"

    local GRUB_CMDLINE_LINUX_DEFAULT_VAL=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | cut -d'"' -f2)
    local GRUB_CMDLINE_LINUX_VAL=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub | sed -n 's/^GRUB_CMDLINE_LINUX="\([^"]*\)"/\1/p' || echo "") # Robust extraction

    # Combine cmdline options, ensuring root=UUID is explicitly included and not duplicated.
    local FULL_CMDLINE="${GRUB_CMDLINE_LINUX_DEFAULT_VAL} ${GRUB_CMDLINE_LINUX_VAL}"
    FULL_CMDLINE=$(echo "$FULL_CMDLINE" | xargs) # Trim whitespace

    if [[ ! "$FULL_CMDLINE" =~ root=UUID= ]]; then
        FULL_CMDLINE="root=UUID=$ROOT_UUID $FULL_CMDLINE"
    fi
    # Remove any potential duplicate root=UUID entries if they exist
    FULL_CMDLINE=$(echo "$FULL_CMDLINE" | sed -E 's/(root=UUID=[a-f0-9-]{36}).*\1/\1/' | xargs)

    log_success "Combined Kernel Cmdline: $FULL_CMDLINE"

    # 3. Create a custom GRUB script (09_arch_linux_default_kernel) with higher priority
    local grub_script_path="/etc/grub.d/09_arch_linux_default_kernel"
    log_info "Creating custom GRUB script '$grub_script_path' to prioritize 'Arch Linux, with Linux linux'..."

    # Use a here document with literal content and dynamic variable expansion
    # Note: Variables like $ROOT_UUID, $GRUB_DISK_NUM etc. are expanded here when the script is written.
    # $0 within the heredoc itself is escaped (\$) so it refers to the 09_ script, not the parent script.
    sudo bash -c "cat << 'GRUB_ENTRY_EOF' > '$grub_script_path'
#!/bin/sh
exec tail -n +3 \$0
# This custom entry ensures 'Arch Linux, with Linux linux' appears first in GRUB menu.
menuentry 'Arch Linux, with Linux linux' --class arch --class gnu-linux --class gnu --class os \$menuentry_id_option 'gnulinux-simple-$(findmnt -no UUID /)' {
    load_video
    set gfxpayload=keep
    insmod gzio
    $GRUB_FSM

    # Set root based on disk and partition number (e.g., hd0,gpt2 or hd0,msdos2)
    # This is a more direct approach for GRUB to find the root partition.
    set root='hd$GRUB_DISK_NUM,$PART_TABLE_TYPE$ROOT_PART_NUM'

    # Fallback search by UUID for robustness, especially if partition order changes
    if [ x\$feature_platform_search_hint = xy ]; then
      search --no-floppy --fs-uuid --set=root $ROOT_UUID
    fi
    echo 'Loading Linux linux ...'
    linux /boot/vmlinuz-linux $FULL_CMDLINE
    echo 'Loading initial ramdisk ...'
    initrd /boot/initramfs-linux.img
}
GRUB_ENTRY_EOF"
    sudo chmod +x "$grub_script_path"
    log_success "Custom GRUB script created and made executable."

    # 4. Generate initial GRUB configuration (needed to get a full grub.cfg before deleting entries from it)
    log_info "Generating initial GRUB configuration (to ensure a base grub.cfg exists for cleanup)..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_success "Initial GRUB configuration generated."

    # 5. Remove fallback kernel entries and the default 'Arch Linux, with Linux linux' entry from 10_linux script
    log_info "Cleaning up /boot/grub/grub.cfg: Removing fallback entries and the duplicate 'Arch Linux, with Linux linux'..."
    # Delete the standard 'Arch Linux, with Linux linux' entry generated by 10_linux
    # This sed command is designed to delete the entire menuentry block.
    # It finds the line starting with "menuentry 'Arch Linux, with Linux linux'",
    # then deletes until the closing brace '}' for that entry.
    sudo sed -i "/^menuentry 'Arch Linux, with Linux linux'/,/^}/d" /boot/grub/grub.cfg || true

    # Delete any other fallback entries or similar
    sudo sed -i '/^menuentry / { N; /\n.*fallback/ { d }; P; D }' /boot/grub/grub.cfg || true
    sudo sed -i '/initrd \/boot\/initramfs-.*-fallback.img/d/' /boot/grub/grub.cfg || true
    sudo sed -i '/title .*fallback/d/' /boot/grub/grub.cfg || true
    log_success "Fallback and duplicate entries cleaned up."


    # 6. Final grub-mkconfig to apply the custom script
    log_info "Generating final GRUB configuration with custom entry... This may take a moment."
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_success "GRUB configuration complete: 'Arch Linux, with Linux linux' should now appear first."
    log_success "Please reboot to verify the changes."
}


# --- Windows Dual-Boot Detection and Configuration ---

detect_windows() {
    # Check for Windows EFI bootloader
    if [ -d /boot/efi/EFI/Microsoft ] || [ -d /boot/EFI/Microsoft ]; then
        return 0
    fi
    # Check for NTFS partitions (Windows)
    if lsblk -f | grep -qi ntfs; then
        return 0
    fi
    return 1
}

add_windows_to_grub() {
    step "Adding Windows to GRUB menu"
    sudo pacman -S --noconfirm os-prober >/dev/null 2>&1 || log_warning "Failed to install os-prober"

    # Ensure GRUB_DISABLE_OS_PROBER is not set to true
    if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    else
        echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null
    fi
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_success "Windows entry added to GRUB (if detected by os-prober)."
}

find_windows_efi_partition() {
    local partitions=($(lsblk -n -o NAME,TYPE | grep "part" | awk '{print "/dev/"$1}'))
    for partition in "${partitions[@]}"; do
        local temp_mount="/tmp/windows_efi_check"
        mkdir -p "$temp_mount"
        if sudo mount "$partition" "$temp_mount" 2>/dev/null; then
            if [ -d "$temp_mount/EFI/Microsoft" ]; then
                sudo umount "$temp_mount"
                sudo rm -rf "$temp_mount"
                echo "$partition"
                return 0
            fi
            sudo umount "$temp_mount"
        fi
        sudo rm -rf "$temp_mount"
    done
    return 1
}

add_windows_to_systemdboot() {
    step "Adding Windows to systemd-boot menu"
    # Only copy EFI files if not already present
    if [ ! -d "/boot/EFI/Microsoft" ]; then
        local windows_partition
        windows_partition=$(find_windows_efi_partition)
        if [ -z "$windows_partition" ]; then
            log_error "Could not find Windows EFI partition"
            return 1
        fi
        local mount_point="/mnt/winefi"
        mkdir -p "$mount_point"
        if sudo mount "$windows_partition" "$mount_point"; then
            if [ -d "$mount_point/EFI/Microsoft" ]; then
                sudo cp -R "$mount_point/EFI/Microsoft" /boot/EFI/
                log_success "Copied Microsoft EFI files to /boot/EFI/Microsoft."
            else
                log_error "Microsoft EFI files not found in $windows_partition"
            fi
            sudo umount "$mount_point"
        else
            log_error "Failed to mount Windows EFI partition"
        fi
        sudo rm -rf "$mount_point"
    else
        log_success "Microsoft EFI files already present in /boot/EFI/Microsoft."
    fi

    # Create loader entry if not present
    local entry="/boot/loader/entries/windows.conf"
    if [ ! -f "$entry" ]; then
        sudo bash -c "cat <<EOF > \"$entry\"
title   Windows
efi     /EFI/Microsoft/Boot/bootmgfw.efi
EOF"
        log_success "Added Windows entry to systemd-boot."
    else
        log_success "Windows entry already exists in systemd-boot."
    fi
}

set_localtime_for_windows() {
    step "Adjusting hardware clock for Windows compatibility"
    sudo timedatectl set-local-rtc 1 --adjust-system-clock
    log_success "Set hardware clock to local time for Windows compatibility."
}

# --- Main Execution ---

# Apply GRUB config if needed
if [ "$BOOTLOADER" = "grub" ]; then
    configure_grub
fi

# Windows dual-boot configuration
if detect_windows; then
    log_info "Windows installation detected. Configuring dual-boot..."
    # Always install ntfs-3g for NTFS access
    run_step "Installing ntfs-3g for Windows partition access" sudo pacman -S --noconfirm ntfs-3g >/dev/null 2>&1

    if [ "$BOOTLOADER" = "grub" ]; then
        add_windows_to_grub
    elif [ "$BOOTLOADER" = "systemd-boot" ]; then
        add_windows_to_systemdboot
    fi
    set_localtime_for_windows
fi
