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
    "ufw"
    "apparmor"
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

# Install security packages for all distributions
security_install_packages() {
    step "Installing Security Packages"

    # Install security essential packages
    if [ ${#SECURITY_ESSENTIALS[@]} -gt 0 ]; then
        install_packages_with_progress "${SECURITY_ESSENTIALS[@]}"
    fi

    # Install distribution-specific security packages
    case "$DISTRO_ID" in
        "arch")
            if [ ${#SECURITY_ARCH[@]} -gt 0 ]; then
                install_packages_with_progress "${SECURITY_ARCH[@]}"
            fi
            ;;
        "fedora")
            if [ ${#SECURITY_FEDORA[@]} -gt 0 ]; then
                install_packages_with_progress "${SECURITY_FEDORA[@]}"
            fi
            ;;
        "debian"|"ubuntu")
            if [ ${#SECURITY_DEBIAN[@]} -gt 0 ]; then
                install_packages_with_progress "${SECURITY_DEBIAN[@]}"
            fi
            ;;
    esac
}

# Configure Fail2ban intrusion prevention system
security_configure_fail2ban() {
    step "Configuring Fail2ban"

    # Configure fail2ban for all distributions
    if [ ! -f /etc/fail2ban/jail.local ]; then
        log_info "Creating fail2ban configuration..."

        # Copy default config to local config
        if [ -f /etc/fail2ban/jail.conf ]; then
            cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
        fi

        # Configure fail2ban settings
        sed -i 's/^backend = auto/backend = systemd/' /etc/fail2ban/jail.local 2>/dev/null || true
        sed -i 's/^bantime  = 10m/bantime = 1h/' /etc/fail2ban/jail.local 2>/dev/null || true
        sed -i 's/^findtime  = 10m/findtime = 10m/' /etc/fail2ban/jail.local 2>/dev/null || true
        sed -i 's/^maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local 2>/dev/null || true

        # Enable SSH jail
        sed -i 's/^enabled = false/enabled = true/' /etc/fail2ban/jail.local 2>/dev/null || true
    fi

    # Enable and start fail2ban service
    if systemctl enable --now fail2ban >/dev/null 2>&1; then
        log_success "fail2ban enabled and started"
    else
        log_warn "Failed to enable fail2ban service"
    fi
}

# Configure firewall (UFW for Arch/Debian/Ubuntu, firewalld for Fedora)
security_configure_firewall() {
    step "Configuring Firewall"

    case "$DISTRO_ID" in
        "arch")
            # Configure UFW for Arch
            ufw default deny incoming >/dev/null 2>&1
            ufw default allow outgoing >/dev/null 2>&1
            ufw limit ssh >/dev/null 2>&1

            # Allow KDE Connect if KDE is detected
            if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
                ufw allow 1714:1764/udp >/dev/null 2>&1
                ufw allow 1714:1764/tcp >/dev/null 2>&1
                log_success "KDE Connect ports (1714-1764 UDP/TCP) allowed in UFW"
            fi

            # Force enable without prompt, and ensure the ufw systemd service is enabled so rules persist across reboot
            echo "y" | ufw enable >/dev/null 2>&1 || true
            if command -v systemctl >/dev/null 2>&1; then
                if systemctl enable --now ufw >/dev/null 2>&1; then
                    log_success "UFW enabled and will start on boot"
                else
                    log_warn "Failed to enable ufw.service; firewall may not persist across reboot"
                fi
            fi
            log_success "UFW configured with SSH and KDE Connect (if applicable)"
            ;;
        "fedora")
            # Configure firewalld for Fedora
            if command -v firewall-cmd >/dev/null 2>&1; then
                if systemctl enable --now firewalld >/dev/null 2>&1; then
                    firewall-cmd --set-default-zone=public >/dev/null 2>&1
                    firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1

                    # Allow KDE Connect if KDE is detected
                    if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
                        if firewall-cmd --permanent --add-service=kde-connect >/dev/null 2>&1; then
                            log_success "KDE Connect service allowed in firewall"
                        else
                            # Fallback: manually allow KDE Connect ports
                            firewall-cmd --permanent --add-port=1714-1764/udp >/dev/null 2>&1
                            firewall-cmd --permanent --add-port=1714-1764/tcp >/dev/null 2>&1
                            log_success "KDE Connect ports (1714-1764) allowed in firewall"
                        fi
                    fi

                    firewall-cmd --reload >/dev/null 2>&1
                    log_success "firewalld configured with SSH and KDE Connect (if applicable)"
                else
                    log_warn "Failed to enable firewalld"
                fi
            fi
            ;;
        "debian"|"ubuntu")
            # Configure UFW for Debian/Ubuntu
            ufw default deny incoming >/dev/null 2>&1
            ufw default allow outgoing >/dev/null 2>&1
            ufw limit ssh >/dev/null 2>&1

            # Allow KDE Connect if KDE is detected
            if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
                ufw allow 1714:1764/udp >/dev/null 2>&1
                ufw allow 1714:1764/tcp >/dev/null 2>&1
                log_success "KDE Connect ports (1714-1764 UDP/TCP) allowed in UFW"
            fi

            # Force enable without prompt, and ensure the ufw systemd service is enabled so rules persist across reboot
            echo "y" | ufw enable >/dev/null 2>&1 || true
            if command -v systemctl >/dev/null 2>&1; then
                if systemctl enable --now ufw >/dev/null 2>&1; then
                    log_success "UFW enabled and will start on boot"
                else
                    log_warn "Failed to enable ufw.service; firewall may not persist across reboot"
                fi
            fi
            log_success "UFW configured with SSH and KDE Connect (if applicable)"
            ;;
    esac
}

# Configure AppArmor security framework
security_configure_apparmor() {
    step "Configuring AppArmor"

    if [ "$DISTRO_ID" == "arch" ] || [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
        if command -v apparmor_parser >/dev/null 2>&1; then
            # Enable AppArmor
            if systemctl enable --now apparmor >/dev/null 2>&1; then
                log_success "AppArmor enabled and started"

                # Load default profiles
                apparmor_parser -q /etc/apparmor.d/* >/dev/null 2>&1 || true
                log_success "AppArmor profiles loaded"
            else
                log_warn "Failed to enable AppArmor"
            fi
        fi
    fi
}

# Configure SELinux security framework (Fedora only)
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
                setenforce 1 >/dev/null 2>&1
                log_success "SELinux enabled in permissive mode"
            fi
        fi
    fi
}

# Configure SSH server security settings
security_configure_ssh() {
    step "Configuring SSH Security"

    if [ -f /etc/ssh/sshd_config ]; then
        log_info "Configuring SSH security settings..."

        # Apply security settings
        sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true
        sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true
        sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true
        sed -i 's/^#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config 2>/dev/null || true
        sed -i 's/^#ClientAliveInterval 0/ClientAliveInterval 300/' /etc/ssh/sshd_config 2>/dev/null || true
        sed -i 's/^#ClientAliveCountMax 3/ClientAliveCountMax 2/' /etc/ssh/sshd_config 2>/dev/null || true

        # Restart SSH service
        if systemctl restart sshd >/dev/null 2>&1; then
            log_success "SSH configuration applied"
        else
            log_warn "Failed to restart SSH service"
        fi
    fi
}

# Configure user group memberships for system access
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
                usermod -aG "$group" "$USER"
                log_success "Added user to group: $group"
            else
                log_info "User already in group: $group"
            fi
        else
            log_warn "Group does not exist: $group"
        fi
    done
}



# =============================================================================
# MAIN SECURITY CONFIGURATION FUNCTION
# =============================================================================

security_main_config() {
    log_info "Starting security configuration..."

    security_install_packages

    security_configure_fail2ban

    security_configure_firewall

    security_configure_apparmor

    security_configure_selinux

    security_configure_ssh

    security_configure_user_groups

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
