#!/bin/bash
set -uo pipefail

# Installation log file
INSTALL_LOG="$HOME/.linuxinstaller.log"

# --- Script Setup ---
# Get the directory where this script is located, resolving symlinks
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
PROGRAMS_YAML="$CONFIGS_DIR/programs.yaml"

# State flags for prerequisite cleanup
FIGLET_INSTALLED_BY_SCRIPT=false
GUM_INSTALLED_BY_SCRIPT=false
YQ_INSTALLED_BY_SCRIPT=false

# --- Helper Functions ---

# Function to show help
show_help() {
  echo "LinuxInstaller - Unified Linux Post-Installation Script"
  echo ""
  echo "USAGE:"
  echo "    ./install.sh [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "    -h, --help      Show this help message and exit"
  echo "    -v, --verbose   Enable verbose output (set -x)"
  exit 0
}

# Universal logging function
log() {
    local level="$1"
    local message="$2"
    # Fallback to echo if gum is not available yet
    if command -v gum >/dev/null 2>&1; then
        gum log --level "$level" "$message"
    else
        echo "[$level] $message"
    fi
}

# --- Distribution Detection ---
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        PRETTY_NAME=${PRETTY_NAME:-$ID}
    else
        DISTRO=$(uname -s)
        PRETTY_NAME=$DISTRO
    fi
    log "info" "Detected Distribution: $PRETTY_NAME"
}

# --- Prerequisite Management ---
install_prerequisites() {
    log "info" "Checking for required tools (figlet, gum, yq)..."
    # Set package manager commands
    case "$DISTRO" in
        arch)
            PKG_INSTALL="sudo pacman -S --noconfirm"
            PKG_REMOVE="sudo pacman -Rns --noconfirm"
            ;;
        debian|ubuntu)
            PKG_INSTALL="sudo apt-get install -y"
            PKG_REMOVE="sudo apt-get remove -y"
            sudo apt-get update >/dev/null 2>&1
            ;;
        fedora)
            PKG_INSTALL="sudo dnf install -y"
            PKG_REMOVE="sudo dnf remove -y"
            ;;
        *)
            log "error" "Unsupported distribution for prerequisite installation: $DISTRO"
            exit 1
            ;;
    esac

    # Install figlet
    if ! command -v figlet >/dev/null 2>&1; then
        log "info" "figlet not found, installing silently..."
        $PKG_INSTALL figlet >> "$INSTALL_LOG" 2>&1
        FIGLET_INSTALLED_BY_SCRIPT=true
    fi

    # Install gum
    if ! command -v gum >/dev/null 2>&1; then
        log "info" "gum not found, installing silently..."
        if [ "$DISTRO" == "arch" ] || [ "$DISTRO" == "fedora" ]; then
            $PKG_INSTALL gum >> "$INSTALL_LOG" 2>&1
        else
            # Binary install for Debian/Ubuntu to get the latest version
            ARCH="amd64"; [[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"
            VER="0.14.1" # Using a recent version
            curl -sL -o /tmp/gum.deb "https://github.com/charmbracelet/gum/releases/download/v${VER}/gum_${VER}_linux_${ARCH}.deb"
            sudo dpkg -i /tmp/gum.deb >> "$INSTALL_LOG" 2>&1
            rm /tmp/gum.deb
        fi
        GUM_INSTALLED_BY_SCRIPT=true
    fi

    # Install yq
    if ! command -v yq >/dev/null 2>&1; then
        log "info" "yq not found, installing silently..."
        if [ "$DISTRO" == "arch" ] || [ "$DISTRO" == "fedora" ]; then
             $PKG_INSTALL yq >> "$INSTALL_LOG" 2>&1
        else
             # Binary install for others to avoid snap dependency
             ARCH="amd64"; [[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"
             sudo curl -sL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}"
             sudo chmod +x /usr/local/bin/yq
        fi
        YQ_INSTALLED_BY_SCRIPT=true
    fi
    log "info" "Prerequisite check complete."
}

cleanup_prerequisites() {
    log "info" "Cleaning up script-installed tools..."
    if [ "$YQ_INSTALLED_BY_SCRIPT" = true ]; then
        log "info" "Removing yq..."
        if [ "$DISTRO" == "arch" ] || [ "$DISTRO" == "fedora" ]; then
            $PKG_REMOVE yq >> "$INSTALL_LOG" 2>&1
        else
            sudo rm -f /usr/local/bin/yq
        fi
    fi
    if [ "$GUM_INSTALLED_BY_SCRIPT" = true ]; then
        log "info" "Removing gum..."
        if [ "$DISTRO" == "arch" ] || [ "$DISTRO" == "fedora" ]; then
            $PKG_REMOVE gum >> "$INSTALL_LOG" 2>&1
        else
            sudo dpkg -P gum >> "$INSTALL_LOG" 2>&1
        fi
    fi
    if [ "$FIGLET_INSTALLED_BY_SCRIPT" = true ]; then
        log "info" "Removing figlet..."
        $PKG_REMOVE figlet >> "$INSTALL_LOG" 2>&1
    fi
    log "info" "Cleanup complete."
}

# --- Core Installation Logic ---
# Function to install packages for a given category from programs.yaml
install_packages() {
    local category="$1"
    log "info" "Installing packages for category: '$category'"

    # Determine the correct package key (native, aur, snap, flatpak)
    local pkg_keys="native"
    if [ "$DISTRO" == "arch" ]; then pkg_keys="native aur"; fi
    if [ "$DISTRO" == "ubuntu" ]; then pkg_keys="native snap flatpak"; fi
    if [ "$DISTRO" == "fedora" ] || [ "$DISTRO" == "debian" ]; then pkg_keys="native flatpak"; fi

    for pkg_type in $pkg_keys; do
        packages=$(yq e ".${category}.${DISTRO}.${pkg_type}[]" "$PROGRAMS_YAML" 2>/dev/null)
        if [ -z "$packages" ] || [ "$packages" == "null" ]; then
            continue
        fi

        log "info" "Installing ${pkg_type} packages for '${category}'..."

        # Determine install command based on package type
        local INSTALL_CMD=""
        case "$pkg_type" in
            native)
                case "$DISTRO" in
                    arch) INSTALL_CMD="sudo pacman -S --noconfirm";;
                    debian|ubuntu) INSTALL_CMD="sudo apt install -y";;
                    fedora) INSTALL_CMD="sudo dnf install -y";;
                esac
                ;;
            aur)
                # Assuming yay is installed as a base/default package for Arch
                INSTALL_CMD="yay -S --noconfirm"
                ;;
            snap)
                INSTALL_CMD="sudo snap install"
                ;;
            flatpak)
                INSTALL_CMD="flatpak install flathub -y"
                ;;
        esac

        gum spin --spinner dot --title "Installing $category ($pkg_type) packages..." -- \
        $INSTALL_CMD $packages >> "$INSTALL_LOG" 2>&1

        if [ $? -eq 0 ]; then
            log "info" "Successfully installed packages for $category ($pkg_type)."
        else
            log "error" "Failed to install some packages for $category ($pkg_type). Check $INSTALL_LOG."
        fi
    done
}

