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
    "linux-lts"
    "linux-lts-headers"
)

MAINTENANCE_FEDORA=(
    "btrfs-progs"
    "dnf-automatic"
)

MAINTENANCE_DEBIAN=(
    "btrfs-tools"
    "unattended-upgrades"
    "apticron"
)

# =============================================================================
# MAINTENANCE CONFIGURATION FUNCTIONS
# =============================================================================

maintenance_install_packages() {
    step "Installing Maintenance Packages"

    log_info "Installing maintenance essential packages..."
    for package in "${MAINTENANCE_ESSENTIALS[@]}"; do
        if ! install_pkg "$package"; then
            log_warn "Failed to install maintenance package: $package"
        else
            log_success "Installed maintenance package: $package"
        fi
    done

    # Install distribution-specific maintenance packages
    case "$DISTRO_ID" in
        "arch")
            log_info "Installing Arch-specific maintenance packages..."
            for package in "${MAINTENANCE_ARCH[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Arch maintenance package: $package"
                else
                    log_success "Installed Arch maintenance package: $package"
                fi
            done
            ;;
        "fedora")
            log_info "Installing Fedora-specific maintenance packages..."
            for package in "${MAINTENANCE_FEDORA[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Fedora maintenance package: $package"
                else
                    log_success "Installed Fedora maintenance package: $package"
                fi
            done
            ;;
        "debian"|"ubuntu")
            log_info "Installing Debian/Ubuntu-specific maintenance packages..."
            for package in "${MAINTENANCE_DEBIAN[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Debian maintenance package: $package"
                else
                    log_success "Installed Debian maintenance package: $package"
                fi
            done
            ;;
    esac
}

maintenance_configure_snapper_settings() {
    step "Configuring Snapper Settings"

    if ! command -v snapper >/dev/null 2>&1; then
        log_info "Snapper not installed, skipping configuration"
        return
    fi

    log_info "Configuring Snapper for optimal snapshot management..."

    # Create snapper config if it doesn't exist
    if ! sudo snapper -c root create-config / >/dev/null 2>&1; then
        log_warn "Failed to create Snapper configuration"
        return
    fi

    # Backup existing config
    if [ -f /etc/snapper/configs/root ]; then
        sudo cp /etc/snapper/configs/root "/etc/snapper/configs/root.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        log_info "Snapper config backed up"
    fi

    # Configure Snapper with user's desired settings
    # Disable all timeline snapshots (hourly, daily, weekly, monthly, yearly)
    sudo sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/' /etc/snapper/configs/root
    sudo sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="yes"/' /etc/snapper/configs/root
    sudo sed -i 's/^NUMBER_CLEANUP=.*/NUMBER_CLEANUP="yes"/' /etc/snapper/configs/root
    sudo sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="0"/' /etc/snapper/configs/root
    sudo sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="0"/' /etc/snapper/configs/root
    sudo sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/' /etc/snapper/configs/root
    sudo sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' /etc/snapper/configs/root
    sudo sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root

    # Set number of snapshots to keep to 5 (not default 50)
    sudo sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="5"/' /etc/snapper/configs/root
    sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/root

    # Enable only boot timer for automatic snapshots
    sudo systemctl enable --now snapper-boot.timer >/dev/null 2>&1

    # Disable timeline and cleanup timers (we don't want automatic snapshots)
    sudo systemctl disable --now snapper-timeline.timer >/dev/null 2>&1 || true
    sudo systemctl disable --now snapper-cleanup.timer >/dev/null 2>&1 || true

    log_success "Snapper configured: boot snapshots only, max 5 snapshots"
    log_info "Timeline snapshots disabled as requested"
}

maintenance_setup_pre_update_snapshots() {
    step "Setting Up Pre-Update Snapshot Function"

    if ! command -v snapper >/dev/null 2>&1; then
        log_info "Snapper not installed, skipping snapshot hook setup"
        return
    fi

    local HOOK_DIR=""
    local HOOK_SCRIPT=""

    case "$DISTRO_ID" in
        "arch")
            HOOK_DIR="/etc/pacman.d/hooks"
            HOOK_SCRIPT="snapper-notify.hook"
            ;;
        "fedora")
            HOOK_DIR="/etc/dnf/plugins"
            HOOK_SCRIPT="snapper-notify.sh"
            ;;
        "debian"|"ubuntu")
            HOOK_DIR="/etc/apt/apt.conf.d"
            HOOK_SCRIPT="99snapper-notify"
            ;;
        *)
            log_info "No package hook supported for $DISTRO_ID"
            return
            ;;
    esac

    if [ -z "$HOOK_DIR" ]; then
        return
    fi

    sudo mkdir -p "$HOOK_DIR"

    case "$DISTRO_ID" in
        "arch")
            if [ -f "$HOOK_DIR/$HOOK_SCRIPT" ]; then
                sudo cp "$HOOK_DIR/$HOOK_SCRIPT" "$HOOK_DIR/${HOOK_SCRIPT}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            fi

            cat << 'EOF' | sudo tee "$HOOK_DIR/$HOOK_SCRIPT" >/dev/null
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
            log_success "Pacman hook installed for pre/post-update snapshots"
            ;;
        "fedora")
            if [ -f "$HOOK_DIR/$HOOK_SCRIPT" ]; then
                sudo cp "$HOOK_DIR/$HOOK_SCRIPT" "$HOOK_DIR/${HOOK_SCRIPT}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            fi

            cat << 'EOF' | sudo tee "$HOOK_DIR/$HOOK_SCRIPT" >/dev/null
