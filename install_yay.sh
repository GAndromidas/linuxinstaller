#!/bin/bash

# Function to install Yay
install_yay() {
    log "Installing Yay..."
    git clone https://aur.archlinux.org/yay.git
    cd yay || { log "Failed to change directory to yay. Exiting."; exit 1; }
    makepkg -si --needed --noconfirm || { log "Failed to install Yay. Exiting."; exit 1; }
    cd .. && rm -rf yay || { log "Failed to clean up Yay files. Exiting."; exit 1; }
    log "Yay installed successfully."
}

# Fuction to load files
load_program_lists() {
    if [ -n "$SUDO_USER" ]; then
        home_directory="/home/$SUDO_USER"
    else
        home_directory="$HOME"
    fi

# Function to install AUR packages using Yay
install_yay_packages() {
    log "Installing AUR packages with Yay..."
    yay_packages=($(cat "$HOME/archinstaller/yay_packages.txt"))
    if ! yay -S --needed --noconfirm "${yay_packages[@]}"; then
        log "Failed to install AUR packages with Yay. Exiting."
        exit 1
    fi
    log "AUR packages installed successfully."
}

# Main execution flow
main() {
    install_yay
    load_program_lists
    yay_packages
}

main
