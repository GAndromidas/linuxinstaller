#!/bin/bash

# Function to install Flatpak programs for KDE
install_flatpak_programs_kde() {
    echo
    printf "Installing Flatpak Programs for KDE... "
    echo
    # List of Flatpak packages to install for KDE
    flatpak_packages=(
    com.github.tchx84.Flatseal # Flatseal
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
    echo
    printf "Flatpak Programs for KDE installed successfully.\n"
}

# Function to install Flatpak programs for GNOME
install_flatpak_programs_gnome() {
    echo
    printf "Installing Flatpak Programs for GNOME... "
    echo
    # List of Flatpak packages to install for GNOME
    flatpak_packages=(
    com.github.tchx84.Flatseal # Flatseal
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
    echo
    printf "Flatpak Programs for GNOME installed successfully.\n"
}

# Main function
install_flatpak_programs() {
    # Detect the desktop environment
    desktop_env=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')

    # Install appropriate Flatpak packages based on the desktop environment
    case "$desktop_env" in
        kde)
            install_flatpak_programs_kde
            ;;
        gnome)
            install_flatpak_programs_gnome
            ;;
        *)
            echo "Unsupported desktop environment: $desktop_env. Exiting."
            exit 1
            ;;
    esac
}

# Run the main function
install_flatpak_programs
