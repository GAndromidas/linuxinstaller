#!/bin/bash

# Function to detect desktop environment
detect_desktop_environment() {
    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        echo "KDE detected."
        specific_programs=("${kde_programs[@]}")
    elif [ "$XDG_CURRENT_DESKTOP" == "GNOME" ]; then
        echo "GNOME detected."
        specific_programs=("${gnome_programs[@]}")
    else
        echo "Unsupported desktop environment detected."
        specific_programs=()
    fi
}

# Function to install programs
install_programs() {
    echo
    printf "Installing Programs... "
    echo
    sudo pacman -S --needed --noconfirm "${pacman_programs[@]}" "${essential_programs[@]}" "${specific_programs[@]}"
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
    gamemode
    gamescope
    gnome-disk-utility
    hwinfo
    inxi
    lib32-gamemode
    lib32-mangohud
    lib32-vkd3d
    lib32-vulkan-radeon
    mangohud
    net-tools
    noto-fonts-extra
    ntfs-3g
    os-prober
    pacman-contrib
    samba
    sl
    speedtest-cli
    ttf-hack-nerd
    ttf-liberation
    ufw
    unrar
    vkd3d
    vulkan-radeon
    wlroots
    xdg-desktop-portal-gtk
    zoxide
    # Add or remove programs as needed
)

# Essential programs to install using pacman
essential_programs=(
    discord
    filezilla
    firefox
    gimp
    libreoffice-fresh
    lutris
    obs-studio
    smplayer
    steam
    telegram-desktop
    timeshift
    vlc
    wine
    # Add or remove essential programs as needed
)

# KDE-specific programs to install using pacman
kde_programs=(
    gwenview
    kdeconnect
    kwalletmanager
    kvantum
    okular
    packagekit-qt6
    spectacle
    qbittorrent
    xwaylandvideobridge
    # Add or remove KDE-specific programs as needed
)

# GNOME-specific programs to install using pacman
gnome_programs=(
    dconf-editor
    gnome-tweaks
    gnome-shell-extensions
    seahorse
    transmission-gtk
    # Add or remove GNOME-specific programs as needed
)

# Detect desktop environment
detect_desktop_environment

# Run function
install_programs
