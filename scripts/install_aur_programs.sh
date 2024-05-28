#!/bin/bash

# Function to install AUR packages
install_aur_packages() {
    echo
    printf "Installing AUR Packages... "
    echo
    yay -S --needed --noconfirm "${yay_programs[@]}"
    echo
    printf "AUR Packages installed successfully.\n"
}

# Main script

# Programs to install using yay
yay_programs=(
    dropbox
    github-desktop-bin
    spotify
    stremio
    teamviewer
    via-bin
    # Add or remove AUR programs as needed
)

# Run function
install_aur_packages