#!/bin/bash
# DNF plugin for creating snapshots before/after package operations

pre_transaction() {
    if command -v snapper >/dev/null 2>&1; then
        snapper -c root create -d "Pre-update: $(date +%Y-%m-%d\ %H:%M)"
    fi
}

post_transaction() {
    if command -v snapper >/dev/null 2>&1; then
        snapper -c root create -d "Post-update: $(date +%Y-%m-%d\ %H:%M)"
    fi
}

# Hook into DNF
EOF
            sudo chmod +x "$HOOK_DIR/$HOOK_SCRIPT"
            log_success "DNF hook installed for pre/post-update snapshots"
            ;;
        "debian"|"ubuntu")
            if [ -f "$HOOK_DIR/$HOOK_SCRIPT" ]; then
                sudo cp "$HOOK_DIR/$HOOK_SCRIPT" "$HOOK_DIR/${HOOK_SCRIPT}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            fi

            cat << 'EOF' | sudo tee "$HOOK_DIR/$HOOK_SCRIPT" >/dev/null
DPkg::Pre-Install-Pkgs { "snapper -c root create -d \"Pre-install: \$(date +%Y-%m-%d\\ %H:%M)\""; }
DPkg::Post-Invoke { "if [ \$1 = \"configure\" ] || [ \$1 = \"remove\" ]; then snapper -c root create -d \"Post-operation: \$(date +%Y-%m-%d\\ %H:%M)\"; fi"; }
EOF
            log_success "APT hook installed for pre/post-update snapshots"
            ;;
    esac
}

maintenance_configure_grub_snapshots() {
    step "Configuring GRUB for Snapshot Boot Menu"

    if ! command -v snapper >/dev/null 2>&1; then
        log_info "Snapper not installed, skipping GRUB configuration"
        return
    fi

    local bootloader
    bootloader=$(detect_bootloader)
    log_info "Detected bootloader: $bootloader"

    # Only configure GRUB, skip systemd-boot and others
    if [ "$bootloader" != "grub" ]; then
        log_info "Non-GRUB bootloader detected ($bootloader). Skipping GRUB snapshot menu."
        if [ "$bootloader" = "systemd-boot" ]; then
            log_info "systemd-boot detected. Snapshots will not be added to boot menu."
        fi
        return
    fi

    # Install grub-btrfs if on Arch
    if [ "$DISTRO_ID" = "arch" ]; then
        if ! pacman -Q grub-btrfs >/dev/null 2>&1; then
            log_info "Installing grub-btrfs for GRUB snapshot support..."
            install_pkg "grub-btrfs" || {
                log_warn "Failed to install grub-btrfs"
                return 1
            }
        else
            log_info "grub-btrfs already installed"
        fi

        # Enable grub-btrfsd service for automatic snapshot detection
        if command -v grub-btrfsd >/dev/null 2>&1; then
            if sudo systemctl enable --now grub-btrfsd.service >/dev/null 2>&1; then
                log_success "grub-btrfsd service enabled and started"
            else
                log_warn "Failed to enable grub-btrfsd service"
            fi
        fi
    fi

    # Regenerate GRUB configuration
    log_info "Regenerating GRUB configuration with snapshot support..."
    if command -v grub-mkconfig >/dev/null 2>&1; then
        if sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
            log_success "GRUB configuration complete - snapshots will appear in boot menu"
        else
            log_warn "Failed to regenerate GRUB configuration"
        fi
    elif command -v update-grub >/dev/null 2>&1; then
        # For Debian/Ubuntu systems
        if sudo update-grub >/dev/null 2>&1; then
            log_success "GRUB configuration complete - snapshots will appear in boot menu"
        else
            log_warn "Failed to regenerate GRUB configuration"
        fi
    else
        log_warn "GRUB regeneration command not found. Please regenerate manually."
    fi
}

