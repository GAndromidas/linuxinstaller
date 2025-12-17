#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup_firewall_and_services() {
  step "Setting up firewall and services"

  # First handle firewall setup
  if command -v firewalld >/dev/null 2>&1; then
    run_step "Configuring Firewalld" configure_firewalld
  else
    run_step "Configuring UFW" configure_ufw
  fi

  # Configure user groups
  run_step "Configuring user groups" configure_user_groups

  # Then handle services
  run_step "Enabling system services" enable_services
}

configure_firewalld() {
  # Start and enable firewalld
  if ! sudo systemctl start firewalld 2>/dev/null; then
    log_error "Failed to start firewalld"
    return 1
  fi

  if ! sudo systemctl enable firewalld 2>/dev/null; then
    log_warning "Failed to enable firewalld (may already be enabled)"
  fi

  # Verify firewalld is active
  if ! sudo systemctl is-active --quiet firewalld; then
    log_error "Firewalld failed to start"
    return 1
  fi
  log_success "Firewalld is active"

  # Set default zone to public (allows outgoing, denies incoming by default)
  sudo firewall-cmd --set-default-zone=public --permanent 2>/dev/null
  sudo firewall-cmd --reload 2>/dev/null
  log_success "Default zone set to public (deny incoming, allow outgoing)"

  # Allow SSH
  if ! sudo firewall-cmd --list-all 2>/dev/null | grep -qE "\b22/tcp\b|ssh"; then
    if sudo firewall-cmd --add-service=ssh --permanent 2>/dev/null; then
      sudo firewall-cmd --reload 2>/dev/null
      log_success "SSH allowed through Firewalld"
    else
      log_error "Failed to allow SSH through Firewalld"
    fi
  else
    log_info "SSH is already allowed"
  fi

  # Verify SSH is actually allowed
  if sudo firewall-cmd --list-all 2>/dev/null | grep -qE "\b22/tcp\b|ssh"; then
    log_success "SSH access verified"
  else
    log_warning "SSH may not be properly configured - please verify manually"
  fi

  # Check if KDE Connect is installed
  if pacman -Q kdeconnect &>/dev/null 2>&1; then
    # Allow specific ports for KDE Connect
    if sudo firewall-cmd --add-port=1714-1764/udp --permanent 2>/dev/null && \
       sudo firewall-cmd --add-port=1714-1764/tcp --permanent 2>/dev/null; then
      sudo firewall-cmd --reload 2>/dev/null
      log_success "KDE Connect ports allowed through Firewalld"
    else
      log_warning "Failed to allow KDE Connect ports"
    fi
  fi
}

configure_ufw() {
  # Install UFW if not present
  if ! command -v ufw >/dev/null 2>&1; then
    install_packages_quietly ufw
    log_success "UFW installed successfully"
  fi

  # Set default policies first (before enabling)
  sudo ufw default deny incoming 2>/dev/null
  sudo ufw default allow outgoing 2>/dev/null
  log_success "Default policies set (deny incoming, allow outgoing)"

  # Allow SSH before enabling (prevents lockout)
  if ! sudo ufw status 2>/dev/null | grep -qE "\b22/tcp\b|SSH"; then
    if sudo ufw allow ssh 2>/dev/null; then
      log_success "SSH rule added to UFW"
    else
      log_error "Failed to add SSH rule to UFW"
    fi
  else
    log_info "SSH is already allowed"
  fi

  # Enable UFW
  if echo "y" | sudo ufw enable 2>/dev/null; then
    log_success "UFW enabled"
  else
    log_warning "UFW may already be enabled"
  fi

  # Enable and start UFW service
  if sudo systemctl enable --now ufw 2>/dev/null; then
    log_success "UFW service enabled and started"
  else
    log_warning "UFW service may already be running"
  fi

  # Verify UFW is active
  if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    log_success "UFW is active and running"
  else
    log_error "UFW is not active - please check manually"
    return 1
  fi

  # Verify SSH is allowed
  if sudo ufw status 2>/dev/null | grep -qE "\b22/tcp\b|SSH"; then
    log_success "SSH access verified in UFW"
  else
    log_warning "SSH may not be properly configured - please verify manually"
  fi

  # Check if KDE Connect is installed
  if pacman -Q kdeconnect &>/dev/null 2>&1; then
    # Allow specific ports for KDE Connect
    if sudo ufw allow 1714:1764/udp 2>/dev/null && \
       sudo ufw allow 1714:1764/tcp 2>/dev/null; then
      log_success "KDE Connect ports allowed through UFW"
    else
      log_warning "Failed to allow KDE Connect ports"
    fi
  fi
}



configure_user_groups() {
  step "Configuring user groups"

  local groups=("wheel" "input" "video" "storage" "optical" "scanner" "lp" "rfkill")

  # Dynamic hardware/software detection for additional groups
  if command -v docker >/dev/null 2>&1; then
    groups+=("docker")
    log_info "Docker detected - will add user to docker group"
  fi
  if command -v libvirtd >/dev/null 2>&1 || systemctl list-unit-files | grep -q libvirtd.service; then
    groups+=("libvirt")
    log_info "Libvirt detected - will add user to libvirt group"
  fi

  local added_count=0
  local skipped_count=0

  for group in "${groups[@]}"; do
    if getent group "$group" >/dev/null; then
      if ! groups "$USER" | grep -q "\b$group\b"; then
        if sudo usermod -aG "$group" "$USER" 2>/dev/null; then
          log_success "Added $USER to $group group"
          ((added_count++))
        else
          log_warning "Failed to add $USER to $group group"
        fi
      else
        log_info "User already in $group group"
        ((skipped_count++))
      fi
    else
      log_info "Group '$group' not present on system (skipping)"
    fi
  done

  if [ $added_count -gt 0 ]; then
    log_info "Added user to $added_count group(s). Logout and login required for changes to take effect."
  fi
}

