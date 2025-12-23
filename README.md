# LinuxInstaller - Unified Linux Post-Installation Script

![LinuxInstaller Logo](https://via.placeholder.com/800x200.png?text=LinuxInstaller)

**LinuxInstaller** is a unified, intelligent post-installation script designed to work across **Arch Linux**, **Fedora**, **Debian**, and **Ubuntu**. It abstracts package management and system configuration to provide a consistent, high-quality environment regardless of the underlying distribution.

## 🚀 Key Features

*   **Multi-Distro Support**:
    *   **Arch Linux**: Full support (AUR, Pacman).
    *   **Fedora**: Native DNF support, Flatpak integration.
    *   **Debian/Ubuntu**: Apt support, Snap/Flatpak integration.
*   **Smart Package Management**:
    *   Automatically detects the package manager (pacman, dnf, apt).
    *   **Universal Packages**:
        *   Desktop: Defaults to Flatpak (Arch/Fedora/Debian) or Snap (Ubuntu) for GUI apps.
        *   Server: Avoids containerized apps by default for a lean footprint.
*   **Shell Environment**:
    *   Sets up **ZSH** with **Oh-My-Zsh** features (Autosuggestions, Syntax Highlighting).
    *   Configures **Starship** prompt cross-platform.
    *   Installs modern CLI tools (`eza`, `bat`, `fzf`, `fastfetch`).
*   **Intelligent Configuration**:
    *   Detects Desktop Environment (GNOME, KDE, Cosmic) and installs specific optimizations and shortcuts.
    *   Handles Firewall (UFW/Firewalld).

## 📦 Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/yourusername/linuxinstaller.git
    cd linuxinstaller
    ```

2.  **Run the installer**:
    ```bash
    ./install.sh
    ```

3.  **Follow the on-screen menu**:
    Select your mode:
    *   **Standard**: Recommended for most users.
    *   **Minimal**: Core essentials only.
    *   **Server**: Headless setup (Docker, SSH, no GUI apps).
    *   **Custom**: Interactive selection.

### Command Line Options

```bash
./install.sh [OPTIONS]

Options:
    -h, --help      Show help message
    -v, --verbose   Enable verbose output
    -m, --mode      Installation mode (default, server, minimal)
```

## 📂 Configuration

The installer is configuration-driven. You can customize what gets installed by editing `configs/programs.yaml`.

*   **`configs/programs.yaml`**: Lists packages. You can specify native names, or generic names that the script tries to resolve via Flatpak/Snap.
*   **`configs/starship.toml`**: Customization for the shell prompt.

## Directory Structure

*   `scripts/distro_check.sh`: The brain of the operation. Handles distro detection and package manager abstraction.
*   `scripts/programs.sh`: Logic for resolving and installing packages across different providers.
*   `install.sh`: The main entry point.

## 🤝 Contributing

Contributions are welcome! If you find a package that is named differently on Fedora or Debian, feel free to submit a PR to update the mapping logic in `scripts/programs.sh` or `scripts/distro_check.sh`.

## 📄 License

This project is licensed under the MIT License.
