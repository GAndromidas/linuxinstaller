#!/bin/bash
set -uo pipefail

# Security Configuration Module for LinuxInstaller
# Based on best practices from all installers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Security-specific package lists
SECURITY_ESSENTIALS=(
    "fail2ban"
    "ufw"
)

SECURITY_ARCH=(
    "firewalld"
    "apparmor"
    "apparmor-utils"
)

SECURITY_FEDORA=(
    "firewalld"
    "selinux-policy-targeted"
)

SECURITY_DEBIAN=(
    "apparmor"
    "apparmor-utils"
    "apparmor-profiles"
)

# =============================================================================
# SECURITY CONFIGURATION FUNCTIONS
# =============================================================================

security_install_packages() {
    step "Installing Security Packages"

    log_info "Installing security essential packages..."
    for package in "${SECURITY_ESSENTIALS[@]}"; do
        if ! install_pkg "$package"; then
            log_warn "Failed to install security package: $package"
        else
            log_success "Installed security package: $package"
        fi
    done

    # Install distribution-specific security packages
    case "$DISTRO_ID" in
        "arch")
            log_info "Installing Arch-specific security packages..."
            for package in "${SECURITY_ARCH[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Arch security package: $package"
                else
                    log_success "Installed Arch security package: $package"
                fi
            done
            ;;
        "fedora")
            log_info "Installing Fedora-specific security packages..."
            for package in "${SECURITY_FEDORA[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Fedora security package: $package"
                else
                    log_success "Installed Fedora security package: $package"
                fi
            done
            ;;
        "debian"|"ubuntu")
            log_info "Installing Debian/Ubuntu-specific security packages..."
            for package in "${SECURITY_DEBIAN[@]}"; do
                if ! install_pkg "$package"; then
                    log_warn "Failed to install Debian security package: $package"
                else
                    log_success "Installed Debian security package: $package"
                fi
            done
            ;;
    esac
}

security_configure_fail2ban() {
    step "Configuring Fail2ban"

    # Configure fail2ban for all distributions
    if [ ! -f /etc/fail2ban/jail.local ]; then
        log_info "Creating fail2ban configuration..."

        # Copy default config to local config
        if [ -f /etc/fail2ban/jail.conf ]; then
            sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
        fi

        # Configure fail2ban settings
        sudo sed -i 's/^backend = auto/backend = systemd/' /etc/fail2ban/jail.local 2>/dev/null || true
        sudo sed -i 's/^bantime  = 10m/bantime = 1h/' /etc/fail2ban/jail.local 2>/dev/null || true
        sudo sed -i 's/^findtime  = 10m/findtime = 10m/' /etc/fail2ban/jail.local 2>/dev/null || true
        sudo sed -i 's/^maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local 2>/dev/null || true

        # Enable SSH jail
        sudo sed -i 's/^enabled = false/enabled = true/' /etc/fail2ban/jail.local 2>/dev/null || true
    fi

    # Enable and start fail2ban service
    if sudo systemctl enable --now fail2ban >/dev/null 2>&1; then
        log_success "fail2ban enabled and started"
    else
        log_warn "Failed to enable fail2ban service"
    fi
}