enable_services() {
  # For server mode, we enable only a minimal set of services and then exit this script
  # to prevent any desktop-specific logic (like display manager setup) from running.
  if [[ "$INSTALL_MODE" == "server" ]]; then
    ui_info "Server mode: Enabling only essential services (cronie, sshd, etc.)."
    local services=(
      cronie.service
      fstrim.timer
      paccache.timer
      sshd.service
    )
    step "Enabling the following system services:"
    for svc in "${services[@]}"; do
      echo -e "  - $svc"
    done
    sudo systemctl enable --now "${services[@]}" >/dev/null 2>&1 || true
    log_success "Essential server services enabled."
    exit 0
  fi

  local services=(
    bluetooth.service
    cronie.service
    fstrim.timer
    paccache.timer
    power-profiles-daemon.service
    sshd.service
  )



  # Conditionally add rustdesk.service if installed
  if pacman -Q rustdesk-bin &>/dev/null || pacman -Q rustdesk &>/dev/null; then
    services+=(rustdesk.service)
    log_success "rustdesk.service will be enabled."
  else
    log_warning "rustdesk is not installed. Skipping rustdesk.service."
  fi

  step "Enabling the following system services:"
  for svc in "${services[@]}"; do
    echo -e "  - $svc"
  done
  sudo systemctl enable --now "${services[@]}" 2>/dev/null || true

  # Verify services started correctly
  log_info "Verifying service status..."
  local failed_services=()
  for svc in "${services[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      log_success "$svc is active"
    elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      log_warning "$svc is enabled but not running (may require reboot)"
    else
      log_warning "$svc failed to start or enable"
      failed_services+=("$svc")
    fi
  done

  if [ ${#failed_services[@]} -eq 0 ]; then
    log_success "All services verified successfully"
  else
    log_warning "Some services may need attention: ${failed_services[*]}"
  fi
}

# Function to get total RAM in GB (rounded to common consumer sizes)
# Accounts for kernel memory reservation (e.g., 32GB shows as ~31GB, 8GB as ~7.5GB, etc.)
# Only returns: 2GB, 4GB, 8GB, 16GB, or 32GB
get_ram_gb() {
  local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')

  # Convert to MB for better precision
  local ram_mb=$((ram_kb / 1024))

  # Calculate actual GB with decimal precision
  local ram_gb_precise=$(echo "scale=2; $ram_mb / 1024" | bc -l)

  # Round to common consumer RAM sizes: 2GB, 4GB, 8GB, 16GB, 32GB+
  local rounded_gb

  if (( $(echo "$ram_gb_precise < 3" | bc -l) )); then
    rounded_gb=2
  elif (( $(echo "$ram_gb_precise < 6" | bc -l) )); then
    rounded_gb=4
  elif (( $(echo "$ram_gb_precise < 12" | bc -l) )); then
    rounded_gb=8
  elif (( $(echo "$ram_gb_precise < 24" | bc -l) )); then
    rounded_gb=16
  else
    # Anything 24GB+ is treated as 32GB
    rounded_gb=32
  fi

  echo $rounded_gb
}

# Function to get optimal ZRAM size multiplier based on RAM
# Only handles common consumer sizes: 2GB, 4GB, 8GB, 16GB, 32GB+
get_zram_multiplier() {
  local ram_gb=$1
  case $ram_gb in
    2) echo "1.5" ;;      # 2GB RAM -> 150% ZRAM (3GB)
    4) echo "1.0" ;;      # 4GB RAM -> 100% ZRAM (4GB)
    8) echo "0.75" ;;     # 8GB RAM -> 75% ZRAM (6GB)
    16) echo "0.5" ;;     # 16GB RAM -> 50% ZRAM (8GB)
    32) echo "0.25" ;;    # 32GB+ RAM -> 25% ZRAM (8GB)
    *)
      # Fallback (should not happen with smart rounding)
      if [ $ram_gb -le 4 ]; then
        echo "1.0"
      elif [ $ram_gb -le 8 ]; then
        echo "0.75"
      elif [ $ram_gb -le 16 ]; then
        echo "0.5"
      else
        echo "0.25"
      fi
      ;;
  esac
}

# Function to check and manage traditional swap
check_traditional_swap() {
  step "Checking for traditional swap partitions/files"

  # Check for hibernation
  local hibernation_enabled=false
  if grep -q "resume=" /proc/cmdline 2>/dev/null; then
    hibernation_enabled=true
  fi

  # Check if any swap is active
  if swapon --show | grep -q '/'; then
    log_info "Traditional swap detected"
    swapon --show

    # If hibernation is enabled, keep swap
    if [ "$hibernation_enabled" = true ]; then
      log_warning "Hibernation is configured - keeping disk swap"
      log_info "Hibernation requires disk swap to save RAM contents"
      log_info "Traditional swap will remain active alongside ZRAM"
      return 1
    fi

    local should_disable=false
    if command -v gum >/dev/null 2>&1; then
      gum confirm --default=true "Disable traditional swap in favor of ZRAM?" && should_disable=true
    else
      read -r -p "Disable traditional swap in favor of ZRAM? [Y/n]: " response
      response=${response,,}
      [[ "$response" != "n" && "$response" != "no" ]] && should_disable=true
    fi

    if [ "$should_disable" = true ]; then
      log_info "Disabling traditional swap..."
      sudo swapoff -a

      # Comment out swap entries in fstab
      if grep -q '^[^#].*swap' /etc/fstab; then
        sudo sed -i.bak '/^[^#].*swap/s/^/# /' /etc/fstab
        log_success "Traditional swap disabled and fstab updated (backup saved)"
        log_warning "Hibernation will not work without disk swap"
      fi
    else
      log_warning "Traditional swap kept active alongside ZRAM"
      return 1
    fi
  else
    log_info "No traditional swap detected - good for ZRAM setup"
  fi
  return 0
}

