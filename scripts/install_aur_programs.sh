#!/bin/bash

# Function to install AUR packages
install_aur_packages() {
    echo
    printf "Installing AUR Packages... "
    echo
    if [[ "$aur_helper" == "p" ]]; then
        paru -S --needed --noconfirm "${yay_programs[@]}"
    else
        yay -S --needed --noconfirm "${yay_programs[@]}"
    fi
    echo
    printf "\033[0;32m "AUR Packages installed successfully.\033[0m"\n"
}

# Main script

# Programs to install using yay
yay_programs=(
    dropbox
    github-desktop-bin
    spotify
    stremio
    teamviewer
    ventoy-bin
    via-bin
    # Add or remove AUR programs as needed
)

# Run function
install_aur_packages
