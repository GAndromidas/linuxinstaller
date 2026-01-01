#!/bin/bash
set -uo pipefail

# Maintenance Configuration Module for LinuxInstaller
# Based on best practices from all installers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Maintenance-specific package lists
MAINTENANCE_ESSENTIALS=(
    "btrfs-assistant"
    "btrfsmaintenance"
)

MAINTENANCE_ARCH=(
    "snap-pac"
    "snapper"
    "grub-btrfs"
    "linux-lts"
    "linux-lts-headers"
)

MAINTENANCE_FEDORA=(
    "timeshift"
    "btrfs-progs"
)

MAINTENANCE_DEBIAN=(
    "timeshift"
    "btrfs-progs"
)

# =============================================================================
# MAINTENANCE CONFIGURATION FUNCTIONS
# =============================================================================

# Install maintenance packages for all distributions
maintenance_install_packages() {
    step "Installing Maintenance Packages"

    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Maintenance packages help protect your system with snapshots and updates"
    fi

    local packages=()
    local descriptions=()
    local installed=()
    local skipped=()
    local failed=()

    case "$DISTRO_ID" in
        "arch")
            packages=("${MAINTENANCE_ARCH[@]}")
            descriptions=(
                "snap-pac: Automatic snapshots before/after package updates"
                "snapper: Btrfs snapshot management tool"
                "grub-btrfs: GRUB integration for booting from snapshots"
                "linux-lts: Long-term support kernel for stability"
                "linux-lts-headers: Headers for LTS kernel (required for modules)"
            )
            ;;
        "fedora")
            packages=("${MAINTENANCE_FEDORA[@]}")
            descriptions=(
                "timeshift: System backup and restore tool"
                "btrfs-progs: Btrfs filesystem utilities (already installed)"
            )
            ;;
        "debian"|"ubuntu")
            packages=("${MAINTENANCE_DEBIAN[@]}")
            descriptions=(
                "timeshift: System backup and restore tool"
                "btrfs-progs: Btrfs filesystem utilities (already installed)"
            )
            ;;
    esac

    for i in "${!packages[@]}"; do
        local pkg="${packages[$i]}"
        local desc="${descriptions[$i]:-Maintenance tool}"

        # Check if already installed
        if is_package_installed "$pkg"; then
            skipped+=("$pkg")
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "○ $pkg (already installed)"
            fi
            continue
        fi

        # Check if package exists
        if ! package_exists "$pkg"; then
            failed+=("$pkg")
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_ERROR_FG" "✗ $pkg (not found in repositories)"
            fi
            continue
        fi

        # Install with gum spin and show description
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "• Installing $pkg"
            gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  $desc"
            if gum spin --spinner dot --title "" -- install_pkg "$pkg" >/dev/null 2>&1; then
                installed+=("$pkg")
                gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "  ✓ $pkg installed"
            else
                failed+=("$pkg")
                gum style --margin "0 2" --foreground "$GUM_ERROR_FG" "  ✗ Failed to install $pkg"
            fi
        else
            log_info "Installing $pkg: $desc"
            if install_pkg "$pkg" >/dev/null 2>&1; then
                installed+=("$pkg")
                log_success "✓ $pkg installed"
            else
                failed+=("$pkg")
                log_error "✗ Failed to install $pkg"
            fi
        fi
    done

    # Show summary with gum styling
    if supports_gum; then
        echo ""
        gum style --margin "0 2" --border rounded --border-foreground "$GUM_BORDER_FG" --padding "1 2" "Installation Summary"
        if [ ${#installed[@]} -gt 0 ]; then
            gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Installed: ${#installed[@]} package(s)"
            gum style --margin "0 4" --foreground "$GUM_BODY_FG" "${installed[*]}"
        fi
        if [ ${#skipped[@]} -gt 0 ]; then
            gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "○ Skipped (already installed): ${#skipped[@]} package(s)"
        fi
        if [ ${#failed[@]} -gt 0 ]; then
            gum style --margin "0 2" --foreground "$GUM_ERROR_FG" "✗ Failed: ${#failed[@]} package(s)"
            gum style --margin "0 4" --foreground "$GUM_BODY_FG" "${failed[*]}"
        fi
    else
        if [ ${#installed[@]} -gt 0 ]; then
            log_success "✓ Installed: ${#installed[@]} package(s) - ${installed[*]}"
        fi
        if [ ${#skipped[@]} -gt 0 ]; then
            log_info "○ Skipped: ${#skipped[@]} package(s) already installed"
        fi
        if [ ${#failed[@]} -gt 0 ]; then
            log_error "✗ Failed: ${#failed[@]} package(s) - ${failed[*]}"
        fi
    fi
}

# Configure TimeShift for Fedora/Debian/Ubuntu
maintenance_configure_timeshift() {
    step "Configuring TimeShift"

    if ! command -v timeshift >/dev/null 2>&1; then
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "○ TimeShift not installed, skipping configuration"
        fi
        return
    fi

    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "TimeShift: Creating system backup configuration"
        gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  This creates snapshots to protect your system from updates"
    fi

    mkdir -p /etc/timeshift

    local TS_CONFIG="/etc/timeshift/timeshift.json"

    tee "$TS_CONFIG" >/dev/null << 'EOF'
{
    "snapshot_device_uuid": null,
    "snapshot_device": "",
    "snapshot_mnt": "/",
    "snapshot_output_dir": "",
    "snapshot_output_dirs": [],
    "schedule_monthly": false,
    "schedule_weekly": false,
    "schedule_daily": false,
    "schedule_hourly": false,
    "schedule_boot": false,
    "schedule_startup": false,
    "count_max": 10,
    "count_min": 0,
    "count": 0,
    "date_format": "%Y-%m-%d %H:%M",
    "exclude": [
        "/home/*/.cache*",
        "/home/*/.local/share/Trash*",
        "/home/*/.thumbnails/*",
        "/home/*/.local/share/Steam/*",
        "/var/cache/*",
        "/var/tmp/*",
        "/var/log/journal/*",
        "/home/*/Downloads/*"
    ]
}
EOF

    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ TimeShift configured for manual snapshots"
        gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Excludes: cache, downloads, Steam, and temporary files"
    else
        log_success "✓ TimeShift configured for manual snapshots"
    fi
}

# Configure Snapper for Arch (only)
maintenance_configure_snapper_settings() {
    step "Configuring Snapper (Arch Only)"

    if [ "$DISTRO_ID" != "arch" ]; then
        return
    fi

    if ! command -v snapper >/dev/null 2>&1; then
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "○ Snapper not installed, skipping configuration"
        fi
        return
    fi

    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Snapper: Configuring Btrfs snapshot management"
        gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Automatic snapshots protect your system before/after updates"
    fi

    # Create snapper config if it doesn't exist
    if ! snapper -c root create-config / >/dev/null 2>&1; then
        log_warn "Failed to create Snapper configuration"
        return
    fi

    # Configure Snapper with best practice settings
    # Enable timeline snapshots for automatic protection
    sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' /etc/snapper/configs/root
    sed -i 's/^NUMBER_CLEANUP=.*/NUMBER_CLEANUP="yes"/' /etc/snapper/configs/root
    sed -i 's/^EMPTY_CLEANUP=.*/EMPTY_CLEANUP="yes"/' /etc/snapper/configs/root

    # Set reasonable limits for timeline snapshots
    sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="10"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="4"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="12"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root

    # Set number of snapshots to keep to 10
    sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/' /etc/snapper/configs/root
    sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="10"/' /etc/snapper/configs/root

    # Enable timeline and cleanup timers for automatic snapshots
    if supports_gum; then
        gum spin --spinner dot --title "Enabling snapshot timers..." -- systemctl enable --now snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer >/dev/null 2>&1
        gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Snapper timers enabled"
        gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Timeline: Hourly (10), Daily (7), Weekly (4), Monthly (12)"
    else
        systemctl enable --now snapper-timeline.timer >/dev/null 2>&1
        systemctl enable --now snapper-cleanup.timer >/dev/null 2>&1
        systemctl enable --now snapper-boot.timer >/dev/null 2>&1
        log_success "✓ Snapper timers enabled"
    fi
}

# Setup pre-update snapshots (TimeShift for non-Arch, Snapper for Arch)
maintenance_setup_pre_update_snapshots() {
    step "Setting Up Pre-Update Snapshot Function"

    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Creating automatic snapshots before system updates"
        gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  This protects your system from broken updates"
    fi

    if [ "$DISTRO_ID" = "arch" ]; then
        if ! command -v snapper >/dev/null 2>&1; then
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "○ Snapper not available, skipping pre-update snapshots"
            fi
            return
        fi

        # Arch: Pacman hook
        local HOOK_DIR="/etc/pacman.d/hooks"
        local HOOK_SCRIPT="snapper-notify.hook"

        mkdir -p "$HOOK_DIR"

        cat << 'EOF' | tee "$HOOK_DIR/$HOOK_SCRIPT" >/dev/null
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Create pre-update snapshot
When = PreTransaction
Exec = /usr/bin/sh -c 'snapper -c root create -d "Pre-update: $(date +"%%Y-%%m-%%d %%H:%%M")"'

[Action]
Description = Create post-update snapshot
When = PostTransaction
Exec = /usr/bin/sh -c 'snapper -c root create -d "Post-update: $(date +"%%Y-%%m-%%d %%H:%%M")" && echo "Snapshots created. View with: snapper list"'
EOF

        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Pacman hook installed for pre/post-update snapshots"
            gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Snapshots will be created automatically before/after each package update"
        else
            log_success "✓ Pacman hook installed for pre/post-update snapshots"
        fi

    else
        if ! command -v timeshift >/dev/null 2>&1; then
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "○ TimeShift not available, skipping pre-update snapshots"
            fi
            return
        fi

        cat << 'EOF' | tee /usr/local/bin/system-update-snapshot >/dev/null
#!/bin/bash
DESCRIPTION="${1:-Pre-update}"

if command -v timeshift >/dev/null 2>&1; then
    timeshift --create --description "$DESCRIPTION"
else
    exit 1
fi
EOF
        chmod +x /usr/local/bin/system-update-snapshot

        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Snapshot wrapper created: /usr/local/bin/system-update-snapshot"
            gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Run this before updates: system-update-snapshot"
        else
            log_success "✓ Snapshot wrapper created: /usr/local/bin/system-update-snapshot"
        fi
    fi
}

# Configure GRUB for snapshot boot menu (TimeShift for non-Arch, Snapper for Arch)
maintenance_configure_grub_snapshots() {
    step "Configuring GRUB for Snapshot Boot Menu"

    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Adding snapshots to boot menu"
        gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Allows booting from previous snapshots if updates fail"
    fi

    local bootloader
    bootloader=$(detect_bootloader)

    if [ "$bootloader" != "grub" ]; then
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "○ Only GRUB bootloader is supported for snapshot menu"
        fi
        return
    fi

    local grub_update_command=""

    if [ "$DISTRO_ID" = "arch" ]; then
        if ! pacman -Q grub-btrfs >/dev/null 2>&1; then
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_BODY_FG" "• Installing grub-btrfs for snapshot boot menu"
                if gum spin --spinner dot --title "" -- pacman -S --noconfirm grub-btrfs >/dev/null 2>&1; then
                    gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "  ✓ grub-btrfs installed"
                fi
            else
                pacman -S --noconfirm grub-btrfs >/dev/null 2>&1 || true
            fi
        fi

        if command -v grub-btrfsd >/dev/null 2>&1; then
            systemctl enable --now grub-btrfsd.service >/dev/null 2>&1
        fi

        grub_update_command="grub-mkconfig"
    else
        if command -v grub-mkconfig >/dev/null 2>&1; then
            grub_update_command="grub-mkconfig"
        elif command -v update-grub >/dev/null 2>&1; then
            grub_update_command="update-grub"
        fi
    fi

    if [ -n "$grub_update_command" ]; then
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "• Updating GRUB configuration"
            if gum spin --spinner dot --title "Regenerating boot menu..." -- $grub_update_command -o /boot/grub/grub.cfg >/dev/null 2>&1; then
                gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ GRUB updated with snapshot boot menu"
                gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Reboot and hold 'Shift' to see snapshot boot entries"
            fi
        else
            $grub_update_command -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
            log_success "✓ GRUB updated with snapshot support"
        fi
    fi
}

# Configure Btrfs snapshot management
maintenance_configure_btrfs_snapshots() {
    step "Configuring Btrfs Snapshots"

    if ! is_btrfs_system; then
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "○ Not a Btrfs system, skipping snapshot configuration"
        fi
        return
    fi

    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Btrfs filesystem detected: Configuring snapshot protection"
        gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Snapshots allow you to restore your system if updates break it"
    fi

    # Choose snapshot tool based on distro
    # Arch: Snapper (better GRUB integration with grub-btrfs)
    # Fedora/Debian/Ubuntu: TimeShift (simpler, better for cross-distro)
    if [ "$DISTRO_ID" = "arch" ]; then
        maintenance_configure_snapper_settings
    else
        maintenance_configure_timeshift
    fi

    # Setup pre/post-update snapshot hooks for all distros
    maintenance_setup_pre_update_snapshots

    # Configure GRUB for snapshots (only if GRUB bootloader)
    maintenance_configure_grub_snapshots

    # Configure Btrfs maintenance timers with best practice settings
    if [ -f /etc/systemd/system/btrfs-scrub@.timer ] || command -v btrfs-scrub >/dev/null 2>&1; then
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "• Setting up Btrfs maintenance: Weekly scrub ( Sundays at 2:00 AM )"
        fi
        # Weekly scrub on Sunday at 2:00 AM
        mkdir -p /etc/systemd/system/btrfs-scrub@.timer.d
        cat << 'EOF' | tee /etc/systemd/system/btrfs-scrub@root.timer.d/override.conf >/dev/null
[Timer]
OnCalendar=Sun *-*-* 02:00:00
Persistent=true
EOF
        systemctl enable --now btrfs-scrub@root.timer >/dev/null 2>&1
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "  ✓ Btrfs scrub scheduled"
        fi
    fi

    if [ -f /etc/systemd/system/btrfs-balance@.timer ] || command -v btrfs-balance >/dev/null 2>&1; then
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "• Setting up Btrfs maintenance: Monthly balance ( 1st Sunday at 3:00 AM )"
        fi
        # Monthly balance on first Sunday at 3:00 AM
        mkdir -p /etc/systemd/system/btrfs-balance@.timer.d
        cat << 'EOF' | tee /etc/systemd/system/btrfs-balance@root.timer.d/override.conf >/dev/null
[Timer]
OnCalendar=Sun *-*-01 03:00:00
Persistent=true
EOF
        systemctl enable --now btrfs-balance@root.timer >/dev/null 2>&1
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "  ✓ Btrfs balance scheduled"
        fi
    fi

    # Create initial snapshot
    if [ "$DISTRO_ID" = "arch" ]; then
        if snapper -c root create -d "Initial snapshot after setup" >/dev/null 2>&1; then
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Initial snapshot created"
            else
                log_success "Initial snapshot created"
            fi
        fi
    else
        if command -v timeshift >/dev/null 2>&1; then
            if timeshift --create --description "Initial snapshot after setup" >/dev/null 2>&1; then
                if supports_gum; then
                    gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Initial snapshot created"
                else
                    log_success "Initial snapshot created"
                fi
            fi
        fi
    fi
}

# Configure automatic system updates for Fedora/Debian/Ubuntu
maintenance_configure_automatic_updates() {
    step "Configuring Automatic Updates"

    case "$DISTRO_ID" in
        "fedora")
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Configuring dnf-automatic for security updates"
                gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Security updates will be installed automatically"
            fi
            # Configure dnf-automatic
            if [ -f /etc/dnf/automatic.conf ]; then
                sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf 2>/dev/null || true
                sed -i 's/^upgrade_type = default/upgrade_type = security/' /etc/dnf/automatic.conf 2>/dev/null || true
                if systemctl enable --now dnf-automatic-install.timer >/dev/null 2>&1; then
                    if supports_gum; then
                        gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ dnf-automatic configured and enabled"
                    else
                        log_success "dnf-automatic configured and enabled"
                    fi
                else
                    log_warn "Failed to enable dnf-automatic"
                fi
            fi
            ;;
        "debian"|"ubuntu")
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Configuring unattended-upgrades for security updates"
                gum style --margin "0 4" --foreground "$GUM_BORDER_FG" "  Security updates will be installed automatically"
            fi
            # Configure unattended-upgrades
            if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
                sed -i 's|//\("o=Debian,a=stable"\)|"\${distro_id}:\${distro_codename}-security"|' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
                sed -i 's|//Unattended-Upgrade::AutoFixInterruptedDpkg|Unattended-Upgrade::AutoFixInterruptedDpkg|' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
                sed -i 's|//Unattended-Upgrade::MinimalSteps|Unattended-Upgrade::MinimalSteps|' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
                sed -i 's|//Unattended-Upgrade::Remove-Unused-Dependencies|Unattended-Upgrade::Remove-Unused-Dependencies|' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
            fi

            if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
                sed -i 's|APT::Periodic::Update-Package-Lists "0"|APT::Periodic::Update-Package-Lists "1"|' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
                sed -i 's|APT::Periodic::Unattended-Upgrade "0"|APT::Periodic::Unattended-Upgrade "1"|' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
            fi

            if systemctl enable --now unattended-upgrades >/dev/null 2>&1; then
                if supports_gum; then
                    gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ unattended-upgrades configured and enabled"
                else
                    log_success "unattended-upgrades configured and enabled"
                fi
            else
                log_warn "Failed to enable unattended-upgrades"
            fi
            ;;
        *)
            # For other distributions (including Arch) we intentionally do not
            # create distribution-specific auto-update scripts here.
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "○ Automatic updates not configured for $DISTRO_ID"
            else
                log_info "Automatic updates not configured for $DISTRO_ID by this installer"
            fi
            ;;
    esac
}

# =============================================================================
# MAIN MAINTENANCE CONFIGURATION FUNCTION
# =============================================================================

maintenance_main_config() {
    log_info "Starting maintenance configuration..."

    maintenance_install_packages

    maintenance_configure_btrfs_snapshots

    maintenance_setup_pre_update_snapshots

    maintenance_configure_automatic_updates

    # Show final summary
    if supports_gum; then
        echo ""
        gum style --margin "1 2" --border double --border-foreground "$GUM_PRIMARY_FG" --padding "1 2" "Maintenance Configuration Complete"
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Your system is now configured for safety and maintenance:"
        gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Snapshots: Protect against broken updates"
        gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Btrfs maintenance: Scheduled scrub and balance"
        if [ "$DISTRO_ID" = "arch" ]; then
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "• View snapshots: snapper list"
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "• Restore snapshot: Select from boot menu"
        else
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "• View snapshots: timeshift --list"
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "• Restore snapshot: timeshift --restore"
        fi
        echo ""
    fi

    log_success "Maintenance configuration completed"
}

# Export functions for use by main installer
export -f maintenance_main_config
export -f maintenance_install_packages
export -f maintenance_configure_btrfs_snapshots
export -f maintenance_configure_automatic_updates
export -f maintenance_configure_timeshift
export -f maintenance_configure_snapper_settings
export -f maintenance_setup_pre_update_snapshots
export -f maintenance_configure_grub_snapshots
