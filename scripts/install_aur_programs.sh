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

# Function to print usage
print_usage() {
    echo -e "${CYAN}Usage:${RESET}"
    echo -e "${CYAN}$0 [OPTIONS]${RESET}"
    echo -e "Options:"
    echo -e "  -d, --default    Install default AUR packages"
    echo -e "  -m, --minimal    Install minimal AUR packages"
    echo -e "  -h, --help       Show this help message and exit"
}

# Function to check if yay is installed
check_yay() {
    if ! command -v yay &> /dev/null; then
        print_error "Error: yay is not installed. Please install yay and try again."
        exit 1
    fi
}

# Function to install AUR packages
install_aur_packages() {
    print_info "Installing AUR Packages..."

    yay -S --needed --noconfirm "${yay_programs[@]}" || {
        print_error "Failed to install AUR packages."
        exit 1
    }

    print_success "AUR Packages installed successfully."
}

# Function to parse command-line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -d|--default)
                FLAG="-d"
                ;;
            -m|--minimal)
                FLAG="-m"
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
        shift
    done
}

# Parse command-line arguments
parse_args "$@"

# Check for yay
check_yay

# Set programs to install based on FLAG
case "$FLAG" in
    -d)
        yay_programs=(
            dropbox
            teamviewer
            via-bin
        )
        ;;
    -m)
        yay_programs=(
            teamviewer
        )
        ;;
    *)
        print_warning "No valid flag provided. Installing default programs."
        yay_programs=(
            dropbox
            teamviewer
            via-bin
        )
        ;;
esac

# Run function
install_aur_packages