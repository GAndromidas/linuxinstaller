#!/bin/bash

# Color functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to install specified packages
install_packages() {
    echo -e "${YELLOW}Installing specified packages...${NC}"
    if ! sudo pacman -S --noconfirm cmake comgr cppdap hip-runtime-amd hsa-rocr hsakmt-roct jsoncpp libuv opencl-headers rhash rocm-cmake rocm-core rocm-device-libs rocm-language-runtime rocm-llvm rocminfo lib32-mesa-vdpau rocm-hip-runtime rocm-opencl-runtime; then
        echo -e "${RED}Failed to install specified packages.${NC}"
        exit 1
    fi
}

# Function to install DaVinci Resolve using yay
install_davinci_resolve() {
    echo -e "${YELLOW}Installing DaVinci Resolve using yay...${NC}"
    if ! yay -S --noconfirm davinci-resolve; then
        echo -e "${RED}Failed to install DaVinci Resolve.${NC}"
        exit 1
    fi
}

# Function to print completion message
print_completion_message() {
    echo -e "${GREEN}Installation complete. DaVinci Resolve and specified packages have been installed.${NC}"
}

# Main script execution
main() {
    install_packages
    install_davinci_resolve
    print_completion_message
}

# Execute the main function
main
