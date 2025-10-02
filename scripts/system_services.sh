#!/bin/bash
set -euo pipefail

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

  # Then handle services
  run_step "Enabling system services" enable_services
}

configure_firewalld() {
  # Start and enable firewalld
  sudo systemctl start firewalld
  sudo systemctl enable firewalld

  # Set default policies
  sudo firewall-cmd --set-default-zone=drop
  log_success "Default policy set to deny all incoming connections."

  sudo firewall-cmd --set-default-zone=public
  log_success "Default policy set to allow all outgoing connections."

  # Allow SSH
  if ! sudo firewall-cmd --list-all | grep -q "22/tcp"; then
    sudo firewall-cmd --add-service=ssh --permanent
    sudo firewall-cmd --reload
    log_success "SSH allowed through Firewalld."
  else
    log_warning "SSH is already allowed. Skipping SSH service configuration."
  fi

  # Check if KDE Connect is installed
  if pacman -Q kdeconnect &>/dev/null; then
    # Allow specific ports for KDE Connect
    sudo firewall-cmd --add-port=1714-1764/udp --permanent
    sudo firewall-cmd --add-port=1714-1764/tcp --permanent
    sudo firewall-cmd --reload
    log_success "KDE Connect ports allowed through Firewalld."
  else
    log_warning "KDE Connect is not installed. Skipping KDE Connect service configuration."
  fi
}

configure_ufw() {
  # Install UFW if not present
  if ! command -v ufw >/dev/null 2>&1; then
    install_packages_quietly ufw
    log_success "UFW installed successfully."
  fi

  # Enable UFW
  sudo ufw enable

  # Set default policies
  sudo ufw default deny incoming
  log_success "Default policy set to deny all incoming connections."

  sudo ufw default allow outgoing
  log_success "Default policy set to allow all outgoing connections."

  # Allow SSH
  if ! sudo ufw status | grep -q "22/tcp"; then
    sudo ufw allow ssh
    log_success "SSH allowed through UFW."
  else
    log_warning "SSH is already allowed. Skipping SSH service configuration."
  fi

  # Check if KDE Connect is installed
  if pacman -Q kdeconnect &>/dev/null; then
    # Allow specific ports for KDE Connect
    sudo ufw allow 1714:1764/udp
    sudo ufw allow 1714:1764/tcp
    log_success "KDE Connect ports allowed through UFW."
  else
    log_warning "KDE Connect is not installed. Skipping KDE Connect service configuration."
  fi
}

enable_services() {
  local services=(
    bluetooth.service
    cronie.service
    fstrim.timer
    paccache.timer
    power-profiles-daemon.service
    sshd.service
    ufw.service
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

# Function to get total RAM in GB
get_ram_gb() {
  local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  echo $((ram_kb / 1024 / 1024))
}

# Function to get optimal ZRAM size multiplier based on RAM
get_zram_multiplier() {
  local ram_gb=$1
  case $ram_gb in
    1) echo "2.0" ;;      # 1GB RAM -> 200% ZRAM (2GB)
    2) echo "1.5" ;;      # 2GB RAM -> 150% ZRAM (3GB)
    3) echo "1.33" ;;     # 3GB RAM -> 133% ZRAM (4GB)
    4) echo "1.0" ;;      # 4GB RAM -> 100% ZRAM (4GB)
    6) echo "0.83" ;;     # 6GB RAM -> 83% ZRAM (5GB)
    8) echo "0.75" ;;     # 8GB RAM -> 75% ZRAM (6GB)
    10) echo "0.6" ;;     # 10GB RAM -> 60% ZRAM (6GB)
    12) echo "0.5" ;;     # 12GB RAM -> 50% ZRAM (6GB)
    15) echo "0.5" ;;     # 15GB RAM -> 50% ZRAM (8GB) - treat as 16GB
    16) echo "0.5" ;;     # 16GB RAM -> 50% ZRAM (8GB)
    24) echo "0.33" ;;    # 24GB RAM -> 33% ZRAM (8GB)
    31) echo "0.25" ;;    # 31GB RAM -> 25% ZRAM (8GB) - treat as 32GB
    32) echo "0.25" ;;    # 32GB RAM -> 25% ZRAM (8GB)
    48) echo "0.25" ;;    # 48GB RAM -> 25% ZRAM (12GB)
    64) echo "0.2" ;;     # 64GB RAM -> 20% ZRAM (12.8GB)
    *)
      # For other sizes, use a dynamic calculation
      if [ $ram_gb -le 4 ]; then
        echo "1.0"
      elif [ $ram_gb -le 8 ]; then
        echo "0.75"
      elif [ $ram_gb -le 16 ]; then
        echo "0.5"
      elif [ $ram_gb -le 32 ]; then
        echo "0.33"
      else
        echo "0.25"
      fi
      ;;
  esac
}

# Function to check and manage traditional swap
check_traditional_swap() {
  step "Checking for traditional swap partitions/files"

  # Check if any swap is active
  if swapon --show | grep -q '/'; then
    log_info "Traditional swap detected"
    swapon --show

    if command -v gum >/dev/null 2>&1; then
      if gum confirm --default=true "Disable traditional swap in favor of ZRAM?"; then
        log_info "Disabling traditional swap..."
        sudo swapoff -a

        # Comment out swap entries in fstab
        if grep -q '^[^#].*swap' /etc/fstab; then
          sudo sed -i.bak '/^[^#].*swap/s/^/# /' /etc/fstab
          log_success "Traditional swap disabled and fstab updated (backup saved)"
        fi
      else
        log_warning "Traditional swap kept active alongside ZRAM"
        return 1
      fi
    else
      read -r -p "Disable traditional swap in favor of ZRAM? [Y/n]: " response
      response=${response,,}
      if [[ "$response" != "n" && "$response" != "no" ]]; then
        log_info "Disabling traditional swap..."
        sudo swapoff -a

        # Comment out swap entries in fstab
        if grep -q '^[^#].*swap' /etc/fstab; then
          sudo sed -i.bak '/^[^#].*swap/s/^/# /' /etc/fstab
          log_success "Traditional swap disabled and fstab updated (backup saved)"
        fi
      else
        log_warning "Traditional swap kept active alongside ZRAM"
        return 1
      fi
    fi
  else
    log_info "No traditional swap detected - good for ZRAM setup"
  fi
  return 0
}

