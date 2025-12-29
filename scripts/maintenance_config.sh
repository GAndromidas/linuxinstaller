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
        "arch")
            # Arch doesn't have automatic updates by default, but we can set up
            # a cron job for manual updates
            log_info "Setting up manual update script for Arch..."
            cat > /tmp/arch-update.sh << 'EOF'
#!/bin/bash
# Arch Linux update script
sudo pacman -Syu --noconfirm
EOF
            chmod +x /tmp/arch-update.sh
            sudo mv /tmp/arch-update.sh /usr/local/bin/arch-update
            log_success "Arch update script created at /usr/local/bin/arch-update"
            ;;
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
    esac
}

maintenance_configure_cleanup() {
    step "Configuring System Cleanup"

    # Create cleanup script
    cat > /tmp/cleanup-system.sh << 'EOF'
#!/bin/bash
# System cleanup script

# Clean package cache
case "$DISTRO_ID" in
    "arch")
        sudo pacman -Sc --noconfirm
        if command -v yay >/dev/null 2>&1; then
            yay -Yc --noconfirm
        fi
        ;;
    "fedora")
        sudo dnf autoremove -y
        sudo dnf clean all
        ;;
    "debian"|"ubuntu")
        sudo apt-get autoremove -y
        sudo apt-get autoclean
        sudo apt-get clean
        ;;
esac

# Remove orphaned packages (Arch only)
if [ "$DISTRO_ID" == "arch" ]; then
    local orphans
    orphans=$(pacman -Qtdq 2>/dev/null)
    if [ -n "$orphans" ]; then
        echo "Removing orphaned packages: $orphans"
        sudo pacman -Rns --noconfirm $orphans
    fi
fi

# Clean temporary files
sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true
sudo find /var/tmp -type f -atime +7 -delete 2>/dev/null || true

# Clean journal logs
sudo journalctl --vacuum-time=7d >/dev/null 2>&1 || true

echo "System cleanup completed"
EOF

    chmod +x /tmp/cleanup-system.sh
    sudo mv /tmp/cleanup-system.sh /usr/local/bin/cleanup-system
    log_success "System cleanup script created at /usr/local/bin/cleanup-system"

    # Create weekly cleanup cron job
    if ! crontab -l 2>/dev/null | grep -q "cleanup-system"; then
        (crontab -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/cleanup-system") | crontab -
        log_success "Weekly cleanup cron job created"
    fi
}

maintenance_configure_monitoring() {
    step "Configuring System Monitoring"

    # Install monitoring tools
    local monitoring_packages=(
        "htop"
        "iotop"
        "nethogs"
        "lsof"
        "strace"
        "iotop"
    )

    for package in "${monitoring_packages[@]}"; do
        if ! install_pkg "$package"; then
            log_warn "Failed to install monitoring package: $package"
        else
            log_success "Installed monitoring package: $package"
        fi
    done

    # Create system monitoring script
    cat > /tmp/monitor-system.sh << 'EOF'
#!/bin/bash
# System monitoring script

echo "=== System Status Report ==="
echo "Date: $(date)"
echo ""

echo "=== CPU Usage ==="
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - $1"%"}'
echo ""

echo "=== Memory Usage ==="
free -h | grep "Mem:" | awk '{printf "Memory Usage: %s/%s (%.2f%%)\n", $3, $2, $3/$2*100}'
echo ""

echo "=== Disk Usage ==="
df -h | grep -E "^/dev/" | awk '{print "Disk Usage (" $1 "): " $3 "/" $2 " (" $5 ")"}'
echo ""

echo "=== Top Processes ==="
ps aux --sort=-%cpu | head -6
echo ""

echo "=== Network Connections ==="
ss -tuln | head -10
echo ""

echo "=== System Load ==="
uptime
echo ""
EOF

    chmod +x /tmp/monitor-system.sh
    sudo mv /tmp/monitor-system.sh /usr/local/bin/monitor-system
    log_success "System monitoring script created at /usr/local/bin/monitor-system"
}

maintenance_configure_backup() {
    step "Configuring Backup Solutions"

    # Install backup tools
    local backup_packages=(
        "rsync"
        "tar"
        "gzip"
        "bzip2"
        "xz-utils"
    )

    for package in "${backup_packages[@]}"; do
        if ! install_pkg "$package"; then
            log_warn "Failed to install backup package: $package"
        else
            log_success "Installed backup package: $package"
        fi
    done

    # Create backup script
    cat > /tmp/create-backup.sh << 'EOF'
#!/bin/bash
# System backup script

BACKUP_DIR="$HOME/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="system_backup_$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "Creating system backup..."
echo "Backup location: $BACKUP_DIR/$BACKUP_FILE"

# Create backup of important directories
tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
    --exclude="$HOME/.cache" \
    --exclude="$HOME/.local/share/Trash" \
    --exclude="$HOME/.mozilla/firefox/*/Cache*" \
    --exclude="$HOME/.config/google-chrome/Default/Cache*" \
    --exclude="$HOME/.config/chromium/Default/Cache*" \
    "$HOME/Documents" \
    "$HOME/Pictures" \
    "$HOME/.config" \
    "$HOME/.ssh" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "Backup completed successfully!"
    echo "Backup size: $(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)"
else
    echo "Backup failed!"
fi
EOF

    chmod +x /tmp/create-backup.sh
    sudo mv /tmp/create-backup.sh /usr/local/bin/create-backup
    log_success "Backup script created at /usr/local/bin/create-backup"
}

