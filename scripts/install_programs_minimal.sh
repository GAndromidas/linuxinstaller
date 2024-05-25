#!/bin/bash

# Function to install programs
install_programs_minimal() {
    echo
    printf "Installing Programs... "
    echo
    sudo pacman -S --needed --noconfirm "${pacman_programs[@]}" "${essential_programs[@]}"
    echo
    printf "Programs installed successfully.\n"
}

# Main script

# Programs to install using pacman
pacman_programs=(
    android-tools
    bleachbit
    btop
    cmatrix
    dosfstools
    fastfetch
    flatpak
    fwupd
    fzf
    gnome-disk-utility
    hwinfo
    inxi
    net-tools
    noto-fonts-extra
    ntfs-3g
    pacman-contrib
    samba
    sl
    speedtest-cli
    ttf-hack-nerd
    ttf-liberation
    ufw
    unrar
    wlroots
    xdg-desktop-portal-gtk
    xwaylandvideobridge
    zoxide
    # Add or remove programs as needed
)

# Essential programs to install using pacman
essential_programs=(
    firefox
    timeshift
    vlc
    qbittorrent
    # Add or remove essential programs as needed
)

# Run function
install_programs_minimal
