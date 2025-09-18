#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

setup_system_services() {
  step "Setting up system services"

  # System services using unified function
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
    log_success "rustdesk detected - service will be enabled"
  fi

  enable_system_services "${services[@]}"
}

# Firewall functions moved to security_setup.sh

# Function to get total RAM in GB with proper rounding
get_ram_gb() {
  local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  # Use proper rounding instead of truncation
  # Add 512MB (524288 KB) before dividing to round to nearest GB
  echo $(((ram_kb + 524288) / 1024 / 1024))
}

# Detect if gaming mode is enabled
detect_gaming_mode() {
  # Check various indicators that gaming mode was selected
  if [[ "$INSTALL_MODE" == *"gaming"* ]] || \
     [[ -f "/tmp/gaming_mode_enabled" ]] || \
     [[ -f "/tmp/archinstaller_gaming" ]] || \
     command -v steam >/dev/null 2>&1 || \
     command -v lutris >/dev/null 2>&1; then
    return 0  # Gaming mode detected
  fi
  return 1    # Regular mode
}

# Get optimal ZRAM configuration based on system profile
get_zram_config() {
  local ram_gb=$1
  local profile=$2

  if [ "$profile" = "gaming" ]; then
    # Gaming Profile - Aggressive ZRAM allocation for maximum performance
    case $ram_gb in
      1|2) echo "1.5 150" ;;     # 1-2GB RAM -> 150% ZRAM, swappiness 150
      3|4) echo "1.25 150" ;;    # 3-4GB RAM -> 125% ZRAM, swappiness 150
      6|8) echo "1.0 160" ;;     # 6-8GB RAM -> 100% ZRAM, swappiness 160
      12|16) echo "0.75 160" ;;  # 12-16GB RAM -> 75% ZRAM, swappiness 160
      24|32) echo "0.5 180" ;;   # 24-32GB RAM -> 50% ZRAM, swappiness 180
      *)
        if [ "$ram_gb" -le 4 ]; then
          echo "1.25 150"
        elif [ "$ram_gb" -le 16 ]; then
          echo "0.75 160"
        else
          echo "0.4 180"
        fi
        ;;
    esac
  else
    # Regular Profile - Conservative ZRAM allocation for stability
    case $ram_gb in
      1|2) echo "1.0 90" ;;      # 1-2GB RAM -> 100% ZRAM, swappiness 90
      3|4) echo "0.75 90" ;;     # 3-4GB RAM -> 75% ZRAM, swappiness 90
      6|8) echo "0.6 100" ;;     # 6-8GB RAM -> 60% ZRAM, swappiness 100
      12|16) echo "0.4 100" ;;   # 12-16GB RAM -> 40% ZRAM, swappiness 100
      24|32) echo "0.3 80" ;;    # 24-32GB RAM -> 30% ZRAM, swappiness 80
      *)
        if [ "$ram_gb" -le 4 ]; then
          echo "0.75 90"
        elif [ "$ram_gb" -le 16 ]; then
          echo "0.4 100"
        else
          echo "0.25 80"
        fi
        ;;
    esac
  fi
}

