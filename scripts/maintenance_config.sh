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

maintenance_configure_btrfs_snapshots() {
    step "Configuring Btrfs Snapshots"

    if is_btrfs_system; then
        log_info "Btrfs filesystem detected, setting up snapshots..."

        local bootloader
        bootloader=$(detect_bootloader)

        # Configure Snapper
        if ! sudo snapper -c root create-config / >/dev/null 2>&1; then
            log_warn "Failed to create Snapper configuration"
            return
        fi

        # Enable Snapper services
        sudo systemctl enable --now snapper-timeline.timer >/dev/null 2>&1
        sudo systemctl enable --now snapper-cleanup.timer >/dev/null 2>&1
        sudo systemctl enable --now snapper-boot.timer >/dev/null 2>&1

        # Enable Btrfs maintenance services
        sudo systemctl enable --now btrfs-scrub@-.timer >/dev/null 2>&1
        sudo systemctl enable --now btrfs-balance@-.timer >/dev/null 2>&1
        sudo systemctl enable --now btrfs-defrag@-.timer >/dev/null 2>&1

        # Update bootloader for snapshots
        if [ "$bootloader" == "grub" ]; then
            sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
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
