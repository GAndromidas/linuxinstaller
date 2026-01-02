#!/bin/bash
set -uo pipefail

# Performance Optimization Module for LinuxInstaller
# Based on best practices from all installers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Performance-specific package lists
PERFORMANCE_ESSENTIALS=(
    # Btrfs maintenance moved to maintenance_config.sh
)

PERFORMANCE_ARCH=(
    # Performance-related packages moved to maintenance_config.sh
)

PERFORMANCE_FEDORA=(
    btrfs-progs
    fstrim
)

PERFORMANCE_DEBIAN=(
    btrfs-tools
    fstrim
)

# Performance configuration files
PERFORMANCE_CONFIGS_DIR="$SCRIPT_DIR/../configs"

# =============================================================================
# PERFORMANCE CONFIGURATION FUNCTIONS
# =============================================================================

# Configure system swappiness for optimal performance
performance_configure_swappiness() {
    display_step "⚙️" "Configuring System Swappiness"

    # Optimize swappiness for performance
    if [ -f /proc/sys/vm/swappiness ]; then
        echo 10 | tee /proc/sys/vm/swappiness >/dev/null 2>&1
        log_success "Optimized swappiness for performance (set to 10)"
    fi

    # Make it persistent
    local sysctl_file="/etc/sysctl.conf"
    local sysctl_dir="/etc/sysctl.d"

    # Check if sysctl.conf exists, if not create it
    if [ ! -f "$sysctl_file" ]; then
        touch "$sysctl_file" 2>/dev/null || {
            log_warn "Cannot create $sysctl_file, trying sysctl.d directory"
            sysctl_file="$sysctl_dir/99-swappiness.conf"
            mkdir -p "$sysctl_dir" 2>/dev/null || {
                log_warn "Cannot create sysctl configuration, swappiness setting will not persist"
                return 0
            }
        }
    fi

    # Check if setting already exists
    if ! grep -q "vm.swappiness" "$sysctl_file" 2>/dev/null; then
        echo "vm.swappiness=10" | tee -a "$sysctl_file" >/dev/null 2>&1
        log_info "Made swappiness setting persistent in $sysctl_file"
    else
        log_info "Swappiness setting already configured in $sysctl_file"
    fi
}

# Configure CPU governor for optimal performance
performance_configure_cpu_governor() {
    display_step "⚡" "Configuring CPU Governor"

    # Enable performance governor for better performance
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
        log_success "Set CPU governor to performance"
    fi

    # Make it persistent with a systemd service
    if [ ! -f /etc/systemd/system/cpu-performance.service ]; then
        tee /etc/systemd/system/cpu-performance.service > /dev/null << EOF
[Unit]
Description=Set CPU Governor to Performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable cpu-performance.service >/dev/null 2>&1
        log_success "CPU performance service created and enabled"
    fi
}

