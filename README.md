# Arch Linux Installation Script

This script automates the setup of an Arch Linux system with various configurations and installations.

## Purpose
The script performs the following tasks:
- Identifies and installs kernel headers based on the detected kernel type.
- Configures Pacman settings for package management.
- Adds silent boot options to Systemd-Boot.
- Changes the default shell to ZSH.
- Sets language locale and timezone settings.
- Installs essential programs, KDE-specific programs or Gnome-specific programs, AUR packages, and YAY.
- Enables necessary services for system functionality.
- Configures UFW firewall settings.
- Removes unused packages and clears cache.
- Deletes the archinstaller folder after setup completion.

## Installation

To use this script:

1. Download the repository: git clone https://github.com/gandromidas/archinstaller
2. Go to the directory: cd archinstaller/
3. Run the script: ./install.sh
