#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

setup_firewall_and_services() {
  step "Setting up firewall and services"

  # Firewall Logic: Prefer Firewalld if installed (Fedora default), else UFW (Ubuntu/Debian/Arch)
  if command -v firewalld >/dev/null 2>&1; then
    run_step "Configuring Firewalld" configure_firewalld
  else
    # Ensure UFW is installed if we are going to configure it
    install_packages_quietly ufw
    run_step "Configuring UFW" configure_ufw
  fi

  # Configure user groups
  run_step "Configuring user groups" configure_user_groups

  # Enable services
  run_step "Enabling system services" enable_services
  
  # ZRAM
  run_step "Configuring ZRAM" configure_zram
}

configure_firewalld() {
  if ! sudo systemctl enable --now firewalld; then
    log_error "Failed to start firewalld"
    return 1
  fi

  # Default secure zone
  sudo firewall-cmd --set-default-zone=public >/dev/null 2>&1
  # Allow SSH
  sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
  
  # Allow KDE Connect if needed
  if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
      sudo firewall-cmd --permanent --add-service=kde-connect >/dev/null 2>&1
  fi
  
  sudo firewall-cmd --reload >/dev/null 2>&1
  log_success "Firewalld configured."
}

configure_ufw() {
  # Enable UFW with defaults
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw limit ssh
  
  if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
      sudo ufw allow 1714:1764/udp
      sudo ufw allow 1714:1764/tcp
  fi
  
  # Force enable without prompt
  echo "y" | sudo ufw enable
  log_success "UFW configured."
}

configure_user_groups() {
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
          sudo usermod -aG "$group" "$USER"
      fi
  done
}