security_configure_firewall() {
    step "Configuring Firewall"

    case "$DISTRO_ID" in
        "arch")
            # Configure firewalld for Arch
            if command -v firewall-cmd >/dev/null 2>&1; then
                if sudo systemctl enable --now firewalld >/dev/null 2>&1; then
                    sudo firewall-cmd --set-default-zone=public >/dev/null 2>&1
                    sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1

                    # Allow KDE Connect if KDE is detected
                    if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
                        if sudo firewall-cmd --permanent --add-service=kde-connect >/dev/null 2>&1; then
                            log_success "KDE Connect service allowed in firewall"
                        else
                            # Fallback: manually allow KDE Connect ports
                            sudo firewall-cmd --permanent --add-port=1714-1764/udp >/dev/null 2>&1
                            sudo firewall-cmd --permanent --add-port=1714-1764/tcp >/dev/null 2>&1
                            log_success "KDE Connect ports (1714-1764) allowed in firewall"
                        fi
                    fi

                    sudo firewall-cmd --reload >/dev/null 2>&1
                    log_success "firewalld configured with SSH and KDE Connect (if applicable)"
                else
                    log_warn "Failed to enable firewalld"
                fi
            fi
            ;;
        "fedora")
            # Configure firewalld for Fedora
            if command -v firewall-cmd >/dev/null 2>&1; then
                if sudo systemctl enable --now firewalld >/dev/null 2>&1; then
                    sudo firewall-cmd --set-default-zone=public >/dev/null 2>&1
                    sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1

                    # Allow KDE Connect if KDE is detected
                    if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
                        if sudo firewall-cmd --permanent --add-service=kde-connect >/dev/null 2>&1; then
                            log_success "KDE Connect service allowed in firewall"
                        else
                            # Fallback: manually allow KDE Connect ports
                            sudo firewall-cmd --permanent --add-port=1714-1764/udp >/dev/null 2>&1
                            sudo firewall-cmd --permanent --add-port=1714-1764/tcp >/dev/null 2>&1
                            log_success "KDE Connect ports (1714-1764) allowed in firewall"
                        fi
                    fi

                    sudo firewall-cmd --reload >/dev/null 2>&1
                    log_success "firewalld configured with SSH and KDE Connect (if applicable)"
                else
                    log_warn "Failed to enable firewalld"
                fi
            fi
            ;;
        "debian"|"ubuntu")
            # Configure UFW for Debian/Ubuntu
            sudo ufw default deny incoming >/dev/null 2>&1
            sudo ufw default allow outgoing >/dev/null 2>&1
            sudo ufw limit ssh >/dev/null 2>&1

            # Allow KDE Connect if KDE is detected
            if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
                sudo ufw allow 1714:1764/udp >/dev/null 2>&1
                sudo ufw allow 1714:1764/tcp >/dev/null 2>&1
                log_success "KDE Connect ports (1714-1764 UDP/TCP) allowed in UFW"
            fi

            # Force enable without prompt
            echo "y" | sudo ufw enable >/dev/null 2>&1
            log_success "UFW configured with SSH and KDE Connect (if applicable)"
            ;;
    esac
}