# Apply kernel parameters for ZRAM optimization
apply_zram_kernel_params() {
  local profile=$1
  local swappiness=$2

  step "Applying ZRAM kernel optimizations for $profile profile"

  # Create sysctl configuration for ZRAM
  local sysctl_file="/etc/sysctl.d/99-archinstaller-zram.conf"

  if [ "$profile" = "gaming" ]; then
    # Gaming profile - aggressive optimizations for maximum performance
    sudo tee "$sysctl_file" > /dev/null << EOF
# ZRAM Gaming Profile Optimizations
# Applied by archinstaller for gaming systems

# Set swappiness for aggressive ZRAM usage
vm.swappiness = $swappiness

# Reduce memory fragmentation for gaming performance
vm.watermark_boost_factor = 0

# More aggressive free memory maintenance
vm.watermark_scale_factor = 125

# Disable swap readahead for ZRAM (better for compressed swap)
vm.page-cluster = 0

# Reduce cache pressure for gaming workloads
vm.vfs_cache_pressure = 50

# Optimize memory reclaim for gaming
vm.dirty_ratio = 5
vm.dirty_background_ratio = 1
EOF
    log_success "Applied gaming performance optimizations (swappiness: $swappiness)"
  else
    # Regular profile - balanced optimizations
    sudo tee "$sysctl_file" > /dev/null << EOF
# ZRAM Regular Profile Optimizations
# Applied by archinstaller for general desktop use

# Set moderate swappiness for balanced ZRAM usage
vm.swappiness = $swappiness

# Conservative memory management
vm.vfs_cache_pressure = 60

# Standard memory reclaim settings
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF
    log_success "Applied regular profile kernel optimizations (swappiness: $swappiness)"
  fi

  # Disable zswap to prevent conflicts with ZRAM
  if ! grep -q "zswap.enabled=0" /etc/default/grub 2>/dev/null && [ -f /etc/default/grub ]; then
    sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&zswap.enabled=0 /' /etc/default/grub
    log_success "Disabled zswap to prevent conflicts with ZRAM"
  fi

  # Apply sysctl settings immediately
  sudo sysctl -p "$sysctl_file" >/dev/null 2>&1 || true
}

setup_zram_swap() {
  step "Setting up intelligent ZRAM swap"

  # Check if ZRAM is already configured
  if systemctl is-active --quiet systemd-zram-setup@zram0; then
    log_success "ZRAM is already active"
    return 0
  fi

  # Detect system profile
  local profile="regular"
  if detect_gaming_mode; then
    profile="gaming"
    log_info "Gaming system detected - using performance-optimized ZRAM profile"
  else
    log_info "Regular system detected - using balanced ZRAM profile"
  fi

  # Get system RAM and optimal configuration
  local ram_gb=$(get_ram_gb)
  local config=$(get_zram_config $ram_gb $profile)
  local multiplier=$(echo $config | cut -d' ' -f1)
  local swappiness=$(echo $config | cut -d' ' -f2)
  local zram_size_gb=$(echo "$ram_gb * $multiplier" | bc -l | cut -d. -f1)

  log_info "System RAM: ${ram_gb}GB"
  log_info "ZRAM Profile: $profile (${multiplier}x multiplier, ${zram_size_gb}GB effective, swappiness: $swappiness)"

  # Apply kernel optimizations for the selected profile
  apply_zram_kernel_params "$profile" "$swappiness"

  # Create optimized ZRAM configuration
  sudo tee /etc/systemd/zram-generator.conf > /dev/null << EOF
# ZRAM Configuration - $profile profile
# Generated by archinstaller with intelligent optimization
[zram0]
zram-size = ram * ${multiplier}
compression-algorithm = zstd
swap-priority = 100
EOF

  # Enable and start ZRAM services
  enable_system_services systemd-zram-setup@zram0

  if [ "$profile" = "gaming" ]; then
    log_success "Gaming-optimized ZRAM configured with performance-focused tuning"
    log_info "Benefits: Maximum RAM utilization, reduced stuttering, better game performance"
  else
    log_success "Balanced ZRAM configured for general desktop use"
    log_info "Benefits: Improved multitasking, stable performance, efficient memory usage"
  fi
}

