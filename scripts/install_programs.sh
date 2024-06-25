#!/bin/bash

# Function to detect desktop environment and set specific programs to install or remove
detect_desktop_environment() {
    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        echo "KDE detected."
        specific_install_programs=("${kde_install_programs[@]}")
        specific_remove_programs=("${kde_remove_programs[@]}")
        kde_environment=true
    elif [ "$XDG_CURRENT_DESKTOP" == "GNOME" ]; then
        echo "GNOME detected."
        specific_install_programs=("${gnome_install_programs[@]}")
        specific_remove_programs=("${gnome_remove_programs[@]}")
        kde_environment=false
    else
        echo "Unsupported desktop environment detected."
        specific_install_programs=()
        specific_remove_programs=()
        kde_environment=false
    fi
}

# Function to remove programs
remove_programs() {
    echo
    printf "Removing Programs... \n"
    echo
    sudo pacman -Rns --noconfirm "${specific_remove_programs[@]}"
    if [ $? -eq 0 ]; then
        echo
        printf "Programs removed successfully.\n"
    else
        echo
        printf "Failed to remove programs. Exiting...\n"
        exit 1
    fi
}

# Function to install programs
install_programs() {
    echo
    printf "Installing Programs... \n"
    echo
    sudo pacman -S --needed --noconfirm "${pacman_programs[@]}" "${essential_programs[@]}" "${specific_install_programs[@]}"
    if [ $? -eq 0 ]; then
        echo
        printf "Programs installed successfully.\n"
    else
        echo
        printf "Failed to install programs. Exiting...\n"
        exit 1
    fi
}

# Main script

# Programs to install using pacman
pacman_programs=(
    android-tools
    bleachbit
    btop
    chromium
    cmatrix
    curl
    dosfstools
    easyeffects
    fastfetch
    firefox
    flatpak
    fwupd
    gamemode
    gnome-disk-utility
    hwinfo
    inxi
    lib32-gamemode
    lib32-mangohud
    lib32-vulkan-radeon
    mangohud
    net-tools
    noto-fonts-extra
    ntfs-3g
    pacman-contrib
    samba
    sl
    speedtest-cli
    sshfs
    ttf-hack-nerd
    ttf-liberation
    unrar
    vulkan-radeon
    wget
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
    wine
    # Add or remove essential programs as needed
)

# KDE-specific programs to install using pacman
kde_install_programs=(
    firewalld
    gwenview
    kdeconnect
    kwalletmanager
    kvantum
    okular
    packagekit-qt6
    qbittorrent
    spectacle
    vlc
    # Add or remove KDE-specific programs as needed
)

# KDE-specific programs to remove using pacman
kde_remove_programs=(
    htop
    # Add other KDE-specific programs to remove if needed
)

# GNOME-specific programs to install using pacman
gnome_install_programs=(
    celluloid
    dconf-editor
    gnome-tweaks
    gufw
    seahorse
    transmission-gtk
    # Add or remove GNOME-specific programs as needed
)

# GNOME-specific programs to remove using pacman
gnome_remove_programs=(
    epiphany
    gnome-contacts
    gnome-maps
    gnome-music
    gnome-tour
    htop
    snapshot
    totem
    # Add other GNOME-specific programs to remove if needed
)

# Detect desktop environment
detect_desktop_environment

# Remove specified programs
remove_programs

# Install specified programs
install_programs
