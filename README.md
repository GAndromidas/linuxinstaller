Arch Linux Installation Script
Description

This script automates the setup and configuration of an Arch Linux system. It streamlines the installation process with various system tweaks and software installations.
Author

George Andromidas
Features

    Kernel Headers: Detects and installs appropriate Linux kernel headers.
    Systemd-Boot: Configures for a silent boot.
    Boot Configuration: Updates loader.conf for faster boot times.
    Password Feedback: Enables password feedback in sudo.
    Pacman Configuration: Improves performance and features.
    Mirrorlist Update: Refreshes mirrorlist and reflector settings.
    System Update: Performs a full system update.
    ZSH Setup: Installs and configures ZSH with Oh-My-ZSH and plugins.
    Default Shell: Changes the default shell to ZSH.
    Starship Prompt: Installs and configures the Starship prompt.
    Locales Configuration: Sets up system locales.
    YAY AUR Helper: Installs the YAY AUR helper.
    Additional Programs: Installs extra programs and dependencies.
    Services: Enables and starts necessary system services.
    Fastfetch Configuration: Creates a fastfetch configuration.
    Firewall Configuration: Sets up firewalld.
    Cache Cleanup: Clears unused packages and cache.
    Folder Cleanup: Deletes the installation folder upon completion.
    Reboot Option: Offers an option to reboot the system.

Prerequisites

    Arch Linux system with git and curl installed.

Installation

    Clone the Repository:

    bash

git clone https://github.com/gandromidas/archinstaller
cd archinstaller

Run the Script:

    For a full default installation:

    bash

./install.sh -d

For a minimal installation:

bash

        ./install.sh -m

Usage

    -d, --default: Installs the default set of programs and configurations.
    -m, --minimal: Installs a minimal set of programs and configurations.
    -h, --help: Displays the help message.

Notes

    Review the script for any modifications specific to your setup before running.
    Ensure your system is fully updated before executing the script.
