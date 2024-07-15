#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to print messages with colors
print_info() {
    echo -e "${CYAN}$1${RESET}"
}

print_success() {
    echo -e "${GREEN}$1${RESET}"
}

print_error() {
    echo -e "${RED}$1${RESET}"
}

# Function to detect desktop environment and set specific programs to install or remove
detect_desktop_environment() {
    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        print_info "KDE detected."
        specific_install_programs=("${kde_install_programs[@]}")
        specific_remove_programs=("${kde_remove_programs[@]}")
        kde_environment=true
    elif [ "$XDG_CURRENT_DESKTOP" == "GNOME" ]; then
        print_info "GNOME detected."
        specific_install_programs=("${gnome_install_programs[@]}")
        specific_remove_programs=("${gnome_remove_programs[@]}")
        kde_environment=false
    else
        print_error "Unsupported desktop environment detected."
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
        print_success "Programs removed successfully."
    else
        echo
        print_error "Failed to remove programs. Exiting..."
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
        print_success "Programs installed successfully."
    else
        echo
        print_error "Failed to install programs. Exiting..."
        exit 1
    fi
}

# Main script

# Programs to install using pacman (Default option)
pacman_programs_default=(
    android-tools
    bleachbit
    btop
    bluez-utils
    chromium
    cmatrix
    curl
    dmidecode
    dosfstools
    easyeffects
    fastfetch
    firefox
    firewalld
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

essential_programs_default=(
    discord
    filezilla
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

# Programs to install using pacman (Minimal option)
pacman_programs_minimal=(
    android-tools
    bleachbit
    btop
    bluez-utils
    chromium
    cmatrix
    curl
    dmidecode
    dosfstools
    easyeffects
    fastfetch
    firefox
    firewalld
    flatpak
    fwupd
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
    wget
    xdg-desktop-portal-gtk
    zoxide
    # Add or remove minimal programs as needed
)

essential_programs_minimal=(
    libreoffice-fresh
    timeshift
    vlc
    wine
    # Add or remove minimal essential programs as needed
)

# KDE-specific programs to install using pacman
kde_install_programs=(
    gwenview
    kdeconnect
    kwalletmanager
    kvantum
    okular
    packagekit-qt6
    python-pyqt5
    python-pyqt6
    qbittorrent
    spectacle
    xwaylandvideobridge
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

# Prompt the user for selection
echo "Select an option:"
echo "1) Default"
echo "2) Minimal"
read -p "Enter your choice [1-2, default is 1]: " choice

# Modify the lists based on the user's choice
if [[ -z "$choice" || "$choice" -eq 1 ]]; then
    # Default option: Install specific programs
    pacman_programs=("${pacman_programs_default[@]}")
    essential_programs=("${essential_programs_default[@]}")
else
    # Minimal option: Install minimal programs
    pacman_programs=("${pacman_programs_minimal[@]}")
    essential_programs=("${essential_programs_minimal[@]}")
fi

# Detect desktop environment
detect_desktop_environment

# Remove specified programs
remove_programs

# Install specified programs
install_programs
