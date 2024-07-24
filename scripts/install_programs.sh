#!/bin/bash

# Constants for commands
PACMAN_CMD="sudo pacman -S --needed --noconfirm"
REMOVE_CMD="sudo pacman -Rns --noconfirm"
AUR_INSTALL_CMD="yay -S --noconfirm"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to print messages with colors
print_info() { echo -e "${CYAN}$1${RESET}"; }
print_success() { echo -e "${GREEN}$1${RESET}"; }
print_error() { echo -e "${RED}$1${RESET}"; }

# Function to print usage information
print_usage() {
    echo -e "${CYAN}Usage:${RESET}"
    echo -e "${CYAN}$0 [OPTIONS]${RESET}"
    echo -e "Options:"
    echo -e "  -d, --default        Install default programs for your system"
    echo -e "  -m, --minimal        Install minimal set of programs for your system"
    echo -e "  -h, --help           Show this help message and exit"
}

# Function to check if the script is run as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root!"
        exit 1
    fi
}

# Function to handle errors
handle_error() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    fi
}

# Function to detect desktop environment and set specific programs to install or remove
detect_desktop_environment() {
    case "$XDG_CURRENT_DESKTOP" in
        KDE)
            print_info "KDE detected."
            specific_install_programs=("${kde_install_programs[@]}")
            specific_remove_programs=("${kde_remove_programs[@]}")
            ;;
        GNOME)
            print_info "GNOME detected."
            specific_install_programs=("${gnome_install_programs[@]}")
            specific_remove_programs=("${gnome_remove_programs[@]}")
            ;;
        *)
            print_error "No KDE or GNOME detected. Skipping DE-specific programs."
            specific_install_programs=()
            specific_remove_programs=()
            ;;
    esac
}

# Function to remove programs
remove_programs() {
    if [ ${#specific_remove_programs[@]} -eq 0 ]; then
        print_info "No specific programs to remove."
    else
        print_info "Removing Programs..."
        $REMOVE_CMD "${specific_remove_programs[@]}"
        handle_error "Failed to remove programs. Exiting..."
        print_success "Programs removed successfully."
    fi
}

# Function to install programs
install_programs() {
    print_info "Installing Programs..."
    $PACMAN_CMD "${pacman_programs[@]}" "${essential_programs[@]}" "${specific_install_programs[@]}"
    handle_error "Failed to install programs. Exiting..."
    print_success "Programs installed successfully."
}

# Function to install DaVinci Resolve dependencies
install_davinci_resolve_dependencies() {
    davinci_packages=(
        cmake comgr cppdap hip-runtime-amd hsa-rocr hsakmt-roct jsoncpp libuv opencl-headers rhash rocm-cmake
        rocm-core rocm-device-libs rocm-language-runtime rocm-llvm rocminfo lib32-mesa-vdpau rocm-hip-runtime rocm-opencl-runtime
    )
    print_info "Installing DaVinci Resolve dependencies..."
    $PACMAN_CMD "${davinci_packages[@]}"
    handle_error "Failed to install DaVinci Resolve dependencies. Exiting..."
    print_success "DaVinci Resolve dependencies installed successfully."
}

# Function to install DaVinci Resolve from AUR
install_davinci_resolve() {
    print_info "Installing DaVinci Resolve from AUR..."
    $AUR_INSTALL_CMD davinci-resolve
    handle_error "Failed to install DaVinci Resolve from AUR. Exiting..."
    print_success "DaVinci Resolve installed successfully."
}

# Function to parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -d|--default)
                pacman_programs=("${pacman_programs_default[@]}")
                essential_programs=("${essential_programs_default[@]}")
                ;;
            -m|--minimal)
                pacman_programs=("${pacman_programs_minimal[@]}")
                essential_programs=("${essential_programs_minimal[@]}")
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
        shift
    done
}

# Main script
check_root

# Programs to install using pacman (Default option)
pacman_programs_default=(
    android-tools bleachbit btop bluez-utils cmatrix curl dmidecode dosfstools expac eza fastfetch firefox
    firewalld flatpak fwupd gamemode gnome-disk-utility hwinfo inxi lib32-gamemode lib32-mangohud lib32-vulkan-icd-loader
    lib32-vulkan-radeon mangohud net-tools noto-fonts-extra ntfs-3g pacman-contrib samba sl speedtest-cli sshfs ttf-hack-nerd
    ttf-liberation ttf-meslo-nerd unrar vulkan-icd-loader vulkan-radeon wget xdg-desktop-portal-gtk zoxide
)

essential_programs_default=(
    discord filezilla gimp libreoffice-fresh lutris obs-studio smplayer steam telegram-desktop timeshift vlc wine
)

# Programs to install using pacman (Minimal option)
pacman_programs_minimal=(
    android-tools bleachbit btop bluez-utils cmatrix curl dmidecode dosfstools expac eza fastfetch firefox
    firewalld flatpak fwupd net-tools noto-fonts-extra ntfs-3g pacman-contrib samba sl speedtest-cli sshfs ttf-hack-nerd
    ttf-liberation ttf-meslo-nerd unrar wget xdg-desktop-portal-gtk zoxide
)

essential_programs_minimal=(
    libreoffice-fresh timeshift vlc wine
)

# KDE-specific programs to install using pacman
kde_install_programs=(
    gwenview kdeconnect kwalletmanager kvantum okular packagekit-qt6 python-pyqt5 python-pyqt6 qbittorrent spectacle
)

# KDE-specific programs to remove using pacman
kde_remove_programs=(
    htop
)

# GNOME-specific programs to install using pacman
gnome_install_programs=(
    celluloid dconf-editor gnome-tweaks seahorse transmission-gtk
)

# GNOME-specific programs to remove using pacman
gnome_remove_programs=(
    epiphany gnome-contacts gnome-maps gnome-music gnome-tour htop snapshot totem
)

# Parse command line arguments
parse_args "$@"

# Detect desktop environment
detect_desktop_environment

# Prompt to install DaVinci Resolve
read -p "Do you want to install DaVinci Resolve dependencies and DaVinci Resolve? [Y/n]: " install_davinci
if [[ -z "$install_davinci" || "$install_davinci" == "y" || "$install_davinci" == "Y" ]]; then
    install_davinci_resolve_dependencies
    install_davinci_resolve
fi

# Remove specified programs
remove_programs

# Install specified programs
install_programs