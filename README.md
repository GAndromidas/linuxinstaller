# LinuxInstaller

<div align="center">

![LinuxInstaller Screenshot](https://github.com/user-attachments/assets/864b65e9-9144-40f5-98ce-1994461f1625)

**A unified, intelligent post-installation script for Arch Linux, Fedora, Debian, and Ubuntu**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash)](https://www.gnu.org/software/bash/)

</div>

---

## Overview

**LinuxInstaller** is a powerful, cross-distribution post-installation script that abstracts package management and system configuration. Whether you're running Arch Linux, Fedora, Debian, or Ubuntu, LinuxInstaller provides a consistent, high-quality environment setup with intelligent package resolution and distro-specific optimizations.

### Why LinuxInstaller?

- **One Script, Multiple Distros** - Works seamlessly across Arch, Fedora, Debian, and Ubuntu
- **Smart Package Resolution** - Automatically resolves package names across different package managers
- **Fast & Efficient** - Minimal output, maximum productivity
- **Beautiful Shell Setup** - ZSH with autosuggestions, syntax highlighting, and Starship prompt
- **Distro-Aware Configuration** - Automatically applies the right configs for your distribution

---

## Key Features

### Smart Package Management

- **Automatic Detection**: Detects your package manager (pacman, dnf, apt) automatically
- **Universal Packages**: Specify generic package names, LinuxInstaller resolves them
- **Desktop Apps**: Defaults to Flatpak (Arch/Fedora/Debian) or Snap (Ubuntu) for GUI applications
- **Server Mode**: Lean setup without containerized apps for headless servers

### Shell Environment

- **ZSH Configuration**: Distro-specific `.zshrc` files with optimized settings
- **Plugins**: `zsh-autosuggestions` and `zsh-syntax-highlighting` (installed via package managers)
- **Starship Prompt**: Modern, fast, and customizable prompt
- **Modern CLI Tools**: `eza`, `bat`, `fzf`, `fastfetch`, `zoxide`

### Intelligent Configuration

- **Desktop Environment Detection**: Automatically detects GNOME, KDE, or Cosmic
- **Environment-Specific Optimizations**: Applies shortcuts and settings for your DE
- **Firewall Configuration**: Handles UFW (Debian/Ubuntu) or Firewalld (Fedora/Arch)
- **System Services**: Configures essential services (SSH, fail2ban, Wake-on-LAN, etc.)

### Security & System

- **Password Feedback**: Asterisks when typing passwords in terminal
- **Fail2ban Setup**: Automatic configuration for SSH protection
- **Firewall Management**: Distro-appropriate firewall configuration
- **Logitech Mouse Detection**: Auto-installs Solaar for Logitech devices

### Localization

- **Smart Locale Detection**: Automatically enables US and local country locales
- **IP Geolocation**: Detects your country and enables appropriate locales
- **Timezone-Based Fallback**: Uses system timezone if geolocation fails

---

## Installation

### Prerequisites

- A fresh or existing installation of Arch Linux, Fedora, Debian, or Ubuntu
- `sudo` privileges
- Internet connection

### Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/linuxinstaller.git
   cd linuxinstaller
   ```

2. **Make the script executable**:
   ```bash
   chmod +x install.sh
   ```

3. **Run the installer**:
   ```bash
   ./install.sh
   ```

4. **Select your installation mode**:
   - **Standard**: Recommended for most users (full desktop setup)
   - **Minimal**: Core essentials only (lightweight setup)
   - **Server**: Headless setup (Docker, SSH, no GUI apps)
   - **Custom**: Interactive selection of components

### Command Line Options

```bash
./install.sh [OPTIONS]

Options:
    -h, --help      Show help message and exit
    -v, --verbose   Enable verbose output for debugging
    -m, --mode      Installation mode (standard, minimal, server, custom)
```

**Example**:
```bash
./install.sh -m minimal -v
```

---

## Configuration

LinuxInstaller is fully configuration-driven. Customize your installation by editing the configuration files:

### Configuration Files

| File | Description |
|------|-------------|
| `configs/programs.yaml` | Package lists for different installation modes |
| `configs/package_map.yaml` | Generic to distro-specific package name mappings |
| `configs/starship.toml` | Starship prompt customization |
| `configs/.zshrc.*` | Distro-specific ZSH configuration files |
| `configs/config.jsonc` | Fastfetch configuration |

### Customizing Packages

Edit `configs/programs.yaml` to add or remove packages:

```yaml
standard:
  native:
    - firefox
    - vim
  flatpak:
    - com.spotify.Client
```

The script will automatically resolve package names using `package_map.yaml` if needed.

---

## Project Structure

```
linuxinstaller/
├── install.sh                 # Main entry point
├── configs/                   # Configuration files
│   ├── programs.yaml          # Package lists
│   ├── package_map.yaml       # Package name mappings
│   ├── starship.toml          # Starship prompt config
│   ├── .zshrc.arch            # Arch-specific ZSH config
│   ├── .zshrc.fedora          # Fedora-specific ZSH config
│   ├── .zshrc.debian          # Debian-specific ZSH config
│   └── .zshrc.ubuntu          # Ubuntu-specific ZSH config
└── scripts/                   # Core scripts
    ├── distro_check.sh        # Distro detection & package manager abstraction
    ├── system_preparation.sh  # System setup & package installation
    ├── programs.sh            # Package resolution & installation logic
    ├── shell_setup.sh         # ZSH & shell configuration
    ├── system_services.sh     # Service configuration
    └── common.sh              # Shared utilities & functions
```

---

## Installation Modes

### Standard Mode
Full-featured desktop setup with:
- Complete package suite
- Desktop environment optimizations
- Gaming tools (if applicable)
- Development tools
- Media codecs

### Minimal Mode
Lightweight setup with:
- Essential system packages
- Basic CLI tools
- Core utilities only

### Server Mode
Headless server setup with:
- Docker & containerization tools
- SSH server configuration
- System monitoring tools
- No GUI applications

### Custom Mode
Interactive selection where you choose:
- Which package categories to install
- Desktop environment optimizations
- System services to configure

---

## Advanced Features

### Distro-Specific Optimizations

- **Arch Linux**: AUR support via Yay, pacman hooks, multilib configuration
- **Fedora**: RPMFusion repositories, DNF optimizations
- **Debian/Ubuntu**: APT optimizations, Snap integration (Ubuntu only)

### Automatic Detection

- **Hardware**: Logitech mice, Ethernet interfaces for Wake-on-LAN
- **Desktop Environment**: GNOME, KDE, Cosmic
- **Bootloader**: GRUB, systemd-boot
- **Country/Locale**: IP geolocation for locale setup

---

## Contributing

Contributions are welcome! Here's how you can help:

1. **Report Issues**: Found a bug? Open an issue with details
2. **Add Package Mappings**: If a package has different names across distros, update `package_map.yaml`
3. **Improve Documentation**: Help make the README and docs better
4. **Add Features**: Submit PRs for new features or improvements

### Areas for Contribution

- Package name mappings for different distributions
- Additional desktop environment support
- New installation modes
- Performance optimizations
- Documentation improvements

---

## License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Inspired by the need for a unified post-installation experience across Linux distributions
- Built for the Linux community

---

<div align="center">

**Made for Linux users everywhere**

[Star this repo](https://github.com/yourusername/linuxinstaller) if you find it useful!

</div>