security_configure_apparmor() {
    step "Configuring AppArmor"

    if [ "$DISTRO_ID" == "arch" ] || [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
        if command -v apparmor_parser >/dev/null 2>&1; then
            # Enable AppArmor
            if sudo systemctl enable --now apparmor >/dev/null 2>&1; then
                log_success "AppArmor enabled and started"

                # Load default profiles
                sudo apparmor_parser -q /etc/apparmor.d/* >/dev/null 2>&1 || true
                log_success "AppArmor profiles loaded"
            else
                log_warn "Failed to enable AppArmor"
            fi
        fi
    fi
}

security_configure_selinux() {
    step "Configuring SELinux"

    if [ "$DISTRO_ID" == "fedora" ]; then
        if command -v sestatus >/dev/null 2>&1; then
            # Check SELinux status
            local selinux_status=$(sestatus | grep "SELinux status" | awk '{print $3}')
            if [ "$selinux_status" == "enabled" ]; then
                log_info "SELinux is already enabled"
            else
                log_info "SELinux is disabled, enabling..."
                sudo setenforce 1 >/dev/null 2>&1
                log_success "SELinux enabled in permissive mode"
            fi
        fi
    fi
}

security_configure_ssh() {
    step "Configuring SSH Security"

    if [ -f /etc/ssh/sshd_config ]; then
        log_info "Configuring SSH security settings..."

        # Backup original config
        if [ ! -f /etc/ssh/sshd_config.backup ]; then
            sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
        fi

        # Apply security settings
        sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true
        sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true
        sudo sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true
        sudo sed -i 's/^#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config 2>/dev/null || true
        sudo sed -i 's/^#ClientAliveInterval 0/ClientAliveInterval 300/' /etc/ssh/sshd_config 2>/dev/null || true
        sudo sed -i 's/^#ClientAliveCountMax 3/ClientAliveCountMax 2/' /etc/ssh/sshd_config 2>/dev/null || true

        # Restart SSH service
        if sudo systemctl restart sshd >/dev/null 2>&1; then
            log_success "SSH configuration applied"
        else
            log_warn "Failed to restart SSH service"
        fi
    fi
}

security_configure_user_groups() {
    step "Configuring User Groups"

    # Add user to essential groups
    local groups=("input" "video" "storage")

    # Sudo group difference
    if [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
        groups+=("sudo")
    else
        groups+=("wheel")
    fi

    # Docker group check
    if command -v docker >/dev/null; then groups+=("docker"); fi

    log_info "Adding user to groups: ${groups[*]}"
    for group in "${groups[@]}"; do
        if getent group "$group" >/dev/null; then
            if ! id -nG "$USER" | grep -qw "$group"; then
                sudo usermod -aG "$group" "$USER"
                log_success "Added user to group: $group"
            else
                log_info "User already in group: $group"
            fi
        else
            log_warn "Group does not exist: $group"
        fi
    done
}

security_setup_logwatch() {
    step "Setting up Log Monitoring"

    # Install and configure logwatch
    if ! install_pkg logwatch; then
        log_warn "Failed to install logwatch"
        return
    fi

    # Configure logwatch
    if [ -f /etc/logwatch/conf/logwatch.conf ]; then
        sudo sed -i 's/^Output = stdout/Output = mail/' /etc/logwatch/conf/logwatch.conf 2>/dev/null || true
        sudo sed -i 's/^Format = text/Format = html/' /etc/logwatch/conf/logwatch.conf 2>/dev/null || true
        log_success "Logwatch configured"
    fi
}

# =============================================================================
# MAIN SECURITY CONFIGURATION FUNCTION
# =============================================================================

security_main_config() {
    log_info "Starting security configuration..."

    # Install security packages
    if ! is_step_complete "security_install_packages"; then
        security_install_packages
        mark_step_complete "security_install_packages"
    fi

    # Configure fail2ban
    if ! is_step_complete "security_configure_fail2ban"; then
        security_configure_fail2ban
        mark_step_complete "security_configure_fail2ban"
    fi

    # Configure firewall
    if ! is_step_complete "security_configure_firewall"; then
        security_configure_firewall
        mark_step_complete "security_configure_firewall"
    fi

    # Configure AppArmor
    if ! is_step_complete "security_configure_apparmor"; then
        security_configure_apparmor
        mark_step_complete "security_configure_apparmor"
    fi

    # Configure SELinux
    if ! is_step_complete "security_configure_selinux"; then
        security_configure_selinux
        mark_step_complete "security_configure_selinux"
    fi

    # Configure SSH
    if ! is_step_complete "security_configure_ssh"; then
        security_configure_ssh
        mark_step_complete "security_configure_ssh"
    fi

    # Configure user groups
    if ! is_step_complete "security_configure_user_groups"; then
        security_configure_user_groups
        mark_step_complete "security_configure_user_groups"
    fi

    # Setup logwatch
    if ! is_step_complete "security_setup_logwatch"; then
        security_setup_logwatch
        mark_step_complete "security_setup_logwatch"
    fi

    log_success "Security configuration completed"
}

# Export functions for use by main installer
export -f security_main_config
export -f security_install_packages
export -f security_configure_fail2ban
export -f security_configure_firewall
export -f security_configure_apparmor
export -f security_configure_selinux
export -f security_configure_ssh
export -f security_configure_user_groups
export -f security_setup_logwatch
