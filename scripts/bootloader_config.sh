#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
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
    # Set kernel parameters for Plymouth and quiet boot
    sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 plymouth.ignore-serial-consoles"/' /etc/default/grub

    # Set default entry to saved and enable save default
    if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
    else
        echo 'GRUB_DEFAULT=saved' | sudo tee -a /etc/default/grub >/dev/null
    fi
    if grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub
    else
        echo 'GRUB_SAVEDEFAULT=true' | sudo tee -a /etc/default/grub >/dev/null
    fi

    # Set timeout to 3 seconds
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

    # Set console mode (gfxmode)
    grep -q '^GRUB_GFXMODE=' /etc/default/grub || echo 'GRUB_GFXMODE=auto' | sudo tee -a /etc/default/grub >/dev/null
    grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub || echo 'GRUB_GFXPAYLOAD_LINUX=keep' | sudo tee -a /etc/default/grub >/dev/null

    # Remove all fallback initramfs images
    sudo rm -f /boot/initramfs-*-fallback.img

    # Show all kernels and fallback entries in main menu
    if grep -q '^GRUB_DISABLE_SUBMENU=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub
    else
        echo 'GRUB_DISABLE_SUBMENU=y' | sudo tee -a /etc/default/grub >/dev/null
    fi

    # Show Btrfs snapshots in main menu if grub-btrfs is installed
    if pacman -Q grub-btrfs &>/dev/null; then
        if grep -q '^GRUB_BTRFS_SUBMENU=' /etc/default/grub; then
            sudo sed -i 's/^GRUB_BTRFS_SUBMENU=.*/GRUB_BTRFS_SUBMENU=n/' /etc/default/grub
        else
            echo 'GRUB_BTRFS_SUBMENU=n' | sudo tee -a /etc/default/grub >/dev/null
        fi
    fi

    # Regenerate grub config
    log_info "Regenerating GRUB configuration..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    # Remove fallback kernel entries from grub.cfg for a cleaner menu
    log_info "Removing GRUB fallback kernel entries..."
    sudo sed -i '/fallback/d' /boot/grub/grub.cfg || true

    # Post-process grub.cfg to ensure correct ordering
    log_info "Reordering GRUB menu entries: standard kernel first, then LTS..."

    # Create Python script for reordering
    cat > /tmp/reorder_grub.py <<'PYTHON_EOF'
import re
import sys

try:
    with open('/boot/grub/grub.cfg', 'r') as f:
        content = f.read()

    # Find the 10_linux section
    start_marker = '### BEGIN /etc/grub.d/10_linux ###'
    end_marker = '### END /etc/grub.d/10_linux ###'

    if start_marker not in content or end_marker not in content:
        print("Could not find 10_linux section markers", file=sys.stderr)
        sys.exit(1)

    start_idx = content.index(start_marker) + len(start_marker)
    end_idx = content.index(end_marker)

    before = content[:start_idx]
    section = content[start_idx:end_idx]
    after = content[end_idx:]

    # Extract all menu entries with proper nesting handling
    entries = []
    depth = 0
    current_entry = []
    in_entry = False

    for line in section.split('\n'):
        if line.strip().startswith('menuentry'):
            in_entry = True
            depth = 0
            current_entry = [line]
        elif in_entry:
            current_entry.append(line)
            if '{' in line:
                depth += line.count('{')
            if '}' in line:
                depth -= line.count('}')
            if depth == 0 and '}' in line:
                entries.append('\n'.join(current_entry))
                in_entry = False
                current_entry = []

    # Categorize entries
    standard = []
    lts = []
    others = []

    for entry in entries:
        if 'Linux linux' in entry and 'linux-lts' not in entry and 'linux-zen' not in entry and 'linux-hardened' not in entry:
            standard.append(entry)
        elif 'linux-lts' in entry:
            lts.append(entry)
        else:
            others.append(entry)

    # Rebuild section with correct order
    reordered = standard + lts + others
    new_section = '\n'.join(reordered)

    # Write back
    with open('/boot/grub/grub.cfg', 'w') as f:
        f.write(before + '\n' + new_section + '\n' + after)

    print(f"Successfully reordered GRUB menu: {len(standard)} standard, {len(lts)} LTS, {len(others)} other entries")
    sys.exit(0)

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

    # Run Python reordering
    if python3 /tmp/reorder_grub.py 2>/dev/null; then
        log_success "Python reordering completed successfully"
    else
        log_warning "Python reordering failed, trying awk method..."

        # Fallback awk method - simpler but should work
        awk '
        BEGIN {
            in_section=0
            entry=""
            entry_count=0
        }

        # Mark section boundaries
        /### BEGIN \/etc\/grub.d\/10_linux ###/ {
            in_section=1
            print
            next
        }
        /### END \/etc\/grub.d\/10_linux ###/ {
            # Output collected entries in order
            for (i=1; i<=std_count; i++) print standard[i]
            for (i=1; i<=lts_count; i++) print lts[i]
            for (i=1; i<=other_count; i++) print others[i]
            in_section=0
            print
            next
        }

        # Collect entries in section
        in_section==1 {
            if ($0 ~ /^menuentry/) {
                # Save previous entry if exists
                if (entry != "") {
                    if (entry ~ /Linux linux[^-]/ && entry !~ /linux-lts/) {
                        standard[++std_count] = entry
                    } else if (entry ~ /linux-lts/) {
                        lts[++lts_count] = entry
                    } else {
                        others[++other_count] = entry
                    }
                }
                entry = $0 "\n"
                brace_depth = gsub(/{/, "&")
                next
            }

            if (entry != "") {
                entry = entry $0 "\n"
                brace_depth += gsub(/{/, "&")
                brace_depth -= gsub(/}/, "&")

                # Entry complete when braces balanced
                if (brace_depth == 0 && $0 ~ /}/) {
                    if (entry ~ /Linux linux[^-]/ && entry !~ /linux-lts/) {
                        standard[++std_count] = entry
                    } else if (entry ~ /linux-lts/) {
                        lts[++lts_count] = entry
                    } else {
                        others[++other_count] = entry
                    }
                    entry = ""
                }
                next
            }

            # Non-menuentry lines
            print
            next
        }

        # Outside section - pass through
        { print }
        ' /boot/grub/grub.cfg > /tmp/grub_reordered.cfg

        if [ -s /tmp/grub_reordered.cfg ]; then
            sudo mv /tmp/grub_reordered.cfg /boot/grub/grub.cfg
            log_success "AWK reordering completed"
        else
            log_error "AWK reordering produced empty file, keeping original"
        fi
    fi

    # Clean up
    rm -f /tmp/reorder_grub.py

    # Set default to position 0 (which should now be the standard kernel)
    log_info "Setting default GRUB entry to position 0 (standard kernel)..."
    sudo grub-set-default 0

    # Update grubenv to ensure saved_entry is set correctly
    if [ -f /boot/grub/grubenv ]; then
        sudo grub-editenv /boot/grub/grubenv set saved_entry=0
    fi

    log_success "GRUB configuration complete:"
    log_success "  - Standard 'linux' kernel set as first entry"
    log_success "  - LTS kernel set as second entry"
    log_success "  - Default boot set to standard kernel (position 0)"
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
    sudo pacman -S --noconfirm os-prober >/dev/null 2>&1
    # Ensure GRUB_DISABLE_OS_PROBER is not set to true
    if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    else
        echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null
    fi
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo "Windows entry added to GRUB (if detected by os-prober)."
}