detect_and_install_gpu_drivers() {
  step "Detecting and installing graphics drivers"

  # VM detection function (from gamemode.sh)
  is_vm() {
    if grep -q -i 'hypervisor' /proc/cpuinfo; then
      return 0
    fi
    if systemd-detect-virt --quiet; then
      return 0
    fi
    if [ -d /proc/xen ]; then
      return 0
    fi
    return 1
  }

  if is_vm; then
    step "Installing VM guest utilities"
    install_packages_quietly qemu-guest-agent spice-vdagent xf86-video-qxl
    log_success "VM guest utilities installed"
    return
  fi

  if lspci | grep -Eiq 'vga.*amd|3d.*amd|display.*amd'; then
    step "Installing AMD GPU drivers"
    install_packages_quietly mesa xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon mesa-vdpau libva-mesa-driver lib32-mesa-vdpau lib32-libva-mesa-driver
    log_success "AMD drivers and Vulkan support installed"
  elif lspci | grep -Eiq 'vga.*intel|3d.*intel|display.*intel'; then
    step "Installing Intel GPU drivers"
    install_packages_quietly mesa vulkan-intel lib32-vulkan-intel mesa-vdpau libva-mesa-driver lib32-mesa-vdpau lib32-libva-mesa-driver
    log_success "Intel drivers and Vulkan support installed"
  elif lspci | grep -qi nvidia; then
    echo -e "${YELLOW}NVIDIA GPU detected.${RESET}"

    # Get PCI ID and map to family
    nvidia_pciid=$(lspci -n -d ::0300 | grep -i nvidia | awk '{print $3}' | head -n1)
    nvidia_family=""
    nvidia_pkg=""
    nvidia_note=""

    # Map PCI ID to family (simplified, for full mapping see ArchWiki and Nouveau code names)
    if lspci | grep -Eiq 'TU|GA|AD|Turing|Ampere|Lovelace'; then
      nvidia_family="Turing or newer"
      nvidia_pkg="nvidia-open-dkms nvidia-utils lib32-nvidia-utils"
      nvidia_note="(open kernel modules, recommended for Turing/Ampere/Lovelace)"
    elif lspci | grep -Eiq 'GM|GP|Maxwell|Pascal'; then
      nvidia_family="Maxwell or newer"
      nvidia_pkg="nvidia nvidia-utils lib32-nvidia-utils"
      nvidia_note="(proprietary, recommended for Maxwell/Pascal)"
    elif lspci | grep -Eiq 'GK|Kepler'; then
      nvidia_family="Kepler"
      nvidia_pkg="nvidia-470xx-dkms"
      nvidia_note="(legacy, AUR, unsupported)"
    elif lspci | grep -Eiq 'GF|Fermi'; then
      nvidia_family="Fermi"
      nvidia_pkg="nvidia-390xx-dkms"
      nvidia_note="(legacy, AUR, unsupported)"
    elif lspci | grep -Eiq 'G8|Tesla'; then
      nvidia_family="Tesla"
      nvidia_pkg="nvidia-340xx-dkms"
      nvidia_note="(legacy, AUR, unsupported)"
    else
      nvidia_family="Unknown"
      nvidia_pkg="nvidia nvidia-utils lib32-nvidia-utils"
      nvidia_note="(defaulting to latest proprietary driver)"
    fi

    step "Installing NVIDIA GPU drivers ($nvidia_family)"

    if [[ "$nvidia_family" == "Kepler" || "$nvidia_family" == "Fermi" || "$nvidia_family" == "Tesla" ]]; then
      echo -e "${YELLOW}Your NVIDIA GPU is legacy and may not be well supported by the proprietary driver, especially on Wayland.${RESET}"
      echo "For best Wayland support, it is recommended to use the open-source Nouveau driver."
      echo "Choose driver to install:"
      echo "  1) Nouveau (open source, best for Wayland, basic 3D support)"
      echo "  2) Proprietary legacy NVIDIA driver (AUR, may not work with Wayland, unsupported)"
      local legacy_choice
      while true; do
        read -r -p "Enter your choice [1-2]: " legacy_choice
        case "$legacy_choice" in
          1)
            install_packages_quietly mesa xf86-video-nouveau vulkan-nouveau lib32-vulkan-nouveau
            log_success "Nouveau drivers installed"
            break
            ;;
          2)
            ensure_yay_installed || { log_error "Could not install yay to get legacy drivers."; break; }
            if [[ "$nvidia_family" == "Kepler" ]]; then
              yay -S --noconfirm --needed nvidia-470xx-dkms >/dev/null 2>&1
            elif [[ "$nvidia_family" == "Fermi" ]]; then
              yay -S --noconfirm --needed nvidia-390xx-dkms >/dev/null 2>&1
            elif [[ "$nvidia_family" == "Tesla" ]]; then
              yay -S --noconfirm --needed nvidia-340xx-dkms >/dev/null 2>&1
            fi
            log_success "Legacy proprietary NVIDIA drivers installed"
            break
            ;;
          *)
            echo -e "${RED}Invalid choice! Please enter 1 or 2.${RESET}"
            ;;
        esac
      done
      return
    fi

    # If AUR package, warn user
    if [[ "$nvidia_pkg" == *"dkms"* && "$nvidia_pkg" != *"nvidia-open-dkms"* ]]; then
      log_warning "This is a legacy/unsupported NVIDIA card. The driver will be installed from the AUR if yay is available."
      if ! command -v yay &>/dev/null; then
        log_error "yay (AUR helper) is not installed. Cannot install legacy NVIDIA driver."
        return 1
      fi
      yay -S --noconfirm --needed $nvidia_pkg
    else
      install_packages_quietly $nvidia_pkg
    fi

    log_success "NVIDIA drivers installed."
    return
  else
    step "Installing basic Mesa drivers"
    install_packages_quietly mesa
    log_success "Basic Mesa drivers installed"
  fi
}

