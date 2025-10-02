# Archinstaller

Comprehensive post-installation automation script for Arch Linux systems.

[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/commits/main)
[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)
[![YouTube Video](https://img.shields.io/badge/YouTube-Video-red)](https://www.youtube.com/watch?v=lWoKlybEjeU)

---

## Demo

![archinstaller](https://github.com/user-attachments/assets/7a2d86b9-5869-4113-818e-50b3039d6685)

---

## Overview

Archinstaller transforms a fresh Arch Linux installation into a fully configured, optimized system through automated package installation, system configuration, security hardening, and performance optimization.

**Primary Features**

- Three installation modes: Standard, Minimal, and Custom
- Automatic desktop environment detection and optimization
- Optional gaming tools and performance enhancements
- Comprehensive security configuration
- Dual bootloader support with Windows integration
- Automatic GPU driver detection and installation
- Btrfs snapshot support with automatic configuration
- YAML-driven package management

---

## Installation Modes

### Standard Mode
Complete system setup with all recommended packages and tools. Includes productivity applications, media tools, development utilities, and desktop environment integration.

### Minimal Mode
Essential tools and core functionality only. Optimized for users who prefer a lightweight installation or plan to customize their system manually.

### Custom Mode
Interactive package selection through a graphical interface. Provides granular control over installed components with detailed package descriptions.

---

## Desktop Environment Support

The installer automatically detects and optimizes for the following desktop environments:

**KDE Plasma**
- Installs: KDE Connect, Spectacle, Okular, QBittorrent, Kvantum, Gwenview, KWallet Manager
- Removes: Redundant system monitor utilities
- Configures: Global shortcuts and KDE-specific integrations

**GNOME**
- Installs: GNOME Tweaks, Extension Manager, Transmission, Seahorse, dconf-editor
- Removes: Default bloatware (Epiphany, Contacts, Maps, Music, Tour, Totem, Snapshot)
- Configures: ADW GTK theme integration

**Cosmic**
- Installs: Cosmic Tweaks and power management tools
- Configures: Desktop-specific optimizations

**Generic Support**
- Works with any desktop environment or window manager
- Applies universal optimizations without DE-specific dependencies

---

## System Optimizations

### Performance
- Pacman parallel downloads and optimization
- Intelligent ZRAM configuration based on system RAM
- Automatic CPU microcode installation (Intel/AMD)
- Kernel headers for all installed kernels
- SSD optimization with automatic fstrim
- Mirror list optimization using rate-mirrors

### Security
- Fail2ban configuration for SSH protection
- Firewall setup (UFW or Firewalld) with intelligent defaults
- Automatic port configuration for installed services
- System service hardening

### Boot Configuration
- Plymouth boot screen installation and configuration
- Bootloader detection and optimization (GRUB/systemd-boot)
- Windows dual-boot support with automatic detection
- Quiet boot parameters and reduced timeout
- NTFS support for Windows partitions

### Btrfs Snapshots
- Automatic Btrfs detection and snapshot configuration
- Snapper integration with automatic timeline snapshots
- Pre/post package operation snapshots via snap-pac
- Bootloader integration for snapshot booting (GRUB)
- LTS kernel fallback for system recovery
- GUI management through btrfs-assistant
- Configurable retention policy (5 hourly, 7 daily)

### Graphics Drivers
- Automatic GPU detection (AMD/Intel/NVIDIA)
- Generation-specific NVIDIA driver selection
- Vulkan support with 32-bit libraries
- Virtual machine detection and guest utilities
- Hardware acceleration configuration

---

## Package Categories

### Core System Tools
System utilities, network tools, development packages, media applications, and essential fonts installed across all modes.

### Helper Utilities
Base development tools, shell enhancements, system services, and package managers installed during system preparation.

### Essential Applications
Mode-specific applications including productivity tools, media players, and system utilities.

### AUR Packages
Cloud storage, office suites, remote desktop software, media streaming, and specialized tools.

### Gaming Mode (Optional)
Discord, Steam, Lutris, MangoHud, OBS Studio, Wine, Heroic Games Launcher, and performance optimization tools.

---

## Shell Configuration

- ZSH as default shell with Oh-My-Zsh framework
- Starship prompt with system information
- Enhanced directory navigation with zoxide
- Fastfetch system information display
- Comprehensive aliases for system maintenance
- Git integration and fuzzy finding
- Syntax highlighting and autosuggestions

---

## Architecture

### Modular Design
```
install.sh                    Main orchestration script
scripts/common.sh             Shared functions and utilities
scripts/system_preparation.sh System updates and core packages
scripts/shell_setup.sh        ZSH and shell configuration
scripts/plymouth.sh           Boot screen setup
scripts/yay.sh               AUR helper installation
scripts/programs.sh          Application installation
scripts/gaming_mode.sh       Gaming tools and tweaks
scripts/bootloader_config.sh Bootloader configuration
scripts/fail2ban.sh          SSH security
scripts/system_services.sh   Services and GPU drivers
scripts/maintenance.sh       Cleanup, optimization, and snapshots
```

### Configuration Files
```
configs/programs.yaml       Package definitions and descriptions
configs/.zshrc             ZSH configuration and aliases
configs/starship.toml      Prompt configuration
configs/MangoHud.conf      Gaming overlay settings
configs/config.jsonc       Fastfetch configuration
configs/kglobalshortcutsrc KDE shortcuts
```

---

## Installation

### Prerequisites
- Fresh Arch Linux installation
- Active internet connection
- Regular user account with sudo privileges
- Minimum 2GB free disk space

### Quick Start
```bash
git clone https://github.com/gandromidas/archinstaller && cd archinstaller
chmod +x install.sh
./install.sh
```

### Installation Process
1. System requirements validation
2. Installation mode selection
3. Automated package installation (10-20 minutes)
4. Optional gaming mode setup
5. Bootloader and security configuration
6. Btrfs snapshot setup (if applicable)
7. System cleanup and reboot

---

## Customization

### Adding Packages
Edit `configs/programs.yaml` to modify package lists:

```yaml
essential:
  default:
    - name: "package-name"
      description: "Package description"
```

### Modifying Behavior
Each installation phase is isolated in `scripts/` directory. Modify individual scripts to customize behavior without affecting other components.

### Desktop Environment Extensions
Add desktop environment support by extending `programs.yaml` and updating detection logic in `programs.sh`.

---

## Technical Details

### Error Handling
- Non-critical errors do not halt installation
- Comprehensive error collection and reporting
- Detailed summary at completion
- Installer preservation on failure for debugging

### User Interface
- Gum-based terminal UI with fallback support
- Real-time progress tracking
- Color-coded status messages
- Step-by-step installation feedback

### Package Management
- YAML-driven configuration
- Multi-source support (Pacman, AUR, Flatpak)
- Desktop environment-specific package selection
- Automatic dependency resolution

---

## Important Notes

- Execute as regular user, not root
- Designed for fresh installations
- Internet connection required throughout installation
- Reboot recommended after completion
- Existing configurations preserved when possible
- Installer directory removed on successful completion

---

## Contributing

Contributions are welcome. To extend functionality:

1. Package additions: Update `configs/programs.yaml`
2. New features: Add modular scripts to `scripts/`
3. Desktop environments: Extend detection and package selection
4. Configuration files: Add to `configs/` directory

---

## License

Licensed under the terms specified in the LICENSE file.

---

**Automated Arch Linux system configuration and optimization.**