setup_zram_swap() {
  step "Setting up ZRAM swap"

  # Get system RAM
  local ram_gb=$(get_ram_gb)

  # Handle ZRAM on very high memory systems (32GB+)
  # Note: get_ram_gb() now intelligently rounds to nearest common RAM size
  if [ $ram_gb -ge 32 ]; then
    log_info "High memory system detected (${ram_gb}GB RAM)"

    # Check if ZRAM is already configured
    if systemctl is-active --quiet systemd-zram-setup@zram0 || systemctl is-enabled systemd-zram-setup@zram0 2>/dev/null; then
      log_warning "ZRAM is currently enabled but not needed with ${ram_gb}GB RAM"
      log_info "Automatically removing ZRAM configuration..."

      # Stop and disable ZRAM service
      sudo systemctl stop systemd-zram-setup@zram0 2>/dev/null || true
      sudo systemctl disable systemd-zram-setup@zram0 2>/dev/null || true

      # Remove ZRAM configuration file
      if [ -f /etc/systemd/zram-generator.conf ]; then
        sudo rm /etc/systemd/zram-generator.conf
        log_success "ZRAM configuration removed"
      fi

      # Reload systemd
      sudo systemctl daemon-reexec

      log_success "ZRAM disabled - system has sufficient RAM"
    else
      log_success "ZRAM not configured - system has sufficient RAM"
    fi

    # Remove zram-generator package and dependencies if installed
    if pacman -Q zram-generator &>/dev/null; then
      log_info "Removing zram-generator package and dependencies..."
      if sudo pacman -Rns --noconfirm zram-generator >/dev/null 2>&1; then
        log_success "zram-generator package removed"
        REMOVED_PACKAGES+=("zram-generator")
      else
        log_warning "Failed to remove zram-generator package (may have dependent packages)"
      fi
    fi

    log_info "Swap usage will be minimal with this amount of memory"
    return
  fi

  # Check for hibernation configuration
  local hibernation_enabled=false
  if grep -q "resume=" /proc/cmdline 2>/dev/null; then
    hibernation_enabled=true
    log_warning "Hibernation detected in kernel parameters"
  fi

  # Check if ZRAM is already enabled
  if ! systemctl is-active --quiet systemd-zram-setup@zram0; then
    # Automatic ZRAM for low memory systems (≤4GB)
    if [ $ram_gb -le 4 ]; then
      log_info "Low memory system detected (${ram_gb}GB RAM)"

      # Warn about hibernation conflict
      if [ "$hibernation_enabled" = true ]; then
        log_warning "ZRAM conflicts with hibernation (suspend-to-disk)"
        log_info "Hibernation requires disk swap, ZRAM is swap in RAM"
        log_info "Options:"
        log_info "  1. Use ZRAM (better performance, no hibernation)"
        log_info "  2. Keep disk swap (hibernation works, slower swap)"

        local enable_zram_anyway=false
        if command -v gum >/dev/null 2>&1; then
          gum confirm --default=false "Enable ZRAM anyway (disables hibernation)?" && enable_zram_anyway=true
        else
          read -r -p "Enable ZRAM anyway (disables hibernation)? [y/N]: " response
          response=${response,,}
          [[ "$response" == "y" || "$response" == "yes" ]] && enable_zram_anyway=true
        fi

        if [ "$enable_zram_anyway" = false ]; then
          log_info "Keeping disk swap for hibernation support"
          return
        fi
      fi

      log_info "Automatically enabling ZRAM (compressed swap in RAM)"
      log_success "ZRAM will provide $(echo "$ram_gb * $(get_zram_multiplier $ram_gb)" | bc | cut -d. -f1)GB effective memory"

      # Check and manage traditional swap
      check_traditional_swap

      # Enable ZRAM service
      sudo systemctl enable systemd-zram-setup@zram0
      sudo systemctl start systemd-zram-setup@zram0
    else
      # Optional ZRAM for medium memory systems (>4GB and <32GB)
      log_info "System has ${ram_gb}GB RAM - ZRAM is optional"

      # Don't offer ZRAM if hibernation is enabled
      if [ "$hibernation_enabled" = true ]; then
        log_warning "Hibernation detected - ZRAM not recommended"
        log_info "ZRAM conflicts with hibernation (suspend-to-disk)"
        log_info "Keeping disk swap for hibernation support"
        return
      fi

      local enable_zram=false
      if command -v gum >/dev/null 2>&1; then
        gum confirm --default=false "Enable ZRAM swap for additional performance?" && enable_zram=true
      else
        read -r -p "Enable ZRAM swap for additional performance? [y/N]: " response
        response=${response,,}
        [[ "$response" == "y" || "$response" == "yes" ]] && enable_zram=true
      fi

      if [ "$enable_zram" = true ]; then
        check_traditional_swap
        sudo systemctl enable systemd-zram-setup@zram0
        sudo systemctl start systemd-zram-setup@zram0
      else
        log_info "ZRAM configuration skipped"
        return
      fi
    fi
  else
    log_info "ZRAM is already active"
  fi

  # Get optimal multiplier (ram_gb already fetched above)
  local multiplier=$(get_zram_multiplier $ram_gb)
  local zram_size_gb=$(echo "$ram_gb * $multiplier" | bc -l | cut -d. -f1)

  echo -e "${CYAN}System RAM: ${ram_gb}GB${RESET}"
  echo -e "${CYAN}ZRAM multiplier: ${multiplier} (${zram_size_gb}GB effective)${RESET}"

  # Create ZRAM config with optimal settings
  sudo tee /etc/systemd/zram-generator.conf > /dev/null << EOF
[zram0]
zram-size = ram * ${multiplier}
compression-algorithm = zstd
swap-priority = 100
EOF

  # Enable and start ZRAM
  sudo systemctl daemon-reexec
  sudo systemctl enable --now systemd-zram-setup@zram0 2>/dev/null || true

  # Verify ZRAM is active
  if systemctl is-active --quiet systemd-zram-setup@zram0; then
    log_success "ZRAM swap is active and configured"

    # Show ZRAM status
    if command -v zramctl >/dev/null 2>&1; then
      echo -e "${CYAN}ZRAM Status:${RESET}"
      zramctl
    fi
  else
    log_warning "ZRAM service may not have started correctly"
  fi
}

