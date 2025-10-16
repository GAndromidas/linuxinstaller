#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/../configs" # Assuming configs are in archinstaller/configs
source "$SCRIPT_DIR/common.sh" # Source common functions like detect_bootloader and is_btrfs_system

# --- systemd-boot handling ---
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

# --- fastfetch config setup ---
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

# Execute systemd-boot config if present
if [ -d /boot/loader ] || [ -d /boot/EFI/systemd ]; then
    configure_boot
fi
setup_fastfetch_config

# --- Bootloader and Btrfs detection variables ---
BOOTLOADER=$(detect_bootloader)
IS_BTRFS=$(is_btrfs_system && echo "true" || echo "false")

# --- Helper: backup paths to timestamped folder ---
_backup_paths() {
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local dest="/root/grub_backup_${ts}"
    sudo mkdir -p "$dest"
    [ -f /etc/default/grub ] && sudo cp -a /etc/default/grub "$dest/" || true
    [ -f /etc/mkinitcpio.conf ] && sudo cp -a /etc/mkinitcpio.conf "$dest/" || true
    sudo cp -a /etc/grub.d "$dest/" 2>/dev/null || true
    [ -f /boot/grub/grub.cfg ] && sudo cp -a /boot/grub/grub.cfg "$dest/" || true
    echo "$dest"
}

# --- GRUB configuration ---
configure_grub() {
    step "Configuring GRUB: standard 'linux' kernel first, cleaning stale entries"

    log_info "Backing up current grub/mkinitcpio configs..."
    BACKUP_DIR=$(_backup_paths)
    log_info "Backups stored at: $BACKUP_DIR"

    # Normalize /etc/default/grub
    log_info "Updating /etc/default/grub..."
    sudo cp -a /etc/default/grub "/etc/default/grub.bak.$(date +%s)" || true
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub || sudo bash -c 'echo "GRUB_DEFAULT=0" >> /etc/default/grub'
    if grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=false/' /etc/default/grub
    else
        echo 'GRUB_SAVEDEFAULT=false' | sudo tee -a /etc/default/grub >/dev/null
    fi
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub || sudo bash -c 'echo "GRUB_TIMEOUT=3" >> /etc/default/grub'

    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
        sudo sed -i 's@^GRUB_CMDLINE_LINUX_DEFAULT=.*@GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"@' /etc/default/grub
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"' | sudo tee -a /etc/default/grub >/dev/null
    fi

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
        log_info "grub-btrfs present: snapshots will be shown as separate GRUB entries."
    fi

    # Ensure plymouth is in mkinitcpio HOOKS
    if [ -f /etc/mkinitcpio.conf ]; then
        if ! grep -q 'plymouth' /etc/mkinitcpio.conf; then
            log_info "Inserting 'plymouth' into HOOKS of /etc/mkinitcpio.conf"
            if grep -q 'filesystems' /etc/mkinitcpio.conf; then
                sudo sed -i "s/\(HOOKS=.*\)filesystems/\1plymouth filesystems/" /etc/mkinitcpio.conf || true
            else
                sudo sed -i "s/^\(HOOKS=.*\)\"$/\1 plymouth\"/" /etc/mkinitcpio.conf || true
            fi
            log_success "plymouth added to HOOKS (backup exists)."
        else
            log_info "plymouth already present in HOOKS."
        fi
    else
        log_warning "/etc/mkinitcpio.conf not found; skipping plymouth hook changes."
    fi

    # Rebuild initramfs for all kernels
    if command -v mkinitcpio >/dev/null 2>&1; then
        log_info "Regenerating initramfs for all presets (mkinitcpio -P)..."
        if sudo mkinitcpio -P >/dev/null 2>&1; then
            log_success "Initramfs regenerated for all presets."
        else
            log_error "mkinitcpio -P failed. You may need to regenerate initramfs manually."
        fi
    else
        log_warning "mkinitcpio not found; skipping initramfs regeneration."
    fi

    # --- Identify kernels and set GRUB default ---
    log_info "Detecting installed Arch kernels..."
    KERNELS=($(ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||g'))

    if [[ ${#KERNELS[@]} -eq 0 ]]; then
        log_error "No kernels found in /boot. Aborting grub configuration."
        return 1
    fi

    log_info "Detected kernels: ${KERNELS[*]}"

    # Prefer 'linux' (mainline) over 'linux-lts' or others
    if [[ " ${KERNELS[*]} " == *" linux "* ]]; then
        DEFAULT_KERNEL="linux"
    else
        DEFAULT_KERNEL="${KERNELS[0]}"
    fi

    log_info "Setting GRUB default to: ${DEFAULT_KERNEL}"

    # Generate GRUB config
    log_info "Generating GRUB config (grub-mkconfig -o /boot/grub/grub.cfg)..."
    if sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
        log_success "grub.cfg generated."
    else
        log_error "grub-mkconfig failed. Aborting grub configuration."
        return 1
    fi

    # --- Set default kernel explicitly ---
    sudo grub-set-default "Advanced options for Arch Linux>Arch Linux, with Linux ${DEFAULT_KERNEL}" >/dev/null 2>&1 || \
        sudo grub-set-default 0

    log_success "GRUB default entry set to: ${DEFAULT_KERNEL}"

    # --- Remove fallback entries ---
    log_info "Removing fallback/recovery entries from grub.cfg..."
    sudo sed -i '/fallback/d;/recovery/d;/rescue/d' /boot/grub/grub.cfg || true
    log_success "Fallback/recovery entries removed."

    # --- Remove fallback initramfs images ---
    log_info "Removing fallback initramfs images from /boot..."
    sudo rm -f /boot/initramfs-*-fallback.img 2>/dev/null || true
    log_success "Fallback initramfs images removed."

    log_success "GRUB configuration finished."
    log_success "Default kernel: ${DEFAULT_KERNEL}"
    log_success "Backups stored at: ${BACKUP_DIR}"
}

# --- Windows Dual-Boot Detection ---
detect_windows() {
    if [ -d /boot/efi/EFI/Microsoft ] || [ -d /boot/EFI/Microsoft ]; then
        return 0
    fi
    if lsblk -f | grep -qi ntfs; then
        return 0
    fi
    return 1
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
if [ "$BOOTLOADER" = "grub" ]; then
    configure_grub
elif [ "$BOOTLOADER" = "systemd-boot" ]; then
    log_info "Detected systemd-boot. systemd-boot-specific configuration already applied."
else
    log_warning "Unknown bootloader ($BOOTLOADER). No bootloader-specific actions taken."
fi

if detect_windows && [ "$BOOTLOADER" = "systemd-boot" ]; then
    log_info "Windows installation detected with systemd-boot. Configuring dual-boot..."
    run_step "Installing ntfs-3g for Windows partition access" sudo pacman -S --noconfirm ntfs-3g >/dev/null 2>&1
    add_windows_to_systemdboot
    set_localtime_for_windows
elif detect_windows && [ "$BOOTLOADER" = "grub" ]; then
    log_info "Windows dual-boot already configured inside GRUB setup."
    set_localtime_for_windows
fi
