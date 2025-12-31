#!/bin/bash
set -uo pipefail

# Performance Optimization Module for LinuxInstaller
# Based on best practices from all installers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Performance-specific package lists
PERFORMANCE_ESSENTIALS=(
    "zram-generator"
    "btrfs-assistant"
    "btrfsmaintenance"
)

PERFORMANCE_ARCH=(
    "linux-lts"
    "linux-lts-headers"
    "snap-pac"
    "snapper"
)

PERFORMANCE_FEDORA=(
    "btrfs-progs"
    "fstrim"
)

PERFORMANCE_DEBIAN=(
    "btrfs-tools"
    "fstrim"
)

# Performance configuration files
PERFORMANCE_CONFIGS_DIR="$SCRIPT_DIR/../configs"

# =============================================================================
# PERFORMANCE CONFIGURATION FUNCTIONS
# =============================================================================

# Configure ZRAM compressed swap for performance
performance_configure_zram() {
    step "Configuring ZRAM for Performance"

    if ! command -v zramctl >/dev/null; then
        log_warn "zramctl not found, skipping ZRAM configuration"
        return
    fi

    if [ ! -f /etc/systemd/zram-generator.conf ]; then
        log_info "Creating ZRAM configuration..."
        sudo tee /etc/systemd/zram-generator.conf > /dev/null << EOF
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
EOF
        sudo systemctl daemon-reload
        if sudo systemctl start systemd-zram-setup@zram0.service >/dev/null 2>&1; then
            log_success "ZRAM configured and started"
        else
            log_warn "Failed to start ZRAM service"
        fi
    else
        log_info "ZRAM configuration already exists"
    fi
}

# Configure system swappiness for optimal performance
performance_configure_swappiness() {
    step "Configuring System Swappiness"

    # Optimize swappiness for performance
    if [ -f /proc/sys/vm/swappiness ]; then
        echo 10 | sudo tee /proc/sys/vm/swappiness >/dev/null 2>&1
        log_success "Optimized swappiness for performance (set to 10)"
    fi

    # Make it persistent
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf >/dev/null
    fi
}

# Configure CPU governor for optimal performance
performance_configure_cpu_governor() {
    step "Configuring CPU Governor"

    # Enable performance governor for better performance
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
        log_success "Set CPU governor to performance"
    fi

    # Make it persistent with a systemd service
    if [ ! -f /etc/systemd/system/cpu-performance.service ]; then
        sudo tee /etc/systemd/system/cpu-performance.service > /dev/null << EOF
[Unit]
Description=Set CPU Governor to Performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl enable cpu-performance.service >/dev/null 2>&1
        log_success "CPU performance service created and enabled"
    fi
}

