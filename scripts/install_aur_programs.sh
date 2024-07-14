#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to print messages with colors
print_info() {
    echo -e "${CYAN}$1${RESET}"
}

print_success() {
    echo -e "${GREEN}$1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}$1${RESET}"
}

print_error() {
    echo -e "${RED}$1${RESET}"
}

# Function to install AUR packages
install_aur_packages() {
    print_info "Installing AUR Packages..."

    yay -S --needed --noconfirm "${yay_programs[@]}"

    print_success "AUR Packages installed successfully."
}

# Main script

# User selection
echo "Select an option:"
echo "1) Default"  # Switched to be the first and default option
echo "2) Minimal"  # Switched to be the second option
read -p "Enter your choice [1-2, default is 1]: " choice

# Programs to install using yay
if [[ -z "$choice" || "$choice" -eq 1 ]]; then
    yay_programs=(
        dropbox
        teamviewer
        via-bin
    )
elif [[ "$choice" -eq 2 ]]; then
    yay_programs=(
        teamviewer
    )
else
    print_warning "Invalid choice. Installing Default option."
    yay_programs=(
        dropbox
        teamviewer
        via-bin
    )
fi

# Run function
install_aur_packages