maintenance_configure_log_rotation() {
    step "Configuring Log Rotation"

    # Configure logrotate for custom scripts
    if [ ! -f /etc/logrotate.d/linuxinstaller ]; then
        sudo tee /etc/logrotate.d/linuxinstaller > /dev/null << 'EOF'
/var/log/linuxinstaller.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
        log_success "Log rotation configured for linuxinstaller.log"
    fi
}

maintenance_setup_health_check() {
    step "Setting up System Health Checks"

    # Create health check script
    cat > /tmp/health-check.sh << 'EOF'
#!/bin/bash
# System health check script

echo "=== System Health Check ==="
echo "Date: $(date)"
echo ""

# Check disk space
echo "=== Disk Space ==="
df -h | awk 'NR>1 {if($5+0 > 80) print "WARNING: " $6 " is " $5 " full"; else print "OK: " $6 " is " $5 " used"}'
echo ""

# Check memory usage
echo "=== Memory Usage ==="
free -h | awk 'NR==2 {if($3/$2*100 > 80) print "WARNING: Memory is " int($3/$2*100) "% full"; else print "OK: Memory is " int($3/$2*100) "% used"}'
echo ""

# Check system load
echo "=== System Load ==="
load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
cpu_cores=$(nproc)
load_percent=$(echo "$load_avg $cpu_cores" | awk '{printf "%.0f", $1/$2*100}')
if [ "$load_percent" -gt 80 ]; then
    echo "WARNING: System load is high ($load_percent%)"
else
    echo "OK: System load is normal ($load_percent%)"
fi
echo ""

# Check failed services
echo "=== Failed Services ==="
failed_services=$(systemctl --failed --no-legend | wc -l)
if [ "$failed_services" -gt 0 ]; then
    echo "WARNING: $failed_services failed services found:"
    systemctl --failed --no-legend
else
    echo "OK: No failed services"
fi
echo ""

# Check disk I/O
echo "=== Disk I/O ==="
if command -v iostat >/dev/null 2>&1; then
    iostat -x 1 1 | awk '/^[sv]d[a-z]/{if($10 > 80) print "WARNING: " $1 " I/O wait is " $10 "%"; else print "OK: " $1 " I/O wait is " $10 "%"}'
else
    echo "iostat not available, skipping disk I/O check"
fi
echo ""

echo "=== Health Check Complete ==="
EOF

    chmod +x /tmp/health-check.sh
    sudo mv /tmp/health-check.sh /usr/local/bin/health-check
    log_success "Health check script created at /usr/local/bin/health-check"

    # Create daily health check cron job
    if ! crontab -l 2>/dev/null | grep -q "health-check"; then
        (crontab -l 2>/dev/null; echo "0 6 * * * /usr/local/bin/health-check | mail -s 'Daily Health Check' $USER") | crontab -
        log_success "Daily health check cron job created"
    fi
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

    # Configure automatic updates
    if ! is_step_complete "maintenance_configure_automatic_updates"; then
        maintenance_configure_automatic_updates
        mark_step_complete "maintenance_configure_automatic_updates"
    fi

    # Configure cleanup
    if ! is_step_complete "maintenance_configure_cleanup"; then
        maintenance_configure_cleanup
        mark_step_complete "maintenance_configure_cleanup"
    fi

    # Configure monitoring
    if ! is_step_complete "maintenance_configure_monitoring"; then
        maintenance_configure_monitoring
        mark_step_complete "maintenance_configure_monitoring"
    fi

    # Configure backup
    if ! is_step_complete "maintenance_configure_backup"; then
        maintenance_configure_backup
        mark_step_complete "maintenance_configure_backup"
    fi

    # Configure log rotation
    if ! is_step_complete "maintenance_configure_log_rotation"; then
        maintenance_configure_log_rotation
        mark_step_complete "maintenance_configure_log_rotation"
    fi

    # Setup health check
    if ! is_step_complete "maintenance_setup_health_check"; then
        maintenance_setup_health_check
        mark_step_complete "maintenance_setup_health_check"
    fi

    log_success "Maintenance configuration completed"
}

# Export functions for use by main installer
export -f maintenance_main_config
export -f maintenance_install_packages
export -f maintenance_configure_btrfs_snapshots
export -f maintenance_configure_automatic_updates
export -f maintenance_configure_cleanup
export -f maintenance_configure_monitoring
export -f maintenance_configure_backup
export -f maintenance_configure_log_rotation
export -f maintenance_setup_health_check
