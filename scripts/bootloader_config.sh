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
    step "Configuring GRUB for desired kernel order (Visual Reorder & Cleanup)"

    # Helper: ensure plymouth hook is in mkinitcpio HOOKS (backup first)
    ensure_plymouth_hook() {
        local mkconf="/etc/mkinitcpio.conf"
        if [ ! -f "$mkconf" ]; then
            log_warning "mkinitcpio.conf not found; skipping plymouth hook insertion."
            return 0
        fi
        sudo cp -a "$mkconf" "${mkconf}.bak.$(date +%s)" || true

        # If plymouth already present, nothing to do
        if grep -q '^[[:space:]]*HOOKS=.*plymouth' "$mkconf"; then
            log_info "plymouth already present in HOOKS."
            return 0
        fi

        # Try to insert 'plymouth' before 'filesystems' if present; otherwise append before closing quote
        if grep -q 'filesystems' "$mkconf"; then
            sudo sed -i "s/\(HOOKS=.*\)filesystems/\1plymouth filesystems/" "$mkconf"
            log_success "Inserted 'plymouth' into HOOKS before 'filesystems' in $mkconf."
        else
            # append 'plymouth' before the final quote of HOOKS line
            sudo sed -i "s/^\(HOOKS=.*\)\"$/\1 plymouth\"/" "$mkconf"
            log_success "Appended 'plymouth' into HOOKS in $mkconf."
        fi
    }

    # Helper: regenerate initramfs for all presets using mkinitcpio -P
    regenerate_initramfs_all() {
        if ! command -v mkinitcpio >/dev/null 2>&1; then
            log_warning "mkinitcpio not found; skipping initramfs regeneration."
            return 0
        fi

        log_info "Regenerating initramfs for all presets (mkinitcpio -P)..."
        if sudo mkinitcpio -P >/dev/null 2>&1; then
            log_success "Initramfs regenerated for all presets."
        else
            log_error "mkinitcpio -P failed; you may need to run it manually."
        fi
    }

    # 1) Update /etc/default/grub settings (robustly, backup first)
    log_info "Updating /etc/default/grub settings..."
    sudo cp -a /etc/default/grub /etc/default/grub.bak.$(date +%s) || true

    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub || sudo bash -c 'echo "GRUB_DEFAULT=0" >> /etc/default/grub'

    if grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=false/' /etc/default/grub
    else
        echo 'GRUB_SAVEDEFAULT=false' | sudo tee -a /etc/default/grub >/dev/null
    fi

    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub || sudo bash -c 'echo "GRUB_TIMEOUT=3" >> /etc/default/grub'

    # Ensure kernel cmdline matches what you used in systemd-boot
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

    log_success "Updated /etc/default/grub."

    # 2) Ensure plymouth hook present and rebuild initramfs for all kernels
    if command -v plymouthd >/dev/null 2>&1 || pacman -Q plymouth &>/dev/null; then
        ensure_plymouth_hook
        regenerate_initramfs_all
    else
        log_warning "plymouth not installed; skipping plymouth hooks and initramfs adjustments."
    fi

    # 3) Remove fallback initramfs images from /boot
    log_info "Removing fallback initramfs images from /boot..."
    sudo rm -f /boot/initramfs-*-fallback.img 2>/dev/null || true
    log_success "Fallback initramfs images removed."

    # 4) Generate initial grub.cfg so canonical entries exist
    log_info "Generating initial GRUB configuration (grub-mkconfig)..."
    if sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
        log_success "Initial GRUB configuration generated."
    else
        log_error "grub-mkconfig failed; ensure grub is installed and run 'sudo grub-mkconfig -o /boot/grub/grub.cfg' manually."
    fi

    # 5) Post-process /boot/grub/grub.cfg: remove broken entries, deduplicate, reorder
    log_info "Post-processing /boot/grub/grub.cfg to remove broken entries, deduplicate and reorder..."

    # create a Python script that validates menuentries by checking referenced kernel/initrd file existence
    sudo bash -c "cat > /tmp/reorder_and_filter_grub.py <<'PY'