enable_services() {
    # Cron
    local cron_svc="cronie"
    if [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then cron_svc="cron"; fi
    
    if systemctl list-unit-files | grep -q "^$cron_svc"; then
        sudo systemctl enable --now "$cron_svc"
    fi
    
    # Bluetooth
    if command -v bluetoothd >/dev/null; then
        sudo systemctl enable --now bluetooth
    fi
    
    # SSH
    local ssh_svc="sshd"
    if [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then ssh_svc="ssh"; fi
    
    if systemctl list-unit-files | grep -q "^$ssh_svc"; then
        sudo systemctl enable --now "$ssh_svc"
    fi
    
    # Fstrim
    sudo systemctl enable --now fstrim.timer 2>/dev/null
}

configure_zram() {
    # Check if zram-generator is installed (Arch/Fedora)
    if command -v zramctl >/dev/null; then
        if [ "$DISTRO_ID" == "arch" ]; then
             if [ ! -f /etc/systemd/zram-generator.conf ]; then
                 echo -e "[zram0]\nzram-size = min(ram, 8192)\ncompression-algorithm = zstd" | sudo tee /etc/systemd/zram-generator.conf >/dev/null
                 sudo systemctl daemon-reload
                 sudo systemctl start systemd-zram-setup@zram0.service
             fi
        fi
        # Fedora has defaults usually
    fi
}

# Function to get Ethernet interface names
get_ethernet_interfaces() {
    local interfaces=()
    
    # Use ip command to find Ethernet interfaces (enp*, eth*, ens*)
    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r line; do
            local iface=$(echo "$line" | awk -F': ' '{print $2}' | awk '{print $1}')
            if [[ "$iface" =~ ^(enp|eth|ens|enx)[0-9] ]]; then
                # Verify it's actually an Ethernet interface (not wireless)
                if ip link show "$iface" 2>/dev/null | grep -q "link/ether"; then
                    interfaces+=("$iface")
                fi
            fi
        done < <(ip -o link show 2>/dev/null | grep -E 'state UP|state UNKNOWN')
    fi
    
    # Fallback: try common interface names
    if [ ${#interfaces[@]} -eq 0 ]; then
        for iface in enp3s0 enp5s0 eth0 ens33 ens34; do
            if ip link show "$iface" &>/dev/null && ip link show "$iface" 2>/dev/null | grep -q "link/ether"; then
                interfaces+=("$iface")
            fi
        done
    fi
    
    echo "${interfaces[@]}"
}

# Function to create systemd service for persistent Wake-on-LAN
create_wol_systemd_service() {
    local interface="$1"
    local service_file="/etc/systemd/system/wol-${interface}.service"
    
    # Check if service already exists
    if [ -f "$service_file" ]; then
        log_info "WoL service for $interface already exists. Skipping."
        return 0
    fi
    
    # Find ethtool path
    local ethtool_path=$(command -v ethtool 2>/dev/null || echo "/usr/bin/ethtool")
    if [ ! -f "$ethtool_path" ]; then
        # Try common locations
        for path in /usr/sbin/ethtool /sbin/ethtool /usr/bin/ethtool; do
            if [ -f "$path" ]; then
                ethtool_path="$path"
                break
            fi
        done
    fi
    
    # Create the systemd service file
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Enable Wake-on-LAN for $interface
After=network.target

[Service]
Type=oneshot
ExecStart=$ethtool_path -s $interface wol g
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd daemon and enable the service
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable "wol-${interface}.service" 2>/dev/null || true
    
    log_success "Created and enabled WoL service for $interface"
}

# Function to configure Wake-on-LAN for all Ethernet interfaces
configure_wakeonlan() {
    step "Configuring Wake-on-LAN"
    
    # Install ethtool (required for WoL configuration)
    if ! command -v ethtool >/dev/null 2>&1; then
        log_info "Installing ethtool (required for Wake-on-LAN)..."
        install_packages_quietly ethtool
    fi
    
    if ! command -v ethtool >/dev/null 2>&1; then
        log_warning "ethtool not available. Cannot configure Wake-on-LAN."
        return 1
    fi
    
    # Get all Ethernet interfaces
    local interfaces=($(get_ethernet_interfaces))
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        log_warning "No Ethernet interfaces detected. Wake-on-LAN configuration skipped."
        log_info "Wake-on-LAN only works with wired Ethernet connections."
        return 0
    fi
    
    log_info "Detected Ethernet interfaces: ${interfaces[*]}"
    
    local enabled_count=0
    local failed_count=0
    
    # Enable WoL on each Ethernet interface
    for interface in "${interfaces[@]}"; do
        log_info "Configuring Wake-on-LAN for $interface..."
        
        # Check if interface supports WoL
        if ! sudo ethtool "$interface" &>/dev/null; then
            log_warning "Interface $interface does not support ethtool. Skipping."
            ((failed_count++))
            continue
        fi
        
        # Get current WoL status
        local current_wol=$(sudo ethtool "$interface" 2>/dev/null | grep -i "Wake-on" | awk '{print $NF}' || echo "unknown")
        
        # Enable WoL (g = magic packet)
        if sudo ethtool -s "$interface" wol g >/dev/null 2>&1; then
            # Verify it was enabled
            local new_wol=$(sudo ethtool "$interface" 2>/dev/null | grep -i "Wake-on" | awk '{print $NF}' || echo "unknown")
            
            if [[ "$new_wol" == *"g"* ]] || [[ "$new_wol" == *"G"* ]]; then
                log_success "Wake-on-LAN enabled for $interface (mode: g)"
                ((enabled_count++))
                
                # Create systemd service to persist the setting
                create_wol_systemd_service "$interface"
            else
                log_warning "Failed to enable Wake-on-LAN for $interface (current: $new_wol)"
                ((failed_count++))
            fi
        else
            log_warning "Failed to configure Wake-on-LAN for $interface"
            ((failed_count++))
        fi
    done
    
    # Summary
    if [ $enabled_count -gt 0 ]; then
        log_success "Wake-on-LAN configured for $enabled_count interface(s)"
        
        # Display MAC addresses for reference
        log_info "MAC addresses for Wake-on-LAN:"
        for interface in "${interfaces[@]}"; do
            local mac=$(ip link show "$interface" 2>/dev/null | grep -oP '(?<=link/ether )[0-9a-f:]+' || echo "unknown")
            if [ "$mac" != "unknown" ]; then
                log_info "  $interface: $mac"
            fi
        done
        
        log_info "You can wake this computer using: wakeonlan <MAC_ADDRESS>"
    else
        log_warning "Wake-on-LAN could not be enabled on any interface"
    fi
    
    if [ $failed_count -gt 0 ]; then
        log_warning "$failed_count interface(s) failed to configure"
    fi
}

setup_firewall_and_services() {
  step "Setting up firewall and services"

  # Firewall Logic: Prefer Firewalld if installed (Fedora default), else UFW (Ubuntu/Debian/Arch)
  if command -v firewalld >/dev/null 2>&1; then
    run_step "Configuring Firewalld" configure_firewalld
  else
    # Ensure UFW is installed if we are going to configure it
    install_packages_quietly ufw
    run_step "Configuring UFW" configure_ufw
  fi

  # Configure user groups
  run_step "Configuring user groups" configure_user_groups

  # Enable services
  run_step "Enabling system services" enable_services
  
  # ZRAM
  run_step "Configuring ZRAM" configure_zram
  
  # Wake-on-LAN
  run_step "Configuring Wake-on-LAN" configure_wakeonlan
}

setup_firewall_and_services
