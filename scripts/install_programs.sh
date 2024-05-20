#!/bin/bash

# Function to install programs
install_programs() {
    printf "Installing Programs... "
    sudo pacman -S --needed --noconfirm "${pacman_programs[@]}" "${essential_programs[@]}" "${kde_programs[@]}"
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
    fail2ban
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
    powerline-fonts
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
    xwaylandvideobridge
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
    qbittorrent
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
    # Add or remove KDE-specific programs as needed
)

# Run function
install_programs