setup_zram_swap() {
  step "Setting up ZRAM swap"

  # Check if ZRAM is already enabled
  if ! systemctl is-active --quiet systemd-zram-setup@zram0; then
    echo -e "${YELLOW}ZRAM is not enabled or is disabled.${RESET}"
    if command -v gum >/dev/null 2>&1; then
      gum confirm --default=false "Would you like to enable and configure ZRAM swap?" || {
        echo -e "${YELLOW}ZRAM configuration skipped by user.${RESET}"
        return
      }
    else
      read -r -p "Would you like to enable and configure ZRAM swap? [y/N]: " response
      response=${response,,}
      if [[ "$response" != "y" && "$response" != "yes" ]]; then
        echo -e "${YELLOW}ZRAM configuration skipped by user.${RESET}"
        return
      fi
    fi

    # Check and manage traditional swap first
    check_traditional_swap

    # Enable ZRAM service
    sudo systemctl enable systemd-zram-setup@zram0
    sudo systemctl start systemd-zram-setup@zram0
  fi

  # Get system RAM and optimal multiplier
  local ram_gb=$(get_ram_gb)
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
    echo -e "${YELLOW}Virtual machine detected. Installing VM guest utilities and skipping physical GPU drivers.${RESET}"
    install_packages_quietly qemu-guest-agent spice-vdagent xf86-video-qxl
    log_success "VM guest utilities installed."
    return
  fi

  if lspci | grep -Eiq 'vga.*amd|3d.*amd|display.*amd'; then
    echo -e "${CYAN}AMD GPU detected. Installing AMD drivers and Vulkan support...${RESET}"
    install_packages_quietly mesa xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon mesa-vdpau libva-mesa-driver lib32-mesa-vdpau lib32-libva-mesa-driver
    log_success "AMD drivers and Vulkan support installed"
    log_info "AMD GPU will use AMDGPU driver after reboot"
  elif lspci | grep -Eiq 'vga.*intel|3d.*intel|display.*intel'; then
    echo -e "${CYAN}Intel GPU detected. Installing Intel drivers and Vulkan support...${RESET}"
    install_packages_quietly mesa vulkan-intel lib32-vulkan-intel mesa-vdpau libva-mesa-driver lib32-mesa-vdpau lib32-libva-mesa-driver
    log_success "Intel drivers and Vulkan support installed"
    log_info "Intel GPU will use i915 or xe driver after reboot"
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

    echo -e "${CYAN}Detected NVIDIA family: $nvidia_family $nvidia_note${RESET}"
    echo -e "${CYAN}Installing: $nvidia_pkg${RESET}"

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
            echo -e "${CYAN}Installing Nouveau drivers...${RESET}"
            install_packages_quietly mesa xf86-video-nouveau vulkan-nouveau lib32-vulkan-nouveau
            log_success "Nouveau drivers installed."
            break
            ;;
          2)
            echo -e "${CYAN}Installing legacy proprietary NVIDIA drivers...${RESET}"
            if [[ "$nvidia_family" == "Kepler" ]]; then
              yay -S --noconfirm --needed nvidia-470xx-dkms
            elif [[ "$nvidia_family" == "Fermi" ]]; then
              yay -S --noconfirm --needed nvidia-390xx-dkms
            elif [[ "$nvidia_family" == "Tesla" ]]; then
              yay -S --noconfirm --needed nvidia-340xx-dkms
            fi
            log_success "Legacy proprietary NVIDIA drivers installed."
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
    echo -e "${YELLOW}No AMD, Intel, or NVIDIA GPU detected. Installing basic Mesa drivers only.${RESET}"
    install_packages_quietly mesa
  fi

  # Verify GPU driver is loaded
  verify_gpu_driver
}

# Function to verify GPU driver is loaded correctly
verify_gpu_driver() {
  step "Verifying GPU driver installation"

  # Check which driver is in use
  if lspci -k | grep -A 3 -iE 'vga|3d|display' | grep -iq 'Kernel driver in use'; then
    log_info "GPU driver status:"
    lspci -k | grep -A 3 -iE 'vga|3d|display' | grep -E 'VGA|3D|Display|Kernel driver'
    log_success "GPU driver is loaded and in use"
  else
    log_warning "Could not verify GPU driver status"
    log_info "Run 'lspci -k | grep -A 3 -iE \"vga|3d|display\"' after reboot to check driver"
  fi

  # Check for Vulkan support
  if command -v vulkaninfo >/dev/null 2>&1; then
    if vulkaninfo --summary &>/dev/null; then
      log_success "Vulkan support verified"
    else
      log_warning "Vulkan may not be properly configured"
    fi
  else
    log_info "Install vulkan-tools to verify Vulkan support: sudo pacman -S vulkan-tools"
  fi
}

# Execute all service and maintenance steps
setup_firewall_and_services
setup_zram_swap
detect_and_install_gpu_drivers
