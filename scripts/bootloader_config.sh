#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/../configs" # Assuming configs are in archinstaller/configs
source "$SCRIPT_DIR/common.sh" # Source common functions like detect_bootloader and is_btrfs_system

# --- systemd-boot handling (left as you originally had) ---
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

# --- fastfetch config setup (unchanged) ---
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

# --- Bootloader and Btrfs detection variables (using centralized functions) ---
BOOTLOADER=$(detect_bootloader)
IS_BTRFS=$(is_btrfs_system && echo "true" || echo "false") # Store as "true" or "false" for easier scripting

# --- Helper: backup paths to timestamped folder ---
_backup_paths() {
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local dest="/root/grub_backup_${ts}"
    sudo mkdir -p "$dest"
    # backup common items if present
    [ -f /etc/default/grub ] && sudo cp -a /etc/default/grub "$dest/" || true
    [ -f /etc/mkinitcpio.conf ] && sudo cp -a /etc/mkinitcpio.conf "$dest/" || true
    sudo cp -a /etc/grub.d "$dest/" 2>/dev/null || true
    [ -f /boot/grub/grub.cfg ] && sudo cp -a /boot/grub/grub.cfg "$dest/" || true
    # return backup dir
    echo "$dest"
}

# --- GRUB configuration (full robust implementation) ---
configure_grub() {
    step "Configuring GRUB: standard 'linux' kernel first, then 'linux-lts', cleaning stale entries"

    log_info "Backing up current grub/mkinitcpio configs..."
    BACKUP_DIR=$(_backup_paths)
    log_info "Backups stored at: $BACKUP_DIR"

    # Normalize /etc/default/grub (make conservative replacements, append missing ones)
    log_info "Updating /etc/default/grub..."
    sudo cp -a /etc/default/grub "/etc/default/grub.bak.$(date +%s)" || true

    # Set primary options
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub || sudo bash -c 'echo "GRUB_DEFAULT=0" >> /etc/default/grub'
    if grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=false/' /etc/default/grub
    else
        echo 'GRUB_SAVEDEFAULT=false' | sudo tee -a /etc/default/grub >/dev/null
    fi
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub || sudo bash -c 'echo "GRUB_TIMEOUT=3" >> /etc/default/grub'

    # sync kernel cmdline with your systemd-boot settings
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

    # If grub-btrfs present, prefer showing snapshots as root entries
    if pacman -Q grub-btrfs &>/dev/null; then
        if grep -q '^GRUB_BTRFS_SUBMENU=' /etc/default/grub; then
            sudo sed -i 's/^GRUB_BTRFS_SUBMENU=.*/GRUB_BTRFS_SUBMENU=n/' /etc/default/grub
        else
            echo 'GRUB_BTRFS_SUBMENU=n' | sudo tee -a /etc/default/grub >/dev/null
        fi
        log_info "grub-btrfs present: snapshots will be shown as separate GRUB entries."
    fi

    log_success "Updated /etc/default/grub."

    # Ensure plymouth is in mkinitcpio HOOKS — backup already done
    if [ -f /etc/mkinitcpio.conf ]; then
        if ! grep -q 'plymouth' /etc/mkinitcpio.conf; then
            log_info "Inserting 'plymouth' into HOOKS of /etc/mkinitcpio.conf"
            # try to insert before filesystems if present, fallback to appending
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

    # Rebuild initramfs for all kernels (mkinitcpio -P)
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

    # Remove fallback initramfs images to avoid stale references
    log_info "Removing fallback initramfs images from /boot..."
    sudo rm -f /boot/initramfs-*-fallback.img 2>/dev/null || true
    log_success "Fallback initramfs images removed."

    # Backup and remove user-custom grub fragments that can cause different experiences
    # (safe: everything is backed up to $BACKUP_DIR)
    log_info "Checking for custom grub fragments to normalize experience..."
    if [ -f /boot/grub/custom.cfg ]; then
        sudo cp -a /boot/grub/custom.cfg "$BACKUP_DIR/" || true
        sudo rm -f /boot/grub/custom.cfg || true
        log_info "Backed up and removed /boot/grub/custom.cfg"
    fi
    if [ -f /etc/grub.d/40_custom ]; then
        sudo cp -a /etc/grub.d/40_custom "$BACKUP_DIR/" || true
        sudo rm -f /etc/grub.d/40_custom || true
        log_info "Backed up and removed /etc/grub.d/40_custom"
    fi
    if [ -f /etc/grub.d/41_custom ]; then
        sudo cp -a /etc/grub.d/41_custom "$BACKUP_DIR/" || true
        sudo rm -f /etc/grub.d/41_custom || true
        log_info "Backed up and removed /etc/grub.d/41_custom"
    fi

    # Handle Windows detection BEFORE generating grub.cfg
    if detect_windows; then
        log_info "Windows detected - enabling os-prober before grub-mkconfig..."
        sudo pacman -S --noconfirm os-prober >/dev/null 2>&1 || log_warning "Failed to install os-prober"
        if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
            sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
        else
            echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null
        fi
    fi

    # Generate initial grub.cfg using distro scripts (ensures canonical entries)
    log_info "Generating GRUB config (grub-mkconfig -o /boot/grub/grub.cfg)..."
    if sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
        log_success "Initial grub.cfg generated."
    else
        log_error "grub-mkconfig failed. Aborting post-processing."
        return 1
    fi

    # Python post-processing: remove broken kernel entries, dedupe, reorder
    log_info "Running post-processing to remove broken entries, deduplicate, and reorder GRUB menu..."
    log_info "Target order: 1st=standard 'linux', 2nd='linux-lts', then others, then snapshots/Windows/UEFI"

    sudo bash -c "cat > /tmp/reorder_and_filter_grub.py <<'PY'
#!/usr/bin/env python3
import os, re, sys

GRUB_CFG = '/boot/grub/grub.cfg'
TMP_OUT = '/tmp/grub_cleaned.cfg'

def read_file(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return f.read()

def write_file(path, content):
    with open(path, 'w', encoding='utf-8', errors='replace') as f:
        f.write(content)

def extract_blocks(content):
    \"\"\"
    Return a list where each element is either a string (non-menuentry text)
    or a block starting with menuentry/submenu and ending with the matching closing brace.
    \"\"\"
    blocks = []
    i = 0
    n = len(content)
    menu_re = re.compile(r'^\s*(menuentry|submenu)\b', re.MULTILINE)
    last = 0
    for m in menu_re.finditer(content):
        start = m.start()
        if start > last:
            blocks.append(content[last:start])
        # find matching closing brace for this block
        brace_count = 0
        j = start
        while j < n:
            if content[j] == '{':
                brace_count += 1
            elif content[j] == '}':
                brace_count -= 1
                if brace_count == 0:
                    end = j + 1
                    blocks.append(content[start:end])
                    last = end
                    break
            j += 1
        else:
            blocks.append(content[start:])
            last = n
            break
    if last < n:
        blocks.append(content[last:])
    return blocks

def get_title(block):
    m = re.search(r\"(?:menuentry|submenu)\s+'([^']+)'\", block)
    return m.group(1).strip() if m else ''

def block_has_kernel_refs(block):
    linux_re = re.compile(r'^\s*(?:linux(?:efi|16)?)[ \t]+([^\n\s]+)', re.MULTILINE)
    initrd_re = re.compile(r'^\s*initrd[ \t]+([^\n\s]+)', re.MULTILINE)
    linux_matches = linux_re.findall(block)
    initrd_matches = initrd_re.findall(block)
    return bool(linux_matches or initrd_matches), linux_matches, initrd_matches

def path_exists_try(path):
    if os.path.isabs(path) and os.path.exists(path):
        return True
    b = os.path.basename(path)
    if os.path.exists(os.path.join('/boot', b)):
        return True
    if os.path.exists(os.path.join('/boot', path)):
        return True
    return False

def kernel_refs_valid(linux_matches, initrd_matches):
    linux_ok = True
    initrd_ok = True
    if linux_matches:
        linux_ok = any(path_exists_try(p) for p in linux_matches)
    if initrd_matches:
        initrd_ok = any(path_exists_try(p) for p in initrd_matches)
    if linux_matches and initrd_matches:
        return linux_ok and initrd_ok
    if linux_matches:
        return linux_ok
    return True

def is_snapshot_title(title):
    return 'snapshot' in title.lower() or 'snapshots' in title.lower()

def is_windows_title(title):
    return 'windows' in title.lower()

def is_uefi_title(title):
    return 'uefi' in title.lower() or 'firmware' in title.lower()

def is_lts_title(title):
    return 'lts' in title.lower() or 'linux-lts' in title.lower()

def is_standard_linux_title(title):
    # The standard Arch kernel entry: \"Arch Linux, with Linux linux\"
    # Must have 'linux' but NOT 'lts', 'zen', 'hardened', 'rt'
    tl = title.lower()
    if 'arch linux' not in tl:
        return False
    if 'lts' in tl or 'zen' in tl or 'hardened' in tl or 'rt' in tl:
        return False
    # Check for pattern like \"with Linux linux\" (not \"with Linux linux-something\")
    if 'with linux linux' in tl:
        # Make sure it's exactly \"linux\" and not \"linux-lts\" or similar
        # Pattern: \"with Linux linux\" followed by end or space/comma
        if re.search(r'with\s+linux\s+linux\s*(?:,|$)', tl):
            return True
    return False

try:
    orig = read_file(GRUB_CFG)
    blocks = extract_blocks(orig)

    kept_nonblocks = []
    standard_kernel = []  # Standard 'linux' kernel - FIRST priority
    lts_kernel = []       # LTS kernel - SECOND priority
    other_kernels = []    # Other kernels (zen, hardened, etc)
    snapshot_blocks = []
    windows_blocks = []
    uefi_blocks = []
    misc_blocks = []

    seen_titles = set()

    for blk in blocks:
        # Non-menu text (configuration, comments, etc)
        if not blk.strip().startswith('menuentry') and not blk.strip().startswith('submenu'):
            kept_nonblocks.append(blk)
            continue

        title = get_title(blk)
        if not title:
            misc_blocks.append(('UNKNOWN', blk))
            continue

        # Skip fallback/recovery/rescue entries
        tl = title.lower()
        if 'fallback' in tl or 'recovery' in tl or 'rescue' in tl:
            continue

        has_kernel, linux_matches, initrd_matches = block_has_kernel_refs(blk)
        if has_kernel:
            if not kernel_refs_valid(linux_matches, initrd_matches):
                # Broken kernel entry -> skip
                continue

        # Deduplicate by title
        if title in seen_titles:
            continue
        seen_titles.add(title)

        # Categorize entries
        if is_snapshot_title(title):
            snapshot_blocks.append((title, blk))
        elif is_windows_title(title):
            windows_blocks.append((title, blk))
        elif is_uefi_title(title):
            uefi_blocks.append((title, blk))
        elif is_standard_linux_title(title):
            # CRITICAL: This is the standard 'linux' kernel - highest priority!
            standard_kernel.append((title, blk))
        elif is_lts_title(title):
            # This is LTS - second priority
            lts_kernel.append((title, blk))
        elif has_kernel:
            # Other kernel variants (zen, hardened, rt, etc)
            other_kernels.append((title, blk))
        else:
            misc_blocks.append((title, blk))

    # Build new content in correct order
    new_parts = []

    # 1. Non-block header (GRUB settings, load statements, etc)
    new_parts.extend(kept_nonblocks)

    # 2. STANDARD 'linux' kernel FIRST (not LTS!)
    for t, b in standard_kernel:
        new_parts.append(b)

    # 3. LTS kernel SECOND
    for t, b in lts_kernel:
        new_parts.append(b)

    # 4. Other kernel variants
    for t, b in other_kernels:
        new_parts.append(b)

    # 5. Snapshots
    for t, b in snapshot_blocks:
        new_parts.append(b)

    # 6. Windows
    for t, b in windows_blocks:
        new_parts.append(b)

    # 7. UEFI/Firmware
    for t, b in uefi_blocks:
        new_parts.append(b)

    # 8. Misc
    for t, b in misc_blocks:
        new_parts.append(b)

    final = \"\".join(new_parts)
    write_file(TMP_OUT, final)
    os.replace(TMP_OUT, GRUB_CFG)

    print('[+] grub.cfg cleaned and reordered')
    print(f'    Standard kernel entries: {len(standard_kernel)}')
    print(f'    LTS kernel entries: {len(lts_kernel)}')
    print(f'    Other kernel entries: {len(other_kernels)}')
    print(f'    Snapshot entries: {len(snapshot_blocks)}')
    print(f'    Windows entries: {len(windows_blocks)}')
    sys.exit(0)

except Exception as e:
    print('[!] error in grub post-processing:', e, file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
PY"

    # run the python post-processor with sudo
    if sudo python3 /tmp/reorder_and_filter_grub.py 2>&1 | tee /tmp/reorder_and_filter_grub.log; then
        log_success "GRUB post-processing completed successfully."
        log_success "Menu order: 1st=standard 'linux', 2nd='linux-lts', then others"
    else
        log_error "GRUB post-processing failed. Check /tmp/reorder_and_filter_grub.log"
        log_error "Backups available at: $BACKUP_DIR"
        cat /tmp/reorder_and_filter_grub.log
    fi

    # cleanup the python script
    sudo rm -f /tmp/reorder_and_filter_grub.py 2>/dev/null || true

    # Conservative sed-based cleanup for leftover patterns
    log_info "Final conservative cleanup of grub.cfg..."
    sudo sed -i '/fallback/d;/recovery/d;/initramfs-.*-fallback.img/d' /boot/grub/grub.cfg || true

    # IMPORTANT: Do NOT regenerate grub.cfg again - it would undo our reordering!
    # The Python script has already placed everything in the correct order.

    log_success "GRUB configuration finished."
    log_success "Standard 'linux' kernel is now FIRST in the menu (position 0)"
    log_success "'linux-lts' kernel is SECOND in the menu (position 1)"
    log_success "Backups kept at: $BACKUP_DIR"
    log_success "Please reboot to validate the changes."
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

if [ "$BOOTLOADER" = "grub" ]; then
    configure_grub
elif [ "$BOOTLOADER" = "systemd-boot" ]; then
    log_info "Detected systemd-boot. systemd-boot-specific configuration already applied."
else
    log_warning "Unknown bootloader ($BOOTLOADER). No bootloader-specific actions taken."
fi

# Windows dual-boot configuration (systemd-boot only, GRUB handled inside configure_grub)
if detect_windows && [ "$BOOTLOADER" = "systemd-boot" ]; then
    log_info "Windows installation detected with systemd-boot. Configuring dual-boot..."
    run_step "Installing ntfs-3g for Windows partition access" sudo pacman -S --noconfirm ntfs-3g >/dev/null 2>&1
    add_windows_to_systemdboot
    set_localtime_for_windows
elif detect_windows && [ "$BOOTLOADER" = "grub" ]; then
    log_info "Windows dual-boot already configured inside GRUB setup."
    set_localtime_for_windows
fi
