#!/bin/bash

# Function to install AUR packages
install_aur_packages() {
    printf "Installing AUR Packages... "
    if [[ "$aur_helper" == "p" ]]; then
        paru -S --needed --noconfirm "${yay_programs[@]}"
    else
        yay -S --needed --noconfirm "${yay_programs[@]}"
    fi
    printf "AUR Packages installed successfully.\n"
}

# Main script

# Programs to install using yay
yay_programs=(
    brave-bin
    dropbox
    spotify
    stremio
    teamviewer
    # Add or remove AUR programs as needed
)

# Run function
install_aur_packages
