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
print_warning() { echo -e "${YELLOW}$1${RESET}"; }
print_error() { echo -e "${RED}$1${RESET}"; }

# Function to print usage information
print_usage() {
    echo -e "${CYAN}Usage:${RESET}"
    echo -e "${CYAN}$0 [OPTIONS]${RESET}"
    echo -e "Options:"
    echo -e "  -d, --default    Install default programs for your system and desktop environment"
    echo -e "  -m, --minimal    Install minimal programs for your system and desktop environment"
    echo -e "  -h, --help       Show this help message and exit"
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
            flatpak_install_function="install_flatpak_programs_kde"
            ;;
        GNOME)
            print_info "GNOME detected."
            specific_install_programs=("${gnome_install_programs[@]}")
            specific_remove_programs=("${gnome_remove_programs[@]}")
            flatpak_install_function="install_flatpak_programs_gnome"
            ;;
        *)
            print_error "No KDE or GNOME detected. Skipping DE-specific programs."
            specific_install_programs=()
            specific_remove_programs=()
            flatpak_install_function=""
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

# Function to install programs via pacman
install_pacman_programs() {
    print_info "Installing Pacman Programs..."
    $PACMAN_CMD "${pacman_programs[@]}" "${essential_programs[@]}" "${specific_install_programs[@]}"
    handle_error "Failed to install programs. Exiting..."
    print_success "Programs installed successfully."
}

# Function to install Flatpak programs
install_flatpak_programs() {
    if [ -n "$flatpak_install_function" ]; then
        print_info "Installing Flatpak Programs..."
        $flatpak_install_function
        handle_error "Failed to install Flatpak programs. Exiting..."
    else
        print_info "No Flatpak installation function defined for the detected desktop environment."
    fi
}

# Function to check if yay is installed
check_yay() {
    if ! command -v yay &> /dev/null; then
        print_error "Error: yay is not installed. Please install yay and try again."
        exit 1
    fi
}

# Function to install AUR packages
install_aur_packages() {
    print_info "Installing AUR Packages..."
    $AUR_INSTALL_CMD "${yay_programs[@]}"
    handle_error "Failed to install AUR packages. Exiting..."
    print_success "AUR Packages installed successfully."
}

# Function to parse command-line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -d|--default)
                installation_mode="default"
                ;;
            -m|--minimal)
                installation_mode="minimal"
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
# Programs to install using pacman (Default option)
pacman_programs_default=(
    android-tools bleachbit btop bluez-utils cmatrix curl dmidecode dosfstools expac eza fastfetch firefox
    firewalld flatpak fwupd fzf gamemode gnome-disk-utility hwinfo inxi lib32-gamemode lib32-mangohud lib32-vulkan-icd-loader
    lib32-vulkan-radeon mangohud net-tools noto-fonts-extra ntfs-3g pacman-contrib samba sl speedtest-cli sshfs ttf-hack-nerd
    ttf-liberation ttf-meslo-nerd unrar vulkan-icd-loader vulkan-radeon wget xdg-desktop-portal-gtk zoxide
)

essential_programs_default=(
    discord filezilla gimp libreoffice-fresh lutris obs-studio smplayer steam telegram-desktop timeshift vlc wine
)

# Programs to install using pacman (Minimal option)
pacman_programs_minimal=(
    android-tools bleachbit btop bluez-utils cmatrix curl dmidecode dosfstools expac eza fastfetch firefox
    firewalld flatpak fwupd fzf net-tools noto-fonts-extra ntfs-3g pacman-contrib samba sl speedtest-cli sshfs ttf-hack-nerd
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

# Flatpak programs to install for KDE (Default)
install_flatpak_programs_kde() {
    print_info "Installing Flatpak Programs for KDE..."
    flatpak_packages=(
        com.spotify.Client
        com.stremio.Stremio
        io.github.shiftey.Desktop
        it.mijorus.gearlever
        net.davidotek.pupgui2
    )
    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done
    print_success "Flatpak Programs for KDE installed successfully."
}

# Flatpak programs to install for GNOME (Default)
install_flatpak_programs_gnome() {
    print_info "Installing Flatpak Programs for GNOME..."
    flatpak_packages=(
        com.mattjakeman.ExtensionManager
        com.spotify.Client
        com.stremio.Stremio
        io.github.shiftey.Desktop
        it.mijorus.gearlever
        com.vysp3r.ProtonPlus
    )
    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done
    print_success "Flatpak Programs for GNOME installed successfully."
}

# Minimal Flatpak programs for KDE
install_flatpak_minimal_kde() {
    print_info "Installing Minimal Flatpak Programs for KDE..."
    flatpak_packages=(
        com.stremio.Stremio
        it.mijorus.gearlever
    )
    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done
    print_success "Minimal Flatpak Programs for KDE installed successfully."
}

# Minimal Flatpak programs for GNOME
install_flatpak_minimal_gnome() {
    print_info "Installing Minimal Flatpak Programs for GNOME..."
    flatpak_packages=(
        com.mattjakeman.ExtensionManager
        com.stremio.Stremio
        it.mijorus.gearlever
    )
    for package in "${flatpak_packages[@]}"; do
        sudo flatpak install -y flathub "$package"
    done
    print_success "Minimal Flatpak Programs for GNOME installed successfully."
}

# AUR Packages to install (Default option)
yay_programs_default=(
    dropbox
    heroic-games-launcher-bin
    teamviewer
    via-bin
)

# AUR Packages to install (Minimal option)
yay_programs_minimal=(
    teamviewer
)

# Parse command line arguments
parse_args "$@"

# Check for yay
check_yay

# Set programs to install based on installation mode
case "$installation_mode" in
    "default")
        pacman_programs=("${pacman_programs_default[@]}")
        essential_programs=("${essential_programs_default[@]}")
        yay_programs=("${yay_programs_default[@]}")
        ;;
    "minimal")
        pacman_programs=("${pacman_programs_minimal[@]}")
        essential_programs=("${essential_programs_minimal[@]}")
        yay_programs=("${yay_programs_minimal[@]}")
        ;;
    *)
        print_error "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Detect desktop environment
detect_desktop_environment

# Remove specified programs
remove_programs

# Install specified programs via pacman
install_pacman_programs

# Install Flatpak programs
if [[ "$installation_mode" == "default" ]]; then
    install_flatpak_programs
else
    if [[ "$XDG_CURRENT_DESKTOP" == "KDE" ]]; then
        install_flatpak_minimal_kde
    elif [[ "$XDG_CURRENT_DESKTOP" == "GNOME" ]]; then
        install_flatpak_minimal_gnome
    fi
fi

# Install AUR packages
install_aur_packages
