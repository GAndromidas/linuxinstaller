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

setup_zram_swap() {
  step "Setting up ZRAM swap"

  # Check if ZRAM is already configured
  if systemctl is-active --quiet systemd-zram-setup@zram0; then
    log_success "ZRAM is already active"
    return 0
  fi

  # Interactive confirmation
  local enable_zram=false
  if command -v gum >/dev/null 2>&1; then
    gum confirm --default=false "Would you like to enable and configure ZRAM swap?" && enable_zram=true
  else
    read -r -p "Would you like to enable and configure ZRAM swap? [y/N]: " response
    response=${response,,}
    [[ "$response" =~ ^(y|yes)$ ]] && enable_zram=true
  fi

  if [ "$enable_zram" = false ]; then
    log_info "ZRAM configuration skipped by user"
    return 0
  fi

  # Get system RAM and optimal multiplier
  local ram_gb=$(get_ram_gb)
  local multiplier=$(get_zram_multiplier $ram_gb)
  local zram_size_gb=$(echo "$ram_gb * $multiplier" | bc -l | cut -d. -f1)

  log_info "System RAM: ${ram_gb}GB, ZRAM multiplier: ${multiplier} (${zram_size_gb}GB effective)"

  # Create optimized ZRAM configuration
  sudo tee /etc/systemd/zram-generator.conf > /dev/null << EOF
[zram0]
zram-size = ram * ${multiplier}
compression-algorithm = zstd
swap-priority = 100
EOF

  # Enable and start ZRAM services
  enable_system_services systemd-zram-setup@zram0
  log_success "ZRAM swap configured and enabled"
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
    log_success "AMD drivers and Vulkan support installed."
  elif lspci | grep -Eiq 'vga.*intel|3d.*intel|display.*intel'; then
    echo -e "${CYAN}Intel GPU detected. Installing Intel drivers and Vulkan support...${RESET}"
    install_packages_quietly mesa vulkan-intel lib32-vulkan-intel mesa-vdpau libva-mesa-driver lib32-mesa-vdpau lib32-libva-mesa-driver
    log_success "Intel drivers and Vulkan support installed."
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
}

# Execute all service and system configuration steps
main() {
  setup_system_services
  setup_zram_swap
  detect_and_install_gpu_drivers
}

# Run main function
main
