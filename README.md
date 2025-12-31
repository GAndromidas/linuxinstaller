<div align="center">

<img width="600" height="135" alt="LinuxInstaller Banner" src="https://github.com/user-attachments/assets/adb433bd-ebab-4c51-a72d-6208164e1026" />

# LinuxInstaller

**Automated post-installation configuration for Arch Linux, Fedora, Debian, and Ubuntu**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-green.svg)](https://kernel.org/)

A comprehensive automation script that transforms a fresh Linux installation into a fully configured, optimized system with intelligent hardware detection and customizable installation modes.

</div>

---

## ✨ Features

- **🎯 Cross-Distribution Support** - Arch Linux, Fedora, Debian, Ubuntu
- **🤖 Smart Hardware Detection** - Automatic GPU, bootloader, and device detection
- **🎮 Gaming Environment** - Steam, Wine, Vulkan drivers, performance optimizations
- **🔒 Security Hardening** - Firewall, Fail2ban, SSH hardening
- **⚡ Performance Tuning** - ZRAM, CPU governor, filesystem optimization
- **🎨 Desktop Integration** - KDE Plasma & GNOME configuration
- **🔄 Resume Capability** - Interrupted installations can be resumed
- **📊 Beautiful UI** - Modern gum-based interface with fallback to text mode

---

## 🚀 Quick Start

```bash
# Download and run
wget https://github.com/GAndromidas/linuxinstaller/raw/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

---

## 📋 Installation Modes

| Mode | Description | Best For |
|-------|-------------|-----------|
| **Standard** | Complete setup with all recommended packages | Full desktop experience |
| **Minimal** | Essential tools only | Lightweight systems, VMs |
| **Server** | Headless server configuration | Production servers |

---

## 🖥️ Distribution Support

### Arch Linux
- ✅ AUR integration with yay/paru
- ✅ Pacman optimization (parallel downloads, ILoveCandy)
- ✅ Plymouth boot screen
- ✅ systemd-zram-generator

### Fedora
- ✅ RPM Fusion repositories
- ✅ DNF optimization
- ✅ Firewalld configuration

### Debian/Ubuntu
- ✅ Universe/Multiverse repositories
- ✅ APT optimization
- ✅ UFW firewall

---

## 🎮 Gaming Suite

When choosing **Standard** or **Minimal** mode, you'll be prompted to install gaming packages:

- 🎮 Steam installation and configuration
- 🍷 Wine setup
- 📊 MangoHud performance monitoring
- ⚡ GameMode system optimization
- 🎯 Vulkan driver installation

---

## 🔒 Security Features

| Feature | Description |
|---------|-------------|
| **Firewall** | UFW (Debian/Ubuntu) or firewalld (Arch/Fedora) |
| **Fail2ban** | SSH brute-force protection (1-hour ban, 3 attempts) |
| **SSH Hardening** | Secure SSH configuration |
| **User Groups** | Automatic addition to essential groups (wheel, docker, etc.) |
| **AppArmor/SELinux** | Distribution-appropriate security framework |

---

## ⚡ Performance Optimization

- **ZRAM** - Compressed swap for limited RAM systems
- **CPU Governor** - Performance mode configuration
- **Swappiness** - Tuned for desktop responsiveness
- **Btrfs Snapper** - Automatic snapshots for rollback capability
- **TRIM** - SSD optimization scheduling

---

## 🎨 Desktop Environments

### KDE Plasma
- Global shortcuts configuration
- Theme optimization
- KDE Connect setup

### GNOME
- Extensions installation
- Theme customization
- Workspace configuration

### Universal
- **Zsh** with syntax highlighting and autosuggestions
- **Starship** prompt with distribution icons
- **Fastfetch** system information tool

---

## 🤖 Smart Hardware Detection

| Hardware | Detection | Action |
|----------|------------|--------|
| **GPU** | lspci/udev | Installs NVIDIA, AMD, or Intel drivers |
| **Bootloader** | /boot analysis | Configures GRUB or systemd-boot |
| **Logitech** | USB/Bluetooth/HID | Installs solaar for device management |
| **Filesystem** | /proc/mounts | Sets up Btrfs snapshots |

---

## 📦 Command-Line Options

```bash
sudo ./install.sh [OPTIONS]

Options:
  -h, --help      Show help message
  -v, --verbose   Enable detailed output
  -d, --dry-run   Preview changes without applying
```

---

## 📁 Project Structure

```
linuxinstaller/
├── install.sh              # Main installer script
├── scripts/               # Modular configuration scripts
│   ├── common.sh          # Shared functions and utilities
│   ├── distro_check.sh    # Distribution detection
│   ├── arch_config.sh     # Arch-specific configuration
│   ├── fedora_config.sh   # Fedora-specific configuration
│   ├── debian_config.sh    # Debian/Ubuntu configuration
│   ├── kde_config.sh      # KDE Plasma configuration
│   ├── gnome_config.sh    # GNOME configuration
│   ├── security_config.sh  # Security hardening
│   ├── performance_config.sh # Performance tuning
│   ├── gaming_config.sh    # Gaming environment setup
│   └── ...
├── configs/               # Configuration files
│   ├── arch/             # Arch-specific configs
│   ├── fedora/           # Fedora-specific configs
│   ├── debian/           # Debian-specific configs
│   └── ubuntu/           # Ubuntu-specific configs
├── LICENSE                # MIT License
└── README.md             # This file
```

---

## 🛠️ Troubleshooting

### Gum Installation Fails
```bash
sudo pacman -S gum     # Arch
sudo dnf install gum    # Fedora
sudo apt install gum     # Debian/Ubuntu
```

### Permission Issues
```bash
chmod +x install.sh
sudo ./install.sh
```

### View Installation Log
```bash
cat ~/.linuxinstaller.log
```

---

## 📝 Requirements

- Fresh Linux installation (Arch, Fedora, Debian, or Ubuntu)
- Active internet connection
- Regular user account with sudo privileges
- Minimum 2GB free disk space

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **Arch Linux Community** - Excellent documentation and package management
- **Fedora Project** - RPM Fusion and package ecosystem
- **Debian/Ubuntu Teams** - Stable and reliable distributions
- **All Contributors** - Testing, feedback, and improvements

---

<div align="center">

**Built with ❤️ for the Linux community**

[⬆ Back to Top](#linuxinstaller)

</div>
