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
    reflector.service
    reflector.timer
    sshd.service
    ufw.service
  )
  step "Enabling the following system services:"
  for svc in "${services[@]}"; do
    echo -e "  - $svc"
  done
  sudo systemctl enable --now "${services[@]}" 2>/dev/null || true
}

setup_zram_swap() {
  step "Setting up ZRAM swap"
  
  # Create ZRAM config in one command
  sudo tee /etc/systemd/zram-generator.conf > /dev/null << EOF
[zram0]
zram-size = ram * 0.5
compression-algorithm = zstd
swap-priority = 100
EOF
  
  # Enable and start ZRAM
  sudo systemctl enable --now systemd-zram-setup@zram0 2>/dev/null || true
}

detect_and_install_gpu_drivers() {
  step "Detecting and installing graphics drivers"

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
    echo "Please select the NVIDIA driver to install:"
    echo "  1) nvidia-open (open kernel modules, newer cards only)"
    echo "  2) nouveau (open source, basic support)"
    echo "  3) proprietary (nvidia, closed source)"
    local nvidia_choice
    while true; do
      read -r -p "Enter your choice [1-3]: " nvidia_choice
      case "$nvidia_choice" in
        1)
          echo -e "${CYAN}Installing nvidia-open drivers...${RESET}"
          install_packages_quietly nvidia-open-dkms nvidia-utils lib32-nvidia-utils
          log_success "nvidia-open drivers installed."
          break
          ;;
        2)
          echo -e "${CYAN}Installing nouveau drivers...${RESET}"
          install_packages_quietly mesa xf86-video-nouveau vulkan-nouveau lib32-vulkan-nouveau
          log_success "nouveau drivers installed."
          break
          ;;
        3)
          echo -e "${CYAN}Installing proprietary NVIDIA drivers...${RESET}"
          install_packages_quietly nvidia nvidia-utils lib32-nvidia-utils
          log_success "Proprietary NVIDIA drivers installed."
          break
          ;;
        *)
          echo -e "${RED}Invalid choice! Please enter 1, 2, or 3.${RESET}"
          ;;
      esac
    done
  else
    echo -e "${YELLOW}No AMD, Intel, or NVIDIA GPU detected. Installing basic Mesa drivers only.${RESET}"
    install_packages_quietly mesa
  fi
}

# Execute all service and maintenance steps
setup_firewall_and_services
setup_zram_swap
detect_and_install_gpu_drivers 