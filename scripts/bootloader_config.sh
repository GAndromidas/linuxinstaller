#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# --- systemd-boot ---
configure_boot() {
  find /boot/loader/entries -name "*.conf" ! -name "*fallback.conf" -exec \
    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' {} \; 2>/dev/null || true

  if [ -f "/boot/loader/loader.conf" ]; then
    sudo sed -i \
      -e '/^default /d' \
      -e '1i default @saved' \
      -e 's/^timeout.*/timeout 3/' \
      -e 's/^[#]*console-mode[[:space:]]\+.*/console-mode max/' \
      /boot/loader/loader.conf

    grep -q '^timeout' /boot/loader/loader.conf || echo "timeout 3" | sudo tee -a /boot/loader/loader.conf >/dev/null
    grep -q '^console-mode' /boot/loader/loader.conf || echo "console-mode max" | sudo tee -a /boot/loader/loader.conf >/dev/null
  fi

  sudo rm -f /boot/loader/entries/*fallback.conf 2>/dev/null || true
}

# --- Bootloader and Btrfs detection ---
BOOTLOADER=$(detect_bootloader)
IS_BTRFS=$(is_btrfs_system && echo "true" || echo "false")

# --- GRUB configuration ---
configure_grub() {
    step "Configuring GRUB: linux kernel first, others in submenu"

    # /etc/default/grub settings
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub || echo 'GRUB_TIMEOUT=3' | sudo tee -a /etc/default/grub >/dev/null
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub || echo 'GRUB_DEFAULT=0' | sudo tee -a /etc/default/grub >/dev/null
    sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub || echo 'GRUB_SAVEDEFAULT=true' | sudo tee -a /etc/default/grub >/dev/null
    sudo sed -i 's@^GRUB_CMDLINE_LINUX_DEFAULT=.*@GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"@' /etc/default/grub || \
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"' | sudo tee -a /etc/default/grub >/dev/null

    # Enable submenu for additional kernels (linux-lts, linux-zen)
    grep -q '^GRUB_DISABLE_SUBMENU=' /etc/default/grub && sudo sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=notlinux/' /etc/default/grub || \
        echo 'GRUB_DISABLE_SUBMENU=notlinux' | sudo tee -a /etc/default/grub >/dev/null

    grep -q '^GRUB_GFXMODE=' /etc/default/grub || echo 'GRUB_GFXMODE=auto' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub || echo 'GRUB_GFXPAYLOAD_LINUX=keep' | sudo tee -a /etc/default/grub >/dev/null

    # Add plymouth hook
    if [ -f /etc/mkinitcpio.conf ] && ! grep -q plymouth /etc/mkinitcpio.conf; then
        if grep -q filesystems /etc/mkinitcpio.conf; then
            sudo sed -i "s/\(HOOKS=.*\)filesystems/\1plymouth filesystems/" /etc/mkinitcpio.conf || true
        else
            sudo sed -i "s/^\(HOOKS=.*\)\"$/\1 plymouth\"/" /etc/mkinitcpio.conf || true
        fi
        log_success "plymouth added to HOOKS."
    fi

    # Rebuild initramfs
    if command -v mkinitcpio >/dev/null 2>&1; then
        sudo mkinitcpio -P >/dev/null 2>&1 || log_warning "mkinitcpio -P failed"
    fi

    # Detect installed kernels
    KERNELS=($(ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||g'))
    if [[ ${#KERNELS[@]} -eq 0 ]]; then
        log_error "No kernels found in /boot."
        return 1
    fi

    # Determine main kernel and secondary kernels
    MAIN_KERNEL=""
    SECONDARY_KERNELS=()
    for k in "${KERNELS[@]}"; do
        [[ "$k" == "linux" ]] && MAIN_KERNEL="$k"
        [[ "$k" != "linux" && "$k" != "fallback" && "$k" != "rescue" ]] && SECONDARY_KERNELS+=("$k")
    done
    [[ -z "$MAIN_KERNEL" ]] && MAIN_KERNEL="${KERNELS[0]}"

    # Remove fallback/recovery kernels
    sudo rm -f /boot/initramfs-*-fallback.img /boot/vmlinuz-*-fallback 2>/dev/null || true

    # Regenerate grub.cfg
    sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || { log_error "grub-mkconfig failed"; return 1; }

    # Set default to main kernel (linux)
    DEFAULT_MENU=$(grep -Po "menuentry 'Arch Linux, with Linux linux[^']*'" /boot/grub/grub.cfg | head -n1 | sed "s/menuentry '\(.*\)'/\1/")
    if [[ -n "$DEFAULT_MENU" ]]; then
        sudo grub-set-default "$DEFAULT_MENU" >/dev/null 2>&1 || true
        log_success "GRUB default set to: linux"
    else
        sudo grub-set-default 0
        log_warning "Could not find menu entry for linux, defaulting to first entry."
    fi
}

# --- Windows helpers ---
detect_windows() {
    [ -d /boot/efi/EFI/Microsoft ] || [ -d /boot/EFI/Microsoft ] && return 0
    lsblk -f | grep -qi ntfs && return 0
    return 1
}

find_windows_efi_partition() {
    local partitions=($(lsblk -n -o NAME,TYPE | grep "part" | awk '{print "/dev/"$1}'))
    for partition in "${partitions[@]}"; do
        local temp_mount="/tmp/windows_efi_check"
        mkdir -p "$temp_mount"
        if sudo mount "$partition" "$temp_mount" 2>/dev/null; then
            [ -d "$temp_mount/EFI/Microsoft" ] && { sudo umount "$temp_mount"; sudo rm -rf "$temp_mount"; echo "$partition"; return 0; }
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
        [ -z "$windows_partition" ] && log_error "No Windows EFI found" && return 1
        local mount_point="/mnt/winefi"
        mkdir -p "$mount_point"
        sudo mount "$windows_partition" "$mount_point"
        sudo cp -R "$mount_point/EFI/Microsoft" /boot/EFI/
        sudo umount "$mount_point"
        sudo rm -rf "$mount_point"
    fi
    local entry="/boot/loader/entries/windows.conf"
    [ ! -f "$entry" ] && sudo bash -c "cat <<EOF > \"$entry\"
title   Windows
efi     /EFI/Microsoft/Boot/bootmgfw.efi
EOF"
}

set_localtime_for_windows() {
    sudo timedatectl set-local-rtc 1 --adjust-system-clock
}

# --- Main execution ---
if [ "$BOOTLOADER" = "grub" ]; then
    configure_grub
elif [ "$BOOTLOADER" = "systemd-boot" ]; then
    configure_boot
fi

if detect_windows && [ "$BOOTLOADER" = "systemd-boot" ]; then
    run_step "Installing ntfs-3g" sudo pacman -S --noconfirm ntfs-3g >/dev/null 2>&1
    add_windows_to_systemdboot
    set_localtime_for_windows
elif detect_windows && [ "$BOOTLOADER" = "grub" ]; then
    set_localtime_for_windows
fi
