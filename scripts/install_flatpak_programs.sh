#!/bin/bash 

# Function to install Flatpak programs including ProtonUp-Qt and Gear Lever
install_flatpak_programs() {
    echo
    printf "Installing Flatpak Programs... "
    echo
    sudo flatpak install -y flathub net.davidotek.pupgui2 it.mijorus.gearlever
    echo
    printf "\033[0;32m "Flatpak Programs installed successfully.\033[0m"\n"
}

# Main script

# Run function
install_flatpak_programs