#!/usr/bin/env python3
import re,os,sys

GRUB_CFG='/boot/grub/grub.cfg'
TMP='/tmp/grub_filtered_reordered.cfg'

def readf(p):
    with open(p,'r',encoding='utf-8',errors='ignore') as f:
        return f.read()

def writef(p,txt):
    with open(p,'w',encoding='utf-8',errors='ignore') as f:
        f.write(txt)

if not os.path.exists(GRUB_CFG):
    print('ERROR: grub.cfg not found',file=sys.stderr); sys.exit(1)

content = readf(GRUB_CFG)

start_marker = '### BEGIN /etc/grub.d/10_linux ###'
end_marker = '### END /etc/grub.d/10_linux ###'

if start_marker in content and end_marker in content:
    pre,rest = content.split(start_marker,1)
    mid,post = rest.split(end_marker,1)
    mid = start_marker + mid + end_marker
else:
    pre=''; mid=content; post=''

# Extract all menuentry/submenu blocks
pattern = re.compile(r'((?:menuentry|submenu)[\\s\\S]*?\\n\\})', re.MULTILINE)
blocks = pattern.findall(mid)

def title_of(b):
    m = re.search(r'(?:menuentry|submenu)\\s+\\'([^\\']+)\\'', b)
    return m.group(1).strip() if m else ''

def referenced_files_exist(block):
    # Look for linux/linuxefi lines and initrd lines.
    # Accept both relative (/vmlinuz-...) and absolute (/boot/...) references.
    # If a linux line has a path starting with /boot, use as-is; otherwise prepend /boot when necessary.
    found_any_kernel=False
    all_exist=True

    # linux lines: linux, linux16, linuxefi
    for m in re.finditer(r'^[ \\t]*(linux(?:efi|16)?)[ \\t]+([^\\n\\s]+)', block, re.MULTILINE):
        found_any_kernel=True
        kpath = m.group(2)
        if not kpath.startswith('/'):
            # common in grub.cfg: /vmlinuz-linux (already absolute), but just in case make safe
            kcheck = os.path.join('/boot', kpath.lstrip('/'))
        else:
            kcheck = kpath
            # if kernel path points to /vmlinuz-* (rooted at /), ensure /boot prefix
            if os.path.exists(os.path.join('/boot', os.path.basename(kpath))) and not os.path.exists(kpath):
                kcheck = os.path.join('/boot', os.path.basename(kpath))
        if not os.path.exists(kcheck):
            # try basename in /boot
            if not os.path.exists(os.path.join('/boot', os.path.basename(kpath))):
                all_exist=False
    # initrd lines
    for m in re.finditer(r'^[ \\t]*initrd[ \\t]+([^\\n\\s]+)', block, re.MULTILINE):
        ipath = m.group(1)
        if not ipath.startswith('/'):
            icheck = os.path.join('/boot', ipath.lstrip('/'))
        else:
            icheck = ipath
            if os.path.exists(os.path.join('/boot', os.path.basename(ipath))) and not os.path.exists(ipath):
                icheck = os.path.join('/boot', os.path.basename(ipath))
        if not os.path.exists(icheck):
            # sometimes initrd in grub.cfg uses relative path; try basename in /boot
            if not os.path.exists(os.path.join('/boot', os.path.basename(ipath))):
                all_exist=False

    # If there are no linux lines found, treat as non-kernel entry (UEFI/Windows/other) and keep it
    if not found_any_kernel:
        return True
    return all_exist

# Filter out blocks that reference missing files or obvious fallback/recovery titles
valid_blocks = []
seen_titles = set()
for b in blocks:
    t = title_of(b)
    tl = t.lower()
    # remove fallback/recovery entries explicitly
    if 'fallback' in tl or 'recovery' in tl or 'rescue' in tl:
        # skip
        continue
    if not referenced_files_exist(b):
        # skip broken kernel entry
        continue
    # deduplicate by title (first occurrence kept)
    if t in seen_titles:
        continue
    seen_titles.add(t)
    valid_blocks.append((t,b))

# Categorize and reorder: primary (non-lts) kernel first, then lts, then other kernels, snapshots, windows, uefi, others
primary=None
lts=None
others=[]
snapshots=[]
windows=None
uefi=None
misc=[]

for t,b in valid_blocks:
    tl = t.lower()
    if 'with linux linux' in t or ('with linux' in t and 'lts' not in tl):
        if primary is None:
            primary=(t,b)
        else:
            others.append((t,b))
    elif 'linux-lts' in t or 'lts' in tl:
        if lts is None:
            lts=(t,b)
        else:
            others.append((t,b))
    elif 'snapshot' in tl or 'snapshots' in tl:
        snapshots.append((t,b))
    elif 'windows' in tl or 'windows boot manager' in tl:
        if windows is None:
            windows=(t,b)
        else:
            others.append((t,b))
    elif 'uefi firmware' in tl:
        if uefi is None:
            uefi=(t,b)
        else:
            others.append((t,b))
    else:
        misc.append((t,b))

# Reconstruct mid section content: keep original header of mid (everything before first menuentry) if present
# Find first menuentry index to preserve top non-10_linux lines
first_menu_match = re.search(r'(?:menuentry|submenu)', mid)
mid_prefix = ''
if first_menu_match:
    mid_prefix = mid[:first_menu_match.start()]

new_mid = mid_prefix
if primary:
    new_mid += primary[1]
if lts and (not primary or lts[0] != primary[0]):
    new_mid += lts[1]
for t,b in others:
    new_mid += b
for t,b in snapshots:
    new_mid += b
if windows:
    new_mid += windows[1]
if uefi:
    new_mid += uefi[1]
for t,b in misc:
    new_mid += b

out = pre + new_mid + post

writef(TMP,out)
# atomic move
os.replace(TMP, GRUB_CFG)
print('OK',file=sys.stderr)
PY"

    # execute the python filter/reorder
    if sudo python3 /tmp/reorder_and_filter_grub.py >/dev/null 2>&1; then
        log_success "Filtered out broken/non-functional GRUB entries and reordered menu successfully."
    else
        log_error "Filtering/reordering script failed. Inspect /tmp/reorder_and_filter_grub.py and /boot/grub/grub.cfg."
    fi
    sudo rm -f /tmp/reorder_and_filter_grub.py 2>/dev/null || true

    # 6) Final shell-based conservative cleanup (catch any stray fallback mentions)
    log_info "Performing final conservative shell cleanup..."
    sudo sed -i '/fallback/d' /boot/grub/grub.cfg || true
    sudo sed -i '/recovery/d' /boot/grub/grub.cfg || true
    sudo sed -i '/initramfs.*-fallback.img/d' /boot/grub/grub.cfg || true
    log_success "Final shell cleanup complete."

    # 7) If grub-btrfs present, attempt to ensure snapshot entries are present (regenerate)
    if pacman -Q grub-btrfs &>/dev/null; then
        log_info "Attempting grub-btrfs snapshot regeneration..."
        if command -v grub-btrfs-mkconfig >/dev/null 2>&1; then
            sudo grub-btrfs-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
        else
            sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
        fi
        log_success "grub-btrfs regeneration attempted."
    fi

    log_success "GRUB configuration complete: broken entries removed, primary kernel should appear first."
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

# This function is specifically for adding Windows to GRUB, and should run AFTER grub-mkconfig generates initial config
# but BEFORE the Python script reorders it, so the Python script can categorize the Windows entry.
add_windows_to_grub_logic() {
    step "Adding Windows to GRUB menu (if detected)"
    sudo pacman -S --noconfirm os-prober >/dev/null 2>&1 || log_warning "Failed to install os-prober"

    # Ensure GRUB_DISABLE_OS_PROBER is not set to true
    if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    else
        echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null
    fi
    # Regenerate GRUB config to pick up os-prober's work
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_success "Windows entry added to GRUB (if detected by os-prober). This entry will be reordered shortly."
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
        add_windows_to_grub_logic # Call the function
    elif [ "$BOOTLOADER" = "systemd-boot" ]; then
        add_windows_to_systemdboot
    fi
    set_localtime_for_windows
fi