# SSH Hardening - moved here to happen AFTER SSH service is enabled
harden_ssh() {
  step "Hardening SSH configuration"

  log_info "Applying SSH security hardening automatically"

  # Verify SSH service is running and host keys exist
  local max_attempts=10
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if systemctl is-active sshd >/dev/null 2>&1 && [ -f "/etc/ssh/ssh_host_rsa_key" ]; then
      log_success "SSH service is active and host keys are present"
      break
    fi

    if [ $attempt -eq 0 ]; then
      log_info "Waiting for SSH service to fully initialize..."
    fi

    sleep 2
    ((attempt++))

    if [ $attempt -eq $max_attempts ]; then
      log_error "SSH service failed to start properly or host keys missing"
      return 1
    fi
  done

  local ssh_config="/etc/ssh/sshd_config"
  local ssh_backup="/etc/ssh/sshd_config.backup"

  # Create backup if it doesn't exist
  if [ ! -f "$ssh_backup" ]; then
    sudo cp "$ssh_config" "$ssh_backup"
    log_success "Created SSH config backup"
  fi

  # Apply SSH hardening settings
  local ssh_settings=(
    "PermitRootLogin no"
    "PasswordAuthentication yes"
    "PubkeyAuthentication yes"
    "X11Forwarding no"
    "MaxAuthTries 3"
    "ClientAliveInterval 300"
    "ClientAliveCountMax 2"
    "Protocol 2"
  )

  for setting in "${ssh_settings[@]}"; do
    local key=$(echo "$setting" | cut -d' ' -f1)
    local value=$(echo "$setting" | cut -d' ' -f2-)

    if grep -q "^#*$key" "$ssh_config"; then
      sudo sed -i "s/^#*$key.*/$setting/" "$ssh_config"
    else
      echo "$setting" | sudo tee -a "$ssh_config" >/dev/null
    fi
  done

  log_success "SSH hardening applied"

  # Test SSH config (should work now since service is enabled and keys exist)
  if sudo sshd -t; then
    log_success "SSH configuration is valid"
    # Restart SSH service to apply changes
    if sudo systemctl restart sshd; then
      log_success "SSH service restarted with hardened configuration"
    else
      log_warning "SSH service restart failed"
      return 1
    fi
  else
    log_error "SSH configuration has errors - restoring backup"
    sudo cp "$ssh_backup" "$ssh_config"
    sudo systemctl restart sshd
    return 1
  fi
}

# Execute all service and system configuration steps
main() {
  setup_system_services
  harden_ssh
  setup_zram_swap
  detect_and_install_gpu_drivers
}

# Run main function
main
