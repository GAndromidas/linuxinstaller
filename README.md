# Arch Linux System Setup Script

This Bash script automates the setup and configuration of an Arch Linux system, aiming to streamline the installation process for both beginners and experienced users.

## Features

- **Automated Configuration**: The script automates various configuration tasks including setting up pacman, installing Oh-My-ZSH with plugins, configuring locales and timezone, and more.
- **Package Management**: Installs essential packages, AUR packages, and Flatpak apps to set up a complete working environment.
- **Firewall Configuration**: Configures the firewall using UFW to enhance system security.
- **Service Management**: Enables essential services like Bluetooth, SSH, etc., for a smooth user experience.
- **Cleanup**: Removes installation files and directories to keep the system clean post-installation.

## Usage
1. Clone this repository:

   git clone https://github.com/karlfloyd/archinstaller.git

2. Navigate to the cloned directory:

   cd archinstaller

3. Run the install.sh script:

   chmod +x install.sh

   sudo ./install.sh

## Disclaimer
- Use this script at your own risk. 
- Read through the script before running to ensure it meets your requirements.
- This script assumes you have a basic understanding of Arch Linux and system administration.

## License
This project is licensed under the terms of the MIT license. See the [LICENSE](LICENSE) file for details.
