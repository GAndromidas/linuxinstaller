#!/bin/bash

# Distro Detection and Package Manager Abstraction

# Detect Linux distribution and set package manager variables
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
            PKG_INSTALL="pacman -S --needed"
            PKG_REMOVE="pacman -Rns"
            PKG_UPDATE="pacman -Syu"
            PKG_NOCONFIRM="--noconfirm"
            PKG_CLEAN="pacman -Sc --noconfirm"
            ;;
        fedora)
            DISTRO_ID="fedora"
            PKG_MANAGER="dnf"
            PKG_INSTALL="dnf install"
            PKG_REMOVE="dnf remove"
            PKG_UPDATE="dnf upgrade"
            PKG_NOCONFIRM="-y"
            PKG_CLEAN="dnf clean all"
            ;;
        debian)
            DISTRO_ID="debian"
            PKG_MANAGER="apt"
            PKG_INSTALL="apt-get install"
            PKG_REMOVE="apt-get remove"
            PKG_UPDATE="DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq"
            PKG_NOCONFIRM="-y"
            PKG_CLEAN="apt-get clean"
            ;;
        ubuntu)
            DISTRO_ID="ubuntu"
            PKG_MANAGER="apt"
            PKG_INSTALL="apt-get install"
            PKG_REMOVE="apt-get remove"
            PKG_UPDATE="DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq"
            PKG_NOCONFIRM="-y"
            PKG_CLEAN="apt-get clean"
            ;;
        *)
            echo "Error: Unsupported distribution: $DISTRO_ID"
            exit 1
            ;;
    esac

    export DISTRO_ID PKG_MANAGER PKG_INSTALL PKG_REMOVE PKG_UPDATE PKG_NOCONFIRM PKG_CLEAN PRETTY_NAME
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

# Setup primary and backup universal package manager (flatpak/snap/native)
setup_package_providers() {
    # Determine primary and backup universal package manager
    if [ "$DISTRO_ID" = "ubuntu" ]; then
        PRIMARY_UNIVERSAL_PKG="snap"
        BACKUP_UNIVERSAL_PKG="none"
    else
        PRIMARY_UNIVERSAL_PKG="flatpak"
        BACKUP_UNIVERSAL_PKG="none"
    fi

    if [ "${INSTALL_MODE:-default}" = "server" ]; then
        if [ "$DISTRO_ID" != "ubuntu" ]; then
             PRIMARY_UNIVERSAL_PKG="native"
             BACKUP_UNIVERSAL_PKG="native"
        fi
    fi

    export PRIMARY_UNIVERSAL_PKG BACKUP_UNIVERSAL_PKG
}

# Define common utility packages for all distros
define_common_packages() {
    # Common packages
    COMMON_UTILS="bc curl git rsync ufw fzf fastfetch eza zoxide"

    # Use resolver implicitly by listing generic names where possible,
    # but for bootstrap we hardcode to ensure they exist before resolver is ready
    case "$DISTRO_ID" in
        arch)
            HELPER_UTILS=($COMMON_UTILS base-devel bluez-utils cronie openssh pacman-contrib plymouth flatpak)
            ;;
        fedora)
            HELPER_UTILS=($COMMON_UTILS @development-tools bluez cronie openssh-server plymouth flatpak)
            ;;
        debian)
            HELPER_UTILS=($COMMON_UTILS build-essential bluez cron openssh-server plymouth flatpak)
            ;;
        ubuntu)
            HELPER_UTILS=($COMMON_UTILS build-essential bluez cron openssh-server plymouth snapd)
            ;;
    esac

    export HELPER_UTILS
}

# Resolve package name across different distributions (hardcoded fallback)
resolve_package_name() {
    local pkg="$1"
    local mapped="$pkg"

    if [ "$DISTRO_ID" != "arch" ]; then
        case "$pkg" in
            pacman-contrib|expac|yay|mkinitcpio) echo ""; return ;;
        esac
    fi

    if [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
        case "$pkg" in
            base-devel) mapped="build-essential" ;;
            android-tools) mapped="adb fastboot" ;;
            cronie) mapped="cron" ;;
            bluez-utils) mapped="bluez" ;;
            openssh) mapped="openssh-server" ;;
            docker) mapped="docker.io" ;;
        esac
    elif [ "$DISTRO_ID" == "fedora" ]; then
        case "$pkg" in
            base-devel) mapped="@development-tools" ;;
            cronie) mapped="cronie" ;;
            openssh) mapped="openssh-server" ;;
        esac
    fi

    echo "$mapped"
}