# Function to detect if system is a laptop
is_laptop() {
  # Check multiple indicators for laptop detection
  if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
    return 0
  fi
  if command -v dmidecode >/dev/null 2>&1; then
    if sudo dmidecode -s chassis-type | grep -qiE 'Notebook|Laptop|Portable'; then
      return 0
    fi
  fi
  if [ -f /sys/class/dmi/id/chassis_type ]; then
    local chassis_type=$(cat /sys/class/dmi/id/chassis_type)
    # 8=Portable, 9=Laptop, 10=Notebook, 14=Sub Notebook
    if [[ "$chassis_type" =~ ^(8|9|10|14)$ ]]; then
      return 0
    fi
  fi
  return 1
}

# Function to detect CPU generation and recommend power profile daemon
detect_power_profile_daemon() {
  local cpu_vendor=$(detect_cpu_vendor)
  local recommended_daemon="tuned-ppd"  # Default to safer choice
  local cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)

  # Simple logic: Check kernel version and CPU family for modern support
  # power-profiles-daemon requires kernel 5.17+ and modern CPU (Zen 3+ or Skylake+)
  local kernel_major=$(uname -r | cut -d. -f1)
  local kernel_minor=$(uname -r | cut -d. -f2)

  if [ "$cpu_vendor" = "intel" ]; then
    # Budget Intel CPUs - always use tuned-ppd
    if echo "$cpu_model" | grep -qiE "Atom|Celeron|Pentium"; then
      recommended_daemon="tuned-ppd"
      log_info "Intel budget CPU detected - tuned-ppd recommended"
    # Modern kernel + Core i-series = likely 6th gen+ = power-profiles-daemon OK
    elif [ "$kernel_major" -ge 6 ] && echo "$cpu_model" | grep -qiE "Core.*i[3579]"; then
      recommended_daemon="power-profiles-daemon"
      log_info "Modern Intel CPU with recent kernel - power-profiles-daemon supported"
    else
      recommended_daemon="tuned-ppd"
      log_info "Older Intel CPU or kernel - tuned-ppd recommended"
    fi
  elif [ "$cpu_vendor" = "amd" ]; then
    # Simple check: Ryzen with 5 or higher first digit = likely 5000+ series
    # Modern kernel required for proper AMD P-State support
    if [ "$kernel_major" -ge 6 ] && echo "$cpu_model" | grep -qiE "Ryzen.*(5[0-9]{3}|[6-9][0-9]{3})"; then
      recommended_daemon="power-profiles-daemon"
      log_info "Modern AMD Ryzen (5000+ series) - power-profiles-daemon supported"
    else
      recommended_daemon="tuned-ppd"
      log_info "AMD CPU (Ryzen 1st-4th gen or older) - tuned-ppd recommended"
    fi
  else
    # Unknown CPU - default to tuned-ppd (safer choice)
    recommended_daemon="tuned-ppd"
    log_info "Unknown CPU vendor - tuned-ppd recommended (safer)"
  fi

  echo "$recommended_daemon"
}

# Function to install and configure power profile daemon
setup_power_profile_daemon() {
  step "Setting up power profile management"

  local daemon=$(detect_power_profile_daemon)

  if [ "$daemon" = "power-profiles-daemon" ]; then
    log_info "Installing power-profiles-daemon..."
    install_packages_quietly power-profiles-daemon

    sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null

    if systemctl is-active --quiet power-profiles-daemon.service; then
      log_success "power-profiles-daemon is active"
      log_info "Use 'powerprofilesctl' to manage power profiles"
    else
      log_warning "power-profiles-daemon may require a reboot"
    fi
  else
    log_info "Installing tuned-ppd (power-profiles-daemon alternative)..."

    # Check if tuned-ppd is available in AUR
    if command -v yay >/dev/null 2>&1; then
      install_aur_quietly tuned-ppd

      sudo systemctl enable --now tuned.service 2>/dev/null

      if systemctl is-active --quiet tuned.service; then
        log_success "tuned-ppd is active"
        log_info "Use 'tuned-adm' to manage power profiles"
        log_info "Available profiles: balanced, powersave, performance"
      else
        log_warning "tuned-ppd may require a reboot"
      fi
    else
      log_warning "yay not available - cannot install tuned-ppd from AUR"
      log_info "Using kernel's built-in power management"
    fi
  fi
}

# Function to detect CPU vendor
detect_cpu_vendor() {
  if grep -qi "GenuineIntel" /proc/cpuinfo; then
    echo "intel"
  elif grep -qi "AuthenticAMD" /proc/cpuinfo; then
    echo "amd"
  else
    echo "unknown"
  fi
}

# Function to detect RAM size and make adaptive decisions
detect_memory_size() {
  step "Detecting system memory and applying optimizations"

  # Get total RAM in GB
  local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local ram_gb=$((ram_kb / 1024 / 1024))

  log_info "Total system memory: ${ram_gb}GB"

  # Apply memory-based optimizations
  if [ $ram_gb -lt 4 ]; then
    log_warning "Low memory system detected (< 4GB)"
    log_info "Applying low-memory optimizations..."

    # Aggressive swappiness for low RAM
    echo "vm.swappiness=60" | sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null
    log_success "Set swappiness to 60 (aggressive swap usage)"

    # Reduce cache pressure
    echo "vm.vfs_cache_pressure=50" | sudo tee -a /etc/sysctl.d/99-swappiness.conf >/dev/null
    log_success "Reduced cache pressure for low memory"

  elif [ $ram_gb -ge 4 ] && [ $ram_gb -lt 8 ]; then
    log_info "Standard memory system detected (4-8GB)"

    # Moderate swappiness
    echo "vm.swappiness=30" | sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null
    log_success "Set swappiness to 30 (moderate swap usage)"

  elif [ $ram_gb -ge 8 ] && [ $ram_gb -lt 16 ]; then
    log_info "High memory system detected (8-16GB)"

    # Low swappiness
    echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null
    log_success "Set swappiness to 10 (low swap usage)"

  else
    log_success "Very high memory system detected (16GB+)"

    # Minimal swappiness
    echo "vm.swappiness=1" | sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null
    log_success "Set swappiness to 1 (minimal swap usage)"

    # Disable swap on very high memory systems
    if [ $ram_gb -ge 32 ]; then
      log_info "32GB+ RAM detected - swap can be fully disabled if desired"
    fi
  fi

  # Apply sysctl settings immediately
  sudo sysctl -p /etc/sysctl.d/99-swappiness.conf >/dev/null 2>&1

  log_success "Memory-based optimizations applied"
}

