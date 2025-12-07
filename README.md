<div align="center">

# Archinstaller

</div>

[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/commits/main)
[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)


**Archinstaller** is an advanced post-installation script for Arch Linux that automates the transition from a base system to a fully configured, highly optimized, and ready-to-use desktop environment. It leverages intelligent detection systems to tailor the installation to your specific hardware, ensuring optimal performance and stability.

Built with the Arch Linux philosophy of simplicity and minimalism, Archinstaller provides a clean, professional installation experience with enhanced user interface features including real-time progress tracking, time estimation, and intelligent resume functionality.

## Demo
<div align="center">
<img width="666" height="369" alt="archinstaller" src="https://github.com/user-attachments/assets/f00f6518-2f10-42f5-b312-d098b3e0f913" />
</div>

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
*   **Dedicated Server Mode**: A one-click setup for a true headless server environment. This mode installs a curated list of server tools (like Docker and Portainer), skips all graphical components and desktop shells, and applies a secure-by-default firewall configuration.
*   **Intelligent Security Hardening**: Deploys and configures a robust security posture out-of-the-box. This includes a stricter `Fail2ban` policy and a smart `UFW` firewall configuration that sets secure defaults, always allows SSH, and automatically opens ports for KDE Connect only when a KDE Plasma desktop is detected.
*   **Optional Gaming Mode**: A one-click setup for a complete gaming environment, including Steam, Faugus Launcher, Heroic Games Launcher, MangoHud, Goverlay and GameMode.
*   **Power Management**: Advanced power-saving features for laptops, including `power-profiles-daemon` or `tuned-ppd`, `thermald` for Intel CPUs, and touchpad gesture support.

#### User Experience
*   **Flexible Installation Modes**: Choose between a feature-rich **Standard** setup, a lightweight **Minimal** installation, a true headless **Server** mode, or an interactive **Custom** mode to select your own packages.
*   **Enhanced Shell**: Comes with a pre-configured Zsh environment powered by Oh-My-Zsh and the Starship prompt.
*   **Smart Resume Functionality**: The installer tracks its progress and can be safely re-run to resume from the last completed step with an interactive menu showing completed steps.
*   **Real-time Progress Tracking**: Visual progress bars with step counters and time estimation for all installation steps.
*   **Professional Interface**: Clean, minimal design following Arch Linux principles with enhanced visual feedback and status updates.

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

#### Installation Experience
The installer provides a modern, user-friendly experience with:
*   **Interactive Menu**: Clean interface powered by `gum` for mode selection and confirmations
*   **Progress Visualization**: Real-time progress bars showing step counters for each step
*   **Time Estimation**: Dynamic time estimates that improve as installation progresses
*   **Resume Support**: If interrupted, the installer can resume from the last completed step
*   **Professional Summary**: Minimal, clean installation summary following Arch Linux principles
*   **Automatic Cleanup**: Removes temporary files and packages after successful installation

## Customization
This installer is designed to be easily customized. The package lists for all installation modes are managed in `configs/programs.yaml`. This file is structured into logical groups (`common`, `desktop_base`, `server`, etc.), allowing you to add or remove packages to perfectly match your preferences without altering the script logic.

## Contributing
Contributions are welcome! Please feel free to submit a pull request for improvements or open an issue to report a bug or request a new feature.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
