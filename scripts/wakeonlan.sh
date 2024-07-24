#!/bin/bash

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to install packages based on distribution
install_packages() {
  local distro=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
  if [[ "$distro" == *"Arch"* || "$distro" == *"Arch Linux"* ]]; then
    echo -e "${GREEN}Detected Arch Linux${NC}"
    sudo pacman -S --noconfirm ethtool
  else
    echo -e "${YELLOW}Unsupported distribution: $distro${NC}"
    exit 1
  fi
}

# Function to enable Wake-on-LAN
enable_wake_on_lan() {
  local connection_name=$(get_ethernet_connection_name)
  if [ -n "$connection_name" ]; then
    echo -e "${GREEN}Enabling Wake-on-LAN on $connection_name...${NC}"
    # Set WoL setting
    sudo ethtool -s "$connection_name" wol g

    # Create systemd service file to persist WoL setting
    create_systemd_service "$connection_name"
  else
    echo -e "${YELLOW}Error: No Ethernet adapter found.${NC}"
    exit 1
  fi
}

# Function to create systemd service for persistent Wake-on-LAN
create_systemd_service() {
  local connection_name="$1"
  local service_file="/etc/systemd/system/wol-$connection_name.service"

  # Create the systemd service file
  sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Enable Wake-on-LAN for $connection_name

[Service]
Type=oneshot
ExecStart=/sbin/ethtool -s $connection_name wol g

[Install]
WantedBy=multi-user.target
EOF

  # Reload systemd daemon and enable the service
  sudo systemctl daemon-reload
  sudo systemctl enable "wol-$connection_name.service"
}

# Function to get Ethernet connection name
get_ethernet_connection_name() {
  local eth_interface=""

  # Check for specific interfaces
  if ip link show enp3s0 &> /dev/null; then
    eth_interface="enp3s0"
  elif ip link show enp5s0 &> /dev/null; then
    eth_interface="enp5s0"
  elif ip link show eth0 &> /dev/null; then
    eth_interface="eth0"
  else
    # If none of the specific interfaces are found, scan for any interface starting with 'enp' or 'eth'
    eth_interface=$(ip link show | grep -oP '(?<=: ).*(?=:)' | grep -E 'enp|eth' | head -n 1)
  fi

  echo "$eth_interface"
}

# Function to get MAC address of the adapter
get_mac_address() {
  local mac_address=$(ip link show $(ip route show default | awk '/default/ {print $5}') | awk '/link\/ether/ {print $2}')
  echo -e "${GREEN}MAC address of this computer: $mac_address${NC}"
}

# Main script execution
main() {
  install_packages
  enable_wake_on_lan
  get_mac_address
}

# Run the main function
main
