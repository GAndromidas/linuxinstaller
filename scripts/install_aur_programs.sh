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

# User selection
echo "Select an option:"
echo "1) Default"
echo "2) Desktop"
read -p "Enter your choice [1-2, default is 1]: " choice

# Programs to install using yay
if [[ -z "$choice" || "$choice" -eq 1 ]]; then
    yay_programs=(
        teamviewer
    )
else
    case $choice in
        2)
            yay_programs=(
                dropbox
                teamviewer
                via-bin
            )
            ;;
        *)
            echo "Invalid choice. Installing Default option."
            yay_programs=(
                teamviewer
            )
            ;;
    esac
fi

# Run function
install_aur_packages
