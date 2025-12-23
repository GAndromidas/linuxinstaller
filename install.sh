#!/bin/bash
set -uo pipefail

# Installation log file
INSTALL_LOG="$HOME/.linuxinstaller.log"
# Ensure log file exists
touch "$INSTALL_LOG"

# --- Directory and Script Setup ---
# Get the directory where this script is located, resolving symlinks
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
PROGRAMS_YAML="$CONFIGS_DIR/programs.yaml"

# Source common functions and distribution checks early
# This makes functions like log_info() and variables available.
if [ -f "$SCRIPTS_DIR/common.sh" ]; then
  source "$SCRIPTS_DIR/common.sh"
else
  echo "FATAL: common.sh not found in $SCRIPTS_DIR. Cannot continue."
  exit 1
fi
if [ -f "$SCRIPTS_DIR/distro_check.sh" ]; then
  source "$SCRIPTS_DIR/distro_check.sh"
else
  echo "FATAL: distro_check.sh not found in $SCRIPTS_DIR. Cannot continue."
  exit 1
fi

# --- Prerequisite Management ---
FIGLET_INSTALLED_BY_SCRIPT=false
GUM_INSTALLED_BY_SCRIPT=false
YQ_INSTALLED_BY_SCRIPT=false

# Function to install helper tools silently if they are not present
install_prerequisites() {
    log_info "Checking for required tools (figlet, gum, yq)..."

    if ! command -v figlet >/dev/null 2>&1; then
        log_info "figlet not found, installing silently..."
        $PKG_INSTALL figlet >> "$INSTALL_LOG" 2>&1
        FIGLET_INSTALLED_BY_SCRIPT=true
    fi

    if ! command -v gum >/dev/null 2>&1; then
        log_info "gum not found, installing silently..."
        $PKG_INSTALL gum >> "$INSTALL_LOG" 2>&1
        GUM_INSTALLED_BY_SCRIPT=true
    fi

    if ! command -v yq >/dev/null 2>&1; then
        log_info "yq not found, installing silently..."
        if [ "$DISTRO_ID" == "arch" ] || [ "$DISTRO_ID" == "fedora" ]; then
             $PKG_INSTALL yq >> "$INSTALL_LOG" 2>&1
        else
             ARCH="amd64"; [[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"
             sudo curl -sL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}"
             sudo chmod +x /usr/local/bin/yq
        fi
        YQ_INSTALLED_BY_SCRIPT=true
    fi
    log_success "Prerequisite check complete."
}

cleanup_prerequisites() {
    log_info "Cleaning up script-installed tools..."
    if [ "$YQ_INSTALLED_BY_SCRIPT" = true ]; then
        if [ "$DISTRO_ID" == "arch" ] || [ "$DISTRO_ID" == "fedora" ]; then
            $PKG_REMOVE yq >> "$INSTALL_LOG" 2>&1
        else
            sudo rm -f /usr/local/bin/yq
        fi
    fi
    if [ "$GUM_INSTALLED_BY_SCRIPT" = true ]; then
        $PKG_REMOVE gum >> "$INSTALL_LOG" 2>&1
    fi
    if [ "$FIGLET_INSTALLED_BY_SCRIPT" = true ]; then
        $PKG_REMOVE figlet >> "$INSTALL_LOG" 2>&1
    fi
    log_success "Cleanup complete."
}

# --- Core Installation Logic ---
# Function to install packages for a given category from programs.yaml
install_packages() {
    local category="$1"
    log_info "Installing packages for category: '$category'"

    local pkg_keys="native"
    case "$DISTRO_ID" in
        arch) pkg_keys="native aur" ;;
        ubuntu) pkg_keys="native snap flatpak" ;;
        fedora|debian) pkg_keys="native flatpak" ;;
    esac

    for pkg_type in $pkg_keys; do
        packages=$(yq e ".${category}.${DISTRO_ID}.${pkg_type}[]" "$PROGRAMS_YAML" 2>/dev/null)
        if [ -z "$packages" ] || [ "$packages" == "null" ]; then
            continue
        fi

        log_info "Installing ${pkg_type} packages for '${category}'..."

        local INSTALL_CMD=""
        case "$pkg_type" in
            native) INSTALL_CMD="$PKG_INSTALL" ;;
            aur) INSTALL_CMD="yay -S --noconfirm" ;;
            snap) INSTALL_CMD="sudo snap install" ;;
            flatpak) INSTALL_CMD="flatpak install flathub -y" ;;
        esac

        TITLE="Installing $category ($pkg_type) packages..."
        COMMAND_STRING="$INSTALL_CMD $packages"

        {
            gum spin --spinner dot --title "$TITLE" -- bash -c "$COMMAND_STRING"
        } >> "$INSTALL_LOG" 2>&1

        if [ $? -eq 0 ]; then
            log_success "Successfully installed packages for $category ($pkg_type)."
        else
            log_error "Failed to install some packages for $category ($pkg_type). Check $INSTALL_LOG for details."
        fi
    done
}


