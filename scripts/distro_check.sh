#!/bin/bash

# Distro Detection and Package Manager Abstraction

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID=$ID
        # Some distros might not have VERSION_ID or it might be empty (e.g. Arch Rolling)
        DISTRO_VERSION=${VERSION_ID:-rolling}
    else
        echo "Error: Cannot detect distribution. /etc/os-release not found."
        exit 1
    fi

    # Normalize DISTRO_ID
    case "$DISTRO_ID" in
        arch|archlinux|cachyos|endeavouros|manjaro)
            DISTRO_ID="arch"
            PKG_MANAGER="pacman"
            PKG_INSTALL="sudo pacman -S --needed"
            PKG_REMOVE="sudo pacman -Rns"
            PKG_UPDATE="sudo pacman -Syu"
            PKG_NOCONFIRM="--noconfirm"
            PKG_CLEAN="sudo pacman -Sc --noconfirm"
            ;;
        fedora)
            DISTRO_ID="fedora"
            PKG_MANAGER="dnf"
            PKG_INSTALL="sudo dnf install"
            PKG_REMOVE="sudo dnf remove"
            PKG_UPDATE="sudo dnf upgrade"
            PKG_NOCONFIRM="-y"
            PKG_CLEAN="sudo dnf clean all"
            ;;
        debian)
            DISTRO_ID="debian"
            PKG_MANAGER="apt"
            PKG_INSTALL="sudo apt-get install"
            PKG_REMOVE="sudo apt-get remove"
            PKG_UPDATE="sudo apt-get update && sudo apt-get upgrade"
            PKG_NOCONFIRM="-y"
            PKG_CLEAN="sudo apt-get clean"
            ;;
        ubuntu)
            DISTRO_ID="ubuntu"
            PKG_MANAGER="apt"
            PKG_INSTALL="sudo apt-get install"
            PKG_REMOVE="sudo apt-get remove"
            PKG_UPDATE="sudo apt-get update && sudo apt-get upgrade"
            PKG_NOCONFIRM="-y"
            PKG_CLEAN="sudo apt-get clean"
            ;;
        *)
            echo "Error: Unsupported distribution: $DISTRO_ID"
            exit 1
            ;;
    esac

    export DISTRO_ID PKG_MANAGER PKG_INSTALL PKG_REMOVE PKG_UPDATE PKG_NOCONFIRM PKG_CLEAN
}

detect_de() {
    # Detect Desktop Environment
    if [ "${XDG_CURRENT_DESKTOP:-}" = "" ]; then
        # Try to detect via installed packages or other env vars if not set
        if [ "$DISTRO_ID" = "arch" ]; then
             if pacman -Qq plasma-desktop >/dev/null 2>&1; then XDG_CURRENT_DESKTOP="KDE"; fi
             if pacman -Qq gnome-shell >/dev/null 2>&1; then XDG_CURRENT_DESKTOP="GNOME"; fi
        elif [ "$DISTRO_ID" = "fedora" ]; then
             if rpm -q plasma-desktop >/dev/null 2>&1; then XDG_CURRENT_DESKTOP="KDE"; fi
             if rpm -q gnome-shell >/dev/null 2>&1; then XDG_CURRENT_DESKTOP="GNOME"; fi
        elif [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
             if dpkg -l | grep -q plasma-desktop; then XDG_CURRENT_DESKTOP="KDE"; fi
             if dpkg -l | grep -q gnome-shell; then XDG_CURRENT_DESKTOP="GNOME"; fi
        fi
    fi
    export XDG_CURRENT_DESKTOP
}

setup_package_providers() {
    # Determine primary and backup universal package manager
    # Rules:
    # - Ubuntu: Snap (Primary), Flatpak (Backup/Optional)
    # - Others: Flatpak (Primary), Snap (Backup/Optional)
    # - Server: Ubuntu uses Snap, others avoid generic containerized apps unless specified.

    if [ "$DISTRO_ID" = "ubuntu" ]; then
        PRIMARY_UNIVERSAL_PKG="snap"
        BACKUP_UNIVERSAL_PKG="flatpak"
    else
        PRIMARY_UNIVERSAL_PKG="flatpak"
        BACKUP_UNIVERSAL_PKG="snap"
    fi

    # In server mode, we might restrict this
    if [ "${INSTALL_MODE:-default}" = "server" ]; then
        if [ "$DISTRO_ID" != "ubuntu" ]; then
             # On non-Ubuntu server, prefer native only
             PRIMARY_UNIVERSAL_PKG="native"
             BACKUP_UNIVERSAL_PKG="native"
        fi
    fi

    export PRIMARY_UNIVERSAL_PKG BACKUP_UNIVERSAL_PKG
}

define_common_packages() {
    # Common packages
    COMMON_UTILS="bc curl git rsync ufw fzf fastfetch eza zoxide"
    
    # Distro specific additions
    case "$DISTRO_ID" in
        arch)
            # Arch specific: pacman-contrib, expac, yay are handled elsewhere or ignored by resolver if not arch
            HELPER_UTILS=($COMMON_UTILS base-devel bluez-utils cronie openssh pacman-contrib plymouth flatpak)
            ;;
        fedora)
            # Mapped via resolve_package_name logic
            HELPER_UTILS=($COMMON_UTILS base-devel bluez-utils cronie openssh plymouth flatpak)
            ;;
        debian|ubuntu)
            # Mapped via resolve_package_name logic
            HELPER_UTILS=($COMMON_UTILS base-devel bluez-utils cronie openssh plymouth flatpak)
            ;;
    esac
    
    export HELPER_UTILS
}
}

# Helper function to resolve package names across distros
resolve_package_name() {
    local pkg="$1"
    local mapped="$pkg"

    # Ignore Arch-specific packages on other distros
    if [ "$DISTRO_ID" != "arch" ]; then
        case "$pkg" in
            noto-fonts-extra) mapped="fonts-noto-extra" ;;
            noto-fonts-extra) mapped="google-noto-sans-fonts google-noto-serif-fonts" ;;
            sshfs) mapped="fuse-sshfs" ;;
            pacman-contrib|expac|yay|mkinitcpio|arch-install-scripts)
                echo ""
                return
                ;;
        esac
    fi

    if [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
        case "$pkg" in
            noto-fonts-extra) mapped="fonts-noto-extra" ;;
            noto-fonts-extra) mapped="google-noto-sans-fonts google-noto-serif-fonts" ;;
            sshfs) mapped="fuse-sshfs" ;;
            base-devel) mapped="build-essential" ;;
            android-tools) mapped="adb fastboot" ;;
            cronie) mapped="cron" ;;
            bluez-utils) mapped="bluez" ;;
            openssh) mapped="openssh-server" ;;
            fd) mapped="fd-find" ;;
            bat) mapped="bat" ;; # Binary is batcat
            docker) mapped="docker.io" ;;
            python) mapped="python3" ;;
        esac
    elif [ "$DISTRO_ID" == "fedora" ]; then
        case "$pkg" in
            noto-fonts-extra) mapped="fonts-noto-extra" ;;
            noto-fonts-extra) mapped="google-noto-sans-fonts google-noto-serif-fonts" ;;
            sshfs) mapped="fuse-sshfs" ;;
            base-devel) mapped="@development-tools" ;;
            android-tools) mapped="android-tools" ;;
            cronie) mapped="cronie" ;;
            openssh) mapped="openssh-server" ;;
            python) mapped="python3" ;;
        esac
    fi
    
    echo "$mapped"
}