# Function to detect filesystem type and apply optimizations
detect_filesystem_type() {
  step "Detecting filesystem type and applying optimizations"

  local root_fs=$(findmnt -no FSTYPE /)
  log_info "Root filesystem: $root_fs"

  case "$root_fs" in
    ext4)
      log_info "ext4 detected - applying ext4 optimizations"
      # Set reserved blocks to 1% (default is 5%)
      local root_device=$(findmnt -no SOURCE /)
      if [ -n "$root_device" ]; then
        sudo tune2fs -m 1 "$root_device" 2>/dev/null && log_success "Reduced ext4 reserved blocks to 1%"
      fi
      ;;
    xfs)
      log_info "XFS detected - XFS is already well-optimized"
      log_success "XFS filesystem detected (no additional optimization needed)"
      ;;
    f2fs)
      log_info "F2FS detected - optimized for flash storage"
      log_success "F2FS filesystem detected (flash-optimized)"
      ;;
    btrfs)
      log_success "Btrfs detected - snapshot support available"
      ;;
    *)
      log_info "Filesystem: $root_fs (using default optimizations)"
      ;;
  esac

  # Check for LUKS encryption
  if lsblk -o NAME,FSTYPE | grep -q crypto_LUKS; then
    log_info "LUKS encryption detected"
    # Check if SSD
    local encrypted_device=$(lsblk -o NAME,FSTYPE,TYPE | grep crypto_LUKS | head -1 | awk '{print $1}')
    if [ -n "$encrypted_device" ]; then
      log_success "Encrypted storage detected - TRIM support should be enabled in crypttab"
    fi
  fi
}

# Function to detect storage type and optimize I/O scheduler
detect_storage_type() {
  step "Detecting storage type and optimizing I/O scheduler"

  # Get all block devices (exclude loop, ram, etc.)
  local devices=$(lsblk -d -n -o NAME,TYPE | grep disk | awk '{print $1}')

  for device in $devices; do
    local rota=$(cat /sys/block/$device/queue/rotational 2>/dev/null || echo "1")
    local device_type=""
    local scheduler=""

    # Determine device type
    if [[ "$device" == nvme* ]]; then
      device_type="NVMe SSD"
      scheduler="none"
    elif [ "$rota" = "0" ]; then
      device_type="SATA SSD"
      scheduler="mq-deadline"
    else
      device_type="HDD"
      scheduler="bfq"
    fi

    log_info "Device /dev/$device: $device_type"

    # Set I/O scheduler
    if [ -f /sys/block/$device/queue/scheduler ]; then
      # Check if scheduler is available
      if grep -q "$scheduler" /sys/block/$device/queue/scheduler 2>/dev/null; then
        echo "$scheduler" | sudo tee /sys/block/$device/queue/scheduler >/dev/null
        log_success "Set I/O scheduler to '$scheduler' for /dev/$device"
      else
        log_warning "Scheduler '$scheduler' not available for /dev/$device"
      fi
    fi
  done

  # Make scheduler changes persistent via udev rule
  sudo tee /etc/udev/rules.d/60-ioschedulers.rules >/dev/null << 'EOF'
# Set I/O scheduler based on storage type
# NVMe devices - use none (multi-queue)
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
# SSD devices - use mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# HDD devices - use bfq
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

  log_success "I/O scheduler optimizations applied and made persistent"
}

# Function to detect audio system
detect_audio_system() {
  step "Detecting audio system"

  if systemctl --user is-active --quiet pipewire 2>/dev/null || systemctl is-active --quiet pipewire 2>/dev/null; then
    log_success "PipeWire audio system detected"
    # Install PipeWire specific packages if not already installed
    install_packages_quietly pipewire-alsa pipewire-jack pipewire-pulse
    log_success "PipeWire compatibility packages installed"
  elif systemctl --user is-active --quiet pulseaudio 2>/dev/null || pgrep -x pulseaudio >/dev/null 2>&1; then
    log_success "PulseAudio audio system detected"
    # Ensure PulseAudio bluetooth support
    if pacman -Q bluez &>/dev/null; then
      install_packages_quietly pulseaudio-bluetooth
      log_success "PulseAudio Bluetooth support installed"
    fi
  else
    log_info "No audio system detected or not running yet"
    log_info "PipeWire is recommended for modern systems"
  fi
}

# Function to detect hybrid graphics
detect_hybrid_graphics() {
  step "Detecting hybrid graphics configuration"

  local gpu_count=$(lspci | grep -i vga | wc -l)

  if [ "$gpu_count" -gt 1 ]; then
    log_warning "Multiple GPUs detected - hybrid graphics system"
    lspci | grep -i vga

    # Check for NVIDIA + Intel/AMD combo
    if lspci | grep -qi nvidia && lspci | grep -qiE "intel|amd"; then
      log_warning "NVIDIA Optimus / Hybrid graphics detected"
      log_info "Consider installing optimus-manager or nvidia-prime for GPU switching"
      log_info "   AUR: yay -S optimus-manager optimus-manager-qt"
      log_info "Manual setup required after installation"
    fi
  else
    log_info "Single GPU system detected"
  fi
}

# Function to detect kernel type
detect_kernel_type() {
  step "Detecting installed kernel type"

  local kernel=$(uname -r)
  local kernel_type="linux"

  if [[ "$kernel" == *"-lts"* ]]; then
    kernel_type="linux-lts"
    log_success "Running linux-lts kernel (Long Term Support)"
    log_info "LTS kernel focuses on stability"
  elif [[ "$kernel" == *"-zen"* ]]; then
    kernel_type="linux-zen"
    log_success "Running linux-zen kernel (Performance)"
    log_info "Zen kernel optimized for desktop/gaming performance"
  elif [[ "$kernel" == *"-hardened"* ]]; then
    kernel_type="linux-hardened"
    log_success "Running linux-hardened kernel (Security)"
    log_info "Hardened kernel focuses on security"
  else
    log_success "Running standard linux kernel"
    log_info "Standard kernel provides balanced performance"
  fi

  # Apply kernel-specific optimizations
  case "$kernel_type" in
    linux-zen)
      # Gaming/desktop optimizations already in place
      log_info "Zen kernel already optimized for low latency"
      ;;
    linux-hardened)
      # Security-focused - minimal changes
      log_info "Hardened kernel - security optimizations active"
      ;;
    linux-lts)
      # Stability focused
      log_info "LTS kernel - maximum stability"
      ;;
  esac
}