find_windows_efi_partition() {
    local partitions=($(lsblk -n -o NAME,TYPE | grep "part" | awk '{print "/dev/"$1}'))
    for partition in "${partitions[@]}"; do
        local temp_mount="/tmp/windows_efi_check"
        mkdir -p "$temp_mount"
        if mount "$partition" "$temp_mount" 2>/dev/null; then
            if [ -d "$temp_mount/EFI/Microsoft" ]; then
                umount "$temp_mount"
                rm -rf "$temp_mount"
                echo "$partition"
                return 0
            fi
            umount "$temp_mount"
        fi
        rm -rf "$temp_mount"
    done
    return 1
}

add_windows_to_systemdboot() {
    # Only copy EFI files if not already present
    if [ ! -d "/boot/EFI/Microsoft" ]; then
        local windows_partition
        windows_partition=$(find_windows_efi_partition)
        if [ -z "$windows_partition" ]; then
            echo "Error: Could not find Windows EFI partition"
            return 1
        fi
        local mount_point="/mnt/winefi"
        mkdir -p "$mount_point"
        if mount "$windows_partition" "$mount_point"; then
            if [ -d "$mount_point/EFI/Microsoft" ]; then
                cp -R "$mount_point/EFI/Microsoft" /boot/EFI/
                echo "Copied Microsoft EFI files to /boot/EFI/Microsoft."
            else
                echo "Error: Microsoft EFI files not found in $windows_partition"
            fi
            umount "$mount_point"
        else
            echo "Error: Failed to mount Windows EFI partition"
        fi
        rm -rf "$mount_point"
    else
        echo "Microsoft EFI files already present in /boot/EFI/Microsoft."
    fi

    # Create loader entry if not present
    local entry="/boot/loader/entries/windows.conf"
    if [ ! -f "$entry" ]; then
        cat <<EOF | sudo tee "$entry" >/dev/null
title   Windows
efi     /EFI/Microsoft/Boot/bootmgfw.efi
EOF
        echo "Added Windows entry to systemd-boot."
    else
        echo "Windows entry already exists in systemd-boot."
    fi
}

set_localtime_for_windows() {
    sudo timedatectl set-local-rtc 1 --adjust-system-clock
    echo "Set hardware clock to local time for Windows compatibility."
}

# --- Main Execution ---

# Apply GRUB config if needed
if [ "$BOOTLOADER" = "grub" ]; then
    configure_grub
fi

# Windows dual-boot configuration
if detect_windows; then
    echo "Windows installation detected. Configuring dual-boot..."
    # Always install ntfs-3g for NTFS access
    sudo pacman -S --noconfirm ntfs-3g >/dev/null 2>&1

    if [ "$BOOTLOADER" = "grub" ]; then
        add_windows_to_grub
    elif [ "$BOOTLOADER" = "systemd-boot" ]; then
        add_windows_to_systemdboot
    fi
    set_localtime_for_windows
fi