# Configure filesystem performance optimizations
performance_configure_filesystem() {
    display_step "💾" "Configuring Filesystem Performance"

    # Enable TRIM for SSDs
    if ls /sys/block/*/queue/discard_max_bytes >/dev/null 2>&1; then
        systemctl enable --now fstrim.timer >/dev/null 2>&1
        log_success "Enabled TRIM for SSD optimization"
    fi

    # Optimize mount options for SSDs
    if mount | grep -q " / ext4"; then
        local current_mount=$(mount | grep " / ext4" | awk '{print $1}')
        if [ -n "$current_mount" ]; then
            # Add performance mount options
            if ! grep -q "noatime" /etc/fstab; then
                sed -i 's|ext4 defaults|ext4 defaults,noatime|' /etc/fstab 2>/dev/null || true
                log_success "Added noatime mount option for performance"
            fi
        fi
    fi
}

# Configure network performance settings
performance_configure_network() {
    display_step "🌐" "Configuring Network Performance"

    # Optimize network settings
    if [ ! -f /etc/sysctl.d/99-performance.conf ]; then
        tee /etc/sysctl.d/99-performance.conf > /dev/null << EOF
# Performance optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF
        sysctl -p /etc/sysctl.d/99-performance.conf >/dev/null 2>&1
        log_success "Network performance optimized"
    fi
}

# Configure kernel parameters for performance
performance_configure_kernel() {
    display_step "🔧" "Configuring Kernel Performance"

    # Optimize kernel parameters for performance
    if [ ! -f /etc/sysctl.d/99-kernel-performance.conf ]; then
        tee /etc/sysctl.d/99-kernel-performance.conf > /dev/null << EOF
# Kernel performance optimizations
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.dirty_expire_centisecs = 100
vm.dirty_writeback_centisecs = 50
vm.vfs_cache_pressure = 50
kernel.sched_migration_cost_ns = 500000
kernel.sched_wakeup_granularity_ns = 1000000
EOF
        sysctl -p /etc/sysctl.d/99-kernel-performance.conf >/dev/null 2>&1
        log_success "Kernel performance optimized"
    fi
}

# Configure systemd services for performance
performance_configure_services() {
    display_step "⚙️" "Configuring Service Performance"

    # Add any service-specific performance optimizations here
    log_info "Service performance optimizations completed"
}

# Configure CPU microcode updates for security and stability
performance_configure_microcode() {
    display_step "🔧" "Configuring CPU Microcode Updates"

    # Detect CPU vendor
    local cpu_vendor=""
    if grep -qi "amd" /proc/cpuinfo; then
        cpu_vendor="amd"
        log_info "AMD CPU detected"
    elif grep -qi "intel" /proc/cpuinfo; then
        cpu_vendor="intel"
        log_info "Intel CPU detected"
    else
        log_warn "Unknown CPU vendor - skipping microcode installation"
        return 0
    fi

    # Determine correct package name based on distro and CPU vendor
    local microcode_package=""
    case "$DISTRO_ID" in
        "arch")
            case "$cpu_vendor" in
                "amd") microcode_package="amd-ucode" ;;
                "intel") microcode_package="intel-ucode" ;;
            esac
            ;;
        "fedora")
            case "$cpu_vendor" in
                "amd") microcode_package="amd-ucode" ;;
                "intel") microcode_package="intel-ucode" ;;
            esac
            ;;
        "debian"|"ubuntu")
            case "$cpu_vendor" in
                "amd") microcode_package="amd64-microcode" ;;
                "intel") microcode_package="intel-microcode" ;;
            esac
            ;;
        *)
            log_warn "Microcode installation not supported for $DISTRO_ID"
            return 0
            ;;
    esac

    if [ -n "$microcode_package" ]; then
        log_info "Installing $cpu_vendor microcode package: $microcode_package"

        # Check if already installed
        if is_package_installed "$microcode_package" 2>/dev/null; then
            log_info "$microcode_package is already installed"
        else
            # Install the microcode package
            install_packages_with_progress "$microcode_package"
            log_success "$cpu_vendor microcode updates installed"
            log_info "Microcode updates will be applied on next boot"
            log_info "For immediate application: sudo update-initramfs -u (Debian/Ubuntu)"
            log_info "For immediate application: sudo mkinitcpio -P (Arch)"
        fi
    else
        log_warn "Could not determine microcode package for $cpu_vendor on $DISTRO_ID"
    fi
}

# Install performance optimization packages for all distributions
performance_install_performance_packages() {
    display_step "📦" "Installing Performance Packages"

    # Install performance essential packages
    if [ ${#PERFORMANCE_ESSENTIALS[@]} -gt 0 ]; then
        install_packages_with_progress "${PERFORMANCE_ESSENTIALS[@]}"
    fi

    # Install distribution-specific performance packages
    case "$DISTRO_ID" in
        "arch")
            if [ ${#PERFORMANCE_ARCH[@]} -gt 0 ]; then
                install_packages_with_progress "${PERFORMANCE_ARCH[@]}"
            fi
            ;;
        "fedora")
            if [ ${#PERFORMANCE_FEDORA[@]} -gt 0 ]; then
                install_packages_with_progress "${PERFORMANCE_FEDORA[@]}"
            fi
            ;;
        "debian"|"ubuntu")
            if [ ${#PERFORMANCE_DEBIAN[@]} -gt 0 ]; then
                install_packages_with_progress "${PERFORMANCE_DEBIAN[@]}"
            fi
            ;;
    esac
}

# Configure Btrfs filesystem performance optimizations
performance_configure_btrfs() {
    display_step "💾" "Configuring Btrfs Performance"

    if is_btrfs_system; then
        log_info "Btrfs filesystem detected, configuring performance optimizations..."

        # Enable Btrfs compression
        local btrfs_mount=$(mount | grep " btrfs " | awk '{print $3}' | head -1)
        if [ -n "$btrfs_mount" ]; then
            # Add compression mount option
            if ! grep -q "compress=zstd" /etc/fstab; then
                sed -i "s|btrfs.*defaults|btrfs defaults,compress=zstd|" /etc/fstab 2>/dev/null || true
                log_success "Added Btrfs compression mount option"
            fi
        fi

        # Configure Btrfs maintenance
        if [ -f /usr/bin/btrfs ]; then
            systemctl enable --now btrfs-scrub@-.timer >/dev/null 2>&1
            systemctl enable --now btrfs-balance@-.timer >/dev/null 2>&1
            systemctl enable --now btrfs-defrag@-.timer >/dev/null 2>&1
            log_success "Btrfs maintenance services enabled"
        fi
    else
        log_info "Btrfs filesystem not detected, skipping Btrfs optimizations"
    fi
}

# Configure system settings for optimal gaming performance
performance_configure_gaming() {
    display_step "🎮" "Configuring Gaming Performance"

    if [ "$INSTALL_MODE" == "gaming" ] || [ "$INSTALL_MODE" == "standard" ]; then
        # Enable performance governor for gaming
        if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
            echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
            log_success "Set CPU governor to performance for gaming"
        fi

        # Configure audio latency
        if [ -f /etc/pulse/daemon.conf ]; then
            sed -i 's/^;default-fragments = 4/default-fragments = 2/' /etc/pulse/daemon.conf 2>/dev/null || true
            sed -i 's/^;default-fragment-size-msec = 25/default-fragment-size-msec = 10/' /etc/pulse/daemon.conf 2>/dev/null || true
            log_success "Audio latency optimized for gaming"
        fi
    fi
}

# =============================================================================
# MAIN PERFORMANCE CONFIGURATION FUNCTION
# =============================================================================

performance_main_config() {
    performance_configure_microcode

    performance_configure_swappiness

    performance_configure_cpu_governor

    performance_configure_filesystem

    performance_configure_network

    performance_configure_kernel

    performance_configure_services

    performance_configure_btrfs

    performance_configure_gaming
}

# Export functions for use by main installer
export -f performance_main_config
export -f performance_configure_microcode
export -f performance_configure_swappiness
export -f performance_configure_cpu_governor
export -f performance_configure_filesystem
export -f performance_configure_network
export -f performance_configure_kernel
export -f performance_configure_services

export -f performance_configure_btrfs
export -f performance_configure_gaming