# Function to detect desktop environment version
detect_de_version() {
  step "Detecting desktop environment version"

  case "${XDG_CURRENT_DESKTOP:-}" in
    *GNOME*)
      if command -v gnome-shell >/dev/null 2>&1; then
        local gnome_version=$(gnome-shell --version | grep -oP '\d+' | head -1)
        log_success "GNOME version: $gnome_version"
        if [ "$gnome_version" -ge 45 ]; then
          log_info "Modern GNOME version detected (45+)"
        fi
      fi
      ;;
    *KDE*|*Plasma*)
      if command -v plasmashell >/dev/null 2>&1; then
        local plasma_version=$(plasmashell --version 2>/dev/null | grep -oP '\d+' | head -1)
        log_success "KDE Plasma version: $plasma_version"
        if [ "$plasma_version" -ge 6 ]; then
          log_info "KDE Plasma 6 detected (Qt6-based)"
        else
          log_info "KDE Plasma 5 detected (Qt5-based)"
        fi
      fi
      ;;
    *COSMIC*)
      log_success "Cosmic Desktop detected (alpha/beta)"
      ;;
    *)
      log_info "Desktop environment: ${XDG_CURRENT_DESKTOP:-Unknown}"
      ;;
  esac
}

# Function to check battery status
check_battery_status() {
  step "Checking battery status"

  if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
    local battery_path="/sys/class/power_supply/BAT0"
    [ ! -d "$battery_path" ] && battery_path="/sys/class/power_supply/BAT1"

    if [ -d "$battery_path" ]; then
      local status=$(cat "$battery_path/status" 2>/dev/null || echo "Unknown")
      local capacity=$(cat "$battery_path/capacity" 2>/dev/null || echo "Unknown")

      log_info "Battery Status: $status"
      log_info "Battery Capacity: ${capacity}%"

      if [ "$status" = "Discharging" ] && [ "$capacity" -lt 30 ]; then
        log_warning "Battery level is low (${capacity}%)"
        log_warning "Consider plugging in AC adapter for installation"
        log_info "Installation may take 20-30 minutes"

        if command -v gum >/dev/null 2>&1; then
          if ! gum confirm --default=false "Continue on battery power?"; then
            log_error "Installation cancelled - please connect AC adapter"
            exit 1
          fi
        else
          read -r -p "Continue on battery power? [y/N]: " response
          response=${response,,}
          if [[ "$response" != "y" && "$response" != "yes" ]]; then
            log_error "Installation cancelled - please connect AC adapter"
            exit 1
          fi
        fi
      elif [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
        log_success "Battery is charging or full - safe to proceed"
      fi
    fi
  else
    log_info "No battery detected (desktop system or AC only)"
  fi
}

# Function to detect bluetooth hardware
detect_bluetooth_hardware() {
  step "Detecting Bluetooth hardware"

  if lsusb | grep -qi bluetooth || lspci | grep -qi bluetooth || [ -d /sys/class/bluetooth ]; then
    log_success "Bluetooth hardware detected"

    # Check if bluetooth service is enabled
    if ! systemctl is-enabled bluetooth.service &>/dev/null; then
      log_info "Bluetooth hardware present - service will be enabled"
    else
      log_info "Bluetooth service already enabled"
    fi
  else
    log_info "No Bluetooth hardware detected"
    log_info "Bluetooth packages installed but service will not be started"
  fi
}

# Function to setup Intel-specific laptop optimizations
setup_intel_laptop_optimizations() {
  step "Configuring Intel-specific laptop optimizations"

  # Install thermald for Intel thermal management
  log_info "Installing thermald for Intel thermal management..."
  install_packages_quietly thermald

  # Enable and start thermald
  sudo systemctl enable thermald.service 2>/dev/null
  sudo systemctl start thermald.service 2>/dev/null

  if systemctl is-active --quiet thermald.service; then
    log_success "thermald is active for thermal management"
  else
    log_warning "thermald may require a reboot"
  fi

  # Check if Intel P-State driver is available
  if [ -d /sys/devices/system/cpu/intel_pstate ]; then
    log_success "Intel P-State driver detected - kernel will manage CPU power"
  else
    log_info "Using ACPI CPUfreq driver for CPU power management"
  fi

  log_success "Intel-specific optimizations completed"
}

# Function to setup AMD-specific laptop optimizations
setup_amd_laptop_optimizations() {
  step "Configuring AMD-specific laptop optimizations"

  # Check for AMD P-State driver
  if [ -d /sys/devices/system/cpu/amd_pstate ]; then
    log_success "AMD P-State driver detected - kernel will manage CPU power efficiently"
    log_info "Modern Ryzen CPUs (5000+ series) have excellent power management built-in"
  else
    log_info "AMD P-State driver not available (using ACPI CPUfreq driver)"
    log_info "This is normal for Ryzen 1st-3rd gen mobile CPUs (2000-3000 series)"
    log_success "Kernel ACPI CPUfreq driver will handle power management"
  fi

  log_success "AMD-specific optimizations completed"
}

# Function to setup laptop optimizations
setup_laptop_optimizations() {
  if ! is_laptop; then
    log_info "Desktop system detected. Skipping laptop optimizations."
    return 0
  fi

  step "Laptop detected - Configuring laptop optimizations"
  log_success "Laptop hardware detected"

  # Detect CPU vendor
  local cpu_vendor=$(detect_cpu_vendor)
  log_info "CPU Vendor: $(echo $cpu_vendor | tr '[:lower:]' '[:upper:]')"

  # Ask user if they want laptop optimizations
  local enable_laptop_opts=false
  if command -v gum >/dev/null 2>&1; then
    echo ""
    gum style --foreground 226 "Laptop-specific optimizations available:"
    gum style --margin "0 2" --foreground 15 "• Power profile management (tuned-ppd or power-profiles-daemon)"
    gum style --margin "0 2" --foreground 15 "• Touchpad tap-to-click"
    gum style --margin "0 2" --foreground 15 "• CPU-specific optimizations"
    echo ""
    if gum confirm --default=true "Enable laptop optimizations?"; then
      enable_laptop_opts=true
    fi
  else
    echo ""
    echo -e "${YELLOW}Laptop-specific optimizations available:${RESET}"
    echo -e "  • Power profile management (tuned-ppd or power-profiles-daemon)"
    echo -e "  • Touchpad tap-to-click"
    echo -e "  • CPU-specific optimizations"
    echo ""
    read -r -p "Enable laptop optimizations? [Y/n]: " response
    response=${response,,}
    if [[ "$response" != "n" && "$response" != "no" ]]; then
      enable_laptop_opts=true
    fi
  fi

  if [ "$enable_laptop_opts" = false ]; then
    log_info "Laptop optimizations skipped by user"
    return 0
  fi

  # Setup power profile management (kernel + power-profiles-daemon/tuned-ppd)
  step "Setting up power profile management"
  log_info "Modern kernels handle power management well"
  log_info "Adding user-friendly profile switching via power-profiles-daemon or tuned-ppd"

  setup_power_profile_daemon

  # Apply CPU-specific optimizations
  case "$cpu_vendor" in
    intel)
      setup_intel_laptop_optimizations
      ;;
    amd)
      setup_amd_laptop_optimizations
      ;;
    *)
      log_info "Unknown CPU vendor - using kernel defaults for power management"
      ;;
  esac

  # Configure touchpad
  step "Configuring touchpad settings"

  # Create libinput configuration for touchpad
  sudo mkdir -p /etc/X11/xorg.conf.d

  cat << 'EOF' | sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf >/dev/null
