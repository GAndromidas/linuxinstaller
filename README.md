# Arch Linux Installation Script

This script is designed for setting up an Arch Linux system with various configurations and installations. The script offers a user-friendly menu for selecting different installation options and automates numerous post-installation tasks.

![archinstaller](https://github.com/user-attachments/assets/72ff3e94-dd8d-4e18-8c13-30f8b6ba4ef6)

## Table of Contents
1. [Features](#features)
2. [Usage](#usage)
3. [Script Details](#script-details)
    - [Variables](#variables)
    - [Functions](#functions)
4. [Author](#author)

## Features

- Installs and configures Linux kernel headers based on the installed kernel type.
- Configures systemd-boot or GRUB bootloader.
- Enhances Pacman with color and parallel downloads.
- Updates the system and the mirrorlist.
- Installs and configures ZSH with Oh-My-ZSH and useful plugins.
- Installs Starship prompt.
- Configures locales.
- Installs AUR helper YAY.
- Installs various programs based on user selection.
- Enables essential services.
- Configures a firewall with firewalld.
- Provides options to install Fail2ban, Virt-Manager, and DaVinci Resolve.
- Clears unused packages and cache.
- Optionally reboots the system after installation.

## Usage

1. **Clone the repository:**
    ```bash
    git clone https://github.com/gandromidas/archinstaller && cd archinstaller
    ```

2. **Run the script:**
    ```bash
    ./install.sh
    ```

3. **Follow the on-screen prompts to select the desired installation option:**
    - Default Installation
    - Minimal Installation
    - Exit

## Script Details

### Variables

- `KERNEL_HEADERS`: Default Linux headers.
- `LOADER_DIR`, `ENTRIES_DIR`, `LOADER_CONF`, `CONFIGS_DIR`, `SCRIPTS_DIR`: Various directory paths used in the script.
- Color codes for formatted terminal output (`RED`, `GREEN`, `YELLOW`, `BLUE`, `MAGENTA`, `CYAN`, `RESET`).

### Functions

- **print_info**, **print_success**, **print_warning**, **print_error**: Print messages with different color codes.
- **show_menu**: Displays the main menu for selecting the installation option.
- **install_kernel_headers**: Installs appropriate kernel headers based on the installed kernel type.
- **make_systemd_boot_silent**: Configures systemd-boot for a silent boot.
- **change_loader_conf**: Updates the `loader.conf` file with desired settings.
- **enable_asterisks_sudo**: Enables asterisks for password input in sudoers.
- **configure_pacman**: Enhances Pacman configuration.
- **update_mirrorlist**: Updates the mirrorlist and configures `reflector`.
- **update_system**: Updates the system packages.
- **install_zsh**: Installs and configures ZSH with Oh-My-ZSH.
- **change_shell_to_zsh**: Changes the default shell to ZSH.
- **move_zshrc**: Moves `.zshrc` to the home directory.
- **install_starship**: Installs the Starship prompt and moves its configuration file.
- **configure_locales**: Configures system locales.
- **install_yay**: Installs YAY (AUR helper).
- **install_programs**: Installs additional programs based on the user's selection.
- **enable_services**: Enables essential system services.
- **create_fastfetch_config**: Creates and moves the `fastfetch` configuration.
- **configure_firewall**: Configures the firewall using `firewalld`.
- **install_and_configure_fail2ban**: Installs and configures Fail2ban.
- **install_and_configure_virt_manager**: Installs and configures Virt-Manager.
- **install_davinci_resolve**: Prompts and installs DaVinci Resolve if desired.
- **clear_unused_packages_cache**: Clears unused packages and cache.
- **delete_archinstaller_folder**: Deletes the `archinstaller` folder after completion.
- **reboot_system**: Prompts the user to reboot the system.

### Contribution

Contributions are welcome! Please fork the repository and submit a pull request with your changes. Make sure to follow the existing code style and include comments where necessary.

### License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

### Acknowledgments

- Inspired by various Arch Linux setup guides and scripts.
- Special thanks to the Arch Linux community for their extensive documentation and support.
