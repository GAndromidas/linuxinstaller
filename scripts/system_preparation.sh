#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
# distro_check.sh should have been sourced by install.sh, but for safety in standalone runs:
if [ -z "${DISTRO_ID:-}" ]; then
    if [ -f "$SCRIPT_DIR/distro_check.sh" ]; then
        source "$SCRIPT_DIR/distro_check.sh"
        detect_distro
        define_common_packages
    fi
fi

check_prerequisites() {
  step "Checking system prerequisites"
  if [[ $EUID -eq 0 ]]; then
    log_error "Do not run this script as root. Please run as a regular user with sudo privileges."
    return 1
  fi
  
  # Basic internet check
  if ! ping -c 1 -W 5 google.com &>/dev/null; then
      log_error "No internet connection detected."
      return 1
  fi

  log_success "Prerequisites OK."
}

setup_extra_repos() {
    # Fedora: Enable RPMFusion
    if [ "$DISTRO_ID" == "fedora" ]; then
        step "Enabling RPMFusion Repositories"
        
        # Check if enabled
        if ! dnf repolist | grep -q rpmfusion-free; then
            log_info "Installing RPMFusion Free & Non-Free..."
            sudo dnf install -y \
                https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
            log_success "RPMFusion enabled."
        else
            log_info "RPMFusion already enabled."
        fi
        
        # Enable Codecs (often needed)
        # sudo dnf groupupdate -y core
        # sudo dnf groupupdate -y multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
        # sudo dnf groupupdate -y sound-and-video
    fi
    
    # Debian/Ubuntu: Ensure contrib non-free (usually handled by user, but we can try)
    if [ "$DISTRO_ID" == "debian" ]; then
        # Check /etc/apt/sources.list for non-free-firmware (Bookworm+)
        # This is invasive to edit sources.list blindly. Skipping for safety unless requested.
        :
    fi
}

configure_package_manager() {
    step "Configuring package manager"
    
    # Run repo setup first
    setup_extra_repos
    
    if [ "$DISTRO_ID" == "arch" ]; then
        # Arch specific pacman configuration
        local parallel_downloads=10
        if grep -q "^#ParallelDownloads" /etc/pacman.conf; then
            sudo sed -i "s/^#ParallelDownloads.*/ParallelDownloads = $parallel_downloads/" /etc/pacman.conf
        elif grep -q "^ParallelDownloads" /etc/pacman.conf; then
            sudo sed -i "s/^ParallelDownloads.*/ParallelDownloads = $parallel_downloads/" /etc/pacman.conf
        else
            sudo sed -i "/^\[options\]/a ParallelDownloads = $parallel_downloads" /etc/pacman.conf
        fi
        
        if grep -q "^#Color" /etc/pacman.conf; then
            sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
        fi
        
        # Initialize keyring if needed
        if [ ! -d /etc/pacman.d/gnupg ]; then
             sudo pacman-key --init
             sudo pacman-key --populate archlinux
        fi
    elif [ "$DISTRO_ID" == "fedora" ]; then
        # Fedora optimization
        if ! grep -q "max_parallel_downloads" /etc/dnf/dnf.conf; then
            echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf
        fi
        if ! grep -q "fastestmirror" /etc/dnf/dnf.conf; then
            echo "fastestmirror=True" | sudo tee -a /etc/dnf/dnf.conf
        fi
    fi
}

update_system() {
    step "Updating System"
    if ! eval "$PKG_UPDATE"; then
        log_error "System update failed."
        return 1
    fi
    log_success "System updated."
}

install_all_packages() {
    step "Installing Base Packages"
    
    # Filter helper utils if server
    local packages_to_install=("${HELPER_UTILS[@]}")
    
    if [[ "${INSTALL_MODE:-}" == "server" ]]; then
        ui_info "Server mode: Filtering packages..."
        local server_filtered_packages=()
        for pkg in "${packages_to_install[@]}"; do
             # Simple filter: remove plymouth and bluez related
             if [[ "$pkg" != *"bluez"* && "$pkg" != "plymouth" ]]; then
                server_filtered_packages+=("$pkg")
             fi
        done
        packages_to_install=("${server_filtered_packages[@]}")
    fi
    
    # Install ZSH and friends
    packages_to_install+=("zsh")
    # Note: zsh plugins might be separate packages or need manual install.
    # Arch has zsh-autosuggestions, Ubuntu has zsh-autosuggestions.
    # Fedora has zsh-autosuggestions.
    
    if [ "$DISTRO_ID" == "arch" ]; then
        packages_to_install+=("zsh-autosuggestions" "zsh-syntax-highlighting" "starship" "zram-generator")
    elif [ "$DISTRO_ID" == "fedora" ]; then
        packages_to_install+=("zsh-autosuggestions" "zsh-syntax-highlighting" "starship" "zram-generator")
    elif [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
        packages_to_install+=("zsh-autosuggestions" "zsh-syntax-highlighting")
        # starship might need manual install script on older debian/ubuntu
    fi

    log_info "Installing: ${packages_to_install[*]}"
    
    # Generic install loop
    # Using install_packages_quietly logic (which handles resolution) or loop
    # We should use install_packages_quietly to benefit from the resolver!
    install_packages_quietly "${packages_to_install[@]}"
    
    # Manual installs for Ubuntu/Debian if starship not found
    if [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
         if ! command -v starship >/dev/null; then
             # Try snap for starship on ubuntu, or curl script
             if [ "$DISTRO_ID" == "ubuntu" ]; then
                 sudo snap install starship || curl -sS https://starship.rs/install.sh | sh -s -- -y
             else
                 curl -sS https://starship.rs/install.sh | sh -s -- -y
             fi
         fi
    fi
}

# Run steps
check_prerequisites
configure_package_manager
update_system
install_all_packages