Section "InputClass"
    Identifier "touchpad"
    Driver "libinput"
    MatchIsTouchpad "on"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "true"
    Option "ScrollMethod" "twofinger"
    Option "DisableWhileTyping" "on"
    Option "ClickMethod" "clickfinger"
EndSection
EOF

  log_success "Touchpad configured (tap-to-click, natural scrolling, disable-while-typing)"

  # Show summary
  show_laptop_summary
}

# Continue setup_laptop_optimizations function
show_laptop_summary() {
  # Display battery information
  step "Battery information"
  if [ -d /sys/class/power_supply/BAT0 ]; then
    local battery_status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
    local battery_capacity=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "Unknown")
    log_info "Battery Status: $battery_status"
    log_info "Battery Capacity: ${battery_capacity}%"
  fi

  # Show power management info
  if command -v tuned-adm >/dev/null 2>&1; then
    log_info "Power profiles managed by tuned-ppd. Use: tuned-adm list"
  elif command -v powerprofilesctl >/dev/null 2>&1; then
    log_info "Power profiles managed by power-profiles-daemon. Use: powerprofilesctl"
  fi

  echo ""
  log_success "Laptop optimizations completed successfully"
  echo ""
  echo -e "${CYAN}Laptop features configured:${RESET}"
  echo -e "  • Kernel-based power management (automatic)"
  if command -v tuned-adm >/dev/null 2>&1; then
    echo -e "  • tuned-ppd for power profile switching"
  elif command -v powerprofilesctl >/dev/null 2>&1; then
    echo -e "  • power-profiles-daemon for power profile switching"
  fi
  case "$cpu_vendor" in
    intel)
      echo -e "  • Intel thermald (thermal management)"
      if [ -d /sys/devices/system/cpu/intel_pstate ]; then
        echo -e "  • Intel P-State driver (efficient CPU scaling)"
      fi
      ;;
    amd)
      if [ -d /sys/devices/system/cpu/amd_pstate ]; then
        echo -e "  • AMD P-State driver (Ryzen 5000+ efficient scaling)"
      else
        echo -e "  • ACPI CPUfreq driver (Ryzen 1st-4th gen)"
      fi
      ;;
  esac
  echo -e "  • Touchpad tap-to-click enabled"
  echo -e "  • Natural scrolling enabled"
  echo -e "  • Disable typing while typing enabled"
  echo ""
  echo -e "${YELLOW}Tips:${RESET}"
  if command -v tuned-adm >/dev/null 2>&1; then
    echo -e "  • List power profiles: ${CYAN}tuned-adm list${RESET}"
    echo -e "  • Switch to powersave: ${CYAN}tuned-adm profile powersave${RESET}"
    echo -e "  • Switch to performance: ${CYAN}tuned-adm profile performance${RESET}"
    echo -e "  • Check active profile: ${CYAN}tuned-adm active${RESET}"
  elif command -v powerprofilesctl >/dev/null 2>&1; then
    echo -e "  • List power profiles: ${CYAN}powerprofilesctl list${RESET}"
    echo -e "  • Switch profile: ${CYAN}powerprofilesctl set performance${RESET}"
  fi
  if [ "$cpu_vendor" = "intel" ]; then
    echo -e "  • Thermal status: ${CYAN}sudo systemctl status thermald${RESET}"
  fi
  echo ""
}

# Function to detect all Ethernet adapters (universal detection)
# Detects interfaces using modern (enp*, eno*, ens*) and legacy (eth*) naming schemes
# Also handles any interface with ethernet link type regardless of name
detect_ethernet_adapters() {
  local adapters=()

  # Use ip command to get all network interfaces
  local all_interfaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' || echo "")

  if [ -z "$all_interfaces" ]; then
    log_warning "Could not detect network interfaces"
    return 1
  fi

  for iface in $all_interfaces; do
    # Skip loopback interface
    [[ "$iface" == "lo" ]] && continue

    # Skip known virtual/wireless interfaces
    [[ "$iface" =~ ^(docker|veth|br-|virbr|vmnet|wlan|wifi|wl-|wwan|wwp) ]] && continue

    # Skip if wireless interface (check sysfs)
    [ -d "/sys/class/net/$iface/wireless" ] && continue

    # Check interface type via sysfs (1 = Ethernet, ARPHRD_ETHER)
    if [ -d "/sys/class/net/$iface" ]; then
      local iface_type=$(cat "/sys/class/net/$iface/type" 2>/dev/null || echo "")
      if [[ "$iface_type" == "1" ]]; then
        # Double-check it has ethernet link type
        if ip link show "$iface" 2>/dev/null | grep -q "link/ether"; then
          adapters+=("$iface")
        fi
      fi
    fi
  done

  printf '%s\n' "${adapters[@]}"
}