maintenance_configure_btrfs_snapshots() {
    step "Configuring Btrfs Snapshots"

    if is_btrfs_system; then
        log_info "Btrfs filesystem detected, setting up snapshots..."

        local bootloader
        bootloader=$(detect_bootloader)

        # Configure Snapper settings (disable timeline, limit to 5 snapshots)
        maintenance_configure_snapper_settings

        # Setup pre/post-update snapshot hooks for all distros
        maintenance_setup_pre_update_snapshots

        # Configure GRUB for snapshots (only if GRUB bootloader)
        maintenance_configure_grub_snapshots

        # Enable Btrfs maintenance services (not snapshots, but maintenance)
        sudo systemctl enable --now btrfs-scrub@-.timer >/dev/null 2>&1 || true
        sudo systemctl enable --now btrfs-balance@-.timer >/dev/null 2>&1 || true
        sudo systemctl enable --now btrfs-defrag@-.timer >/dev/null 2>&1 || true

        # Create initial snapshot
        if sudo snapper -c root create -d "Initial snapshot after setup" >/dev/null 2>&1; then
            log_success "Initial snapshot created"
        else
            log_warn "Failed to create initial snapshot (non-critical)"
        fi

        log_success "Btrfs snapshots configured"
    else
        log_info "Btrfs filesystem not detected, skipping snapshot configuration"
    fi
}

maintenance_configure_automatic_updates() {
    step "Configuring Automatic Updates"

    case "$DISTRO_ID" in
        "fedora")
            # Configure dnf-automatic
            if [ -f /etc/dnf/automatic.conf ]; then
                sudo sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf 2>/dev/null || true
                sudo sed -i 's/^upgrade_type = default/upgrade_type = security/' /etc/dnf/automatic.conf 2>/dev/null || true
                if sudo systemctl enable --now dnf-automatic-install.timer >/dev/null 2>&1; then
                    log_success "dnf-automatic configured and enabled"
                else
                    log_warn "Failed to enable dnf-automatic"
                fi
            fi
            ;;
        "debian"|"ubuntu")
            # Configure unattended-upgrades
            if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
                sudo sed -i 's|//\("o=Debian,a=stable"\)|"\${distro_id}:\${distro_codename}-security"|' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
                sudo sed -i 's|//Unattended-Upgrade::AutoFixInterruptedDpkg|Unattended-Upgrade::AutoFixInterruptedDpkg|' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
                sudo sed -i 's|//Unattended-Upgrade::MinimalSteps|Unattended-Upgrade::MinimalSteps|' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
                sudo sed -i 's|//Unattended-Upgrade::Remove-Unused-Dependencies|Unattended-Upgrade::Remove-Unused-Dependencies|' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || true
            fi

            if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
                sudo sed -i 's|APT::Periodic::Update-Package-Lists "0"|APT::Periodic::Update-Package-Lists "1"|' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
                sudo sed -i 's|APT::Periodic::Unattended-Upgrade "0"|APT::Periodic::Unattended-Upgrade "1"|' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
            fi

            if sudo systemctl enable --now unattended-upgrades >/dev/null 2>&1; then
                log_success "unattended-upgrades configured and enabled"
            else
                log_warn "Failed to enable unattended-upgrades"
            fi
            ;;
        *)
            # For other distributions (including Arch) we intentionally do not
            # create distribution-specific auto-update scripts here.
            log_info "Automatic updates not configured for $DISTRO_ID by this installer"
            ;;
    esac
}

# =============================================================================
# MAIN MAINTENANCE CONFIGURATION FUNCTION
# =============================================================================

maintenance_main_config() {
    log_info "Starting maintenance configuration..."

    # Install maintenance packages
    if ! is_step_complete "maintenance_install_packages"; then
        maintenance_install_packages
        mark_step_complete "maintenance_install_packages"
    fi

    # Configure Btrfs snapshots
    if ! is_step_complete "maintenance_configure_btrfs_snapshots"; then
        maintenance_configure_btrfs_snapshots
        mark_step_complete "maintenance_configure_btrfs_snapshots"
    fi

    # Configure pre-update snapshot function
    if ! is_step_complete "maintenance_setup_pre_update_snapshots"; then
        maintenance_setup_pre_update_snapshots
        mark_step_complete "maintenance_setup_pre_update_snapshots"
    fi

    # Configure automatic updates (Fedora/Debian/Ubuntu)
    if ! is_step_complete "maintenance_configure_automatic_updates"; then
        maintenance_configure_automatic_updates
        mark_step_complete "maintenance_configure_automatic_updates"
    fi

    log_success "Maintenance configuration completed"
}

# Export functions for use by main installer
export -f maintenance_main_config
export -f maintenance_install_packages
export -f maintenance_configure_btrfs_snapshots
export -f maintenance_configure_automatic_updates
export -f maintenance_configure_snapper_settings
export -f maintenance_setup_pre_update_snapshots
export -f maintenance_configure_grub_snapshots
