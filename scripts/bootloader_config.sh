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

    # 1. Configure /etc/default/grub
    log_info "Updating /etc/default/grub settings..."
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
    # Correct GRUB_SAVEDEFAULT typo and ensure it's set to false
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

    # Remove all fallback initramfs images from /boot
    log_info "Removing fallback initramfs images from /boot... (This helps clean up grub.cfg as well)"
    sudo rm -f /boot/initramfs-*-fallback.img 2>/dev/null || true
    log_success "Fallback initramfs images removed."

    # 2. Generate grub.cfg to ensure all standard entries are present
    log_info "Generating initial GRUB configuration... This ensures all working kernel entries are created by system scripts."
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_success "Initial GRUB configuration generated. Now reordering entries..."

    # 3. Post-process grub.cfg with a Python script to reorder and clean
    log_info "Post-processing /boot/grub/grub.cfg to reorder kernels and remove redundant entries..."

    # Create a Python script dynamically to reorder GRUB entries
    sudo bash -c "cat << 'PYTHON_SCRIPT_EOF' > /tmp/reorder_grub_entries.py
import re
import sys
import os

GRUB_CFG_PATH = '/boot/grub/grub.cfg'
TEMP_GRUB_CFG_PATH = '/tmp/grub_reordered_temp.cfg'

