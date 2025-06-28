#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ======= GameMode Setup Steps =======
install_gamemode() {
  step "Installing GameMode"
  install_packages_quietly gamemode lib32-gamemode
}

configure_gamemode() {
  step "Configuring GameMode"
  local CONFIG_FILE="/etc/gamemode.ini"
  
  # Check if running in a VM
  if systemd-detect-virt --quiet; then
    log_warning "VM detected. Using minimal GameMode configuration."
    
    # Create minimal config for VM
    sudo tee "$CONFIG_FILE" >/dev/null << 'EOF'
[general]
# GameMode configuration for VM environment
# Reduced settings to avoid conflicts with VM

[gpu]
# Disable GPU optimizations in VM
apply_gpu_optimisations=0
gpu_device=0

[cpu]
# Conservative CPU settings for VM
desired_governor=performance
min_freq=0
max_freq=0

[general]
# Reduced logging for VM
soft_realtime=off
ioprio_class=0
ioprio_level=0
EOF
    log_success "Minimal GameMode config written to $CONFIG_FILE (VM detected)"
  else
    # Create full config for physical machine
    sudo tee "$CONFIG_FILE" >/dev/null << 'EOF'
[general]
# GameMode configuration
# Optimized for gaming performance

[gpu]
# GPU optimizations
apply_gpu_optimisations=1
gpu_device=0
gpu_power_threshold=50

[cpu]
# CPU optimizations
desired_governor=performance
min_freq=0
max_freq=0
energy_performance_preference=performance

[general]
# General optimizations
soft_realtime=on
ioprio_class=1
ioprio_level=4
EOF
    log_success "GameMode config written to $CONFIG_FILE"
  fi
}

create_gamemode_scripts() {
  step "Creating GameMode start/end scripts"
  
  # Create gamemode start script
  sudo tee /usr/local/bin/gamemode-start >/dev/null << 'EOF'
#!/bin/bash
# GameMode start script
# This script runs when GameMode starts

# Log GameMode start
logger "GameMode started for process $1"

# Additional optimizations can be added here
# For example: disable compositor, set CPU governor, etc.

exit 0
EOF

  # Create gamemode end script
  sudo tee /usr/local/bin/gamemode-end >/dev/null << 'EOF'
#!/bin/bash
# GameMode end script
# This script runs when GameMode ends

# Log GameMode end
logger "GameMode ended for process $1"

# Restore normal settings
# For example: re-enable compositor, restore CPU governor, etc.

exit 0
EOF

  # Make scripts executable
  sudo chmod +x /usr/local/bin/gamemode-start
  sudo chmod +x /usr/local/bin/gamemode-end

  # Update gamemode config to use custom scripts
  if [ -f "/etc/gamemode.ini" ]; then
    sudo sed -i '/^\[general\]/a start=/usr/local/bin/gamemode-start\nend=/usr/local/bin/gamemode-end' /etc/gamemode.ini
  fi

  log_success "GameMode start/end scripts installed."
  log_success "GameMode with safe system optimizations configured successfully."
}

# ======= Main =======
main() {
  echo -e "${CYAN}=== GameMode Setup ===${RESET}"

  # Check if GameMode is already installed
  if pacman -Q gamemode &>/dev/null; then
    log_success "GameMode is already installed."
  else
    install_gamemode
  fi

  # Configure GameMode
  configure_gamemode

  # Create custom scripts
  create_gamemode_scripts

  echo -e "\n${GREEN}GameMode setup completed successfully!${RESET}"
  echo -e "${CYAN}You can now use 'gamemoderun <command>' to run applications with GameMode.${RESET}"
}

main "$@"
