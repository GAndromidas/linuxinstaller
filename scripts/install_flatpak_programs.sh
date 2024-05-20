#!/bin/bash 

# Function to install Flatpak programs including ProtonUp-Qt and Gear Lever
install_flatpak_programs() {
    printf "Installing Flatpak Programs... "
    sudo flatpak install -y flathub net.davidotek.pupgui2 it.mijorus.gearlever
    printf "Flatpak Programs installed successfully.\n"
}

# Main script

# Run function
install_flatpak_programs