def log_message(message):
    print(f\"[GRUB_REORDER] {message}\", file=sys.stderr)

def parse_grub_cfg_into_parts(content):
    parts = []
    current_block_lines = []
    brace_depth = 0
    in_block = False # True if we are inside a menuentry/submenu block

    for line in content.splitlines(keepends=True): # keepends=True preserves newlines
        stripped_line = line.strip()

        if not in_block:
            # Look for the start of a new menuentry or submenu block
            if stripped_line.startswith("menuentry ") or stripped_line.startswith("submenu "):
                if current_block_lines: # If there were non-block lines accumulated, add them as a part
                    parts.append("".join(current_block_lines))
                    current_block_lines = []

                in_block = True
                current_block_lines.append(line)
                brace_depth = stripped_line.count('{') - stripped_line.count('}')
            else:
                # Accumulate non-block lines
                current_block_lines.append(line)
        else: # We are inside a block
            current_block_lines.append(line)
            brace_depth += stripped_line.count('{')
            brace_depth -= stripped_line.count('}')

            if brace_depth == 0 and stripped_line == '}': # End of current block
                parts.append("".join(current_block_lines))
                current_block_lines = []
                in_block = False

    # Add any remaining accumulated lines as a final part
    if current_block_lines:
        parts.append("".join(current_block_lines))

    return parts

def get_block_type_and_title(block_content):
    block_type_match = re.match(r"^(menuentry|submenu)", block_content.strip())
    block_type = block_type_match.group(1) if block_type_match else None
    title_match = re.search(r"^(?:menuentry|submenu)\s+'([^']+)'", block_content, re.MULTILINE)
    block_title = title_match.group(1) if title_match else "UNKNOWN_TITLE"
    return block_type, block_title

def reorder_grub_cfg():
    if not os.path.exists(GRUB_CFG_PATH):
        log_message(f"Error: GRUB config file not found at {GRUB_CFG_PATH}")
        return 1

    try:
        with open(GRUB_CFG_PATH, 'r') as f:
            content = f.read()

        all_parts = parse_grub_cfg_into_parts(content)

        # Categorized blocks
        primary_linux_entry = None
        lts_linux_entry = None
        snapshot_entries = []
        windows_entry = None
        uefi_entry = None
        other_arch_kernels_entries = [] # For zen, hardened etc.
        miscellaneous_blocks = [] # Anything else not specifically ordered

        pre_10_linux_content = []
        post_10_linux_content = []
        main_10_linux_section_blocks = []

        in_10_linux_section = False
        start_marker = "### BEGIN /etc/grub.d/10_linux ###"
        end_marker = "### END /etc/grub.d/10_linux ###"

        # First pass: Separate content into pre-10_linux, 10_linux section, and post-10_linux
        for part in all_parts:
            if start_marker in part:
                in_10_linux_section = True
                pre_10_linux_content.append(part)
                continue
            elif end_marker in part:
                in_10_linux_section = False
                post_10_linux_content.append(part)
                continue

            if in_10_linux_section:
                main_10_linux_section_blocks.append(part)
            else:
                pre_10_linux_content.append(part) # Also captures content before BEGIN marker


        # Second pass: Categorize blocks within the main_10_linux_section_blocks
        for block_or_line in main_10_linux_section_blocks:
            stripped_line = block_or_line.strip()
            if stripped_line.startswith("menuentry ") or stripped_line.startswith("submenu "):
                block_type, block_title = get_block_type_and_title(block_or_line)

                if "fallback" in block_title.lower() or "Advanced options for Arch Linux" in block_title:
                    log_message(f"Filtering out fallback/advanced entry: '{block_title}'")
                elif block_title == "Arch Linux, with Linux linux":
                    if primary_linux_entry is None: primary_linux_entry = block_or_line
                    else: log_message(f"Filtering out duplicate primary Linux entry: '{block_title}'")
                elif block_title == "Arch Linux, with Linux linux-lts":
                    if lts_linux_entry is None: lts_linux_entry = block_or_line
                    else: log_message(f"Filtering out duplicate LTS entry: '{block_title}'")
                elif "Arch Linux snapshots" in block_title:
                    snapshot_entries.append(block_or_line)
                elif "Windows Boot Manager" in block_title or re.search(r"Windows (?:10|11)", block_title):
                    if windows_entry is None: windows_entry = block_or_line
                    else: log_message(f"Filtering out duplicate Windows entry: '{block_title}'")
                elif block_title == "UEFI Firmware Settings":
                    if uefi_entry is None: uefi_entry = block_or_line
                    else: log_message(f"Filtering out duplicate UEFI entry: '{block_title}'")
                elif "Arch Linux" in block_title and ("linux-zen" in block_title or "linux-hardened" in block_title):
                    other_arch_kernels_entries.append(block_or_line)
                else:
                    miscellaneous_blocks.append(block_or_line)
                    log_message(f"Categorized miscellaneous entry: '{block_title}'")
            else:
                # Non-block lines within the 10_linux section are treated as miscellaneous too
                miscellaneous_blocks.append(block_or_line)

        # Reconstruct the main 10_linux section content in desired order
        reordered_main_section_content_parts = []
        if primary_linux_entry: reordered_main_section_content_parts.append(primary_linux_entry)
        if lts_linux_entry: reordered_main_section_content_parts.append(lts_linux_entry)
        reordered_main_section_content_parts.extend(other_arch_kernels_entries)
        reordered_main_section_content_parts.extend(snapshot_entries)
        if windows_entry: reordered_main_section_content_parts.append(windows_entry)
        if uefi_entry: reordered_main_section_content_parts.append(uefi_entry)
        reordered_main_section_content_parts.extend(miscellaneous_blocks) # Add any remaining non-categorized content

        final_content = "".join(pre_10_linux_content) + "".join(reordered_main_section_content_parts) + "".join(post_10_linux_content)

        with open(TEMP_GRUB_CFG_PATH, 'w') as f:
            f.write(final_content)

        sudo_mv_cmd = f"sudo mv {TEMP_GRUB_CFG_PATH} {GRUB_CFG_PATH}"
        log_message(f"Executing: {sudo_mv_cmd}")
        os.system(sudo_mv_cmd)

        log_message("GRUB menu reordered and cleaned successfully.")
        return 0

    except Exception as e:
        log_message(f"Critical Error during GRUB reordering: {e}")
        return 1

if __name__ == '__main__':
    sys.exit(reorder_grub_cfg())
PYTHON_SCRIPT_EOF"

    # Execute the Python script
    if sudo python3 /tmp/reorder_grub_entries.py; then
        log_success "GRUB menu entries reordered and cleaned successfully."
    else
        log_error "Failed to reorder GRUB menu with Python script. You may need to manually inspect /boot/grub/grub.cfg and verify Python3 is installed. Check logs for details."
    fi

    # Clean up the temporary Python script
    sudo rm -f /tmp/reorder_grub_entries.py 2>/dev/null || true
    log_success "Temporary Python script cleaned up."

    # Final shell-based cleanup as a safeguard (in case Python misses something or fails.)
    log_info "Performing final shell-based cleanup for any remaining fallback/advanced entries... (as a safeguard)"
    # Delete the entire 'Advanced options' submenu block using a robust sed pattern
    sudo sed -i '/^submenu 'Advanced options for Arch Linux'/{:a;N;/^}/!ba;d}' /boot/grub/grub.cfg || true
    # Delete any stray fallback menuentries (e.g., if generated outside 10_linux section or by a different script)
    sudo sed -i '/^menuentry '[^']*(fallback|recovery|debug).*'/{:a;N;/^}/!ba;d}' /boot/grub/grub.cfg || true
    # Remove any remaining lines specifically mentioning fallback images or titles
    sudo sed -i '/initrd \/boot\/initramfs-.*-fallback.img/d/' /boot/grub/grub.cfg || true
    sudo sed -i '/title .*fallback/d/' /boot/grub/grub.cfg || true
    log_success "Final shell cleanup for GRUB entries completed."

    log_success "GRUB configuration complete: 'Arch Linux, with Linux linux' should now appear first and be default."
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