# Function to get MAC address of an interface
get_interface_mac() {
  local iface="$1"
  ip link show "$iface" 2>/dev/null | grep -oP 'link/ether \K[0-9a-f:]+' | head -1
}

# Function to check if Wake-on-LAN is supported on an interface
check_wol_support() {
  local iface="$1"

  # Check if ethtool is available
  if ! command -v ethtool >/dev/null 2>&1; then
    return 1
  fi

  # Check if interface supports WoL
  if sudo ethtool "$iface" 2>/dev/null | grep -q "Wake-on:"; then
    return 0
  fi

  return 1
}

# Function to get current Wake-on-LAN status
get_wol_status() {
  local iface="$1"
  sudo ethtool "$iface" 2>/dev/null | grep "Wake-on:" | awk '{print $2}' | tr -d ' '
}

# Function to setup Wake-on-LAN for all Ethernet adapters
setup_wake_on_lan() {
  step "Configuring Wake-on-LAN for Ethernet adapters"

  # Install ethtool if not available
  if ! command -v ethtool >/dev/null 2>&1; then
    log_info "Installing ethtool for Wake-on-LAN support..."
    if ! install_packages_quietly ethtool; then
      log_error "Failed to install ethtool. Wake-on-LAN cannot be configured."
      return 1
    fi
  fi

  # Detect all Ethernet adapters
  local adapters=($(detect_ethernet_adapters))

  if [ ${#adapters[@]} -eq 0 ]; then
    log_warning "No Ethernet adapters detected. Skipping Wake-on-LAN configuration."
    return 0
  fi

  log_info "Detected ${#adapters[@]} Ethernet adapter(s): ${adapters[*]}"

  local configured_count=0
  local skipped_count=0
  local failed_count=0

  for adapter in "${adapters[@]}"; do
    log_info "Configuring Wake-on-LAN for $adapter..."

    # Check if WoL is supported
    if ! check_wol_support "$adapter"; then
      log_warning "$adapter does not support Wake-on-LAN (skipping)"
      ((skipped_count++))
      continue
    fi

    # Get current status
    local current_status=$(get_wol_status "$adapter")

    # Check if already enabled
    if [[ "$current_status" == "g" ]]; then
      log_info "$adapter: Wake-on-LAN already enabled (magic packet mode)"

      # Check if systemd service exists
      if [ -f "/etc/systemd/system/wol-$adapter.service" ]; then
        log_info "$adapter: Systemd service already exists"
        ((configured_count++))
        continue
      fi
    fi

    # Enable Wake-on-LAN (magic packet mode)
    if sudo ethtool -s "$adapter" wol g 2>/dev/null; then
      log_success "$adapter: Wake-on-LAN enabled (magic packet mode)"

      # Get MAC address for user information
      local mac_address=$(get_interface_mac "$adapter")
      if [ -n "$mac_address" ]; then
        log_info "$adapter MAC address: $mac_address"
      fi

      # Create systemd service for persistence
      create_wol_systemd_service "$adapter"

      if [ $? -eq 0 ]; then
        ((configured_count++))
      else
        log_warning "$adapter: WoL enabled but systemd service creation failed"
        ((failed_count++))
      fi
    else
      log_error "$adapter: Failed to enable Wake-on-LAN"
      ((failed_count++))
    fi
  done

  # Summary
  echo ""
  if [ $configured_count -gt 0 ]; then
    log_success "Wake-on-LAN configured for $configured_count adapter(s)"

    # Show MAC addresses for all configured adapters
    echo ""
    log_info "Wake-on-LAN MAC addresses:"
    for adapter in "${adapters[@]}"; do
      local mac=$(get_interface_mac "$adapter")
      if [ -n "$mac" ] && check_wol_support "$adapter"; then
        local status=$(get_wol_status "$adapter")
        if [[ "$status" == "g" ]]; then
          echo -e "  ${GREEN}$adapter${RESET}: $mac ${GREEN}(enabled)${RESET}"
        fi
      fi
    done
    echo ""
    log_info "To wake this computer remotely, use: wakeonlan <MAC_ADDRESS>"
  fi

  if [ $skipped_count -gt 0 ]; then
    log_warning "$skipped_count adapter(s) skipped (no WoL support)"
  fi

  if [ $failed_count -gt 0 ]; then
    log_warning "$failed_count adapter(s) failed to configure"
  fi

  return 0
}

# Function to create systemd service for Wake-on-LAN persistence
create_wol_systemd_service() {
  local adapter="$1"
  local service_file="/etc/systemd/system/wol-$adapter.service"

  # Check if service already exists
  if [ -f "$service_file" ]; then
    log_info "$adapter: Systemd service already exists"
    return 0
  fi

  # Create the systemd service file
  sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Enable Wake-on-LAN for $adapter
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ethtool -s $adapter wol g
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  if [ $? -eq 0 ]; then
    # Reload systemd and enable the service
    sudo systemctl daemon-reload 2>/dev/null
    if sudo systemctl enable "wol-$adapter.service" 2>/dev/null; then
      log_success "$adapter: Systemd service created and enabled"
      return 0
    else
      log_warning "$adapter: Systemd service created but failed to enable"
      return 1
    fi
  else
    log_error "$adapter: Failed to create systemd service"
    return 1
  fi
}

# Execute all service and maintenance steps
setup_firewall_and_services
check_battery_status
detect_memory_size
setup_zram_swap
detect_filesystem_type
detect_storage_type
detect_audio_system
detect_kernel_type
detect_de_version
detect_bluetooth_hardware
detect_hybrid_graphics
setup_laptop_optimizations
setup_wake_on_lan
