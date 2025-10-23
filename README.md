# Archinstaller

[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/commits/main)
[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)

**Archinstaller** is an advanced post-installation script for Arch Linux that automates the transition from a base system to a fully configured, highly optimized, and ready-to-use desktop environment. It leverages intelligent detection systems to tailor the installation to your specific hardware, ensuring optimal performance and stability.

## Demo
<img width="796" height="423" alt="ArchInstaller" src="https://github.com/user-attachments/assets/2f866c98-37e7-4036-aacf-c24aa0ab49f3" />

## Core Philosophy

This project is built on the principle of **Intelligent Automation**. Instead of providing a one-size-fits-all setup, Archinstaller inspects your system's hardware and software to make smart decisions, applying best-practice configurations that would otherwise require hours of manual research and tweaking.

## Key Features

#### System Intelligence & Automation
*   **Hardware Detection**: Automatically identifies your CPU (Intel/AMD), GPU (NVIDIA/AMD/Intel), storage type (NVMe/SSD/HDD), and laptop-specific hardware to apply tailored configurations.
*   **Driver Management**: Installs the correct graphics drivers, including legacy NVIDIA drivers and VM guest utilities.
*   **Performance Optimization**: Dynamically configures ZRAM swap, I/O schedulers, and memory parameters based on your system's resources.
*   **Desktop Environment Integration**: Applies specific optimizations and keyboard shortcuts for KDE, GNOME, and Cosmic desktops.

#### Robust Features
*   **Btrfs Snapshot System**: Implements a full Btrfs snapshot and recovery solution with `snapper`, including bootloader integration with GRUB for easy rollbacks.
*   **Security Hardening**: Deploys and configures a firewall (`firewalld` or `UFW`) and `Fail2ban` for out-of-the-box system protection.
*   **Optional Gaming Mode**: A one-click setup for a complete gaming environment, including Steam, Lutris, Heroic Games Launcher, MangoHud, and GameMode.
*   **Power Management**: Advanced power-saving features for laptops, including `power-profiles-daemon` or `tuned-ppd`, `thermald` for Intel CPUs, and touchpad gesture support.

#### User Experience
*   **Flexible Installation Modes**: Choose between a feature-rich **Standard** setup, a lightweight **Minimal** installation, or an interactive **Custom** mode to select your own packages.
*   **Enhanced Shell**: Comes with a pre-configured Zsh environment powered by Oh-My-Zsh and the Starship prompt.
*   **Resumable Installation**: The installer tracks its progress and can be safely re-run to resume from the last completed step.

## Installation

#### Prerequisites
*   A fresh, minimal Arch Linux installation with an active internet connection.
*   A regular user account with `sudo` privileges.

#### Quick Start
1.  **Clone the repository:**
    ```bash
    git clone https://github.com/gandromidas/archinstaller.git
    ```
2.  **Navigate to the directory:**
    ```bash
    cd archinstaller
    ```
3.  **Run the installer:**
    ```bash
    ./install.sh
    ```
The script will present a menu where you can choose your desired installation mode.

## Customization
This installer is designed to be easily customized. The package lists for all installation modes are managed in a human-readable YAML file located at `configs/programs.yaml`. You can add or remove packages from these lists to perfectly match your preferences without altering the script logic.

## Contributing
Contributions are welcome! Please feel free to submit a pull request for improvements or open an issue to report a bug or request a new feature.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
