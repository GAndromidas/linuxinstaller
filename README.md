# Arch Linux Installation Script

## Description
This script automates the setup and configuration of an Arch Linux system. It performs a variety of installations and system tweaks to streamline the setup process for new installations or after system updates.

## Author
- **George Andromidas**

## Features
- Detects and installs appropriate Linux kernel headers.
- Configures systemd-boot for a silent boot.
- Updates `loader.conf` for faster boot times.
- Enables password feedback in `sudo`.
- Configures Pacman for improved performance and features.
- Updates mirrorlist and reflector configurations.
- Performs a full system update.
- Installs and configures ZSH with Oh-My-ZSH and plugins.
- Changes the default shell to ZSH.
- Installs and configures the Starship prompt.
- Configures system locales.
- Installs YAY AUR helper.
- Installs additional programs and dependencies.
- Enables and starts necessary system services.
- Creates a fastfetch configuration.
- Configures the firewall using `firewalld`.
- Clears unused packages and cache.
- Deletes the installation folder upon completion.
- Offers an option to reboot the system.

## Prerequisites
- Ensure you have an Arch Linux system with `git` and `curl` installed.

## Installation
1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/gandromidas/archinstaller
   cd archinstaller