# --- Main Execution ---

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--help) show_help ;;
    -v|--verbose) set -x ;;
    *) log_error "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# --- Environment Setup for Sub-Scripts ---
log_info "Detecting distribution and setting up environment..."
detect_distro
setup_package_providers
define_common_packages

# Export variables so they are available to all child scripts
export DISTRO_ID DISTRO_NAME PKG_INSTALL PKG_REMOVE PKG_UPDATE PKG_CLEAN PKG_NOCONFIRM SCRIPTS_DIR CONFIGS_DIR

log_success "Environment ready. Detected Distro: $DISTRO_NAME"

# Now that package managers are defined, install prerequisites
install_prerequisites

# --- User Interface ---
figlet "LinuxInstaller" | gum style --foreground 212
gum style --foreground 248 "Your friendly neighborhood post-install script."
gum style --margin "1 0" --border double --padding "1" "Welcome! This script will guide you through setting up your new ${DISTRO_NAME} system."

# Interactive Menu
log_info "Please select an installation mode:"
MODE=$(gum choose "Standard" "Minimal" "Server" "Custom" "Exit")

if [ "$MODE" == "Exit" ]; then
    log_info "Installation cancelled by user."
    exit 0
fi

log_info "Starting installation in '$MODE' mode..."

# --- Package Installation ---
install_packages "base"

case "$MODE" in
    "Standard") install_packages "default" ;;
    "Minimal") install_packages "minimal" ;;
    "Server") install_packages "server" ;;
    "Custom")
        log_info "Select optional package groups to install:"
        CHOICES=$(gum choose --no-limit "Development Tools" "Gaming Software")
        if [[ "$CHOICES" == *"Development Tools"* ]]; then
            install_packages "optional_dev"
        fi
        if [[ "$CHOICES" == *"Gaming Software"* ]]; then
            install_packages "optional_gaming"
        fi
        ;;
esac

# For Standard and Minimal, ask about optional packages. Skip for Server.
if [ "$MODE" == "Standard" ] || [ "$MODE" == "Minimal" ]; then
    if gum confirm "Do you want to install optional development tools?"; then
        install_packages "optional_dev"
    fi
    if gum confirm "Do you want to install optional gaming software?"; then
        install_packages "optional_gaming"
    fi
fi

# --- Configuration Scripts (The Steps) ---
log_info "Applying system configurations from ordered scripts..."
for script in "$SCRIPTS_DIR"/??_*.sh; do
    if [ -f "$script" ]; then
        script_name=$(basename "$script")
        log_info "Executing configuration step: $script_name"
        # Execute the script in a subshell to isolate its environment
        # and correctly redirect its output to the log file.
        bash "$script" >> "$INSTALL_LOG" 2>&1
        if [ $? -eq 0 ]; then
            log_success "Step '$script_name' completed successfully."
        else
            log_error "Step '$script_name' failed. Check $INSTALL_LOG for details."
        fi
    fi
done

# --- Finalization ---
log_info "Finalizing installation..."
cleanup_prerequisites

gum format "## Installation Complete!
Your system is now set up. A log of the installation has been saved to \`$INSTALL_LOG\`.
Thanks for using LinuxInstaller!"

prompt_reboot
