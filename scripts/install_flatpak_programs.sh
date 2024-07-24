#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to print messages with colors
print_info() {
    echo -e "${CYAN}$1${RESET}"
}

print_success() {
    echo -e "${GREEN}$1${RESET}"
}

print_error() {
    echo -e "${RED}$1${RESET}"
}

# Function to print usage information
print_usage() {
    echo -e "${CYAN}Usage:${RESET}"
    echo -e "${CYAN}$0 [OPTIONS]${RESET}"
    echo -e "Options:"
    echo -e "  -d, --default    Install default Flatpak programs for your desktop environment"
    echo -e "  -m, --minimal    Install minimal Flatpak programs for your desktop environment"
    echo -e "  -h, --help       Show this help message and exit"
}

# Function to install Flatpak programs for KDE (Default)
install_flatpak_programs_kde() {
    print_info "Installing Flatpak Programs for KDE..."

    # List of Flatpak packages to install for KDE (Default)
    flatpak_packages=(
        com.spotify.Client # Spotify
        com.stremio.Stremio # Stremio
        io.github.shiftey.Desktop # GitHub Desktop
        net.davidotek.pupgui2 # ProtonUp-Qt
        # Add or remove packages as needed
    )

    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done

    print_success "Flatpak Programs for KDE installed successfully."
}

# Function to install Flatpak programs for GNOME (Default)
install_flatpak_programs_gnome() {
    print_info "Installing Flatpak Programs for GNOME..."

    # List of Flatpak packages to install for GNOME (Default)
    flatpak_packages=(
        com.mattjakeman.ExtensionManager # Extensions Manager
        com.spotify.Client # Spotify
        com.stremio.Stremio # Stremio
        io.github.shiftey.Desktop # GitHub Desktop
        com.vysp3r.ProtonPlus # ProtonPlus
        # Add or remove packages as needed
    )

    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done

    print_success "Flatpak Programs for GNOME installed successfully."
}

# Function to install Minimal Flatpak programs for KDE
install_flatpak_minimal_kde() {
    print_info "Installing Minimal Flatpak Programs for KDE..."

    # List of Minimal Flatpak packages to install for KDE
    flatpak_packages=(
        com.stremio.Stremio # Stremio
    )

    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done

    print_success "Minimal Flatpak Programs for KDE installed successfully."
}

# Function to install Minimal Flatpak programs for GNOME
install_flatpak_minimal_gnome() {
    print_info "Installing Minimal Flatpak Programs for GNOME..."

    # List of Minimal Flatpak packages to install for GNOME
    flatpak_packages=(
        com.mattjakeman.ExtensionManager # Extensions Manager
        com.stremio.Stremio # Stremio
    )

    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done

    print_success "Minimal Flatpak Programs for GNOME installed successfully."
}

# Function to parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -d|--default)
                installation_mode="default"
                ;;
            -m|--minimal)
                installation_mode="minimal"
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

# Main function
install_flatpak_programs() {
    # Detect the desktop environment
    desktop_env=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')

    if [ -z "$desktop_env" ]; then
        print_error "No desktop environment detected. Skipping installation."
        exit 0
    fi

    # Install Flatpak programs based on the desktop environment and installation mode
    case "$installation_mode" in
        "default" | "")
            case "$desktop_env" in
                kde)
                    install_flatpak_programs_kde
                    ;;
                gnome)
                    install_flatpak_programs_gnome
                    ;;
                *)
                    print_error "Unsupported desktop environment: $desktop_env. Exiting."
                    exit 0
                    ;;
            esac
            ;;
        "minimal")
            case "$desktop_env" in
                kde)
                    install_flatpak_minimal_kde
                    ;;
                gnome)
                    install_flatpak_minimal_gnome
                    ;;
                *)
                    print_error "Unsupported desktop environment: $desktop_env. Exiting."
                    exit 0
                    ;;
            esac
            ;;
        *)
            print_error "Invalid choice. Skipping installation."
            exit 0
            ;;
    esac
}

# Parse command line arguments
parse_args "$@"

# Run the main function
install_flatpak_programs