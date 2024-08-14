#!/bin/bash

# Display "Davinci Resolve" using figlet
echo -e "${GREEN}"
figlet "Davinci Resolve"
echo -e "${NC}"

# Color functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Temporary directory for the script
TEMP_DIR="/tmp/davinci_resolve_install"

# Function to check if a package is installed
is_package_installed() {
    pacman -Qi "$1" &> /dev/null
}

# Function to check for AMD GPU
check_amd_gpu() {
    if lspci | grep -i amd/ati > /dev/null; then
        echo -e "${GREEN}AMD GPU detected.${NC}"
        return 0
    else
        echo -e "${YELLOW}No AMD GPU detected. AMD-specific packages will not be installed.${NC}"
        return 1
    fi
}

# Function to install specified packages
install_packages() {
    echo -e "${YELLOW}Installing required packages...${NC}"
    local common_packages=(
        cmake jsoncpp libuv opencl-headers rhash
    )

    local amd_packages=(
        comgr cppdap hip-runtime-amd hsa-rocr hsakmt-roct
        rocm-cmake rocm-core rocm-device-libs
        rocm-language-runtime rocm-llvm rocminfo lib32-mesa-vdpau
        rocm-hip-runtime rocm-opencl-runtime
    )

    local to_install=()

    # Check common packages
    for pkg in "${common_packages[@]}"; do
        if ! is_package_installed "$pkg"; then
            to_install+=("$pkg")
        fi
    done

    # Check AMD packages if AMD GPU is detected
    if check_amd_gpu; then
        for pkg in "${amd_packages[@]}"; do
            if ! is_package_installed "$pkg"; then
                to_install+=("$pkg")
            fi
        done
    fi

    if [ ${#to_install[@]} -eq 0 ]; then
        echo -e "${GREEN}All required packages are already installed.${NC}"
    else
        if sudo pacman -S --noconfirm "${to_install[@]}"; then
            echo -e "${GREEN}Packages installed successfully.${NC}"
        else
            echo -e "${RED}Failed to install some packages.${NC}"
            exit 1
        fi
    fi
}

# Function to install DaVinci Resolve using yay
install_davinci_resolve() {
    echo -e "${YELLOW}Installing DaVinci Resolve using yay...${NC}"
    if is_package_installed "davinci-resolve"; then
        echo -e "${GREEN}DaVinci Resolve is already installed.${NC}"
    else
        # Create and move to temporary directory
        mkdir -p "$TEMP_DIR"
        cd "$TEMP_DIR"

        if yay -S --noconfirm davinci-resolve; then
            echo -e "${GREEN}DaVinci Resolve installed successfully.${NC}"
        else
            echo -e "${RED}Failed to install DaVinci Resolve.${NC}"
            exit 1
        fi
    fi
}

# Function to clean up temporary files and directories
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        echo -e "${GREEN}Temporary directory removed.${NC}"
    fi

    # Clean pacman cache
    if sudo pacman -Scc --noconfirm; then
        echo -e "${GREEN}Pacman cache cleaned.${NC}"
    else
        echo -e "${YELLOW}Failed to clean pacman cache.${NC}"
    fi

    # Clean yay cache
    if yay -Scc --noconfirm; then
        echo -e "${GREEN}Yay cache cleaned.${NC}"
    else
        echo -e "${YELLOW}Failed to clean yay cache.${NC}"
    fi
}

# Function to print completion message
print_completion_message() {
    echo -e "${GREEN}Installation complete. DaVinci Resolve and required packages have been installed.${NC}"
}

# Main script execution
main() {
    install_packages
    install_davinci_resolve
    cleanup
    print_completion_message
}

# Trap to ensure cleanup is performed even if the script is interrupted
trap cleanup EXIT

# Execute the main function
main