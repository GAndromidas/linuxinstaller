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

# Function to install Flatpak programs for KDE
install_flatpak_programs_kde() {
    print_info "Installing Flatpak Programs for KDE..."

    # List of Flatpak packages to install for KDE
    flatpak_packages=(
        com.spotify.Client # Spotify
        com.stremio.Stremio # Stremio
        io.github.shiftey.Desktop # GitHub Desktop
        it.mijorus.gearlever # Gear Lever
        net.davidotek.pupgui2 # ProtonUp-Qt
        # Add or remove packages as needed
    )

    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done

    print_success "Flatpak Programs for KDE installed successfully."
}

# Function to install Flatpak programs for GNOME
install_flatpak_programs_gnome() {
    print_info "Installing Flatpak Programs for GNOME..."

    # List of Flatpak packages to install for GNOME
    flatpak_packages=(
        com.mattjakeman.ExtensionManager # Extensions Manager
        com.spotify.Client # Spotify
        com.stremio.Stremio # Stremio
        com.vysp3r.ProtonPlus # ProtonPlus
        io.github.shiftey.Desktop # GitHub Desktop
        it.mijorus.gearlever # Gear Lever
        # Add or remove packages as needed
    )

    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done

    print_success "Flatpak Programs for GNOME installed successfully."
}

# Function to install Default Flatpak programs for KDE
install_flatpak_default_kde() {
    print_info "Installing Default Flatpak Programs for KDE..."

    # List of Default Flatpak packages to install for KDE
    flatpak_packages=(
        it.mijorus.gearlever # Gear Lever
    )

    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done

    print_success "Default Flatpak Programs for KDE installed successfully."
}

# Function to install Default Flatpak programs for GNOME
install_flatpak_default_gnome() {
    print_info "Installing Default Flatpak Programs for GNOME..."

    # List of Default Flatpak packages to install for GNOME
    flatpak_packages=(
        com.mattjakeman.ExtensionManager # Extensions Manager
        it.mijorus.gearlever # Gear Lever
    )

    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done

    print_success "Default Flatpak Programs for GNOME installed successfully."
}

# Main function
install_flatpak_programs() {
    # Detect the desktop environment
    desktop_env=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')

    # Prompt the user for selection
    echo "Select an option:"
    echo "1) Default"
    echo "2) Desktop"
    read -p "Enter your choice [1-2, default is 1]: " choice

    # Install appropriate Flatpak packages based on the desktop environment and user selection
    if [[ -z "$choice" || "$choice" -eq 1 ]]; then
        case "$desktop_env" in
            kde)
                install_flatpak_default_kde
                ;;
            gnome)
                install_flatpak_default_gnome
                ;;
            *)
                print_error "Unsupported desktop environment: $desktop_env. Exiting."
                exit 1
                ;;
        esac
    else
        case "$choice" in
            2)
                case "$desktop_env" in
                    kde)
                        install_flatpak_programs_kde
                        ;;
                    gnome)
                        install_flatpak_programs_gnome
                        ;;
                    *)
                        print_error "Unsupported desktop environment: $desktop_env. Exiting."
                        exit 1
                        ;;
                esac
                ;;
            *)
                print_error "Invalid choice. Installing Default option."
                case "$desktop_env" in
                    kde)
                        install_flatpak_default_kde
                        ;;
                    gnome)
                        install_flatpak_default_gnome
                        ;;
                    *)
                        print_error "Unsupported desktop environment: $desktop_env. Exiting."
                        exit 1
                        ;;
                esac
                ;;
        esac
    fi
}

# Run the main function
install_flatpak_programs
