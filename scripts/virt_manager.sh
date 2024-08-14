#!/bin/bash

echo -e "${GREEN}"
figlet "Virt Manager"
echo -e "${NC}"

# Color functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to resolve iptables conflict and install required packages
install_packages() {
    echo -e "${YELLOW}Resolving package conflicts and installing required packages...${NC}"
    sudo pacman -Rdd --noconfirm iptables
    sudo pacman -S --noconfirm iptables-nft qemu-full virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat ebtables libguestfs
}

# Function to create libvirt group if it doesn't exist and add the current user to the libvirt group
configure_libvirt_group() {
    echo -e "${YELLOW}Configuring libvirt group...${NC}"
    if ! grep -q '^libvirt:' /etc/group; then
        sudo groupadd libvirt
    fi
    sudo usermod -a -G libvirt $(whoami)
}

# Function to configure libvirtd
configure_libvirtd() {
    echo -e "${YELLOW}Configuring libvirtd...${NC}"
    sudo mkdir -p /etc/libvirt
    sudo bash -c 'cat > /etc/libvirt/libvirtd.conf <<EOF
unix_sock_group = "libvirt"
unix_sock_rw_perms = "0770"
EOF'
}

# Function to enable and start libvirtd service
enable_and_start_libvirtd() {
    echo -e "${YELLOW}Enabling and starting libvirtd service...${NC}"
    sudo systemctl enable --now libvirtd
}

# Function to print completion message
print_completion_message() {
    echo -e "${GREEN}Installation and configuration complete. Please log out and back in for the group changes to take effect.${NC}"
}

# Main script execution
main()
    install_packages
    configure_libvirt_group
    configure_libvirtd
    enable_and_start_libvirtd
    print_completion_message
}

# Execute the main function
main