# Final reboot prompt
prompt_reboot() {
    if gum confirm "Reboot now to apply all changes?"; then
        log "warn" "Rebooting system..."
        sudo reboot
    else
        log "info" "Please reboot your system later to apply all changes."
    fi
}


# --- Main Execution ---
# Parse command-line options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--help) show_help ;;
    -v|--verbose) set -x ;;
    *) log "error" "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# Touch the log file to ensure it exists
touch "$INSTALL_LOG"

# Initial setup
detect_distro
install_prerequisites

# Welcome Banner
figlet "LinuxInstaller" | gum style --foreground 212
gum style --foreground 248 "Your friendly neighborhood post-install script."
gum style --margin "1 0" --border double --padding "1" "Welcome! This script will guide you through setting up your new ${PRETTY_NAME} system."

# Interactive Menu
log "info" "Please select an installation mode:"
MODE=$(gum choose "Standard" "Minimal" "Server" "Custom" "Exit")

log "info" "Starting installation in '$MODE' mode..."

case "$MODE" in
    "Standard")
        install_packages "base"
        install_packages "default"
        ;;
    "Minimal")
        install_packages "base"
        install_packages "minimal"
        ;;
    "Server")
        install_packages "base"
        install_packages "server"
        ;;
    "Custom")
        log "info" "Select optional package groups to install:"
        CHOICES=$(gum choose --no-limit "Development Tools" "Gaming Software")

        install_packages "base"

        if [[ "$CHOICES" == *"Development Tools"* ]]; then
            install_packages "optional_dev"
        fi
        if [[ "$CHOICES" == *"Gaming Software"* ]]; then
            install_packages "optional_gaming"
        fi
        ;;
    "Exit")
        log "info" "Installation cancelled by user."
        exit 0
        ;;
esac

# --- Configuration ---
log "info" "Applying system configurations..."
for script in "$SCRIPTS_DIR"/*.sh; do
    if [ -f "$script" ]; then
        log "info" "Executing configuration script: $(basename "$script")"
        bash "$script" >> "$INSTALL_LOG" 2>&1
    fi
done

log "info" "Copying dotfiles and configs..."
# Example: cp "$CONFIGS_DIR/.zshrc.$DISTRO" "$HOME/.zshrc"

# --- Finalization ---
cleanup_prerequisites

gum format "## Installation Complete!

Your system is now set up. A log of the installation has been saved to \`$INSTALL_LOG\`.

Thanks for using LinuxInstaller!
"
prompt_reboot
