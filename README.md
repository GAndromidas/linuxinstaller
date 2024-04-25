# Arch Linux System Setup Script

This script automates the setup process for an Arch Linux system, configuring various settings, installing essential programs, and enabling services. It's designed to streamline the setup process and ensure consistency across installations.

## Features

- Display ASCII Art to add visual appeal.
- Prompt user for password to perform administrative tasks.
- Configure Pacman for optimized package management.
- Update system and mirrorlist for latest packages and faster downloads.
- Install Oh-My-ZSH and ZSH Plugins for enhanced shell experience.
- Set language locale and timezone for system.
- Install Yay for managing AUR packages.
- Install essential programs and KDE-specific programs.
- Enable necessary services such as firewall, SSH, and fail2ban.
- Configure firewall settings to enhance security.
- Restart Fail2Ban service with customized settings.
- Clean up and delete setup files after completion.
- Reboot system with countdown and cancel option.

## Usage

1. Clone the repository `git clone https://github.com/gandromidas/archinstaller`.
2. Make the script executable: `chmod +x install.sh`.
3. Run the script with `./install.sh`.
4. Follow the prompts and enter the necessary information when prompted.
5. Sit back and relax while the script handles the setup process.

## Note

- Ensure you have an active internet connection before running the script.
- Review the script content before executing to ensure compatibility and security.
- Some configurations may require manual intervention or customization based on specific requirements.

## License

This project is licensed under the [MIT License](LICENSE).
