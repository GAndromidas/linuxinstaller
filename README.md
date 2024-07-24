Arch Linux Post-Installation Script

Description

This script automates the setup and configuration of an Arch Linux system. It streamlines the installation process with various system tweaks and software installations.

Features

1. Kernel Headers: Detects and installs appropriate Linux kernel headers.
2. Systemd-Boot: Configures for a silent boot.
3. Boot Configuration: Updates loader.conf for faster boot times.
4. Password Feedback: Enables password feedback in sudo.
5. Pacman Configuration: Improves performance and features.
6. Mirrorlist Update: Refreshes mirrorlist and reflector settings.
7. System Update: Performs a full system update.
8. ZSH Setup: Installs and configures ZSH with Oh-My-ZSH and plugins.
9. Default Shell: Changes the default shell to ZSH.
10. Starship Prompt: Installs and configures the Starship prompt.
11. Locales Configuration: Sets up system locales.
12. YAY AUR Helper: Installs the YAY AUR helper.
13. Additional Programs: Installs extra programs and dependencies.
14. Services: Enables and starts necessary system services.
15. Fastfetch Configuration: Creates a fastfetch configuration.
16. Firewall Configuration: Sets up firewalld.
17. Cache Cleanup: Clears unused packages and cache.
18. Folder Cleanup: Deletes the installation folder upon completion.
19. Reboot Option: Offers an option to reboot the system.

Installation

Clone the Repository: 

    git clone https://github.com/gandromidas/archinstaller

Run the Script:

For a full default installation:

    ./install.sh -d

For a minimal installation:

    ./install.sh -m

Notes

1. Review the script for any modifications specific to your setup before running.
2. Ensure your system is fully updated before executing the script.