# Configure filesystem performance optimizations
performance_configure_filesystem() {
    step "Configuring Filesystem Performance"

    # Enable TRIM for SSDs
    if [ -f /sys/block/*/queue/discard_max_bytes ]; then
        sudo systemctl enable --now fstrim.timer >/dev/null 2>&1
        log_success "Enabled TRIM for SSD optimization"
    fi

    # Optimize mount options for SSDs
    if mount | grep -q " / ext4"; then
        local current_mount=$(mount | grep " / ext4" | awk '{print $1}')
        if [ -n "$current_mount" ]; then
            # Add performance mount options
            if ! grep -q "noatime" /etc/fstab; then
                sudo sed -i 's|ext4 defaults|ext4 defaults,noatime|' /etc/fstab 2>/dev/null || true
                log_success "Added noatime mount option for performance"
            fi
        fi
    fi
}

# Configure network performance settings
performance_configure_network() {
    step "Configuring Network Performance"

    # Optimize network settings
    if [ ! -f /etc/sysctl.d/99-performance.conf ]; then
        sudo tee /etc/sysctl.d/99-performance.conf > /dev/null << EOF
# Performance optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF
        sudo sysctl -p /etc/sysctl.d/99-performance.conf >/dev/null 2>&1
        log_success "Network performance optimized"
    fi
}

# Configure kernel parameters for performance
performance_configure_kernel() {
    step "Configuring Kernel Performance"

    # Optimize kernel parameters for performance
    if [ ! -f /etc/sysctl.d/99-kernel-performance.conf ]; then
        sudo tee /etc/sysctl.d/99-kernel-performance.conf > /dev/null << EOF
# Kernel performance optimizations
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.dirty_expire_centisecs = 100
vm.dirty_writeback_centisecs = 50
vm.vfs_cache_pressure = 50
kernel.sched_migration_cost_ns = 500000
kernel.sched_wakeup_granularity_ns = 1000000
EOF
        sudo sysctl -p /etc/sysctl.d/99-kernel-performance.conf >/dev/null 2>&1
        log_success "Kernel performance optimized"
    fi
}

# Configure systemd services for performance
performance_configure_services() {
    step "Configuring Service Performance"

    # Disable unnecessary services for performance
    local services_to_disable=(
        "bluetooth"
        "cups"
        "avahi-daemon"
        "ModemManager"
    )

    for service in "${services_to_disable[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            if ! systemctl is-enabled "$service" >/dev/null 2>&1; then
                sudo systemctl disable "$service" >/dev/null 2>&1
                log_info "Disabled service: $service"
            fi
        fi
    done

    # Enable essential services
    local services_to_enable=(
        "cronie"
        "sshd"
        "fstrim.timer"
    )

    for service in "${services_to_enable[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            if ! sudo systemctl is-enabled "$service" >/dev/null 2>&1; then
                sudo systemctl enable --now "$service" >/dev/null 2>&1
                log_success "Enabled service: $service"
            fi
        fi
    done
}

# Install performance optimization packages for all distributions
performance_install_performance_packages() {
    step "Installing Performance Packages"

    log_info "Installing performance essential packages..."
    for package in "${PERFORMANCE_ESSENTIALS[@]}"; do
        if ! install_pkg "$package"; then
            log_warn "Failed to install performance package: $package"
        else
            log_success "Installed performance package: $package"
        fi
    done

    # Install distribution-specific performance packages
    case "$DISTRO_ID" in
        "arch")
            log_info "Installing Arch-specific performance packages..."
            for package in "${PERFORMANCE_ARCH[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Arch performance package: $package"
                else
                    log_success "Installed Arch performance package: $package"
                fi
            done
            ;;
        "fedora")
            log_info "Installing Fedora-specific performance packages..."
            for package in "${PERFORMANCE_FEDORA[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Fedora performance package: $package"
                else
                    log_success "Installed Fedora performance package: $package"
                fi
            done
            ;;
        "debian"|"ubuntu")
            log_info "Installing Debian/Ubuntu-specific performance packages..."
            for package in "${PERFORMANCE_DEBIAN[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Debian performance package: $package"
                else
                    log_success "Installed Debian performance package: $package"
                fi
            done
            ;;
    esac
}

# Configure Btrfs filesystem performance optimizations
performance_configure_btrfs() {
    step "Configuring Btrfs Performance"

    if is_btrfs_system; then
        log_info "Btrfs filesystem detected, configuring performance optimizations..."

        # Enable Btrfs compression
        local btrfs_mount=$(mount | grep " btrfs " | awk '{print $3}' | head -1)
        if [ -n "$btrfs_mount" ]; then
            # Add compression mount option
            if ! grep -q "compress=zstd" /etc/fstab; then
                sudo sed -i "s|btrfs.*defaults|btrfs defaults,compress=zstd|" /etc/fstab 2>/dev/null || true
                log_success "Added Btrfs compression mount option"
            fi
        fi

        # Configure Btrfs maintenance
        if [ -f /usr/bin/btrfs ]; then
            sudo systemctl enable --now btrfs-scrub@-.timer >/dev/null 2>&1
            sudo systemctl enable --now btrfs-balance@-.timer >/dev/null 2>&1
            sudo systemctl enable --now btrfs-defrag@-.timer >/dev/null 2>&1
            log_success "Btrfs maintenance services enabled"
        fi
    else
        log_info "Btrfs filesystem not detected, skipping Btrfs optimizations"
    fi
}

# Configure system settings for optimal gaming performance
performance_configure_gaming() {
    step "Configuring Gaming Performance"

    if [ "$INSTALL_MODE" == "gaming" ] || [ "$INSTALL_MODE" == "standard" ]; then
        # Enable performance governor for gaming
        if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
            echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
            log_success "Set CPU governor to performance for gaming"
        fi

        # Optimize GPU settings
        if command -v nvidia-settings >/dev/null 2>&1; then
            log_info "Configuring NVIDIA settings for gaming..."
            sudo nvidia-settings -a GPUPowerMizerMode=1 >/dev/null 2>&1 || true
            log_success "NVIDIA performance mode enabled"
        fi

        # Configure audio latency
        if [ -f /etc/pulse/daemon.conf ]; then
            sudo sed -i 's/^;default-fragments = 4/default-fragments = 2/' /etc/pulse/daemon.conf 2>/dev/null || true
            sudo sed -i 's/^;default-fragment-size-msec = 25/default-fragment-size-msec = 10/' /etc/pulse/daemon.conf 2>/dev/null || true
            log_success "Audio latency optimized for gaming"
        fi
    fi
}

# =============================================================================
# MAIN PERFORMANCE CONFIGURATION FUNCTION
# =============================================================================

performance_main_config() {
    log_info "Starting performance optimization..."

    # Install performance packages
    if ! is_step_complete "performance_install_packages"; then
        performance_install_performance_packages
        mark_step_complete "performance_install_packages"
    fi

    # Configure ZRAM
    if ! is_step_complete "performance_configure_zram"; then
        performance_configure_zram
        mark_step_complete "performance_configure_zram"
    fi

    # Configure swappiness
    if ! is_step_complete "performance_configure_swappiness"; then
        performance_configure_swappiness
        mark_step_complete "performance_configure_swappiness"
    fi

    # Configure CPU governor
    if ! is_step_complete "performance_configure_cpu_governor"; then
        performance_configure_cpu_governor
        mark_step_complete "performance_configure_cpu_governor"
    fi

    # Configure filesystem
    if ! is_step_complete "performance_configure_filesystem"; then
        performance_configure_filesystem
        mark_step_complete "performance_configure_filesystem"
    fi

    # Configure network
    if ! is_step_complete "performance_configure_network"; then
        performance_configure_network
        mark_step_complete "performance_configure_network"
    fi

    # Configure kernel
    if ! is_step_complete "performance_configure_kernel"; then
        performance_configure_kernel
        mark_step_complete "performance_configure_kernel"
    fi

    # Configure services
    if ! is_step_complete "performance_configure_services"; then
        performance_configure_services
        mark_step_complete "performance_configure_services"
    fi

    # Configure Btrfs
    if ! is_step_complete "performance_configure_btrfs"; then
        performance_configure_btrfs
        mark_step_complete "performance_configure_btrfs"
    fi

    # Configure gaming performance
    if ! is_step_complete "performance_configure_gaming"; then
        performance_configure_gaming
        mark_step_complete "performance_configure_gaming"
    fi

    log_success "Performance optimization completed"
}

# Export functions for use by main installer
export -f performance_main_config
export -f performance_configure_zram
export -f performance_configure_swappiness
export -f performance_configure_cpu_governor
export -f performance_configure_filesystem
export -f performance_configure_network
export -f performance_configure_kernel
export -f performance_configure_services
export -f performance_install_performance_packages
export -f performance_configure_btrfs
export -f performance_configure_gaming
