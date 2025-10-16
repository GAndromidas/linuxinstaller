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
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub || echo 'GRUB_TIMEOUT=3' | sudo tee -a /etc/default/grub >/dev/null
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub || echo 'GRUB_DEFAULT=0' | sudo tee -a /etc/default/grub >/dev/null

    # Remember last selected kernel
    sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub || \
        echo 'GRUB_SAVEDEFAULT=true' | sudo tee -a /etc/default/grub >/dev/null

    # Standard kernel command line
    sudo sed -i 's@^GRUB_CMDLINE_LINUX_DEFAULT=.*@GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"@' /etc/default/grub || \
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"' | sudo tee -a /etc/default/grub >/dev/null

    grep -q '^GRUB_DISABLE_SUBMENU=' /etc/default/grub || echo 'GRUB_DISABLE_SUBMENU=y' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_GFXMODE=' /etc/default/grub || echo 'GRUB_GFXMODE=auto' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub || echo 'GRUB_GFXPAYLOAD_LINUX=keep' | sudo tee -a /etc/default/grub >/dev/null

    # Ensure plymouth in mkinitcpio HOOKS
    if [ -f /etc/mkinitcpio.conf ] && ! grep -q plymouth /etc/mkinitcpio.conf; then
        if grep -q filesystems /etc/mkinitcpio.conf; then
            sudo sed -i "s/\(HOOKS=.*\)filesystems/\1plymouth filesystems/" /etc/mkinitcpio.conf || true
        else
            sudo sed -i "s/^\(HOOKS=.*\)\"$/\1 plymouth\"/" /etc/mkinitcpio.conf || true
        fi
        log_success "plymouth added to HOOKS (backup exists)."
    fi

    # Rebuild initramfs
    if command -v mkinitcpio >/dev/null 2>&1; then
        log_info "Regenerating initramfs for all presets..."
        sudo mkinitcpio -P >/dev/null 2>&1 || log_warning "mkinitcpio -P failed"
    fi

    # --- Detect installed kernels ---
    KERNELS=($(ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||g'))
    if [[ ${#KERNELS[@]} -eq 0 ]]; then
        log_error "No kernels found in /boot. Aborting GRUB configuration."
        return 1
    fi
    log_info "Detected kernels: ${KERNELS[*]}"

    # --- Build ordered list: linux > linux-lts > others ---
    ORDERED_KERNELS=()
    [[ " ${KERNELS[*]} " == *" linux "* ]] && ORDERED_KERNELS+=("linux")
    [[ " ${KERNELS[*]} " == *" linux-lts "* ]] && ORDERED_KERNELS+=("linux-lts")
    for k in "${KERNELS[@]}"; do
        [[ "$k" != "linux" && "$k" != "linux-lts" ]] && ORDERED_KERNELS+=("$k")
    done
    log_info "Kernel boot order: ${ORDERED_KERNELS[*]}"

    # --- Remove fallback initramfs images ---
    sudo rm -f /boot/initramfs-*-fallback.img 2>/dev/null || true

    # --- Remove fallback/recovery menu entries from previous grub.cfg ---
    sudo sed -i '/fallback/d;/recovery/d;/rescue/d' /boot/grub/grub.cfg || true

    # --- Generate grub.cfg ---
    log_info "Generating grub.cfg..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || { log_error "grub-mkconfig failed"; return 1; }

    # --- Set default kernel explicitly ---
    DEFAULT_KERNEL="${ORDERED_KERNELS[0]}"
    MENU_ENTRY=$(grep -Po "menuentry 'Arch Linux, with Linux ${DEFAULT_KERNEL}[^']*'" /boot/grub/grub.cfg | head -n1 | sed "s/menuentry '\(.*\)'/\1/")
    if [[ -n "$MENU_ENTRY" ]]; then
        sudo grub-set-default "Advanced options for Arch Linux>${MENU_ENTRY}" >/dev/null 2>&1 || true
        log_success "GRUB default set to: ${DEFAULT_KERNEL}"
    else
        log_warning "Could not find exact menu entry for ${DEFAULT_KERNEL}. Using first menuentry as fallback."
        sudo grub-set-default 0
    fi

    log_success "GRUB configuration complete. Default kernel: ${DEFAULT_KERNEL}"
    log_success "Backups stored at: ${BACKUP_DIR}"
}

# --- Windows Dual-Boot Detection ---
detect_windows() {
    if [ -d /boot/efi/EFI/Microsoft ] || [ -d /boot/EFI/Microsoft ]; then
        return 0
    fi
    if lsblk -f | grep -qi ntfs; then
