#!/bin/bash
set -euo pipefail

# Color variables for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to print status messages
print_status() {
    echo -e "${CYAN}[*] $1${RESET}"
}

print_success() {
    echo -e "${GREEN}[+] $1${RESET}"
}

print_error() {
    echo -e "${RED}[-] $1${RESET}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "Do not run this script as root. Please run as a regular user with sudo privileges."
    exit 1
fi

# Check if pacman is available
if ! command -v pacman >/dev/null; then
    print_error "This script is intended for Arch Linux systems with pacman."
    exit 1
fi

# Update mirrors using reflector
print_status "Updating mirrorlist..."
sudo reflector --verbose --protocol https --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
print_success "Mirrorlist updated successfully."

# Update system
print_status "Updating system..."
sudo pacman -Syu --noconfirm
print_success "System updated successfully."

# Install required packages
print_status "Installing required packages..."
sudo pacman -S --needed --noconfirm \
    python \
    python-pip \
    python-setuptools \
    python-wheel \
    python-virtualenv \
    base-devel \
    git

print_success "Base packages installed successfully."

# Create and activate virtual environment
print_status "Setting up Python virtual environment..."
python -m venv ~/.archinstaller_venv
source ~/.archinstaller_venv/bin/activate

# Upgrade pip
print_status "Upgrading pip..."
pip install --upgrade pip

# Install PyQt6
print_status "Installing PyQt6..."
pip install PyQt6

print_success "Python environment setup completed."

# Create desktop entry
print_status "Creating desktop entry..."
mkdir -p ~/.local/share/applications

cat > ~/.local/share/applications/archinstaller.desktop << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Arch Installer
Comment=Graphical installer for Arch Linux
Exec=python $(pwd)/archinstaller.py
Icon=system-software-install
Terminal=false
Categories=System;Settings;
EOF

print_success "Desktop entry created."

# Make scripts executable
print_status "Making scripts executable..."
chmod +x archinstaller.py
chmod +x install.sh

print_success "Setup completed successfully!"
echo -e "\n${YELLOW}You can now run the Arch Installer in two ways:${RESET}"
echo -e "1. From terminal: ${CYAN}python archinstaller.py${RESET}"
echo -e "2. From desktop: ${CYAN}Find 'Arch Installer' in your applications menu${RESET}"
echo -e "\n${YELLOW}Note:${RESET} The installer will be available in your applications menu after logging out and back in."

# Add alias to .zshrc if it doesn't exist
if ! grep -q "alias archinstaller=" ~/.zshrc; then
    echo -e "\n${YELLOW}Adding alias to .zshrc...${RESET}"
    echo "alias archinstaller='python $(pwd)/archinstaller.py'" >> ~/.zshrc
    print_success "Alias 'archinstaller' added to .zshrc"
    echo -e "You can now run the installer by typing ${CYAN}archinstaller${RESET} in your terminal"
fi

# Ask if user wants to run the installer now
echo -e "\n${YELLOW}Would you like to run the Arch Installer now? [Y/n]${RESET}"
read -r response
response=${response,,}  # Convert to lowercase

if [[ "$response" =~ ^(yes|y|)$ ]]; then
    print_status "Starting Arch Installer..."
    python archinstaller.py
else
    print_success "Setup completed. You can run the installer later using 'archinstaller' command or from the applications menu."
fi